using System.Net;
using System.Net.Http.Json;
using System.Text.Json;

namespace NhomBar;

/// <summary>Brevo transactional HTTPS API. No SMTP or automatic delivery retries.</summary>
public sealed class BrevoEmail(HttpClient http, IConfiguration configuration, ILogger<BrevoEmail> logger) : ICodeSender, INoticeEmail
{
    public static bool Configured(IConfiguration configuration) =>
        !string.IsNullOrWhiteSpace(configuration["Email:Brevo:ApiKey"]) &&
        System.Net.Mail.MailAddress.TryCreate(configuration["Email:Brevo:SenderEmail"], out _);

    public Task Send(string email, string code) => Send(email, "Mã xác nhận NhomBar",
        $"Mã xác nhận của bạn là {code}. Mã có hiệu lực trong 5 phút và chỉ dùng một lần. Không chia sẻ mã với bất kỳ ai. Nếu bạn không yêu cầu, hãy bỏ qua thư này.", CancellationToken.None);

    public async Task Send(string email, string title, string content, CancellationToken cancellationToken)
    {
        Check.That(Configured(configuration), "Chưa thể gửi email lúc này. Vui lòng thử lại sau hoặc liên hệ hỗ trợ.", 503);
        using var request = new HttpRequestMessage(HttpMethod.Post, "https://api.brevo.com/v3/smtp/email");
        request.Headers.Add("api-key", configuration["Email:Brevo:ApiKey"]);
        request.Headers.Accept.ParseAdd("application/json");
        request.Content = JsonContent.Create(new
        {
            sender = new
            {
                name = "NhomBar",
                email = configuration["Email:Brevo:SenderEmail"]
            },
            to = new[] { new { email } },
            subject = title,
            textContent = content
        });
        try
        {
            using var response = await http.SendAsync(request, cancellationToken);
            if (response.StatusCode != HttpStatusCode.Created)
            {
                // Never log the body: it may include the recipient, API key or OTP.
                logger.LogWarning("Email provider rejected submission. HTTP {Status}", (int)response.StatusCode);
                throw new AppError(503, response.StatusCode == HttpStatusCode.TooManyRequests
                    ? "Hiện có nhiều yêu cầu gửi email. Vui lòng thử lại sau ít phút."
                    : "Chưa gửi được email. Vui lòng thử lại sau hoặc liên hệ hỗ trợ.");
            }
            using var body = await JsonDocument.ParseAsync(await response.Content.ReadAsStreamAsync(cancellationToken), cancellationToken: cancellationToken);
            Check.That(body.RootElement.TryGetProperty("messageId", out var id) && id.ValueKind == JsonValueKind.String && !string.IsNullOrWhiteSpace(id.GetString()),
                "Chưa xác nhận được yêu cầu gửi email. Vui lòng chờ một phút rồi thử lại.", 503);
            logger.LogInformation("Email provider accepted submission. MessageId {MessageId}", id.GetString());
        }
        catch (Exception e) when (e is HttpRequestException or TaskCanceledException or JsonException)
        {
            logger.LogWarning("Email submission result unavailable: {ErrorType}", e.GetType().Name);
            throw new AppError(503, "Chưa xác nhận được yêu cầu gửi email. Vui lòng chờ một phút rồi thử lại.");
        }
    }
}
