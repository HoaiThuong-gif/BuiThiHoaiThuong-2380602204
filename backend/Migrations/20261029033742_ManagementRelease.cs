using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace NhomBar.Api.Migrations
{
    /// <inheritdoc />
    public partial class ManagementRelease : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AddColumn<DateTimeOffset>(
                name: "ReleaseRequestedUntil",
                table: "Devices",
                type: "datetimeoffset",
                nullable: true);
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropColumn(
                name: "ReleaseRequestedUntil",
                table: "Devices");
        }
    }
}
