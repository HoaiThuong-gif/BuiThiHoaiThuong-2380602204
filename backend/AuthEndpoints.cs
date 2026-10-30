using Microsoft.EntityFrameworkCore;

namespace NhomBar;

public record RegisterInput(string FullName, string Email, string Password);
public record LoginInput(string Email, string Password);
public record OtpInput(Guid ChallengeId, string Code, string Purpose);
public record EmailInput(string Email);
public record RefreshInput(string RefreshToken);
public record ResetInput(Guid ChallengeId, string Code, string Password);
public record PasswordInput(string CurrentPassword, string NewPassword);
public record ProfileInput(string FullName, string? PhoneNumber, bool? SmsAlertsEnabled = null, bool? EmailReportsEnabled = null, string? AvatarBase64 = null, bool RemoveAvatar = false);

public static class AuthEndpoints
{
    // Các kiểu Input là JSON nhận từ ứng dụng; AppDb đọc/ghi SQL Server.
    // Security xử lý mật khẩu, mã xác nhận và phiên; endpoint trả kết quả JSON.
    public static void MapAuth(this WebApplication app)
    {
        var auth = app.MapGroup("/api/auth").WithTags("Đăng nhập và tài khoản").RequireRateLimiting("auth");
        auth.MapPost("/register", async (RegisterInput r, AppDb db, Security security) =>
        {
            var email = Check.Email(r.Email);
            Check.Password(r.Password);
            Check.That(!await db.Users.AnyAsync(x => x.Email == email), "Email đã được sử dụng.", 409);
            var u = new User { FullName = Check.Text(r.FullName), Email = email };
            u.PasswordHash = security.PasswordHash(u, r.Password);
            var f = new Family { FamilyName = $"Gia đình {u.FullName}", CreatedBy = u.Id };
            db.Users.Add(u);
            db.Families.Add(f);
            db.FamilyMembers.Add(new FamilyMember { FamilyId = f.Id, UserId = u.Id });
            // Chỉ lưu khi dịch vụ chấp nhận gửi; chưa có nghĩa thư đã tới hộp thư.
            return await security.SendCode(u, "register");
        });
        auth.MapPost("/login", async (LoginInput r, AppDb db, Security security) =>
        {
            var email = Check.Email(r.Email);
            var u = await db.Users.SingleOrDefaultAsync(x => x.Email == email);
            Check.That(u is { Active: true, DeviceOnly: false } && u.Role != "Child" && security.PasswordOk(u, r.Password), "Email hoặc mật khẩu chưa đúng.", 401);
            return await security.SendCode(u!, "login");
        });
        auth.MapPost("/verify-otp", async (OtpInput r, AppDb db, Security security) =>
        {
            Check.That(r.Purpose is "register" or "login", "Yêu cầu xác nhận không hợp lệ.");
            var u = await security.VerifyCode(r.ChallengeId, r.Code, r.Purpose);
            u.EmailVerified = true;
            // Đăng nhập OTP mới kết thúc phiên cũ của phụ huynh/admin trên máy khác.
            // Không thay đổi phiên QR dành cho trẻ em.
            u.SecurityStamp = Guid.NewGuid().ToString();
            u.UpdatedAt = DateTimeOffset.UtcNow;
            return await security.Tokens(u);
        });
        auth.MapPost("/resend-otp", async (OtpInput r, AppDb db, Security security) =>
        {
            var c = await db.EmailOtpChallenges.FindAsync(r.ChallengeId);
            Check.That(c != null && c.VerifiedAt == null, "Vui lòng đăng nhập lại để nhận mã mới.");
            var u = await db.Users.FindAsync(c!.UserId);
            Check.That(u is { Active: true }, "Tài khoản không thể sử dụng.", 403);
            return await security.SendCode(u!, c.Purpose);
        });
        auth.MapPost("/forgot-password", async (EmailInput r, AppDb db, Security security) =>
        {
            var email = Check.Email(r.Email);
            var u = await db.Users.SingleOrDefaultAsync(x => x.Email == email && x.Active && !x.DeviceOnly && x.Role != "Child");
            // Dùng cùng cấu trúc phản hồi để không tiết lộ email nào đã đăng ký.
            var result = u == null ? new
            {
                challengeId = Guid.NewGuid(),
                expiresAt = DateTimeOffset.UtcNow.AddMinutes(5),
                message = "Nếu email đã đăng ký, bạn sẽ nhận được mã xác nhận."
            } : await security.SendCode(u, "reset");
            return Results.Ok(result);
        });
        auth.MapPost("/reset-password", async (ResetInput r, AppDb db, Security security) =>
        {
            Check.Password(r.Password);
            var u = await security.VerifyCode(r.ChallengeId, r.Code, "reset");
            u.PasswordHash = security.PasswordHash(u, r.Password);
            u.SecurityStamp = Guid.NewGuid().ToString();
            u.UpdatedAt = DateTimeOffset.UtcNow;
            db.Notifications.Add(new Notice { ReceiverId = u.Id, Title = "Mật khẩu của bạn đã được đặt lại", Content = "Nếu bạn không thực hiện thay đổi này, hãy liên hệ người quản lý ứng dụng và bảo vệ hộp thư của mình.", Type = "Security", EmailState = "Pending" });
            await db.SaveChangesAsync();
            return Results.Ok(new
            {
                message = "Đã đặt lại mật khẩu. Bạn có thể đăng nhập."
            });
        });
        auth.MapPost("/refresh", async (RefreshInput r, AppDb db, Security security) =>
        {
            var hash = Security.Hash(r.RefreshToken);
            var t = await db.RefreshTokens.SingleOrDefaultAsync(x => x.TokenHash == hash);
            Check.That(t != null && t.RevokedAt == null && t.ExpiresAt > DateTimeOffset.UtcNow, "Vui lòng đăng nhập lại.", 401);
            var u = await db.Users.FindAsync(t!.UserId);
            Check.That(u is { Active: true }, "Tài khoản không thể sử dụng.", 401);
            Check.That(t.CreatedAt >= u!.UpdatedAt, "Vui lòng đăng nhập lại.", 401);
            if (u.Role == "Child")
                Check.That(t.DeviceId != null && await db.Devices.AnyAsync(d => d.Id == t.DeviceId && d.Linked && db.Children.Any(c => c.Id == d.ChildId && c.UserId == u.Id)), "Kết nối điện thoại đã kết thúc. Hãy nhờ bố mẹ kết nối lại.", 401);
            t.RevokedAt = DateTimeOffset.UtcNow;
            return await security.Tokens(u, t.DeviceId);
        });
        auth.MapPost("/logout", async (Access access, AppDb db) =>
        {
            Check.That(!access.Child || !await db.Devices.AnyAsync(d => d.Linked && d.DeviceOwner && db.Children.Any(c => c.Id == d.ChildId && c.UserId == access.UserId)), "Hãy nhờ bố mẹ kết thúc quản lý điện thoại trước khi đăng xuất.", 403);
            var u = await db.Users.FindAsync(access.UserId);
            u!.SecurityStamp = Guid.NewGuid().ToString();
            u.UpdatedAt = DateTimeOffset.UtcNow;
            await db.SaveChangesAsync();
            return Results.NoContent();
        }).RequireAuthorization();
        auth.MapPost("/change-password", async (PasswordInput r, Access access, AppDb db, Security security) =>
        {
            var u = await db.Users.FindAsync(access.UserId);
            Check.That(security.PasswordOk(u!, r.CurrentPassword), "Mật khẩu hiện tại chưa đúng.");
            Check.Password(r.NewPassword);
            u!.PasswordHash = security.PasswordHash(u, r.NewPassword);
            u.SecurityStamp = Guid.NewGuid().ToString();
            u.UpdatedAt = DateTimeOffset.UtcNow;
            db.Notifications.Add(new Notice { ReceiverId = u.Id, Title = "Mật khẩu của bạn đã được thay đổi", Content = "Nếu bạn không thực hiện thay đổi này, hãy bảo vệ tài khoản và liên hệ người quản lý ứng dụng.", Type = "Security", EmailState = "Pending" });
            await db.SaveChangesAsync();
            return Results.Ok(new
            {
                message = "Đã đổi mật khẩu. Vui lòng đăng nhập lại."
            });
        }).RequireAuthorization();
        app.MapGet("/api/users/me", async (Access a, AppDb db) => Security.Profile((await db.Users.FindAsync(a.UserId))!)).RequireAuthorization().WithTags("Tài khoản");
        app.MapPut("/api/users/me", async (ProfileInput r, Access a, AppDb db, IConfiguration config) =>
        {
            Check.That(!a.Child, "Thông tin của con do bố mẹ quản lý.", 403);
            var u = (await db.Users.FindAsync(a.UserId))!;
            var fullName = Check.Text(r.FullName);
            var phone = string.IsNullOrWhiteSpace(r.PhoneNumber) ? null : r.PhoneNumber.Trim();
            Check.That(phone == null || System.Text.RegularExpressions.Regex.IsMatch(phone, @"^\+[1-9]\d{7,14}$"), "Số điện thoại cần mã quốc gia, ví dụ +84901234567.");
            var sms = r.SmsAlertsEnabled ?? u.SmsAlertsEnabled;
            Check.That(!sms || a.Parent && phone != null, "Để nhận tin nhắn, hãy nhập số điện thoại bắt đầu bằng mã quốc gia, ví dụ +84901234567.");
            Check.That(!sms || !string.IsNullOrWhiteSpace(config["Twilio:AccountSid"]), "Gửi tin nhắn chưa sẵn sàng. Bạn vẫn nhận được thông báo trong ứng dụng.", 503);
            if (r.EmailReportsEnabled != null)
                Check.That(a.Parent, "Chỉ phụ huynh được đăng ký báo cáo.", 403);
            Check.That(!r.RemoveAvatar || string.IsNullOrEmpty(r.AvatarBase64), "Hãy chọn ảnh mới hoặc xóa ảnh.");
            var avatar = string.IsNullOrEmpty(r.AvatarBase64) ? null : AvatarValidation.Read(r.AvatarBase64);
            // Chỉ sửa tài khoản trong JWT; email và vai trò không có trong Input.
            u.FullName = fullName;
            u.PhoneNumber = phone;
            u.SmsAlertsEnabled = sms;
            if (r.EmailReportsEnabled != null) u.EmailReportsEnabled = r.EmailReportsEnabled.Value;
            if (r.RemoveAvatar) u.AvatarBytes = null;
            else if (avatar != null) u.AvatarBytes = avatar;
            await db.SaveChangesAsync();
            return Security.Profile(u);
        }).RequireAuthorization().WithTags("Tài khoản");
    }
}
