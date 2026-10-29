using Microsoft.EntityFrameworkCore;

namespace NhomBar;

public interface INoticeEmail
{
    Task Send(string email, string title, string content, CancellationToken cancellationToken);
}
public static class DailyReports
{
    public static async Task Queue(AppDb db, DateOnly day, CancellationToken cancellationToken = default)
    {
        var parents = await db.Users.Where(x => x.Active && x.EmailVerified && x.Role == "Parent" && x.EmailReportsEnabled).ToListAsync(cancellationToken);
        foreach (var parent in parents)
        {
            if (await db.Notifications.AnyAsync(x => x.ReceiverId == parent.Id && x.ReportDate == day, cancellationToken))
                continue;
            var children = await db.Children.Where(c => db.FamilyMembers.Any(m => m.UserId == parent.Id && m.FamilyId == c.FamilyId && m.Relationship == "Parent")).ToListAsync(cancellationToken);
            var lines = new List<string>();
            foreach (var child in children)
            {
                var reports = await db.DailyUsageSummaries.Where(s => s.UsageDate == day && db.Devices.Any(d => d.Id == s.DeviceId && d.ChildId == child.Id)).ToListAsync(cancellationToken);
                lines.Add(reports.Count == 0 ? $"{child.FullName}: chưa có báo cáo từ điện thoại." : $"{child.FullName}: đã sử dụng {reports.Sum(s => s.TotalSeconds) / 60} phút.");
            }
            db.Notifications.Add(new Notice { ReceiverId = parent.Id, Title = $"Báo cáo ngày {day:dd/MM/yyyy}", Content = lines.Count == 0 ? "Gia đình chưa có hồ sơ con." : string.Join("\n", lines), Type = "DailyReport", ReportDate = day, EmailState = "Pending" });
        }
        await db.SaveChangesAsync(cancellationToken);
    }
}
public class EmailDelivery(IServiceScopeFactory scopes, IConfiguration configuration, ILogger<EmailDelivery> logger) : BackgroundService
{
    private string? lastReportHour;
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        using var timer = new PeriodicTimer(TimeSpan.FromSeconds(30));
        while (await timer.WaitForNextTickAsync(stoppingToken))
        {
            if (!BrevoEmail.Configured(configuration))
                continue;
            try
            {
                using var scope = scopes.CreateScope();
                var db = scope.ServiceProvider.GetRequiredService<AppDb>();
                var sender = scope.ServiceProvider.GetRequiredService<INoticeEmail>();
                var now = DateTime.UtcNow.AddHours(7);
                var hour = now.ToString("yyyy-MM-dd-HH");
                if (now.Hour >= 7 && hour != lastReportHour)
                {
                    await DailyReports.Queue(db, DateOnly.FromDateTime(now).AddDays(-1), stoppingToken);
                    lastReportHour = hour;
                }
                foreach (var n in await db.Notifications.Where(x => x.EmailState == "Pending").OrderBy(x => x.CreatedAt).Take(10).ToListAsync(stoppingToken))
                {
                    var u = await db.Users.FindAsync([n.ReceiverId], stoppingToken);
                    if (u == null || n.Type == "DailyReport" && (!u.Active || !u.EmailReportsEnabled))
                    {
                        n.EmailState = "Cancelled";
                        await db.SaveChangesAsync(stoppingToken);
                        continue;
                    }
                    var claimed = await db.Notifications.Where(x => x.Id == n.Id && x.EmailState == "Pending").ExecuteUpdateAsync(s => s.SetProperty(x => x.EmailState, "Sending"), stoppingToken);
                    if (claimed == 0)
                        continue;
                    try
                    {
                        await sender.Send(u.Email, n.Title, n.Content, stoppingToken);
                        n.EmailState = "Submitted";
                    }
                    catch (Exception e) { n.EmailState = "NeedsReview"; logger.LogWarning("Email result uncertain for notice {NoticeId}: {ErrorType}", n.Id, e.GetType().Name); }
                    await db.SaveChangesAsync(stoppingToken);
                }
            }
            catch (Exception e) when (!stoppingToken.IsCancellationRequested) { logger.LogWarning("Email queue unavailable: {ErrorType}", e.GetType().Name); }
        }
    }
}
