param([switch]$SeedAccounts)
$ErrorActionPreference='Stop'
$projectRoot=Split-Path -Parent $PSScriptRoot
$backendPath=Join-Path $projectRoot 'backend'
$settingsPath=Join-Path $backendPath 'appsettings.local.json'
if(-not (Test-Path -LiteralPath $settingsPath)) {
    $randomBytes=New-Object byte[] 48
    $randomGenerator=[System.Security.Cryptography.RandomNumberGenerator]::Create()
    try { $randomGenerator.GetBytes($randomBytes) } finally { $randomGenerator.Dispose() }
    @{Jwt=@{Key=[Convert]::ToBase64String($randomBytes)}} | ConvertTo-Json -Depth 6 | Set-Content -Encoding utf8 -LiteralPath $settingsPath
}
Push-Location -LiteralPath $backendPath
try {
    $env:ASPNETCORE_ENVIRONMENT='Development'
    dotnet restore NhomBar.Api.csproj
    if($LASTEXITCODE -ne 0){throw 'Không tải được thư viện .NET.'}
    dotnet build NhomBar.Api.csproj --no-restore
    if($LASTEXITCODE -ne 0){throw 'Chưa biên dịch được máy chủ.'}
    dotnet run --project NhomBar.Api.csproj --no-build -- --migrate
    if($LASTEXITCODE -ne 0){throw 'Chưa tạo được dữ liệu. Hãy kiểm tra SQL Server và quyền của tài khoản Windows.'}
    if($SeedAccounts) {
        $secret=Read-Host 'Mật khẩu ban đầu cho hai tài khoản kiểm thử' -AsSecureString
        $secretPointer=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($secret)
        try {
            $env:Seed__AdminEmail='bththuong05.c23xuantruong@gmail.com'
            $env:Seed__ParentEmail='buithihoaithuongdl@gmail.com'
            $env:Seed__Password=[Runtime.InteropServices.Marshal]::PtrToStringBSTR($secretPointer)
            dotnet run --project NhomBar.Api.csproj --no-build -- --seed
            if($LASTEXITCODE -ne 0){throw 'Chưa tạo được tài khoản.'}
        } finally {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($secretPointer)
            Remove-Item Env:Seed__Password -ErrorAction SilentlyContinue
        }
    }
    Write-Host 'Đã chuẩn bị dữ liệu. Cấu hình gửi email theo README.md trước khi đăng nhập.'
} finally {Pop-Location}
