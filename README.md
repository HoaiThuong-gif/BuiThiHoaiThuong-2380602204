# Cách tải và chạy NhomBar từ đầu

## Bước 1. Cài phần mềm

Cài lần lượt:

1. Git for Windows.
2. Flutter SDK có Dart từ 3.13.3 trở lên; thêm thư mục `flutter\bin` vào `PATH`.
3. Android Studio và plugin Flutter, Dart. Trong SDK Manager, cài Android SDK Platform 37, Android SDK Build-Tools, Platform-Tools và Command-line Tools. Dùng JDK đi kèm Android Studio phù hợp với Gradle của dự án.
4. .NET SDK 8. Nếu mở backend bằng Visual Studio, cài thêm workload **ASP.NET and web development**.
5. SQL Server và SQL Server Management Studio (SSMS). Ghi nhớ tên instance đã cài, ví dụ `.` hoặc `.\SQLEXPRESS`.

Mở PowerShell mới và kiểm tra:

```powershell
git --version
flutter --version
dotnet --list-sdks
flutter doctor
flutter doctor --android-licenses
```

Chấp nhận các giấy phép Android. Sửa các lỗi liên quan Flutter/Android trong `flutter doctor` trước khi tiếp tục; không cần cài công cụ Windows desktop để chạy Android.

## Bước 2. Tải source từ GitHub

Mở terminal tại nơi muốn lưu source:

```powershell
git clone https://github.com/HoaiThuong-gif/BuiThiHoaiThuong-2380602204.git bui-thi-hoai-thuong-2380602204
Set-Location bui-thi-hoai-thuong-2380602204
```

Thư mục này gọi là **gốc dự án** trong các bước sau, có `backend`, `mobile` và `scripts`. Các terminal mới cần mở tại đây.

## Bước 3. Cấu hình SQL Server và khóa đăng nhập

1. Mở Services, bảo đảm dịch vụ SQL Server đang chạy.
2. Mở SSMS, chọn Windows Authentication và kết nối instance vừa cài.
3. Tại gốc dự án, chạy đoạn sau; nhập đúng tên server đã kết nối trong SSMS:

```powershell
$serverName = Read-Host 'Tên SQL Server trong SSMS, ví dụ . hoặc .\SQLEXPRESS'
$settingsPath = Join-Path (Get-Location) 'backend/appsettings.local.json'
if (Test-Path -LiteralPath $settingsPath) { throw 'Đã có cấu hình riêng. Mở file hiện tại để chỉnh, không ghi đè.' }
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

Đoạn lệnh tạo `backend/appsettings.local.json`, dùng tài khoản Windows hiện tại và khóa ngẫu nhiên. Không đưa file này lên Git. Cấu hình SQL trên dành cho chạy cục bộ.

## Bước 4. Tạo database bằng EF Core Migrations

Tại gốc dự án:

```powershell
./scripts/Initialize-Local.ps1
```

Script tải thư viện .NET, biên dịch và áp dụng migrations vào database `NhomBar2380602204`. Tài khoản Windows cần quyền tạo database. Trong SSMS, làm mới mục Databases để thấy kết quả.

Khi đã có database và cần áp dụng migration mới, dùng:

```powershell
$env:ASPNETCORE_ENVIRONMENT = 'Development'
dotnet run --project backend/NhomBar.Api.csproj -- --migrate
```

Không cần chạy cả hai lệnh cho cùng một lần thiết lập. Không xóa database hoặc chạy lại `schema.sql` trên database đang có dữ liệu.

## Bước 5. Cấu hình gửi mã email

1. Tạo tài khoản Brevo.
2. Thêm và xác minh địa chỉ gửi thư trong phần Senders.
3. Tạo API key trong SMTP & API → API Keys. Không dùng mật khẩu email hoặc SMTP key.
4. Tại gốc dự án:

```powershell
./scripts/Configure-Email.ps1
```

Nhập địa chỉ gửi đã xác minh và API key khi script hỏi. Khóa được lưu trong cấu hình riêng, không ghi vào source. Cần hoàn thành bước này để đăng ký/đăng nhập và nhận mã email.

## Bước 6. Cấu hình thông báo Firebase

1. Trong Firebase Console, tạo hoặc chọn dự án bạn có quyền quản lý.
2. Đăng ký ứng dụng Android với package `vn.nhombar.nhombar`.
3. Tải file cấu hình ứng dụng `google-services.json`, đặt vào `mobile/android/app/google-services.json`. Nếu dùng file có sẵn, cần quyền quản lý đúng dự án Firebase đó.
4. Trong Project settings → Service accounts, tạo khóa tài khoản dịch vụ và tải JSON về vị trí riêng ngoài source.
5. Tại gốc dự án:

```powershell
./scripts/Configure-Push.ps1
```

Nhập đường dẫn file tài khoản dịch vụ khi được hỏi. Hai file Firebase phải cùng dự án. File có `private_key` chỉ dùng trên backend, không chép vào `mobile` hoặc đưa lên Git.

## Bước 7. Chạy backend

Mở một terminal tại gốc dự án:

```powershell
./scripts/Start-Backend.ps1
```

Giữ terminal mở. Trong trình duyệt trên laptop, truy cập:

```text
http://127.0.0.1:5080/swagger
```

Có thể mở `backend/NhomBar.sln` bằng Visual Studio để đọc và chỉnh backend. Lệnh trên chạy bằng .NET SDK, không bắt buộc dùng Visual Studio.

Mở terminal thứ hai tại gốc dự án và kiểm tra:

```powershell
Invoke-RestMethod 'http://127.0.0.1:5080/health'
```

Phải nhận `status: ready` trước bước tiếp theo. Nếu lỗi, kiểm tra dịch vụ SQL, tên instance, quyền tài khoản và cấu hình ở bước 3.

## Bước 8. Tạo địa chỉ HTTPS để điện thoại kết nối

1. Tải Dev Tunnels CLI dành cho Windows theo [hướng dẫn Microsoft](https://learn.microsoft.com/en-us/azure/developer/dev-tunnels/get-started).
2. Tại gốc dự án, tạo thư mục chứa công cụ:

```powershell
New-Item -ItemType Directory -Force -Path artifacts/tools
```

3. Đặt công cụ đã tải thành `artifacts/tools/devtunnel.exe`.
4. Khi backend đang chạy, tại terminal thứ hai:

```powershell
./scripts/Start-HttpsTest.ps1
```

Đăng nhập Microsoft khi công cụ yêu cầu. Script tạo/dùng lại đường hầm và ghi URL thực vào `mobile/config/api.tunnel.local.json`. Không tự điền URL mẫu.

Kiểm tra kết nối:

```powershell
$connection = Get-Content -Raw -Encoding UTF8 'mobile/config/api.tunnel.local.json' | ConvertFrom-Json
Invoke-RestMethod ($connection.API_BASE_URL.TrimEnd('/') + '/health') -Headers @{Accept='application/json'}
```

Phải nhận `ready`. Giữ laptop, SQL Server, backend và đường hầm hoạt động; điện thoại cần có Internet.

## Bước 9. Cắm điện thoại Android

1. Bật Tùy chọn nhà phát triển và Gỡ lỗi USB trên điện thoại.
2. Cắm cáp truyền dữ liệu, mở khóa máy, chấp nhận thông báo cho phép gỡ lỗi.
3. Tại gốc dự án:

```powershell
flutter devices
```

Ghi lại mã thiết bị Android. Nếu không thấy, kiểm tra cáp/driver và quyền gỡ lỗi trên điện thoại.

## Bước 10. Chạy ứng dụng Flutter

Trong terminal tại gốc dự án:

```powershell
Set-Location mobile
flutter pub get
$deviceId = Read-Host 'Dán mã thiết bị Android từ flutter devices'
flutter run -d $deviceId --dart-define-from-file=config/api.tunnel.local.json
```

Nếu dùng Android Studio: mở thư mục `mobile`, mở `lib/main.dart`, chọn điện thoại. Trong Run → Edit Configurations → Additional run args, nhập `--dart-define-from-file=config/api.tunnel.local.json` rồi bấm Run.

Muốn nhập địa chỉ HTTPS khác đã kiểm tra, chạy tại `mobile`:

```powershell
$apiUrl = Read-Host 'Địa chỉ gốc HTTPS thật, không thêm /api hoặc /swagger'
flutter run -d $deviceId "--dart-define=API_BASE_URL=$apiUrl"
```

Không dùng `localhost` làm địa chỉ API trên điện thoại. Đổi `API_BASE_URL` cần chạy/build lại app.

## Bước 11. Vào ứng dụng lần đầu

Trên điện thoại phụ huynh, đăng ký tài khoản rồi nhập mã nhận qua email. Tạo hồ sơ con và mở mã QR kết nối. Trên máy trẻ, chọn kết nối với bố mẹ, quét QR; phụ huynh đối chiếu thông tin và xác nhận.

Cấp quyền theo thông báo: xem thời gian sử dụng để theo dõi, thông báo để nhận lời nhắc, máy ảnh để quét QR, vị trí khi đồng ý chia sẻ, micro khi đo tiếng ồn. Bật cập nhật và lời nhắc trên máy trẻ. Quét QR không tự cấp quyền khóa toàn bộ thiết bị Android.

## Bước 12. Tạo APK để cài thử

Tại thư mục `mobile`, với backend/HTTPS đã cấu hình:

```powershell
flutter build apk --debug --dart-define-from-file=config/api.tunnel.local.json
```

Lấy file `mobile/build/app/outputs/flutter-apk/app-debug.apk` tính từ gốc dự án, chép sang điện thoại và cho phép cài từ nguồn đã chọn. Đây là bản debug để thử.

Để chạy lại hôm sau, mở SQL Server, thực hiện bước 7–8 rồi chạy/cài app. Không cần tạo lại database, tài khoản hoặc cấu hình email/Firebase nếu vẫn dùng máy và dịch vụ đã thiết lập.
