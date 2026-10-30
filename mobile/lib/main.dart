import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/api.dart';
import 'core/appearance.dart';
import 'core/strings.dart';
import 'core/push.dart';
import 'features/auth.dart';
import 'features/home.dart';
import 'features/child_time_gate.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const NhomBarApp());
}

class NhomBarApp extends StatefulWidget {
  const NhomBarApp({super.key});
  @override
  State<NhomBarApp> createState() => _NhomBarAppState();
}

class _NhomBarAppState extends State<NhomBarApp> with WidgetsBindingObserver {
  final api = Api();
  final navigatorKey = GlobalKey<NavigatorState>();
  late final push = FamilyPush(api);
  bool loading = true, signedIn = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    SharedPreferences.getInstance().then(
      (prefs) => changeLanguage(prefs.getString('language') ?? 'vi'),
    );
    api.onSessionEnded = () {
      unawaited(push.stop());
      if (mounted) {
        setState(() {
          signedIn = false;
        });
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          navigatorKey.currentState?.popUntil((route) => route.isFirst);
        }
      });
    };
    api.restore().then((v) {
      if (mounted) {
        setState(() {
          signedIn = v;
          loading = false;
        });
        if (v) unawaited(push.start());
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && signedIn) {
      unawaited(push.register());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(push.stop());
    super.dispose();
  }

  ThemeData theme(Brightness b) => ThemeData(
    useMaterial3: true,
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF087F8C),
      brightness: b,
    ),
    scaffoldBackgroundColor: b == Brightness.light
        ? Appearance.colors[appearance.background]
        : Color.lerp(
            const Color(0xFF12191B),
            Appearance.colors[appearance.background],
            0.08,
          ),
    inputDecorationTheme: const InputDecorationTheme(
      border: OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(14)),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 22),
      ),
    ),
    cardTheme: const CardThemeData(
      elevation: 0,
      margin: EdgeInsets.only(bottom: 16),
    ),
  );
  @override
  Widget build(BuildContext c) => AnimatedBuilder(
    animation: appearance,
    builder: (context, _) => ValueListenableBuilder<Locale>(
      valueListenable: appLocale,
      builder: (context, locale, _) => MaterialApp(
        navigatorKey: navigatorKey,
        title: 'NhomBar',
        debugShowCheckedModeBanner: false,
        locale: locale,
        supportedLocales: const [Locale('vi'), Locale('en')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        theme: theme(Brightness.light),
        darkTheme: theme(Brightness.dark),
        builder: (context, child) {
          final media = MediaQuery.of(context);
          return MediaQuery(
            data: media.copyWith(
              textScaler: TextScaler.linear(
                media.textScaler.scale(1) * appearance.scale,
              ),
            ),
            child: child!,
          );
        },
        home: !api.configured
            ? const Scaffold(
                body: SafeArea(
                  child: Center(
                    child: Padding(
                      padding: EdgeInsets.all(28),
                      child: AppText(
                        'Ứng dụng chưa sẵn sàng kết nối. Vui lòng liên hệ người cung cấp ứng dụng để được hỗ trợ.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
              )
            : loading
            ? const Scaffold(body: Center(child: CircularProgressIndicator()))
            : signedIn
            ? ChildTimeGate(
                api: api,
                child: HomePage(
                  api: api,
                  onLogout: () {
                    unawaited(push.stop());
                    setState(() => signedIn = false);
                  },
                ),
              )
            : AuthPage(
                api: api,
                onSignedIn: () {
                  setState(() => signedIn = true);
                  unawaited(push.start());
                },
              ),
      ),
    ),
  );
}
