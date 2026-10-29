using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace NhomBar.Api.Migrations
{
    /// <inheritdoc />
    public partial class OfflineRecovery : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<string>(
                name: "RecoveryHash",
                table: "Devices",
                type: "nvarchar(1000)",
                maxLength: 1000,
                nullable: true);

            migrationBuilder.AddColumn<long>(
                name: "RecoveryVersion",
                table: "Devices",
                type: "bigint",
                nullable: false,
                defaultValue: 0L);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "RecoveryHash",
                table: "Devices");

            migrationBuilder.DropColumn(
                name: "RecoveryVersion",
                table: "Devices");
        }
    }
}
