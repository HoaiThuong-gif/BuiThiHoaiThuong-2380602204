using Microsoft.EntityFrameworkCore;

namespace NhomBar;

public abstract class Row
{
    public Guid Id { get; set; } = Guid.NewGuid(); public DateTimeOffset CreatedAt { get; set; } = DateTimeOffset.UtcNow;
}
public class User : Row
{
    public bool DeviceOnly
    {
        get; set;
    }
    public string FullName { get; set; } = ""; public string Email { get; set; } = "";
    public string PasswordHash { get; set; } = ""; public string Role { get; set; } = "Parent";
    public string? PhoneNumber
    {
        get; set;
    }
    public bool EmailVerified
    {
        get; set;
    }
    public bool SmsAlertsEnabled
    {
        get; set;
    }
    public bool EmailReportsEnabled
    {
        get; set;
    }
    public bool Active { get; set; } = true; public string SecurityStamp { get; set; } = Guid.NewGuid().ToString();
    public DateTimeOffset UpdatedAt { get; set; } = DateTimeOffset.UtcNow;
}
public class Family : Row
{
    public string FamilyName { get; set; } = ""; public Guid CreatedBy
    {
        get; set;
    }
}
public class FamilyMember : Row
{
    public Guid FamilyId
    {
        get; set;
    }
    public Guid UserId
    {
        get; set;
    }
    public string Relationship { get; set; } = "Parent";
}
public class ChildProfile : Row
{
    public string? Nickname
    {
        get; set;
    }
    public byte[]? AvatarBytes
    {
        get; set;
    }
    public Guid FamilyId
    {
        get; set;
    }
    public Guid? UserId
    {
        get; set;
    }
    public string FullName { get; set; } = ""; public DateOnly? DateOfBirth
    {
        get; set;
    }
    public string? AvatarUrl
    {
        get; set;
    }
}
public class Device : Row
{
    public Guid ChildId
    {
        get; set;
    }
    public string DeviceName { get; set; } = ""; public string DeviceModel { get; set; } = ""; public string AndroidVersion { get; set; } = ""; public DateTimeOffset? LastOnlineAt
    {
        get; set;
    }
    public bool Linked { get; set; } = true; public bool DeviceOwner
    {
        get; set;
    }
    public string? RecoveryHash
    {
        get; set;
    }
    public long RecoveryVersion
    {
        get; set;
    }
    public DateTimeOffset? ReleaseRequestedUntil
    {
        get; set;
    }
}
public class PairingRequest : Row
{
    public Guid ParentId
    {
        get; set;
    }
    public Guid ChildId
    {
        get; set;
    }
    public string TokenHash { get; set; } = ""; public DateTimeOffset ExpiresAt
    {
        get; set;
    }
    public DateTimeOffset? UsedAt
    {
        get; set;
    }
}
public class DeviceEnrollment : Row
{
    public Guid PairingRequestId
    {
        get; set;
    }
    public string ClaimHash { get; set; } = "";
    public string InstallationHash { get; set; } = "";
    public string VerificationCode { get; set; } = "";
    public string DeviceName { get; set; } = "";
    public string DeviceModel { get; set; } = "";
    public string AndroidVersion { get; set; } = "";
    public string Status { get; set; } = "Pending";
    public DateTimeOffset ExpiresAt
    {
        get; set;
    }
    public DateTimeOffset? ConsumedAt
    {
        get; set;
    }
    public Guid? DeviceId
    {
        get; set;
    }
}
public class ScreenTimeRule : Row
{
    public Guid ChildId
    {
        get; set;
    }
    public int DailyLimitMinutes { get; set; } = 120; public TimeOnly StartTime { get; set; } = new(7, 0); public TimeOnly EndTime { get; set; } = new(21, 0); public bool StrictMode
    {
        get; set;
    }
    public bool AllowExtensionRequest { get; set; } = true; public bool IsEnabled { get; set; } = true; public long Version { get; set; } = 1; public string WarningMinutes { get; set; } = "30,15,5"; public string? VoiceName
    {
        get; set;
    }
}
public class AppUsageRecord : Row
{
    public Guid DeviceId
    {
        get; set;
    }
    public string PackageName { get; set; } = ""; public string AppName { get; set; } = ""; public DateTimeOffset StartedAt
    {
        get; set;
    }
    public DateTimeOffset EndedAt
    {
        get; set;
    }
    public int DurationSeconds
    {
        get; set;
    }
}
public class DailyUsageSummary : Row
{
    public Guid DeviceId
    {
        get; set;
    }
    public DateOnly UsageDate
    {
        get; set;
    }
    public int TotalSeconds
    {
        get; set;
    }
    public DateTimeOffset LastSyncedAt
    {
        get; set;
    }
}
public class TimeExtensionRequest : Row
{
    public Guid ChildId
    {
        get; set;
    }
    public int RequestedMinutes
    {
        get; set;
    }
    public string Reason { get; set; } = ""; public string Status { get; set; } = "Pending"; public string? ParentResponse
    {
        get; set;
    }
    public DateTimeOffset? RespondedAt
    {
        get; set;
    }
    public DateOnly UsageDate
    {
        get; set;
    }
}
public class DeviceLockState : Row
{
    public Guid DeviceId
    {
        get; set;
    }
    public bool IsLocked
    {
        get; set;
    }
    public string LockReason { get; set; } = ""; public DateTimeOffset? LockedAt
    {
        get; set;
    }
    public DateTimeOffset? UnlockAt
    {
        get; set;
    }
    public long PolicyVersion { get; set; } = 1; public long AcknowledgedVersion
    {
        get; set;
    }
}
public class ParentPin : Row
{
    public Guid ParentId
    {
        get; set;
    }
    public string PinHash { get; set; } = ""; public int Attempts
    {
        get; set;
    }
    public DateTimeOffset? BlockedUntil
    {
        get; set;
    }
}
public class LocationUpdate : Row
{
    public Guid DeviceId
    {
        get; set;
    }
    public double Latitude
    {
        get; set;
    }
    public double Longitude
    {
        get; set;
    }
    public double Accuracy
    {
        get; set;
    }
    public DateTimeOffset RecordedAt
    {
        get; set;
    }
}
public class SafePlace : Row
{
    public Guid ChildId
    {
        get; set;
    }
    public string PlaceName { get; set; } = ""; public double Latitude
    {
        get; set;
    }
    public double Longitude
    {
        get; set;
    }
    public int RadiusMeters
    {
        get; set;
    }
}
public class NoiseReport : Row
{
    public Guid ChildId
    {
        get; set;
    }
    public double AverageLevel
    {
        get; set;
    }
    public double MaximumLevel
    {
        get; set;
    }
    public DateTimeOffset RecordedAt
    {
        get; set;
    }
}
public class Notice : Row
{
    public DateTimeOffset? PushQueuedAt
    {
        get; set;
    }
    public string EmailState { get; set; } = "NotRequested";
    public DateOnly? ReportDate
    {
        get; set;
    }
    public Guid ReceiverId
    {
        get; set;
    }
    public string Title { get; set; } = ""; public string Content { get; set; } = ""; public string Type { get; set; } = "Info"; public bool IsRead
    {
        get; set;
    }
    public string SmsState { get; set; } = "NotRequested"; public DateTimeOffset? SmsSentAt
    {
        get; set;
    }
}
public class AuditLog : Row
{
    public Guid ActorId
    {
        get; set;
    }
    public string Action { get; set; } = ""; public string EntityType { get; set; } = ""; public string EntityId { get; set; } = "";
}
public class RefreshToken : Row
{
    public Guid? DeviceId
    {
        get; set;
    }
    public Guid UserId
    {
        get; set;
    }
    public string TokenHash { get; set; } = ""; public DateTimeOffset ExpiresAt
    {
        get; set;
    }
    public DateTimeOffset? RevokedAt
    {
        get; set;
    }
}
public class EmailOtpChallenge : Row
{
    public Guid UserId
    {
        get; set;
    }
    public string OtpHash { get; set; } = ""; public string Purpose { get; set; } = "login"; public DateTimeOffset ExpiresAt
    {
        get; set;
    }
    public int AttemptCount
    {
        get; set;
    }
    public DateTimeOffset? VerifiedAt
    {
        get; set;
    }
}

public class AppDb(DbContextOptions<AppDb> options) : DbContext(options)
{
    public DbSet<DeviceEnrollment> DeviceEnrollments => Set<DeviceEnrollment>();
    public DbSet<PushRegistration> PushRegistrations => Set<PushRegistration>();
    public DbSet<PushDeliveryRow> PushDeliveries => Set<PushDeliveryRow>();
    public DbSet<AppClassification> AppClassifications => Set<AppClassification>();
    public DbSet<User> Users => Set<User>(); public DbSet<Family> Families => Set<Family>(); public DbSet<FamilyMember> FamilyMembers => Set<FamilyMember>();
    public DbSet<ChildProfile> Children => Set<ChildProfile>(); public DbSet<Device> Devices => Set<Device>(); public DbSet<PairingRequest> PairingRequests => Set<PairingRequest>();
    public DbSet<ScreenTimeRule> ScreenTimeRules => Set<ScreenTimeRule>(); public DbSet<AppUsageRecord> AppUsageRecords => Set<AppUsageRecord>(); public DbSet<DailyUsageSummary> DailyUsageSummaries => Set<DailyUsageSummary>();
    public DbSet<TimeExtensionRequest> ExtensionRequests => Set<TimeExtensionRequest>(); public DbSet<DeviceLockState> DeviceLockStates => Set<DeviceLockState>(); public DbSet<ParentPin> ParentPins => Set<ParentPin>();
    public DbSet<LocationUpdate> Locations => Set<LocationUpdate>(); public DbSet<SafePlace> SafePlaces => Set<SafePlace>(); public DbSet<NoiseReport> NoiseReports => Set<NoiseReport>();
    public DbSet<Notice> Notifications => Set<Notice>(); public DbSet<AuditLog> AuditLogs => Set<AuditLog>(); public DbSet<RefreshToken> RefreshTokens => Set<RefreshToken>(); public DbSet<EmailOtpChallenge> EmailOtpChallenges => Set<EmailOtpChallenge>();
    protected override void OnModelCreating(ModelBuilder b)
    {
        b.Entity<DeviceEnrollment>().HasOne<PairingRequest>().WithMany().HasForeignKey(x => x.PairingRequestId).OnDelete(DeleteBehavior.Restrict);
        b.Entity<DeviceEnrollment>().HasOne<Device>().WithMany().HasForeignKey(x => x.DeviceId).OnDelete(DeleteBehavior.Restrict);
        b.Entity<DeviceEnrollment>().HasIndex(x => x.PairingRequestId).IsUnique();
        b.Entity<DeviceEnrollment>().HasIndex(x => x.ClaimHash).IsUnique();
        b.Entity<DeviceEnrollment>().Property(x => x.Status).IsConcurrencyToken();
        b.Entity<DeviceEnrollment>().Property(x => x.ConsumedAt).IsConcurrencyToken();
        b.Entity<PairingRequest>().Property(x => x.UsedAt).IsConcurrencyToken();
        b.Entity<PushRegistration>().HasOne<User>().WithMany().HasForeignKey(x => x.UserId).OnDelete(DeleteBehavior.Restrict);
        b.Entity<PushRegistration>().HasIndex(x => x.TokenHash).IsUnique();
        b.Entity<PushRegistration>().Property(x => x.ProtectedToken).HasMaxLength(8192);
        b.Entity<PushRegistration>().HasIndex(x => x.InstallationHash).IsUnique();
        b.Entity<PushDeliveryRow>().HasOne<Notice>().WithMany().HasForeignKey(x => x.NoticeId).OnDelete(DeleteBehavior.Cascade);
        b.Entity<PushDeliveryRow>().HasOne<PushRegistration>().WithMany().HasForeignKey(x => x.RegistrationId).OnDelete(DeleteBehavior.Restrict);
        b.Entity<PushDeliveryRow>().HasIndex(x => new { x.NoticeId, x.RegistrationId }).IsUnique();
        b.Entity<Notice>().Property(x => x.PushQueuedAt).IsConcurrencyToken();
        b.Entity<AppClassification>().HasOne<ChildProfile>().WithMany().HasForeignKey(x => x.ChildId).OnDelete(DeleteBehavior.Restrict);
        b.Entity<AppClassification>().Property(x => x.PackageName).HasMaxLength(256);
        b.Entity<AppClassification>().HasIndex(x => new { x.ChildId, x.PackageName }).IsUnique();
        b.Entity<ScreenTimeRule>().Property(x => x.WarningMinutes).HasDefaultValue("30,15,5");
        b.Entity<Notice>().Property(x => x.SmsState).HasDefaultValue("NotRequested");
        b.Entity<Notice>().HasIndex(x => new { x.ReceiverId, x.ReportDate }).IsUnique().HasFilter("[ReportDate] IS NOT NULL");
        foreach (var entity in b.Model.GetEntityTypes())
            foreach (var p in entity.GetProperties().Where(p => p.ClrType == typeof(string)))
                if (p.GetMaxLength() == null)
                    p.SetMaxLength(1000);
        b.Entity<User>().Property(x => x.Email).HasMaxLength(254);
        b.Entity<User>().HasIndex(x => x.Email).IsUnique();
        b.Entity<Family>().HasOne<User>().WithMany().HasForeignKey(x => x.CreatedBy).OnDelete(DeleteBehavior.Restrict);
        b.Entity<FamilyMember>().HasOne<Family>().WithMany().HasForeignKey(x => x.FamilyId).OnDelete(DeleteBehavior.Restrict);
        b.Entity<FamilyMember>().HasOne<User>().WithMany().HasForeignKey(x => x.UserId).OnDelete(DeleteBehavior.Restrict);
        b.Entity<FamilyMember>().HasIndex(x => new { x.FamilyId, x.UserId }).IsUnique();
        b.Entity<ChildProfile>().HasOne<Family>().WithMany().HasForeignKey(x => x.FamilyId).OnDelete(DeleteBehavior.Restrict);
        b.Entity<ChildProfile>().HasOne<User>().WithMany().HasForeignKey(x => x.UserId).OnDelete(DeleteBehavior.Restrict);
        b.Entity<ChildProfile>().HasIndex(x => x.UserId).IsUnique().HasFilter("[UserId] IS NOT NULL");
        b.Entity<Device>().HasOne<ChildProfile>().WithMany().HasForeignKey(x => x.ChildId).OnDelete(DeleteBehavior.Restrict);
        b.Entity<Device>().Property(x => x.RecoveryVersion).IsConcurrencyToken();
        b.Entity<PairingRequest>().HasOne<ChildProfile>().WithMany().HasForeignKey(x => x.ChildId).OnDelete(DeleteBehavior.Restrict);
        b.Entity<PairingRequest>().HasOne<User>().WithMany().HasForeignKey(x => x.ParentId).OnDelete(DeleteBehavior.Restrict);
        b.Entity<PairingRequest>().HasIndex(x => x.TokenHash).IsUnique();
        b.Entity<ScreenTimeRule>().HasOne<ChildProfile>().WithMany().HasForeignKey(x => x.ChildId).OnDelete(DeleteBehavior.Restrict);
        b.Entity<ScreenTimeRule>().HasIndex(x => x.ChildId).IsUnique();
        b.Entity<ScreenTimeRule>().Property(x => x.Version).IsConcurrencyToken();
        b.Entity<AppUsageRecord>().HasOne<Device>().WithMany().HasForeignKey(x => x.DeviceId).OnDelete(DeleteBehavior.Restrict);
        b.Entity<AppUsageRecord>().Property(x => x.PackageName).HasMaxLength(256);
        b.Entity<AppUsageRecord>().HasIndex(x => new { x.DeviceId, x.PackageName, x.StartedAt, x.EndedAt }).IsUnique();
        b.Entity<DailyUsageSummary>().HasOne<Device>().WithMany().HasForeignKey(x => x.DeviceId).OnDelete(DeleteBehavior.Restrict);
        b.Entity<DailyUsageSummary>().HasIndex(x => new { x.DeviceId, x.UsageDate }).IsUnique();
        b.Entity<TimeExtensionRequest>().HasOne<ChildProfile>().WithMany().HasForeignKey(x => x.ChildId).OnDelete(DeleteBehavior.Restrict);
        b.Entity<TimeExtensionRequest>().Property(x => x.Status).IsConcurrencyToken();
        b.Entity<DeviceLockState>().HasOne<Device>().WithMany().HasForeignKey(x => x.DeviceId).OnDelete(DeleteBehavior.Restrict);
        b.Entity<DeviceLockState>().HasIndex(x => x.DeviceId).IsUnique();
        b.Entity<DeviceLockState>().Property(x => x.PolicyVersion).IsConcurrencyToken();
        b.Entity<ParentPin>().HasOne<User>().WithMany().HasForeignKey(x => x.ParentId).OnDelete(DeleteBehavior.Restrict);
        b.Entity<ParentPin>().HasIndex(x => x.ParentId).IsUnique();
        b.Entity<ParentPin>().Property(x => x.Attempts).IsConcurrencyToken();
        b.Entity<LocationUpdate>().HasOne<Device>().WithMany().HasForeignKey(x => x.DeviceId).OnDelete(DeleteBehavior.Restrict);
        b.Entity<LocationUpdate>().HasIndex(x => new { x.DeviceId, x.RecordedAt });
        b.Entity<SafePlace>().HasOne<ChildProfile>().WithMany().HasForeignKey(x => x.ChildId).OnDelete(DeleteBehavior.Restrict);
        b.Entity<NoiseReport>().HasOne<ChildProfile>().WithMany().HasForeignKey(x => x.ChildId).OnDelete(DeleteBehavior.Restrict);
        b.Entity<Notice>().HasOne<User>().WithMany().HasForeignKey(x => x.ReceiverId).OnDelete(DeleteBehavior.Restrict);
        b.Entity<Notice>().HasIndex(x => new { x.ReceiverId, x.CreatedAt });
        b.Entity<AuditLog>().HasOne<User>().WithMany().HasForeignKey(x => x.ActorId).OnDelete(DeleteBehavior.Restrict);
        b.Entity<RefreshToken>().HasOne<User>().WithMany().HasForeignKey(x => x.UserId).OnDelete(DeleteBehavior.Restrict);
        b.Entity<RefreshToken>().HasOne<Device>().WithMany().HasForeignKey(x => x.DeviceId).OnDelete(DeleteBehavior.Restrict);
        b.Entity<RefreshToken>().HasIndex(x => x.TokenHash).IsUnique();
        b.Entity<RefreshToken>().Property(x => x.RevokedAt).IsConcurrencyToken();
        b.Entity<EmailOtpChallenge>().HasOne<User>().WithMany().HasForeignKey(x => x.UserId).OnDelete(DeleteBehavior.Restrict);
        b.Entity<EmailOtpChallenge>().Property(x => x.AttemptCount).IsConcurrencyToken();
        b.Entity<EmailOtpChallenge>().Property(x => x.VerifiedAt).IsConcurrencyToken();
    }
}
