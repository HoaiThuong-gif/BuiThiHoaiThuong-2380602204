param([string]$DeviceId='R5CRC0C2T3V')
$ErrorActionPreference='Stop'
$projectRoot=Split-Path -Parent $PSScriptRoot
$adb=Join-Path $env:LOCALAPPDATA 'Android/Sdk/platform-tools/adb.exe'
if($DeviceId -like 'emulator-*'){throw 'Hãy chọn điện thoại USB, không chọn máy ảo.'}
$devices=& $adb devices -l
$devices|Write-Host
if(!($devices -match ('^'+[regex]::Escape($DeviceId)+'\s+device(?:\s|$)'))){throw 'Chưa nhận điện thoại USB. Mở khóa và cho phép gỡ lỗi USB trên điện thoại.'}
$flutterCommand=(Get-Command flutter -ErrorAction SilentlyContinue).Source
if(!$flutterCommand){
    $properties=Join-Path $projectRoot 'mobile/android/local.properties'
    $sdkLine=Get-Content -LiteralPath $properties|Where-Object {$_ -like 'flutter.sdk=*'}|Select-Object -First 1
    $sdkPath=$sdkLine.Substring('flutter.sdk='.Length).Replace('\:',':').Replace('\\','\')
    $flutterCommand=Join-Path $sdkPath 'bin/flutter.bat'
    if(!(Test-Path -LiteralPath $flutterCommand)){throw 'Chưa tìm thấy Flutter trên laptop.'}
}
$phoneLines=& $adb -s $DeviceId shell ip -o -4 addr show
$tether=@($phoneLines|Where-Object {$_ -match '^\d+:\s+(?:rndis|usb|ncm)\w*\s+inet\s+'})
if($tether.Count -ne 1){throw 'Điện thoại đã chọn chưa bật Chia sẻ kết nối USB. Cắm cáp không đồng nghĩa đã có mạng USB; không dùng nhầm mạng của máy khác.'}
$match=[regex]::Match($tether[0],'\binet\s+(\d+\.\d+\.\d+\.\d+)/(\d+)')
if(!$match.Success){throw 'Chưa đọc được mạng USB của điện thoại đã chọn.'}
$phoneAddress=$match.Groups[1].Value
$phoneBytes=[Net.IPAddress]::Parse($phoneAddress).GetAddressBytes()
$prefix=[int]$match.Groups[2].Value
function Same-PhoneSubnet([string]$Address){
    $bytes=[Net.IPAddress]::Parse($Address).GetAddressBytes()
    for($i=0;$i -lt 4;$i++){
        $bits=[Math]::Min(8,[Math]::Max(0,$prefix-8*$i))
        $mask=[int](256-[Math]::Pow(2,8-$bits))
        if(($bytes[$i] -band $mask) -ne ($phoneBytes[$i] -band $mask)){return $false}
    }
    return $true
}
$adapters=@(Get-NetAdapter|Where-Object {$_.Status -eq 'Up' -and $_.InterfaceDescription -match 'NDIS|Samsung|USB'})
$candidates=@(foreach($adapter in $adapters){Get-NetIPAddress -InterfaceIndex $adapter.ifIndex -AddressFamily IPv4|Where-Object {Same-PhoneSubnet $_.IPAddress}})
if($candidates.Count -ne 1){throw 'Không xác định duy nhất mạng laptop nối với điện thoại đã chọn. Không tự chọn mạng của máy khác.'}
$ip=$candidates[0]
$apiUrl='http://'+$ip.IPAddress+':5080'
Write-Host "Điện thoại: $DeviceId; máy chủ laptop: $apiUrl"
$firewallScript=Join-Path $PSScriptRoot 'Enable-UsbApi.ps1'
$permission=Start-Process -FilePath powershell.exe -Verb RunAs -WindowStyle Hidden -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+$firewallScript+'"'),'-LocalIp',$ip.IPAddress,'-PhoneIp',$phoneAddress,'-RuleName',('NhomBar-USB-'+$DeviceId+'-5080')) -Wait -PassThru
if($permission.ExitCode -ne 0){throw 'Windows chưa cho mở cổng riêng cho điện thoại.'}
$listener=Get-NetTCPConnection -LocalPort 5080 -State Listen -ErrorAction SilentlyContinue|Select-Object -First 1
if($listener){
    $process=Get-CimInstance Win32_Process -Filter ('ProcessId='+$listener.OwningProcess)
    if($process.Name -ne 'NhomBar.Api.exe' -and !($process.Name -eq 'dotnet.exe' -and $process.CommandLine -match 'NhomBar\.Api\.dll')){throw 'Cổng 5080 đang được chương trình khác dùng.'}
}
if(!$listener){
    $startScript=Join-Path $PSScriptRoot 'Start-Backend.ps1'
    Start-Process -FilePath powershell.exe -WindowStyle Hidden -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"'+$startScript+'"'),'-BindAddress','0.0.0.0')|Out-Null
}
$ready=$false
for($i=0;$i -lt 20;$i++){
    try{$health=Invoke-RestMethod ($apiUrl+'/health') -TimeoutSec 2;if($health.status -eq 'ready'){$ready=$true;break}}catch{}
    Start-Sleep -Seconds 1
}
if(!$ready){throw 'Máy chủ chưa sẵn sàng. Xem kết nối SQL Server và Start-Backend.ps1.'}
$request=Join-Path ([IO.Path]::GetTempPath()) ('nhombar-health-'+[Guid]::NewGuid().ToString('N')+'.txt')
try{
    [IO.File]::WriteAllText($request,"GET /health HTTP/1.0`r`nHost: $($ip.IPAddress)`r`nConnection: close`r`n`r`n",[Text.Encoding]::ASCII)
    & $adb -s $DeviceId push $request /data/local/tmp/nhombar-health.txt 2>&1|Out-Null
    $reply=& $adb -s $DeviceId shell "(cat /data/local/tmp/nhombar-health.txt; sleep 2) | toybox nc -w 5 $($ip.IPAddress) 5080" 2>&1
    if(($reply -join ' ') -notmatch 'HTTP/1\.[01] 200'){throw 'Điện thoại chưa gọi được máy chủ. Không chạy app với địa chỉ chưa kết nối được.'}
}finally{Remove-Item -LiteralPath $request -ErrorAction SilentlyContinue}
Push-Location -LiteralPath (Join-Path $projectRoot 'mobile')
try{
    & $flutterCommand devices
    Write-Host "flutter run -d $DeviceId --dart-define=API_BASE_URL=$apiUrl"
    & $flutterCommand run -d $DeviceId "--dart-define=API_BASE_URL=$apiUrl"
    if($LASTEXITCODE -ne 0){throw 'Chưa chạy được ứng dụng trên điện thoại.'}
}finally{Pop-Location}
