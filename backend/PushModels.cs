namespace NhomBar;

public class PushRegistration : Row
{
    public Guid UserId
    {
        get; set;
    }
    public string SecurityStamp { get; set; } = "";
    public string TokenHash { get; set; } = "";
    public string ProtectedToken { get; set; } = "";
    public string InstallationHash { get; set; } = "";
    public bool Active { get; set; } = true;
    public DateTimeOffset LastSeenAt { get; set; } = DateTimeOffset.UtcNow;
}
public class PushDeliveryRow : Row
{
    public Guid NoticeId
    {
        get; set;
    }
    public Guid RegistrationId
    {
        get; set;
    }
    public string State { get; set; } = "Pending";
    public int Attempts
    {
        get; set;
    }
    public DateTimeOffset NextAttemptAt { get; set; } = DateTimeOffset.UtcNow;
    public DateTimeOffset? ReceivedAt
    {
        get; set;
    }
    public DateTimeOffset? OpenedAt
    {
        get; set;
    }
    public string? ProviderMessageId
    {
        get; set;
    }
}
