IF OBJECT_ID(N'[__EFMigrationsHistory]') IS NULL
BEGIN
    CREATE TABLE [__EFMigrationsHistory] (
        [MigrationId] nvarchar(150) NOT NULL,
        [ProductVersion] nvarchar(32) NOT NULL,
        CONSTRAINT [PK___EFMigrationsHistory] PRIMARY KEY ([MigrationId])
    );
END;
GO

BEGIN TRANSACTION;
GO

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261029031035_InitialSchema'
)
BEGIN
    CREATE TABLE [Users] (
        [Id] uniqueidentifier NOT NULL,
        [FullName] nvarchar(1000) NOT NULL,
        [Email] nvarchar(254) NOT NULL,
        [PasswordHash] nvarchar(1000) NOT NULL,
        [Role] nvarchar(1000) NOT NULL,
        [PhoneNumber] nvarchar(1000) NULL,
        [EmailVerified] bit NOT NULL,
        [Active] bit NOT NULL,
        [SecurityStamp] nvarchar(1000) NOT NULL,
        [UpdatedAt] datetimeoffset NOT NULL,
        [CreatedAt] datetimeoffset NOT NULL,
        CONSTRAINT [PK_Users] PRIMARY KEY ([Id])
    );
END;
GO

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261029031035_InitialSchema'
)
BEGIN
    CREATE TABLE [AuditLogs] (
        [Id] uniqueidentifier NOT NULL,
        [ActorId] uniqueidentifier NOT NULL,
        [Action] nvarchar(1000) NOT NULL,
        [EntityType] nvarchar(1000) NOT NULL,
        [EntityId] nvarchar(1000) NOT NULL,
        [CreatedAt] datetimeoffset NOT NULL,
        CONSTRAINT [PK_AuditLogs] PRIMARY KEY ([Id]),
        CONSTRAINT [FK_AuditLogs_Users_ActorId] FOREIGN KEY ([ActorId]) REFERENCES [Users] ([Id]) ON DELETE NO ACTION
    );
END;
GO

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261029031035_InitialSchema'
)
BEGIN
    CREATE TABLE [EmailOtpChallenges] (
        [Id] uniqueidentifier NOT NULL,
        [UserId] uniqueidentifier NOT NULL,
        [OtpHash] nvarchar(1000) NOT NULL,
        [Purpose] nvarchar(1000) NOT NULL,
        [ExpiresAt] datetimeoffset NOT NULL,
        [AttemptCount] int NOT NULL,
        [VerifiedAt] datetimeoffset NULL,
        [CreatedAt] datetimeoffset NOT NULL,
        CONSTRAINT [PK_EmailOtpChallenges] PRIMARY KEY ([Id]),
        CONSTRAINT [FK_EmailOtpChallenges_Users_UserId] FOREIGN KEY ([UserId]) REFERENCES [Users] ([Id]) ON DELETE NO ACTION
    );
END;
GO

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261029031035_InitialSchema'
)
BEGIN
    CREATE TABLE [Families] (
        [Id] uniqueidentifier NOT NULL,
        [FamilyName] nvarchar(1000) NOT NULL,
        [CreatedBy] uniqueidentifier NOT NULL,
        [CreatedAt] datetimeoffset NOT NULL,
        CONSTRAINT [PK_Families] PRIMARY KEY ([Id]),
        CONSTRAINT [FK_Families_Users_CreatedBy] FOREIGN KEY ([CreatedBy]) REFERENCES [Users] ([Id]) ON DELETE NO ACTION
    );
END;
GO

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261029031035_InitialSchema'
)
BEGIN
    CREATE TABLE [Notifications] (
        [Id] uniqueidentifier NOT NULL,
        [ReceiverId] uniqueidentifier NOT NULL,
        [Title] nvarchar(1000) NOT NULL,
        [Content] nvarchar(1000) NOT NULL,
        [Type] nvarchar(1000) NOT NULL,
        [IsRead] bit NOT NULL,
        [CreatedAt] datetimeoffset NOT NULL,
        CONSTRAINT [PK_Notifications] PRIMARY KEY ([Id]),
        CONSTRAINT [FK_Notifications_Users_ReceiverId] FOREIGN KEY ([ReceiverId]) REFERENCES [Users] ([Id]) ON DELETE NO ACTION
    );
END;
GO

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261029031035_InitialSchema'
)
BEGIN
    CREATE TABLE [ParentPins] (
        [Id] uniqueidentifier NOT NULL,
        [ParentId] uniqueidentifier NOT NULL,
        [PinHash] nvarchar(1000) NOT NULL,
        [Attempts] int NOT NULL,
        [BlockedUntil] datetimeoffset NULL,
        [CreatedAt] datetimeoffset NOT NULL,
        CONSTRAINT [PK_ParentPins] PRIMARY KEY ([Id]),
        CONSTRAINT [FK_ParentPins_Users_ParentId] FOREIGN KEY ([ParentId]) REFERENCES [Users] ([Id]) ON DELETE NO ACTION
    );
END;
GO

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261029031035_InitialSchema'
)
BEGIN
    CREATE TABLE [RefreshTokens] (
        [Id] uniqueidentifier NOT NULL,
        [UserId] uniqueidentifier NOT NULL,
        [TokenHash] nvarchar(1000) NOT NULL,
        [ExpiresAt] datetimeoffset NOT NULL,
        [RevokedAt] datetimeoffset NULL,
        [CreatedAt] datetimeoffset NOT NULL,
        CONSTRAINT [PK_RefreshTokens] PRIMARY KEY ([Id]),
        CONSTRAINT [FK_RefreshTokens_Users_UserId] FOREIGN KEY ([UserId]) REFERENCES [Users] ([Id]) ON DELETE NO ACTION
    );
END;
GO

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261029031035_InitialSchema'
)
BEGIN
    CREATE TABLE [Children] (
        [Id] uniqueidentifier NOT NULL,
        [FamilyId] uniqueidentifier NOT NULL,
        [UserId] uniqueidentifier NULL,
        [FullName] nvarchar(1000) NOT NULL,
        [DateOfBirth] date NULL,
        [AvatarUrl] nvarchar(1000) NULL,
        [CreatedAt] datetimeoffset NOT NULL,
        CONSTRAINT [PK_Children] PRIMARY KEY ([Id]),
        CONSTRAINT [FK_Children_Families_FamilyId] FOREIGN KEY ([FamilyId]) REFERENCES [Families] ([Id]) ON DELETE NO ACTION,
        CONSTRAINT [FK_Children_Users_UserId] FOREIGN KEY ([UserId]) REFERENCES [Users] ([Id]) ON DELETE NO ACTION
    );
END;
GO

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261029031035_InitialSchema'
)
BEGIN
    CREATE TABLE [FamilyMembers] (
        [Id] uniqueidentifier NOT NULL,
        [FamilyId] uniqueidentifier NOT NULL,
        [UserId] uniqueidentifier NOT NULL,
        [Relationship] nvarchar(1000) NOT NULL,
        [CreatedAt] datetimeoffset NOT NULL,
        CONSTRAINT [PK_FamilyMembers] PRIMARY KEY ([Id]),
        CONSTRAINT [FK_FamilyMembers_Families_FamilyId] FOREIGN KEY ([FamilyId]) REFERENCES [Families] ([Id]) ON DELETE NO ACTION,
        CONSTRAINT [FK_FamilyMembers_Users_UserId] FOREIGN KEY ([UserId]) REFERENCES [Users] ([Id]) ON DELETE NO ACTION
    );
END;
GO

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261029031035_InitialSchema'
)
BEGIN
    CREATE TABLE [Devices] (
        [Id] uniqueidentifier NOT NULL,
        [ChildId] uniqueidentifier NOT NULL,
        [DeviceName] nvarchar(1000) NOT NULL,
        [DeviceModel] nvarchar(1000) NOT NULL,
        [AndroidVersion] nvarchar(1000) NOT NULL,
        [LastOnlineAt] datetimeoffset NULL,
        [Linked] bit NOT NULL,
        [DeviceOwner] bit NOT NULL,
        [CreatedAt] datetimeoffset NOT NULL,
        CONSTRAINT [PK_Devices] PRIMARY KEY ([Id]),
        CONSTRAINT [FK_Devices_Children_ChildId] FOREIGN KEY ([ChildId]) REFERENCES [Children] ([Id]) ON DELETE NO ACTION
    );
END;
GO

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261029031035_InitialSchema'
)
BEGIN
    CREATE TABLE [ExtensionRequests] (
        [Id] uniqueidentifier NOT NULL,
        [ChildId] uniqueidentifier NOT NULL,
        [RequestedMinutes] int NOT NULL,
        [Reason] nvarchar(1000) NOT NULL,
        [Status] nvarchar(1000) NOT NULL,
        [ParentResponse] nvarchar(1000) NULL,
        [RespondedAt] datetimeoffset NULL,
        [UsageDate] date NOT NULL,
        [CreatedAt] datetimeoffset NOT NULL,
        CONSTRAINT [PK_ExtensionRequests] PRIMARY KEY ([Id]),
        CONSTRAINT [FK_ExtensionRequests_Children_ChildId] FOREIGN KEY ([ChildId]) REFERENCES [Children] ([Id]) ON DELETE NO ACTION
    );
END;
GO

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261029031035_InitialSchema'
)
BEGIN
    CREATE TABLE [NoiseReports] (
        [Id] uniqueidentifier NOT NULL,
        [ChildId] uniqueidentifier NOT NULL,
        [AverageLevel] float NOT NULL,
        [MaximumLevel] float NOT NULL,
        [RecordedAt] datetimeoffset NOT NULL,
        [CreatedAt] datetimeoffset NOT NULL,
        CONSTRAINT [PK_NoiseReports] PRIMARY KEY ([Id]),
        CONSTRAINT [FK_NoiseReports_Children_ChildId] FOREIGN KEY ([ChildId]) REFERENCES [Children] ([Id]) ON DELETE NO ACTION
    );
END;
GO

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261029031035_InitialSchema'
)
BEGIN
    CREATE TABLE [PairingRequests] (
        [Id] uniqueidentifier NOT NULL,
        [ParentId] uniqueidentifier NOT NULL,
        [ChildId] uniqueidentifier NOT NULL,
        [TokenHash] nvarchar(1000) NOT NULL,
        [ExpiresAt] datetimeoffset NOT NULL,
        [UsedAt] datetimeoffset NULL,
        [CreatedAt] datetimeoffset NOT NULL,
        CONSTRAINT [PK_PairingRequests] PRIMARY KEY ([Id]),
        CONSTRAINT [FK_PairingRequests_Children_ChildId] FOREIGN KEY ([ChildId]) REFERENCES [Children] ([Id]) ON DELETE NO ACTION,
        CONSTRAINT [FK_PairingRequests_Users_ParentId] FOREIGN KEY ([ParentId]) REFERENCES [Users] ([Id]) ON DELETE NO ACTION
    );
END;
GO

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261029031035_InitialSchema'
)
BEGIN
    CREATE TABLE [SafePlaces] (
        [Id] uniqueidentifier NOT NULL,
        [ChildId] uniqueidentifier NOT NULL,
        [PlaceName] nvarchar(1000) NOT NULL,
        [Latitude] float NOT NULL,
        [Longitude] float NOT NULL,
        [RadiusMeters] int NOT NULL,
        [CreatedAt] datetimeoffset NOT NULL,
        CONSTRAINT [PK_SafePlaces] PRIMARY KEY ([Id]),
        CONSTRAINT [FK_SafePlaces_Children_ChildId] FOREIGN KEY ([ChildId]) REFERENCES [Children] ([Id]) ON DELETE NO ACTION
    );
END;
GO

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261029031035_InitialSchema'
)
BEGIN
    CREATE TABLE [ScreenTimeRules] (
        [Id] uniqueidentifier NOT NULL,
        [ChildId] uniqueidentifier NOT NULL,
        [DailyLimitMinutes] int NOT NULL,
        [StartTime] time NOT NULL,
        [EndTime] time NOT NULL,
        [StrictMode] bit NOT NULL,
        [AllowExtensionRequest] bit NOT NULL,
        [IsEnabled] bit NOT NULL,
        [Version] bigint NOT NULL,
        [CreatedAt] datetimeoffset NOT NULL,
        CONSTRAINT [PK_ScreenTimeRules] PRIMARY KEY ([Id]),
        CONSTRAINT [FK_ScreenTimeRules_Children_ChildId] FOREIGN KEY ([ChildId]) REFERENCES [Children] ([Id]) ON DELETE NO ACTION
    );
END;
GO

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261029031035_InitialSchema'
)
BEGIN
    CREATE TABLE [AppUsageRecords] (
        [Id] uniqueidentifier NOT NULL,
        [DeviceId] uniqueidentifier NOT NULL,
        [PackageName] nvarchar(256) NOT NULL,
        [AppName] nvarchar(1000) NOT NULL,
        [StartedAt] datetimeoffset NOT NULL,
        [EndedAt] datetimeoffset NOT NULL,
        [DurationSeconds] int NOT NULL,
        [CreatedAt] datetimeoffset NOT NULL,
        CONSTRAINT [PK_AppUsageRecords] PRIMARY KEY ([Id]),
        CONSTRAINT [FK_AppUsageRecords_Devices_DeviceId] FOREIGN KEY ([DeviceId]) REFERENCES [Devices] ([Id]) ON DELETE NO ACTION
    );
END;
GO

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261029031035_InitialSchema'
)
BEGIN
    CREATE TABLE [DailyUsageSummaries] (
        [Id] uniqueidentifier NOT NULL,
        [DeviceId] uniqueidentifier NOT NULL,
        [UsageDate] date NOT NULL,
        [TotalSeconds] int NOT NULL,
        [LastSyncedAt] datetimeoffset NOT NULL,
        [CreatedAt] datetimeoffset NOT NULL,
        CONSTRAINT [PK_DailyUsageSummaries] PRIMARY KEY ([Id]),
        CONSTRAINT [FK_DailyUsageSummaries_Devices_DeviceId] FOREIGN KEY ([DeviceId]) REFERENCES [Devices] ([Id]) ON DELETE NO ACTION
    );
END;
GO

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261029031035_InitialSchema'
)
BEGIN
    CREATE TABLE [DeviceLockStates] (
        [Id] uniqueidentifier NOT NULL,
        [DeviceId] uniqueidentifier NOT NULL,
        [IsLocked] bit NOT NULL,
        [LockReason] nvarchar(1000) NOT NULL,
        [LockedAt] datetimeoffset NULL,
        [UnlockAt] datetimeoffset NULL,
        [PolicyVersion] bigint NOT NULL,
        [AcknowledgedVersion] bigint NOT NULL,
        [CreatedAt] datetimeoffset NOT NULL,
        CONSTRAINT [PK_DeviceLockStates] PRIMARY KEY ([Id]),
        CONSTRAINT [FK_DeviceLockStates_Devices_DeviceId] FOREIGN KEY ([DeviceId]) REFERENCES [Devices] ([Id]) ON DELETE NO ACTION
    );
END;
GO

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261029031035_InitialSchema'
)
BEGIN
    CREATE TABLE [Locations] (
        [Id] uniqueidentifier NOT NULL,
        [DeviceId] uniqueidentifier NOT NULL,
        [Latitude] float NOT NULL,
        [Longitude] float NOT NULL,
        [Accuracy] float NOT NULL,
        [RecordedAt] datetimeoffset NOT NULL,
        [CreatedAt] datetimeoffset NOT NULL,
        CONSTRAINT [PK_Locations] PRIMARY KEY ([Id]),
        CONSTRAINT [FK_Locations_Devices_DeviceId] FOREIGN KEY ([DeviceId]) REFERENCES [Devices] ([Id]) ON DELETE NO ACTION
    );
END;
GO

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261029031035_InitialSchema'
)
BEGIN
    CREATE UNIQUE INDEX [IX_AppUsageRecords_DeviceId_PackageName_StartedAt_EndedAt] ON [AppUsageRecords] ([DeviceId], [PackageName], [StartedAt], [EndedAt]);
END;
GO

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261029031035_InitialSchema'
)
BEGIN
    CREATE INDEX [IX_AuditLogs_ActorId] ON [AuditLogs] ([ActorId]);
END;
GO

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261029031035_InitialSchema'
)
BEGIN
    CREATE INDEX [IX_Children_FamilyId] ON [Children] ([FamilyId]);
END;
GO

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261029031035_InitialSchema'
)
BEGIN
    EXEC(N'CREATE UNIQUE INDEX [IX_Children_UserId] ON [Children] ([UserId]) WHERE [UserId] IS NOT NULL');
END;
GO

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261029031035_InitialSchema'
)
BEGIN
    CREATE UNIQUE INDEX [IX_DailyUsageSummaries_DeviceId_UsageDate] ON [DailyUsageSummaries] ([DeviceId], [UsageDate]);
END;
GO

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261029031035_InitialSchema'
)
BEGIN
    CREATE UNIQUE INDEX [IX_DeviceLockStates_DeviceId] ON [DeviceLockStates] ([DeviceId]);
END;
GO

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261029031035_InitialSchema'
)
BEGIN
    CREATE INDEX [IX_Devices_ChildId] ON [Devices] ([ChildId]);
END;
GO

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261029031035_InitialSchema'
)
BEGIN
    CREATE INDEX [IX_EmailOtpChallenges_UserId] ON [EmailOtpChallenges] ([UserId]);
END;
GO

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261029031035_InitialSchema'
)
BEGIN
    CREATE INDEX [IX_ExtensionRequests_ChildId] ON [ExtensionRequests] ([ChildId]);
END;
GO

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261029031035_InitialSchema'
)
BEGIN
    CREATE INDEX [IX_Families_CreatedBy] ON [Families] ([CreatedBy]);
END;
GO

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261029031035_InitialSchema'
)
BEGIN
    CREATE UNIQUE INDEX [IX_FamilyMembers_FamilyId_UserId] ON [FamilyMembers] ([FamilyId], [UserId]);
END;
GO

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261029031035_InitialSchema'
)
BEGIN
    CREATE INDEX [IX_FamilyMembers_UserId] ON [FamilyMembers] ([UserId]);
END;
GO

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261029031035_InitialSchema'
)
BEGIN
    CREATE INDEX [IX_Locations_DeviceId_RecordedAt] ON [Locations] ([DeviceId], [RecordedAt]);
END;
GO

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261029031035_InitialSchema'
)
BEGIN
    CREATE INDEX [IX_NoiseReports_ChildId] ON [NoiseReports] ([ChildId]);
END;
GO

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261029031035_InitialSchema'
)
BEGIN
    CREATE INDEX [IX_Notifications_ReceiverId_CreatedAt] ON [Notifications] ([ReceiverId], [CreatedAt]);
END;
GO

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261029031035_InitialSchema'
)
BEGIN
    CREATE INDEX [IX_PairingRequests_ChildId] ON [PairingRequests] ([ChildId]);
END;
GO

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261029031035_InitialSchema'
)
BEGIN
    CREATE INDEX [IX_PairingRequests_ParentId] ON [PairingRequests] ([ParentId]);
END;
GO

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261029031035_InitialSchema'
)
BEGIN
    CREATE UNIQUE INDEX [IX_PairingRequests_TokenHash] ON [PairingRequests] ([TokenHash]);
END;
GO

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261029031035_InitialSchema'
)
BEGIN
    CREATE UNIQUE INDEX [IX_ParentPins_ParentId] ON [ParentPins] ([ParentId]);
END;
GO

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261029031035_InitialSchema'
)
BEGIN
    CREATE UNIQUE INDEX [IX_RefreshTokens_TokenHash] ON [RefreshTokens] ([TokenHash]);
END;
GO

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261029031035_InitialSchema'
)
BEGIN
    CREATE INDEX [IX_RefreshTokens_UserId] ON [RefreshTokens] ([UserId]);
END;
GO

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261029031035_InitialSchema'
)
BEGIN
    CREATE INDEX [IX_SafePlaces_ChildId] ON [SafePlaces] ([ChildId]);
END;
GO

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261029031035_InitialSchema'
)
BEGIN
    CREATE UNIQUE INDEX [IX_ScreenTimeRules_ChildId] ON [ScreenTimeRules] ([ChildId]);
END;
GO

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261029031035_InitialSchema'
)
BEGIN
    CREATE UNIQUE INDEX [IX_Users_Email] ON [Users] ([Email]);
END;
GO

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261029031035_InitialSchema'
)
BEGIN
    INSERT INTO [__EFMigrationsHistory] ([MigrationId], [ProductVersion])
    VALUES (N'20261029031035_InitialSchema', N'8.0.25');
END;
GO

COMMIT;
GO

BEGIN TRANSACTION;
GO

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261029033210_OfflineRecovery'
)
BEGIN
    ALTER TABLE [Devices] ADD [RecoveryHash] nvarchar(1000) NULL;
END;
GO

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261029033210_OfflineRecovery'
)
BEGIN
    ALTER TABLE [Devices] ADD [RecoveryVersion] bigint NOT NULL DEFAULT CAST(0 AS bigint);
END;
GO

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261029033210_OfflineRecovery'
)
BEGIN
    INSERT INTO [__EFMigrationsHistory] ([MigrationId], [ProductVersion])
    VALUES (N'20261029033210_OfflineRecovery', N'8.0.25');
END;
GO

COMMIT;
GO

BEGIN TRANSACTION;
GO

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261029033742_ManagementRelease'
)
BEGIN
    ALTER TABLE [Devices] ADD [ReleaseRequestedUntil] datetimeoffset NULL;
END;
GO

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261029033742_ManagementRelease'
)
BEGIN
    INSERT INTO [__EFMigrationsHistory] ([MigrationId], [ProductVersion])
    VALUES (N'20261029033742_ManagementRelease', N'8.0.25');
END;
GO

COMMIT;
GO

BEGIN TRANSACTION;
GO

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261029034230_VoiceAndSmsSettings'
)
BEGIN
    ALTER TABLE [Users] ADD [SmsAlertsEnabled] bit NOT NULL DEFAULT CAST(0 AS bit);
END;
GO

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261029034230_VoiceAndSmsSettings'
)
BEGIN
    ALTER TABLE [ScreenTimeRules] ADD [VoiceName] nvarchar(1000) NULL;
END;
GO

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261029034230_VoiceAndSmsSettings'
)
BEGIN
    ALTER TABLE [ScreenTimeRules] ADD [WarningMinutes] nvarchar(1000) NOT NULL DEFAULT N'';
END;
GO

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261029034230_VoiceAndSmsSettings'
)
BEGIN
    ALTER TABLE [Notifications] ADD [SmsSentAt] datetimeoffset NULL;
END;
GO

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261029034230_VoiceAndSmsSettings'
)
BEGIN
    ALTER TABLE [Notifications] ADD [SmsState] nvarchar(1000) NOT NULL DEFAULT N'';
END;
GO

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261029034230_VoiceAndSmsSettings'
)
BEGIN
    INSERT INTO [__EFMigrationsHistory] ([MigrationId], [ProductVersion])
    VALUES (N'20261029034230_VoiceAndSmsSettings', N'8.0.25');
END;
GO

COMMIT;
GO

BEGIN TRANSACTION;
GO

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261029034905_AppCategoriesAndDefaults'
)
BEGIN
    DECLARE @var0 sysname;
    SELECT @var0 = [d].[name]
    FROM [sys].[default_constraints] [d]
    INNER JOIN [sys].[columns] [c] ON [d].[parent_column_id] = [c].[column_id] AND [d].[parent_object_id] = [c].[object_id]
    WHERE ([d].[parent_object_id] = OBJECT_ID(N'[ScreenTimeRules]') AND [c].[name] = N'WarningMinutes');
    IF @var0 IS NOT NULL EXEC(N'ALTER TABLE [ScreenTimeRules] DROP CONSTRAINT [' + @var0 + '];');
    ALTER TABLE [ScreenTimeRules] ADD DEFAULT N'30,15,5' FOR [WarningMinutes];
END;
GO

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261029034905_AppCategoriesAndDefaults'
)
BEGIN
    DECLARE @var1 sysname;
    SELECT @var1 = [d].[name]
    FROM [sys].[default_constraints] [d]
    INNER JOIN [sys].[columns] [c] ON [d].[parent_column_id] = [c].[column_id] AND [d].[parent_object_id] = [c].[object_id]
    WHERE ([d].[parent_object_id] = OBJECT_ID(N'[Notifications]') AND [c].[name] = N'SmsState');
    IF @var1 IS NOT NULL EXEC(N'ALTER TABLE [Notifications] DROP CONSTRAINT [' + @var1 + '];');
    ALTER TABLE [Notifications] ADD DEFAULT N'NotRequested' FOR [SmsState];
END;
GO

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261029034905_AppCategoriesAndDefaults'
)
BEGIN
    CREATE TABLE [AppClassifications] (
        [Id] uniqueidentifier NOT NULL,
        [ChildId] uniqueidentifier NOT NULL,
        [PackageName] nvarchar(256) NOT NULL,
        [Category] nvarchar(1000) NOT NULL,
        [CreatedAt] datetimeoffset NOT NULL,
        CONSTRAINT [PK_AppClassifications] PRIMARY KEY ([Id]),
        CONSTRAINT [FK_AppClassifications_Children_ChildId] FOREIGN KEY ([ChildId]) REFERENCES [Children] ([Id]) ON DELETE NO ACTION
    );
END;
GO

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261029034905_AppCategoriesAndDefaults'
)
BEGIN
    CREATE UNIQUE INDEX [IX_AppClassifications_ChildId_PackageName] ON [AppClassifications] ([ChildId], [PackageName]);
END;
GO

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261029034905_AppCategoriesAndDefaults'
)
BEGIN
    UPDATE ScreenTimeRules SET WarningMinutes = N'30,15,5' WHERE WarningMinutes = N'';
END;
GO

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261029034905_AppCategoriesAndDefaults'
)
BEGIN
    UPDATE Notifications SET SmsState = N'NotRequested' WHERE SmsState = N'';
END;
GO

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261029034905_AppCategoriesAndDefaults'
)
BEGIN
    INSERT INTO [__EFMigrationsHistory] ([MigrationId], [ProductVersion])
    VALUES (N'20261029034905_AppCategoriesAndDefaults', N'8.0.25');
END;
GO

COMMIT;
GO

BEGIN TRANSACTION;
GO

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261029040118_EmailReportsAndSecurityAlerts'
)
BEGIN
    ALTER TABLE [Users] ADD [EmailReportsEnabled] bit NOT NULL DEFAULT CAST(0 AS bit);
END;
GO

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261029040118_EmailReportsAndSecurityAlerts'
)
BEGIN
    ALTER TABLE [Notifications] ADD [EmailState] nvarchar(1000) NOT NULL DEFAULT N'';
END;
GO

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261029040118_EmailReportsAndSecurityAlerts'
)
BEGIN
    ALTER TABLE [Notifications] ADD [ReportDate] date NULL;
END;
GO

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261029040118_EmailReportsAndSecurityAlerts'
)
BEGIN
    EXEC(N'CREATE UNIQUE INDEX [IX_Notifications_ReceiverId_ReportDate] ON [Notifications] ([ReceiverId], [ReportDate]) WHERE [ReportDate] IS NOT NULL');
END;
GO

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261029040118_EmailReportsAndSecurityAlerts'
)
BEGIN
    INSERT INTO [__EFMigrationsHistory] ([MigrationId], [ProductVersion])
    VALUES (N'20261029040118_EmailReportsAndSecurityAlerts', N'8.0.25');
END;
GO

COMMIT;
GO

BEGIN TRANSACTION;
GO

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261029082322_DeviceEnrollmentAndPush'
)
BEGIN
    ALTER TABLE [Users] ADD [DeviceOnly] bit NOT NULL DEFAULT CAST(0 AS bit);
END;
GO

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261029082322_DeviceEnrollmentAndPush'
)
BEGIN
    ALTER TABLE [RefreshTokens] ADD [DeviceId] uniqueidentifier NULL;
END;
GO

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261029082322_DeviceEnrollmentAndPush'
)
BEGIN
    ALTER TABLE [Notifications] ADD [PushQueuedAt] datetimeoffset NULL;
END;
GO

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261029082322_DeviceEnrollmentAndPush'
)
BEGIN
    ALTER TABLE [Children] ADD [AvatarBytes] varbinary(max) NULL;
END;
GO

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261029082322_DeviceEnrollmentAndPush'
)
BEGIN
    ALTER TABLE [Children] ADD [Nickname] nvarchar(1000) NULL;
END;
GO

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261029082322_DeviceEnrollmentAndPush'
)
BEGIN
    CREATE TABLE [DeviceEnrollments] (
        [Id] uniqueidentifier NOT NULL,
        [PairingRequestId] uniqueidentifier NOT NULL,
        [ClaimHash] nvarchar(1000) NOT NULL,
        [InstallationHash] nvarchar(1000) NOT NULL,
        [VerificationCode] nvarchar(1000) NOT NULL,
        [DeviceName] nvarchar(1000) NOT NULL,
        [DeviceModel] nvarchar(1000) NOT NULL,
        [AndroidVersion] nvarchar(1000) NOT NULL,
        [Status] nvarchar(1000) NOT NULL,
        [ExpiresAt] datetimeoffset NOT NULL,
        [ConsumedAt] datetimeoffset NULL,
        [DeviceId] uniqueidentifier NULL,
        [CreatedAt] datetimeoffset NOT NULL,
        CONSTRAINT [PK_DeviceEnrollments] PRIMARY KEY ([Id]),
        CONSTRAINT [FK_DeviceEnrollments_Devices_DeviceId] FOREIGN KEY ([DeviceId]) REFERENCES [Devices] ([Id]) ON DELETE NO ACTION,
        CONSTRAINT [FK_DeviceEnrollments_PairingRequests_PairingRequestId] FOREIGN KEY ([PairingRequestId]) REFERENCES [PairingRequests] ([Id]) ON DELETE NO ACTION
    );
END;
GO

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261029082322_DeviceEnrollmentAndPush'
)
BEGIN
    CREATE TABLE [PushRegistrations] (
        [Id] uniqueidentifier NOT NULL,
        [UserId] uniqueidentifier NOT NULL,
        [SecurityStamp] nvarchar(1000) NOT NULL,
        [TokenHash] nvarchar(1000) NOT NULL,
        [ProtectedToken] nvarchar(max) NOT NULL,
        [InstallationHash] nvarchar(1000) NOT NULL,
        [Active] bit NOT NULL,
        [LastSeenAt] datetimeoffset NOT NULL,
        [CreatedAt] datetimeoffset NOT NULL,
        CONSTRAINT [PK_PushRegistrations] PRIMARY KEY ([Id]),
        CONSTRAINT [FK_PushRegistrations_Users_UserId] FOREIGN KEY ([UserId]) REFERENCES [Users] ([Id]) ON DELETE NO ACTION
    );
END;
GO

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261029082322_DeviceEnrollmentAndPush'
)
BEGIN
    CREATE TABLE [PushDeliveries] (
        [Id] uniqueidentifier NOT NULL,
        [NoticeId] uniqueidentifier NOT NULL,
        [RegistrationId] uniqueidentifier NOT NULL,
        [State] nvarchar(1000) NOT NULL,
        [Attempts] int NOT NULL,
        [NextAttemptAt] datetimeoffset NOT NULL,
        [ReceivedAt] datetimeoffset NULL,
        [OpenedAt] datetimeoffset NULL,
        [ProviderMessageId] nvarchar(1000) NULL,
        [CreatedAt] datetimeoffset NOT NULL,
        CONSTRAINT [PK_PushDeliveries] PRIMARY KEY ([Id]),
        CONSTRAINT [FK_PushDeliveries_Notifications_NoticeId] FOREIGN KEY ([NoticeId]) REFERENCES [Notifications] ([Id]) ON DELETE CASCADE,
        CONSTRAINT [FK_PushDeliveries_PushRegistrations_RegistrationId] FOREIGN KEY ([RegistrationId]) REFERENCES [PushRegistrations] ([Id]) ON DELETE NO ACTION
    );
END;
GO

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261029082322_DeviceEnrollmentAndPush'
)
BEGIN
    CREATE INDEX [IX_RefreshTokens_DeviceId] ON [RefreshTokens] ([DeviceId]);
END;
GO

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261029082322_DeviceEnrollmentAndPush'
)
BEGIN
    CREATE UNIQUE INDEX [IX_DeviceEnrollments_ClaimHash] ON [DeviceEnrollments] ([ClaimHash]);
END;
GO

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261029082322_DeviceEnrollmentAndPush'
)
BEGIN
    CREATE INDEX [IX_DeviceEnrollments_DeviceId] ON [DeviceEnrollments] ([DeviceId]);
END;
GO

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261029082322_DeviceEnrollmentAndPush'
)
BEGIN
    CREATE UNIQUE INDEX [IX_DeviceEnrollments_PairingRequestId] ON [DeviceEnrollments] ([PairingRequestId]);
END;
GO

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261029082322_DeviceEnrollmentAndPush'
)
BEGIN
    CREATE UNIQUE INDEX [IX_PushDeliveries_NoticeId_RegistrationId] ON [PushDeliveries] ([NoticeId], [RegistrationId]);
END;
GO

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261029082322_DeviceEnrollmentAndPush'
)
BEGIN
    CREATE INDEX [IX_PushDeliveries_RegistrationId] ON [PushDeliveries] ([RegistrationId]);
END;
GO

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261029082322_DeviceEnrollmentAndPush'
)
BEGIN
    CREATE UNIQUE INDEX [IX_PushRegistrations_InstallationHash] ON [PushRegistrations] ([InstallationHash]);
END;
GO

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261029082322_DeviceEnrollmentAndPush'
)
BEGIN
    CREATE UNIQUE INDEX [IX_PushRegistrations_TokenHash] ON [PushRegistrations] ([TokenHash]);
END;
GO

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261029082322_DeviceEnrollmentAndPush'
)
BEGIN
    CREATE INDEX [IX_PushRegistrations_UserId] ON [PushRegistrations] ([UserId]);
END;
GO

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261029082322_DeviceEnrollmentAndPush'
)
BEGIN
    ALTER TABLE [RefreshTokens] ADD CONSTRAINT [FK_RefreshTokens_Devices_DeviceId] FOREIGN KEY ([DeviceId]) REFERENCES [Devices] ([Id]) ON DELETE NO ACTION;
END;
GO

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261029082322_DeviceEnrollmentAndPush'
)
BEGIN
    INSERT INTO [__EFMigrationsHistory] ([MigrationId], [ProductVersion])
    VALUES (N'20261029082322_DeviceEnrollmentAndPush', N'8.0.25');
END;
GO

COMMIT;
GO

BEGIN TRANSACTION;
GO

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261030010701_UserAvatar'
)
BEGIN
    ALTER TABLE [Users] ADD [AvatarBytes] varbinary(max) NULL;
END;
GO

IF NOT EXISTS (
    SELECT * FROM [__EFMigrationsHistory]
    WHERE [MigrationId] = N'20261030010701_UserAvatar'
)
BEGIN
    INSERT INTO [__EFMigrationsHistory] ([MigrationId], [ProductVersion])
    VALUES (N'20261030010701_UserAvatar', N'8.0.25');
END;
GO

COMMIT;
GO
