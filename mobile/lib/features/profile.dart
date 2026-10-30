import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/api.dart';
import '../core/appearance.dart';
import '../core/widgets.dart';

class ProfilePage extends StatefulWidget {
  final Api api;
  const ProfilePage({super.key, required this.api});
  @override
  State<ProfilePage> createState() => _ProfilePageState();
}

class _ProfilePageState extends State<ProfilePage> {
  final form = GlobalKey<FormState>();
  late final name = TextEditingController(
    text: widget.api.user?['fullName'] as String? ?? '',
  );
  late final phone = TextEditingController(
    text: widget.api.user?['phoneNumber'] as String? ?? '',
  );
  late bool sms = widget.api.user?['smsAlertsEnabled'] == true;
  late bool reports = widget.api.user?['emailReportsEnabled'] == true;
  Uint8List? avatar;
  bool busy = false, biometricBusy = false, biometricEnabled = false;
  bool biometricAvailable = false, avatarChanged = false;
  String biometricLabel = '';
  String? error;
  bool get child => widget.api.user?['role'] == 'Child';
  bool get parent => widget.api.user?['role'] == 'Parent';

  @override
  void initState() {
    super.initState();
    readAvatar();
    loadBiometrics();
    loadProfile();
  }

  void readAvatar() {
    final encoded = widget.api.user?['avatarBytes'];
    if (encoded is String) {
      try {
        avatar = base64Decode(encoded);
      } catch (_) {
        avatar = null;
      }
    }
  }

  Future<void> loadProfile() async {
    setState(() => busy = true);
    try {
      final profile = Map<String, dynamic>.from(
        await widget.api.get('/api/users/me') as Map,
      );
      await widget.api.cacheProfile(profile);
      if (!mounted) return;
      setState(() {
        name.text = profile['fullName'] as String? ?? '';
        phone.text = profile['phoneNumber'] as String? ?? '';
        sms = profile['smsAlertsEnabled'] == true;
        reports = profile['emailReportsEnabled'] == true;
        readAvatar();
      });
    } catch (e) {
      if (mounted) setState(() => error = Api.message(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> loadBiometrics() async {
    if (child) return;
    final types = await widget.api.biometrics.available();
    final enabled = await widget.api.biometrics.enabled(
      Api.baseUrl,
      widget.api.user?['id'] as String?,
    );
    if (mounted) {
      setState(() {
        biometricAvailable = types.isNotEmpty;
        biometricLabel = widget.api.biometrics.describe(types);
        biometricEnabled = enabled;
      });
    }
  }

  Future<void> toggleBiometrics(bool value) async {
    setState(() => biometricBusy = true);
    try {
      if (value) {
        final enabled = await widget.api.enableBiometrics();
        if (mounted) {
          toast(
            context,
            enabled
                ? 'Đã bật đăng nhập sinh trắc học.'
                : 'Chưa xác thực. Bạn vẫn dùng được mật khẩu và OTP.',
          );
        }
      } else {
        await widget.api.biometrics.disable();
        if (mounted) toast(context, 'Đã tắt đăng nhập sinh trắc học.');
      }
      await loadBiometrics();
    } catch (e) {
      if (mounted) toast(context, Api.message(e));
    } finally {
      if (mounted) setState(() => biometricBusy = false);
    }
  }

  Future<void> pickAvatar() async {
    try {
      final photo = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 75,
      );
      if (photo == null) return;
      final bytes = await photo.readAsBytes();
      if (!mounted) return;
      if (bytes.length > 262144) {
        toast(context, 'Hãy chọn ảnh JPG hoặc PNG nhỏ hơn 256 KB.');
        return;
      }
      setState(() {
        avatar = bytes;
        avatarChanged = true;
      });
    } catch (e) {
      if (mounted) toast(context, Api.message(e));
    }
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final profile = await widget.api.put('/api/users/me', {
        'fullName': name.text.trim(),
        'phoneNumber': phone.text.trim(),
        if (parent) 'smsAlertsEnabled': sms,
        if (parent) 'emailReportsEnabled': reports,
        if (avatarChanged && avatar != null)
          'avatarBase64': base64Encode(avatar!),
        'removeAvatar': avatarChanged && avatar == null,
      });
      await widget.api.cacheProfile(Map<String, dynamic>.from(profile as Map));
      avatarChanged = false;
      if (mounted) toast(context, 'Đã lưu thông tin cá nhân.');
    } catch (e) {
      if (mounted) setState(() => error = Api.message(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  void dispose() {
    name.dispose();
    phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const AppText('Hồ sơ cá nhân')),
    body: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 720),
        child: Form(
          key: form,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Center(
                child: CircleAvatar(
                  radius: 44,
                  backgroundImage: avatar == null ? null : MemoryImage(avatar!),
                  child: avatar == null
                      ? const Icon(Icons.person, size: 44)
                      : null,
                ),
              ),
              if (!child)
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 12,
                  children: [
                    TextButton(
                      onPressed: busy ? null : pickAvatar,
                      child: const AppText('Chọn ảnh'),
                    ),
                    if (avatar != null)
                      TextButton(
                        onPressed: busy
                            ? null
                            : () => setState(() {
                                avatar = null;
                                avatarChanged = true;
                              }),
                        child: const AppText('Xóa ảnh'),
                      ),
                  ],
                ),
              const SizedBox(height: 16),
              TextFormField(
                controller: name,
                readOnly: child || busy,
                maxLength: 200,
                decoration: const InputDecoration(labelText: 'Họ và tên'),
                validator: (v) =>
                    v == null || v.trim().isEmpty || v.trim().length > 200
                    ? 'Nhập họ tên từ 1 đến 200 ký tự.'
                    : null,
              ),
              const SizedBox(height: 16),
              if (!child) ...[
                TextFormField(
                  initialValue: widget.api.user?['email'] as String? ?? '',
                  readOnly: true,
                  decoration: const InputDecoration(
                    labelText: 'Email đã đăng ký',
                    helperText: 'Email không thể sửa tại đây.',
                    helperMaxLines: 2,
                  ),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: phone,
                  readOnly: busy,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'Số điện thoại liên hệ',
                    helperText: 'Ví dụ: +84901234567',
                  ),
                  validator: (v) =>
                      v != null &&
                          v.trim().isNotEmpty &&
                          !RegExp(r'^\+[1-9]\d{7,14}$').hasMatch(v.trim())
                      ? 'Nhập số điện thoại kèm mã quốc gia.'
                      : null,
                ),
                if (parent) ...[
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const AppText('Nhận tin nhắn khi con cần giúp đỡ'),
                    value: sms,
                    onChanged: busy ? null : (v) => setState(() => sms = v),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const AppText('Nhận báo cáo hằng ngày qua email'),
                    value: reports,
                    onChanged: busy ? null : (v) => setState(() => reports = v),
                  ),
                ],
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: busy ? null : save,
                  child: AppText(busy ? 'Đang tải/lưu...' : 'Lưu'),
                ),
              ] else
                const AppText('Thông tin của con do bố mẹ quản lý.'),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              const SizedBox(height: 24),
              if (!child)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const AppText('Đăng nhập sinh trắc học'),
                  subtitle: AppText(
                    biometricAvailable
                        ? '$biometricLabel. Dùng khi mở lại hoặc chọn Khóa ứng dụng. Đăng xuất sẽ kết thúc phiên và cần OTP lại.'
                        : 'Android chưa cung cấp sinh trắc học đã đăng ký. Hãy kiểm tra Cài đặt của điện thoại.',
                  ),
                  value: biometricEnabled,
                  onChanged:
                      biometricBusy || !biometricAvailable && !biometricEnabled
                      ? null
                      : toggleBiometrics,
                ),
              const SizedBox(height: 24),
              AnimatedBuilder(
                animation: appearance,
                builder: (context, _) => Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppText(
                      'Cỡ chữ',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (var i = 0; i < Appearance.scales.length; i++)
                          ChoiceChip(
                            label: Text(['Nhỏ', 'Vừa', 'Lớn'][i]),
                            selected: appearance.scale == Appearance.scales[i],
                            onSelected: (_) => changeAppearance(
                              textScale: Appearance.scales[i],
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 20),
                    AppText(
                      'Màu nền',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        for (var i = 0; i < Appearance.colors.length; i++)
                          ChoiceChip(
                            avatar: CircleAvatar(
                              backgroundColor: Appearance.colors[i],
                            ),
                            label: Text(Appearance.colorNames[i]),
                            selected: appearance.background == i,
                            onSelected: (_) => changeAppearance(color: i),
                          ),
                      ],
                    ),
                    TextButton(
                      onPressed: () => changeAppearance(textScale: 1, color: 0),
                      child: const AppText('Khôi phục giao diện mặc định'),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );

  Future<void> changeAppearance({double? textScale, int? color}) async {
    try {
      await appearance.update(textScale: textScale, color: color);
    } catch (_) {
      if (mounted) toast(context, 'Chưa lưu được giao diện. Hãy thử lại.');
    }
  }
}
