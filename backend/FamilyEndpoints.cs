using System.Data;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;

namespace NhomBar;

public record FamilyInput(string FamilyName);
public record ChildInput(string FullName, DateOnly? DateOfBirth, string? AvatarUrl, string? Nickname = null, string? AvatarBase64 = null, bool RemoveAvatar = false);
public record ChildAccountInput(string Email, string Password);
public record PairInput(string Token, string DeviceName, string DeviceModel, string AndroidVersion);
public record PinInput(string Pin, string? CurrentPin);
public record RuleInput(int DailyLimitMinutes, TimeOnly StartTime, TimeOnly EndTime, bool StrictMode, bool AllowExtensionRequest, bool IsEnabled, long Version, string Pin, string? WarningMinutes = null, string? VoiceName = null);
public record ExtensionInput(int RequestedMinutes, string Reason);
public record DecisionInput(bool Approve, string? Response, string Pin);
public record UnlockInput(int Minutes, string Pin, long Version);
public record ParentUnlockInput(string Email, string Pin, long Version);
public record RecoveryInput(string Pin, long Version);
public record RecoveryReceiptInput(string Hash);
public record AckInput(long Version, bool IsLocked, bool DeviceOwner);
public record SafePlaceInput(string PlaceName, double Latitude, double Longitude, int RadiusMeters);
public record LocationInput(double Latitude, double Longitude, double Accuracy, DateTimeOffset RecordedAt);
public record NoiseInput(double AverageLevel, double MaximumLevel, DateTimeOffset RecordedAt);
public record UsageInput(string PackageName, string AppName, DateTimeOffset StartedAt, DateTimeOffset EndedAt, int DurationSeconds);
public record NoticeInput(Guid ReceiverId, string Title, string Content);
public record AdminUserInput(string FullName, string Email, string Role, bool Active, string? Password);

public static class FamilyEndpoints
{
    public static void MapFamily(this WebApplication app)
    {
        var api = app.MapGroup("/api").RequireAuthorization();
        api.MapGet("/families", async (Access a, AppDb db) => await db.Families.Where(f => db.FamilyMembers.Any(m => m.FamilyId == f.Id && m.UserId == a.UserId)).ToListAsync()).WithTags("Gia đình");
        api.MapPost("/families", async (FamilyInput r, Access a, AppDb db) => { a.RequireParent(); var f = new Family { FamilyName = Check.Text(r.FamilyName), CreatedBy = a.UserId }; db.Families.Add(f); db.FamilyMembers.Add(new FamilyMember { FamilyId = f.Id, UserId = a.UserId }); await db.SaveChangesAsync(); return f; }).WithTags("Gia đình");
        api.MapPut("/families/{id:guid}", async (Guid id, FamilyInput r, Access a, AppDb db) => { a.RequireParent(); var f = await db.Families.FindAsync(id); Check.That(f?.CreatedBy == a.UserId, "Bạn không có quyền thay đổi gia đình này.", 403); f!.FamilyName = Check.Text(r.FamilyName); await db.SaveChangesAsync(); return f; }).WithTags("Gia đình");
        api.MapDelete("/families/{id:guid}", async (Guid id, Access a, AppDb db) => { a.RequireParent(); var f = await db.Families.FindAsync(id); Check.That(f?.CreatedBy == a.UserId, "Bạn không có quyền xóa gia đình này.", 403); Check.That(!await db.Children.AnyAsync(x => x.FamilyId == id), "Vui lòng xóa hồ sơ con trước khi xóa gia đình.", 409); db.FamilyMembers.RemoveRange(db.FamilyMembers.Where(x => x.FamilyId == id)); db.Families.Remove(f!); await db.SaveChangesAsync(); return Results.NoContent(); }).WithTags("Gia đình");
        api.MapGet("/children", async (Access a, AppDb db) => await db.Children.Where(c => (a.Child && c.UserId == a.UserId) || (a.Parent && db.FamilyMembers.Any(m => m.UserId == a.UserId && m.FamilyId == c.FamilyId && m.Relationship == "Parent"))).ToListAsync()).WithTags("Hồ sơ con");
        api.MapGet("/dashboard", async (Access a, AppDb db) =>
        {
            var children = await db.Children.Where(c => (a.Child && c.UserId == a.UserId) || (a.Parent && db.FamilyMembers.Any(m => m.UserId == a.UserId && m.FamilyId == c.FamilyId && m.Relationship == "Parent"))).ToListAsync();
            var result = new List<object>();
            foreach (var c in children)
            {
                var rule = await db.ScreenTimeRules.SingleOrDefaultAsync(x => x.ChildId == c.Id);
                var devices = await db.Devices.Where(x => x.ChildId == c.Id && x.Linked).ToListAsync();
                var ids = devices.Select(x => x.Id).ToList();
                var summaries = await db.DailyUsageSummaries.Where(x => ids.Contains(x.DeviceId) && x.UsageDate == Check.Today).ToListAsync();
                var used = summaries.Sum(x => x.TotalSeconds);
                var bonus = await db.ExtensionRequests.Where(x => x.ChildId == c.Id && x.UsageDate == Check.Today && x.Status == "Approved").SumAsync(x => (int?)x.RequestedMinutes) ?? 0;
                var pending = await db.ExtensionRequests.CountAsync(x => x.ChildId == c.Id && x.Status == "Pending" && x.UsageDate == Check.Today);
                var locked = await db.DeviceLockStates.AnyAsync(x => ids.Contains(x.DeviceId) && x.IsLocked);
                var last = devices.Select(x => x.LastOnlineAt).Max();
                result.Add(new
                {
                    c.Id,
                    c.FullName,
                    c.FamilyId,
                    c.UserId,
                    c.DateOfBirth,
                    c.AvatarUrl,
                    c.AvatarBytes,
                    c.Nickname,
                    usedMinutes = used / 60,
                    remainingMinutes = rule is { IsEnabled: true } ? Math.Max(0, rule.DailyLimitMinutes + bonus - (int)Math.Ceiling(used / 60.0)) : (int?)null,
                    hasReport = summaries.Count > 0,
                    pendingRequests = pending,
                    isLocked = locked,
                    lastOnlineAt = last,
                    online = last > DateTimeOffset.UtcNow.AddMinutes(-2)
                });
            }
            return result;
        }).WithTags("Tổng quan");
        api.MapGet("/children/{id:guid}", async (Guid id, Access a) => await a.ForChild(id));
        api.MapPost("/families/{familyId:guid}/children", async (Guid familyId, ChildInput r, Access a, AppDb db, Security security) =>
        {
            a.RequireParent();
            Check.That(await db.FamilyMembers.AnyAsync(x => x.UserId == a.UserId && x.FamilyId == familyId && x.Relationship == "Parent"), "Bạn không có quyền thêm con vào gia đình này.", 403);
            ValidateChild(r);
            var c = new ChildProfile { FamilyId = familyId, FullName = Check.Text(r.FullName), DateOfBirth = r.DateOfBirth, AvatarUrl = r.AvatarUrl };
            ApplyChild(c, r);
            EnrollmentEndpoints.CreateIdentity(c, db, security);
            db.Children.Add(c);
            db.ScreenTimeRules.Add(new ScreenTimeRule { ChildId = c.Id });
            a.Log("Thêm hồ sơ con", "Child", c.Id);
            await db.SaveChangesAsync();
            return c;
        }).WithTags("Hồ sơ con");
        api.MapPut("/children/{id:guid}", async (Guid id, ChildInput r, Access a, AppDb db) => { var c = await a.ForChild(id, true); ApplyChild(c, r); if (c.UserId != null) { var u = await db.Users.FindAsync(c.UserId); if (u != null) u.FullName = c.FullName; } a.Log("Sửa hồ sơ con", "Child", id); await db.SaveChangesAsync(); return c; }).WithTags("Hồ sơ con");
        api.MapDelete("/children/{id:guid}", async (Guid id, [Microsoft.AspNetCore.Mvc.FromBody] PinInput r, Access a, AppDb db) =>
        {
            var c = await a.ForChild(id, true);
            await a.VerifyPin(r.Pin);
            Check.That(!await db.Devices.AnyAsync(x => x.ChildId == id), "Hồ sơ đã có lịch sử điện thoại. Hãy giữ hồ sơ để không mất thông tin.", 409);
            Check.That(!await db.ExtensionRequests.AnyAsync(x => x.ChildId == id) && !await db.NoiseReports.AnyAsync(x => x.ChildId == id), "Hồ sơ có lịch sử cần được lưu giữ.", 409);
            db.ScreenTimeRules.RemoveRange(db.ScreenTimeRules.Where(x => x.ChildId == id));
            db.SafePlaces.RemoveRange(db.SafePlaces.Where(x => x.ChildId == id));
            db.PairingRequests.RemoveRange(db.PairingRequests.Where(x => x.ChildId == id));
            db.Children.Remove(c);
            a.Log("Xóa hồ sơ con", "Child", id);
            await db.SaveChangesAsync();
            return Results.NoContent();
        }).WithTags("Hồ sơ con");
        api.MapGet("/children/{id:guid}/devices", async (Guid id, Access a, AppDb db) => { await a.ForChild(id); return await db.Devices.Where(x => x.ChildId == id && x.Linked).ToListAsync(); }).WithTags("Điện thoại");
        api.MapPost("/children/{id:guid}/pairing", async (Guid id, Access a, AppDb db, Security security) => await EnrollmentEndpoints.Invitation(id, a, db, security));
        api.MapPost("/pairing/complete", () => Results.Json(new { message = "Hãy cập nhật NhomBar và quét mã ở màn hình bắt đầu để kết nối với bố mẹ." }, statusCode: 410));
        api.MapDelete("/devices/{id:guid}", async (Guid id, [Microsoft.AspNetCore.Mvc.FromBody] PinInput r, Access a, AppDb db) => { var d = await a.ForDevice(id, parentOnly: true); await a.VerifyPin(r.Pin); Check.That(!d.DeviceOwner, "Hãy gỡ chế độ quản lý trên điện thoại của con trước để tránh điện thoại bị khóa.", 409); d.Linked = false; a.Log("Ngắt kết nối điện thoại", "Device", id); await db.SaveChangesAsync(); return Results.NoContent(); }).WithTags("Điện thoại");
        api.MapPut("/parent-pin", async (PinInput r, Access a, AppDb db) => { a.RequireParent(); Check.That(r.Pin.Length == 6 && r.Pin.All(char.IsAsciiDigit), "Mã phụ huynh cần đúng 6 chữ số."); var p = await db.ParentPins.SingleOrDefaultAsync(x => x.ParentId == a.UserId); if (p != null) await a.VerifyPin(r.CurrentPin ?? ""); else { p = new ParentPin { ParentId = a.UserId }; db.ParentPins.Add(p); } p.PinHash = new PasswordHasher<ParentPin>().HashPassword(p, r.Pin); await db.SaveChangesAsync(); return Results.Ok(new { message = "Đã lưu mã phụ huynh." }); }).WithTags("Mã phụ huynh");
        api.MapGet("/children/{id:guid}/rule", async (Guid id, Access a, AppDb db) => { await a.ForChild(id); return await db.ScreenTimeRules.SingleOrDefaultAsync(x => x.ChildId == id); }).WithTags("Thời gian sử dụng");
        api.MapPut("/children/{id:guid}/rule", async (Guid id, RuleInput r, Access a, AppDb db) =>
        {
            await a.ForChild(id, true);
            await a.VerifyPin(r.Pin);
            Check.That(r.DailyLimitMinutes is >= 1 and <= 1440 && r.StartTime < r.EndTime, "Vui lòng chọn thời gian hợp lệ trong cùng một ngày.");
            var rule = await db.ScreenTimeRules.SingleOrDefaultAsync(x => x.ChildId == id);
            if (rule == null)
            {
                Check.That(r.Version == 0, "Cài đặt đã thay đổi. Vui lòng tải lại.", 409);
                rule = new ScreenTimeRule { ChildId = id, Version = 0 };
                db.ScreenTimeRules.Add(rule);
            }
            Check.That(rule.Version == r.Version, "Cài đặt đã thay đổi. Vui lòng tải lại.", 409);
            rule.Version++;
            rule.DailyLimitMinutes = r.DailyLimitMinutes;
            rule.StartTime = r.StartTime;
            rule.EndTime = r.EndTime;
            rule.StrictMode = r.StrictMode;
            rule.AllowExtensionRequest = r.AllowExtensionRequest;
            rule.IsEnabled = r.IsEnabled;
            var warningText = r.WarningMinutes ?? "30,15,5";
            var warnings = warningText.Split(",", StringSplitOptions.RemoveEmptyEntries).Select(x => int.TryParse(x.Trim(), out var value) ? value : -1).ToList();
            Check.That(warnings.Count <= 10 && warnings.All(x => x is >= 1 and <= 120), "Mốc nhắc cần từ 1 đến 120 phút, tối đa 10 mốc.");
            rule.WarningMinutes = string.Join(",", warnings.Distinct().OrderDescending());
            rule.VoiceName = r.VoiceName;
            a.Log("Đổi thời gian sử dụng", "Child", id);
            await db.SaveChangesAsync();
            return rule;
        }).WithTags("Thời gian sử dụng");
        api.MapDelete("/children/{id:guid}/rule", async (Guid id, [Microsoft.AspNetCore.Mvc.FromBody] PinInput r, Access a, AppDb db) => { await a.ForChild(id, true); await a.VerifyPin(r.Pin); var rule = await db.ScreenTimeRules.SingleOrDefaultAsync(x => x.ChildId == id); Check.That(rule != null, "Chưa có cài đặt thời gian.", 404); rule!.IsEnabled = false; rule.Version++; a.Log("Tắt giới hạn thời gian", "Child", id); await db.SaveChangesAsync(); return Results.NoContent(); }).WithTags("Thời gian sử dụng");
        api.MapGet("/children/{id:guid}/extensions", async (Guid id, Access a, AppDb db) => { await a.ForChild(id); return await db.ExtensionRequests.Where(x => x.ChildId == id).OrderByDescending(x => x.CreatedAt).Take(100).ToListAsync(); }).WithTags("Xin thêm thời gian");
        api.MapPost("/children/{id:guid}/extensions", async (Guid id, ExtensionInput r, Access a, AppDb db) =>
        {
            a.RequireChild();
            await a.ForChild(id);
            var rule = await db.ScreenTimeRules.SingleOrDefaultAsync(x => x.ChildId == id);
            Check.That(rule is { AllowExtensionRequest: true }, "Bố mẹ chưa cho phép xin thêm thời gian.", 403);
            Check.That(r.RequestedMinutes is >= 5 and <= 120, "Con hãy chọn từ 5 đến 120 phút.");
            Check.That(!await db.ExtensionRequests.AnyAsync(x => x.ChildId == id && x.Status == "Pending" && x.UsageDate == Check.Today), "Con đã gửi yêu cầu. Hãy chờ bố mẹ trả lời nhé.", 409);
            var request = new TimeExtensionRequest { ChildId = id, RequestedMinutes = r.RequestedMinutes, Reason = Check.Text(r.Reason, 500), UsageDate = Check.Today };
            db.ExtensionRequests.Add(request);
            await a.NotifyParents(id, "Con xin thêm thời gian", request.Reason, "Extension");
            await db.SaveChangesAsync();
            return request;
        }).WithTags("Xin thêm thời gian");
        api.MapPost("/extensions/{id:guid}/decision", async (Guid id, DecisionInput r, Access a, AppDb db) =>
        {
            var e = await db.ExtensionRequests.FindAsync(id);
            Check.That(e != null, "Không tìm thấy yêu cầu.", 404);
            var c = await a.ForChild(e!.ChildId, true);
            await a.VerifyPin(r.Pin);
            Check.That(e.Status == "Pending" && e.UsageDate == Check.Today, "Yêu cầu đã được trả lời hoặc đã sang ngày mới.", 409);
            e.Status = r.Approve ? "Approved" : "Rejected";
            e.RespondedAt = DateTimeOffset.UtcNow;
            e.ParentResponse = r.Response;
            if (c.UserId != null)
                db.Notifications.Add(new Notice { ReceiverId = c.UserId.Value, Title = r.Approve ? "Bố mẹ đã đồng ý thêm thời gian" : "Bố mẹ chưa đồng ý thêm thời gian", Content = r.Response ?? "", Type = "Extension" });
            a.Log(r.Approve ? "Đồng ý thêm thời gian" : "Từ chối thêm thời gian", "Extension", id);
            await db.SaveChangesAsync();
            return e;
        }).WithTags("Xin thêm thời gian");
        api.MapGet("/devices/{id:guid}/policy", async (Guid id, Access a, AppDb db) =>
        {
            var d = await a.ForDevice(id);
            var rule = await db.ScreenTimeRules.SingleOrDefaultAsync(x => x.ChildId == d.ChildId);
            var state = await db.DeviceLockStates.SingleAsync(x => x.DeviceId == id);
            var total = await db.DailyUsageSummaries.Where(x => x.UsageDate == Check.Today && db.Devices.Any(d2 => d2.Id == x.DeviceId && d2.ChildId == d.ChildId)).SumAsync(x => (int?)x.TotalSeconds) ?? 0;
            var bonus = await db.ExtensionRequests.Where(x => x.ChildId == d.ChildId && x.UsageDate == Check.Today && x.Status == "Approved").SumAsync(x => (int?)x.RequestedMinutes) ?? 0;
            return new
            {
                rule,
                state,
                releaseUntil = d.ReleaseRequestedUntil,
                recovery = new
                {
                    hash = d.RecoveryHash,
                    version = d.RecoveryVersion
                },
                usedSeconds = total,
                extraMinutes = bonus,
                serverTime = DateTimeOffset.UtcNow,
                usageDate = Check.Today
            };
        }).WithTags("Khóa điện thoại");
        api.MapPost("/devices/{id:guid}/end-management", async (Guid id, RecoveryInput r, Access a, AppDb db) =>
        {
            var d = await a.ForDevice(id, parentOnly: true);
            await a.VerifyPin(r.Pin);
            var state = await db.DeviceLockStates.SingleAsync(x => x.DeviceId == id);
            Check.That(state.PolicyVersion == r.Version, "Trạng thái đã thay đổi. Vui lòng tải lại.", 409);
            d.ReleaseRequestedUntil = DateTimeOffset.UtcNow.AddMinutes(5);
            state.PolicyVersion++;
            a.Log("Yêu cầu kết thúc quản lý điện thoại", "Device", id);
            await db.SaveChangesAsync();
            return Results.Ok(new
            {
                message = "Đã gửi yêu cầu. Hãy giữ điện thoại của con kết nối mạng để hoàn tất."
            });
        }).WithTags("Khóa điện thoại");
        api.MapPost("/devices/{id:guid}/recovery", async (Guid id, RecoveryInput r, Access a, AppDb db) =>
        {
            var d = await a.ForDevice(id, parentOnly: true);
            await a.VerifyPin(r.Pin);
            Check.That(d.RecoveryVersion == r.Version, "Mã dự phòng đã thay đổi. Vui lòng tải lại.", 409);
            var code = Convert.ToHexString(System.Security.Cryptography.RandomNumberGenerator.GetBytes(10));
            d.RecoveryHash = Security.Hash(code);
            d.RecoveryVersion++;
            a.Log("Tạo mã mở khóa khi mất mạng", "Device", id);
            await db.SaveChangesAsync();
            return new
            {
                code,
                d.RecoveryVersion,
                message = "Giữ mã riêng cho bố mẹ. Hãy chờ điện thoại của con cập nhật trước khi cần dùng khi mất mạng. Mỗi mã chỉ dùng được một lần để mở khóa 15 phút."
            };
        }).WithTags("Khóa điện thoại");
        api.MapPost("/devices/{id:guid}/recovery-used", async (Guid id, RecoveryReceiptInput r, Access a, AppDb db) =>
        {
            var d = await a.ForDevice(id, true);
            Check.That(d.RecoveryHash == r.Hash, "Mã khôi phục đã được thay thế.", 409);
            d.RecoveryHash = null;
            a.Log("Đã dùng mã mở khóa khi mất mạng", "Device", id);
            await a.NotifyParents(d.ChildId, "Đã dùng mã mở khóa khi mất mạng", "Điện thoại đã được cho phép dùng thêm 15 phút. Hãy tạo mã mới nếu cần.", "Lock");
            await db.SaveChangesAsync();
            return Results.NoContent();
        }).WithTags("Khóa điện thoại");
        api.MapPost("/devices/{id:guid}/unlock", async (Guid id, UnlockInput r, Access a, AppDb db) =>
        {
            var d = await a.ForDevice(id, parentOnly: true);
            await a.VerifyPin(r.Pin);
            Check.That(r.Minutes is >= 1 and <= 1440, "Thời gian mở khóa không hợp lệ.");
            var s = await db.DeviceLockStates.SingleAsync(x => x.DeviceId == id);
            Check.That(s.PolicyVersion == r.Version, "Trạng thái đã thay đổi. Vui lòng tải lại.", 409);
            s.IsLocked = false;
            s.UnlockAt = DateTimeOffset.UtcNow.AddMinutes(r.Minutes);
            s.PolicyVersion++;
            a.Log("Cho phép dùng thêm điện thoại", "Device", id);
            await db.SaveChangesAsync();
            return s;
        }).WithTags("Khóa điện thoại");
        api.MapPost("/devices/{id:guid}/parent-unlock", async (Guid id, ParentUnlockInput r, Access a, AppDb db) =>
        {
            var d = await a.ForDevice(id, true);
            var c = await db.Children.FindAsync(d.ChildId);
            var email = Check.Email(r.Email);
            var parent = await db.Users.SingleOrDefaultAsync(x => x.Email == email && x.Active && x.Role == "Parent");
            Check.That(parent != null && await db.FamilyMembers.AnyAsync(x => x.UserId == parent.Id && x.FamilyId == c!.FamilyId && x.Relationship == "Parent"), "Email hoặc mã phụ huynh chưa đúng.");
            var pin = await db.ParentPins.SingleOrDefaultAsync(x => x.ParentId == parent!.Id);
            Check.That(pin != null, "Email hoặc mã phụ huynh chưa đúng.");
            Check.That(pin!.BlockedUntil == null || pin.BlockedUntil < DateTimeOffset.UtcNow, "Vui lòng thử lại sau 5 phút.", 429);
            if (new PasswordHasher<ParentPin>().VerifyHashedPassword(pin, pin.PinHash, r.Pin) == PasswordVerificationResult.Failed)
            {
                pin.Attempts++;
                if (pin.Attempts >= 5)
                {
                    pin.BlockedUntil = DateTimeOffset.UtcNow.AddMinutes(5);
                    pin.Attempts = 0;
                }
                await db.SaveChangesAsync();
                throw new AppError(400, "Email hoặc mã phụ huynh chưa đúng.");
            }
            pin.Attempts = 0;
            pin.BlockedUntil = null;
            var state = await db.DeviceLockStates.SingleAsync(x => x.DeviceId == id);
            Check.That(state.PolicyVersion == r.Version, "Trạng thái đã thay đổi. Vui lòng thử lại.", 409);
            state.PolicyVersion++;
            state.IsLocked = false;
            state.UnlockAt = DateTimeOffset.UtcNow.AddMinutes(15);
            a.Log("Phụ huynh xác nhận mở khóa tại điện thoại", "Device", id);
            await a.NotifyParents(d.ChildId, "Điện thoại đã được mở khóa bằng mã phụ huynh", "Cho phép sử dụng thêm 15 phút.", "Lock");
            await db.SaveChangesAsync();
            return state;
        }).RequireRateLimiting("auth").WithTags("Khóa điện thoại");
        api.MapPost("/devices/{id:guid}/ack", async (Guid id, AckInput r, Access a, AppDb db) =>
        {
            var d = await a.ForDevice(id, true);
            var s = await db.DeviceLockStates.SingleAsync(x => x.DeviceId == id);
            Check.That(r.Version == s.PolicyVersion, "Cài đặt đã thay đổi. Vui lòng tải lại.", 409);
            var changed = s.IsLocked != r.IsLocked;
            s.IsLocked = r.IsLocked;
            s.AcknowledgedVersion = r.Version;
            if (r.IsLocked)
                s.LockedAt = DateTimeOffset.UtcNow;
            d.LastOnlineAt = DateTimeOffset.UtcNow;
            d.DeviceOwner = r.DeviceOwner;
            if (changed)
            {
                a.Log(r.IsLocked ? "Điện thoại đã khóa" : "Điện thoại đã mở", "Device", id);
                await a.NotifyParents(d.ChildId, r.IsLocked ? "Điện thoại của con đã khóa" : "Điện thoại của con đã mở", "Trạng thái được gửi từ điện thoại của con.", "Lock");
            }
            await db.SaveChangesAsync();
            return Results.NoContent();
        }).WithTags("Khóa điện thoại");
        MapReports(api);
        MapAdmin(api);
    }
    static void ApplyChild(ChildProfile c, ChildInput r)
    {
        ValidateChild(r);
        c.FullName = Check.Text(r.FullName);
        c.DateOfBirth = r.DateOfBirth;
        c.Nickname = string.IsNullOrWhiteSpace(r.Nickname) ? null : Check.Text(r.Nickname, 60);
        c.AvatarUrl = string.IsNullOrWhiteSpace(r.AvatarUrl) ? null : Check.Text(r.AvatarUrl, 1000);
        Check.That(c.AvatarUrl == null || Uri.TryCreate(c.AvatarUrl, UriKind.Absolute, out var avatarUri) && avatarUri.Scheme == "https", "Địa chỉ ảnh chưa hợp lệ.");
        if (r.RemoveAvatar)
        {
            c.AvatarBytes = null;
            c.AvatarUrl = null;
        }
        if (!string.IsNullOrEmpty(r.AvatarBase64))
            c.AvatarBytes = AvatarValidation.Read(r.AvatarBase64);
    }
    static void ValidateChild(ChildInput r)
    {
        Check.Text(r.FullName);
        Check.That(r.DateOfBirth == null || r.DateOfBirth >= new DateOnly(1900, 1, 1) && r.DateOfBirth <= Check.Today, "Ngày sinh cần từ năm 1900 đến hôm nay.");
        Check.That(r.AvatarUrl == null || Uri.TryCreate(r.AvatarUrl, UriKind.Absolute, out var url) && url.Scheme == "https", "Ảnh đại diện cần là đường dẫn ảnh an toàn.");
    }

    static void MapReports(RouteGroupBuilder api)
    {
        api.MapPost("/devices/{id:guid}/usage", async (Guid id, List<UsageInput> records, Access a, AppDb db) =>
        {
            await a.ForDevice(id, true);
            Check.That(records.Count <= 500, "Vui lòng gửi ít dữ liệu hơn trong một lần.");
            await using var tx = await db.Database.BeginTransactionAsync(IsolationLevel.Serializable);
            var dates = new HashSet<DateOnly>();
            foreach (var r in records)
            {
                Check.Text(r.PackageName, 256);
                Check.Text(r.AppName);
                Check.That(r.StartedAt < r.EndedAt && r.EndedAt <= DateTimeOffset.UtcNow.AddMinutes(2) && r.DurationSeconds > 0 && r.DurationSeconds <= (r.EndedAt - r.StartedAt).TotalSeconds + 1 && (r.EndedAt - r.StartedAt).TotalDays <= 1, "Bản ghi thời gian sử dụng chưa hợp lệ.");
                var day = DateOnly.FromDateTime(r.StartedAt.ToOffset(TimeSpan.FromHours(7)).DateTime);
                Check.That(day == DateOnly.FromDateTime(r.EndedAt.AddTicks(-1).ToOffset(TimeSpan.FromHours(7)).DateTime), "Vui lòng chia bản ghi theo từng ngày.");
                dates.Add(day);
                if (!await db.AppUsageRecords.AnyAsync(x => x.DeviceId == id && x.PackageName == r.PackageName && x.StartedAt == r.StartedAt && x.EndedAt == r.EndedAt) && !db.AppUsageRecords.Local.Any(x => x.DeviceId == id && x.PackageName == r.PackageName && x.StartedAt == r.StartedAt && x.EndedAt == r.EndedAt))
                    db.AppUsageRecords.Add(new AppUsageRecord { DeviceId = id, PackageName = r.PackageName, AppName = r.AppName, StartedAt = r.StartedAt, EndedAt = r.EndedAt, DurationSeconds = r.DurationSeconds });
            }
            await db.SaveChangesAsync();
            foreach (var day in dates)
            {
                var start = new DateTimeOffset(day.ToDateTime(TimeOnly.MinValue), TimeSpan.FromHours(7));
                var end = start.AddDays(1);
                var total = await db.AppUsageRecords.Where(x => x.DeviceId == id && x.StartedAt >= start && x.StartedAt < end).SumAsync(x => (int?)x.DurationSeconds) ?? 0;
                var s = await db.DailyUsageSummaries.SingleOrDefaultAsync(x => x.DeviceId == id && x.UsageDate == day);
                if (s == null)
                {
                    s = new DailyUsageSummary { DeviceId = id, UsageDate = day };
                    db.DailyUsageSummaries.Add(s);
                }
                s.TotalSeconds = total;
                s.LastSyncedAt = DateTimeOffset.UtcNow;
            }
            await db.SaveChangesAsync();
            await tx.CommitAsync();
            return Results.Ok(new
            {
                message = "Đã cập nhật thời gian sử dụng."
            });
        }).WithTags("Báo cáo sử dụng");
        api.MapGet("/children/{id:guid}/usage", async (Guid id, DateOnly? from, DateOnly? to, Access a, AppDb db) =>
        {
            await a.ForChild(id);
            var start = from ?? Check.Today.AddDays(-6);
            var end = to ?? Check.Today;
            Check.That(end >= start && end.DayNumber - start.DayNumber <= 90, "Vui lòng chọn khoảng thời gian tối đa 90 ngày.");
            var devices = db.Devices.Where(x => x.ChildId == id).Select(x => x.Id);
            var summaries = await db.DailyUsageSummaries.Where(x => devices.Contains(x.DeviceId) && x.UsageDate >= start && x.UsageDate <= end).OrderBy(x => x.UsageDate).ToListAsync();
            var utcStart = new DateTimeOffset(start.ToDateTime(TimeOnly.MinValue), TimeSpan.FromHours(7));
            var utcEnd = new DateTimeOffset(end.AddDays(1).ToDateTime(TimeOnly.MinValue), TimeSpan.FromHours(7));
            var apps = await db.AppUsageRecords.Where(x => devices.Contains(x.DeviceId) && x.StartedAt >= utcStart && x.StartedAt < utcEnd).GroupBy(x => new { x.PackageName, x.AppName }).Select(x => new { x.Key.PackageName, x.Key.AppName, seconds = x.Sum(v => v.DurationSeconds) }).OrderByDescending(x => x.seconds).Take(20).ToListAsync();
            var categories = await db.AppClassifications.Where(x => x.ChildId == id).ToDictionaryAsync(x => x.PackageName, x => x.Category);
            return new
            {
                summaries,
                apps = apps.Select(x => new { x.PackageName, x.AppName, x.seconds, category = categories.GetValueOrDefault(x.PackageName, "Other") })
            };
        }).WithTags("Báo cáo sử dụng");
        api.MapGet("/children/{id:guid}/locations", async (Guid id, Access a, AppDb db) => { await a.ForChild(id); return await db.Locations.Where(x => db.Devices.Any(d => d.Id == x.DeviceId && d.ChildId == id)).OrderByDescending(x => x.RecordedAt).Take(100).ToListAsync(); }).WithTags("Vị trí");
        api.MapPost("/devices/{id:guid}/locations", async (Guid id, LocationInput r, Access a, AppDb db) =>
        {
            var d = await a.ForDevice(id, true);
            Check.Coordinates(r.Latitude, r.Longitude);
            Check.That(double.IsFinite(r.Accuracy) && r.Accuracy >= 0 && r.RecordedAt <= DateTimeOffset.UtcNow.AddMinutes(2) && r.RecordedAt > DateTimeOffset.UtcNow.AddDays(-7), "Thông tin vị trí chưa hợp lệ.");
            var previous = await db.Locations.Where(x => x.DeviceId == id).OrderByDescending(x => x.RecordedAt).FirstOrDefaultAsync();
            if (previous != null && r.RecordedAt <= previous.RecordedAt)
                return Results.Ok(new
                {
                    message = "Đã có vị trí mới hơn."
                });
            db.Locations.Add(new LocationUpdate { DeviceId = id, Latitude = r.Latitude, Longitude = r.Longitude, Accuracy = r.Accuracy, RecordedAt = r.RecordedAt });
            var places = await db.SafePlaces.Where(x => x.ChildId == d.ChildId).ToListAsync();
            foreach (var p in places)
            {
                var inside = Distance(r.Latitude, r.Longitude, p.Latitude, p.Longitude) <= p.RadiusMeters;
                if (previous != null && inside != (Distance(previous.Latitude, previous.Longitude, p.Latitude, p.Longitude) <= p.RadiusMeters))
                    await a.NotifyParents(d.ChildId, inside ? "Con đã vào khu vực an toàn" : "Con đã rời khu vực an toàn", p.PlaceName, "Location");
            }
            await db.SaveChangesAsync();
            return Results.Ok(new
            {
                message = "Đã chia sẻ vị trí."
            });
        }).WithTags("Vị trí");
        api.MapGet("/children/{id:guid}/safe-places", async (Guid id, Access a, AppDb db) => { await a.ForChild(id); return await db.SafePlaces.Where(x => x.ChildId == id).ToListAsync(); }).WithTags("Khu vực an toàn");
        api.MapPost("/children/{id:guid}/safe-places", async (Guid id, SafePlaceInput r, Access a, AppDb db) => { await a.ForChild(id, true); ValidatePlace(r); var p = new SafePlace { ChildId = id, PlaceName = r.PlaceName.Trim(), Latitude = r.Latitude, Longitude = r.Longitude, RadiusMeters = r.RadiusMeters }; db.SafePlaces.Add(p); await db.SaveChangesAsync(); return p; }).WithTags("Khu vực an toàn");
        api.MapPut("/safe-places/{id:guid}", async (Guid id, SafePlaceInput r, Access a, AppDb db) => { var p = await db.SafePlaces.FindAsync(id); Check.That(p != null, "Không tìm thấy địa điểm.", 404); await a.ForChild(p!.ChildId, true); ValidatePlace(r); p.PlaceName = r.PlaceName.Trim(); p.Latitude = r.Latitude; p.Longitude = r.Longitude; p.RadiusMeters = r.RadiusMeters; await db.SaveChangesAsync(); return p; }).WithTags("Khu vực an toàn");
        api.MapDelete("/safe-places/{id:guid}", async (Guid id, Access a, AppDb db) => { var p = await db.SafePlaces.FindAsync(id); Check.That(p != null, "Không tìm thấy địa điểm.", 404); await a.ForChild(p!.ChildId, true); db.SafePlaces.Remove(p); await db.SaveChangesAsync(); return Results.NoContent(); }).WithTags("Khu vực an toàn");
        api.MapPost("/children/{id:guid}/noise", async (Guid id, NoiseInput r, Access a, AppDb db) => { a.RequireChild(); var child = await a.ForChild(id); Check.That(double.IsFinite(r.AverageLevel) && double.IsFinite(r.MaximumLevel) && r.AverageLevel is >= 0 and <= 200 && r.MaximumLevel >= r.AverageLevel && r.MaximumLevel <= 200 && r.RecordedAt <= DateTimeOffset.UtcNow.AddMinutes(2), "Kết quả đo chưa hợp lệ."); var report = new NoiseReport { ChildId = id, AverageLevel = r.AverageLevel, MaximumLevel = r.MaximumLevel, RecordedAt = r.RecordedAt }; db.NoiseReports.Add(report); await a.NotifyParents(id, $"{child.FullName} đã gửi kết quả đo tiếng ồn", $"Trung bình {r.AverageLevel:F0} dB, cao nhất {r.MaximumLevel:F0} dB. Mở hồ sơ con để xem các lần đo. Kết quả chỉ để tham khảo.", "Noise"); await db.SaveChangesAsync(); return report; }).WithTags("Đo tiếng ồn");
        api.MapGet("/children/{id:guid}/noise", async (Guid id, Access a, AppDb db) => { await a.ForChild(id); return await db.NoiseReports.Where(x => x.ChildId == id).OrderByDescending(x => x.RecordedAt).Take(100).ToListAsync(); }).WithTags("Đo tiếng ồn");
        api.MapPost("/children/{id:guid}/safety", async (Guid id, bool emergency, Access a, AppDb db) => { a.RequireChild(); var c = await a.ForChild(id); await a.NotifyParents(id, emergency ? "Con cần giúp đỡ" : "Con báo an toàn", $"{c.FullName} vừa gửi thông báo.", emergency ? "SOS" : "Safety"); await db.SaveChangesAsync(); return Results.Ok(new { message = "Đã gửi thông báo đến bố mẹ." }); }).RequireRateLimiting("safety").WithTags("An toàn");
        api.MapGet("/children/{id:guid}/contacts", async (Guid id, Access a, AppDb db) => { var c = await a.ForChild(id); return await db.Users.Where(u => db.FamilyMembers.Any(m => m.FamilyId == c.FamilyId && m.UserId == u.Id && m.Relationship == "Parent")).Select(u => new { u.FullName, u.PhoneNumber }).ToListAsync(); }).WithTags("An toàn");
        api.MapGet("/notifications", async (Access a, AppDb db) => await db.Notifications.Where(x => x.ReceiverId == a.UserId).OrderByDescending(x => x.CreatedAt).Take(100).ToListAsync()).WithTags("Thông báo");
        api.MapPut("/notifications/{id:guid}/read", async (Guid id, Access a, AppDb db) => { var n = await db.Notifications.FindAsync(id); Check.That(n?.ReceiverId == a.UserId, "Không tìm thấy thông báo.", 404); n!.IsRead = true; await db.SaveChangesAsync(); return Results.NoContent(); }).WithTags("Thông báo");
        api.MapGet("/audit", async (Access a, AppDb db) => await db.AuditLogs.Where(x => x.ActorId == a.UserId).OrderByDescending(x => x.CreatedAt).Take(100).ToListAsync()).WithTags("Lịch sử quản lý");
    }
    static void ValidatePlace(SafePlaceInput r)
    {
        Check.Text(r.PlaceName);
        Check.Coordinates(r.Latitude, r.Longitude);
        Check.That(r.RadiusMeters is >= 50 and <= 10000, "Bán kính cần từ 50 đến 10.000 mét.");
    }
    static double Distance(double lat, double lon, double lat2, double lon2)
    {
        var rad = Math.PI / 180;
        var a = Math.Pow(Math.Sin((lat2 - lat) * rad / 2), 2) + Math.Cos(lat * rad) * Math.Cos(lat2 * rad) * Math.Pow(Math.Sin((lon2 - lon) * rad / 2), 2);
        return 6371000 * 2 * Math.Atan2(Math.Sqrt(a), Math.Sqrt(1 - a));
    }
    static void MapAdmin(RouteGroupBuilder api)
    {
        var admin = api.MapGroup("/admin").RequireAuthorization(p => p.RequireRole("Admin")).WithTags("Quản trị");
        admin.MapGet("/summary", async (AppDb db) => new { users = await db.Users.CountAsync(), parents = await db.Users.CountAsync(x => x.Role == "Parent"), children = await db.Children.CountAsync(), active = await db.Users.CountAsync(x => x.Active) });
        admin.MapGet("/users", async (AppDb db) => (await db.Users.OrderByDescending(x => x.CreatedAt).Take(200).ToListAsync()).Select(Security.Profile));
        admin.MapPost("/users", async (AdminUserInput r, Access a, AppDb db, Security security) => { var email = Check.Email(r.Email); Check.That(r.Role is "Admin" or "Parent", "Tài khoản của con cần được phụ huynh tạo trong gia đình."); Check.Password(r.Password ?? ""); Check.That(!await db.Users.AnyAsync(x => x.Email == email), "Email đã được sử dụng.", 409); var u = new User { FullName = Check.Text(r.FullName), Email = email, Role = r.Role, Active = r.Active }; u.PasswordHash = security.PasswordHash(u, r.Password!); db.Users.Add(u); if (u.Role == "Parent") { var f = new Family { FamilyName = $"Gia đình {u.FullName}", CreatedBy = u.Id }; db.Families.Add(f); db.FamilyMembers.Add(new FamilyMember { FamilyId = f.Id, UserId = u.Id }); } a.Log("Thêm tài khoản", "User", u.Id); await db.SaveChangesAsync(); return Security.Profile(u); });
        admin.MapPut("/users/{id:guid}", async (Guid id, AdminUserInput r, Access a, AppDb db, Security security) => { var u = await db.Users.FindAsync(id); Check.That(u != null, "Không tìm thấy tài khoản.", 404); Check.That(u!.Role == r.Role, "Không thể đổi loại tài khoản sau khi đã tạo."); Check.That(id != a.UserId || r.Active, "Bạn không thể tự khóa tài khoản đang dùng."); u.FullName = Check.Text(r.FullName); u.Active = r.Active; if (!string.IsNullOrEmpty(r.Password)) { Check.Password(r.Password); u.PasswordHash = security.PasswordHash(u, r.Password); } u.SecurityStamp = Guid.NewGuid().ToString(); u.UpdatedAt = DateTimeOffset.UtcNow; a.Log("Cập nhật tài khoản", "User", id); await db.SaveChangesAsync(); return Security.Profile(u); });
        admin.MapDelete("/users/{id:guid}", async (Guid id, Access a, AppDb db) => { Check.That(id != a.UserId, "Bạn không thể xóa tài khoản đang dùng."); var u = await db.Users.FindAsync(id); Check.That(u != null, "Không tìm thấy tài khoản.", 404); u!.Active = false; u.SecurityStamp = Guid.NewGuid().ToString(); u.UpdatedAt = DateTimeOffset.UtcNow; a.Log("Ngừng tài khoản", "User", id); await db.SaveChangesAsync(); return Results.NoContent(); });
        admin.MapGet("/notifications", async (AppDb db) => await db.Notifications.Where(x => x.Type == "Admin").OrderByDescending(x => x.CreatedAt).Take(200).Select(x => new { x.Id, x.ReceiverId, x.Title, x.Content, x.Type, x.CreatedAt }).ToListAsync());
        admin.MapPost("/notifications", async (NoticeInput r, Access a, AppDb db) => { Check.That(await db.Users.AnyAsync(x => x.Id == r.ReceiverId), "Không tìm thấy người nhận.", 404); var n = new Notice { ReceiverId = r.ReceiverId, Title = Check.Text(r.Title), Content = Check.Text(r.Content, 1000), Type = "Admin" }; db.Notifications.Add(n); a.Log("Gửi thông báo", "Notice", n.Id); await db.SaveChangesAsync(); return n; });
        admin.MapPut("/notifications/{id:guid}", async (Guid id, NoticeInput r, Access a, AppDb db) => { var n = await db.Notifications.FindAsync(id); Check.That(n is { Type: "Admin" }, "Không tìm thấy thông báo quản trị.", 404); n!.Title = Check.Text(r.Title); n.Content = Check.Text(r.Content, 1000); a.Log("Sửa thông báo", "Notice", id); await db.SaveChangesAsync(); return n; });
        admin.MapDelete("/notifications/{id:guid}", async (Guid id, Access a, AppDb db) => { var n = await db.Notifications.FindAsync(id); Check.That(n is { Type: "Admin" }, "Không tìm thấy thông báo quản trị.", 404); db.Notifications.Remove(n!); a.Log("Xóa thông báo", "Notice", id); await db.SaveChangesAsync(); return Results.NoContent(); });
        admin.MapGet("/audit", async (AppDb db) => await db.AuditLogs.OrderByDescending(x => x.CreatedAt).Take(200).ToListAsync());
    }
}
