import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'appearance.dart';
import 'biometric_login.dart';

typedef Json = Map<String, dynamic>;
const deviceChannel = MethodChannel('vn.nhombar/device');

class Api {
  static const baseUrl = String.fromEnvironment('API_BASE_URL');
  final Dio dio = Dio(
    BaseOptions(
      baseUrl: baseUrl,
      headers: {'Accept': 'application/json'},
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 25),
    ),
  );
  final storage = const FlutterSecureStorage();
  final biometrics = BiometricLogin();
  Json? user;
  VoidCallback? onSessionEnded;
  VoidCallback? onNoticeOpened;
  String? pendingNotice;
  String? token;
  Future<void>? refreshing;
  Api() {
    dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (o, h) {
          if (token != null) o.headers['Authorization'] = 'Bearer $token';
          h.next(o);
        },
        onError: (e, h) async {
          if (e.response?.statusCode == 401 &&
              e.requestOptions.extra['retried'] != true &&
              !e.requestOptions.path.contains('/auth/')) {
            try {
              refreshing ??= refresh().whenComplete(() => refreshing = null);
              await refreshing;
            } catch (problem) {
              final expired =
                  problem is DioException &&
                      [401, 403].contains(problem.response?.statusCode) ||
                  problem is PlatformException && problem.code == 'session';
              if (expired) {
                await clear(endMonitoring: false);
                return h.next(e);
              }
              return h.reject(
                DioException(
                  requestOptions: e.requestOptions,
                  type: DioExceptionType.connectionError,
                  error: problem,
                ),
              );
            }
            e.requestOptions.extra['retried'] = true;
            e.requestOptions.headers['Authorization'] = 'Bearer $token';
            try {
              return h.resolve(await dio.fetch(e.requestOptions));
            } on DioException catch (retryError) {
              if (retryError.response?.statusCode == 401) {
                await clear(endMonitoring: false);
              }
              return h.reject(retryError);
            }
          }
          h.next(e);
        },
      ),
    );
  }
  bool get configured {
    final uri = Uri.tryParse(baseUrl);
    if (uri == null || !uri.hasAuthority || uri.userInfo.isNotEmpty) {
      return false;
    }
    if (kReleaseMode) {
      return uri.scheme == 'https' &&
          (uri.path.isEmpty || uri.path == '/') &&
          uri.query.isEmpty &&
          uri.fragment.isEmpty &&
          uri.port == 443 &&
          uri.host.contains('.') &&
          !RegExp(r'^\d+\.\d+\.\d+\.\d+$').hasMatch(uri.host) &&
          !uri.host.contains(':') &&
          ![
            'localhost',
            '.localhost',
            '.local',
            '.lan',
            '.internal',
            '.test',
            '.invalid',
            '.localdomain',
          ].any((suffix) => uri.host.toLowerCase().endsWith(suffix));
    }
    return uri.scheme == 'https' || uri.scheme == 'http';
  }

  Future<bool> restore() async {
    if (!configured) return false;
    final role = await storage.read(key: 'role');
    // Phiên phụ huynh/admin chỉ mở bằng OTP hoặc sinh trắc học + backend.
    // Luồng QR và dịch vụ nền của con giữ nguyên.
    if (role != 'Child') return false;
    token = await storage.read(key: 'access');
    if (role != null) user = {'role': role};
    final cachedProfile = await storage.read(key: 'profile');
    if (cachedProfile != null) {
      try {
        user = Map<String, dynamic>.from(jsonDecode(cachedProfile) as Map);
      } catch (_) {
        /* Read older installations without a saved profile. */
      }
    }
    if (token == null) return false;
    if (user?['role'] == 'Child') {
      // Preserve the native service's latest rotated credentials when the app URL changes.
      unawaited(
        deviceChannel
            .invokeMethod<void>('configureConnection', {'baseUrl': baseUrl})
            .catchError((Object _) {}),
      );
    }
    try {
      user = Map<String, dynamic>.from(await get('/api/users/me'));
      await storage.write(key: 'profile', value: jsonEncode(user));
      await appearance.selectAccount('$baseUrl/${user?['id']}');
      return true;
    } catch (e) {
      if (e is DioException &&
          [401, 403, 404].contains(e.response?.statusCode)) {
        return false;
      }
      // A temporary outage must not look like the user signed out.
      final restored = token != null && user?['role'] != null;
      if (restored) await appearance.selectAccount('$baseUrl/${user?['id']}');
      return restored;
    }
  }

  Future<void> save(Json data) async {
    final nextUser = Map<String, dynamic>.from(data['user'] as Map);
    final enrolled = await storage.read(key: 'biometricUser');
    if (nextUser['role'] == 'Child' ||
        enrolled != null && enrolled != nextUser['id']) {
      await biometrics.disable();
    }
    token = data['accessToken'] as String;
    user = nextUser;
    await storage.write(key: 'access', value: token);
    await storage.write(key: 'role', value: user?['role'] as String?);
    await storage.write(key: 'profile', value: jsonEncode(user));
    await storage.write(key: 'refresh', value: data['refreshToken'] as String);
    if (appearanceAccount != user?['id']) {
      appearanceAccount = user?['id'] as String?;
      await appearance.selectAccount('$baseUrl/$appearanceAccount');
    }
    if (user?['role'] == 'Child') {
      try {
        await deviceChannel.invokeMethod('credentials', {
          'baseUrl': baseUrl,
          'accessToken': token,
          'refreshToken': data['refreshToken'],
        });
      } on MissingPluginException {
        /* Android only. */
      }
    }
  }

  String? appearanceAccount;

  Future<void> cacheProfile(Json profile) async {
    user = profile;
    await storage.write(key: 'profile', value: jsonEncode(profile));
  }

  Future<bool> enableBiometrics() async {
    if (user == null || user?['role'] == 'Child') return false;
    if (!await biometrics.authenticate()) return false;
    try {
      await refresh(); // Chỉ bật khi backend xác nhận phiên vẫn còn hiệu lực.
    } catch (e) {
      if (e is DioException &&
          [400, 401, 403].contains(e.response?.statusCode)) {
        await clear(endMonitoring: false);
      }
      rethrow;
    }
    await biometrics.enable(user!['id'] as String, baseUrl);
    return true;
  }

  Future<bool> biometricSignIn() async {
    if (!await biometrics.enabled(baseUrl)) return false;
    if (!await biometrics.authenticate()) return false;
    final owner = await storage.read(key: 'biometricUser');
    try {
      // Không dùng access token/profile cache để bỏ qua backend.
      token = null;
      user = null;
      await refresh();
      if (user?['id'] != owner || user?['role'] == 'Child') {
        await clear(endMonitoring: false);
        return false;
      }
      return true;
    } catch (e) {
      if (e is DioException &&
              [400, 401, 403].contains(e.response?.statusCode) ||
          e is PlatformException && e.code == 'session') {
        await clear(endMonitoring: false);
      }
      rethrow;
    }
  }

  Future<void> refresh() async {
    if (user?['role'] == 'Child') {
      final response = await deviceChannel.invokeMethod<String>(
        'refreshCredentials',
      );
      await save(Map<String, dynamic>.from(jsonDecode(response!) as Map));
      return;
    }
    final r = await storage.read(key: 'refresh');
    if (r == null || r.isEmpty) {
      throw PlatformException(
        code: 'session',
        message: 'Vui lòng đăng nhập bằng mật khẩu và OTP.',
      );
    }
    final d = await Dio(
      BaseOptions(
        baseUrl: baseUrl,
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 25),
      ),
    ).post('/api/auth/refresh', data: {'refreshToken': r});
    await save(Map<String, dynamic>.from(d.data as Map));
  }

  Future<void> clear({bool endMonitoring = true}) async {
    if (endMonitoring) {
      try {
        await deviceChannel.invokeMethod('clearCredentials');
      } on MissingPluginException {
        /* Android only. */
      }
    }
    token = null;
    user = null;
    appearanceAccount = null;
    await appearance.selectAccount(null);
    await storage.deleteAll();
    onSessionEnded?.call();
  }

  Future<void> logout() async {
    await post('/api/auth/logout', {});
    await clear();
  }

  Future<bool> lock() async {
    if (user == null ||
        user?['role'] == 'Child' ||
        !await biometrics.enabled(baseUrl, user?['id'] as String?)) {
      return false;
    }
    final refreshToken = await storage.read(key: 'refresh');
    if (refreshToken == null || refreshToken.isEmpty) return false;
    // Giữ phiên mã hóa để lần mở sau xác thực sinh trắc học rồi hỏi backend.
    token = null;
    user = null;
    appearanceAccount = null;
    await appearance.selectAccount(null);
    onSessionEnded?.call();
    return true;
  }

  Future<dynamic> get(String path) async => (await dio.get<dynamic>(path)).data;
  Future<dynamic> post(String path, dynamic data) async =>
      (await dio.post<dynamic>(path, data: data)).data;
  Future<dynamic> put(String path, dynamic data) async =>
      (await dio.put<dynamic>(path, data: data)).data;
  Future<void> delete(String path, [dynamic data]) async {
    await dio.delete<dynamic>(path, data: data);
  }

  static bool temporaryFailure(Object error) {
    if (error is! DioException) return false;
    final status = error.response?.statusCode;
    return status == null || status >= 500 || status == 408 || status == 429;
  }

  static String message(Object e) {
    if (e is DioException) {
      final d = e.response?.data;
      if (d is Map && d['message'] is String) return d['message'] as String;
      if (e.response?.statusCode == 401) {
        return 'Phiên đăng nhập đã kết thúc. Vui lòng đăng nhập lại.';
      }
      if (e.response?.statusCode == 429) {
        return 'Vui lòng chờ một phút rồi thử lại.';
      }
      if (e.response?.statusCode == 403) {
        return 'Bạn chưa được phép thực hiện thao tác này.';
      }
      if ((e.response?.statusCode ?? 0) >= 500) {
        return 'Dịch vụ đang tạm gián đoạn. Vui lòng thử lại sau.';
      }
      final host = Uri.tryParse(baseUrl)?.host ?? '';
      if (!kReleaseMode &&
          (host == 'localhost' ||
              RegExp(r'^(10\.|127\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.)')
                  .hasMatch(host))) {
        return 'NhomBar chưa sẵn sàng kết nối. Vui lòng thử lại sau hoặc liên hệ hỗ trợ.';
      }
      return 'Chưa liên lạc được với dịch vụ. Hãy thử lại khi có kết nối Internet.';
    }
    if (e is PlatformException) {
      return e.message ?? 'Điện thoại chưa thể thực hiện thao tác này.';
    }
    return 'Chưa thể thực hiện. Vui lòng thử lại.';
  }
}
