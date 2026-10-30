import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../core/api.dart';
import '../core/widgets.dart';

class ChildProfilePage extends StatefulWidget {
  final Api api;
  final Json child;
  const ChildProfilePage({super.key, required this.api, required this.child});
  @override
  State<ChildProfilePage> createState() => _ChildProfilePageState();
}

class _ChildProfilePageState extends State<ChildProfilePage> {
  final form = GlobalKey<FormState>();
  late final TextEditingController name, nickname;
  DateTime? birth;
  Uint8List? avatar;
  bool changedAvatar = false, removeAvatar = false, busy = false;
  String? error;
  @override
  void initState() {
    super.initState();
    name = TextEditingController(text: widget.child['fullName'] as String?);
    nickname = TextEditingController(text: widget.child['nickname'] as String?);
    birth = DateTime.tryParse('${widget.child['dateOfBirth']}');
    final encoded = widget.child['avatarBytes'] as String?;
    if (encoded != null) {
      try {
        avatar = base64Decode(encoded);
      } catch (_) {}
    }
  }

  @override
  void dispose() {
    name.dispose();
    nickname.dispose();
    super.dispose();
  }

  Future<void> pickPhoto() async {
    try {
      final photo = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        maxWidth: 512,
        maxHeight: 512,
        imageQuality: 75,
      );
      if (photo == null) return;
      final bytes = await photo.readAsBytes();
      if (bytes.length > 262144) {
        throw Exception('Ảnh quá lớn. Hãy chọn ảnh nhỏ hơn.');
      }
      if (mounted) {
        setState(() {
          avatar = bytes;
          changedAvatar = true;
          removeAvatar = false;
        });
      }
    } catch (e) {
      if (mounted) toast(context, Api.message(e));
    }
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await widget.api.put('/api/children/${widget.child['id']}', {
        'fullName': name.text.trim(),
        'nickname': nickname.text.trim(),
        'dateOfBirth': birth == null
            ? null
            : '${birth!.year}-${birth!.month.toString().padLeft(2, '0')}-${birth!.day.toString().padLeft(2, '0')}',
        'avatarUrl': widget.child['avatarUrl'],
        'avatarBase64': changedAvatar && avatar != null
            ? base64Encode(avatar!)
            : null,
        'removeAvatar': removeAvatar,
      });
      if (mounted) {
        toast(context, 'Đã lưu thông tin của con.');
        Navigator.pop(context, Map<String, dynamic>.from(result as Map));
      }
    } catch (e) {
      if (mounted) setState(() => error = Api.message(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(title: const AppText('Thông tin của con')),
    body: Form(
      key: form,
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Center(
            child: CircleAvatar(
              radius: 48,
              backgroundImage: avatar == null ? null : MemoryImage(avatar!),
              child: avatar == null
                  ? const Icon(Icons.child_care, size: 42)
                  : null,
            ),
          ),
          TextButton.icon(
            onPressed: busy ? null : pickPhoto,
            icon: const Icon(Icons.photo_library_outlined),
            label: const AppText('Chọn ảnh đại diện'),
          ),
          if (avatar != null)
            TextButton(
              onPressed: busy
                  ? null
                  : () => setState(() {
                      avatar = null;
                      changedAvatar = false;
                      removeAvatar = true;
                    }),
              child: const AppText('Dùng ảnh mặc định'),
            ),
          const SizedBox(height: 20),
          TextFormField(
            controller: name,
            maxLength: 200,
            decoration: InputDecoration(labelText: tr(c, 'Họ và tên')),
            validator: (v) => v == null || v.trim().isEmpty
                ? tr(c, 'Vui lòng nhập tên của con.')
                : null,
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: nickname,
            maxLength: 60,
            decoration: InputDecoration(
              labelText: tr(c, 'Biệt danh (không bắt buộc)'),
            ),
          ),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: busy
                ? null
                : () async {
                    final now = DateTime.now();
                    final selected = await showDatePicker(
                      context: c,
                      initialDate: birth ?? DateTime(now.year - 10, 1, 1),
                      firstDate: DateTime(1900),
                      lastDate: now,
                    );
                    if (selected != null && mounted) {
                      setState(() => birth = selected);
                    }
                  },
            icon: const Icon(Icons.calendar_month),
            label: AppText(
              birth == null
                  ? 'Chọn ngày sinh'
                  : '${birth!.day.toString().padLeft(2, '0')}/${birth!.month.toString().padLeft(2, '0')}/${birth!.year}',
            ),
          ),
          if (error != null)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: AppText(
                error!,
                style: TextStyle(color: Theme.of(c).colorScheme.error),
              ),
            ),
          const SizedBox(height: 24),
          FilledButton(
            onPressed: busy ? null : save,
            child: AppText(busy ? 'Đang lưu…' : 'Lưu thay đổi'),
          ),
          TextButton(
            onPressed: busy ? null : () => Navigator.pop(c),
            child: const AppText('Hủy'),
          ),
        ],
      ),
    ),
  );
}
