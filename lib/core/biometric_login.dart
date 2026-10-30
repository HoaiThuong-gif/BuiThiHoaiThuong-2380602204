import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:local_auth/local_auth.dart';

class BiometricLogin {
  final auth = LocalAuthentication();
  final storage = const FlutterSecureStorage();

  Future<List<BiometricType>> available() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return [];
    try {
      if (!await auth.canCheckBiometrics) return [];
      return await auth.getAvailableBiometrics();
    } catch (_) {
      return [];
    }
  }

  // Android mới thường chỉ trả mức strong/weak, không trả tên cảm biến.
  String describe(List<BiometricType> types) {
    final names = <String>[
      if (types.contains(BiometricType.fingerprint)) 'Vân tay',
      if (types.contains(BiometricType.face)) 'Khuôn mặt',
    ];
    return names.isEmpty
        ? 'Sinh trắc học do Android cung cấp'
        : names.join(' / ');
  }

  Future<bool> authenticate() async {
    if ((await available()).isEmpty) return false;
    try {
      return await auth.authenticate(
        localizedReason: 'Xác thực để đăng nhập NhomBar trên thiết bị này',
        biometricOnly: true,
      );
    } catch (_) {
      // Hủy, khóa tạm thời hoặc lỗi cảm biến: vẫn dùng mật khẩu và OTP.
      return false;
    }
  }

  Future<bool> enabled(String server, [String? userId]) async {
    try {
      final owner = await storage.read(key: 'biometricUser');
      return owner != null &&
          (userId == null || owner == userId) &&
          await storage.read(key: 'biometricServer') == server;
    } catch (_) {
      return false;
    }
  }

  Future<void> enable(String userId, String server) async {
    await storage.write(key: 'biometricServer', value: server);
    await storage.write(key: 'biometricUser', value: userId);
  }

  Future<void> disable() async {
    await storage.delete(key: 'biometricUser');
    await storage.delete(key: 'biometricServer');
  }
}
