using System.Net.Http.Headers;
using System.Text;
using Microsoft.EntityFrameworkCore;

namespace NhomBar;
/// <summary>SMS outbox: claim once before sending; ambiguous sends need manual review, never blind retries.</summary>
public class SmsDelivery(IServiceScopeFactory scopes, IConfiguration config, ILogger<SmsDelivery> logger) : BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        using var timer = new PeriodicTimer(TimeSpan.FromSeconds(15));
        while (await timer.WaitForNextTickAsync(stoppingToken))
        {
            if (string.IsNullOrWhiteSpace(config["Twilio:AccountSid"]) || string.IsNullOrWhiteSpace(config["Twilio:AuthToken"]) || string.IsNullOrWhiteSpace(config["Twilio:From"]))
                continue;
            try
            {
                using var scope = scopes.CreateScope();
                var db = scope.ServiceProvider.GetRequiredService<AppDb>();
                var notices = await db.Notifications.Where(x => x.SmsState == "Pending").OrderBy(x => x.CreatedAt).Take(10).ToListAsync(stoppingToken);
                foreach (var n in notices)
                {
                    var u = await db.Users.FindAsync([n.ReceiverId], stoppingToken);
                    if (u is not { Active: true, SmsAlertsEnabled: true } || string.IsNullOrWhiteSpace(u.PhoneNumber))
                    {
                        n.SmsState = "Cancelled";
                        await db.SaveChangesAsync(stoppingToken);
                        continue;
                    }
                    if (await db.Notifications.AnyAsync(x => x.ReceiverId == u.Id && x.SmsSentAt > DateTimeOffset.UtcNow.AddMinutes(-1), stoppingToken))
                        continue;
                    // Compare-and-set prevents two server instances from claiming the same message.
                    var claimed = await db.Notifications.Where(x => x.Id == n.Id && x.SmsState == "Pending").ExecuteUpdateAsync(s => s.SetProperty(x => x.SmsState, "Sending"), stoppingToken);
                    if (claimed == 0)
                        continue;
                    try
                    {
                        using var http = new HttpClient { Timeout = TimeSpan.FromSeconds(20) };
                        http.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Basic", Convert.ToBase64String(Encoding.ASCII.GetBytes($"{config["Twilio:AccountSid"]}:{config["Twilio:AuthToken"]}")));
                        using var response = await http.PostAsync($"https://api.twilio.com/2010-04-01/Accounts/{Uri.EscapeDataString(config["Twilio:AccountSid"]!)}/Messages.json", new FormUrlEncodedContent(new Dictionary<string, string> { { "To", u.PhoneNumber }, { "From", config["Twilio:From"]! }, { "Body", $"NhomBar: {n.Title}. {n.Content}" } }), stoppingToken);
                        n.SmsState = response.IsSuccessStatusCode ? "Sent" : "Failed";
                        if (response.IsSuccessStatusCode)
                            n.SmsSentAt = DateTimeOffset.UtcNow;
                    }
                    catch (Exception e) { n.SmsState = "NeedsReview"; logger.LogWarning("SMS result uncertain for notice {NoticeId}: {ErrorType}", n.Id, e.GetType().Name); }
                    await db.SaveChangesAsync(stoppingToken);
                }
            }
            catch (Exception e) when (!stoppingToken.IsCancellationRequested) { logger.LogWarning("SMS queue unavailable: {ErrorType}", e.GetType().Name); }
        }
    }
}
