param([Parameter(Mandatory=$true)][string]$ApkUrl,[Parameter(Mandatory=$true)][string]$SignedApk)
$ErrorActionPreference='Stop'
$frontendPath = & (Join-Path $PSScriptRoot 'Get-FrontendPath.ps1')
$url=$null
if(![Uri]::TryCreate($ApkUrl,[UriKind]::Absolute,[ref]$url) -or $url.Scheme -ne 'https' -or $url.IsLoopback -or $url.HostNameType -ne [UriHostNameType]::Dns){throw 'Cần URL HTTPS công khai của APK release đã ký.'}
$root=Split-Path -Parent $PSScriptRoot
$folder=Join-Path $root 'artifacts/provisioning'
New-Item -ItemType Directory -Force -Path $folder|Out-Null
$download=Join-Path $folder 'download-check.apk'
Invoke-WebRequest -UseBasicParsing -Uri $url -OutFile $download
$expected=(Get-FileHash -LiteralPath $SignedApk -Algorithm SHA256).Hash
if((Get-FileHash -LiteralPath $download -Algorithm SHA256).Hash -ne $expected){throw 'APK công khai khác bản release đã chọn. Không tạo QR.'}
$bytes=New-Object byte[] 32
for($i=0;$i -lt 32;$i++){$bytes[$i]=[Convert]::ToByte($expected.Substring($i*2,2),16)}
$checksum=[Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+','-').Replace('/','_')
$payload=@{'android.app.extra.PROVISIONING_DEVICE_ADMIN_COMPONENT_NAME'='vn.nhombar.nhombar/vn.nhombar.nhombar.FamilyAdminReceiver';'android.app.extra.PROVISIONING_DEVICE_ADMIN_PACKAGE_DOWNLOAD_LOCATION'=$url.AbsoluteUri;'android.app.extra.PROVISIONING_DEVICE_ADMIN_PACKAGE_CHECKSUM'=$checksum}
$json=Join-Path $folder 'managed-device.json'
[IO.File]::WriteAllText($json,($payload|ConvertTo-Json -Compress),[Text.UTF8Encoding]::new($false))
Push-Location -LiteralPath $frontendPath
try{dart --packages=.dart_tool/package_config.json tool/provision_qr.dart $json (Join-Path $folder 'managed-device.svg');if($LASTEXITCODE -ne 0){throw 'Chưa tạo được hình QR.'}}finally{Pop-Location}
Write-Host 'Chỉ tạo file QR. Chưa cấu hình, đặt lại hay khóa bất kỳ điện thoại nào. Đọc phần quyền quản lý điện thoại trong README.md trước khi sử dụng.'
