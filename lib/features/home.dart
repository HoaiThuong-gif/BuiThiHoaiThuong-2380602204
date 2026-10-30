import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../core/api.dart';
import '../core/widgets.dart';
import 'child_detail.dart';
import 'device_tools.dart';
import 'profile.dart';
import 'child_access_setup.dart';

class HomePage extends StatefulWidget {
  final Api api;
  final VoidCallback onLogout;
  const HomePage({super.key, required this.api, required this.onLogout});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  int tab = 0;
  int revision = 0;
  Timer? inboxTimer;
  ChildAccessSetup? childSetup;
  List<Json> inbox = [];
  bool inboxLoaded = false, inboxFetching = false, noticesOpen = false;
  int get unread => inbox.where((n) => n['isRead'] != true).length;
  Api get api => widget.api;
  bool get parent => api.user?['role'] == 'Parent';
  bool get admin => api.user?['role'] == 'Admin';
  @override
  void initState() {
    super.initState();
    api.onNoticeOpened = openNotices;
    if (api.user?['role'] == 'Child') childSetup = ChildAccessSetup(api);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      childSetup?.attach(context);
      unawaited(refreshInbox());
      if (api.pendingNotice != null && mounted) {
        api.pendingNotice = null;
        openNotices();
      }
    });
    inboxTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      if (mounted &&
          WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        unawaited(refreshInbox());
      }
    });
  }

  Future<void> refreshInbox({bool announce = true}) async {
    if (inboxFetching || api.token == null) return;
    inboxFetching = true;
    try {
      final list = (await api.get('/api/notifications') as List)
          .map((n) => Map<String, dynamic>.from(n as Map))
          .toList();
      if (!mounted) return;
      final known = inbox.map((n) => n['id']).toSet();
      final fresh = list
          .where((n) => !known.contains(n['id']) && n['isRead'] != true)
          .toList();
      final notify =
          inboxLoaded && announce && !noticesOpen && fresh.isNotEmpty;
      setState(() {
        inbox = list;
        inboxLoaded = true;
      });
      if (notify) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: AppText('${fresh.first['title']}'),
            duration: const Duration(seconds: 6),
            action: SnackBarAction(
              label: tr(context, 'Xem'),
              onPressed: openNotices,
            ),
          ),
        );
      }
    } catch (_) {
      /* Keep the last unread count during a temporary outage. */
    } finally {
      inboxFetching = false;
    }
  }

  void openNotices() {
    if (mounted && !noticesOpen) {
      noticesOpen = true;
      Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) => Scaffold(
            appBar: AppBar(title: const AppText('Thông báo')),
            body: notifications(),
          ),
        ),
      ).whenComplete(() {
        noticesOpen = false;
        unawaited(refreshInbox(announce: false));
      });
    }
  }

  @override
  void dispose() {
    inboxTimer?.cancel();
    childSetup?.dispose();
    api.onNoticeOpened = null;
    super.dispose();
  }

  Future<void> action(Future<void> Function() fn) async {
    try {
      await fn();
      if (mounted) setState(() => revision++);
    } catch (e) {
      if (mounted) toast(context, Api.message(e));
    }
  }

  @override
  Widget build(BuildContext c) {
    final labels = admin
        ? ['Tổng quan', 'Tài khoản', 'Thông báo', 'Cá nhân']
        : parent
        ? ['Tổng quan', 'Vị trí', 'Quản lý', 'Tài khoản']
        : ['Hôm nay', 'Điện thoại', 'Thông báo', 'Tài khoản'];
    final icons = admin
        ? [
            Icons.dashboard_rounded,
            Icons.people_rounded,
            Icons.notifications_rounded,
            Icons.person_rounded,
          ]
        : parent
        ? [
            Icons.home_rounded,
            Icons.location_on_rounded,
            Icons.tune_rounded,
            Icons.person_rounded,
          ]
        : [
            Icons.home_rounded,
            Icons.phone_android_rounded,
            Icons.notifications_rounded,
            Icons.person_rounded,
          ];
    return Scaffold(
      appBar: AppBar(
        title: AppText(tab == 0 ? 'NhomBar' : labels[tab]),
        actions: [
          Badge(
            isLabelVisible: unread > 0,
            label: Text(unread > 99 ? '99+' : '$unread'),
            child: IconButton(
              tooltip: 'Thông báo',
              onPressed: openNotices,
              icon: const Icon(Icons.notifications_outlined),
            ),
          ),
        ],
      ),
      body: KeyedSubtree(
        key: ValueKey('$tab-$revision'),
        child: tab == 3
            ? account()
            : admin
            ? adminPage()
            : !parent && tab == 0
            ? DataView(
                load: () => api.get('/api/children'),
                builder: (data, _) {
                  final profiles = data as List;
                  return profiles.isEmpty
                      ? ListView(
                          children: const [
                            Empty(
                              'Chưa có hồ sơ kết nối',
                              'Nhờ bố mẹ kiểm tra lại tài khoản của con nhé.',
                            ),
                          ],
                        )
                      : ChildDetail(
                          api: api,
                          child: Map<String, dynamic>.from(
                            profiles.first as Map,
                          ),
                          embedded: true,
                        );
                },
              )
            : !parent && tab == 1
            ? DeviceTools(api: api)
            : !parent && tab == 2
            ? notifications()
            : children(),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (v) => setState(() => tab = v),
        destinations: [
          for (var i = 0; i < 4; i++)
            NavigationDestination(
              icon: Icon(icons[i]),
              label: tr(c, labels[i]),
            ),
        ],
      ),
    );
  }

  Widget children() => DataView(
    load: () => api.get('/api/dashboard'),
    builder: (data, reload) {
      final list = data as List;
      return ListView(
        padding: const EdgeInsets.all(20),
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          AppText(
            parent
                ? 'Xin chào, ${api.user?['fullName']}'
                : 'Chào con, ${api.user?['fullName']}!',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          const SizedBox(height: 8),
          AppText(
            parent
                ? 'Cùng con cân bằng học tập, vui chơi và nghỉ ngơi.'
                : 'Cùng xem hôm nay con còn bao nhiêu thời gian nhé.',
          ),
          const SizedBox(height: 24),
          if (parent && tab != 1)
            Align(
              alignment: Alignment.centerLeft,
              child: FilledButton.icon(
                onPressed: () => addChild(reload),
                icon: const Icon(Icons.person_add_alt_1),
                label: const AppText('Thêm hồ sơ con'),
              ),
            ),
          const SizedBox(height: 16),
          if (list.isEmpty)
            Empty(
              parent ? 'Chưa có hồ sơ của con' : 'Chưa có hồ sơ kết nối',
              parent
                  ? 'Thêm hồ sơ để bắt đầu đồng hành cùng con.'
                  : 'Nhờ bố mẹ kiểm tra lại tài khoản của con nhé.',
            ),
          for (final item in list)
            Card(
              child: ListTile(
                contentPadding: const EdgeInsets.all(18),
                leading: CircleAvatar(
                  backgroundImage: item['avatarBytes'] == null
                      ? null
                      : MemoryImage(
                          base64Decode(item['avatarBytes'] as String),
                        ),
                  child: item['avatarBytes'] != null
                      ? null
                      : AppText((item['fullName'] as String).characters.first),
                ),
                title: AppText(item['fullName'] as String),
                subtitle: AppText(
                  tab == 1
                      ? 'Xem vị trí con chia sẻ'
                      : tab == 2
                      ? 'Thời gian, điện thoại và yêu cầu của con'
                      : item['hasReport'] == true
                      ? 'Đã dùng ${item['usedMinutes']} phút · ${item['remainingMinutes'] == null ? 'Chưa đặt giới hạn' : 'Còn ${item['remainingMinutes']} phút'}\n${item['online'] == true ? 'Vừa kết nối' : 'Chưa kết nối gần đây'}${item['isLocked'] == true ? ' · Lần gần nhất: đã khóa' : ''}${(item['pendingRequests'] as num) > 0 ? '\n${item['pendingRequests']} yêu cầu đang chờ' : ''}'
                      : 'Chưa có báo cáo từ điện thoại của con',
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => ChildDetail(
                      api: api,
                      child: Map<String, dynamic>.from(item as Map),
                      initialTab: tab == 1 ? 2 : 0,
                    ),
                  ),
                ).then((_) => reload()),
              ),
            ),
        ],
      );
    },
  );
  Future<void> addChild(VoidCallback reload) async {
    final families = await api.get('/api/families') as List;
    if (!mounted) return;
    if (families.isEmpty) {
      toast(context, 'Bạn cần tạo gia đình trước.');
      return;
    }
    await inputForm(
      context,
      'Thêm hồ sơ con',
      const [
        Field('fullName', 'Tên của con'),
        Field('dateOfBirth', 'Ngày sinh', required: false, date: true),
      ],
      onSave: (v) async {
        await api.post('/api/families/${families.first['id']}/children', {
          'fullName': v['fullName'],
          'dateOfBirth': (v['dateOfBirth'] as String).isEmpty
              ? null
              : v['dateOfBirth'],
          'avatarUrl': null,
        });
        reload();
      },
    );
  }

  Widget notifications() => DataView(
    load: () => api.get('/api/notifications'),
    builder: (d, reload) => ListView(
      padding: const EdgeInsets.all(20),
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        if ((d as List).isEmpty)
          const Empty(
            'Chưa có thông báo',
            'Thông tin mới sẽ được hiển thị ở đây.',
          ),
        for (final n in d)
          Card(
            child: ListTile(
              leading: Icon(
                n['isRead'] == true
                    ? Icons.notifications_none
                    : Icons.notifications_active_outlined,
              ),
              title: AppText(n['title'] as String),
              subtitle: AppText('${n['content']}\n${moment(n['createdAt'])}'),
              isThreeLine: true,
              onTap: () => action(() async {
                await api.put('/api/notifications/${n['id']}/read', {});
                await refreshInbox(announce: false);
                reload();
              }),
            ),
          ),
      ],
    ),
  );
  Widget account() => ListView(
    padding: const EdgeInsets.all(20),
    children: [
      CircleAvatar(
        radius: 36,
        backgroundImage: api.user?['avatarBytes'] is String
            ? MemoryImage(base64Decode(api.user!['avatarBytes'] as String))
            : null,
        child: api.user?['avatarBytes'] == null
            ? const Icon(Icons.person, size: 36)
            : null,
      ),
      const SizedBox(height: 16),
      AppText(
        '${api.user?['fullName']}',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.headlineSmall,
      ),
      AppText(
        '${api.user?['email'] ?? ''}\n${roleName(api.user?['role'])}',
        textAlign: TextAlign.center,
      ),
      const SizedBox(height: 24),
      Card(
        child: Column(
          children: [
            ListTile(
              leading: const Icon(Icons.language),
              title: const AppText('Ngôn ngữ / Language'),
              trailing: TextButton(
                onPressed: () => changeLanguage(
                  Localizations.localeOf(context).languageCode == 'vi'
                      ? 'en'
                      : 'vi',
                ),
                child: AppText(
                  Localizations.localeOf(context).languageCode == 'vi'
                      ? 'English'
                      : 'Tiếng Việt',
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const AppText('Hồ sơ cá nhân'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () async {
                await Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => ProfilePage(api: api),
                  ),
                );
                if (mounted) setState(() => revision++);
              },
            ),
            if (parent)
              ListTile(
                leading: const Icon(Icons.pin_outlined),
                title: const AppText('Đặt hoặc đổi mã phụ huynh'),
                subtitle: const AppText(
                  'Mã gồm 6 số dùng để xác nhận thay đổi quan trọng.',
                ),
                onTap: () => inputForm(
                  context,
                  'Mã phụ huynh',
                  const [
                    Field(
                      'currentPin',
                      'Mã hiện tại (bỏ trống nếu chưa đặt)',
                      secret: true,
                      required: false,
                      keyboard: TextInputType.number,
                    ),
                    Field(
                      'pin',
                      'Mã mới gồm 6 số',
                      secret: true,
                      keyboard: TextInputType.number,
                    ),
                  ],
                  onSave: (v) async {
                    await api.put('/api/parent-pin', v);
                    if (mounted) toast(context, 'Đã lưu mã phụ huynh.');
                  },
                ),
              ),
            if (parent || admin)
              ListTile(
                leading: const Icon(Icons.password_rounded),
                title: const AppText('Đổi mật khẩu'),
                onTap: () => inputForm(
                  context,
                  'Đổi mật khẩu',
                  const [
                    Field('currentPassword', 'Mật khẩu hiện tại', secret: true),
                    Field('newPassword', 'Mật khẩu mới', secret: true),
                  ],
                  onSave: (v) async {
                    await api.post('/api/auth/change-password', v);
                    await api.clear(endMonitoring: false);
                    widget.onLogout();
                  },
                ),
              ),
            ListTile(
              leading: const Icon(Icons.history),
              title: const AppText('Lịch sử quản lý'),
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => Scaffold(
                    appBar: AppBar(title: const AppText('Lịch sử quản lý')),
                    body: DataView(
                      load: () => api.get('/api/audit'),
                      builder: (d, _) => ListView(
                        children: [
                          for (final x in d as List)
                            ListTile(
                              title: AppText('${x['action']}'),
                              subtitle: AppText(moment(x['createdAt'])),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
            ListTile(
              leading: const Icon(Icons.privacy_tip_outlined),
              title: const AppText('Thông tin được chia sẻ'),
              onTap: () => showDialog<void>(
                context: context,
                builder: (c) => AlertDialog(
                  title: const AppText('Cả nhà cùng biết'),
                  content: const AppText(
                    'Điện thoại của con chỉ chia sẻ thời gian sử dụng và vị trí khi đã được cho phép. Đo tiếng ồn không lưu lời nói hay bản ghi âm. Bố mẹ chỉ xem thông tin trong gia đình mình.\n\nKhi mất mạng, giới hạn đã đặt vẫn được giữ. Để khóa điện thoại, bố mẹ cần làm theo hướng dẫn thiết lập trên một điện thoại dành riêng cho con.',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(c),
                      child: const AppText('Đã hiểu'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(height: 20),
      if (parent || admin)
        FutureBuilder<bool>(
          future: api.biometrics.enabled(
            Api.baseUrl,
            api.user?['id'] as String?,
          ),
          builder: (_, snapshot) => snapshot.data != true
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: OutlinedButton.icon(
                    onPressed: () => action(() async {
                      final locked = await api.lock();
                      if (!locked && mounted) {
                        toast(
                          context,
                          'Chưa thể khóa ứng dụng. Hãy kiểm tra tùy chọn sinh trắc học trong Hồ sơ cá nhân.',
                        );
                      }
                    }),
                    icon: const Icon(Icons.lock_outline),
                    label: const AppText('Khóa ứng dụng'),
                  ),
                ),
        ),
      OutlinedButton.icon(
        onPressed: () => action(() async {
          if (!parent && !admin) {
            final status = await deviceChannel.invokeMapMethod<String, dynamic>(
              'status',
            );
            if (status?['locked'] == true) {
              if (mounted) {
                toast(context, 'Hãy nhờ bố mẹ mở khóa trước khi đăng xuất.');
              }
              return;
            }
          }
          await api.logout();
          widget.onLogout();
        }),
        icon: const Icon(Icons.logout),
        label: const AppText('Đăng xuất'),
      ),
    ],
  );
  Widget adminPage() {
    if (tab == 0) {
      return DataView(
        load: () => api.get('/api/admin/summary'),
        builder: (d, _) => ListView(
          padding: const EdgeInsets.all(20),
          children: [
            AppText(
              'Quản lý NhomBar',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 20),
            for (final entry in {
              'users': 'Tổng tài khoản',
              'parents': 'Phụ huynh',
              'children': 'Hồ sơ con',
              'active': 'Tài khoản đang hoạt động',
            }.entries)
              Section(
                entry.value,
                AppText(
                  '${d[entry.key]}',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
              ),
            const AppText('Thông tin vị trí của trẻ được dành cho gia đình.'),
          ],
        ),
      );
    }
    if (tab == 1) {
      return DataView(
        load: () => api.get('/api/admin/users'),
        builder: (d, reload) => ListView(
          padding: const EdgeInsets.all(20),
          children: [
            FilledButton.icon(
              onPressed: () => editUser(null, reload),
              icon: const Icon(Icons.person_add),
              label: const AppText('Thêm tài khoản'),
            ),
            const SizedBox(height: 16),
            for (final u in d as List)
              Card(
                child: ListTile(
                  title: AppText('${u['fullName']}'),
                  subtitle: AppText(
                    '${u['email']}\n${roleName(u['role'])} · ${u['active'] == true ? 'Đang hoạt động' : 'Đã ngừng'}',
                  ),
                  isThreeLine: true,
                  onTap: () =>
                      editUser(Map<String, dynamic>.from(u as Map), reload),
                  trailing: IconButton(
                    tooltip: 'Ngừng tài khoản',
                    icon: const Icon(Icons.person_off_outlined),
                    onPressed: () => action(() async {
                      if (await confirm(
                        context,
                        'Ngừng tài khoản?',
                        'Người này sẽ không thể đăng nhập cho đến khi được mở lại.',
                      )) {
                        await api.delete('/api/admin/users/${u['id']}');
                        reload();
                      }
                    }),
                  ),
                ),
              ),
          ],
        ),
      );
    }
    return DataView(
      load: () => api.get('/api/admin/notifications'),
      builder: (d, reload) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          FilledButton.icon(
            onPressed: () => editNotice(null, reload),
            icon: const Icon(Icons.add),
            label: const AppText('Gửi thông báo'),
          ),
          const SizedBox(height: 16),
          if ((d as List).isEmpty)
            const Empty(
              'Chưa có thông báo',
              'Bạn có thể gửi thông báo cho một tài khoản.',
            ),
          for (final n in d)
            Card(
              child: ListTile(
                title: AppText('${n['title']}'),
                subtitle: AppText('${n['content']}'),
                onTap: () =>
                    editNotice(Map<String, dynamic>.from(n as Map), reload),
                trailing: IconButton(
                  tooltip: 'Xóa thông báo',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: () => action(() async {
                    if (await confirm(
                      context,
                      'Xóa thông báo?',
                      'Thông báo sẽ được xóa khỏi danh sách người nhận.',
                    )) {
                      await api.delete('/api/admin/notifications/${n['id']}');
                      reload();
                    }
                  }),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> editUser(Json? u, VoidCallback reload) async {
    String role = u?['role'] as String? ?? 'Parent';
    if (u == null) {
      role =
          await showDialog<String>(
            context: context,
            builder: (c) => SimpleDialog(
              title: const AppText('Loại tài khoản'),
              children: [
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(c, 'Parent'),
                  child: const AppText('Phụ huynh'),
                ),
                SimpleDialogOption(
                  onPressed: () => Navigator.pop(c, 'Admin'),
                  child: const AppText('Quản trị viên'),
                ),
              ],
            ),
          ) ??
          '';
      if (role.isEmpty || !mounted) return;
    }
    await inputForm(
      context,
      u == null ? 'Thêm ${roleName(role).toLowerCase()}' : 'Sửa tài khoản',
      [
        Field('fullName', 'Họ và tên', value: u?['fullName'] as String? ?? ''),
        if (u == null)
          const Field('email', 'Email', keyboard: TextInputType.emailAddress),
        Field(
          'password',
          u == null
              ? 'Mật khẩu ban đầu'
              : 'Mật khẩu mới (bỏ trống để giữ nguyên)',
          secret: true,
          required: u == null,
        ),
        if (u != null)
          Field(
            'active',
            'Trạng thái tài khoản',
            value: u['active'] == true ? 'Đang hoạt động' : 'Tạm ngừng',
            choices: const ['Đang hoạt động', 'Tạm ngừng'],
          ),
      ],
      onSave: (v) async {
        final body = {
          'fullName': v['fullName'],
          'email': u?['email'] ?? v['email'],
          'role': role,
          'active': u == null || v['active'] == 'Đang hoạt động',
          'password': v['password'],
        };
        if (u == null) {
          await api.post('/api/admin/users', body);
        } else {
          await api.put('/api/admin/users/${u['id']}', body);
        }
        reload();
      },
    );
  }

  Future<void> editNotice(Json? n, VoidCallback reload) async {
    String? receiver = n?['receiverId'] as String?;
    if (n == null) {
      final users = await api.get('/api/admin/users') as List;
      if (!mounted) return;
      receiver = await showDialog<String>(
        context: context,
        builder: (c) => SimpleDialog(
          title: const AppText('Chọn người nhận'),
          children: [
            for (final u in users)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(c, u['id'] as String),
                child: AppText('${u['fullName']}\n${u['email']}'),
              ),
          ],
        ),
      );
      if (receiver == null || !mounted) return;
    }
    await inputForm(
      context,
      n == null ? 'Gửi thông báo' : 'Sửa thông báo',
      [
        Field('title', 'Tiêu đề', value: n?['title'] as String? ?? ''),
        Field('content', 'Nội dung', value: n?['content'] as String? ?? ''),
      ],
      onSave: (v) async {
        final body = {...v, 'receiverId': receiver};
        if (n == null) {
          await api.post('/api/admin/notifications', body);
        } else {
          await api.put('/api/admin/notifications/${n['id']}', body);
        }
        reload();
      },
    );
  }
}
