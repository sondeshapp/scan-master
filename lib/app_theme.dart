import 'package:flutter/material.dart';

class AppTheme {
  AppTheme._();

  static const primary = Color(0xFF2563EB);
  static const bgGray = Color(0xFFF2F2F7);
  static const textDark = Color(0xFF1C1C1E);
  static const textGray = Color(0xFF8E8E93);
  static const separator = Color(0xFFE5E5EA);
  static const cardBg = Color(0xFFFFFFFF);

  static const folderBlue = Color(0xFF2563EB);
  static const folderOrange = Color(0xFFF97316);
  static const folderGreen = Color(0xFF22C55E);
  static const folderPurple = Color(0xFFA855F7);

  static final light = ThemeData(
    useMaterial3: true,
    colorScheme: const ColorScheme.light(
      primary: primary,
      surface: bgGray,
    ),
    scaffoldBackgroundColor: bgGray,
    appBarTheme: const AppBarTheme(
      backgroundColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
  );
}
