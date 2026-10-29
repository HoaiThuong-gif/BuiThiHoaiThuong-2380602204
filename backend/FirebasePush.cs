using System.IdentityModel.Tokens.Jwt;
using System.Net;
using System.Net.Http.Headers;
using System.Net.Http.Json;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.IdentityModel.Tokens;

namespace NhomBar;

public record PushResult(string State, string? MessageId = null);
public interface IPushTransport
{
    bool Configured
    {
        get;
    }
    Task<PushResult> Send(string token, Guid noticeId, string binding, CancellationToken cancellationToken);
}
public sealed class PushTokenProtection(IConfiguration config)
{
    private byte[] Key => HMACSHA256.HashData(Encoding.UTF8.GetBytes(config["Jwt:Key"]!), Encoding.UTF8.GetBytes("NhomBar push registration v1"));
    public string Protect(string token)
    {
        var data = Encoding.UTF8.GetBytes(token);
        var nonce = RandomNumberGenerator.GetBytes(12);
        var tag = new byte[16];
        var encrypted = new byte[data.Length];
        using var aes = new AesGcm(Key, 16);
        aes.Encrypt(nonce, data, encrypted, tag);
        return Convert.ToBase64String(nonce.Concat(tag).Concat(encrypted).ToArray());
    }
    public string Unprotect(string value)
    {
        var bytes = Convert.FromBase64String(value);
        if (bytes.Length < 29)
            throw new CryptographicException();
        var data = new byte[bytes.Length - 28];
        using var aes = new AesGcm(Key, 16);
        aes.Decrypt(bytes.AsSpan(0, 12), bytes.AsSpan(28), bytes.AsSpan(12, 16), data);
        return Encoding.UTF8.GetString(data);
    }
}
public sealed class FirebasePush(HttpClient http, IConfiguration config) : IPushTransport
{
    private readonly SemaphoreSlim gate = new(1, 1);
    private string? accessToken;
    private DateTimeOffset validUntil;
    public bool Configured => !string.IsNullOrWhiteSpace(config["Push:Firebase:ServiceAccountJson"]) || File.Exists(config["Push:Firebase:ServiceAccountPath"]);
    public JsonDocument Credentials() => JsonDocument.Parse(!string.IsNullOrWhiteSpace(config["Push:Firebase:ServiceAccountJson"]) ? config["Push:Firebase:ServiceAccountJson"]! : File.ReadAllText(config["Push:Firebase:ServiceAccountPath"]!));
    private async Task<string> AccessToken(CancellationToken ct)
    {
        await gate.WaitAsync(ct);
        try
        {
            if (accessToken != null && validUntil > DateTimeOffset.UtcNow.AddMinutes(2))
                return accessToken;
            using var credentials = Credentials();
            var root = credentials.RootElement;
            Check.That(root.GetProperty("type").GetString() == "service_account", "Thông báo hiện chưa sẵn sàng.", 503);
            using var rsa = RSA.Create();
            rsa.ImportFromPem(root.GetProperty("private_key").GetString());
            var now = DateTimeOffset.UtcNow;
            // The RSA handle is disposed after signing; never cache a provider holding it.
            var signing = new SigningCredentials(new RsaSecurityKey(rsa), SecurityAlgorithms.RsaSha256) { CryptoProviderFactory = new CryptoProviderFactory { CacheSignatureProviders = false } };
            var jwt = new JwtSecurityToken(root.GetProperty("client_email").GetString(), "https://oauth2.googleapis.com/token", [new Claim("scope", "https://www.googleapis.com/auth/firebase.messaging"), new Claim(JwtRegisteredClaimNames.Iat, now.ToUnixTimeSeconds().ToString(), ClaimValueTypes.Integer64)], now.UtcDateTime, now.AddMinutes(50).UtcDateTime, signing);
            using var response = await http.PostAsync("https://oauth2.googleapis.com/token", new FormUrlEncodedContent(new Dictionary<string, string> { { "grant_type", "urn:ietf:params:oauth:grant-type:jwt-bearer" }, { "assertion", new JwtSecurityTokenHandler().WriteToken(jwt) } }), ct);
            if (!response.IsSuccessStatusCode)
                throw new HttpRequestException("Push authorization unavailable");
            using var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync(ct));
            accessToken = body.RootElement.GetProperty("access_token").GetString()!;
            validUntil = now.AddSeconds(Math.Min(3000, body.RootElement.GetProperty("expires_in").GetInt32()));
            return accessToken;
        }
        finally { gate.Release(); }
    }
    public async Task<PushResult> Send(string token, Guid noticeId, string binding, CancellationToken cancellationToken)
    {
        using var credentials = Credentials();
        var project = credentials.RootElement.GetProperty("project_id").GetString();
        // Generic lock-screen content; family information is fetched through the authenticated API.
        using var request = new HttpRequestMessage(HttpMethod.Post, $"https://fcm.googleapis.com/v1/projects/{Uri.EscapeDataString(project!)}/messages:send");
        request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", await AccessToken(cancellationToken));
        request.Content = JsonContent.Create(new
        {
            message = new
            {
                token,
                data = new
                {
                    noticeId = noticeId.ToString(),
                    binding
                },
                android = new
                {
                    priority = "HIGH",
                    ttl = "86400s"
                }
            }
        });
        using var response = await http.SendAsync(request, cancellationToken);
        if (response.StatusCode == HttpStatusCode.Unauthorized)
        {
            accessToken = null;
            return new("NeedsReview");
        }
        if (response.StatusCode == HttpStatusCode.TooManyRequests)
            return new("Retry");
        if (response.IsSuccessStatusCode)
        {
            using var body = JsonDocument.Parse(await response.Content.ReadAsStringAsync(cancellationToken));
            return body.RootElement.TryGetProperty("name", out var id) && id.ValueKind == JsonValueKind.String && !string.IsNullOrWhiteSpace(id.GetString()) ? new("Accepted", id.GetString()) : new("Unknown");
        }
        if (response.StatusCode == HttpStatusCode.NotFound)
        {
            var body = await response.Content.ReadAsStringAsync(cancellationToken);
            if (body.Contains("UNREGISTERED", StringComparison.Ordinal))
                return new("InvalidToken");
        }
        return new("NeedsReview");
    }
}
