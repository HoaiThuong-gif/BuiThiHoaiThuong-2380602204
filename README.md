# Tải và chạy ứng dụng Android NhomBar

## Bước 1. Cài công cụ

Cài Git, Flutter SDK có Dart từ 3.13.3 trở lên, Android Studio và plugin Flutter/Dart. Trong SDK Manager, cài Android SDK Platform 37, Build-Tools, Platform-Tools và Command-line Tools.

Mở PowerShell mới:

```powershell
flutter doctor
flutter doctor --android-licenses
```

Chấp nhận giấy phép và hoàn tất các mục Flutter/Android mà công cụ báo thiếu.

## Bước 2. Tải nhánh frontend

```powershell
git clone --branch frontend --single-branch https://github.com/HoaiThuong-gif/BuiThiHoaiThuong-2380602204.git bui-thi-hoai-thuong-2380602204
Set-Location bui-thi-hoai-thuong-2380602204
```

Nếu cần tự chạy backend trên laptop, tải nhánh `main` ở một thư mục riêng và làm các bước trong README của nhánh đó để có địa chỉ HTTPS. Các bước bên dưới cần backend đã chạy.

## Bước 3. Chuẩn bị cấu hình Firebase Android

Trong Firebase Console, tải `google-services.json` của ứng dụng có package `vn.nhombar.nhombar`, lưu tại `mobile/android/app/google-services.json`. File cần cùng dự án Firebase đã cấu hình trên backend. Nếu dùng file có sẵn, cần backend dùng đúng dự án đó. Không đặt file tài khoản dịch vụ có `private_key` vào ứng dụng.

## Bước 4. Lấy địa chỉ backend

Lấy URL HTTPS thật từ người chạy backend; địa chỉ gốc không thêm `/api`, `/swagger` hoặc `/health`. Trong PowerShell:

```powershell
$apiUrl = Read-Host 'Dán URL HTTPS gốc của backend đang chạy'
Invoke-RestMethod ($apiUrl.TrimEnd('/') + '/health') -Headers @{Accept='application/json'}
```

Chỉ tiếp tục khi nhận `status: ready`. Nếu dùng đường hầm tới laptop, laptop và backend phải giữ hoạt động. Không dùng `localhost` làm URL trên điện thoại.

## Bước 5. Cắm điện thoại

Bật Tùy chọn nhà phát triển và Gỡ lỗi USB, cắm cáp truyền dữ liệu, mở khóa máy rồi chấp nhận quyền gỡ lỗi. Xem mã thiết bị:

```powershell
flutter devices
```

## Bước 6. Chạy Flutter

```powershell
Set-Location mobile
flutter pub get
$deviceId = Read-Host 'Dán mã thiết bị Android từ flutter devices'
flutter run -d $deviceId "--dart-define=API_BASE_URL=$apiUrl"
```

Hoặc mở thư mục `mobile` bằng Android Studio, chọn `lib/main.dart` và điện thoại. Trong Run → Edit Configurations → Additional run args, điền `--dart-define=API_BASE_URL=` rồi nối URL HTTPS thật phía sau dấu `=`; bấm Run. Đổi URL cần chạy/build lại.

## Bước 7. Đăng nhập và kết nối máy trẻ

Trên máy phụ huynh, đăng ký rồi nhập mã email. Tạo hồ sơ con và mở QR kết nối. Máy trẻ chọn kết nối với bố mẹ, quét QR; phụ huynh đối chiếu và xác nhận thiết bị.

Cấp các quyền được hỏi theo thao tác sử dụng: máy ảnh, thông báo, xem thời gian sử dụng, vị trí hoặc micro. Bật cập nhật/lời nhắc trên máy trẻ. QR gia đình không tự cấp quyền khóa toàn bộ Android.

## Bước 8. Tạo APK cài thử

Tại `mobile`, giữ biến `$apiUrl` từ bước 4 trong cùng terminal:

```powershell
flutter build apk --debug "--dart-define=API_BASE_URL=$apiUrl"
```

Lấy `mobile/build/app/outputs/flutter-apk/app-debug.apk` tính từ gốc source, chép tới điện thoại để cài thử.
