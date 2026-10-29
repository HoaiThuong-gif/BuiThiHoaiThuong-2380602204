using System.Net;
using System.Text.Json;
using Microsoft.Extensions.Configuration;
using Microsoft.Extensions.Logging.Abstractions;
using NhomBar;

int passed=0;
void Assert(bool ok,string name){if(!ok)throw new Exception(name);Console.WriteLine("PASS: "+name);passed++;}
IConfiguration Config(bool key=true)=>new ConfigurationBuilder().AddInMemoryCollection(new Dictionary<string,string?>{
    ["Email:Brevo:ApiKey"]=key?"test-api-key-not-a-real-secret":null,["Email:Brevo:SenderEmail"]="sender@example.com"
}).Build();
var handler=new ResponseHandler(async request=>{
    Assert(request.Method==HttpMethod.Post && request.RequestUri==new Uri("https://api.brevo.com/v3/smtp/email"),"Brevo HTTPS endpoint");
    Assert(request.Headers.GetValues("api-key").Single()=="test-api-key-not-a-real-secret","Backend-only API key header");
    var body=JsonDocument.Parse(await request.Content!.ReadAsStringAsync());
    Assert(body.RootElement.GetProperty("to")[0].GetProperty("email").GetString()=="recipient@example.com" && body.RootElement.GetProperty("textContent").GetString()!.Contains("012345"),"Recipient and six-digit code payload");
    return new HttpResponseMessage(HttpStatusCode.Created){Content=new StringContent("{\"messageId\":\"<test-id>\"}")};
});
await new BrevoEmail(new HttpClient(handler),Config(),NullLogger<BrevoEmail>.Instance).Send("recipient@example.com","012345");
Assert(handler.Calls==1,"201 with messageId accepted once");
foreach(var (status,body) in new[]{(200,"{\"messageId\":\"x\"}"),(201,"{}"),(201,"{\"messageId\":\"\"}"),(201,"invalid"),(400,"bad request"),(401,"private provider detail"),(429,"quota"),(500,"unavailable")}){
    var fake=new ResponseHandler(_=>Task.FromResult(new HttpResponseMessage((HttpStatusCode)status){Content=new StringContent(body)}));
    try{await new BrevoEmail(new HttpClient(fake),Config(),NullLogger<BrevoEmail>.Instance).Send("recipient@example.com","012345");throw new Exception("Unexpected success");}
    catch(AppError e){Assert(e.Status==503 && !e.Message.Contains(body) && fake.Calls==1,$"Reject status {status}, invalid/missing receipt, no retry ({body.Length} chars)");}
}
foreach(var error in new Exception[]{new HttpRequestException("private connection detail"),new TaskCanceledException("timeout")}){
    var fake=new ResponseHandler(_=>Task.FromException<HttpResponseMessage>(error));
    try{await new BrevoEmail(new HttpClient(fake),Config(),NullLogger<BrevoEmail>.Instance).Send("recipient@example.com","012345");throw new Exception("Unexpected success");}
    catch(AppError e){Assert(e.Status==503 && !e.Message.Contains(error.Message) && fake.Calls==1,"Uncertain result uses friendly error, no retry: "+error.GetType().Name);}
}
var unused=new ResponseHandler(_=>throw new Exception("Must not call provider"));
try{await new BrevoEmail(new HttpClient(unused),Config(false),NullLogger<BrevoEmail>.Instance).Send("recipient@example.com","012345");throw new Exception("Unexpected success");}
catch(AppError e){Assert(e.Status==503 && unused.Calls==0,"Missing configuration never reports sent or calls provider");}
Console.WriteLine($"Completed: {passed} Email API contract checks. HTTP responses are simulated; no real email delivery is claimed.");
sealed class ResponseHandler(Func<HttpRequestMessage,Task<HttpResponseMessage>> respond):HttpMessageHandler{
    public int Calls{get;private set;}
    protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request,CancellationToken cancellationToken){Calls++;return respond(request);}
}
