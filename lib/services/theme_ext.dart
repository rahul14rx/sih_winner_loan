import 'package:flutter/material.dart';

extension AppColors on BuildContext {
  bool get isDark => Theme.of(this).brightness == Brightness.dark;

  Color get appBg => Theme.of(this).scaffoldBackgroundColor;
  Color get appCard => Theme.of(this).cardColor;
  Color get appBorder => isDark ? Colors.grey.shade800 : const Color(0xFFF1F5F9);
  Color get chipBg => isDark ? const Color(0xFF1F2937) : const Color(0xFFE5E7EB);
  Color get chipText => isDark ? const Color(0xFFCBD5E1) : const Color(0xFF374151);
}
