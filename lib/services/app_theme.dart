import 'package:flutter/material.dart';

class AppTheme {
  static final ValueNotifier<ThemeMode> mode = ValueNotifier(ThemeMode.light);

  static bool get isDark => mode.value == ThemeMode.dark;
  static void toggle(bool on) => mode.value = on ? ThemeMode.dark : ThemeMode.light;
}
