using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace NhomBar.Api.Migrations
{
    /// <inheritdoc />
    public partial class VoiceAndSmsSettings : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<bool>(
                name: "SmsAlertsEnabled",
                table: "Users",
                type: "bit",
                nullable: false,
                defaultValue: false);

            migrationBuilder.AddColumn<string>(
                name: "VoiceName",
                table: "ScreenTimeRules",
                type: "nvarchar(1000)",
                maxLength: 1000,
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "WarningMinutes",
                table: "ScreenTimeRules",
                type: "nvarchar(1000)",
                maxLength: 1000,
                nullable: false,
                defaultValue: "");

            migrationBuilder.AddColumn<DateTimeOffset>(
                name: "SmsSentAt",
                table: "Notifications",
                type: "datetimeoffset",
                nullable: true);

            migrationBuilder.AddColumn<string>(
                name: "SmsState",
                table: "Notifications",
                type: "nvarchar(1000)",
                maxLength: 1000,
                nullable: false,
                defaultValue: "");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "SmsAlertsEnabled",
                table: "Users");

            migrationBuilder.DropColumn(
                name: "VoiceName",
                table: "ScreenTimeRules");

            migrationBuilder.DropColumn(
                name: "WarningMinutes",
                table: "ScreenTimeRules");

            migrationBuilder.DropColumn(
                name: "SmsSentAt",
                table: "Notifications");

            migrationBuilder.DropColumn(
                name: "SmsState",
                table: "Notifications");
        }
    }
}
