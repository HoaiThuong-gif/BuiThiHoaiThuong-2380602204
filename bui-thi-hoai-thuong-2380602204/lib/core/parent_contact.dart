import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import 'api.dart';
import 'widgets.dart';

String parentPhoneNumber(dynamic value) {
  final text = '$value'.trim();
  if (!RegExp(r'^[+0-9 ()-]+$').hasMatch(text)) return '';
  final number = text.replaceAll(RegExp(r'[ ()-]'), '');
  return RegExp(r'^\+?[0-9]{3,15}$').hasMatch(number) ? number : '';
}

// Mở bàn phím gọi điện; người dùng tự bấm Gọi trong ứng dụng Điện thoại.
Future<void> openParentDialer(BuildContext context, List contacts) async {
  final available = <Json>[
    for (final contact in contacts)
      if (contact is Map &&
          parentPhoneNumber(contact['phoneNumber']).isNotEmpty)
        Map<String, dynamic>.from(contact),
  ];
  String number;
  if (available.isEmpty) {
    final openPhone = await showDialog<bool>(
      context: context,
      builder: (dialog) => AlertDialog(
        title: const AppText('Chưa có số điện thoại bố mẹ'),
        content: const AppText(
          'Nhờ bố mẹ vào Tài khoản → Hồ sơ cá nhân để thêm số điện thoại. Con có thể mở ứng dụng Điện thoại và nhập số cần gọi.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialog, false),
            child: const AppText('Đóng'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialog, true),
            child: const AppText('Mở ứng dụng Điện thoại'),
          ),
        ],
      ),
    );
    if (openPhone != true) return;
    number = '';
  } else {
    final selected = available.length == 1
        ? available.first
        : await showDialog<Json>(
            context: context,
            builder: (dialog) => SimpleDialog(
              title: const AppText('Liên hệ bố mẹ'),
              children: [
                for (final contact in available)
                  SimpleDialogOption(
                    onPressed: () => Navigator.pop(dialog, contact),
                    child: AppText(
                      '${contact['fullName']}\n${contact['phoneNumber']}',
                    ),
                  ),
              ],
            ),
          );
    if (selected == null) return;
    number = parentPhoneNumber(selected['phoneNumber']);
  }
  if (!context.mounted) return;
  try {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      await deviceChannel.invokeMethod<void>('dial', {'number': number});
    } else {
      final opened = await launchUrl(
        Uri(scheme: 'tel', path: number),
        mode: LaunchMode.externalApplication,
      );
      if (!opened && context.mounted) {
        toast(context, 'Chưa mở được ứng dụng Điện thoại trên thiết bị này.');
      }
    }
  } catch (_) {
    if (context.mounted) {
      toast(
        context,
        'Chưa mở được ứng dụng Điện thoại. Hãy nhờ bố mẹ kiểm tra ứng dụng gọi điện mặc định.',
      );
    }
  }
}
