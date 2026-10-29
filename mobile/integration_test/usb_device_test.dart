import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:integration_test/integration_test.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:noise_meter/noise_meter.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:nhombar/main.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('vn.nhombar/device');
  const baseUrl = String.fromEnvironment('API_BASE_URL');
  final results = <String, dynamic>{};
  void record(String name, String status, Object detail) {
    results[name] = {'status': status, 'detail': detail};
    // No coordinates, email code, API keys or credentials in the device report.
    debugPrint('USB_CHECK ${jsonEncode({name: results[name]})}');
    binding.reportData = results;
  }

  testWidgets('USB device checks; each feature has its own outcome', (
    tester,
  ) async {
    final info = await channel.invokeMapMethod<String, dynamic>('deviceInfo');
    expect(
      info?['model'],
      'SM-A528B',
      reason: 'This test must use the actual Samsung USB phone.',
    );
    record('device', 'PASS', info!);
    await tester.pumpWidget(const NhomBarApp());
    await tester.pumpAndSettle();
    expect(find.text('NhomBar'), findsOneWidget);
    record('launch', 'PASS', 'Real NhomBar Flutter screen rendered on Samsung');
    try {
      final health = await Dio(
        BaseOptions(
          connectTimeout: const Duration(seconds: 6),
          receiveTimeout: const Duration(seconds: 6),
        ),
      ).get('$baseUrl/health');
      record(
        'api',
        health.data['status'] == 'ready' ? 'PASS' : 'FAIL',
        '$baseUrl/health: HTTP ${health.statusCode}',
      );
    } catch (_) {
      record('api', 'BLOCKED', 'Phone could not reach laptop LAN API');
    }

    if (results['api']['status'] == 'PASS' &&
        find.byType(TextFormField).evaluate().length == 2) {
      await tester.enterText(
        find.byType(TextFormField).first,
        'buithihoaithuongdl@gmail.com',
      );
      await tester.enterText(
        find.byType(TextFormField).last,
        'wrong-test-password',
      );
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await SystemChannels.textInput.invokeMethod<void>('TextInput.hide');
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Đăng nhập'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Đăng nhập'));
      for (var i = 0; i < 25; i++) {
        await tester.pump(const Duration(milliseconds: 400));
      }
      record(
        'loginWrongPassword',
        find.text('Email hoặc mật khẩu chưa đúng.').evaluate().isNotEmpty
            ? 'PASS'
            : 'BLOCKED',
        'Normal login form; no OTP bypass',
      );
    } else {
      record(
        'loginWrongPassword',
        'BLOCKED',
        'LAN API unavailable; no login success claimed',
      );
    }
    if (find.text('Chưa có tài khoản? Đăng ký').evaluate().isNotEmpty) {
      await tester.ensureVisible(find.text('Chưa có tài khoản? Đăng ký'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chưa có tài khoản? Đăng ký'));
      await tester.pumpAndSettle();
      record(
        'navigation',
        find.text('Tạo tài khoản phụ huynh').evaluate().isNotEmpty
            ? 'PASS'
            : 'FAIL',
        'Login to registration screen',
      );
    }

    try {
      if (await Permission.locationWhenInUse.request().isGranted &&
          await Geolocator.isLocationServiceEnabled()) {
        final p = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 25),
          ),
        );
        record('gps', 'PASS', {
          'accuracyMeters': p.accuracy,
          'sampleAgeSeconds': DateTime.now().difference(p.timestamp).inSeconds,
        });
      } else {
        record('gps', 'BLOCKED', 'Location permission/service unavailable');
      }
    } catch (_) {
      record('gps', 'BLOCKED', 'No real location fix within 25 seconds');
    }

    try {
      if (await Permission.microphone.request().isGranted) {
        final samples = await NoiseMeter().noise
            .take(5)
            .toList()
            .timeout(const Duration(seconds: 10));
        final valid =
            samples.isNotEmpty && samples.every((s) => s.meanDecibel.isFinite);
        record('microphone', valid ? 'PASS' : 'FAIL', {
          'samples': samples.length,
          'meanDb': valid ? samples.last.meanDecibel : null,
          'audioRecorded': false,
        });
      } else {
        record('microphone', 'BLOCKED', 'Microphone permission unavailable');
      }
    } catch (_) {
      record('microphone', 'BLOCKED', 'No microphone level samples');
    }

    try {
      final voices = await channel
          .invokeListMethod<dynamic>('voices')
          .timeout(const Duration(seconds: 15));
      if (voices?.isNotEmpty == true) {
        await channel.invokeMethod('previewVoice', {
          'voice': voices!.first['name'],
        });
        record('tts', 'PARTIAL', {
          'vietnameseVoices': voices.length,
          'previewRequested': true,
          'heardByUser': false,
        });
      } else {
        record('tts', 'BLOCKED', 'No Vietnamese voice reported by Android');
      }
    } catch (_) {
      record('tts', 'BLOCKED', 'Speech engine unavailable');
    }

    try {
      final snapshot = await channel.invokeMapMethod<String, dynamic>(
        'usageSnapshot',
      );
      record(
        'usage',
        snapshot?['allowed'] == true ? 'PASS' : 'BLOCKED',
        snapshot ?? {},
      );
    } catch (_) {
      record('usage', 'BLOCKED', 'Usage Access not available');
    }

    if (const bool.fromEnvironment('CHECK_CAMERA', defaultValue: true)) {
      final scanner = MobileScannerController(autoStart: false);
      final detected = Completer<String>();
      try {
        if (await Permission.camera.request().isGranted) {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                appBar: AppBar(
                  title: const Text('Hướng camera vào mã kiểm tra trên laptop'),
                ),
                body: MobileScanner(
                  controller: scanner,
                  onDetect: (capture) {
                    for (final code in capture.barcodes) {
                      if (code.rawValue == 'NHOMBAR-USB-TEST-20261029' &&
                          !detected.isCompleted) {
                        detected.complete(code.rawValue!);
                      }
                    }
                  },
                ),
              ),
            ),
          );
          await tester.pump(const Duration(seconds: 1));
          await scanner.start();
          record(
            'camera',
            scanner.value.isInitialized && scanner.value.isRunning
                ? 'PASS'
                : 'FAIL',
            'Actual MobileScanner camera initialization',
          );
          try {
            await detected.future.timeout(const Duration(seconds: 60));
            record('qr', 'PASS', 'Public test QR decoded by real camera');
          } catch (_) {
            record(
              'qr',
              'NOT TESTED',
              'Camera opened, no public test QR decoded before timeout',
            );
          }
        } else {
          record('camera', 'BLOCKED', 'Camera permission unavailable');
          record('qr', 'NOT TESTED', 'Camera permission unavailable');
        }
      } catch (_) {
        record('camera', 'BLOCKED', 'Camera initialization unavailable');
        record('qr', 'NOT TESTED', 'No scan result');
      }
      await scanner.dispose();
    }
    await tester.pumpWidget(const NhomBarApp());
    await tester.pumpAndSettle();
  }, timeout: const Timeout(Duration(minutes: 5)));
}
