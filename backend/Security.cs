using System.IdentityModel.Tokens.Jwt;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using Microsoft.EntityFrameworkCore.Storage;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using Microsoft.IdentityModel.Tokens;

namespace NhomBar;

public sealed class AppError(int status, string message) : Exception(message)
{
    public int Status { get; } = status;
}
public static class Check
{
    public static void That(bool ok, string message, int status = 400)
    {
        if (!ok)
            throw new AppError(status, message);
    }
    public static string Text(string? value, int max = 200)
    {
        var s = value?.Trim() ?? "";
        That(s.Length > 0 && s.Length <= max, $"Vui lòng nhập từ 1 đến {max} ký tự.");
        return s;
    }
    public static string Email(string value)
    {
        var s = Text(value, 254).ToLowerInvariant();
        That(System.Net.Mail.MailAddress.TryCreate(s, out var a) && a.Address == s && s.Split('@').Last().Contains('.'), "Vui lòng nhập đúng địa chỉ email.");
        return s;
    }
    public static void Password(string value) => That(value.Length is >= 10 and <= 128 && value.Any(char.IsUpper) && value.Any(char.IsLower) && value.Any(char.IsDigit) && value.Any(c => !char.IsLetterOrDigit(c)), "Mật khẩu cần ít nhất 10 ký tự, gồm chữ hoa, chữ thường, số và ký tự đặc biệt.");
    public static DateOnly Today => DateOnly.FromDateTime(DateTime.UtcNow.AddHours(7));
    public static void Coordinates(double lat, double lon) => That(double.IsFinite(lat) && double.IsFinite(lon) && lat is >= -90 and <= 90 && lon is >= -180 and <= 180, "Vị trí không hợp lệ.");
}
public interface ICodeSender
{
    Task Send(string email, string code);
}
public class Security(AppDb db, IConfiguration config, ICodeSender sender)
{
    private readonly PasswordHasher<User> passwords = new();
    public static string Hash(string value) => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(value)));
    public static string RandomToken() => Convert.ToHexString(RandomNumberGenerator.GetBytes(32));
    public string PasswordHash(User user, string value) => passwords.HashPassword(user, value);
    public bool PasswordOk(User user, string value) => passwords.VerifyHashedPassword(user, user.PasswordHash, value) != PasswordVerificationResult.Failed;
    public static object Profile(User u) => new { u.Id, u.FullName, email = u.Role == "Child" ? null : u.Email, u.Role, u.PhoneNumber, u.EmailVerified, u.Active, u.SmsAlertsEnabled, u.EmailReportsEnabled };
    public async Task<object> Tokens(User user, Guid? deviceId = null)
    {
        var now = DateTimeOffset.UtcNow;
        var refresh = RandomToken();
        Check.That(user.Role != "Child" || deviceId != null, "Hãy quét mã để kết nối với bố mẹ.", 403);
        db.RefreshTokens.Add(new RefreshToken { UserId = user.Id, DeviceId = deviceId, TokenHash = Hash(refresh), ExpiresAt = now.AddDays(14) });
        var claims = new List<Claim> { new(ClaimTypes.NameIdentifier, user.Id.ToString()), new(ClaimTypes.Role, user.Role), new("stamp", user.SecurityStamp), new(JwtRegisteredClaimNames.Jti, Guid.NewGuid().ToString()) };
        if (deviceId != null)
            claims.Add(new Claim("device", deviceId.ToString()!));
        var jwt = new JwtSecurityToken(config["Jwt:Issuer"], config["Jwt:Audience"], claims, now.UtcDateTime, now.AddMinutes(15).UtcDateTime, new SigningCredentials(new SymmetricSecurityKey(Encoding.UTF8.GetBytes(config["Jwt:Key"]!)), SecurityAlgorithms.HmacSha256));
        await db.SaveChangesAsync();
        return new
        {
            accessToken = new JwtSecurityTokenHandler().WriteToken(jwt),
            refreshToken = refresh,
            expiresAt = now.AddMinutes(15),
            user = Profile(user)
        };
    }
    public async Task<object> SendCode(User u, string purpose)
    {
        // One request per account across API instances, including concurrent resend/login.
        await using var transaction = await db.Database.BeginTransactionAsync();
        await using (var command = db.Database.GetDbConnection().CreateCommand())
        {
            command.Transaction = transaction.GetDbTransaction();
            command.CommandText = "DECLARE @result int; EXEC @result = sys.sp_getapplock @Resource=@resource, @LockMode='Exclusive', @LockOwner='Transaction', @LockTimeout=0; SELECT @result;";
            var resource = command.CreateParameter();
            resource.ParameterName = "@resource";
            resource.Value = "nhombar-otp:" + u.Id;
            command.Parameters.Add(resource);
            Check.That(Convert.ToInt32(await command.ExecuteScalarAsync()) >= 0, "Yêu cầu gửi mã đang được xử lý. Vui lòng chờ một chút.", 429);
        }
        Check.That(!await db.EmailOtpChallenges.AnyAsync(x => x.UserId == u.Id && x.CreatedAt > DateTimeOffset.UtcNow.AddSeconds(-60)), "Vui lòng đợi một phút trước khi yêu cầu mã mới.", 429);
        var code = RandomNumberGenerator.GetInt32(0, 1000000).ToString("D6");
        var challenge = new EmailOtpChallenge { UserId = u.Id, Purpose = purpose, ExpiresAt = DateTimeOffset.UtcNow.AddMinutes(5) };
        challenge.OtpHash = OtpHash(challenge.Id, code);
        await sender.Send(u.Email, code);
        var previous = await db.EmailOtpChallenges.Where(x => x.UserId == u.Id && x.Purpose == purpose && x.VerifiedAt == null).ToListAsync();
        foreach (var p in previous)
            p.VerifiedAt = DateTimeOffset.UtcNow;
        db.EmailOtpChallenges.Add(challenge);
        await db.SaveChangesAsync();
        await transaction.CommitAsync();
        return new
        {
            challengeId = challenge.Id,
            challenge.ExpiresAt,
            message = "Yêu cầu gửi mã đã được chấp nhận. Bạn hãy kiểm tra hộp thư và mục thư rác.",
            deliveryStatus = "accepted"
        };
    }
    public async Task<User> VerifyCode(Guid id, string code, string purpose)
    {
        var c = await db.EmailOtpChallenges.FindAsync(id);
        Check.That(c != null && c.Purpose == purpose && c.VerifiedAt == null && c.ExpiresAt > DateTimeOffset.UtcNow && c.AttemptCount < 5, "Mã đã hết hạn hoặc không còn dùng được. Vui lòng yêu cầu mã mới.", 400);
        c!.AttemptCount++;
        await db.SaveChangesAsync();
        Check.That(code is { Length: 6 } && code.All(char.IsAsciiDigit) && CryptographicOperations.FixedTimeEquals(Convert.FromHexString(c.OtpHash), Convert.FromHexString(OtpHash(c.Id, code))), "Mã xác nhận chưa đúng.");
        c.VerifiedAt = DateTimeOffset.UtcNow;
        var u = await db.Users.FindAsync(c.UserId);
        Check.That(u is { Active: true }, "Tài khoản không thể sử dụng.", 403);
        return u!;
    }
    private string OtpHash(Guid id, string code) => Convert.ToHexString(HMACSHA256.HashData(Encoding.UTF8.GetBytes(config["Jwt:Key"]!), Encoding.UTF8.GetBytes(id + ":" + code)));
}
public class Access(AppDb db, IHttpContextAccessor context)
{
    public Guid UserId => Guid.Parse(context.HttpContext!.User.FindFirstValue(ClaimTypes.NameIdentifier)!);
    public bool Parent => context.HttpContext!.User.IsInRole("Parent");
    public bool Child => context.HttpContext!.User.IsInRole("Child");
    public bool Admin => context.HttpContext!.User.IsInRole("Admin");
    public void RequireParent() => Check.That(Parent, "Chỉ phụ huynh mới được thực hiện thao tác này.", 403);
    public void RequireChild() => Check.That(Child, "Chỉ tài khoản của con mới được thực hiện thao tác này.", 403);
    public async Task<ChildProfile> ForChild(Guid id, bool parentOnly = false)
    {
        var child = await db.Children.FindAsync(id);
        Check.That(child != null, "Không tìm thấy hồ sơ của con.", 404);
        var allowed = Parent && await db.FamilyMembers.AnyAsync(x => x.UserId == UserId && x.FamilyId == child!.FamilyId && x.Relationship == "Parent");
        if (!parentOnly)
            allowed |= Child && child!.UserId == UserId;
        Check.That(allowed, "Bạn không có quyền xem hoặc thay đổi thông tin này.", 403);
        return child!;
    }
    public async Task<Device> ForDevice(Guid id, bool childOnly = false, bool parentOnly = false)
    {
        if (Child)
            Check.That(context.HttpContext!.User.FindFirstValue("device") == id.ToString(), "Điện thoại không thuộc phiên kết nối này.", 403);
        if (childOnly)
            RequireChild();
        var d = await db.Devices.FindAsync(id);
        Check.That(d is { Linked: true }, "Điện thoại chưa được kết nối.", 404);
        await ForChild(d!.ChildId, parentOnly);
        return d;
    }
    public void Log(string action, string type, Guid id) => db.AuditLogs.Add(new AuditLog { ActorId = UserId, Action = action, EntityType = type, EntityId = id.ToString() });
    public async Task NotifyParents(Guid childId, string title, string content, string type = "Info")
    {
        var c = await db.Children.FindAsync(childId);
        var parents = await db.Users.Where(u => u.Active && db.FamilyMembers.Any(x => x.UserId == u.Id && x.FamilyId == c!.FamilyId && x.Relationship == "Parent")).ToListAsync();
        foreach (var parent in parents)
            db.Notifications.Add(new Notice { ReceiverId = parent.Id, Title = title, Content = content, Type = type, SmsState = parent.SmsAlertsEnabled && type is "SOS" or "Location" ? "Pending" : "NotRequested" });
    }
    public async Task VerifyPin(string pin)
    {
        RequireParent();
        var p = await db.ParentPins.SingleOrDefaultAsync(x => x.ParentId == UserId);
        Check.That(p != null, "Vui lòng đặt mã gồm 6 số trước.");
        Check.That(p!.BlockedUntil == null || p.BlockedUntil < DateTimeOffset.UtcNow, "Đã nhập sai nhiều lần. Vui lòng thử lại sau 5 phút.", 429);
        var h = new PasswordHasher<ParentPin>();
        if (h.VerifyHashedPassword(p, p.PinHash, pin) == PasswordVerificationResult.Failed)
        {
            p.Attempts++;
            if (p.Attempts >= 5)
            {
                p.BlockedUntil = DateTimeOffset.UtcNow.AddMinutes(5);
                p.Attempts = 0;
            }
            await db.SaveChangesAsync();
            throw new AppError(400, "Mã phụ huynh chưa đúng.");
        }
        p.Attempts = 0;
        p.BlockedUntil = null;
    }
}
