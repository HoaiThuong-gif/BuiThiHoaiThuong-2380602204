import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/api.dart';
import '../core/widgets.dart';

/// Chỉ xin quyền từ màn hình trẻ đang mở để trẻ biết và tự xác nhận.
class ChildAccessSetup with WidgetsBindingObserver {
  final Api api;
  BuildContext? context;
  bool checking = false;
  ChildAccessSetup(this.api);
  static Future<void> bindSetup(
    SharedPreferences prefs,
    String deviceId,
  ) async {
    if (prefs.getString('child_setup_device') == deviceId) return;
    for (final key in [
      'child_usage_prompted',
      'child_notifications_prompted',
      'child_location_prompted',
      'child_location_requested',
    ]) {
      await prefs.remove(key);
    }
    await prefs.setString('child_setup_device', deviceId);
  }

  void attach(BuildContext value) {
    context = value;
    WidgetsBinding.instance.addObserver(this);
    unawaited(check());
  }

  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    context = null;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(check());
  }

  static Future<bool> explain(
    BuildContext c,
    String title,
    String detail,
    String action,
  ) async =>
      await showModalBottomSheet<bool>(
        context: c,
        showDragHandle: true,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (sheet) => SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(
                  Icons.family_restroom_rounded,
                  size: 48,
                  color: Theme.of(sheet).colorScheme.primary,
                ),
                const SizedBox(height: 20),
                AppText(title, style: Theme.of(sheet).textTheme.headlineSmall),
                const SizedBox(height: 12),
                AppText(detail),
                const SizedBox(height: 24),
                FilledButton(
                  onPressed: () => Navigator.pop(sheet, true),
                  child: AppText(action),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(sheet, false),
                  child: const AppText('Để sau'),
                ),
              ],
            ),
          ),
        ),
      ) ??
      false;

  Future<void> check({bool force = false}) async {
    final c = context;
    if (checking ||
        c == null ||
        !c.mounted ||
        api.user?['role'] != 'Child' ||
        kIsWeb ||
        defaultTargetPlatform != TargetPlatform.android) {
      return;
    }
    checking = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final status =
          await deviceChannel.invokeMapMethod<String, dynamic>('status') ?? {};
      if (status['deviceId'] is String) {
        await bindSetup(prefs, status['deviceId'] as String);
      }
      if (!c.mounted) return;
      if (status['usageAccess'] != true) {
        if (force || prefs.getBool('child_usage_prompted') != true) {
          await prefs.setBool('child_usage_prompted', true);
          if (!c.mounted) return;
          final agree = await explain(
            c,
            'Cùng bố mẹ theo dõi thời gian',
            'Cho phép NhomBar xem ứng dụng đã mở và thời gian sử dụng để tính thời gian còn lại. Ứng dụng không đọc tin nhắn hay nội dung màn hình. Trong trang tiếp theo, chọn NhomBar và bật quyền, rồi quay lại đây.',
            'Mở phần cấp quyền',
          );
          if (agree) await deviceChannel.invokeMethod('usageSettings');
        }
        return;
      }
      if (prefs.getBool('child_notifications_prompted') != true) {
        await prefs.setBool('child_notifications_prompted', true);
        await Permission.notification.request();
      }
      String? deviceId = status['deviceId'] as String?;
      if (deviceId == null) {
        final profiles = await api.get('/api/children') as List;
        if (profiles.isEmpty) return;
        final devices = await api.get(
          '/api/children/${profiles.first['id']}/devices',
        ) as List;
        if (devices.isEmpty) return;
        deviceId = devices.first['id'] as String;
      }
      await bindSetup(prefs, deviceId);
      if (!c.mounted) return;
      await deviceChannel.invokeMethod('startMonitoring', {
        'deviceId': deviceId,
      });
      if (status['shareLocation'] == true) return;
      if (prefs.getBool('child_location_prompted') != true) {
        await prefs.setBool('child_location_prompted', true);
        if (!c.mounted) return;
        final agree = await explain(
          c,
          'Để bố mẹ biết con đang ở đâu',
          'Khi được cho phép, NhomBar tự cập nhật vị trí kể cả khi con mở ứng dụng khác. Điện thoại sẽ hiện thông báo khi đang chia sẻ. Con và bố mẹ đều biết việc chia sẻ này; có thể tắt trong mục Điện thoại.',
          'Cho phép cập nhật vị trí',
        );
        if (agree && c.mounted) await enableLocation(c);
      } else if (prefs.getBool('child_location_requested') == true &&
          await Permission.locationAlways.isGranted &&
          await Permission.notification.isGranted) {
        await deviceChannel.invokeMethod('shareLocation', {'enabled': true});
      }
    } catch (e) {
      if (force && c.mounted) toast(c, Api.message(e));
    } finally {
      checking = false;
    }
  }

  static Future<bool> enableLocation(BuildContext c) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('child_location_prompted', true);
    await prefs.setBool('child_location_requested', true);
    if (!await Permission.notification.request().isGranted) {
      await prefs.setBool('child_location_requested', false);
      if (c.mounted) {
        toast(
          c,
          'Hãy cho phép thông báo để điện thoại luôn báo rõ khi đang chia sẻ vị trí.',
        );
      }
      return false;
    }
    if (!await Permission.locationWhenInUse.request().isGranted) {
      if (c.mounted) {
        toast(
          c,
          'Chưa được cho phép chia sẻ vị trí. Con vẫn có thể dùng các mục khác.',
        );
      }
      return false;
    }
    if (!c.mounted) return false;
    if (!await Permission.locationAlways.isGranted) {
      if (!c.mounted) return false;
      final agree = await explain(
        c,
        'Tiếp tục cập nhật khi mở ứng dụng khác',
        'Trong quyền vị trí của NhomBar, chọn “Luôn cho phép” hoặc “Cho phép mọi lúc”. Chọn vị trí chính xác nếu muốn bố mẹ xem điểm gần đúng hơn.',
        'Mở cài đặt vị trí',
      );
      if (!agree) {
        await prefs.setBool('child_location_requested', false);
        return false;
      }
      if (!await Permission.locationAlways.request().isGranted) {
        await openAppSettings();
        return false;
      }
    }
    await deviceChannel.invokeMethod('shareLocation', {'enabled': true});
    return true;
  }

  static Future<void> disableLocation() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('child_location_requested', false);
    await deviceChannel.invokeMethod('shareLocation', {'enabled': false});
  }
}
