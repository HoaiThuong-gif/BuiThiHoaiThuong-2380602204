using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace NhomBar.Api.Migrations
{
    /// <inheritdoc />
    public partial class EmailReportsAndSecurityAlerts : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<bool>(
                name: "EmailReportsEnabled",
                table: "Users",
                type: "bit",
                nullable: false,
                defaultValue: false);

            migrationBuilder.AddColumn<string>(
                name: "EmailState",
                table: "Notifications",
                type: "nvarchar(1000)",
                maxLength: 1000,
                nullable: false,
                defaultValue: "");

            migrationBuilder.AddColumn<DateOnly>(
                name: "ReportDate",
                table: "Notifications",
                type: "date",
                nullable: true);

            migrationBuilder.CreateIndex(
                name: "IX_Notifications_ReceiverId_ReportDate",
                table: "Notifications",
                columns: new[] { "ReceiverId", "ReportDate" },
                unique: true,
                filter: "[ReportDate] IS NOT NULL");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropIndex(
                name: "IX_Notifications_ReceiverId_ReportDate",
                table: "Notifications");

            migrationBuilder.DropColumn(
                name: "EmailReportsEnabled",
                table: "Users");

            migrationBuilder.DropColumn(
                name: "EmailState",
                table: "Notifications");

            migrationBuilder.DropColumn(
                name: "ReportDate",
                table: "Notifications");
        }
    }
}
