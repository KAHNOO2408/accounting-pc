import 'package:flutter/material.dart';

class AppColors {
  static const income = Color(0xFF15803D);
  static const expense = Color(0xFFC2410C);
  static const transfer = Color(0xFF2563EB);
  static const debt = Color(0xFF7C3AED);
  static const sidebar = Color(0xFF0E1A24);
  static const sidebarHover = Color(0xFF172836);
}

ThemeData buildTheme({required Brightness brightness, required Color accent}) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(seedColor: accent, brightness: brightness).copyWith(
    primary: accent,
    surface: dark ? const Color(0xFF151C23) : Colors.white,
    surfaceContainerLowest: dark ? const Color(0xFF0F151B) : const Color(0xFFF3F5F7),
    surfaceContainerLow: dark ? const Color(0xFF1A222A) : const Color(0xFFF7F8FA),
    outlineVariant: dark ? const Color(0xFF2A3540) : const Color(0xFFE3E7EC),
  );

  final base = ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    brightness: brightness,
    fontFamily: 'Vazirmatn',
    scaffoldBackgroundColor: scheme.surfaceContainerLowest,
    visualDensity: VisualDensity.compact,
  );

  final radius = BorderRadius.circular(10);

  return base.copyWith(
    textTheme: base.textTheme.apply(fontFamily: 'Vazirmatn'),
    cardTheme: CardThemeData(
      color: scheme.surface,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: scheme.outlineVariant),
      ),
    ),
    dividerTheme: DividerThemeData(color: scheme.outlineVariant, space: 1, thickness: 1),
    inputDecorationTheme: InputDecorationTheme(
      isDense: true,
      filled: true,
      fillColor: dark ? const Color(0xFF1C252E) : const Color(0xFFF7F8FA),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: scheme.outlineVariant)),
      enabledBorder:
          OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: scheme.outlineVariant)),
      focusedBorder: OutlineInputBorder(borderRadius: radius, borderSide: BorderSide(color: accent, width: 1.6)),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: radius),
        textStyle: const TextStyle(fontFamily: 'Vazirmatn', fontWeight: FontWeight.w500),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: radius),
        side: BorderSide(color: scheme.outlineVariant),
        textStyle: const TextStyle(fontFamily: 'Vazirmatn'),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: TextButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: radius),
        textStyle: const TextStyle(fontFamily: 'Vazirmatn'),
      ),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: scheme.surface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    tooltipTheme: const TooltipThemeData(textStyle: TextStyle(fontFamily: 'Vazirmatn', color: Colors.white, fontSize: 12)),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
    popupMenuTheme: PopupMenuThemeData(
      color: scheme.surface,
      shape: RoundedRectangleBorder(borderRadius: radius, side: BorderSide(color: scheme.outlineVariant)),
    ),
  );
}
