param([Parameter(Mandatory=$true)][string]$OperatorIp,[ValidateSet('FreeEvaluation','BasicPaid')][string]$HostingMode='FreeEvaluation',[string]$ResourceGroup='nhombar-2380602204',[string]$Location='southeastasia',[ValidateSet('Prepare','WhatIf','Create')][string]$Action='Prepare',[switch]$ConfirmCreate,[switch]$ApprovePaid)
$ErrorActionPreference='Stop'
$root=Split-Path -Parent $PSScriptRoot
$parsedIp=$null
if(![System.Net.IPAddress]::TryParse($OperatorIp,[ref]$parsedIp) -or $parsedIp.AddressFamily -ne 'InterNetwork'){throw 'Cần IPv4 công khai của máy chạy chuyển dữ liệu.'}
if($Action -eq 'Create' -and (!$ConfirmCreate -or ($HostingMode -eq 'BasicPaid' -and !$ApprovePaid))){throw 'Chưa xác nhận tạo tài nguyên hoặc chưa phê duyệt gói có phí. Không có tài nguyên nào được tạo.'}
$settings=Get-Content -Raw -Encoding utf8 (Join-Path $root 'backend/appsettings.local.json')|ConvertFrom-Json
if(!$settings.Email.Brevo.ApiKey -or !$settings.Email.Brevo.SenderEmail){throw 'Cấu hình Brevo trước bằng Configure-Email.ps1.'}
$firebasePath=$settings.Push.Firebase.ServiceAccountPath
if(!$firebasePath -or !(Test-Path -LiteralPath $firebasePath)){throw 'Cấu hình khóa máy chủ Firebase trước bằng Configure-Push.ps1.'}
$firebase=Get-Content -Raw -Encoding utf8 -LiteralPath $firebasePath
if(($firebase|ConvertFrom-Json).type -ne 'service_account'){throw 'Sai loại khóa Firebase.'}
$folder=Join-Path $root 'secrets'
New-Item -ItemType Directory -Force -Path $folder|Out-Null
$path=Join-Path $folder 'azure-parameters.local.json'
function New-Secret { $bytes=New-Object byte[] 40;$rng=[Security.Cryptography.RandomNumberGenerator]::Create();try{$rng.GetBytes($bytes);return ([Convert]::ToBase64String($bytes)+'aA9!')}finally{$rng.Dispose()} }
if(Test-Path -LiteralPath $path){$parameters=Get-Content -Raw -Encoding utf8 -LiteralPath $path|ConvertFrom-Json}
else{$parameters=[pscustomobject]@{'$schema'='https://schema.management.azure.com/schemas/2019-04-01/deploymentParameters.json#';contentVersion='1.0.0.0';parameters=[pscustomobject]@{sqlAdminPassword=@{value=(New-Secret)};sqlAppPassword=@{value=(New-Secret)};jwtKey=@{value=(New-Secret)}}}}
foreach($item in @{location=$Location;hostingMode=$HostingMode;operatorIp=$OperatorIp;brevoApiKey=$settings.Email.Brevo.ApiKey;senderEmail=$settings.Email.Brevo.SenderEmail;firebaseServiceAccountJson=$firebase}.GetEnumerator()){$parameters.parameters|Add-Member -Force NoteProperty $item.Key @{value=$item.Value}}
[IO.File]::WriteAllText($path,($parameters|ConvertTo-Json -Depth 20),[Text.UTF8Encoding]::new($false))
Write-Host "Đã chuẩn bị cấu hình riêng. Gói: $HostingMode. Chưa tạo tài nguyên Azure."
if($Action -eq 'Prepare'){return}
if(!(Get-Command az -ErrorAction SilentlyContinue)){throw 'Cài Azure CLI chính thức và chạy az login trước.'}
& az account show --query '{name:name,state:state}' -o table
if($LASTEXITCODE -ne 0){throw 'Chưa đăng nhập Azure.'}
$template=Join-Path $root 'infra/azure/main.bicep'
if($Action -eq 'WhatIf'){
    & az deployment group what-if --resource-group $ResourceGroup --template-file $template --parameters ('@'+$path)
}else{
    & az group create --name $ResourceGroup --location $Location --output none
    if($LASTEXITCODE -ne 0){throw 'Chưa tạo được resource group.'}
    & az deployment group create --name nhombar-production --resource-group $ResourceGroup --template-file $template --parameters ('@'+$path) --query properties.outputs -o json
}
if($LASTEXITCODE -ne 0){throw 'Azure chưa xác nhận thao tác thành công. Không tự đổi sang gói có phí.'}
