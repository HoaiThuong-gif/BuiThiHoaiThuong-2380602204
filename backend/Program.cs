using Microsoft.EntityFrameworkCore;
using NhomBar;

var app = ApiHost.Build(args);

// Chỉ cập nhật cấu trúc SQL Server khi người vận hành truyền --migrate.
if (args.Contains("--migrate"))
{
    using var scope = app.Services.CreateScope();
    var database = scope.ServiceProvider.GetRequiredService<AppDb>();
    await database.Database.MigrateAsync();
    return;
}

if (args.Contains("--seed"))
{
    using var scope = app.Services.CreateScope();
    var db = scope.ServiceProvider.GetRequiredService<AppDb>();
    var security = scope.ServiceProvider.GetRequiredService<Security>();
    foreach (var role in new[] { "Admin", "Parent" })
    {
        var email = app.Configuration[$"Seed:{role}Email"];
        var password = app.Configuration["Seed:Password"];
        if (string.IsNullOrWhiteSpace(email) || string.IsNullOrWhiteSpace(password))
            throw new InvalidOperationException("Set Seed__AdminEmail, Seed__ParentEmail and Seed__Password.");
        email = Check.Email(email);
        Check.Password(password);
        if (await db.Users.AnyAsync(x => x.Email == email))
            continue;
        // Giữ tài khoản đã có; chỉ tạo tài khoản còn thiếu từ cấu hình riêng.
        var user = new User
        {
            Email = email,
            FullName = role == "Admin" ? "Quản trị NhomBar" : "Phụ huynh",
            Role = role
        };
        user.PasswordHash = security.PasswordHash(user, password);
        db.Users.Add(user);
        if (role == "Parent")
        {
            var family = new Family { CreatedBy = user.Id, FamilyName = "Gia đình của tôi" };
            db.Families.Add(family);
            db.FamilyMembers.Add(new FamilyMember { FamilyId = family.Id, UserId = user.Id });
        }
    }
    await db.SaveChangesAsync();
    return;
}

app.Run();
