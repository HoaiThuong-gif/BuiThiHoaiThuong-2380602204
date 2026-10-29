import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import 'api.dart';

class FamilyPush {
  final Api api;
  FamilyPush(this.api);
  StreamSubscription<dynamic>? subscription;
  bool registering = false;
  final status = ValueNotifier<String>(
    'Bạn có thể xem thông báo trong NhomBar.',
  );
  Future<void> start() async {
    if (defaultTargetPlatform != TargetPlatform.android || kIsWeb) return;
    subscription ??= const EventChannel('vn.nhombar/push')
        .receiveBroadcastStream()
        .listen(
          (event) {
            final data = Map<String, dynamic>.from(event as Map);
            if (data['kind'] == 'token') {
              unawaited(register());
            } else if (data['id'] != null) {
              unawaited(
                receipt(
                  '${data['id']}',
                  data['kind'] == 'opened' ? 'opened' : 'received',
                ),
              );
            }
          },
          onError: (_) {
            status.value = 'Thông báo trên điện thoại chưa sẵn sàng.';
          },
        );
    try {
      if (api.user?['role'] != 'Child' &&
          !await Permission.notification.request().isGranted) {
        status.value = 'Chưa được cho phép hiện thông báo trên điện thoại.';
        return;
      }
      await register();
      final initial = await deviceChannel.invokeMethod<String>('initialNotice');
      if (initial != null) await receipt(initial, 'opened');
    } catch (_) {
      status.value = 'Thông báo trên điện thoại chưa sẵn sàng.';
    }
  }

  Future<void> register() async {
    if (registering ||
        api.token == null ||
        defaultTargetPlatform != TargetPlatform.android ||
        kIsWeb) {
      return;
    }
    registering = true;
    try {
      final token = await deviceChannel
          .invokeMethod<String>('pushToken')
          .timeout(const Duration(seconds: 20));
      final installation = await deviceChannel.invokeMethod<String>(
        'installationId',
      );
      if (token == null || installation == null) return;
      final registered = await api.post('/api/push/register', {
        'token': token,
        'installationId': installation,
      });
      await deviceChannel.invokeMethod('pushBinding', {
        'binding': registered['binding'],
      });
      status.value = 'Đã đăng ký nhận thông báo trên điện thoại.';
    } catch (_) {
      status.value =
          'Chưa đăng ký được thông báo. Bạn vẫn có thể xem trong NhomBar.';
    } finally {
      registering = false;
    }
  }

  Future<void> receipt(String id, String phase) async {
    if (api.token == null) {
      if (phase == 'opened') api.pendingNotice = id;
      return;
    }
    try {
      final installation = await deviceChannel.invokeMethod<String>(
        'installationId',
      );
      await api.post('/api/push/receipt', {
        'noticeId': id,
        'installationId': installation,
        'phase': phase,
      });
    } catch (_) {}
    if (phase == 'opened') {
      if (api.onNoticeOpened != null) {
        api.onNoticeOpened!();
      } else {
        api.pendingNotice = id;
      }
    }
  }

  Future<void> stop() async {
    await subscription?.cancel();
    subscription = null;
    try {
      await deviceChannel.invokeMethod<void>('clearFamilyNotifications');
    } catch (_) {}
    status.value = 'Bạn có thể xem thông báo trong NhomBar.';
  }
}
