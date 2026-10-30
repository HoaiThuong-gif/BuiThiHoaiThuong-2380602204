import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/parent_contact.dart';
import '../core/usage_window.dart';
import '../core/widgets.dart';

/// Giới hạn giao diện khi mở NhomBar; không khóa hệ điều hành Android.
class ChildTimeGate extends StatefulWidget {
  final Api api;
  final Widget child;
  const ChildTimeGate({super.key, required this.api, required this.child});

  @override
  State<ChildTimeGate> createState() => _ChildTimeGateState();
}

class _ChildTimeGateState extends State<ChildTimeGate>
    with WidgetsBindingObserver {
  Timer? timer;
  Json? policy;
  String? childId, deviceId;
  List contacts = [];
  bool openingContacts = false;
  int localSeconds = 0;
  int activeSeconds = 0;
  bool readingUsage = false;
  String? localDay;
  bool ready = false, busy = false, owner = false;
  String? problem;
  DateTime? serverAnchor;
  final elapsed = Stopwatch();

  bool get isChild => widget.api.user?['role'] == 'Child';
  String get cacheKey => 'childTimeGate:${widget.api.user?['id']}';
  DateTime get now => serverAnchor == null
      ? DateTime.now().toUtc()
      : serverAnchor!.add(elapsed.elapsed);

  @override
  void initState() {
    super.initState();
    if (!isChild) return;
    WidgetsBinding.instance.addObserver(this);
    unawaited(start());
    timer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        if (busy) {
          unawaited(readLocalUsage());
        } else {
          unawaited(refresh());
        }
      }
    });
  }

  Future<void> start() async {
    try {
      final saved = await widget.api.storage.read(key: cacheKey);
      if (saved != null) {
        final cache = jsonDecode(saved) as Map;
        policy = Map<String, dynamic>.from(cache['policy'] as Map);
        childId = cache['childId'] as String?;
        deviceId = cache['deviceId'] as String?;
        contacts = cache['contacts'] as List? ?? [];
      }
    } catch (_) {
      // Cấu hình chưa có hoặc không đọc được thì lấy lại từ máy chủ.
    }
    await refresh();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (mounted) setState(() => ready = false);
      unawaited(refresh());
    }
  }

  Future<void> refresh() async {
    if (busy || !mounted) return;
    busy = true;
    try {
      final status = await deviceChannel.invokeMapMethod<String, dynamic>(
        'status',
      );
      owner = status?['deviceOwner'] == true;
      if (owner) {
        // Thiết bị được quản lý tiếp tục dùng cơ chế Android hiện có.
        ready = true;
        return;
      }
      await readLocalUsage();
      if (policy != null && mounted) setState(() => ready = true);
      try {
        if (childId == null || deviceId == null) {
          final children = await widget.api.get('/api/children') as List;
          if (children.isEmpty) {
            ready = true;
            return;
          }
          childId = children.first['id'] as String;
          final devices =
              await widget.api.get('/api/children/$childId/devices') as List;
          final linked = devices.where((d) => d['linked'] == true).toList();
          deviceId = status?['deviceId'] as String?;
          deviceId ??= linked.isEmpty ? null : linked.first['id'] as String;
        }
        if (deviceId == null) {
          ready = true;
          return;
        }
        final response =
            await widget.api.get('/api/devices/$deviceId/policy') as Map;
        // Chỉ giữ dữ liệu cần cho giao diện; không sao chép mã khôi phục/PIN.
        policy = {
          'rule': response['rule'],
          'unlockAt': response['state']?['unlockAt'],
          'usedSeconds': response['usedSeconds'],
          'extraMinutes': response['extraMinutes'],
          'usageDate': response['usageDate'],
        };
        serverAnchor = DateTime.parse(response['serverTime'] as String).toUtc();
        elapsed
          ..reset()
          ..start();
        problem = null;
        try {
          if (contacts.isEmpty) {
            contacts =
                await widget.api.get('/api/children/$childId/contacts') as List;
          }
        } catch (_) {
          // Giữ danh bạ đã nhận để vẫn có thể liên hệ khi mất mạng.
        }
        await widget.api.storage.write(
          key: cacheKey,
          value: jsonEncode({
            'childId': childId,
            'deviceId': deviceId,
            'policy': policy,
            'contacts': contacts,
          }),
        );
      } catch (_) {
        problem =
            'Chưa kết nối được với bố mẹ. Con có thể bấm liên hệ bên dưới.';
      }
      ready = true;
    } catch (_) {
      problem = 'Chưa đọc được thời gian sử dụng. Hãy nhờ bố mẹ kiểm tra quyền xem thời gian sử dụng.';
      ready = true;
    } finally {
      busy = false;
      if (mounted) setState(() {});
    }
  }

  Future<void> readLocalUsage() async {
    if (readingUsage || !mounted) return;
    readingUsage = true;
    try {
      final snapshot = await deviceChannel.invokeMapMethod<String, dynamic>(
        'usageSnapshot',
      );
      final measuredDay = snapshot?['date'] as String?;
      if (localDay != measuredDay) {
        localSeconds = 0;
        activeSeconds = 0;
      }
      localDay = measuredDay;
      if (snapshot?['allowed'] == true) {
        localSeconds = math.max(
          localSeconds,
          (snapshot?['usedSeconds'] as num? ?? 0).toInt(),
        );
        activeSeconds = (snapshot?['activeSeconds'] as num? ?? 0).toInt();
      }
      if (mounted) setState(() {});
    } catch (_) {
      // Không hạ số thời gian đã dùng khi Android tạm chưa trả được số liệu.
    } finally {
      readingUsage = false;
    }
  }

  String dayOf(DateTime date) =>
      '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';

  int get usedSeconds {
    final day = dayOf(usageLocalTime(now));
    final server = policy?['usageDate'] == day
        ? (policy?['usedSeconds'] as num? ?? 0).toInt()
        : 0;
    return math.max(server, localDay == day ? localSeconds : 0) +
        (localDay == day ? activeSeconds : 0);
  }

  bool get exhausted {
    final rule = policy?['rule'] as Map?;
    final bonus = policy?['usageDate'] == dayOf(usageLocalTime(now))
        ? (policy?['extraMinutes'] as num? ?? 0).toInt()
        : 0;
    final minutes = (rule?['dailyLimitMinutes'] as num? ?? 0).toInt() + bonus;
    return usedSeconds >= minutes * 60;
  }

  bool get blocked {
    final rule = policy?['rule'] as Map?;
    if (rule?['isEnabled'] != true || rule?['strictMode'] != true) return false;
    final unlock = DateTime.tryParse('${policy?['unlockAt']}');
    if (unlock != null && now.isBefore(unlock)) return false;
    return exhausted || outsideUsageWindow(rule, usageLocalTime(now));
  }

  String get nextUse {
    final local = usageLocalTime(now);
    final start = '${policy?['rule']?['startTime'] ?? '07:00:00'}'.split(':');
    final hour = int.tryParse(start[0]) ?? 7;
    final minute = start.length > 1 ? int.tryParse(start[1]) ?? 0 : 0;
    var next = DateTime.utc(local.year, local.month, local.day, hour, minute);
    if (exhausted || !next.isAfter(local)) {
      next = next.add(const Duration(days: 1));
    }
    return '${next.hour.toString().padLeft(2, '0')}:${next.minute.toString().padLeft(2, '0')} ngày ${next.day}/${next.month}/${next.year}';
  }

  Future<void> callParent() async {
    if (openingContacts) return;
    openingContacts = true;
    try {
      try {
        if (childId != null) {
          contacts =
              await widget.api.get('/api/children/$childId/contacts') as List;
        }
      } catch (_) {
        // Mất mạng thì dùng số liên hệ đã lưu cùng quy tắc thời gian.
      }
      if (!mounted) return;
      await openParentDialer(context, contacts);
    } finally {
      openingContacts = false;
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!isChild || owner) return widget.child;
    if (!ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (policy == null && problem == null || policy != null && !blocked) {
      return widget.child;
    }
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.lock_rounded,
                  size: 88,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: 24),
                AppText(
                  policy == null
                      ? 'Đang kiểm tra thời gian sử dụng'
                      : 'Đã hết thời gian sử dụng!',
                  style: Theme.of(context).textTheme.headlineMedium,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                const AppText(
                  'Con hãy nghỉ ngơi nhé. Hẹn gặp con vào thời gian sử dụng tiếp theo!',
                  textAlign: TextAlign.center,
                ),
                if (policy != null) ...[
                  const SizedBox(height: 20),
                  AppText(
                    'Được sử dụng lại lúc $nextUse',
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 12),
                  const AppText(
                    'Đang chờ bố mẹ cho phép dùng thêm. Màn hình sẽ tự cập nhật.',
                    textAlign: TextAlign.center,
                  ),
                ],
                if (problem != null) ...[
                  const SizedBox(height: 16),
                  AppText(problem!, textAlign: TextAlign.center),
                ],
                const SizedBox(height: 28),
                FilledButton.icon(
                  onPressed: callParent,
                  icon: const Icon(Icons.phone_outlined),
                  label: const AppText('Liên hệ bố mẹ'),
                ),
                TextButton(
                  onPressed: refresh,
                  child: const AppText('Cập nhật lại'),
                ),
                const SizedBox(height: 12),
                const AppText(
                  'Đây là màn hình nghỉ trong NhomBar.',
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
