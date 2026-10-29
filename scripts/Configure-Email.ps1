$ErrorActionPreference='Stop'
$projectRoot=Split-Path -Parent $PSScriptRoot
$settingsPath=Join-Path $projectRoot 'backend/appsettings.local.json'
if(!(Test-Path -LiteralPath $settingsPath)){throw 'Chạy Initialize-Local.ps1 trước để tạo cấu hình máy chủ.'}
$sender=(Read-Host 'Địa chỉ gửi đã xác minh trong Brevo').Trim()
try {$address=[System.Net.Mail.MailAddress]::new($sender);if($address.Address -ne $sender -or $sender -notmatch '@[^@]+\.[^@]+$'){throw 'Invalid sender'}}catch{throw 'Địa chỉ gửi không hợp lệ.'}
$secret=Read-Host 'Dán Brevo API key (không hiện ký tự)' -AsSecureString
$pointer=[Runtime.InteropServices.Marshal]::SecureStringToBSTR($secret)
try {
    $apiKey=[Runtime.InteropServices.Marshal]::PtrToStringBSTR($pointer).Trim()
    if($apiKey.Length -lt 20){throw 'Khóa không hợp lệ. Hãy dùng API key, không dùng SMTP key.'}
    $settings=Get-Content -Raw -Encoding utf8 -LiteralPath $settingsPath|ConvertFrom-Json
    $settings|Add-Member -Force NoteProperty Email ([pscustomobject]@{Brevo=[pscustomobject]@{SenderEmail=$sender;ApiKey=$apiKey}})
    $settings.PSObject.Properties.Remove('Smtp')
    $json=$settings|ConvertTo-Json -Depth 16
    [IO.File]::WriteAllText($settingsPath,$json,[Text.UTF8Encoding]::new($false))
    Write-Host 'Đã lưu cấu hình riêng trên laptop. Không chia sẻ file appsettings.local.json. Máy chủ đang chạy sẽ tự đọc thay đổi.'
} finally {
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($pointer)
    $apiKey=$null;$json=$null;$settings=$null;$secret.Dispose()
}
