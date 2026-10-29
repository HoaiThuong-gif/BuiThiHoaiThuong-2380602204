import 'dart:async';

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../core/api.dart';
import '../core/usage_window.dart';
import '../core/widgets.dart';
import 'device_tools.dart';
import 'link_child.dart';
import 'child_profile.dart';

class ChildDetail extends StatefulWidget {
  final Api api;
  final Json child;
  final int initialTab;
  final bool embedded;
  const ChildDetail({
    super.key,
    required this.api,
    required this.child,
    this.initialTab = 0,
    this.embedded = false,
  });
  @override
  State<ChildDetail> createState() => _ChildDetailState();
}

class _ChildDetailState extends State<ChildDetail> {
  int revision = 0;
  Json? latestProfile;
  final locationMap = MapController();
  bool mapReady = false, followLocation = true;
  LatLng? lastMapPoint;
  bool mapTilesFailed = false;
  int mapTileRevision = 0;
  static const mapTileUrl = String.fromEnvironment(
    'MAP_TILE_URL',
    defaultValue: 'https://tile.openstreetmap.de/{z}/{x}/{y}.png',
  );
  static const mapAttribution = String.fromEnvironment(
    'MAP_ATTRIBUTION',
    defaultValue: 'OpenStreetMap contributors · Tiles: FOSSGIS e.V.',
  );
  @override
  void dispose() {
    locationMap.dispose();
    super.dispose();
  }

  Api get api => widget.api;
  String get id => widget.child['id'] as String;
  bool get parent => api.user?['role'] == 'Parent';
  Future<dynamic> load() async {
    final values = await Future.wait([
      api.get('/api/children/$id/devices'),
      api.get('/api/children/$id/rule'),
      api.get('/api/children/$id/usage'),
      api.get('/api/children/$id/extensions'),
      api.get('/api/children/$id/locations'),
      api.get('/api/children/$id/safe-places'),
      api.get('/api/children/$id'),
    ]);
    if (mounted) {
      setState(
        () => latestProfile = Map<String, dynamic>.from(values[6] as Map),
      );
    }
    return values;
  }

  Future<void> run(Future<void> Function() fn) async {
    try {
      await fn();
      if (mounted) setState(() => revision++);
    } catch (e) {
      if (mounted) toast(context, Api.message(e));
    }
  }

  @override
  Widget build(BuildContext c) => widget.embedded
      ? DataView(
          key: ValueKey(revision),
          load: load,
          builder: (data, reload) {
            final d = data as List;
            return overview(
              d[0] as List,
              d[1] as Map?,
              d[2] as Map,
              d[3] as List,
              reload,
            );
          },
        )
      : DefaultTabController(
          length: 3,
          initialIndex: widget.initialTab,
          child: Scaffold(
            appBar: AppBar(
              title: AppText('${(latestProfile ?? widget.child)['fullName']}'),
              actions: [
                if (parent)
                  IconButton(
                    tooltip: 'Chỉnh sửa thông tin của con',
                    icon: const Icon(Icons.edit_outlined),
                    onPressed: editProfile,
                  ),
              ],
              bottom: TabBar(
                tabs: [
                  Tab(text: tr(c, 'Hôm nay')),
                  Tab(text: tr(c, 'Cài đặt')),
                  Tab(text: tr(c, 'Vị trí')),
                ],
              ),
            ),
            body: DataView(
              key: ValueKey(revision),
              load: load,
              builder: (data, reload) {
                final d = data as List;
                final devices = d[0] as List;
                final rule = d[1] as Map?;
                final usage = d[2] as Map;
                final requests = d[3] as List;
                return TabBarView(
                  children: [
                    overview(devices, rule, usage, requests, reload),
                    settings(devices, rule, reload),
                    DataView(
                      refreshInterval: const Duration(seconds: 5),
                      load: () => Future.wait([
                        api.get('/api/children/$id/locations'),
                        api.get('/api/children/$id/safe-places'),
                      ]),
                      builder: (value, refresh) => locations(
                        value[0] as List,
                        value[1] as List,
                        refresh,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
  Widget overview(
    List devices,
    Map? rule,
    Map usage,
    List requests,
    VoidCallback reload,
  ) {
    final profile = latestProfile ?? widget.child;
    final nickname = (profile['nickname'] as String?)?.trim();
    final displayName = nickname != null && nickname.isNotEmpty
        ? nickname
        : profile['fullName'];
    final summaries = usage['summaries'] as List;
    final apps = usage['apps'] as List;
    final today = usageLocalTime(DateTime.now());
    final day =
        '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
    final seconds = summaries
        .where((s) => s['usageDate'] == day)
        .fold<int>(0, (v, s) => v + (s['totalSeconds'] as num).toInt());
    final bonus = requests
        .where((r) => r['usageDate'] == day && r['status'] == 'Approved')
        .fold<int>(0, (v, r) => v + (r['requestedMinutes'] as num).toInt());
    final limit = ((rule?['dailyLimitMinutes'] as num?)?.toInt() ?? 0) + bonus;
    final remaining = (limit - (seconds / 60).ceil()).clamp(0, 1440);
    return ListView(
      padding: const EdgeInsets.all(20),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        if (widget.embedded) ...[
          AppText(
            'Chào con, $displayName!',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          const AppText('Cùng xem hôm nay con còn bao nhiêu thời gian nhé.'),
          const SizedBox(height: 20),
        ],
        Section(
          parent ? 'Thời gian hôm nay' : 'Thời gian của con',
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppText(
                usageHeadline(
                  rule: rule,
                  localTime: today,
                  hasReport: summaries.isNotEmpty,
                  remainingMinutes: remaining,
                ),
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 12),
              LinearProgressIndicator(
                value: limit > 0 ? (seconds / 60 / limit).clamp(0.0, 1.0) : 0,
                borderRadius: BorderRadius.circular(8),
                minHeight: 8,
              ),
              const SizedBox(height: 12),
              AppText(
                'Đã dùng ${(seconds / 60).floor()} phút · Mức mỗi ngày ${rule?['dailyLimitMinutes'] ?? 0} phút',
              ),
              if (bonus > 0) AppText('Bố mẹ đã cho thêm $bonus phút hôm nay.'),
              if (outsideUsageWindow(rule, today)) ...[
                const SizedBox(height: 8),
                AppText(
                  'Giờ được dùng: ${'${rule?['startTime']}'.substring(0, 5)}–${'${rule?['endTime']}'.substring(0, 5)}. Phút còn lại không được dùng trong giờ nghỉ.',
                ),
              ],
              if (summaries.isEmpty)
                const AppText(
                  'Báo cáo sẽ xuất hiện sau khi hoàn tất quyền và cập nhật từ điện thoại của con.',
                ),
            ],
          ),
        ),
        if (!parent) ...[quickActions(), const SizedBox(height: 24)],
        if (parent)
          Card(
            child: ListTile(
              leading: const Icon(Icons.graphic_eq_rounded),
              title: const AppText('Tiếng ồn quanh con'),
              subtitle: const AppText('Xem các kết quả con đã gửi'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => NoiseReportsPage(api: api, childId: id),
                ),
              ),
            ),
          ),
        if (summaries.isNotEmpty)
          Section(
            'Thời gian trong tuần',
            SizedBox(
              height: 170,
              child: BarChart(
                BarChartData(
                  gridData: const FlGridData(show: false),
                  borderData: FlBorderData(show: false),
                  titlesData: const FlTitlesData(show: false),
                  barGroups: [
                    for (var i = 0; i < summaries.length; i++)
                      BarChartGroupData(
                        x: i,
                        barRods: [
                          BarChartRodData(
                            toY:
                                (summaries[i]['totalSeconds'] as num)
                                    .toDouble() /
                                60,
                            width: 18,
                            color: Theme.of(context).colorScheme.primary,
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),
          ),
        Section(
          'Xin thêm thời gian',
          Column(
            children: [
              if (!parent)
                FilledButton.icon(
                  onPressed: rule?['allowExtensionRequest'] == true
                      ? () => inputForm(
                          context,
                          'Xin thêm thời gian',
                          const [
                            Field(
                              'minutes',
                              'Số phút muốn xin thêm',
                              value: '15',
                              keyboard: TextInputType.number,
                            ),
                            Field('reason', 'Con muốn dùng thêm để làm gì?'),
                          ],
                          submit: 'Gửi bố mẹ',
                          onSave: (v) async {
                            await api.post('/api/children/$id/extensions', {
                              'requestedMinutes':
                                  int.tryParse('${v['minutes']}') ?? 0,
                              'reason': v['reason'],
                            });
                            reload();
                          },
                        )
                      : null,
                  icon: const Icon(Icons.more_time),
                  label: const AppText('Xin thêm thời gian'),
                ),
              if (requests.isEmpty) const AppText('Chưa có yêu cầu nào.'),
              for (final r in requests)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: AppText(
                    'Thêm ${r['requestedMinutes']} phút · ${requestStatus(r['status'])}',
                  ),
                  subtitle: AppText(
                    '${r['reason']}\n${r['parentResponse'] ?? ''}',
                  ),
                  onTap: parent && r['status'] == 'Pending'
                      ? () => decision(r, reload)
                      : null,
                  trailing: parent && r['status'] == 'Pending'
                      ? const Icon(Icons.chevron_right)
                      : null,
                ),
            ],
          ),
        ),

        Section(
          'Ứng dụng dùng nhiều trong tuần',
          Column(
            children: [
              if (apps.isEmpty)
                const AppText('Chưa có thông tin sử dụng ứng dụng.'),
              for (final app in apps.take(5))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: AppText('${app['appName']}'),
                  subtitle: AppText(switch (app['category']) {
                    'Game' => 'Trò chơi',
                    'Social' => 'Mạng xã hội',
                    'Study' => 'Học tập',
                    _ => 'Khác',
                  }),
                  onTap: parent
                      ? () async {
                          final selected = await showDialog<String>(
                            context: context,
                            builder: (c) => SimpleDialog(
                              title: const AppText('Chọn nhóm ứng dụng'),
                              children: [
                                for (final e in {
                                  'Game': 'Trò chơi',
                                  'Social': 'Mạng xã hội',
                                  'Study': 'Học tập',
                                  'Other': 'Khác',
                                }.entries)
                                  SimpleDialogOption(
                                    onPressed: () => Navigator.pop(c, e.key),
                                    child: AppText(e.value),
                                  ),
                              ],
                            ),
                          );
                          if (selected != null) {
                            run(() async {
                              await api.put('/api/children/$id/apps/category', {
                                'packageName': app['packageName'],
                                'category': selected,
                              });
                              reload();
                            });
                          }
                        }
                      : null,
                  trailing: AppText(
                    '${((app['seconds'] as num) / 60).floor()} phút',
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget quickActions() => LayoutBuilder(
    builder: (_, box) {
      final columns = box.maxWidth >= 600 ? 3 : 2;
      final width = (box.maxWidth - (columns - 1) * 12) / columns;
      final actions = <Widget>[
        FamilyActionButton(
          onTap: () => run(() async {
            await api.post('/api/children/$id/safety?emergency=false', {});
            if (mounted) toast(context, 'Đã báo với bố mẹ là con an toàn.');
          }),
          icon: Icons.verified_user_outlined,
          color: const Color(0xFF168568),
          label: 'Con đang an toàn',
        ),

        FamilyActionButton(
          onTap: () => run(() async {
            if (await confirm(
              context,
              'Con cần giúp đỡ?',
              'Bố mẹ sẽ nhận được thông báo trong ứng dụng. Nếu đang nguy hiểm, con hãy gọi ngay cho người lớn hoặc số khẩn cấp.',
            )) {
              await api.post('/api/children/$id/safety?emergency=true', {});
              if (mounted) {
                toast(context, 'Đã gửi thông báo nhờ bố mẹ giúp đỡ.');
              }
            }
          }),
          icon: Icons.sos,
          color: const Color(0xFFC23D55),
          label: 'Nhờ bố mẹ giúp đỡ',
        ),
        FamilyActionButton(
          onTap: () => contacts(),
          icon: Icons.call_outlined,
          color: const Color(0xFF3075C8),
          label: 'Liên hệ bố mẹ',
        ),
        FamilyActionButton(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => NoisePage(api: api, childId: id),
            ),
          ),
          icon: Icons.graphic_eq,
          color: const Color(0xFFAD7215),
          label: 'Đo tiếng ồn',
        ),

        FamilyActionButton(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) =>
                  ChildDetail(api: api, child: widget.child, initialTab: 1),
            ),
          ),
          icon: Icons.rule_outlined,
          color: const Color(0xFF7658B4),
          label: 'Xem quy tắc',
        ),
      ];
      return Wrap(
        spacing: 12,
        runSpacing: 12,
        children: [
          for (final action in actions) SizedBox(width: width, child: action),
        ],
      );
    },
  );
  Future<void> contacts() async {
    try {
      final d = await api.get('/api/children/$id/contacts') as List;
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (c) => SimpleDialog(
          title: const AppText('Liên hệ bố mẹ'),
          children: [
            for (final p in d)
              SimpleDialogOption(
                child: AppText(
                  '${p['fullName']}\n${p['phoneNumber'] ?? 'Chưa thêm số điện thoại'}',
                ),
                onPressed: () => run(() async {
                  if (p['phoneNumber'] != null) {
                    await deviceChannel.invokeMethod('dial', {
                      'number': p['phoneNumber'],
                    });
                  }
                }),
              ),
          ],
        ),
      );
    } catch (e) {
      if (mounted) toast(context, Api.message(e));
    }
  }

  Future<void> decision(dynamic r, VoidCallback reload) async {
    final approve = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: AppText('Con xin thêm ${r['requestedMinutes']} phút'),
        content: AppText('${r['reason']}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const AppText('Chưa đồng ý'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const AppText('Đồng ý'),
          ),
        ],
      ),
    );
    if (approve == null || !mounted) return;
    await inputForm(
      context,
      'Trả lời con',
      const [
        Field('response', 'Lời nhắn cho con', required: false),
        Field(
          'pin',
          'Mã phụ huynh gồm 6 số',
          secret: true,
          keyboard: TextInputType.number,
        ),
      ],
      onSave: (v) async {
        await api.post('/api/extensions/${r['id']}/decision', {
          'approve': approve,
          'response': v['response'],
          'pin': v['pin'],
        });
        reload();
      },
    );
  }

  Widget settings(List devices, Map? rule, VoidCallback reload) => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      if (parent)
        Section(
          'Thông tin của con',
          Row(
            children: [
              CircleAvatar(
                radius: 26,
                child: AppText(
                  '${(latestProfile ?? widget.child)['fullName']}'
                      .characters
                      .first,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppText(
                      '${(latestProfile ?? widget.child)['fullName']}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    if ((latestProfile ?? widget.child)['nickname'] != null)
                      AppText('${(latestProfile ?? widget.child)['nickname']}'),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Chỉnh sửa thông tin của con',
                onPressed: editProfile,
                icon: const Icon(Icons.edit_outlined),
              ),
            ],
          ),
        ),
      Card(
        clipBehavior: Clip.antiAlias,
        child: Container(
          padding: const EdgeInsets.all(22),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Theme.of(context).colorScheme.primaryContainer,
                Theme.of(context).colorScheme.surfaceContainerLow,
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.schedule_rounded,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: AppText(
                      'Thời gian mỗi ngày',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  Icon(
                    rule?['isEnabled'] == true
                        ? Icons.check_circle_outline
                        : Icons.pause_circle_outline,
                  ),
                ],
              ),
              const SizedBox(height: 20),
              AppText(
                rule == null
                    ? 'Chưa đặt thời gian'
                    : '${rule['dailyLimitMinutes']} phút',
                style: Theme.of(context).textTheme.headlineLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (rule != null)
                    Chip(
                      avatar: const Icon(Icons.wb_sunny_outlined, size: 18),
                      label: AppText(
                        '${('${rule['startTime']}').substring(0, 5)} – ${('${rule['endTime']}').substring(0, 5)}',
                      ),
                    ),
                  Chip(
                    label: AppText(
                      rule?['isEnabled'] == true ? 'Đang áp dụng' : 'Đang tắt',
                    ),
                  ),
                  if (rule?['allowExtensionRequest'] == true)
                    const Chip(
                      avatar: Icon(Icons.more_time, size: 18),
                      label: AppText('Có thể xin thêm'),
                    ),
                ],
              ),
              if (parent) ...[
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          RulePage(api: api, childId: id, rule: rule),
                    ),
                  ).then((_) => reload()),
                  icon: const Icon(Icons.tune_rounded),
                  label: const AppText('Điều chỉnh thời gian'),
                ),
                if (rule?['isEnabled'] == true)
                  TextButton(
                    onPressed: () => inputForm(
                      context,
                      'Tắt giới hạn',
                      const [
                        Field(
                          'pin',
                          'Mã phụ huynh',
                          secret: true,
                          keyboard: TextInputType.number,
                        ),
                      ],
                      onSave: (v) async {
                        await api.delete('/api/children/$id/rule', v);
                        reload();
                      },
                    ),
                    child: const AppText('Tạm tắt giới hạn'),
                  ),
              ],
            ],
          ),
        ),
      ),
      if (parent) ...[
        if (devices.isEmpty)
          Card(
            child: ListTile(
              leading: const Icon(Icons.qr_code_rounded),
              title: const AppText('Kết nối điện thoại của con'),
              subtitle: const AppText('Quét mã và xác nhận trên hai máy'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => pair(reload),
            ),
          ),
        for (final d in devices)
          Card(
            child: ExpansionTile(
              leading: const Icon(Icons.phone_android_rounded),
              title: AppText('${d['deviceName']}'),
              subtitle: AppText(
                d['deviceOwner'] == true
                    ? 'Đã thiết lập quản lý'
                    : 'Đang dùng chế độ thông thường',
              ),
              childrenPadding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    AppText(
                      d['deviceOwner'] == true
                          ? 'Đã thiết lập quản lý điện thoại'
                          : 'Chưa hoàn tất thiết lập khóa điện thoại',
                    ),
                    const SizedBox(height: 12),
                    FilledButton(
                      onPressed: () => unlock(d, reload),
                      child: const AppText('Cho con dùng thêm'),
                    ),
                    TextButton.icon(
                      icon: const Icon(Icons.key_outlined),
                      label: const AppText('Chuẩn bị mã mở khóa khi mất mạng'),
                      onPressed: () => inputForm(
                        context,
                        'Xác nhận tạo mã dự phòng',
                        const [
                          Field(
                            'pin',
                            'Mã phụ huynh',
                            secret: true,
                            keyboard: TextInputType.number,
                          ),
                        ],
                        onSave: (v) async {
                          final result = await api.post(
                            '/api/devices/${d['id']}/recovery',
                            {...v, 'version': d['recoveryVersion'] ?? 0},
                          );
                          if (!mounted) return;
                          await showDialog<void>(
                            context: context,
                            builder: (c) => AlertDialog(
                              title: const AppText(
                                'Giữ mã này riêng cho bố mẹ',
                              ),
                              content: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  SelectableText(
                                    '${result['code']}',
                                    style: Theme.of(c).textTheme.titleLarge,
                                  ),
                                  const SizedBox(height: 16),
                                  const AppText(
                                    'Mỗi mã dùng một lần để mở điện thoại trong 15 phút khi mất mạng. Hãy lưu mã ở nơi riêng tư và chờ điện thoại của con cập nhật trước khi cần dùng. Tạo mã mới sẽ thay thế mã cũ.',
                                  ),
                                ],
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(c),
                                  child: const AppText('Đã lưu mã'),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                    ),
                    if (d['deviceOwner'] == true)
                      TextButton(
                        onPressed: () => inputForm(
                          context,
                          'Kết thúc quản lý điện thoại',
                          const [
                            Field(
                              'pin',
                              'Mã phụ huynh',
                              secret: true,
                              keyboard: TextInputType.number,
                            ),
                          ],
                          onSave: (v) async {
                            final policy = await api.get(
                              '/api/devices/${d['id']}/policy',
                            );
                            if (!mounted) return;
                            if (await confirm(
                              context,
                              'Kết thúc quản lý?',
                              'Điện thoại sẽ không còn bị khóa theo thời gian đã đặt. Hãy giữ điện thoại của con kết nối mạng để hoàn tất.',
                            )) {
                              await api.post(
                                '/api/devices/${d['id']}/end-management',
                                {
                                  ...v,
                                  'version': policy['state']['policyVersion'],
                                },
                              );
                              reload();
                            }
                          },
                        ),
                        child: const AppText('Kết thúc quản lý điện thoại'),
                      ),
                    TextButton(
                      onPressed: () => inputForm(
                        context,
                        'Ngắt kết nối điện thoại',
                        const [
                          Field(
                            'pin',
                            'Mã phụ huynh',
                            secret: true,
                            keyboard: TextInputType.number,
                          ),
                        ],
                        onSave: (v) async {
                          if (await confirm(
                            context,
                            'Ngắt kết nối?',
                            'Điện thoại sẽ ngừng gửi thông tin về gia đình.',
                          )) {
                            await api.delete('/api/devices/${d['id']}', v);
                            reload();
                          }
                        },
                      ),
                      child: const AppText('Ngắt kết nối'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        Section(
          'Thay đổi khác',
          Wrap(
            spacing: 12,
            children: [
              TextButton.icon(
                onPressed: () => inputForm(
                  context,
                  'Xóa hồ sơ con',
                  const [
                    Field(
                      'pin',
                      'Mã phụ huynh',
                      secret: true,
                      keyboard: TextInputType.number,
                    ),
                  ],
                  onSave: (v) async {
                    if (await confirm(
                      context,
                      'Xóa hồ sơ của con?',
                      'Chỉ xóa được hồ sơ chưa có lịch sử sử dụng.',
                    )) {
                      await api.delete('/api/children/$id', v);
                      if (mounted) Navigator.pop(context);
                    }
                  },
                ),
                icon: const Icon(Icons.delete_outline),
                label: const AppText('Xóa hồ sơ'),
              ),
            ],
          ),
        ),
      ] else
        const Section(
          'Cùng bố mẹ giữ thói quen tốt',
          AppText(
            'Con sẽ nghe lời nhắc trước khi hết giờ. Nếu cần dùng thêm, hãy gửi yêu cầu và chờ bố mẹ đồng ý. Mất mạng không làm tăng thời gian được dùng.',
          ),
        ),
    ],
  );
  Future<void> editProfile() async {
    final result = await Navigator.push<Json>(
      context,
      MaterialPageRoute(
        builder: (_) =>
            ChildProfilePage(api: api, child: latestProfile ?? widget.child),
      ),
    );
    if (result != null && mounted) {
      setState(() {
        latestProfile = result;
        revision++;
      });
    }
  }

  Future<void> pair(VoidCallback reload) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ParentLinkPage(api: api, childId: id),
      ),
    );
    if (mounted) reload();
  }

  Future<void> unlock(dynamic d, VoidCallback reload) async {
    try {
      final policy = await api.get('/api/devices/${d['id']}/policy');
      if (!mounted) return;
      await inputForm(
        context,
        'Cho con dùng thêm',
        const [
          Field(
            'minutes',
            'Số phút cho phép',
            value: '15',
            keyboard: TextInputType.number,
          ),
          Field(
            'pin',
            'Mã phụ huynh gồm 6 số',
            secret: true,
            keyboard: TextInputType.number,
          ),
        ],
        onSave: (v) async {
          await api.post('/api/devices/${d['id']}/unlock', {
            'minutes': int.tryParse('${v['minutes']}') ?? 0,
            'pin': v['pin'],
            'version': policy['state']['policyVersion'],
          });
          reload();
        },
      );
    } catch (e) {
      if (mounted) toast(context, Api.message(e));
    }
  }

  Widget locations(List history, List places, VoidCallback reload) {
    final latest = history.isEmpty ? null : history.first;
    final recorded = DateTime.tryParse('${latest?['recordedAt']}');
    final fresh =
        recorded != null &&
        DateTime.now().difference(recorded).inSeconds.abs() < 45;
    final point = latest == null
        ? null
        : LatLng(
            (latest['latitude'] as num).toDouble(),
            (latest['longitude'] as num).toDouble(),
          );
    if (point != null && point != lastMapPoint) {
      lastMapPoint = point;
      if (followLocation && mapReady) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted || !followLocation || !mapReady) return;
          try {
            locationMap.move(point, locationMap.camera.zoom);
          } catch (_) {
            mapReady = false;
          }
        });
      }
    }
    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        if (latest == null)
          const Empty(
            'Chưa có vị trí',
            'Bật tự động cập nhật vị trí trong mục Điện thoại trên máy con và cho phép chia sẻ khi mở ứng dụng khác.',
          )
        else ...[
          Section(
            'Vị trí của con',
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(
                      fresh ? Icons.location_on_rounded : Icons.history_rounded,
                      color: fresh ? Colors.teal : Colors.orange,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: AppText(
                        fresh
                            ? 'Vừa nhận vị trí mới'
                            : 'Vị trí đã lưu · ${moment(latest['recordedAt'])}',
                      ),
                    ),
                  ],
                ),
                if (!fresh)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: AppText(
                      'Chưa có vị trí mới. Điểm trên bản đồ không xác nhận con vẫn đang ở đó.',
                    ),
                  ),
                const SizedBox(height: 12),
                if (mapTilesFailed)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Material(
                      color: Theme.of(context).colorScheme.errorContainer,
                      borderRadius: BorderRadius.circular(12),
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Row(
                          children: [
                            const Icon(Icons.map_outlined),
                            const SizedBox(width: 10),
                            const Expanded(
                              child: AppText(
                                'Chưa tải đủ nền bản đồ. Vị trí của con vẫn được cập nhật.',
                              ),
                            ),
                            TextButton(
                              onPressed: () => setState(() {
                                mapTilesFailed = false;
                                mapTileRevision++;
                              }),
                              child: const AppText('Tải lại'),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                SizedBox(
                  height: 360,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: FlutterMap(
                      mapController: locationMap,
                      options: MapOptions(
                        onMapReady: () {
                          mapReady = true;
                          if (followLocation && point != null) {
                            locationMap.move(point, 16);
                          }
                        },
                        onPositionChanged: (_, gesture) {
                          if (gesture && followLocation && mounted) {
                            setState(() => followLocation = false);
                          }
                        },
                        initialCenter: LatLng(
                          (latest['latitude'] as num).toDouble(),
                          (latest['longitude'] as num).toDouble(),
                        ),
                        initialZoom: 15,
                        onLongPress: parent
                            ? (_, p) => editPlace(null, reload, p)
                            : null,
                      ),
                      children: [
                        TileLayer(
                          key: ValueKey(mapTileRevision),
                          urlTemplate: mapTileUrl,
                          userAgentPackageName: 'vn.nhombar.nhombar',
                          errorTileCallback: (_, _, _) {
                            if (!mounted || mapTilesFailed) {
                              return;
                            }
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              if (mounted && !mapTilesFailed) {
                                setState(() => mapTilesFailed = true);
                              }
                            });
                          },
                        ),
                        CircleLayer(
                          circles: [
                            CircleMarker(
                              point: point!,
                              radius: (latest['accuracy'] as num)
                                  .toDouble()
                                  .clamp(5, double.infinity)
                                  .toDouble(),
                              useRadiusInMeter: true,
                              color: Colors.teal.withValues(alpha: .10),
                              borderColor: Colors.teal.withValues(alpha: .35),
                              borderStrokeWidth: 1,
                            ),
                          ],
                        ),
                        MarkerLayer(
                          markers: [
                            Marker(
                              point: LatLng(
                                (latest['latitude'] as num).toDouble(),
                                (latest['longitude'] as num).toDouble(),
                              ),
                              width: 48,
                              height: 48,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: Colors.teal,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 3,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.person_rounded,
                                  size: 30,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const RichAttributionWidget(
                          attributions: [TextSourceAttribution(mapAttribution)],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: AppText(
                        'Độ chính xác khoảng ${(latest['accuracy'] as num).round()} m',
                      ),
                    ),
                    TextButton.icon(
                      onPressed: () {
                        setState(() => followLocation = true);
                        if (mapReady) {
                          locationMap.move(point, 16);
                        }
                      },
                      icon: Icon(
                        followLocation ? Icons.gps_fixed : Icons.gps_not_fixed,
                      ),
                      label: const AppText('Theo vị trí con'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
        Section(
          'Khu vực an toàn',
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (places.isEmpty) const AppText('Chưa thêm khu vực an toàn.'),
              if (parent)
                const AppText(
                  'Nhấn giữ trên bản đồ để chọn nhà, trường học hoặc nơi quen thuộc.',
                ),
              for (final p in places)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: AppText('${p['placeName']}'),
                  subtitle: AppText('Trong vòng ${p['radiusMeters']} m'),
                  onTap: parent ? () => editPlace(p, reload, null) : null,
                  trailing: parent
                      ? IconButton(
                          tooltip: 'Xóa địa điểm',
                          icon: const Icon(Icons.delete_outline),
                          onPressed: () => run(() async {
                            if (await confirm(
                              context,
                              'Xóa khu vực an toàn?',
                              'Bạn sẽ không nhận thông báo ra vào khu vực này nữa.',
                            )) {
                              await api.delete('/api/safe-places/${p['id']}');
                              reload();
                            }
                          }),
                        )
                      : null,
                ),
            ],
          ),
        ),
        if (history.isNotEmpty)
          Section(
            'Các lần chia sẻ gần đây',
            Column(
              children: [
                for (final h in history.take(20))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: const Icon(Icons.history),
                    title: AppText(moment(h['recordedAt'])),
                    subtitle: AppText(
                      '${(h['latitude'] as num).toStringAsFixed(5)}, ${(h['longitude'] as num).toStringAsFixed(5)}',
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Future<void> editPlace(dynamic p, VoidCallback reload, LatLng? point) async {
    await inputForm(
      context,
      p == null ? 'Thêm khu vực an toàn' : 'Sửa khu vực an toàn',
      [
        Field(
          'placeName',
          'Tên địa điểm',
          value: p?['placeName'] as String? ?? '',
        ),
        Field(
          'radius',
          'Khoảng cách quanh địa điểm (m)',
          value: '${p?['radiusMeters'] ?? 200}',
          keyboard: TextInputType.number,
        ),
      ],
      onSave: (v) async {
        final body = {
          'placeName': v['placeName'],
          'latitude': point?.latitude ?? p['latitude'],
          'longitude': point?.longitude ?? p['longitude'],
          'radiusMeters': int.tryParse('${v['radius']}') ?? 0,
        };
        if (p == null) {
          await api.post('/api/children/$id/safe-places', body);
        } else {
          await api.put('/api/safe-places/${p['id']}', body);
        }
        reload();
      },
    );
  }
}

class RulePage extends StatefulWidget {
  final Api api;
  final String childId;
  final Map? rule;
  const RulePage({
    super.key,
    required this.api,
    required this.childId,
    this.rule,
  });
  @override
  State<RulePage> createState() => _RulePageState();
}

class _RulePageState extends State<RulePage> {
  late final warnings = TextEditingController(
    text: '${widget.rule?['warningMinutes'] ?? '30,15,5'}',
  );
  List<dynamic> voices = [];
  late String selectedVoice = widget.rule?['voiceName'] as String? ?? '';
  @override
  void initState() {
    super.initState();
    deviceChannel
        .invokeListMethod<dynamic>('voices')
        .then((v) {
          if (mounted) setState(() => voices = v ?? []);
        })
        .catchError((Object _) {
          /* The default Vietnamese voice remains available on the child phone. */
        });
  }

  late final minutes = TextEditingController(
    text: '${widget.rule?['dailyLimitMinutes'] ?? 120}',
  );
  final pin = TextEditingController();
  late TimeOfDay start = TimeOfDay(
    hour: int.parse('${widget.rule?['startTime'] ?? '07:00'}'.substring(0, 2)),
    minute: int.parse(
      '${widget.rule?['startTime'] ?? '07:00'}'.substring(3, 5),
    ),
  );
  late TimeOfDay end = TimeOfDay(
    hour: int.parse('${widget.rule?['endTime'] ?? '21:00'}'.substring(0, 2)),
    minute: int.parse('${widget.rule?['endTime'] ?? '21:00'}'.substring(3, 5)),
  );
  late bool allow = widget.rule?['allowExtensionRequest'] as bool? ?? true,
      strict = widget.rule?['strictMode'] as bool? ?? false;
  bool busy = false;
  String? error;
  @override
  void dispose() {
    minutes.dispose();
    pin.dispose();
    warnings.dispose();
    super.dispose();
  }

  String time(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}:00';
  final formKey = GlobalKey<FormState>();
  Set<int> get warningValues => warnings.text
      .split(',')
      .map((s) => int.tryParse(s.trim()))
      .whereType<int>()
      .toSet();
  Future<void> save() async {
    if (!(formKey.currentState?.validate() ?? false)) return;
    if (start.hour * 60 + start.minute >= end.hour * 60 + end.minute) {
      setState(
        () => error = 'Giờ bắt đầu cần sớm hơn giờ nghỉ trong cùng một ngày.',
      );
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.api.put('/api/children/${widget.childId}/rule', {
        'dailyLimitMinutes': int.parse(minutes.text),
        'startTime': time(start),
        'endTime': time(end),
        'strictMode': strict,
        'allowExtensionRequest': allow,
        'isEnabled': true,
        'version': widget.rule?['version'] ?? 0,
        'pin': pin.text.trim(),
        'warningMinutes': warnings.text,
        'voiceName': selectedVoice.isEmpty ? null : selectedVoice,
      });
      if (mounted) {
        toast(context, 'Đã lưu thời gian sử dụng.');
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) setState(() => error = Api.message(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget clockTile(
    String label,
    TimeOfDay value,
    IconData icon,
    ValueChanged<TimeOfDay> change,
  ) => Material(
    color: Theme.of(context).colorScheme.surfaceContainerLow,
    borderRadius: BorderRadius.circular(18),
    child: InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: busy
          ? null
          : () async {
              final result = await showTimePicker(
                context: context,
                initialTime: value,
              );
              if (result != null && mounted) setState(() => change(result));
            },
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 12),
            AppText(label),
            const SizedBox(height: 6),
            AppText(
              value.format(context),
              style: Theme.of(context).textTheme.titleLarge,
            ),
          ],
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext c) => PopScope(
    canPop: !busy,
    child: Scaffold(
      appBar: AppBar(title: const AppText('Thời gian sử dụng')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 10, 20, 16),
          child: FilledButton.icon(
            onPressed: busy ? null : save,
            icon: busy
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.check_rounded),
            label: AppText(busy ? 'Đang lưu…' : 'Lưu thay đổi'),
          ),
        ),
      ),
      body: Form(
        key: formKey,
        child: ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 680),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(bottom: 20),
                      child: AppText(
                        'Một nhịp sinh hoạt vừa đủ cho học tập, vui chơi và nghỉ ngơi.',
                      ),
                    ),
                    Section(
                      'Thời gian mỗi ngày',
                      Column(
                        children: [
                          Row(
                            children: [
                              IconButton.filledTonal(
                                tooltip: 'Giảm 15 phút',
                                onPressed: busy
                                    ? null
                                    : () => setState(
                                        () => minutes.text =
                                            ((int.tryParse(minutes.text) ??
                                                        120) -
                                                    15)
                                                .clamp(1, 1440)
                                                .toString(),
                                      ),
                                icon: const Icon(Icons.remove_rounded),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: TextFormField(
                                  controller: minutes,
                                  enabled: !busy,
                                  textAlign: TextAlign.center,
                                  keyboardType: TextInputType.number,
                                  style: Theme.of(c).textTheme.displaySmall
                                      ?.copyWith(fontWeight: FontWeight.w800),
                                  decoration: InputDecoration(
                                    labelText: tr(c, 'Số phút mỗi ngày'),
                                    suffixText: tr(c, 'phút'),
                                  ),
                                  onChanged: (_) => setState(() {}),
                                  validator: (value) {
                                    final n = int.tryParse(value ?? '');
                                    return n == null || n < 1 || n > 1440
                                        ? tr(c, 'Chọn từ 1 đến 1440 phút.')
                                        : null;
                                  },
                                ),
                              ),
                              const SizedBox(width: 12),
                              IconButton.filledTonal(
                                tooltip: 'Tăng 15 phút',
                                onPressed: busy
                                    ? null
                                    : () => setState(
                                        () => minutes.text =
                                            ((int.tryParse(minutes.text) ??
                                                        120) +
                                                    15)
                                                .clamp(1, 1440)
                                                .toString(),
                                      ),
                                icon: const Icon(Icons.add_rounded),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final n in [30, 60, 90, 120, 180])
                                ChoiceChip(
                                  label: AppText('$n phút'),
                                  selected: int.tryParse(minutes.text) == n,
                                  onSelected: busy
                                      ? null
                                      : (_) =>
                                            setState(() => minutes.text = '$n'),
                                ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Section(
                      'Khung giờ được dùng',
                      Row(
                        children: [
                          Expanded(
                            child: clockTile(
                              'Bắt đầu',
                              start,
                              Icons.wb_sunny_outlined,
                              (v) => start = v,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: clockTile(
                              'Giờ nghỉ',
                              end,
                              Icons.bedtime_outlined,
                              (v) => end = v,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Section(
                      'Lời nhắc trước khi hết giờ',
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const AppText(
                            'Chọn lúc con cần được nhắc để chuẩn bị nghỉ.',
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final n in ({
                                30,
                                15,
                                5,
                                1,
                                ...warningValues,
                              }.toList()..sort((a, b) => b.compareTo(a))))
                                FilterChip(
                                  label: AppText('$n phút'),
                                  selected: warningValues.contains(n),
                                  onSelected: busy
                                      ? null
                                      : (selected) => setState(() {
                                          final chosen = warningValues;
                                          if (selected) {
                                            chosen.add(n);
                                          } else {
                                            chosen.remove(n);
                                          }
                                          warnings.text =
                                              (chosen.toList()..sort(
                                                    (a, b) => b.compareTo(a),
                                                  ))
                                                  .join(',');
                                        }),
                                ),
                            ],
                          ),
                          if (warningValues.isEmpty)
                            const Padding(
                              padding: EdgeInsets.only(top: 12),
                              child: AppText('Chỉ nhắc khi đã hết giờ.'),
                            ),
                          ExpansionTile(
                            tilePadding: EdgeInsets.zero,
                            title: const AppText('Giọng đọc và mốc khác'),
                            children: [
                              TextFormField(
                                controller: warnings,
                                enabled: !busy,
                                decoration: InputDecoration(
                                  labelText: tr(c, 'Các mốc nhắc (phút)'),
                                  helperText: tr(
                                    c,
                                    'Ví dụ: 30, 15, 5. Để trống nếu chỉ nhắc khi hết giờ.',
                                  ),
                                ),
                                onChanged: (_) => setState(() {}),
                                validator: (v) {
                                  final list = (v ?? '')
                                      .split(',')
                                      .where((s) => s.trim().isNotEmpty)
                                      .toList();
                                  return list.length > 10 ||
                                          list.any(
                                            (s) =>
                                                (int.tryParse(s.trim()) ?? 0) <
                                                    1 ||
                                                (int.tryParse(s.trim()) ??
                                                        121) >
                                                    120,
                                          )
                                      ? tr(
                                          c,
                                          'Chọn tối đa 10 mốc, mỗi mốc từ 1 đến 120 phút.',
                                        )
                                      : null;
                                },
                              ),
                              const SizedBox(height: 16),
                              DropdownButtonFormField<String>(
                                initialValue:
                                    voices.any(
                                      (v) => v['name'] == selectedVoice,
                                    )
                                    ? selectedVoice
                                    : '',
                                isExpanded: true,
                                decoration: InputDecoration(
                                  labelText: tr(c, 'Giọng nhắc nhở'),
                                ),
                                items: [
                                  const DropdownMenuItem(
                                    value: '',
                                    child: AppText('Giọng tiếng Việt mặc định'),
                                  ),
                                  for (var i = 0; i < voices.length; i++)
                                    DropdownMenuItem(
                                      value: voices[i]['name'] as String,
                                      child: AppText(
                                        'Giọng ${i + 1}${voices[i]['network'] == true ? ' · cần mạng' : ''}',
                                      ),
                                    ),
                                ],
                                onChanged: busy
                                    ? null
                                    : (v) => setState(
                                        () => selectedVoice = v ?? '',
                                      ),
                              ),
                              Align(
                                alignment: Alignment.centerLeft,
                                child: TextButton.icon(
                                  onPressed: voices.isEmpty
                                      ? null
                                      : () => deviceChannel.invokeMethod(
                                          'previewVoice',
                                          {'voice': selectedVoice},
                                        ),
                                  icon: const Icon(Icons.volume_up_outlined),
                                  label: const AppText('Nghe thử trên máy này'),
                                ),
                              ),
                              const Padding(
                                padding: EdgeInsets.only(bottom: 12),
                                child: AppText(
                                  'Máy con sẽ dùng giọng tiếng Việt có sẵn nếu chưa có giọng đã chọn.',
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Card(
                      child: Column(
                        children: [
                          SwitchListTile.adaptive(
                            secondary: const Icon(Icons.more_time_rounded),
                            title: const AppText('Cho con xin thêm thời gian'),
                            subtitle: const AppText(
                              'Bố mẹ duyệt thì thời gian mới được tăng.',
                            ),
                            value: allow,
                            onChanged: busy
                                ? null
                                : (v) => setState(() => allow = v),
                          ),
                          const Divider(height: 1, indent: 16, endIndent: 16),
                          SwitchListTile.adaptive(
                            secondary: const Icon(Icons.lock_clock_outlined),
                            title: const AppText('Khóa khi hết giờ'),
                            subtitle: const AppText(
                              'Chỉ khóa được trên máy đã được Android cấp quyền quản lý toàn bộ. Bật lựa chọn này không tự cấp quyền.',
                            ),
                            value: strict,
                            onChanged: busy
                                ? null
                                : (v) => setState(() => strict = v),
                          ),
                        ],
                      ),
                    ),
                    Section(
                      'Xác nhận của bố mẹ',
                      TextFormField(
                        controller: pin,
                        enabled: !busy,
                        obscureText: true,
                        keyboardType: TextInputType.number,
                        maxLength: 6,
                        decoration: InputDecoration(
                          labelText: tr(c, 'Mã phụ huynh gồm 6 số'),
                          prefixIcon: const Icon(Icons.shield_outlined),
                          counterText: '',
                        ),
                        validator: (v) =>
                            RegExp(r'^\d{6}$').hasMatch(v?.trim() ?? '')
                            ? null
                            : tr(c, 'Nhập đủ mã gồm 6 số.'),
                      ),
                    ),
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: AppText(
                          error!,
                          style: TextStyle(
                            color: Theme.of(c).colorScheme.error,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
