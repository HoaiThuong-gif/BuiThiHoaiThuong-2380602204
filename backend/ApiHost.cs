using System.Security.Claims;
using System.Text;
using System.Threading.RateLimiting;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;
using Microsoft.OpenApi.Models;
using NhomBar;


namespace NhomBar;

public static class ApiHost
{
    public static WebApplication Build(string[] args, Action<WebApplicationBuilder>? customize = null)
    {
        var builder = WebApplication.CreateBuilder(args);
        if (!builder.Environment.IsProduction())
            builder.Configuration.AddJsonFile("appsettings.local.json", optional: true, reloadOnChange: true);
        builder.Configuration.AddEnvironmentVariables();
        customize?.Invoke(builder);
        if (builder.Environment.IsProduction())
            ProductionConfiguration.Validate(builder.Configuration);
        var origins = builder.Configuration.GetSection("Cors:Origins").Get<string[]>() ?? [];
        builder.Services.AddCors(options => options.AddDefaultPolicy(policy => { if (origins.Length > 0) policy.WithOrigins(origins).WithHeaders("Authorization", "Content-Type").WithMethods("GET", "POST", "PUT", "DELETE"); }));
        builder.WebHost.ConfigureKestrel(server => server.Limits.MaxRequestBodySize = 1024 * 1024);
        var key = builder.Configuration["Jwt:Key"];
        if (string.IsNullOrWhiteSpace(key) || Encoding.UTF8.GetByteCount(key) < 32)
            throw new InvalidOperationException("Set Jwt__Key to a random secret of at least 32 bytes.");
        // AppDb được tạo riêng cho mỗi yêu cầu và kết nối SQL Server bằng cấu hình.
        builder.Services.AddDbContext<AppDb>(o => o.UseSqlServer(builder.Configuration.GetConnectionString("SqlServer") ?? throw new InvalidOperationException("Set ConnectionStrings__SqlServer.")));
        builder.Services.AddHttpContextAccessor();
        builder.Services.AddScoped<Security>();
        builder.Services.AddScoped<Access>();
        builder.Services.AddSingleton<PushTokenProtection>();
        builder.Services.AddHttpClient("firebase", http => http.Timeout = TimeSpan.FromSeconds(20)).RedactLoggedHeaders(["Authorization"]);
        builder.Services.AddSingleton<IPushTransport>(sp => new FirebasePush(sp.GetRequiredService<IHttpClientFactory>().CreateClient("firebase"), sp.GetRequiredService<IConfiguration>()));
        builder.Services.AddHostedService<PushDelivery>();
        builder.Services.AddHttpClient<BrevoEmail>(http => http.Timeout = TimeSpan.FromSeconds(20)).RedactLoggedHeaders(["api-key"]);
        Microsoft.Extensions.DependencyInjection.Extensions.ServiceCollectionDescriptorExtensions.TryAddScoped<ICodeSender>(builder.Services, sp => sp.GetRequiredService<BrevoEmail>());
        builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme).AddJwtBearer(o =>
        {
            o.TokenValidationParameters = new TokenValidationParameters { ValidateIssuer = true, ValidIssuer = builder.Configuration["Jwt:Issuer"], ValidateAudience = true, ValidAudience = builder.Configuration["Jwt:Audience"], ValidateLifetime = true, ValidateIssuerSigningKey = true, IssuerSigningKey = new SymmetricSecurityKey(Encoding.UTF8.GetBytes(key)), ClockSkew = TimeSpan.FromSeconds(15) };
            o.Events = new JwtBearerEvents { OnTokenValidated = async c => { var db = c.HttpContext.RequestServices.GetRequiredService<AppDb>(); if (!Guid.TryParse(c.Principal?.FindFirstValue(ClaimTypes.NameIdentifier), out var id)) { c.Fail("Invalid session"); return; } var u = await db.Users.FindAsync(id); if (u == null || !u.Active || u.SecurityStamp != c.Principal?.FindFirstValue("stamp")) c.Fail("Session ended"); if (u?.Role == "Child" && (!Guid.TryParse(c.Principal?.FindFirstValue("device"), out var deviceId) || !await db.Devices.AnyAsync(d => d.Id == deviceId && d.Linked && db.Children.Any(ch => ch.Id == d.ChildId && ch.UserId == u.Id)))) c.Fail("Device unlinked"); } };
        });
        builder.Services.AddScoped<INoticeEmail>(sp => sp.GetRequiredService<BrevoEmail>());
        builder.Services.AddHostedService<SmsDelivery>();
        builder.Services.AddHostedService<EmailDelivery>();
        builder.Services.AddAuthorization();
        builder.Services.AddEndpointsApiExplorer();
        builder.Services.AddSwaggerGen(o =>
        {
            o.SwaggerDoc("v1", new OpenApiInfo { Title = "NhomBar API", Version = "v1", Description = "Quản lý điện thoại gia đình. Đăng nhập và xác nhận email trước khi dùng các chức năng." });
            o.AddSecurityDefinition("Bearer", new OpenApiSecurityScheme { Type = SecuritySchemeType.Http, Scheme = "bearer", BearerFormat = "JWT" });
            o.AddSecurityRequirement(new OpenApiSecurityRequirement { { new OpenApiSecurityScheme { Reference = new OpenApiReference { Type = ReferenceType.SecurityScheme, Id = "Bearer" } }, Array.Empty<string>() } });
        });
        builder.Services.AddRateLimiter(o =>
        {
            o.RejectionStatusCode = 429;
            o.AddPolicy("auth", ctx => RateLimitPartition.GetFixedWindowLimiter(ctx.Connection.RemoteIpAddress?.ToString() ?? "unknown", _ => new FixedWindowRateLimiterOptions { PermitLimit = 30, Window = TimeSpan.FromMinutes(1) }));
            o.AddPolicy("enrollment", ctx => RateLimitPartition.GetFixedWindowLimiter(ctx.Connection.RemoteIpAddress?.ToString() ?? "unknown", _ => new FixedWindowRateLimiterOptions { PermitLimit = 60, Window = TimeSpan.FromMinutes(1) }));
            o.AddPolicy("safety", ctx => RateLimitPartition.GetFixedWindowLimiter(ctx.User.FindFirstValue(ClaimTypes.NameIdentifier) ?? "unknown", _ => new FixedWindowRateLimiterOptions { PermitLimit = 3, Window = TimeSpan.FromMinutes(1) }));
        });
        var app = builder.Build();
        app.Use(async (ctx, next) => { try { await next(); } catch (AppError e) { ctx.Response.StatusCode = e.Status; await ctx.Response.WriteAsJsonAsync(new { message = e.Message }); } catch (DbUpdateConcurrencyException) { ctx.Response.StatusCode = 409; await ctx.Response.WriteAsJsonAsync(new { message = "Thông tin vừa thay đổi. Vui lòng tải lại." }); } catch (DbUpdateException e) { app.Logger.LogError(e, "Database update failed"); ctx.Response.StatusCode = 409; await ctx.Response.WriteAsJsonAsync(new { message = "Chưa thể lưu thay đổi. Vui lòng tải lại và thử lại." }); } catch (Exception e) { app.Logger.LogError(e, "Request failed"); ctx.Response.StatusCode = 503; await ctx.Response.WriteAsJsonAsync(new { message = "Hiện chưa thể thực hiện. Vui lòng thử lại sau." }); } });
        if (!app.Environment.IsDevelopment())
        {
            app.UseHsts();
            app.UseHttpsRedirection();
        }
        app.UseCors();
        app.UseAuthentication();
        app.UseAuthorization();
        app.UseRateLimiter();
        app.Use(async (ctx, next) => { if (!app.Environment.IsDevelopment() && ctx.Request.Path.StartsWithSegments("/swagger") && !ctx.User.IsInRole("Admin")) { ctx.Response.StatusCode = 401; return; } await next(); });
        app.UseSwagger();
        app.UseSwaggerUI();
        app.MapGet("/health", async (AppDb db) => await db.Database.CanConnectAsync() ? Results.Ok(new { status = "ready" }) : Results.StatusCode(503));
        app.MapAuth();
        app.MapFamily();
        app.MapCategories();
        app.MapEnrollment();
        app.MapPush();
        app.MapDeploymentHealth();

        return app;
    }
}
