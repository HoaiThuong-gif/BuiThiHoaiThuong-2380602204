$ErrorActionPreference='Stop'
$nativeCapture=Join-Path $PSScriptRoot 'artifacts/native-test'
$nativeFixture=Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $nativeCapture 'fixture.json') | ConvertFrom-Json
if($nativeFixture.database -notmatch '^NhomBarNativeTests_[a-f0-9]{32}$'){throw 'Expected an isolated Android test database.'}
$nativeApi='http://127.0.0.1:5091'
$nativeSerial='emulator-5580'
$nativeAdb=Join-Path $env:LOCALAPPDATA 'Android/Sdk/platform-tools/adb.exe'
$nativeResults=Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'artifacts/native-test'
New-Item -ItemType Directory -Path $nativeResults -Force | Out-Null
function Invoke-NativeAdb {
    $result=& $nativeAdb -s $nativeSerial @args
    if($LASTEXITCODE -ne 0){throw 'Android test command failed.'}
    return $result
}
function Invoke-NativeApi {
    param([string]$Path,[string]$Method='Get',$Body=$null,[string]$Token='')
    $parameters=@{Uri=$nativeApi+$Path;Method=$Method;ContentType='application/json; charset=utf-8'}
    if($Token){$parameters.Headers=@{Authorization='Bearer '+$Token}}
    if($null -ne $Body){$parameters.Body=$Body|ConvertTo-Json -Depth 12 -Compress}
    return Invoke-RestMethod @parameters
}
function Read-NativeCode {
    param([string]$Email)
    $sha=[Security.Cryptography.SHA256]::Create()
    try{$hash=[BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($Email))).Replace('-','')}finally{$sha.Dispose()}
    return (Get-Content -Raw -LiteralPath (Join-Path $nativeCapture ($hash+'.code'))).Trim()
}
function Login-NativeUser {
    param([string]$Email)
    $challenge=Invoke-NativeApi '/api/auth/login' Post @{email=$Email;password='Hutech@123'}
    return Invoke-NativeApi '/api/auth/verify-otp' Post @{challengeId=$challenge.challengeId;code=(Read-NativeCode $Email);purpose='login'}
}
function Save-NativeSessions {
    param($Sessions)
    ($Sessions|ConvertTo-Json -Depth 12)|ConvertTo-SecureString -AsPlainText -Force|Export-Clixml -LiteralPath (Join-Path $nativeResults 'sessions.xml')
}
function Read-NativeSessions {
    $encrypted=Import-Clixml -LiteralPath (Join-Path $nativeResults 'sessions.xml')
    $pointer=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($encrypted)
    try{return ([Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer)|ConvertFrom-Json)}finally{[Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)}
}
function Read-NativeUi {
    Invoke-NativeAdb shell uiautomator dump /data/local/tmp/nhombar-native-ui.xml | Out-Null
    Invoke-NativeAdb pull /data/local/tmp/nhombar-native-ui.xml (Join-Path $nativeResults 'ui.xml') | Out-Null
    return [xml](Get-Content -Raw -Encoding utf8 -LiteralPath (Join-Path $nativeResults 'ui.xml'))
}
function Touch-NativeNode {
    param($Node)
    if($null -eq $Node){throw 'Expected Android UI element was not found.'}
    $n=[regex]::Matches($Node.bounds,'\d+')
    Invoke-NativeAdb shell input tap ([int](([int]$n[0].Value+[int]$n[2].Value)/2)) ([int](([int]$n[1].Value+[int]$n[3].Value)/2)) | Out-Null
}
function Touch-NativeLabel {
    param([string]$Label)
    $ui=Read-NativeUi
    $node=$ui.SelectNodes('//node') | Where-Object {$_.'content-desc' -eq $Label -or $_.text -eq $Label} | Select-Object -First 1
    Touch-NativeNode $node
}
