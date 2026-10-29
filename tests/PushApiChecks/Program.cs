using System.Net;
using System.Security.Cryptography;
using System.Text.Json;
using Microsoft.Extensions.Configuration;
using NhomBar;

var passed=0;
void Assert(bool ok,string name){if(!ok)throw new Exception(name);passed++;Console.WriteLine("PASS: "+name);}
using var rsa=RSA.Create(2048);
var config=new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string,string?>{
    ["Jwt:Key"]=Convert.ToBase64String(RandomNumberGenerator.GetBytes(48)),
    ["Push:Firebase:ServiceAccountJson"]=JsonSerializer.Serialize(new{type="service_account",project_id="test-project",client_email="test@example.invalid",private_key=rsa.ExportPkcs8PrivateKeyPem()})
}).Build();
var protection=new PushTokenProtection(config);
var encrypted=protection.Protect("test-device-token");
Assert(encrypted!="test-device-token"&&protection.Unprotect(encrypted)=="test-device-token","Device token is encrypted at rest and round-trips");
Assert(encrypted!=protection.Protect("test-device-token"),"Each encrypted token uses a fresh nonce");
var bytes=Convert.FromBase64String(encrypted);bytes[^1]^=1;
try{protection.Unprotect(Convert.ToBase64String(bytes));throw new Exception("Tampering accepted");}catch(CryptographicException){Assert(true,"Modified encrypted token is rejected");}
foreach(var item in new[]{(200,"{\"name\":\"projects/test-project/messages/accepted\"}","Accepted"),(200,"{}","Unknown"),(401,"{}","NeedsReview"),(429,"{}","Retry"),(404,"{\"error\":\"UNREGISTERED\"}","InvalidToken"),(500,"{}","NeedsReview")}){
    var handler=new Fake(async request=>{
        if(request.RequestUri!.Host=="oauth2.googleapis.com")return new HttpResponseMessage(HttpStatusCode.OK){Content=new StringContent("{\"access_token\":\"test-access\",\"expires_in\":3600}")};
        using var payload=JsonDocument.Parse(await request.Content!.ReadAsStringAsync());var message=payload.RootElement.GetProperty("message");
        Assert(request.RequestUri.AbsoluteUri=="https://fcm.googleapis.com/v1/projects/test-project/messages:send"&&request.Headers.Authorization?.Scheme=="Bearer","Firebase uses authenticated HTTP v1");
        Assert(!message.TryGetProperty("notification",out _)&&message.GetProperty("data").GetProperty("binding").GetString()=="test-binding","Push carries account binding and no family information for the lock screen");
        return new HttpResponseMessage((HttpStatusCode)item.Item1){Content=new StringContent(item.Item2)};
    });
    var result=await new FirebasePush(new HttpClient(handler),config).Send("test-device-token",Guid.NewGuid(),"test-binding",CancellationToken.None);
    Assert(result.State==item.Item3&&handler.Calls==2,$"Firebase response {item.Item1} becomes {item.Item3} without sending twice");
}
Console.WriteLine($"Completed: {passed} push contract/security checks. Provider responses are simulated; no real device delivery is claimed.");
sealed class Fake(Func<HttpRequestMessage,Task<HttpResponseMessage>> respond):HttpMessageHandler{
    public int Calls{get;private set;}
    protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request,CancellationToken ct){Calls++;return respond(request);}
}
