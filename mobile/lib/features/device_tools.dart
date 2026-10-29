import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:noise_meter/noise_meter.dart';
import 'package:permission_handler/permission_handler.dart';

import '../core/api.dart';
import '../core/widgets.dart';
import 'child_access_setup.dart';

class DeviceTools extends StatefulWidget {
  final Api api;
  const DeviceTools({super.key, required this.api});
  @override
  State<DeviceTools> createState() => _DeviceToolsState();
}

class _DeviceToolsState extends State<DeviceTools> {
  int revision = 0;
  Future<dynamic> load() async {
    final children = await widget.api.get('/api/children') as List;
    final status = await deviceChannel.invokeMapMethod<String, dynamic>(
      'status',
    );
    final devices = children.isEmpty
        ? <dynamic>[]
        : await widget.api.get('/api/children/${children.first['id']}/devices')
              as List;
    return {'children': children, 'status': status, 'devices': devices};
  }

  Future<void> run(Future<void> Function() fn) async {
    try {
      await fn();
      if (mounted) setState(() => revision++);
    } catch (e) {
      if (mounted) {
        toast(
          context,
          e is TimeoutException
              ? 'Chưa lấy được vị trí. Hãy kiểm tra kết nối, thử ở nơi thoáng hơn rồi gửi lại.'
              : Api.message(e),
        );
      }
    }
  }

  Future<void> permissions(Map status, List devices) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      useSafeArea: true,
      builder: (sheet) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 4, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AppText(
              'Quyền của NhomBar',
              style: Theme.of(sheet).textTheme.titleLarge,
            ),
            const SizedBox(height: 16),
            const AppText(
              'Cho phép xem thời gian sử dụng để tính thời gian còn lại. NhomBar không đọc tin nhắn hay nội dung màn hình.',
            ),
            const SizedBox(height: 20),
            FilledButton.icon(
              icon: const Icon(Icons.settings_outlined),
              label: const AppText('Mở phần cấp quyền'),
              onPressed: () async {
                Navigator.pop(sheet);
                await deviceChannel.invokeMethod('usageSettings');
              },
            ),
            if (status['usageAccess'] == true && devices.isNotEmpty)
              TextButton(
                onPressed: () {
                  Navigator.pop(sheet);
                  run(() async {
                    await Permission.notification.request();
                    await deviceChannel.invokeMethod('startMonitoring', {
                      'deviceId': devices.first['id'],
                    });
                    if (mounted) toast(context, 'Đã bật cập nhật và lời nhắc.');
                  });
                },
                child: const AppText('Bật lại cập nhật và lời nhắc'),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> sendLocation(List devices) => run(() async {
    if (!await Geolocator.isLocationServiceEnabled()) {
      if (mounted) {
        toast(context, 'Con hãy bật vị trí trên điện thoại trước nhé.');
      }
      return;
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      if (mounted) {
        toast(
          context,
          'Chưa được cho phép chia sẻ vị trí. Con có thể bật trong cài đặt điện thoại.',
        );
      }
      return;
    }
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
        timeLimit: Duration(seconds: 25),
      ),
    );
    if (position.isMocked) {
      if (mounted) {
        toast(
          context,
          'Điện thoại đang dùng vị trí giả. Hãy tắt ứng dụng tạo vị trí giả rồi thử lại.',
        );
      }
      return;
    }
    await widget.api.post('/api/devices/${devices.first['id']}/locations', {
      'latitude': position.latitude,
      'longitude': position.longitude,
      'accuracy': position.accuracy,
      'recordedAt': position.timestamp.toUtc().toIso8601String(),
    });
    if (mounted) toast(context, 'Đã gửi vị trí mới cho bố mẹ.');
  });

  @override
  Widget build(BuildContext c) => DataView(
    key: ValueKey(revision),
    load: load,
    builder: (d, reload) {
      final status = d['status'] as Map? ?? {};
      final devices = d['devices'] as List;
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          AppText(
            'Điện thoại của con',
            style: Theme.of(c).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          const AppText(
            'Con và bố mẹ cùng biết những thông tin đang được chia sẻ.',
          ),
          const SizedBox(height: 24),
          Card(
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.link_rounded),
                  title: const AppText('Kết nối gia đình'),
                  subtitle: AppText(
                    devices.isEmpty
                        ? 'Nhờ bố mẹ kết nối lại điện thoại từ màn hình chào.'
                        : 'Đã kết nối: ${devices.first['deviceName']}',
                  ),
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.shield_outlined),
                  title: const AppText('Quyền của ứng dụng'),
                  subtitle: AppText(
                    status['usageAccess'] == true
                        ? 'Đã cho phép xem thời gian sử dụng'
                        : 'Cần hoàn tất quyền để có báo cáo',
                  ),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => permissions(status, devices),
                ),
                const Divider(height: 1, indent: 56),
                ListTile(
                  leading: const Icon(Icons.history_rounded),
                  title: const AppText('Xem lần cập nhật'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => showModalBottomSheet<void>(
                    context: c,
                    showDragHandle: true,
                    useSafeArea: true,
                    builder: (sheet) => Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          AppText(
                            'Lần cập nhật gần nhất',
                            style: Theme.of(sheet).textTheme.titleLarge,
                          ),
                          const SizedBox(height: 12),
                          AppText(moment(status['lastSync'])),
                          if (status['error'] != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: AppText('${status['error']}'),
                            ),
                          if (status['locationError'] != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 12),
                              child: AppText('${status['locationError']}'),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Section(
            'Chia sẻ với bố mẹ',
            Column(
              children: [
                SwitchListTile.adaptive(
                  contentPadding: EdgeInsets.zero,
                  title: const AppText('Tự động cập nhật vị trí'),
                  subtitle: const AppText(
                    'Cập nhật khi con di chuyển, kể cả khi mở ứng dụng khác. Điện thoại sẽ hiện thông báo khi đang chia sẻ.',
                  ),
                  value: status['shareLocation'] == true,
                  onChanged: devices.isEmpty
                      ? null
                      : (value) => run(() async {
                          if (value) {
                            await ChildAccessSetup.enableLocation(c);
                          } else {
                            await ChildAccessSetup.disableLocation();
                          }
                        }),
                ),
                TextButton.icon(
                  onPressed: devices.isEmpty
                      ? null
                      : () => sendLocation(devices),
                  icon: const Icon(Icons.my_location),
                  label: const AppText('Gửi vị trí ngay bây giờ'),
                ),
              ],
            ),
          ),
        ],
      );
    },
  );
}

class ScanPage extends StatefulWidget {
  const ScanPage({super.key});
  @override
  State<ScanPage> createState() => _ScanPageState();
}

class _ScanPageState extends State<ScanPage> {
  final scanner = MobileScannerController();
  bool finished = false;
  @override
  void dispose() {
    unawaited(scanner.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(title: const AppText('Quét mã từ điện thoại bố mẹ')),
    body: Column(
      children: [
        const Padding(
          padding: EdgeInsets.all(20),
          child: AppText(
            'Đưa mã kết nối vào khung hình. Mã chỉ dùng một lần trong 5 phút.',
          ),
        ),
        Expanded(
          child: MobileScanner(
            controller: scanner,
            onDetect: (capture) {
              for (final barcode in capture.barcodes) {
                final value = barcode.rawValue;
                if (!finished &&
                    value != null &&
                    RegExp(r'^[A-Fa-f0-9]{64}$').hasMatch(value)) {
                  finished = true;
                  Navigator.pop(c, value);
                  break;
                }
              }
            },
            errorBuilder: (c, e) => const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: AppText(
                  'Chưa mở được máy ảnh. Con hãy kiểm tra quyền máy ảnh trong cài đặt điện thoại rồi thử lại.',
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

class NoiseReportsPage extends StatelessWidget {
  final Api api;
  final String childId;
  const NoiseReportsPage({super.key, required this.api, required this.childId});
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const AppText('Tiếng ồn quanh con')),
    body: DataView(
      load: () => api.get('/api/children/$childId/noise'),
      builder: (data, reload) {
        final reports = data as List;
        return ListView(
          padding: const EdgeInsets.all(20),
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const Padding(
              padding: EdgeInsets.only(bottom: 20),
              child: AppText(
                'Các kết quả con đã gửi. Chỉ gồm mức âm thanh, không có bản ghi âm hay nội dung trò chuyện. Kết quả chỉ để tham khảo.',
              ),
            ),
            if (reports.isEmpty)
              const Empty(
                'Chưa có kết quả',
                'Khi con đo và gửi, kết quả sẽ xuất hiện tại đây và trong thông báo của bố mẹ.',
              ),
            for (final report in reports)
              Section(
                moment(report['recordedAt']),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.graphic_eq_rounded, size: 36),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              AppText(
                                '${(report['averageLevel'] as num).round()} dB',
                                style: Theme.of(context)
                                    .textTheme
                                    .headlineMedium,
                              ),
                              AppText(
                                'Cao nhất ${(report['maximumLevel'] as num).round()} dB',
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    LinearProgressIndicator(
                      value: ((report['averageLevel'] as num) / 130).clamp(
                        0.0,
                        1.0,
                      ),
                      minHeight: 8,
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    ),
  );
}

class NoisePage extends StatefulWidget {
  final Api api;
  final String childId;
  const NoisePage({super.key, required this.api, required this.childId});
  @override
  State<NoisePage> createState() => _NoisePageState();
}

class _NoisePageState extends State<NoisePage> {
  StreamSubscription<NoiseReading>? subscription;
  final values = <double>[];
  double current = 0, peak = 0;
  bool sending = false, sent = false;
  String? error;
  double get average =>
      values.isEmpty ? 0 : values.reduce((a, b) => a + b) / values.length;
  Future<void> start() async {
    if (!await Permission.microphone.request().isGranted) {
      if (mounted) {
        setState(
          () => error = 'Con hãy cho phép dùng micro để đo tiếng ồn nhé.',
        );
      }
      return;
    }
    values.clear();
    peak = 0;
    sent = false;
    try {
      subscription = NoiseMeter().noise.listen(
        (reading) {
          if (!mounted || subscription == null) return;
          if (!reading.meanDecibel.isFinite || !reading.maxDecibel.isFinite) {
            return;
          }
          setState(() {
            current = reading.meanDecibel.clamp(0, 200);
            values.add(current);
            peak = reading.maxDecibel.clamp(peak, 200);
          });
        },
        onError: (Object e) {
          stop();
          if (mounted) {
            setState(() => error = 'Chưa đo được tiếng ồn. Hãy thử lại.');
          }
        },
      );
      setState(() => error = null);
    } on PlatformException catch (e) {
      if (mounted) setState(() => error = Api.message(e));
    }
  }

  void stop() {
    unawaited(subscription?.cancel());
    subscription = null;
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    unawaited(subscription?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(title: const AppText('Đo tiếng ồn')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const AppText(
          'Kết quả chỉ để tham khảo, có thể khác giữa các điện thoại. NhomBar không ghi âm và không lưu nội dung trò chuyện.',
        ),
        const SizedBox(height: 30),
        AppText(
          '${current.toStringAsFixed(0)} dB',
          textAlign: TextAlign.center,
          style: Theme.of(c).textTheme.displayLarge,
        ),
        AppText(
          subscription != null ? 'Đang đo tiếng ồn' : 'Đã dừng đo',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 20),
        Section(
          'Kết quả đo',
          AppText(
            'Trung bình: ${average.toStringAsFixed(0)} dB\nCao nhất: ${peak.toStringAsFixed(0)} dB',
          ),
        ),
        SizedBox(
          height: 80,
          child: CustomPaint(
            painter: _NoisePainter(
              values.length > 60 ? values.sublist(values.length - 60) : values,
              Theme.of(c).colorScheme.primary,
            ),
          ),
        ),
        if (error != null)
          AppText(
            error!,
            style: TextStyle(color: Theme.of(c).colorScheme.error),
          ),
        const SizedBox(height: 24),
        FilledButton(
          onPressed: sending ? null : (subscription == null ? start : stop),
          child: AppText(subscription == null ? 'Bắt đầu đo' : 'Dừng đo'),
        ),
        const SizedBox(height: 12),
        OutlinedButton(
          onPressed: values.isEmpty || sending || sent
              ? null
              : () async {
                  stop();
                  setState(() => sending = true);
                  try {
                    await widget.api.post(
                      '/api/children/${widget.childId}/noise',
                      {
                        'averageLevel': average,
                        'maximumLevel': peak < average ? average : peak,
                        'recordedAt': DateTime.now().toUtc().toIso8601String(),
                      },
                    );
                    if (c.mounted) {
                      setState(() => sent = true);
                      toast(
                        c,
                        'Đã gửi kết quả. Bố mẹ có thể xem trong Thông báo và hồ sơ của con.',
                      );
                    }
                  } catch (e) {
                    if (mounted) setState(() => error = Api.message(e));
                  } finally {
                    if (mounted) setState(() => sending = false);
                  }
                },
          child: AppText(
            sending
                ? 'Đang gửi…'
                : sent
                ? 'Đã gửi cho bố mẹ'
                : 'Gửi kết quả cho bố mẹ',
          ),
        ),
      ],
    ),
  );
}

class _NoisePainter extends CustomPainter {
  final List<double> values;
  final Color color;
  _NoisePainter(this.values, this.color);
  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = i * size.width / (values.length - 1),
          y = size.height * (1 - values[i] / 200);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );
  }

  @override
  bool shouldRepaint(covariant _NoisePainter old) => true;
}
