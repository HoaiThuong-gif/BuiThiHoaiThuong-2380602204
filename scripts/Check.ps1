$ErrorActionPreference='Stop'
$projectRoot=Split-Path -Parent $PSScriptRoot
Push-Location -LiteralPath $projectRoot
try {
    dotnet build tests/ApiChecks/ApiChecks.csproj
    if($LASTEXITCODE -ne 0){throw 'Kiểm tra biên dịch máy chủ thất bại.'}
    dotnet run --project tests/ApiChecks/ApiChecks.csproj --no-build
    if($LASTEXITCODE -ne 0){throw 'Kiểm thử máy chủ thất bại.'}
    dotnet run --project tests/EmailApiChecks/EmailApiChecks.csproj
    if($LASTEXITCODE -ne 0){throw 'Kiểm thử Email API thất bại.'}
    Push-Location -LiteralPath (Join-Path $projectRoot 'mobile')
    try {
        flutter analyze
        if($LASTEXITCODE -ne 0){throw 'Kiểm tra mã ứng dụng thất bại.'}
        flutter test
        if($LASTEXITCODE -ne 0){throw 'Kiểm thử ứng dụng thất bại.'}
    } finally {Pop-Location}
} finally {Pop-Location}
