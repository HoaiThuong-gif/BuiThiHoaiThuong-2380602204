import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

final appearance = Appearance();

class Appearance extends ChangeNotifier {
  static const colors = [
    Color(0xFFF4F8FA),
    Color(0xFFEAF5F1),
    Color(0xFFEEF2FB),
    Color(0xFFFFF4E5),
  ];
  static const colorNames = ['Mặc định', 'Xanh dịu', 'Xanh lam', 'Kem'];
  static const scales = [0.9, 1.0, 1.15];
  String? _account;
  double scale = 1;
  int background = 0;

  Future<void> selectAccount(String? id) async {
    _account = id;
    scale = 1;
    background = 0;
    notifyListeners();
    if (id == null) return;
    final prefs = await SharedPreferences.getInstance();
    if (_account != id) return;
    final savedScale = prefs.getDouble('appearance.$id.scale');
    scale = scales.contains(savedScale) ? savedScale! : 1;
    final savedColor = prefs.getInt('appearance.$id.background') ?? 0;
    background = savedColor >= 0 && savedColor < colors.length ? savedColor : 0;
    notifyListeners();
  }

  Future<void> update({double? textScale, int? color}) async {
    final id = _account;
    if (id == null) return;
    if (textScale != null && scales.contains(textScale)) scale = textScale;
    if (color != null && color >= 0 && color < colors.length) {
      background = color;
    }
    final savedScale = scale;
    final savedColor = background;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble('appearance.$id.scale', savedScale);
    await prefs.setInt('appearance.$id.background', savedColor);
  }
}
