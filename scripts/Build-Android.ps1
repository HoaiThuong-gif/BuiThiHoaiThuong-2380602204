param([Parameter(Mandatory=$true)][string]$ApiUrl,[switch]$Release)
$ErrorActionPreference='Stop'
$frontendPath = & (Join-Path $PSScriptRoot 'Get-FrontendPath.ps1')
$parsedUrl=$null
if(-not [Uri]::TryCreate($ApiUrl,[UriKind]::Absolute,[ref]$parsedUrl)){throw 'Địa chỉ máy chủ không hợp lệ.'}
if($Release -and ($parsedUrl.Scheme -ne 'https' -or $parsedUrl.Port -ne 443 -or $parsedUrl.IsLoopback -or $parsedUrl.HostNameType -ne [UriHostNameType]::Dns -or !$parsedUrl.Host.Contains('.') -or $parsedUrl.Host -match '(localhost|\.local|\.lan|\.internal|\.test|\.invalid|\.localdomain)$' -or $parsedUrl.AbsolutePath -ne '/' -or $parsedUrl.UserInfo -or $parsedUrl.Query -or $parsedUrl.Fragment)){throw 'Bản phát hành cần tên miền HTTPS công khai thật.'}
if($Release -and -not $env:NHOMBAR_KEYSTORE){throw 'Cần cấu hình khóa ký bản phát hành theo README.md.'}
if($Release){
    foreach($name in @('NHOMBAR_STORE_PASSWORD','NHOMBAR_KEY_ALIAS','NHOMBAR_KEY_PASSWORD')){if(![Environment]::GetEnvironmentVariable($name)){throw "Thiếu cấu hình ký: $name"}}
    if(!(Test-Path -LiteralPath $env:NHOMBAR_KEYSTORE)){throw 'Không tìm thấy kho khóa ký.'}
    $health=Invoke-RestMethod -Uri ($ApiUrl.TrimEnd('/')+'/health/deployment') -TimeoutSec 60
    if($health.environment -ne 'Production' -or !$health.database -or !$health.schemaCurrent -or !$health.emailConfigured -or !$health.pushConfigured -or $health.publicUrl.TrimEnd('/') -ne $ApiUrl.TrimEnd('/')){throw 'Máy chủ production chưa sẵn sàng. Không tạo APK phân phối.'}
    $clientPath=Join-Path $frontendPath 'android/app/google-services.json'
    $client=Get-Content -Raw -Encoding utf8 -LiteralPath $clientPath|ConvertFrom-Json
    if($client.project_info.project_id -ne $health.firebaseProjectId){throw 'Firebase của ứng dụng và máy chủ không cùng dự án.'}
}
Push-Location -LiteralPath $frontendPath
try {
    $mode=if($Release){'--release'}else{'--debug'}
    flutter build apk $mode "--dart-define=API_BASE_URL=$ApiUrl"
    if($LASTEXITCODE -ne 0){throw 'Chưa tạo được bản cài đặt.'}
    if($Release){
        $sdk=if($env:ANDROID_HOME){$env:ANDROID_HOME}else{Join-Path $env:LOCALAPPDATA 'Android/Sdk'}
        $signer=Get-ChildItem (Join-Path $sdk 'build-tools') -Recurse -Filter apksigner.bat|Sort-Object FullName -Descending|Select-Object -First 1
        if(!$signer){throw 'Chưa tìm thấy apksigner để kiểm tra chữ ký. Không phân phối APK.'}
        $apk=Join-Path $PWD 'build/app/outputs/flutter-apk/app-release.apk'
        $verified=& $signer.FullName verify --verbose --print-certs $apk 2>&1
        if($LASTEXITCODE -ne 0 -or ($verified -join "`n") -match 'CN=Android Debug'){throw 'Chữ ký APK chưa phù hợp để phân phối.'}
        @{apiUrl=$ApiUrl;sha256=(Get-FileHash -LiteralPath $apk -Algorithm SHA256).Hash;builtAtUtc=[DateTime]::UtcNow.ToString('o');signatureVerified=$true}|ConvertTo-Json|Set-Content -Encoding utf8 -LiteralPath ($apk+'.manifest.json')
        Write-Host 'APK release có chữ ký đã được xác minh. Vẫn cần kiểm thử production trước khi phát hành.'
    }
} finally {Pop-Location}
