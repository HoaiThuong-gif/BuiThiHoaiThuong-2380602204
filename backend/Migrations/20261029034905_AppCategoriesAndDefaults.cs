using System;
using Microsoft.EntityFrameworkCore.Migrations;

#nullable disable

namespace NhomBar.Api.Migrations
{
    /// <inheritdoc />
    public partial class AppCategoriesAndDefaults : Migration
    {
        /// <inheritdoc />
        protected override void Up(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.AlterColumn<string>(
                name: "WarningMinutes",
                table: "ScreenTimeRules",
                type: "nvarchar(1000)",
                maxLength: 1000,
                nullable: false,
                defaultValue: "30,15,5",
                oldClrType: typeof(string),
                oldType: "nvarchar(1000)",
                oldMaxLength: 1000);

            migrationBuilder.AlterColumn<string>(
                name: "SmsState",
                table: "Notifications",
                type: "nvarchar(1000)",
                maxLength: 1000,
                nullable: false,
                defaultValue: "NotRequested",
                oldClrType: typeof(string),
                oldType: "nvarchar(1000)",
                oldMaxLength: 1000);

            migrationBuilder.CreateTable(
                name: "AppClassifications",
                columns: table => new
                {
                    Id = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                    ChildId = table.Column<Guid>(type: "uniqueidentifier", nullable: false),
                    PackageName = table.Column<string>(type: "nvarchar(256)", maxLength: 256, nullable: false),
                    Category = table.Column<string>(type: "nvarchar(1000)", maxLength: 1000, nullable: false),
                    CreatedAt = table.Column<DateTimeOffset>(type: "datetimeoffset", nullable: false)
                },
                constraints: table =>
                {
                    table.PrimaryKey("PK_AppClassifications", x => x.Id);
                    table.ForeignKey(
                        name: "FK_AppClassifications_Children_ChildId",
                        column: x => x.ChildId,
                        principalTable: "Children",
                        principalColumn: "Id",
                        onDelete: ReferentialAction.Restrict);
                });

            migrationBuilder.CreateIndex(
                name: "IX_AppClassifications_ChildId_PackageName",
                table: "AppClassifications",
                columns: new[] { "ChildId", "PackageName" },
                unique: true);
            migrationBuilder.Sql("UPDATE ScreenTimeRules SET WarningMinutes = N'30,15,5' WHERE WarningMinutes = N'';");
            migrationBuilder.Sql("UPDATE Notifications SET SmsState = N'NotRequested' WHERE SmsState = N'';");
        }

        /// <inheritdoc />
        protected override void Down(MigrationBuilder migrationBuilder)
        {
            migrationBuilder.DropTable(
                name: "AppClassifications");

            migrationBuilder.AlterColumn<string>(
                name: "WarningMinutes",
                table: "ScreenTimeRules",
                type: "nvarchar(1000)",
                maxLength: 1000,
                nullable: false,
                oldClrType: typeof(string),
                oldType: "nvarchar(1000)",
                oldMaxLength: 1000,
                oldDefaultValue: "30,15,5");

            migrationBuilder.AlterColumn<string>(
                name: "SmsState",
                table: "Notifications",
                type: "nvarchar(1000)",
                maxLength: 1000,
                nullable: false,
                oldClrType: typeof(string),
                oldType: "nvarchar(1000)",
                oldMaxLength: 1000,
                oldDefaultValue: "NotRequested");
        }
    }
}
