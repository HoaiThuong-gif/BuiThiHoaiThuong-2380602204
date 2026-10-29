param([int]$Port=5080)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$cli=Join-Path $root 'artifacts/tools/devtunnel.exe'
$stateFile=Join-Path $root 'secrets/devtunnel.local.json'
$logFile=Join-Path $root 'artifacts/week6-devtunnel-host.log'
if(!(Test-Path -LiteralPath $cli)){throw 'Chưa có Dev Tunnels CLI. Xem phần cài đặt HTTPS trong README.md, không nhập URL ví dụ của giáo trình.'}
$signature=Get-AuthenticodeSignature -LiteralPath $cli
if($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch 'Microsoft Corporation'){throw 'Chữ ký công cụ chưa hợp lệ.'}
try{$health=Invoke-RestMethod "http://127.0.0.1:$Port/health" -TimeoutSec 5}catch{throw 'Máy chủ chưa sẵn sàng. Chạy scripts/Start-Backend.ps1 trước; không đổi hoặc tạo lại database.'}
if($health.status -ne 'ready'){throw 'Máy chủ chưa xác nhận SQL Server sẵn sàng.'}
$login=& $cli user show 2>&1
if(($login -join ' ') -match 'Not logged in'){
    & $cli user login
    if($LASTEXITCODE -ne 0){throw 'Chưa đăng nhập Dev Tunnels. Không tạo URL thay thế.'}
}
New-Item -ItemType Directory -Force -Path (Join-Path $root 'secrets')|Out-Null
if(Test-Path -LiteralPath $stateFile){$state=Get-Content -Raw -Encoding utf8 -LiteralPath $stateFile|ConvertFrom-Json}
else{
    $name='nhombar-2380602204-'+[Guid]::NewGuid().ToString('N').Substring(0,6)
    $json=& $cli create $name --allow-anonymous --expiration 7d --json
    if($LASTEXITCODE -ne 0){throw 'Chưa tạo được tunnel; không tự đổi sang dịch vụ trả phí.'}
    $created=($json -join "`n")|ConvertFrom-Json
    $state=[pscustomobject]@{tunnelId=$created.tunnel.tunnelId;port=$Port;kind='InternetTesting';publicUrl=$null}
    & $cli port create $state.tunnelId -p $Port --protocol http --json|Out-Null
    if($LASTEXITCODE -ne 0){throw 'Chưa mở được cổng tunnel.'}
    [IO.File]::WriteAllText($stateFile,($state|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
}
if($state.port -ne $Port){throw 'Cổng đã lưu khác cổng yêu cầu; không tự đổi cấu hình đang dùng.'}
if($state.publicUrl){
    try{$online=Invoke-RestMethod ($state.publicUrl+'/health') -Headers @{Accept='application/json'} -TimeoutSec 10;if($online.status -eq 'ready'){
        New-Item -ItemType Directory -Force -Path (Join-Path $root 'mobile/config')|Out-Null
        [IO.File]::WriteAllText((Join-Path $root 'mobile/config/api.tunnel.local.json'),(@{API_BASE_URL=$state.publicUrl}|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
        Write-Host ('Tunnel đang hoạt động: '+$state.publicUrl);return
    }}catch{}
}
# Reuse the same tunnel ID. The URL must come from Microsoft's output, never a guessed hostname.
$process=Start-Process -FilePath $cli -ArgumentList @('host',$state.tunnelId) -WindowStyle Hidden -RedirectStandardOutput $logFile -RedirectStandardError (Join-Path $root 'artifacts/week6-devtunnel-error.log') -PassThru
$url=$null
for($attempt=0;$attempt -lt 30;$attempt++){
    if(Test-Path -LiteralPath $logFile){$text=Get-Content -Raw -Encoding utf8 -LiteralPath $logFile;$match=[regex]::Match($text,'Connect via browser:\s*(https://[a-z0-9-]+\.[a-z0-9-]+\.devtunnels\.ms)');if($match.Success){$url=$match.Groups[1].Value;break}}
    if($process.HasExited){throw 'Tunnel đã dừng. Xem artifacts/week6-devtunnel-error.log.'}
    Start-Sleep -Seconds 1
}
if(!$url){throw 'Chưa nhận được URL HTTPS thật. Không chạy Flutter bằng địa chỉ đoán.'}
$check=Invoke-RestMethod ($url+'/health') -Headers @{Accept='application/json'} -TimeoutSec 25
if($check.status -ne 'ready'){throw 'HTTPS chưa xác nhận máy chủ sẵn sàng.'}
$state.publicUrl=$url
[IO.File]::WriteAllText($stateFile,($state|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
New-Item -ItemType Directory -Force -Path (Join-Path $root 'mobile/config')|Out-Null
[IO.File]::WriteAllText((Join-Path $root 'mobile/config/api.tunnel.local.json'),(@{API_BASE_URL=$url}|ConvertTo-Json),[Text.UTF8Encoding]::new($false))
Write-Host ('HTTPS kiểm thử: '+$url)
Write-Host 'Laptop, SQL Server, máy chủ và Dev Tunnels vẫn phải bật. Đây chưa phải production.'
