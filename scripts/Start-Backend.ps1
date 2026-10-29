param([string]$BindAddress='127.0.0.1')
$ErrorActionPreference='Stop'
Push-Location -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) 'backend')
try {
    $env:ASPNETCORE_ENVIRONMENT='Development'
    dotnet build NhomBar.Api.csproj -p:UseAppHost=false --verbosity quiet
    if($LASTEXITCODE -ne 0){throw 'Chưa biên dịch được máy chủ.'}
    dotnet bin/Debug/net8.0/NhomBar.Api.dll --urls "http://${BindAddress}:5080"
} finally {Pop-Location}
