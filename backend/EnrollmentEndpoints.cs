using System.Data;
using System.Security.Cryptography;
using Microsoft.EntityFrameworkCore;

namespace NhomBar;

public record EnrollmentStart(string Token, string DeviceName, string DeviceModel, string AndroidVersion, string InstallationId);
public record EnrollmentSecret(Guid Id, string Secret);
public record EnrollmentDecision(bool Approve);

public static class EnrollmentEndpoints
{
    public static User CreateIdentity(ChildProfile child, AppDb db, Security security)
    {
        var u = new User { Role = "Child", DeviceOnly = true, FullName = child.FullName, Email = $"child-{Guid.NewGuid():N}@devices.nhombar.invalid" };
        u.PasswordHash = security.PasswordHash(u, Security.RandomToken());
        child.UserId = u.Id;
        db.Users.Add(u);
        db.FamilyMembers.Add(new FamilyMember { FamilyId = child.FamilyId, UserId = u.Id, Relationship = "Child" });
        return u;
    }
    public static async Task<object> Invitation(Guid id, Access access, AppDb db, Security security)
    {
        var child = await access.ForChild(id, true);
        Check.That(!await db.Devices.AnyAsync(d => d.ChildId == id && d.Linked), "Hãy ngắt kết nối điện thoại cũ trước khi kết nối điện thoại mới.", 409);
        if (child.UserId == null)
            CreateIdentity(child, db, security);
        var token = Security.RandomToken();
        var p = new PairingRequest { ParentId = access.UserId, ChildId = id, TokenHash = Security.Hash(token), ExpiresAt = DateTimeOffset.UtcNow.AddMinutes(5) };
        db.PairingRequests.Add(p);
        await db.SaveChangesAsync();
        return new
        {
            token,
            p.ExpiresAt
        };
    }
    public static void MapEnrollment(this WebApplication app)
    {
        var anonymous = app.MapGroup("/api/enrollment").RequireRateLimiting("enrollment").WithTags("Kết nối với phụ huynh");
        anonymous.MapPost("/start", async (EnrollmentStart r, AppDb db) =>
        {
            Check.That(r.Token is { Length: 64 } && Guid.TryParse(r.InstallationId, out _), "Mã kết nối chưa đúng. Hãy quét lại mã trên điện thoại bố mẹ.");
            await using var tx = await db.Database.BeginTransactionAsync(IsolationLevel.Serializable);
            var hash = Security.Hash(r.Token);
            var p = await db.PairingRequests.SingleOrDefaultAsync(x => x.TokenHash == hash);
            Check.That(p != null && p.UsedAt == null && p.ExpiresAt > DateTimeOffset.UtcNow, "Mã đã hết hạn hoặc được dùng. Hãy nhờ bố mẹ tạo mã mới.");
            Check.That(!await db.Devices.AnyAsync(d => d.ChildId == p!.ChildId && d.Linked), "Hồ sơ đã kết nối một điện thoại. Hãy nhờ bố mẹ kiểm tra.", 409);
            var child = await db.Children.FindAsync(p!.ChildId);
            var parent = await db.Users.FindAsync(p.ParentId);
            Check.That(parent is { Active: true, Role: "Parent" } && child != null, "Mã kết nối không còn dùng được.");
            var secret = Security.RandomToken();
            var e = new DeviceEnrollment { PairingRequestId = p.Id, ClaimHash = Security.Hash(secret), InstallationHash = Security.Hash(r.InstallationId), VerificationCode = RandomNumberGenerator.GetInt32(0, 1000000).ToString("D6"), DeviceName = Check.Text(r.DeviceName), DeviceModel = Check.Text(r.DeviceModel), AndroidVersion = Check.Text(r.AndroidVersion), ExpiresAt = p.ExpiresAt };
            p.UsedAt = DateTimeOffset.UtcNow;
            db.DeviceEnrollments.Add(e);
            db.Notifications.Add(new Notice { ReceiverId = p.ParentId, Title = "Có điện thoại muốn kết nối", Content = "Mở hồ sơ của con để kiểm tra và xác nhận điện thoại.", Type = "Pairing" });
            await db.SaveChangesAsync();
            await tx.CommitAsync();
            return Results.Ok(new
            {
                id = e.Id,
                secret,
                e.VerificationCode,
                e.ExpiresAt,
                child = new
                {
                    child!.FullName,
                    child.DateOfBirth
                },
                parentName = parent!.FullName
            });
        });
        anonymous.MapPost("/status", async (EnrollmentSecret r, AppDb db) =>
        {
            var e = await Find(r, db);
            return Results.Ok(new
            {
                status = e.ExpiresAt <= DateTimeOffset.UtcNow ? "Expired" : e.Status,
                e.ExpiresAt
            });
        });
        anonymous.MapPost("/session", async (EnrollmentSecret r, AppDb db, Security security) =>
        {
            await using var tx = await db.Database.BeginTransactionAsync();
            var e = await Find(r, db);
            Check.That(e.Status == "Approved" && e.ConsumedAt == null && e.ExpiresAt > DateTimeOffset.UtcNow, "Kết nối chưa được xác nhận hoặc đã hết hạn. Hãy nhờ bố mẹ kiểm tra.");
            var device = await db.Devices.FindAsync(e.DeviceId);
            var child = await db.Children.FindAsync(device!.ChildId);
            var user = await db.Users.FindAsync(child!.UserId);
            Check.That(device.Linked && user is { Active: true, Role: "Child" }, "Kết nối không còn dùng được.", 403);
            e.ConsumedAt = DateTimeOffset.UtcNow;
            device.LastOnlineAt = DateTimeOffset.UtcNow;
            var session = await security.Tokens(user!, device.Id);
            await tx.CommitAsync();
            return Results.Ok(new
            {
                session,
                device = new
                {
                    device.Id,
                    device.DeviceName
                },
                child = new
                {
                    child.Id,
                    child.FullName
                }
            });
        });
        var parentApi = app.MapGroup("/api").RequireAuthorization().WithTags("Xác nhận điện thoại của con");
        parentApi.MapGet("/children/{id:guid}/pairing/pending", async (Guid id, Access a, AppDb db) =>
        {
            await a.ForChild(id, true);
            return await db.DeviceEnrollments.Where(e => e.Status == "Pending" && e.ExpiresAt > DateTimeOffset.UtcNow && db.PairingRequests.Any(p => p.Id == e.PairingRequestId && p.ChildId == id))
                .Select(e => new { e.Id, e.DeviceName, e.DeviceModel, e.AndroidVersion, e.VerificationCode, e.ExpiresAt }).ToListAsync();
        });
        parentApi.MapPost("/enrollment/{id:guid}/decision", async (Guid id, EnrollmentDecision r, Access a, AppDb db, Security security) =>
        {
            a.RequireParent();
            await using var tx = await db.Database.BeginTransactionAsync(IsolationLevel.Serializable);
            var e = await db.DeviceEnrollments.FindAsync(id);
            Check.That(e != null, "Không tìm thấy yêu cầu kết nối.", 404);
            var p = await db.PairingRequests.FindAsync(e!.PairingRequestId);
            var child = await a.ForChild(p!.ChildId, true);
            Check.That(e.Status == "Pending" && e.ExpiresAt > DateTimeOffset.UtcNow, "Yêu cầu đã xử lý hoặc hết hạn.", 409);
            if (r.Approve)
            {
                Check.That(!await db.Devices.AnyAsync(d => d.ChildId == child.Id && d.Linked), "Con đã kết nối một điện thoại khác.", 409);
                if (child.UserId == null)
                    CreateIdentity(child, db, security);
                var device = new Device { ChildId = child.Id, DeviceName = e.DeviceName, DeviceModel = e.DeviceModel, AndroidVersion = e.AndroidVersion };
                db.Devices.Add(device);
                db.DeviceLockStates.Add(new DeviceLockState { DeviceId = device.Id });
                e.DeviceId = device.Id;
                e.Status = "Approved";
            }
            else
                e.Status = "Rejected";
            a.Log(r.Approve ? "Xác nhận điện thoại của con" : "Từ chối kết nối", "DeviceEnrollment", id);
            await db.SaveChangesAsync();
            await tx.CommitAsync();
            return Results.Ok(new
            {
                e.Status
            });
        });
    }
    private static async Task<DeviceEnrollment> Find(EnrollmentSecret r, AppDb db)
    {
        Check.That(r.Secret is { Length: 64 }, "Yêu cầu kết nối không hợp lệ.");
        var hash = Security.Hash(r.Secret);
        var e = await db.DeviceEnrollments.SingleOrDefaultAsync(x => x.Id == r.Id && x.ClaimHash == hash);
        Check.That(e != null, "Yêu cầu kết nối không hợp lệ.", 404);
        return e!;
    }
}
