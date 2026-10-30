$ErrorActionPreference='Stop'
$frontendPath = & (Join-Path $PSScriptRoot 'Get-FrontendPath.ps1')
$root=Split-Path -Parent $PSScriptRoot
$clientPath=Join-Path $frontendPath 'android/app/google-services.json'
if(!(Test-Path -LiteralPath $clientPath)){throw 'Lưu google-services.json của ứng dụng Android vào bui-thi-hoai-thuong-2380602204/android/app trước.'}
$source=(Read-Host 'Đường dẫn file JSON tài khoản dịch vụ Firebase (chỉ dùng trên máy chủ)').Trim('"')
$service=Get-Content -Raw -Encoding utf8 -LiteralPath $source|ConvertFrom-Json
$client=Get-Content -Raw -Encoding utf8 -LiteralPath $clientPath|ConvertFrom-Json
if($service.type -ne 'service_account' -or !$service.private_key -or $service.project_id -ne $client.project_info.project_id){throw 'Hai file cần thuộc cùng dự án Firebase. Không dùng file Android làm khóa máy chủ.'}
$packages=@($client.client|ForEach-Object {$_.client_info.android_client_info.package_name})
if($packages -notcontains 'vn.nhombar.nhombar'){throw 'Ứng dụng Firebase cần package vn.nhombar.nhombar.'}
$secretFolder=Join-Path $root 'secrets'
New-Item -ItemType Directory -Force -Path $secretFolder|Out-Null
$privatePath=Join-Path $secretFolder 'firebase-service-account.local.json'
if((Resolve-Path -LiteralPath $source).Path -ne $privatePath){Copy-Item -LiteralPath $source -Destination $privatePath -Force}
$settingsPath=Join-Path $root 'backend/appsettings.local.json'
$settings=Get-Content -Raw -Encoding utf8 -LiteralPath $settingsPath|ConvertFrom-Json
$settings|Add-Member -Force NoteProperty Push ([pscustomobject]@{Firebase=[pscustomobject]@{ServiceAccountPath=$privatePath}})
[IO.File]::WriteAllText($settingsPath,($settings|ConvertTo-Json -Depth 16),[Text.UTF8Encoding]::new($false))
$service=$null;$settings=$null
Write-Host 'Đã cấu hình thông báo cho máy chủ. Cần build/cài lại APK sau khi thêm google-services.json. Không chia sẻ file trong secrets.'
