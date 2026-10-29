using Microsoft.EntityFrameworkCore;
namespace NhomBar;

public class AppClassification : Row
{
    public Guid ChildId
    {
        get; set;
    }
    public string PackageName { get; set; } = "";
    public string Category { get; set; } = "Other";
}
public record ClassificationInput(string PackageName, string Category);
public static class CategoryEndpoints
{
    public static void MapCategories(this WebApplication app)
    {
        app.MapPut("/api/children/{id:guid}/apps/category", async (Guid id, ClassificationInput input, Access access, AppDb db) =>
        {
            await access.ForChild(id, true);
            Check.That(input.Category is "Game" or "Social" or "Study" or "Other", "Vui lòng chọn một nhóm ứng dụng trong danh sách.");
            var package = Check.Text(input.PackageName, 256);
            var category = await db.AppClassifications.SingleOrDefaultAsync(x => x.ChildId == id && x.PackageName == package);
            if (category == null)
            {
                category = new AppClassification { ChildId = id, PackageName = package };
                db.AppClassifications.Add(category);
            }
            category.Category = input.Category;
            await db.SaveChangesAsync();
            return category;
        }).RequireAuthorization().WithTags("Báo cáo sử dụng");
    }
}
