using System.Net;
using System.Security.Cryptography;
using System.Text.Json;
using Microsoft.Data.SqlClient;
using Microsoft.EntityFrameworkCore;
namespace NhomBar;

public static class ProductionConfiguration
{
    public static bool PublicOrigin(string? value) => Uri.TryCreate(value, UriKind.Absolute, out var uri) && uri.Scheme == "https" && uri.IsDefaultPort && uri.AbsolutePath == "/" && uri.UserInfo == "" && uri.Query == "" && uri.Fragment == "" && uri.Host.Contains('.') && !IPAddress.TryParse(uri.Host, out _) && !new[] { "localhost", ".localhost", ".local", ".lan", ".internal", ".test", ".invalid", ".localdomain" }.Any(s => uri.Host.EndsWith(s, StringComparison.OrdinalIgnoreCase));
    public static void Validate(IConfiguration c)
    {
        if (!PublicOrigin(c["Deployment:PublicUrl"]))
            throw new InvalidOperationException("Production requires Deployment__PublicUrl with a public HTTPS hostname.");
        if (string.IsNullOrWhiteSpace(c["AllowedHosts"]) || c["AllowedHosts"]!.Contains('*'))
            throw new InvalidOperationException("Set AllowedHosts to the deployed API hostname.");
        var sql = new SqlConnectionStringBuilder(c.GetConnectionString("SqlServer"));
        if (sql.TrustServerCertificate || sql.Encrypt.ToString() is "False" or "Optional" || sql.IntegratedSecurity || sql.DataSource is "." or "localhost" || sql.DataSource.Contains("(localdb)", StringComparison.OrdinalIgnoreCase))
            throw new InvalidOperationException("Production SQL requires remote SQL Server, encryption and certificate validation.");
        if (!BrevoEmail.Configured(c))
            throw new InvalidOperationException("Configure verified Brevo sender and backend API key.");
        using var credentials = JsonDocument.Parse(!string.IsNullOrWhiteSpace(c["Push:Firebase:ServiceAccountJson"]) ? c["Push:Firebase:ServiceAccountJson"]! : File.ReadAllText(c["Push:Firebase:ServiceAccountPath"] ?? throw new InvalidOperationException("Configure Firebase service account on the backend.")));
        var root = credentials.RootElement;
        if (root.GetProperty("type").GetString() != "service_account" || string.IsNullOrWhiteSpace(root.GetProperty("project_id").GetString()))
            throw new InvalidOperationException("Invalid push service account.");
        using var rsa = RSA.Create();
        rsa.ImportFromPem(root.GetProperty("private_key").GetString());
    }
    public static void MapDeploymentHealth(this WebApplication app)
    {
        app.MapGet("/health/live", () => Results.Ok(new { status = "alive" }));
        app.MapGet("/health/deployment", async (AppDb db, IConfiguration c, IPushTransport push) =>
        {
            var connected = await db.Database.CanConnectAsync();
            var schemaCurrent = connected && !(await db.Database.GetPendingMigrationsAsync()).Any();
            string? firebaseProject = null;
            if (push is FirebasePush firebase && firebase.Configured)
            {
                using var credentials = firebase.Credentials();
                firebaseProject = credentials.RootElement.GetProperty("project_id").GetString();
            }
            return Results.Ok(new
            {
                environment = app.Environment.EnvironmentName,
                database = connected,
                schemaCurrent,
                emailConfigured = BrevoEmail.Configured(c),
                pushConfigured = push.Configured,
                firebaseProjectId = firebaseProject,
                publicUrl = c["Deployment:PublicUrl"],
                version = typeof(ApiHost).Assembly.GetName().Version?.ToString()
            });
        });
    }
}
