import 'dart:async';

import 'strings.dart';
export 'strings.dart';

import 'package:flutter/material.dart';

import 'api.dart';

String moment(dynamic value) {
  final d = DateTime.tryParse('$value')?.toLocal();
  if (d == null) return 'Chưa có thông tin';
  return '${d.day}/${d.month}/${d.year} ${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
}

String roleName(dynamic role) => switch (role) {
  'Admin' => 'Quản trị viên',
  'Parent' => 'Phụ huynh',
  'Child' => 'Con',
  _ => 'Tài khoản',
};
String requestStatus(dynamic v) => switch (v) {
  'Approved' => 'Đã đồng ý',
  'Rejected' => 'Chưa đồng ý',
  _ => 'Chờ bố mẹ trả lời',
};
void toast(BuildContext c, String s) {
  if (c.mounted) {
    ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: AppText(s)));
  }
}

Future<bool> confirm(BuildContext c, String title, String detail) async =>
    await showDialog<bool>(
      context: c,
      builder: (c) => AlertDialog(
        title: AppText(title),
        content: AppText(detail),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const AppText('Giữ lại'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const AppText('Đồng ý'),
          ),
        ],
      ),
    ) ??
    false;

class Field {
  final String keyName, label, value;
  final bool secret, required;
  final bool date;
  final List<String>? choices;
  final TextInputType keyboard;
  const Field(
    this.keyName,
    this.label, {
    this.value = '',
    this.secret = false,
    this.required = true,
    this.date = false,
    this.choices,
    this.keyboard = TextInputType.text,
  });
}

Future<Json?> inputForm(
  BuildContext c,
  String title,
  List<Field> fields, {
  String submit = 'Lưu',
  Future<void> Function(Json)? onSave,
}) => showDialog<Json>(
  context: c,
  builder: (_) => _InputDialog(
    title: title,
    fields: fields,
    submit: submit,
    onSave: onSave,
  ),
);

class _InputDialog extends StatefulWidget {
  final String title, submit;
  final List<Field> fields;
  final Future<void> Function(Json)? onSave;
  const _InputDialog({
    required this.title,
    required this.fields,
    required this.submit,
    this.onSave,
  });
  @override
  State<_InputDialog> createState() => _InputDialogState();
}

class _InputDialogState extends State<_InputDialog> {
  final key = GlobalKey<FormState>();
  late final values = {
    for (final f in widget.fields)
      f.keyName: TextEditingController(
        text: f.date && DateTime.tryParse(f.value) != null
            ? '${DateTime.parse(f.value).day.toString().padLeft(2, '0')}/${DateTime.parse(f.value).month.toString().padLeft(2, '0')}/${DateTime.parse(f.value).year}'
            : f.value,
      ),
  };
  bool busy = false;
  String? error;
  @override
  void dispose() {
    for (final v in values.values) {
      v.dispose();
    }
    super.dispose();
  }

  Future<void> save() async {
    if (!key.currentState!.validate()) return;
    final data = <String, dynamic>{
      for (final f in widget.fields)
        f.keyName: f.date && values[f.keyName]!.text.isNotEmpty
            ? values[f.keyName]!.text.split('/').reversed.join('-')
            : values[f.keyName]!.text.trim(),
    };
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.onSave?.call(data);
      if (mounted) Navigator.pop(context, data);
    } catch (e) {
      if (mounted) setState(() => error = Api.message(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext c) => PopScope(
    canPop: !busy,
    child: AlertDialog(
      title: AppText(widget.title),
      content: SizedBox(
        width: 420,
        child: SingleChildScrollView(
          child: Form(
            key: key,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final f in widget.fields)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: f.choices != null
                        ? DropdownButtonFormField<String>(
                            initialValue: values[f.keyName]!.text,
                            decoration: InputDecoration(
                              labelText: tr(c, f.label),
                            ),
                            items: [
                              for (final choice in f.choices!)
                                DropdownMenuItem(
                                  value: choice,
                                  child: AppText(choice),
                                ),
                            ],
                            onChanged: busy
                                ? null
                                : (v) => values[f.keyName]!.text = v ?? '',
                          )
                        : TextFormField(
                            controller: values[f.keyName],
                            decoration: InputDecoration(
                              labelText: tr(c, f.label),
                            ),
                            readOnly: f.date,
                            onTap: f.date
                                ? () async {
                                    final old = values[f.keyName]!.text;
                                    final initial = old.isEmpty
                                        ? DateTime(DateTime.now().year - 10)
                                        : DateTime.parse(
                                            old.split('/').reversed.join('-'),
                                          );
                                    final chosen = await showDatePicker(
                                      context: c,
                                      initialDate: initial,
                                      firstDate: DateTime(1900),
                                      lastDate: DateTime.now(),
                                    );
                                    if (chosen != null) {
                                      values[f.keyName]!.text =
                                          '${chosen.day.toString().padLeft(2, '0')}/${chosen.month.toString().padLeft(2, '0')}/${chosen.year}';
                                    }
                                  }
                                : null,
                            obscureText: f.secret,
                            keyboardType: f.keyboard,
                            enabled: !busy,
                            validator: (s) =>
                                f.required && (s == null || s.trim().isEmpty)
                                ? Localizations.localeOf(c).languageCode == 'en'
                                      ? 'Please enter ${tr(c, f.label).toLowerCase()}.'
                                      : 'Vui lòng nhập ${f.label.toLowerCase()}.'
                                : null,
                          ),
                  ),
                if (error != null)
                  AppText(
                    error!,
                    style: TextStyle(color: Theme.of(c).colorScheme.error),
                  ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: busy ? null : () => Navigator.pop(c),
          child: const AppText('Hủy'),
        ),
        FilledButton(
          onPressed: busy ? null : save,
          child: busy
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : AppText(widget.submit),
        ),
      ],
    ),
  );
}

class DataView extends StatefulWidget {
  final Future<dynamic> Function() load;
  final Widget Function(dynamic, VoidCallback) builder;
  final Duration refreshInterval;
  const DataView({
    super.key,
    required this.load,
    required this.builder,
    this.refreshInterval = const Duration(seconds: 30),
  });
  @override
  State<DataView> createState() => _DataViewState();
}

class _DataViewState extends State<DataView> {
  late Future<dynamic> future;
  dynamic lastData;
  Timer? timer;
  bool fetching = false;
  @override
  void initState() {
    super.initState();
    future = fetch();
    timer = Timer.periodic(widget.refreshInterval, (_) {
      if (mounted &&
          TickerMode.valuesOf(context).enabled &&
          (WidgetsBinding.instance.lifecycleState == null ||
              WidgetsBinding.instance.lifecycleState ==
                  AppLifecycleState.resumed)) {
        reload();
      }
    });
  }

  Future<dynamic> fetch() async {
    fetching = true;
    try {
      final data = await widget.load();
      lastData = data;
      return data;
    } catch (error) {
      // Never retain a family's displayed data after an authoritative denial/removal.
      if (!Api.temporaryFailure(error)) lastData = null;
      rethrow;
    } finally {
      fetching = false;
    }
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  void reload() {
    if (!mounted || fetching) return;
    setState(() {
      future = fetch();
    });
  }

  @override
  Widget build(BuildContext c) => FutureBuilder<dynamic>(
    future: future,
    builder: (c, snapshot) {
      if (!snapshot.hasData && lastData == null && !snapshot.hasError) {
        return const Center(child: CircularProgressIndicator());
      }
      if (snapshot.hasError && lastData == null) {
        return Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.cloud_off_rounded, size: 42),
                const SizedBox(height: 16),
                AppText(
                  Api.message(snapshot.error!),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton.icon(
                  onPressed: reload,
                  icon: const Icon(Icons.refresh),
                  label: const AppText('Thử lại'),
                ),
              ],
            ),
          ),
        );
      }
      final content = RefreshIndicator(
        onRefresh: () async {
          reload();
          await future;
        },
        child: widget.builder(
          snapshot.hasError ? lastData : (snapshot.data ?? lastData),
          reload,
        ),
      );
      if (!snapshot.hasError) return content;
      return Column(
        children: [
          Material(
            color: Theme.of(c).colorScheme.errorContainer,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  const Icon(Icons.cloud_off_outlined, size: 20),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: AppText(
                      'Đang hiển thị thông tin đã tải. Chưa lấy được bản mới.',
                    ),
                  ),
                  TextButton(
                    onPressed: reload,
                    child: const AppText('Thử lại'),
                  ),
                ],
              ),
            ),
          ),
          Expanded(child: content),
        ],
      );
    },
  );
}

class FamilyActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  const FamilyActionButton({
    super.key,
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });
  @override
  Widget build(BuildContext context) => Material(
    color: color.withValues(
      alpha: Theme.of(context).brightness == Brightness.dark ? .22 : .09,
    ),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(20),
      side: BorderSide(color: color.withValues(alpha: .18)),
    ),
    clipBehavior: Clip.antiAlias,
    child: InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: color, size: 30),
            const SizedBox(height: 10),
            ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 40),
              child: Center(
                heightFactor: 1,
                child: AppText(
                  label,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.labelLarge
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class Empty extends StatelessWidget {
  final String title, detail;
  const Empty(this.title, this.detail, {super.key});
  @override
  Widget build(BuildContext c) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 24),
    child: Column(
      children: [
        Icon(
          Icons.family_restroom_rounded,
          size: 56,
          color: Theme.of(c).colorScheme.primary,
        ),
        const SizedBox(height: 18),
        AppText(
          title,
          style: Theme.of(c).textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        AppText(detail, textAlign: TextAlign.center),
      ],
    ),
  );
}

class Section extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? action;
  const Section(this.title, this.child, {super.key, this.action});
  @override
  Widget build(BuildContext c) => Card(
    child: Padding(
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: AppText(title, style: Theme.of(c).textTheme.titleMedium),
              ),
              ?action,
            ],
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    ),
  );
}
