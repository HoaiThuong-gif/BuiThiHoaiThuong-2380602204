using Microsoft.EntityFrameworkCore;
namespace NhomBar;

public record PushRegisterInput(string Token, string InstallationId);
public record PushReceiptInput(Guid NoticeId, string InstallationId, string Phase);
public static class PushEndpoints
{
    public static void MapPush(this WebApplication app)
    {
        var api = app.MapGroup("/api/push").RequireAuthorization().WithTags("Thông báo trên điện thoại");
        api.MapPost("/register", async (PushRegisterInput r, Access a, AppDb db, PushTokenProtection protection) =>
        {
            Check.That(Guid.TryParse(r.InstallationId, out _) && r.Token.Length is >= 20 and <= 4096, "Chưa đăng ký được thông báo trên điện thoại.");
            var installation = Security.Hash(r.InstallationId);
            var token = Security.Hash(r.Token);
            var user = await db.Users.FindAsync(a.UserId);
            var registration = await db.PushRegistrations.SingleOrDefaultAsync(x => x.InstallationHash == installation);
            var previous = await db.PushRegistrations.SingleOrDefaultAsync(x => x.TokenHash == token);
            Check.That(previous == null || previous.Id == registration?.Id, "Hãy mở lại ứng dụng để đăng ký thông báo.", 409);
            if (registration == null)
            {
                registration = new PushRegistration { InstallationHash = installation };
                db.PushRegistrations.Add(registration);
            }
            registration.UserId = a.UserId;
            registration.SecurityStamp = user!.SecurityStamp;
            registration.TokenHash = token;
            registration.ProtectedToken = protection.Protect(r.Token);
            registration.Active = true;
            registration.LastSeenAt = DateTimeOffset.UtcNow;
            await db.SaveChangesAsync();
            return Results.Ok(new
            {
                message = "Đã đăng ký thông báo trên điện thoại.",
                binding = Security.Hash(user.Id + ":" + user.SecurityStamp)
            });
        });
        api.MapPost("/unregister", async (PushRegisterInput r, Access a, AppDb db) =>
        {
            var installation = Security.Hash(r.InstallationId);
            await db.PushRegistrations.Where(x => x.UserId == a.UserId && x.InstallationHash == installation).ExecuteUpdateAsync(s => s.SetProperty(x => x.Active, false));
            return Results.NoContent();
        });
        api.MapPost("/receipt", async (PushReceiptInput r, Access a, AppDb db) =>
        {
            Check.That(r.Phase is "received" or "opened", "Thông báo chưa hợp lệ.");
            var installation = Security.Hash(r.InstallationId);
            var row = await db.PushDeliveries.SingleOrDefaultAsync(x => x.NoticeId == r.NoticeId && db.PushRegistrations.Any(p => p.Id == x.RegistrationId && p.InstallationHash == installation && p.UserId == a.UserId) && db.Notifications.Any(n => n.Id == x.NoticeId && n.ReceiverId == a.UserId));
            if (row != null)
            {
                row.ReceivedAt ??= DateTimeOffset.UtcNow;
                if (r.Phase == "opened")
                    row.OpenedAt ??= DateTimeOffset.UtcNow;
                await db.SaveChangesAsync();
            }
            return Results.NoContent();
        });
    }
}
public sealed class PushDelivery(IServiceScopeFactory scopes, ILogger<PushDelivery> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        using var timer = new PeriodicTimer(TimeSpan.FromSeconds(5));
        while (await timer.WaitForNextTickAsync(stoppingToken))
        {
            try
            {
                using var scope = scopes.CreateScope();
                var transport = scope.ServiceProvider.GetRequiredService<IPushTransport>();
                if (!transport.Configured)
                    continue;
                var db = scope.ServiceProvider.GetRequiredService<AppDb>();
                var protection = scope.ServiceProvider.GetRequiredService<PushTokenProtection>();
                foreach (var n in await db.Notifications.Where(x => x.PushQueuedAt == null).OrderBy(x => x.CreatedAt).Take(100).ToListAsync(stoppingToken))
                {
                    var user = await db.Users.FindAsync([n.ReceiverId], stoppingToken);
                    if (user is { Active: true })
                    foreach (var registration in await db.PushRegistrations.Where(x => x.Active && x.UserId == user.Id && x.SecurityStamp == user.SecurityStamp).ToListAsync(stoppingToken))
                        if (!await db.PushDeliveries.AnyAsync(x => x.NoticeId == n.Id && x.RegistrationId == registration.Id, stoppingToken))
                            db.PushDeliveries.Add(new PushDeliveryRow { NoticeId = n.Id, RegistrationId = registration.Id });
                    n.PushQueuedAt = DateTimeOffset.UtcNow;
                }
                await db.SaveChangesAsync(stoppingToken);
                // A crashed/ambiguous submission is not blindly repeated.
                await db.PushDeliveries.Where(x => x.State == "Sending" && x.NextAttemptAt < DateTimeOffset.UtcNow.AddMinutes(-2)).ExecuteUpdateAsync(s => s.SetProperty(x => x.State, "Unknown"), stoppingToken);
                foreach (var row in await db.PushDeliveries.Where(x => x.State == "Pending" && x.NextAttemptAt <= DateTimeOffset.UtcNow).OrderBy(x => x.CreatedAt).Take(30).ToListAsync(stoppingToken))
                {
                    var n = await db.Notifications.FindAsync([row.NoticeId], stoppingToken);
                    var registration = await db.PushRegistrations.FindAsync([row.RegistrationId], stoppingToken);
                    var user = registration == null ? null : await db.Users.FindAsync([registration.UserId], stoppingToken);
                    if (n == null || registration is not { Active: true } || user is not { Active: true } || n.ReceiverId != user.Id || registration.SecurityStamp != user.SecurityStamp)
                    {
                        row.State = "Cancelled";
                        await db.SaveChangesAsync(stoppingToken);
                        continue;
                    }
                    if (await db.PushDeliveries.Where(x => x.Id == row.Id && x.State == "Pending").ExecuteUpdateAsync(s => s.SetProperty(x => x.State, "Sending").SetProperty(x => x.NextAttemptAt, DateTimeOffset.UtcNow), stoppingToken) == 0)
                        continue;
                    row.Attempts++;
                    try
                    {
                        var result = await transport.Send(protection.Unprotect(registration.ProtectedToken), n.Id, Security.Hash(user.Id + ":" + user.SecurityStamp), stoppingToken);
                        row.State = result.State;
                        row.ProviderMessageId = result.MessageId;
                        if (result.State == "InvalidToken")
                            registration.Active = false;
                        if (result.State == "Retry")
                        {
                            row.State = row.Attempts < 5 ? "Pending" : "NeedsReview";
                            row.NextAttemptAt = DateTimeOffset.UtcNow.AddSeconds(30 * Math.Pow(2, row.Attempts));
                        }
                    }
                    catch (Exception e) when (!stoppingToken.IsCancellationRequested) { row.State = "Unknown"; logger.LogWarning("Push submission uncertain for {DeliveryId}: {ErrorType}", row.Id, e.GetType().Name); }
                    db.Entry(row).Property(x => x.State).IsModified = true;
                    await db.SaveChangesAsync(stoppingToken);
                }
            }
            catch (Exception e) when (!stoppingToken.IsCancellationRequested) { logger.LogWarning("Push queue unavailable: {ErrorType}", e.GetType().Name); }
        }
    }
}
