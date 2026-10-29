using System.Security.Cryptography;
using System.Text.Json;
using Microsoft.AspNetCore.Identity;
using Microsoft.EntityFrameworkCore;
using NhomBar;

// Local Android integration fixture. No test endpoints or email bypass exist in the production API.
var directory=Path.GetFullPath("artifacts/native-test");Directory.CreateDirectory(directory);
var database="NhomBarNativeTests_"+Guid.NewGuid().ToString("N");
var connection=$"Server=.;Database={database};Trusted_Connection=True;TrustServerCertificate=True;Encrypt=False";
var capture=new LocalTestMail(directory);
var app=ApiHost.Build(["--environment","Development"],builder=>{
    builder.WebHost.UseUrls("http://127.0.0.1:5091");
    builder.Configuration.AddInMemoryCollection(new Dictionary<string,string?>{
        ["ConnectionStrings:SqlServer"]=connection,["Jwt:Issuer"]="NhomBar",["Jwt:Audience"]="NhomBar.Mobile",
        ["Jwt:Key"]=Convert.ToBase64String(RandomNumberGenerator.GetBytes(48)),["Email:Brevo:ApiKey"]="",["Email:Brevo:SenderEmail"]="",
        ["Twilio:AccountSid"]="",["Logging:LogLevel:Default"]="Warning"});
    builder.Services.AddSingleton<ICodeSender>(capture);
});
try {
    Guid childId,parentId;
    using(var scope=app.Services.CreateScope()) {
        var db=scope.ServiceProvider.GetRequiredService<AppDb>();var security=scope.ServiceProvider.GetRequiredService<Security>();await db.Database.MigrateAsync();
        var parent=new User{Email="buithihoaithuongdl@gmail.com",FullName="Phụ huynh thử nghiệm",Role="Parent"};parent.PasswordHash=security.PasswordHash(parent,"Hutech@123");
        var childUser=new User{Email="child.native@example.com",FullName="Con thử Android",Role="Child"};childUser.PasswordHash=security.PasswordHash(childUser,"Hutech@123");
        var family=new Family{FamilyName="Gia đình kiểm thử riêng",CreatedBy=parent.Id};var child=new ChildProfile{FamilyId=family.Id,UserId=childUser.Id,FullName=childUser.FullName};
        db.Users.AddRange(parent,childUser);db.Families.Add(family);db.FamilyMembers.AddRange(new FamilyMember{FamilyId=family.Id,UserId=parent.Id},new FamilyMember{FamilyId=family.Id,UserId=childUser.Id,Relationship="Child"});db.Children.Add(child);db.ScreenTimeRules.Add(new ScreenTimeRule{ChildId=child.Id,DailyLimitMinutes=120,StrictMode=false});
        var pin=new ParentPin{ParentId=parent.Id};pin.PinHash=new PasswordHasher<ParentPin>().HashPassword(pin,"123456");db.ParentPins.Add(pin);await db.SaveChangesAsync();childId=child.Id;parentId=parent.Id;
    }
    await app.StartAsync();
    await File.WriteAllTextAsync(Path.Combine(directory,"fixture.json"),JsonSerializer.Serialize(new{database,childId,parentId,parentEmail="buithihoaithuongdl@gmail.com",childEmail="child.native@example.com",url="http://127.0.0.1:5091"}));
    Console.WriteLine("Android test fixture ready on loopback port 5091. Email delivery is captured locally for tests only.");
    await app.WaitForShutdownAsync();
} finally {
    await app.DisposeAsync();
    await using var db=new AppDb(new DbContextOptionsBuilder<AppDb>().UseSqlServer(connection).Options);
    if(db.Database.GetDbConnection().Database==database && database.StartsWith("NhomBarNativeTests_"))await db.Database.EnsureDeletedAsync();
}
sealed class LocalTestMail(string directory):ICodeSender {
    public Task Send(string email,string code)=>File.WriteAllTextAsync(Path.Combine(directory,Security.Hash(email)+".code"),code);
}
