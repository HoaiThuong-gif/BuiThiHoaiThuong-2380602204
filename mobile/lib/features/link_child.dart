import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../core/api.dart';
import '../core/widgets.dart';
import 'device_tools.dart';

class LinkChildPage extends StatefulWidget {
  final Api api;
  final VoidCallback onLinked;
  const LinkChildPage({super.key, required this.api, required this.onLinked});
  @override
  State<LinkChildPage> createState() => _LinkChildPageState();
}

class _LinkChildPageState extends State<LinkChildPage> {
  Json? pending;
  String? error;
  bool busy = false;
  Timer? timer;
  @override
  void initState() {
    super.initState();
    restore();
  }

  Future<void> restore() async {
    final value = await widget.api.storage.read(key: 'pendingEnrollment');
    if (value != null) {
      try {
        final data = Map<String, dynamic>.from(jsonDecode(value) as Map);
        if (DateTime.parse(data['expiresAt'] as String)
            .isAfter(DateTime.now())) {
          if (mounted) setState(() => pending = data);
          timer = Timer.periodic(const Duration(seconds: 4), (_) => poll());
          await poll();
        }
      } catch (_) {
        await widget.api.storage.delete(key: 'pendingEnrollment');
      }
    }
  }

  Future<void> scan() async {
    final token = await Navigator.push<String>(
      context,
      MaterialPageRoute(builder: (_) => const ScanPage()),
    );
    if (token == null || !mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final info = await deviceChannel.invokeMapMethod<String, dynamic>(
        'deviceInfo',
      );
      final installation = await deviceChannel.invokeMethod<String>(
        'installationId',
      );
      final result = await widget.api.post('/api/enrollment/start', {
        'token': token,
        'deviceName': info?['name'],
        'deviceModel': info?['model'],
        'androidVersion': info?['version'],
        'installationId': installation,
      });
      await widget.api.storage.write(
        key: 'pendingEnrollment',
        value: jsonEncode(result),
      );
      if (mounted) {
        setState(() => pending = Map<String, dynamic>.from(result as Map));
        timer?.cancel();
        timer = Timer.periodic(const Duration(seconds: 4), (_) => poll());
      }
    } catch (e) {
      if (mounted) setState(() => error = Api.message(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  bool checking = false;
  Future<void> poll() async {
    if (checking || pending == null) return;
    checking = true;
    try {
      final body = {'id': pending!['id'], 'secret': pending!['secret']};
      final response = await widget.api.post('/api/enrollment/status', body);
      if (response['status'] == 'Approved') {
        final result = await widget.api.post('/api/enrollment/session', body);
        await widget.api.save(
          Map<String, dynamic>.from(result['session'] as Map),
        );
        await deviceChannel.invokeMethod('link', {
          'deviceId': result['device']['id'],
        });
        await widget.api.storage.delete(key: 'pendingEnrollment');
        timer?.cancel();
        if (mounted) {
          widget.onLinked();
          Navigator.pop(context);
        }
      } else if (response['status'] == 'Rejected' ||
          response['status'] == 'Expired') {
        timer?.cancel();
        await widget.api.storage.delete(key: 'pendingEnrollment');
        if (mounted) {
          setState(() {
            pending = null;
            error = response['status'] == 'Rejected'
                ? 'Bố mẹ chưa đồng ý kết nối. Hãy trao đổi với bố mẹ nhé.'
                : 'Mã đã hết hạn. Hãy nhờ bố mẹ tạo mã mới.';
          });
        }
      } else if (mounted && error != null) {
        setState(() => error = null);
      }
    } catch (e) {
      if (mounted) setState(() => error = Api.message(e));
    } finally {
      checking = false;
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(title: const AppText('Kết nối với bố mẹ')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Icon(Icons.family_restroom, size: 64),
        const SizedBox(height: 20),
        if (pending == null) ...[
          const AppText(
            'Nhờ bố mẹ mở hồ sơ của con và chọn Kết nối điện thoại. Con chỉ cần quét mã trên điện thoại bố mẹ, không cần email hay mật khẩu riêng.',
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: busy ? null : scan,
            icon: const Icon(Icons.qr_code_scanner),
            label: AppText(busy ? 'Đang kết nối…' : 'Quét mã của bố mẹ'),
          ),
        ] else ...[
          AppText(
            'Hồ sơ: ${pending!['child']['fullName']}',
            style: Theme.of(c).textTheme.headlineSmall,
          ),
          const SizedBox(height: 16),
          const AppText(
            'Đối chiếu mã dưới đây với điện thoại bố mẹ. Chỉ nhờ bố mẹ xác nhận khi hai mã giống nhau.',
          ),
          Text(
            '${pending!['verificationCode']}',
            textAlign: TextAlign.center,
            style: Theme.of(c).textTheme.displayMedium,
          ),
          const SizedBox(height: 20),
          const AppText('Đang chờ bố mẹ xác nhận trên điện thoại của mình.'),
          AppText('Mã dùng được đến ${moment(pending!['expiresAt'])}.'),
        ],
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 20),
            child: AppText(
              error!,
              style: TextStyle(color: Theme.of(c).colorScheme.error),
            ),
          ),
      ],
    ),
  );
}

class ParentLinkPage extends StatefulWidget {
  final Api api;
  final String childId;
  const ParentLinkPage({super.key, required this.api, required this.childId});
  @override
  State<ParentLinkPage> createState() => _ParentLinkPageState();
}

class _ParentLinkPageState extends State<ParentLinkPage> {
  Json? invitation;
  List<dynamic> pending = [];
  String? error;
  Timer? timer;
  bool checking = false;
  @override
  void initState() {
    super.initState();
    create();
  }

  Future<void> create() async {
    try {
      final value = await widget.api.post(
        '/api/children/${widget.childId}/pairing',
        {},
      );
      if (mounted) {
        setState(() => invitation = Map<String, dynamic>.from(value as Map));
        timer = Timer.periodic(const Duration(seconds: 4), (_) => poll());
        await poll();
      }
    } catch (e) {
      if (mounted) setState(() => error = Api.message(e));
    }
  }

  Future<void> poll() async {
    if (checking) return;
    checking = true;
    try {
      final values = await widget.api.get(
        '/api/children/${widget.childId}/pairing/pending',
      ) as List;
      if (mounted) setState(() => pending = values);
    } catch (e) {
      if (mounted) setState(() => error = Api.message(e));
    } finally {
      checking = false;
    }
  }

  Future<void> decide(Json request, bool approve) async {
    if (approve &&
        !await confirm(
          context,
          'Kết nối điện thoại này?',
          'Chỉ đồng ý nếu mã ${request['verificationCode']} trùng mã trên điện thoại của con.',
        )) {
      return;
    }
    try {
      await widget.api.post('/api/enrollment/${request['id']}/decision', {
        'approve': approve,
      });
      if (!mounted) return;
      if (approve) {
        toast(context, 'Đã xác nhận. Điện thoại của con sẽ tự kết nối.');
        Navigator.pop(context);
      } else {
        await poll();
      }
    } catch (e) {
      if (mounted) setState(() => error = Api.message(e));
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(title: const AppText('Kết nối điện thoại của con')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const AppText(
          'Trên điện thoại của con, mở NhomBar và chọn Quét QR để kết nối với phụ huynh. Trẻ không cần email riêng.',
        ),
        if (invitation != null) ...[
          Center(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 24),
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: const Color(0xFFE2E8F0)),
              ),
              child: QrImageView(
                data: '${invitation!['token']}',
                size: (MediaQuery.sizeOf(c).width - 96)
                    .clamp(120, 240)
                    .toDouble(),
                backgroundColor: Colors.white,
                eyeStyle: const QrEyeStyle(
                  eyeShape: QrEyeShape.square,
                  color: Colors.black,
                ),
                dataModuleStyle: const QrDataModuleStyle(
                  dataModuleShape: QrDataModuleShape.square,
                  color: Colors.black,
                ),
              ),
            ),
          ),
          AppText(
            'Mã dùng được đến ${moment(invitation!['expiresAt'])}. Mã chỉ dùng một lần.',
          ),
        ],
        for (final p in pending)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  AppText(
                    '${p['deviceName']}',
                    style: Theme.of(c).textTheme.titleMedium,
                  ),
                  AppText('Mã đối chiếu: ${p['verificationCode']}'),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 12,
                    children: [
                      FilledButton(
                        onPressed: () =>
                            decide(Map<String, dynamic>.from(p as Map), true),
                        child: const AppText('Đồng ý kết nối'),
                      ),
                      TextButton(
                        onPressed: () =>
                            decide(Map<String, dynamic>.from(p as Map), false),
                        child: const AppText('Từ chối'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        if (pending.isEmpty && invitation != null)
          const AppText('Đang chờ điện thoại của con quét mã…'),
        if (error != null)
          AppText(
            error!,
            style: TextStyle(color: Theme.of(c).colorScheme.error),
          ),
      ],
    ),
  );
}
