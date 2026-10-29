import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:nhombar/core/api.dart';
import 'package:nhombar/features/auth.dart';
import 'package:nhombar/core/widgets.dart';

void main() {
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
