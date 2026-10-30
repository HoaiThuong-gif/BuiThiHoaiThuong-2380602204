# NhomBar — Bùi Thị Hoài Thương — 2380602204

Nhánh `frontend` chứa Flutter ngay tại gốc repository. Tên thư mục project để mở trong Android Studio phải là **bui-thi-hoai-thuong-2380602204**, có `pubspec.yaml`, `lib/`, `android/`, `assets/` ngay bên trong.

## Tải và mở đúng project

Chạy tại nơi chưa có thư mục trùng tên:

```powershell
git clone --branch frontend --single-branch https://github.com/HoaiThuong-gif/BuiThiHoaiThuong-2380602204.git bui-thi-hoai-thuong-2380602204
Set-Location bui-thi-hoai-thuong-2380602204
flutter pub get
```

1. Cài Flutter SDK, Android SDK Platform 37 và plugin **Flutter/Dart** của Android Studio.
2. Chọn **File → Open**, mở chính thư mục **bui-thi-hoai-thuong-2380602204** vừa clone. Không chọn riêng `android/` và không tạo project mới.
3. Nếu IDE yêu cầu Flutter SDK, chọn SDK đã cài, ví dụ `D:\LTDD\Developmant\flutter`.
4. Mở Terminal tại project, chạy `flutter pub get`, chờ IDE lập chỉ mục và Gradle sync.
5. Thiết lập API theo mục dưới. Chọn cấu hình **NhomBar** từ `.run/NhomBar.run.xml`, chọn điện thoại rồi Run.
6. Nếu tạo Run Configuration thủ công, chọn Flutter, entrypoint `lib/main.dart`, Additional run args `--dart-define-from-file=config/api.tunnel.local.json`.

Thư mục Project và Gradle root mang tên **bui-thi-hoai-thuong-2380602204**. Dart package trong `pubspec.yaml` vẫn là **nhombar**, vì tên package Dart không hỗ trợ dấu gạch ngang. Đây là hai tên phục vụ hai mục đích khác nhau.

## Kết nối API và chạy

Backend, SQL Server và Brevo cần hoạt động trước. [Nhánh main](https://github.com/HoaiThuong-gif/BuiThiHoaiThuong-2380602204/tree/main) có hướng dẫn đầy đủ chạy backend/tunnel. [Nhánh backend](https://github.com/HoaiThuong-gif/BuiThiHoaiThuong-2380602204/tree/backend) được giữ nguyên. Không đưa khóa backend vào Flutter.

Chạy tại gốc frontend, nhập URL HTTPS thật đang hoạt động:

```powershell
$apiUrl = Read-Host 'URL HTTPS goc cua backend, khong them /api hoac /swagger'
Invoke-RestMethod ($apiUrl.TrimEnd('/') + '/health') -Headers @{Accept='application/json'}
New-Item -ItemType Directory -Force config | Out-Null
@{API_BASE_URL=$apiUrl.TrimEnd('/')} | ConvertTo-Json | Set-Content -Encoding utf8 config/api.tunnel.local.json
flutter devices
$deviceId = Read-Host 'Ma thiet bi Android tu flutter devices'
flutter run -d $deviceId --dart-define-from-file=config/api.tunnel.local.json
```

Health phải trả `status: ready`. File API cục bộ không nằm trong Git, nên cần tạo lại sau khi clone. Giữ máy chủ và tunnel hoạt động; không dùng `localhost` của laptop làm địa chỉ API trên điện thoại.

## Build

```powershell
flutter build apk --debug --dart-define-from-file=config/api.tunnel.local.json
```

APK ở `build/app/outputs/flutter-apk/app-debug.apk`. Script `scripts/Build-Android.ps1` cũng nhận diện Flutter tại gốc nhánh này. Bản release cần keystore và backend production phù hợp.

## Source và cấu hình

Giữ nguyên app **NhomBar**, applicationId/namespace **vn.nhombar.nhombar**, Java Android, Firebase client `android/app/google-services.json`, AndroidManifest và MethodChannel. Các chức năng đăng nhập/OTP, sinh trắc học, hồ sơ, giao diện, QR trẻ em, phân quyền, GPS, tiếng ồn, giới hạn thời gian, Voice Time Guard và gọi phụ huynh được giữ nguyên.

Các thư mục `test/`, `integration_test/`, `tool/`, `scripts/`, `assets/` và cấu hình `.metadata` thuộc frontend. QR công cụ xuất vào `build/` hoặc đường dẫn được truyền vào. Cấu hình `*.local.json`, `local.properties`, keystore, Firebase service account, build và cache không được commit. Firebase client hiện có không phải khóa riêng của backend.

Trên nhánh `main`, Flutter tương ứng nằm trong thư mục con `bui-thi-hoai-thuong-2380602204/`, còn backend ở `backend/`. Việc đổi cấu trúc không thay đổi logic nghiệp vụ hay xóa dữ liệu trên điện thoại/SQL Server.
