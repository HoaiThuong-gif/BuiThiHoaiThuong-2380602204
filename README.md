# Tải và chạy backend NhomBar từ đầu

## Bước 1. Cài công cụ

Trên Windows, cài Git, .NET SDK 8, SQL Server và SQL Server Management Studio (SSMS). Nếu dùng Visual Studio, cài workload ASP.NET and web development.

Mở PowerShell mới:

```powershell
git --version
dotnet --list-sdks
```

## Bước 2. Tải nhánh backend

```powershell
git clone --branch backend --single-branch https://github.com/HoaiThuong-gif/BuiThiHoaiThuong-2380602204.git bui-thi-hoai-thuong-2380602204
Set-Location bui-thi-hoai-thuong-2380602204
```

Đây là gốc source cho các lệnh bên dưới. Trong Visual Studio có thể mở `backend/NhomBar.sln` và chọn `NhomBar.Api` làm dự án khởi động.

## Bước 3. Kết nối SQL Server và tạo cấu hình riêng

Bật dịch vụ SQL Server. Mở SSMS, đăng nhập bằng Windows Authentication và ghi đúng tên instance. Tại gốc source:

```powershell
$serverName = Read-Host 'Tên SQL Server trong SSMS, ví dụ . hoặc .\SQLEXPRESS'
$settingsPath = Join-Path (Get-Location) 'backend/appsettings.local.json'
if (Test-Path -LiteralPath $settingsPath) { throw 'Đã có cấu hình riêng; mở file hiện tại để chỉnh, không ghi đè.' }
$randomBytes = New-Object byte[] 48
$generator = [Security.Cryptography.RandomNumberGenerator]::Create()
try { $generator.GetBytes($randomBytes) } finally { $generator.Dispose() }
$settings = @{
    ConnectionStrings = @{
        SqlServer = "Server=$serverName;Database=NhomBar2380602204;Trusted_Connection=True;TrustServerCertificate=True;Encrypt=False"
    }
    Jwt = @{Key = [Convert]::ToBase64String($randomBytes)}
}
$settings | ConvertTo-Json -Depth 6 | Set-Content -Encoding UTF8 -LiteralPath $settingsPath
Remove-Variable settings,randomBytes
```

File cấu hình riêng không đưa lên Git. Chuỗi kết nối này dùng tài khoản Windows cho phát triển trên máy, tài khoản cần quyền tạo database khi cài lần đầu.

## Bước 4. Tạo database bằng migrations

```powershell
./scripts/Initialize-Local.ps1
```

Script tải thư viện, biên dịch và áp dụng migrations vào `NhomBar2380602204`. Làm mới Databases trong SSMS để thấy kết quả.

Khi cần cập nhật migrations sau này, tại gốc source:

```powershell
$env:ASPNETCORE_ENVIRONMENT = 'Development'
dotnet run --project backend/NhomBar.Api.csproj -- --migrate
```

Không cần thực hiện cả hai cách cho cùng lần thiết lập. Không xóa database hoặc chạy lại `schema.sql` trên dữ liệu đang dùng.

## Bước 5. Cấu hình email OTP

Trong Brevo, xác minh địa chỉ gửi rồi tạo API key ở SMTP & API → API Keys. Tại gốc source:

```powershell
./scripts/Configure-Email.ps1
```

Nhập địa chỉ gửi đã xác minh và API key khi được hỏi. Không dùng mật khẩu Gmail hoặc SMTP key; không đưa khóa vào file cấu hình chung.

## Bước 6. Cấu hình Firebase cho backend

Trong Firebase Console, chọn đúng dự án của ứng dụng Android. Vào Project settings → Service accounts để tạo và tải khóa tài khoản dịch vụ JSON về vị trí riêng.

Tại gốc source, nhập đường dẫn file vừa tải:

```powershell
$serviceFile = Read-Host 'Đường dẫn JSON tài khoản dịch vụ Firebase'
$service = Get-Content -Raw -Encoding UTF8 -LiteralPath $serviceFile | ConvertFrom-Json
if ($service.type -ne 'service_account' -or !$service.private_key) { throw 'Cần file tài khoản dịch vụ Firebase.' }
New-Item -ItemType Directory -Force -Path secrets | Out-Null
$privatePath = [IO.Path]::GetFullPath((Join-Path (Get-Location) 'secrets/firebase-service-account.local.json'))
if ((Resolve-Path -LiteralPath $serviceFile).Path -ne $privatePath) {
    Copy-Item -LiteralPath $serviceFile -Destination $privatePath
}
$settingsPath = Join-Path (Get-Location) 'backend/appsettings.local.json'
$settings = Get-Content -Raw -Encoding UTF8 -LiteralPath $settingsPath | ConvertFrom-Json
$settings | Add-Member -Force NoteProperty Push ([pscustomobject]@{
    Firebase = [pscustomobject]@{ServiceAccountPath = $privatePath}
})
$settings | ConvertTo-Json -Depth 16 | Set-Content -Encoding UTF8 -LiteralPath $settingsPath
Remove-Variable service,settings
```

File riêng chỉ dùng trên máy chủ, không đưa lên Git hoặc vào ứng dụng Android. Android phải dùng `google-services.json` thuộc cùng dự án Firebase.

## Bước 7. Chạy API

Tại gốc source:

```powershell
./scripts/Start-Backend.ps1
```

Giữ terminal mở. Mở trình duyệt trên laptop:

```text
http://127.0.0.1:5080/swagger
```

Mở terminal khác tại gốc source để kiểm tra:

```powershell
Invoke-RestMethod 'http://127.0.0.1:5080/health'
```

Phải nhận `status: ready`. Nếu không được, kiểm tra SQL Server, tên instance, quyền tài khoản và cấu hình ở bước 3. Không chạy thêm backend khi cổng 5080 đã được dùng bởi tiến trình đúng.

Để kết nối ứng dụng Android qua Internet, thực hiện phần thiết lập HTTPS trong README nhánh `main`. Không dùng `localhost` của laptop làm địa chỉ máy chủ trên điện thoại.

Khi chạy lại sau khi tắt máy, bật SQL Server rồi làm bước 7. Không cần tạo lại database hoặc tài khoản.
