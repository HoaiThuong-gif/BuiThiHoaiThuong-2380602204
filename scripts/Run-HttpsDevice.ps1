param([Parameter(Mandatory=$true)][string]$DeviceId)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$configFile=Join-Path $root 'mobile/config/api.tunnel.local.json'
$config=Get-Content -Raw -Encoding utf8 -LiteralPath $configFile|ConvertFrom-Json
$url=$null
if(![Uri]::TryCreate($config.API_BASE_URL,[UriKind]::Absolute,[ref]$url) -or $url.Scheme -ne 'https' -or $url.HostNameType -ne [UriHostNameType]::Dns -or !$url.Host.EndsWith('.devtunnels.ms')){throw 'Chưa có cấu hình Dev Tunnels HTTPS thật. Chạy Start-HttpsTest.ps1 trước.'}
if($DeviceId -like 'emulator-*'){throw 'Hãy dùng device ID Samsung/tablet thật.'}
$health=Invoke-RestMethod ($url.AbsoluteUri.TrimEnd('/')+'/health') -Headers @{Accept='application/json'} -TimeoutSec 25
if($health.status -ne 'ready'){throw 'Tunnel hoặc SQL Server chưa sẵn sàng.'}
Push-Location -LiteralPath (Join-Path $root 'mobile')
try{flutter run -d $DeviceId --dart-define-from-file=config/api.tunnel.local.json;if($LASTEXITCODE -ne 0){throw 'Chưa chạy được ứng dụng.'}}finally{Pop-Location}
