import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:nhombar/core/api.dart';
import 'package:nhombar/features/auth.dart';
import 'package:nhombar/core/widgets.dart';
import 'package:nhombar/core/appearance.dart';
import 'package:nhombar/core/biometric_login.dart';
import 'package:local_auth/local_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nhombar/features/profile.dart';

void main() {
  test(
    'Appearance survives restart and stays isolated between accounts',
    () async {
      SharedPreferences.setMockInitialValues({});
      final firstRun = Appearance();
      await firstRun.selectAccount('server/parent-a');
      await firstRun.update(textScale: 1.15, color: 2);
      await firstRun.selectAccount('server/parent-b');
      expect(firstRun.scale, 1);
      expect(firstRun.background, 0);
      await firstRun.update(textScale: 0.9, color: 3);
      await firstRun.selectAccount(null);
      expect(firstRun.scale, 1);
      expect(firstRun.background, 0);
      final nextRun = Appearance();
      await nextRun.selectAccount('server/parent-a');
      expect(nextRun.scale, 1.15);
      expect(nextRun.background, 2);
      await nextRun.selectAccount('server/parent-b');
      expect(nextRun.scale, 0.9);
      expect(nextRun.background, 3);
      await nextRun.selectAccount('another-server/parent-a');
      expect(nextRun.scale, 1);
      expect(nextRun.background, 0);
      firstRun.dispose();
      nextRun.dispose();
    },
  );
  test('Android strength categories do not imply a face sensor', () {
    final biometrics = BiometricLogin();
    expect(
      biometrics.describe([BiometricType.strong, BiometricType.weak]),
      'Sinh trắc học do Android cung cấp',
    );
    expect(biometrics.describe([BiometricType.fingerprint]), 'Vân tay');
    expect(biometrics.describe([BiometricType.face]), 'Khuôn mặt');
  });
  for (final size in [const Size(320, 640), const Size(800, 1100)]) {
    testWidgets('Profile remains scrollable with large text at $size', (
      tester,
    ) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('vi'),
          supportedLocales: const [Locale('vi'), Locale('en')],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: const TextScaler.linear(1.5)),
            child: child!,
          ),
          home: ProfilePage(api: ProfilePreviewApi()),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Hồ sơ cá nhân'), findsOneWidget);
      final pageScroll = find.byType(Scrollable).first;
      await tester.scrollUntilVisible(
        find.text('Lưu'),
        250,
        scrollable: pageScroll,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(
        find.text('Khôi phục giao diện mặc định'),
        250,
        scrollable: pageScroll,
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets(
    'DataView refresh and timer accept async loaders without setState Future errors',
    (tester) async {
      var calls = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DataView(
              load: () async => ++calls,
              builder: (data, reload) => Column(
                children: [
                  Text('Result $data'),
                  TextButton(onPressed: reload, child: const Text('Refresh')),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Result 1'), findsOneWidget);
      await tester.tap(find.text('Refresh'));
      await tester.pumpAndSettle();
      expect(find.text('Result 2'), findsOneWidget);
      await tester.pump(const Duration(seconds: 30));
      await tester.pumpAndSettle();
      expect(find.text('Result 3'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('Login explains missing information without a network request', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale("vi"),
        supportedLocales: const [Locale("vi"), Locale("en")],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: AuthPage(api: Api(), onSignedIn: () {}),
      ),
    );
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Đăng nhập'));
    await tester.tap(find.widgetWithText(FilledButton, 'Đăng nhập'));
    await tester.pump();
    expect(find.text('Vui lòng nhập đúng email.'), findsOneWidget);
    expect(find.text('Vui lòng nhập mật khẩu.'), findsOneWidget);
    expect(find.text('Hutech@123'), findsNothing);
    expect(find.text('Admin'), findsNothing);
  });
  testWidgets(
    'Registration is for parents and explains password requirements',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale("vi"),
          supportedLocales: const [Locale("vi"), Locale("en")],
          localizationsDelegates: GlobalMaterialLocalizations.delegates,
          home: AuthPage(api: Api(), onSignedIn: () {}),
        ),
      );
      await tester.ensureVisible(find.text('Chưa có tài khoản? Đăng ký'));
      await tester.tap(find.text('Chưa có tài khoản? Đăng ký'));
      await tester.pump();
      expect(find.text('Tạo tài khoản phụ huynh'), findsOneWidget);
      expect(find.text('Họ và tên'), findsOneWidget);
      expect(find.textContaining('Ít nhất 10 ký tự'), findsOneWidget);
      expect(find.text('Admin'), findsNothing);
    },
  );
  testWidgets('English sign-in labels and validation are readable', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        supportedLocales: const [Locale('vi'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        home: AuthPage(api: Api(), onSignedIn: () {}),
      ),
    );
    expect(find.text('Password'), findsOneWidget);
    await tester.ensureVisible(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.tap(find.widgetWithText(FilledButton, 'Sign in'));
    await tester.pump();
    expect(find.text('Enter a valid email address.'), findsOneWidget);
    expect(find.text('Enter your password.'), findsOneWidget);
  });
}

class ProfilePreviewApi extends Api {
  ProfilePreviewApi() {
    user = {
      'id': 'preview-parent',
      'role': 'Parent',
      'fullName': 'Phụ huynh kiểm thử',
      'email': 'parent@example.com',
      'phoneNumber': '+84901234567',
    };
  }
  @override
  Future<dynamic> get(String path) async => user!;
  @override
  Future<void> cacheProfile(Json profile) async {
    user = profile;
  }
}
