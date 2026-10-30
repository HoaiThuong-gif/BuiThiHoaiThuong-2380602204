import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/widgets.dart';
import 'link_child.dart';

class AuthPage extends StatefulWidget {
  final Api api;
  final VoidCallback onSignedIn;
  const AuthPage({super.key, required this.api, required this.onSignedIn});
  @override
  State<AuthPage> createState() => _AuthPageState();
}

class _AuthPageState extends State<AuthPage> {
  final form = GlobalKey<FormState>();
  final email = TextEditingController(),
      password = TextEditingController(),
      name = TextEditingController(),
      code = TextEditingController();
  bool register = false, reset = false, busy = false, showPassword = false;
  Json? challenge;
  String? error;
  String purpose = 'login';

  Future<void> signInWithBiometrics() async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final enabled = await widget.api.biometrics.enabled(Api.baseUrl);
      if (!mounted) return;
      if (!enabled) {
        await showDialog<void>(
          context: context,
          builder: (dialog) => AlertDialog(
            title: const AppText('Chưa bật sinh trắc học cho ứng dụng'),
            content: const AppText(
              'Hãy đăng nhập bằng email, mật khẩu và OTP trước, sau đó bật sinh trắc học trong Hồ sơ cá nhân.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialog),
                child: const AppText('Đã hiểu'),
              ),
            ],
          ),
        );
        return;
      }
      final types = await widget.api.biometrics.available();
      if (!mounted) return;
      if (types.isEmpty) {
        toast(
          context,
          'Android chưa cung cấp sinh trắc học đã đăng ký. Hãy kiểm tra Cài đặt của điện thoại.',
        );
        return;
      }
      if (await widget.api.biometricSignIn()) {
        if (mounted) widget.onSignedIn();
      } else if (mounted) {
        setState(
          () =>
              error = 'Chưa xác thực. Bạn có thể dùng email, mật khẩu và OTP.',
        );
      }
    } catch (e) {
      if (mounted) setState(() => error = Api.message(e));
    } finally {
      if (mounted) {
        setState(() => busy = false);
      }
    }
  }

  Future<void> offerBiometrics() async {
    if (await widget.api.biometrics.enabled(
      Api.baseUrl,
      widget.api.user?['id'] as String?,
    )) {
      return;
    }
    if ((await widget.api.biometrics.available()).isEmpty || !mounted) return;
    final enable = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const AppText('Bật đăng nhập sinh trắc học?'),
        content: const AppText(
          'Lần sau, dùng sinh trắc học của Android để mở phiên còn hiệu lực. Bạn cũng có thể bật hoặc tắt trong Hồ sơ cá nhân.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const AppText('Để sau'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const AppText('Bật'),
          ),
        ],
      ),
    );
    if (enable == true) {
      try {
        final enabled = await widget.api.enableBiometrics();
        if (mounted) {
          toast(
            context,
            enabled ? 'Đã bật đăng nhập sinh trắc học.' : 'Chưa bật sinh trắc học. Bạn vẫn có thể dùng mật khẩu và OTP.',
          );
        }
      } catch (e) {
        if (mounted) toast(context, Api.message(e));
      }
    }
  }

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    name.dispose();
    code.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (!form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      if (challenge != null) {
        if (reset) {
          await widget.api.post('/api/auth/reset-password', {
            'challengeId': challenge!['challengeId'],
            'code': code.text,
            'password': password.text,
          });
          if (mounted) {
            toast(context, 'Đã đặt lại mật khẩu. Bạn hãy đăng nhập nhé.');
            setState(() {
              reset = false;
              challenge = null;
              code.clear();
            });
          }
        } else {
          final data = await widget.api.post('/api/auth/verify-otp', {
            'challengeId': challenge!['challengeId'],
            'code': code.text,
            'purpose': purpose,
          });
          await widget.api.save(Map<String, dynamic>.from(data as Map));
          await offerBiometrics();
          if (mounted && widget.api.token != null) widget.onSignedIn();
        }
      } else {
        purpose = reset
            ? 'reset'
            : register
            ? 'register'
            : 'login';
        final d = await widget.api.post(
          '/api/auth/${reset
              ? 'forgot-password'
              : register
              ? 'register'
              : 'login'}',
          {
            'email': email.text.trim(),
            'password': password.text,
            if (register) 'fullName': name.text.trim(),
          },
        );
        if (mounted) {
          setState(() => challenge = Map<String, dynamic>.from(d as Map));
        }
      }
    } catch (e) {
      if (mounted) setState(() => error = Api.message(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext c) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Form(
              key: form,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Icon(
                    Icons.family_restroom_rounded,
                    size: 64,
                    color: Theme.of(c).colorScheme.primary,
                  ),
                  const SizedBox(height: 12),
                  AppText(
                    'NhomBar',
                    textAlign: TextAlign.center,
                    style: Theme.of(c).textTheme.headlineLarge,
                  ),
                  const SizedBox(height: 8),
                  const AppText(
                    'Cùng con tạo thói quen dùng điện thoại lành mạnh.',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 32),
                  AppText(
                    challenge != null
                        ? 'Kiểm tra email của bạn'
                        : reset
                        ? 'Lấy lại mật khẩu'
                        : register
                        ? 'Tạo tài khoản phụ huynh'
                        : 'Chào mừng bạn trở lại',
                    style: Theme.of(c).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 20),
                  if (challenge == null && !reset && !register) ...[
                    FilledButton.icon(
                      onPressed: busy ? null : signInWithBiometrics,
                      icon: const Icon(Icons.fingerprint),
                      label: const AppText('Đăng nhập sinh trắc học'),
                    ),
                    const SizedBox(height: 12),
                    const AppText(
                      'Hoặc dùng email và mật khẩu bên dưới. Cách này vẫn cần OTP.',
                    ),
                    const SizedBox(height: 20),
                  ],
                  if (challenge == null) ...[
                    if (register && !reset)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: TextFormField(
                          controller: name,
                          decoration: InputDecoration(
                            labelText: tr(c, 'Họ và tên'),
                          ),
                          validator: (s) => s == null || s.trim().isEmpty
                              ? tr(c, 'Vui lòng nhập họ tên.')
                              : null,
                        ),
                      ),
                    TextFormField(
                      controller: email,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.email],
                      decoration: InputDecoration(labelText: tr(c, 'Email')),
                      validator: (s) =>
                          s != null &&
                              RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$')
                                  .hasMatch(s.trim())
                          ? null
                          : tr(c, 'Vui lòng nhập đúng email.'),
                    ),
                    const SizedBox(height: 16),
                    if (!reset)
                      TextFormField(
                        controller: password,
                        obscureText: !showPassword,
                        decoration: InputDecoration(
                          labelText: tr(c, 'Mật khẩu'),
                          helperText: register
                              ? tr(
                                  c,
                                  'Ít nhất 10 ký tự, gồm chữ hoa, chữ thường, số và ký tự đặc biệt.',
                                )
                              : null,
                          helperMaxLines: 2,
                          suffixIcon: IconButton(
                            tooltip: showPassword
                                ? 'Ẩn mật khẩu'
                                : 'Hiện mật khẩu',
                            onPressed: () =>
                                setState(() => showPassword = !showPassword),
                            icon: Icon(
                              showPassword
                                  ? Icons.visibility_off
                                  : Icons.visibility,
                            ),
                          ),
                        ),
                        validator: (s) => s == null || s.isEmpty
                            ? tr(c, 'Vui lòng nhập mật khẩu.')
                            : null,
                      ),
                  ] else ...[
                    AppText(
                      challenge!['message'] as String? ??
                          'Bạn hãy kiểm tra hộp thư và mục thư rác.',
                    ),
                    const SizedBox(height: 8),
                    AppText(email.text),
                    const AppText(
                      'Nhập mã gồm 6 số trong email. Mã có hiệu lực trong 5 phút.',
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      controller: code,
                      keyboardType: TextInputType.number,
                      maxLength: 6,
                      autofillHints: const [AutofillHints.oneTimeCode],
                      decoration: InputDecoration(
                        labelText: tr(c, 'Mã xác nhận'),
                      ),
                      validator: (s) =>
                          s != null && RegExp(r'^\d{6}$').hasMatch(s)
                          ? null
                          : tr(c, 'Vui lòng nhập đủ 6 số.'),
                    ),
                    if (reset)
                      TextFormField(
                        controller: password,
                        obscureText: true,
                        decoration: InputDecoration(
                          labelText: tr(c, 'Mật khẩu mới'),
                          helperText: tr(
                            c,
                            'Ít nhất 10 ký tự, gồm chữ hoa, chữ thường, số và ký tự đặc biệt.',
                          ),
                          helperMaxLines: 2,
                        ),
                        validator: (s) => s != null && s.length >= 10
                            ? null
                            : tr(c, 'Mật khẩu cần ít nhất 10 ký tự.'),
                      ),
                    TextButton(
                      onPressed: busy
                          ? null
                          : () async {
                              setState(() => busy = true);
                              try {
                                final d = await widget.api.post(
                                  '/api/auth/resend-otp',
                                  {
                                    'challengeId': challenge!['challengeId'],
                                    'code': '',
                                    'purpose': purpose,
                                  },
                                );
                                if (mounted) {
                                  setState(() {
                                    challenge = Map<String, dynamic>.from(
                                      d as Map,
                                    );
                                    code.clear();
                                    error = null;
                                  });
                                }
                              } catch (e) {
                                if (mounted) {
                                  setState(() => error = Api.message(e));
                                }
                              } finally {
                                if (mounted) setState(() => busy = false);
                              }
                            },
                      child: const AppText('Gửi lại mã'),
                    ),
                  ],
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: AppText(
                        error!,
                        style: TextStyle(color: Theme.of(c).colorScheme.error),
                      ),
                    ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: busy ? null : submit,
                    child: busy
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : AppText(
                            challenge != null
                                ? 'Xác nhận'
                                : reset
                                ? 'Gửi mã xác nhận'
                                : register
                                ? 'Tạo tài khoản'
                                : 'Đăng nhập',
                          ),
                  ),
                  TextButton(
                    onPressed: busy
                        ? null
                        : () => setState(() {
                            if (challenge != null || reset) {
                              challenge = null;
                              reset = false;
                            } else {
                              register = !register;
                            }
                            error = null;
                            code.clear();
                          }),
                    child: AppText(
                      challenge != null || reset
                          ? 'Quay lại đăng nhập'
                          : register
                          ? 'Đã có tài khoản? Đăng nhập'
                          : 'Chưa có tài khoản? Đăng ký',
                    ),
                  ),
                  if (!register && !reset && challenge == null)
                    TextButton(
                      onPressed: busy
                          ? null
                          : () => setState(() => reset = true),
                      child: const AppText('Quên mật khẩu?'),
                    ),
                  if (challenge == null && !reset && !register)
                    OutlinedButton.icon(
                      onPressed: busy
                          ? null
                          : () => Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (_) => LinkChildPage(
                                  api: widget.api,
                                  onLinked: widget.onSignedIn,
                                ),
                              ),
                            ),
                      icon: const Icon(Icons.qr_code_scanner),
                      label: const AppText('Quét QR để kết nối với phụ huynh'),
                    ),
                  TextButton(
                    onPressed: () => changeLanguage(
                      Localizations.localeOf(c).languageCode == 'vi'
                          ? 'en'
                          : 'vi',
                    ),
                    child: const AppText('English / Tiếng Việt'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
