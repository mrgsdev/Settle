import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';

/// Настройки оформления — в settings.json рядом с данными. Файл не
/// шифруется: тема нужна ещё до ввода пароля.
abstract final class AppSettings {
  static File _file(Directory dir) =>
      File('${dir.path}${Platform.pathSeparator}settings.json');

  static Future<ThemeMode> loadTheme(Directory dir) async {
    try {
      final json = jsonDecode(await _file(dir).readAsString());
      return ThemeMode.values.byName((json as Map)['theme'] as String);
    } catch (_) {
      return ThemeMode.system;
    }
  }

  static Future<void> saveTheme(Directory dir, ThemeMode mode) async {
    try {
      await dir.create(recursive: true);
      await _file(dir).writeAsString(jsonEncode({'theme': mode.name}));
    } catch (e) {
      debugPrint('Не удалось сохранить настройки: $e');
    }
  }
}

/// Текущая тема и её смена — для меню «•••».
class ThemeScope extends InheritedWidget {
  const ThemeScope({
    super.key,
    required this.mode,
    required this.onChanged,
    required super.child,
  });

  final ThemeMode mode;
  final ValueChanged<ThemeMode> onChanged;

  static ThemeScope of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ThemeScope>()!;

  @override
  bool updateShouldNotify(ThemeScope old) => old.mode != mode;
}
