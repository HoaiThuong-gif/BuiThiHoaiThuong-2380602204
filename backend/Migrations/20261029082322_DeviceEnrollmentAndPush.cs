using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace NhomBar.Api.Migrations
{
    /// <inheritdoc />
    public partial class DeviceEnrollmentAndPush : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<bool>(
                name: "DeviceOnly",
                table: "Users",
                type: "bit",
                nullable: false,
                defaultValue: false);

            migrationBuilder.AddColumn<Guid>(
                name: "DeviceId",
                table: "RefreshTokens",
                type: "uniqueidentifier",
                nullable: true);

            migrationBuilder.AddColumn<DateTimeOffset>(
                name: "PushQueuedAt",
                table: "Notifications",
                type: "datetimeoffset",
                nullable: true);

            migrationBuilder.AddColumn<byte[]>(
                name: "AvatarBytes",
                table: "Children",
                type: "varbinary(max)",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "Nickname",
                table: "Children",
                type: "nvarchar(1000)",
                maxLength: 1000,
                nullable: true);

            migrationBuilder.CreateTable(
                name: "DeviceEnrollments",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                    PairingRequestId = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                    ClaimHash = table.Column<string>(type: "nvarchar(1000)", maxLength: 1000, nullable: false),
                    InstallationHash = table.Column<string>(type: "nvarchar(1000)", maxLength: 1000, nullable: false),
                    VerificationCode = table.Column<string>(type: "nvarchar(1000)", maxLength: 1000, nullable: false),
                    DeviceName = table.Column<string>(type: "nvarchar(1000)", maxLength: 1000, nullable: false),
                    DeviceModel = table.Column<string>(type: "nvarchar(1000)", maxLength: 1000, nullable: false),
                    AndroidVersion = table.Column<string>(type: "nvarchar(1000)", maxLength: 1000, nullable: false),
                    Status = table.Column<string>(type: "nvarchar(1000)", maxLength: 1000, nullable: false),
                    ExpiresAt = table.Column<DateTimeOffset>(type: "datetimeoffset", nullable: false),
                    ConsumedAt = table.Column<DateTimeOffset>(type: "datetimeoffset", nullable: true),
                    DeviceId = table.Column<Guid>(type: "uniqueidentifier", nullable: true),
                    CreatedAt = table.Column<DateTimeOffset>(type: "datetimeoffset", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_DeviceEnrollments", x => x.Id);
                    table.ForeignKey(
                        name: "FK_DeviceEnrollments_Devices_DeviceId",
                        column: x => x.DeviceId,
                        principalTable: "Devices",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                    table.ForeignKey(
                        name: "FK_DeviceEnrollments_PairingRequests_PairingRequestId",
                        column: x => x.PairingRequestId,
                        principalTable: "PairingRequests",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "PushRegistrations",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                    UserId = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                    SecurityStamp = table.Column<string>(type: "nvarchar(1000)", maxLength: 1000, nullable: false),
                    TokenHash = table.Column<string>(type: "nvarchar(1000)", maxLength: 1000, nullable: false),
                    ProtectedToken = table.Column<string>(type: "nvarchar(max)", maxLength: 8192, nullable: false),
                    InstallationHash = table.Column<string>(type: "nvarchar(1000)", maxLength: 1000, nullable: false),
                    Active = table.Column<bool>(type: "bit", nullable: false),
                    LastSeenAt = table.Column<DateTimeOffset>(type: "datetimeoffset", nullable: false),
                    CreatedAt = table.Column<DateTimeOffset>(type: "datetimeoffset", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_PushRegistrations", x => x.Id);
                    table.ForeignKey(
                        name: "FK_PushRegistrations_Users_UserId",
                        column: x => x.UserId,
                        principalTable: "Users",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateTable(
                name: "PushDeliveries",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                    NoticeId = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                    RegistrationId = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                    State = table.Column<string>(type: "nvarchar(1000)", maxLength: 1000, nullable: false),
                    Attempts = table.Column<int>(type: "int", nullable: false),
                    NextAttemptAt = table.Column<DateTimeOffset>(type: "datetimeoffset", nullable: false),
                    ReceivedAt = table.Column<DateTimeOffset>(type: "datetimeoffset", nullable: true),
                    OpenedAt = table.Column<DateTimeOffset>(type: "datetimeoffset", nullable: true),
                    ProviderMessageId = table.Column<string>(type: "nvarchar(1000)", maxLength: 1000, nullable: true),
                    CreatedAt = table.Column<DateTimeOffset>(type: "datetimeoffset", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_PushDeliveries", x => x.Id);
                    table.ForeignKey(
                        name: "FK_PushDeliveries_Notifications_NoticeId",
                        column: x => x.NoticeId,
                        principalTable: "Notifications",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Cascade);
                    table.ForeignKey(
                        name: "FK_PushDeliveries_PushRegistrations_RegistrationId",
                        column: x => x.RegistrationId,
                        principalTable: "PushRegistrations",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateIndex(
                name: "IX_RefreshTokens_DeviceId",
                table: "RefreshTokens",
                column: "DeviceId");

            migrationBuilder.CreateIndex(
                name: "IX_DeviceEnrollments_ClaimHash",
                table: "DeviceEnrollments",
                column: "ClaimHash",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_DeviceEnrollments_DeviceId",
                table: "DeviceEnrollments",
                column: "DeviceId");

            migrationBuilder.CreateIndex(
                name: "IX_DeviceEnrollments_PairingRequestId",
                table: "DeviceEnrollments",
                column: "PairingRequestId",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_PushDeliveries_NoticeId_RegistrationId",
                table: "PushDeliveries",
                columns: new[] { "NoticeId", "RegistrationId" },
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_PushDeliveries_RegistrationId",
                table: "PushDeliveries",
                column: "RegistrationId");

            migrationBuilder.CreateIndex(
                name: "IX_PushRegistrations_InstallationHash",
                table: "PushRegistrations",
                column: "InstallationHash",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_PushRegistrations_TokenHash",
                table: "PushRegistrations",
                column: "TokenHash",
                unique: true);

            migrationBuilder.CreateIndex(
                name: "IX_PushRegistrations_UserId",
                table: "PushRegistrations",
                column: "UserId");

            migrationBuilder.AddForeignKey(
                name: "FK_RefreshTokens_Devices_DeviceId",
                table: "RefreshTokens",
                column: "DeviceId",
                principalTable: "Devices",
                principalColumn: "Id",
                onDelete: ReferentialAction.Restrict);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropForeignKey(
                name: "FK_RefreshTokens_Devices_DeviceId",
                table: "RefreshTokens");

            migrationBuilder.DropTable(
                name: "DeviceEnrollments");

            migrationBuilder.DropTable(
                name: "PushDeliveries");

            migrationBuilder.DropTable(
                name: "PushRegistrations");

            migrationBuilder.DropIndex(
                name: "IX_RefreshTokens_DeviceId",
                table: "RefreshTokens");

            migrationBuilder.DropColumn(
                name: "DeviceOnly",
                table: "Users");

            migrationBuilder.DropColumn(
                name: "DeviceId",
                table: "RefreshTokens");

            migrationBuilder.DropColumn(
                name: "PushQueuedAt",
                table: "Notifications");

            migrationBuilder.DropColumn(
                name: "AvatarBytes",
                table: "Children");

            migrationBuilder.DropColumn(
                name: "Nickname",
                table: "Children");
        }
    }
}
