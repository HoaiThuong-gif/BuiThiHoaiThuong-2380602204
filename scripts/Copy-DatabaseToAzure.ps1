param([Parameter(Mandatory=$true)][string]$SqlHost,[switch]$ConfirmEmptyTarget)
$ErrorActionPreference='Stop'
if(!$ConfirmEmptyTarget -or $SqlHost -notmatch '^[a-z0-9-]+\.database\.windows\.net$'){throw 'Cần xác nhận database Azure đích trống và đúng tên máy chủ. Không có dữ liệu nào bị thay đổi.'}
$root=Split-Path -Parent $PSScriptRoot
$parameters=Get-Content -Raw -Encoding utf8 (Join-Path $root 'secrets/azure-parameters.local.json')|ConvertFrom-Json
$builder=New-Object System.Data.SqlClient.SqlConnectionStringBuilder
$builder['Data Source']='tcp:'+$SqlHost+',1433';$builder['Initial Catalog']='NhomBar2380602204';$builder['User ID']='nhombar_owner';$builder['Password']=$parameters.parameters.sqlAdminPassword.value;$builder['Encrypt']=$true;$builder['TrustServerCertificate']=$false;$builder['Connect Timeout']=30
$env:NHOMBAR_TARGET_SQL=$builder.ConnectionString
Push-Location -LiteralPath $root
try{
    dotnet build tools/DatabaseTransfer/DatabaseTransfer.csproj -c Release -o artifacts/database-transfer --verbosity quiet
    if($LASTEXITCODE -ne 0){throw 'Chưa biên dịch được công cụ chuyển dữ liệu.'}
    dotnet artifacts/database-transfer/DatabaseTransfer.dll --confirm-empty-target
    if($LASTEXITCODE -ne 0){throw 'Chuyển dữ liệu chưa hoàn tất; không tạo tài khoản ứng dụng.'}
    $connection=New-Object System.Data.SqlClient.SqlConnection $builder.ConnectionString
    try{$connection.Open();$command=$connection.CreateCommand();$command.CommandText=[IO.File]::ReadAllText((Join-Path $root 'infra/azure/create-app-user.sql'));$command.Parameters.Add('@AppPassword',[Data.SqlDbType]::NVarChar,128).Value=$parameters.parameters.sqlAppPassword.value;[void]$command.ExecuteNonQuery()}finally{$connection.Dispose()}
    Write-Host 'Đã đối chiếu dữ liệu và cấp tài khoản API chỉ đọc/ghi. SQL Server laptop được giữ nguyên.'
}finally{Remove-Item Env:NHOMBAR_TARGET_SQL -ErrorAction SilentlyContinue;$builder=$null;$parameters=$null;Pop-Location}
