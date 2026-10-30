using System.Collections.Concurrent;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text.Json.Nodes;
using Microsoft.AspNetCore.TestHost;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Logging;
using NhomBar;

// Real SQL Server, HTTP pipeline, JWT and hashing. Only email delivery is captured.
var database = "NhomBarTests_" + Guid.NewGuid().ToString("N");
var capture = new CaptureMail();
var app = ApiHost.Build([], b =>
{
    b.Environment.EnvironmentName="Testing";
    b.Configuration.AddInMemoryCollection(new Dictionary<string, string?>
    {
        ["ConnectionStrings:SqlServer"] = $"Server=.;Database={database};Trusted_Connection=True;TrustServerCertificate=True;Encrypt=False",
        ["Jwt:Key"] = Convert.ToBase64String(RandomNumberGenerator.GetBytes(48)),
        ["Jwt:Issuer"] = "NhomBar",
        ["Jwt:Audience"] = "NhomBar.Mobile",
        ["Email:Brevo:ApiKey"] = "",
        ["Email:Brevo:SenderEmail"] = "",
        ["Push:Firebase:ServiceAccountJson"] = "",
        ["Push:Firebase:ServiceAccountPath"] = ""
    });
    b.WebHost.UseTestServer();
    b.Services.AddSingleton<ICodeSender>(capture);
    b.Logging.ClearProviders();
});
int passed = 0;
void Assert(bool ok, string name) { if (!ok) throw new Exception("FAIL: " + name); passed++; Console.WriteLine("PASS: " + name); }
async Task<JsonNode> Json(HttpResponseMessage response) { var content = await response.Content.ReadAsStringAsync(); if (!response.IsSuccessStatusCode) throw new Exception($"HTTP {(int)response.StatusCode}: {content}"); return JsonNode.Parse(content) ?? new JsonObject(); }
HttpClient Client(string? token = null) { var c = app.GetTestClient(); c.BaseAddress = new Uri("https://localhost"); if (token != null) c.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bearer", token); return c; }
const string password = "Hutech@123";
try
{
    using (var scope = app.Services.CreateScope())
    {
        var db = scope.ServiceProvider.GetRequiredService<AppDb>();
        await db.Database.MigrateAsync();
        var sec = scope.ServiceProvider.GetRequiredService<Security>();
        foreach (var (email, role) in new[] { ("bththuong05.c23xuantruong@gmail.com", "Admin"), ("buithihoaithuongdl@gmail.com", "Parent") })
        {
            var u = new User { Email = email, FullName = role, Role = role };
            u.PasswordHash = sec.PasswordHash(u, password);
            db.Users.Add(u);
            if (role == "Parent")
            {
                var f = new Family { CreatedBy = u.Id, FamilyName = "Kiểm thử" };
                db.Families.Add(f);
                db.FamilyMembers.Add(new FamilyMember { FamilyId = f.Id, UserId = u.Id });
            }
        }
        await db.SaveChangesAsync();
    }
    await app.StartAsync();
    var guest = Client();
    Assert((await guest.GetAsync("/health")).IsSuccessStatusCode, "SQL Server health");
    Assert((await guest.GetAsync("/api/children")).StatusCode == HttpStatusCode.Unauthorized, "Authentication required");
    Assert((await guest.PostAsJsonAsync("/api/auth/login", new
    {
        email = "buithihoaithuongdl@gmail.com",
        password = "wrong"
    })).StatusCode == HttpStatusCode.Unauthorized, "Wrong password rejected");
    async Task<JsonNode> Login(string email)
    {
        var challenge = await Json(await guest.PostAsJsonAsync("/api/auth/login", new
        {
            email,
            password
        }));
        Assert(challenge["accessToken"] == null, "No JWT before OTP");
        var wrong = await guest.PostAsJsonAsync("/api/auth/verify-otp", new
        {
            challengeId = (string)challenge["challengeId"]!,
            code = "not-a-code",
            purpose = "login"
        });
        Assert(wrong.StatusCode == HttpStatusCode.BadRequest, "Wrong OTP rejected");
        var body = new
        {
            challengeId = (string)challenge["challengeId"]!,
            code = capture.Codes[email],
            purpose = "login"
        };
        var tokens = await Json(await guest.PostAsJsonAsync("/api/auth/verify-otp", body));
        Assert((await guest.PostAsJsonAsync("/api/auth/verify-otp", body)).StatusCode == HttpStatusCode.BadRequest, "OTP cannot be reused");
        return tokens;
    }
    var pTokens = await Login("buithihoaithuongdl@gmail.com");
    var parent = Client((string)pTokens["accessToken"]!);
    var aTokens = await Login("bththuong05.c23xuantruong@gmail.com");
    var admin = Client((string)aTokens["accessToken"]!);
    Assert((await parent.GetAsync("/api/admin/summary")).StatusCode == HttpStatusCode.Forbidden, "Parent cannot use admin endpoints");
    Assert((await admin.GetAsync("/api/admin/summary")).IsSuccessStatusCode, "Admin summary");
    var families = await Json(await parent.GetAsync("/api/families"));
    var family = (string)families[0]!["id"]!;
    var child = await Json(await parent.PostAsJsonAsync($"/api/families/{family}/children", new
    {
        fullName = "Con kiểm thử",
        dateOfBirth = "2015-01-01"
    }));
    var childId = (string)child["id"]!;
    Assert(child["fullName"]!.ToString() == "Con kiểm thử", "Create child in SQL Server");
    Assert((await admin.GetAsync($"/api/children/{childId}/locations")).StatusCode == HttpStatusCode.Forbidden, "Admin cannot view child's location");
    Assert((await parent.PutAsJsonAsync("/api/parent-pin", new
    {
        pin = "123456"
    })).IsSuccessStatusCode, "Hash and save parent PIN");
    var rule = await Json(await parent.GetAsync($"/api/children/{childId}/rule"));
    var settings = new
    {
        dailyLimitMinutes = 60,
        startTime = "07:00:00",
        endTime = "21:00:00",
        strictMode = true,
        allowExtensionRequest = true,
        isEnabled = true,
        version = (long)rule["version"]!,
        pin = "123456"
    };
    Assert((await parent.PutAsJsonAsync($"/api/children/{childId}/rule", settings)).IsSuccessStatusCode, "Update time rule");
    Assert((await parent.PutAsJsonAsync($"/api/children/{childId}/rule", settings)).StatusCode == HttpStatusCode.Conflict, "Stale rule update rejected");
    var expiredPair=await Json(await parent.PostAsJsonAsync($"/api/children/{childId}/pairing",new{}));
    using(var scope=app.Services.CreateScope()){
        var db=scope.ServiceProvider.GetRequiredService<AppDb>();
        await db.PairingRequests.Where(x=>x.ChildId==Guid.Parse(childId)).ExecuteUpdateAsync(x=>x.SetProperty(p=>p.ExpiresAt,DateTimeOffset.UtcNow.AddMinutes(-1)));
    }
    Assert((await guest.PostAsJsonAsync("/api/enrollment/start",new{token=(string)expiredPair["token"]!,deviceName="Test",deviceModel="Test",androidVersion="16",installationId=Guid.NewGuid().ToString()})).StatusCode==HttpStatusCode.BadRequest,"Expired QR invitation cannot start enrollment");
    var rejectedPair=await Json(await parent.PostAsJsonAsync($"/api/children/{childId}/pairing",new{}));
    var rejected=await Json(await guest.PostAsJsonAsync("/api/enrollment/start",new{token=(string)rejectedPair["token"]!,deviceName="Test",deviceModel="Test",androidVersion="16",installationId=Guid.NewGuid().ToString()}));
    Assert((await guest.PostAsJsonAsync($"/api/enrollment/{rejected["id"]}/decision",new{approve=true})).StatusCode==HttpStatusCode.Unauthorized,"Anonymous scanner cannot approve its own enrollment");
    Assert((await parent.PostAsJsonAsync($"/api/enrollment/{rejected["id"]}/decision",new{approve=false})).IsSuccessStatusCode,"Parent can reject a QR enrollment");
    Assert((await guest.PostAsJsonAsync("/api/enrollment/session",new{id=(string)rejected["id"]!,secret=(string)rejected["secret"]!})).StatusCode==HttpStatusCode.BadRequest,"Rejected enrollment cannot obtain a Child session");
    var expiredClaimPair=await Json(await parent.PostAsJsonAsync($"/api/children/{childId}/pairing",new{}));
    var expiredClaim=await Json(await guest.PostAsJsonAsync("/api/enrollment/start",new{token=(string)expiredClaimPair["token"]!,deviceName="Test",deviceModel="Test",androidVersion="16",installationId=Guid.NewGuid().ToString()}));
    using(var scope=app.Services.CreateScope()){
        var db=scope.ServiceProvider.GetRequiredService<AppDb>();
        await db.DeviceEnrollments.Where(x=>x.Id==Guid.Parse((string)expiredClaim["id"]!)).ExecuteUpdateAsync(x=>x.SetProperty(e=>e.ExpiresAt,DateTimeOffset.UtcNow.AddMinutes(-1)));
    }
    var expiredStatus=await Json(await guest.PostAsJsonAsync("/api/enrollment/status",new{id=(string)expiredClaim["id"]!,secret=(string)expiredClaim["secret"]!}));
    Assert((string)expiredStatus["status"]! == "Expired","Pending enrollment reports expiration without issuing a session");
    Assert((await parent.PostAsJsonAsync($"/api/enrollment/{expiredClaim["id"]}/decision",new{approve=true})).StatusCode==HttpStatusCode.Conflict,"Parent cannot approve an expired enrollment");
    var pair=await Json(await parent.PostAsJsonAsync($"/api/children/{childId}/pairing",new{}));
    var pairBody=new{token=(string)pair["token"]!,deviceName="Android kiểm thử",deviceModel="Test",androidVersion="15",installationId=Guid.NewGuid().ToString()};
    var enrollment=await Json(await guest.PostAsJsonAsync("/api/enrollment/start",pairBody));
    Assert((await guest.PostAsJsonAsync("/api/enrollment/start",pairBody)).StatusCode==HttpStatusCode.BadRequest,"Pairing QR is single use before approval");
    var secretBody=new{id=(string)enrollment["id"]!,secret=(string)enrollment["secret"]!};
    Assert((await guest.PostAsJsonAsync("/api/enrollment/session",secretBody)).StatusCode==HttpStatusCode.BadRequest,"No Child session before parent approval");
    Assert((await guest.PostAsJsonAsync("/api/enrollment/status",new{id=(string)enrollment["id"]!,secret=new string('0',64)})).StatusCode==HttpStatusCode.NotFound,"Enrollment status requires the device claim secret");
    var pending=await Json(await parent.GetAsync($"/api/children/{childId}/pairing/pending"));
    Assert(pending.AsArray().Count==1&&pending[0]!["claimHash"]==null&&pending[0]!["secret"]==null,"Parent sees confirmation code and device, not claim secrets");
    Assert((await parent.PostAsJsonAsync($"/api/enrollment/{enrollment["id"]}/decision",new{approve=true})).IsSuccessStatusCode,"Parent approves QR enrollment without child email");
    var claimed=await Json(await guest.PostAsJsonAsync("/api/enrollment/session",secretBody));
    var cTokens=claimed["session"]!;
    var childClient=Client((string)cTokens["accessToken"]!);
    var deviceId=(string)claimed["device"]!["id"]!;
    Assert((string)cTokens["user"]!["role"]! == "Child" && cTokens["user"]!["email"]==null,"QR issues Child device session without email/password");
    Assert((await guest.PostAsJsonAsync("/api/enrollment/session",secretBody)).StatusCode==HttpStatusCode.BadRequest,"Device session claim cannot be replayed");
    Assert((await childClient.PutAsJsonAsync($"/api/children/{childId}/rule",settings)).StatusCode==HttpStatusCode.Forbidden,"Child cannot change time rule");
    Assert((await childClient.GetAsync($"/api/devices/{Guid.NewGuid()}/policy")).StatusCode==HttpStatusCode.Forbidden,"Child session is bound to its own device");
    var editedProfile=new{fullName="Con đã cập nhật",nickname="Nấm nhỏ",dateOfBirth="2016-11-01"};
    Assert((await parent.PutAsJsonAsync($"/api/children/{childId}",editedProfile)).IsSuccessStatusCode,"Parent edits the existing linked child profile");
    var syncedProfile=await Json(await childClient.GetAsync($"/api/children/{childId}"));
    Assert((string)syncedProfile["id"]! == childId && (string)syncedProfile["nickname"]! == "Nấm nhỏ" && (string)syncedProfile["dateOfBirth"]! == "2016-11-01","Child reads updated nickname and birth date without signing in again");
    var preservedDevices=await Json(await parent.GetAsync($"/api/children/{childId}/devices"));
    Assert(preservedDevices.AsArray().Count==1 && (string)preservedDevices[0]!["id"]! == deviceId,"Editing profile preserves the linked device identifier");
    Assert((await childClient.PutAsJsonAsync($"/api/children/{childId}",editedProfile)).StatusCode==HttpStatusCode.Forbidden,"Child cannot edit parent-managed profile");
    Assert((await childClient.PutAsJsonAsync("/api/users/me",new{fullName="Con tự đổi"})).StatusCode==HttpStatusCode.Forbidden,"Child cannot bypass parent profile ownership through users/me");
    Assert((await parent.PutAsJsonAsync($"/api/children/{childId}",new{fullName="Con",dateOfBirth=DateOnly.FromDateTime(DateTime.UtcNow.AddDays(2))})).StatusCode==HttpStatusCode.BadRequest,"Future child birth date is rejected");
    Assert((await parent.PutAsJsonAsync($"/api/children/{childId}",new{fullName="Con",dateOfBirth="2016-11-01",avatarBase64=Convert.ToBase64String(new byte[]{1,2,3})})).StatusCode==HttpStatusCode.BadRequest,"Invalid image bytes are rejected before storing an avatar");
    var extension = await Json(await childClient.PostAsJsonAsync($"/api/children/{childId}/extensions", new
    {
        requestedMinutes = 15,
        reason = "Làm bài tập"
    }));
    var requestId = (string)extension["id"]!;
    Assert(extension["status"]!.ToString() == "Pending", "Extension is not automatically approved");
    Assert((await childClient.PostAsJsonAsync($"/api/extensions/{requestId}/decision", new
    {
        approve = true,
        pin = "123456"
    })).StatusCode == HttpStatusCode.Forbidden, "Child cannot approve own extension");
    Assert((await parent.PostAsJsonAsync($"/api/extensions/{requestId}/decision", new
    {
        approve = true,
        pin = "000000"
    })).StatusCode == HttpStatusCode.BadRequest, "Incorrect parent PIN rejected");
    Assert((await parent.PostAsJsonAsync($"/api/extensions/{requestId}/decision", new
    {
        approve = true,
        pin = "123456",
        response = "Con làm xong bài nhé"
    })).IsSuccessStatusCode, "Parent approves extension");
    Assert((await parent.PostAsJsonAsync($"/api/extensions/{requestId}/decision", new
    {
        approve = true,
        pin = "123456"
    })).StatusCode == HttpStatusCode.Conflict, "Approval replay rejected");
    var now = DateTimeOffset.UtcNow.AddMinutes(-1);
    var records = new[] { new { packageName = "vn.test.study", appName = "Học tập", startedAt = now.AddSeconds(-30), endedAt = now, durationSeconds = 30 } };
    Assert((await childClient.PostAsJsonAsync($"/api/devices/{deviceId}/usage", records)).IsSuccessStatusCode, "Usage saved to SQL Server");
    Assert((await childClient.PostAsJsonAsync($"/api/devices/{deviceId}/usage", records)).IsSuccessStatusCode, "Usage retry accepted without duplication");
    var policy = await Json(await childClient.GetAsync($"/api/devices/{deviceId}/policy"));
    Assert((int)policy["usedSeconds"]! == 30 && (int)policy["extraMinutes"]! == 15, "Usage deduplication and approved time policy");
    var recovery = await Json(await parent.PostAsJsonAsync($"/api/devices/{deviceId}/recovery", new
    {
        pin = "123456",
        version = 0
    }));
    var recoveryCode = (string)recovery["code"]!;
    policy = await Json(await childClient.GetAsync($"/api/devices/{deviceId}/policy"));
    Assert(recoveryCode.Length == 20 && (string)policy["recovery"]!["hash"]! == Security.Hash(recoveryCode), "Only recovery verifier is delivered to child");
    Assert(!policy.ToJsonString().Contains(recoveryCode), "Raw offline unlock code is not exposed to child");
    Assert((await childClient.PostAsJsonAsync($"/api/devices/{deviceId}/recovery-used", new
    {
        hash = Security.Hash(recoveryCode)
    })).IsSuccessStatusCode, "Offline recovery receipt is recorded");
    Assert((await childClient.PostAsJsonAsync($"/api/devices/{deviceId}/recovery-used", new
    {
        hash = Security.Hash(recoveryCode)
    })).StatusCode == HttpStatusCode.Conflict, "Offline recovery receipt cannot be reused");
    var parentUnlock = new
    {
        email = "buithihoaithuongdl@gmail.com",
        pin = "123456",
        version = (long)policy["state"]!["policyVersion"]!
    };
    Assert((await childClient.PostAsJsonAsync($"/api/devices/{deviceId}/parent-unlock", parentUnlock)).IsSuccessStatusCode, "Parent PIN unlock at child phone");
    Assert((await childClient.PostAsJsonAsync($"/api/devices/{deviceId}/parent-unlock", parentUnlock)).StatusCode == HttpStatusCode.Conflict, "Parent PIN unlock replay rejected");
    Assert((await childClient.PostAsJsonAsync($"/api/devices/{deviceId}/locations", new
    {
        latitude = 10.8,
        longitude = 106.7,
        accuracy = 10,
        recordedAt = DateTimeOffset.UtcNow
    })).IsSuccessStatusCode, "Store real-format location report");
    var locations = await Json(await parent.GetAsync($"/api/children/{childId}/locations"));
    Assert(locations.AsArray().Count == 1, "Family can read location history");
    var place = await Json(await parent.PostAsJsonAsync($"/api/children/{childId}/safe-places", new
    {
        placeName = "Trường",
        latitude = 10.8,
        longitude = 106.7,
        radiusMeters = 200
    }));
    Assert((await parent.DeleteAsync($"/api/safe-places/{(string)place["id"]!}")).IsSuccessStatusCode, "Delete safe place");
    Assert((await childClient.PostAsJsonAsync($"/api/children/{childId}/noise", new
    {
        averageLevel = 60,
        maximumLevel = 70,
        recordedAt = DateTimeOffset.UtcNow
    })).IsSuccessStatusCode, "Save noise report");
    // Separate family is created via service fixture; no production bypass endpoint exists.
    string otherToken;
    using (var scope = app.Services.CreateScope())
    {
        var db = scope.ServiceProvider.GetRequiredService<AppDb>();
        var s = scope.ServiceProvider.GetRequiredService<Security>();
        var u = new User { Email = "other@example.com", FullName = "Other", Role = "Parent" };
        u.PasswordHash = s.PasswordHash(u, password);
        db.Users.Add(u);
        await db.SaveChangesAsync();
        otherToken = (string)JsonNode.Parse(System.Text.Json.JsonSerializer.Serialize(await s.Tokens(u)))!["accessToken"]!;
    }
    Assert((await Client(otherToken).GetAsync($"/api/children/{childId}/usage")).StatusCode == HttpStatusCode.Forbidden, "Different family cannot read child data");
    Assert((await parent.PutAsJsonAsync("/api/users/me", new
    {
        fullName = "Phụ huynh",
        phoneNumber = "+84901234567",
        smsAlertsEnabled = true
    })).StatusCode == HttpStatusCode.ServiceUnavailable, "Unavailable SMS service is explained without enabling it");
    Assert((await childClient.PutAsJsonAsync($"/api/children/{childId}/apps/category",new{packageName="vn.test.study",category="Study"})).StatusCode==HttpStatusCode.Forbidden,"Child cannot change parent's app classification");
    Assert((await parent.PutAsJsonAsync($"/api/children/{childId}/apps/category",new{packageName="vn.test.study",category="Study"})).IsSuccessStatusCode,"Parent classifies an app for the family");
    var classified=await Json(await parent.GetAsync($"/api/children/{childId}/usage"));Assert((string)classified["apps"]![0]!["category"]! =="Study","Report uses persisted app classification");
    Assert((await parent.PutAsJsonAsync("/api/users/me",new{fullName="Phụ huynh",emailReportsEnabled=true})).IsSuccessStatusCode,"Parent opts into daily email reports");
    using(var scope=app.Services.CreateScope()){var db=scope.ServiceProvider.GetRequiredService<AppDb>();await DailyReports.Queue(db,Check.Today);await DailyReports.Queue(db,Check.Today);Assert(await db.Notifications.CountAsync(x=>x.Type=="DailyReport"&&x.ReportDate==Check.Today)==1,"Daily report queue is idempotent");Assert(await db.Notifications.AnyAsync(x=>x.Type=="DailyReport"&&x.EmailState=="Pending"&&x.Content.Contains("Con đã cập nhật")),"Daily email uses updated family profiles and waits for delivery");}
    var dashboard = await Json(await parent.GetAsync("/api/dashboard"));
    Assert(dashboard.AsArray().Count == 1 && (bool)dashboard[0]!["hasReport"]!, "Dashboard uses persisted reports");
    var spec = await Json(await admin.GetAsync("/swagger/v1/swagger.json"));
    Assert(spec["paths"]!.AsObject().Count > 40, "Swagger exposes documented endpoints");
    var registered = await Json(await guest.PostAsJsonAsync("/api/auth/register", new
    {
        fullName = "Đăng ký kiểm thử",
        email = "register@example.com",
        password
    }));
    Assert(registered["accessToken"] == null, "Registration requires email verification");
    var newTokens = await Json(await guest.PostAsJsonAsync("/api/auth/verify-otp", new
    {
        challengeId = (string)registered["challengeId"]!,
        code = capture.Codes["register@example.com"],
        purpose = "register"
    }));
    Assert((string)newTokens["user"]!["role"]! == "Parent", "Public registration creates a parent account only");
    var profileClient = Client((string)newTokens["accessToken"]!);
    const string profilePhoto = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=";
    var savedProfile = await Json(await profileClient.PutAsJsonAsync("/api/users/me", new
    {
        fullName = "Hồ sơ đã cập nhật", phoneNumber = "+84901234567", avatarBase64 = profilePhoto,
        role = "Admin", email = "changed@example.com", id = (string)pTokens["user"]!["id"]!
    }));
    Assert((string)savedProfile["fullName"]! == "Hồ sơ đã cập nhật" && (string)savedProfile["avatarBytes"]! == profilePhoto, "Own profile name and avatar saved in SQL Server");
    Assert((string)savedProfile["role"]! == "Parent" && (string)savedProfile["email"]! == "register@example.com" && (string)savedProfile["id"]! == (string)newTokens["user"]!["id"]!, "Profile ignores supplied role, email and another user id");
    var readProfile = await Json(await profileClient.GetAsync("/api/users/me"));
    Assert((string)readProfile["avatarBytes"]! == profilePhoto, "Avatar survives a separate profile read");
    Assert((await profileClient.PutAsJsonAsync("/api/users/me", new { fullName = " ", phoneNumber = "+84901234567" })).StatusCode == HttpStatusCode.BadRequest, "Blank profile name rejected");
    Assert((await profileClient.PutAsJsonAsync("/api/users/me", new { fullName = "Tên", avatarBase64 = "invalid-image" })).StatusCode == HttpStatusCode.BadRequest, "Invalid avatar rejected");
    Assert((await profileClient.PutAsJsonAsync("/api/users/me", new { fullName = "Tên", phoneNumber = "123" })).StatusCode == HttpStatusCode.BadRequest, "Invalid contact number rejected");
    var removedPhoto = await Json(await profileClient.PutAsJsonAsync("/api/users/me", new { fullName = "Hồ sơ đã cập nhật", removeAvatar = true }));
    Assert(removedPhoto["avatarBytes"] == null, "Own avatar can be removed");
    var oldSession = newTokens;
    using (var scope = app.Services.CreateScope())
    {
        var db = scope.ServiceProvider.GetRequiredService<AppDb>();
        var userId = Guid.Parse((string)newTokens["user"]!["id"]!);
        foreach (var challenge in await db.EmailOtpChallenges.Where(x => x.UserId == userId).ToListAsync())
            challenge.CreatedAt = DateTimeOffset.UtcNow.AddMinutes(-2);
        await db.SaveChangesAsync();
    }
    var originalGuest = guest;
    guest = new HttpClient(app.GetTestServer().CreateHandler(ctx => ctx.Connection.RemoteIpAddress = IPAddress.Parse("127.0.0.3"))) { BaseAddress = new Uri("https://localhost") };
    newTokens = await Login("register@example.com");
    Assert((await profileClient.GetAsync("/api/users/me")).StatusCode == HttpStatusCode.Unauthorized, "New OTP login invalidates previous device access token");
    Assert((await guest.PostAsJsonAsync("/api/auth/refresh", new { refreshToken = (string)oldSession["refreshToken"]! })).StatusCode == HttpStatusCode.Unauthorized, "Previous device cannot resume through refresh after new OTP login");
    guest.Dispose();
    guest = originalGuest;
    using (var scope = app.Services.CreateScope())
    {
        var db = scope.ServiceProvider.GetRequiredService<AppDb>();
        foreach (var challenge in await db.EmailOtpChallenges.Where(x => x.UserId == Guid.Parse((string)newTokens["user"]!["id"]!)).ToListAsync())
            challenge.CreatedAt = DateTimeOffset.UtcNow.AddMinutes(-2);
        await db.SaveChangesAsync();
    }
    var forgot = await Json(await guest.PostAsJsonAsync("/api/auth/forgot-password", new
    {
        email = "register@example.com"
    }));
    Assert((await guest.PostAsJsonAsync("/api/auth/reset-password", new
    {
        challengeId = (string)forgot["challengeId"]!,
        code = capture.Codes["register@example.com"],
        password = "Changed@123"
    })).IsSuccessStatusCode, "Reset password requires a fresh email code");
    Assert((await guest.PostAsJsonAsync("/api/auth/refresh", new
    {
        refreshToken = (string)newTokens["refreshToken"]!
    })).StatusCode == HttpStatusCode.Unauthorized, "Password reset revokes existing refresh tokens");
    Assert((await Client((string)newTokens["accessToken"]!).GetAsync("/api/users/me")).StatusCode == HttpStatusCode.Unauthorized, "Password reset revokes existing JWTs");
    using (var scope = app.Services.CreateScope())
    {
        var db = scope.ServiceProvider.GetRequiredService<AppDb>();
        Assert(await db.Users.AllAsync(x => x.PasswordHash != password) && await db.RefreshTokens.AllAsync(x => x.TokenHash.Length == 64), "Passwords and refresh tokens are stored as hashes");
    }
    var refreshed = await Json(await guest.PostAsJsonAsync("/api/auth/refresh", new
    {
        refreshToken = (string)pTokens["refreshToken"]!
    }));
    Assert((await guest.PostAsJsonAsync("/api/auth/refresh", new
    {
        refreshToken = (string)pTokens["refreshToken"]!
    })).StatusCode == HttpStatusCode.Unauthorized, "Refresh token rotation and replay rejection");
    var freshParent = Client((string)refreshed["accessToken"]!);
    Assert((await freshParent.PostAsJsonAsync("/api/auth/logout", new
    {
    })).IsSuccessStatusCode, "Logout");
    Assert((await freshParent.GetAsync("/api/users/me")).StatusCode == HttpStatusCode.Unauthorized, "JWT revoked after logout");
    Assert((await guest.PostAsJsonAsync("/api/auth/refresh", new
    {
        refreshToken = (string)refreshed["refreshToken"]!
    })).StatusCode == HttpStatusCode.Unauthorized, "Refresh invalidated after logout");
    // Separate simulated client IP for this group; retain the production 30/minute limit.
    guest.Dispose();
    guest=new HttpClient(app.GetTestServer().CreateHandler(ctx=>ctx.Connection.RemoteIpAddress=IPAddress.Parse("127.0.0.2"))){BaseAddress=new Uri("https://localhost")};
    var otpCheck=await Json(await guest.PostAsJsonAsync("/api/auth/register",new {fullName="OTP limits",email="otp-limits@example.com",password}));
    var otpId=Guid.Parse((string)otpCheck["challengeId"]!);
    Assert((string)otpCheck["deliveryStatus"]! == "accepted" && DateTimeOffset.Parse((string)otpCheck["expiresAt"]!)>DateTimeOffset.UtcNow.AddMinutes(4),"Accepted submission has a five-minute challenge, no delivery promise");
    using(var scope=app.Services.CreateScope()) {var db=scope.ServiceProvider.GetRequiredService<AppDb>();var row=await db.EmailOtpChallenges.FindAsync(otpId);Assert(row!.OtpHash.Length==64 && row.OtpHash!=Security.Hash(row.Id+":"+capture.Codes["otp-limits@example.com"]),"OTP stored as keyed hash rather than clear code or unkeyed six-digit digest");}
    Assert((await guest.PostAsJsonAsync("/api/auth/resend-otp",new{challengeId=otpId,code="",purpose="register"})).StatusCode==HttpStatusCode.TooManyRequests,"Resend within 60 seconds rejected");
    var wrongOtp=capture.Codes["otp-limits@example.com"]=="000000"?"111111":"000000";
    var failures=new List<HttpStatusCode>();for(var i=0;i<5;i++)failures.Add((await guest.PostAsJsonAsync("/api/auth/verify-otp",new{challengeId=otpId,code=wrongOtp,purpose="register"})).StatusCode);
    Assert(failures.All(s=>s==HttpStatusCode.BadRequest) && (await guest.PostAsJsonAsync("/api/auth/verify-otp",new{challengeId=otpId,code=capture.Codes["otp-limits@example.com"],purpose="register"})).StatusCode==HttpStatusCode.BadRequest,"Five failed attempts block even a subsequent correct code");
    using(var scope=app.Services.CreateScope()){var db=scope.ServiceProvider.GetRequiredService<AppDb>();(await db.EmailOtpChallenges.FindAsync(otpId))!.CreatedAt=DateTimeOffset.UtcNow.AddSeconds(-61);await db.SaveChangesAsync();}
    var replacement=await Json(await guest.PostAsJsonAsync("/api/auth/resend-otp",new{challengeId=otpId,code="",purpose="register"}));
    Assert((string)replacement["challengeId"]! != otpId.ToString() && (await guest.PostAsJsonAsync("/api/auth/verify-otp",new{challengeId=otpId,code=capture.Codes["otp-limits@example.com"],purpose="register"})).StatusCode==HttpStatusCode.BadRequest,"Resend after cooldown creates fresh challenge and invalidates old code");
    using(var scope=app.Services.CreateScope()){var db=scope.ServiceProvider.GetRequiredService<AppDb>();(await db.EmailOtpChallenges.FindAsync(Guid.Parse((string)replacement["challengeId"]!)))!.ExpiresAt=DateTimeOffset.UtcNow.AddSeconds(-1);await db.SaveChangesAsync();}
    Assert((await guest.PostAsJsonAsync("/api/auth/verify-otp",new{challengeId=(string)replacement["challengeId"]!,code=capture.Codes["otp-limits@example.com"],purpose="register"})).StatusCode==HttpStatusCode.BadRequest,"Expired challenge rejected");
    capture.FailNext=true;
    Assert((await guest.PostAsJsonAsync("/api/auth/register",new{fullName="Send failure",email="send-failure@example.com",password})).StatusCode==HttpStatusCode.ServiceUnavailable,"Provider failure never reports OTP sent");
    using(var scope=app.Services.CreateScope()){var db=scope.ServiceProvider.GetRequiredService<AppDb>();Assert(!await db.Users.AnyAsync(u=>u.Email=="send-failure@example.com"),"Provider failure rolls back registration and challenge");}
    Console.WriteLine($"Completed: {passed} checks passed. Real provider delivery and Android hardware are not covered.");
}
finally
{
    using var scope = app.Services.CreateScope();
    var db = scope.ServiceProvider.GetRequiredService<AppDb>();
    if (db.Database.GetDbConnection().Database == database && database.StartsWith("NhomBarTests_"))
        await db.Database.EnsureDeletedAsync();
    await app.DisposeAsync();
}
sealed class CaptureMail : ICodeSender
{
    public bool FailNext {get;set;}
    public ConcurrentDictionary<string, string> Codes { get; } = new(); public Task Send(string email, string code)
    {
        if(FailNext){FailNext=false;throw new AppError(503,"Chưa gửi được email. Vui lòng thử lại sau.");}
        Codes[email] = code;
        return Task.CompletedTask;
    }
}
