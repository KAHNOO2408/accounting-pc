import 'package:flutter/material.dart';

class AppColors {
  static const income = Color(0xFF15803D);
  static const expense = Color(0xFFC2410C);
  static const transfer = Color(0xFF2563EB);
  static const debt = Color(0xFF7C3AED);
  static const loan = Color(0xFFB45309);
  static const discount = Color(0xFF0891B2);
  static const sidebar = Color(0xFF0E1A24);
  static const sidebarHover = Color(0xFF172836);
}

/// Mixes [tint] over [base] with the given strength.
Color tintOf(Color base, Color tint, double a) => Color.alphaBlend(tint.withValues(alpha: a), base);

/// Brand colours derived from the accent, used by the ribbon, headers and backgrounds.
class Brand {
  final Color accent;
  final bool dark;
  const Brand(this.accent, this.dark);

  static Brand of(BuildContext context) {
    final th = Theme.of(context);
    return Brand(th.colorScheme.primary, th.brightness == Brightness.dark);
  }

  /// Second hue of the gradients (shifted toward teal/cyan).
  Color get partner {
    final h = HSLColor.fromColor(accent);
    return h.withHue((h.hue + 40) % 360).withLightness((h.lightness * 0.95).clamp(0.25, 0.6)).toColor();
  }

  Color get deep => Color.lerp(accent, Colors.black, dark ? 0.62 : 0.45)!;

  LinearGradient get chrome => LinearGradient(
        begin: AlignmentDirectional.centerStart,
        end: AlignmentDirectional.centerEnd,
        colors: [deep, Color.lerp(accent, Colors.black, dark ? 0.45 : 0.18)!, Color.lerp(partner, Colors.black, dark ? 0.5 : 0.25)!],
      );

  LinearGradient get ribbon => LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: dark
            ? [const Color(0xFF1B2230), const Color(0xFF141A24)]
            : [tintOf(Colors.white, accent, 0.17), tintOf(Colors.white, partner, 0.13)],
      );

  LinearGradient get header => LinearGradient(
        begin: AlignmentDirectional.centerStart,
        end: AlignmentDirectional.centerEnd,
        colors: [accent, partner],
      );

  Color get page => dark ? const Color(0xFF0E131B) : tintOf(const Color(0xFFF2F4F8), accent, 0.05);
}

ThemeData buildTheme({required Brightness brightness, required Color accent}) {
  final dark = brightness == Brightness.dark;
  final scheme = ColorScheme.fromSeed(seedColor: accent, brightness: brightness).copyWith(
    primary: accent,
    surface: dark ? const Color(0xFF161C26) : Colors.white,
    surfaceContainerLowest: dark ? const Color(0xFF0E131B) : tintOf(const Color(0xFFF2F4F8), accent, 0.05),
    surfaceContainerLow: dark ? tintOf(const Color(0xFF1B2230), accent, 0.10) : tintOf(const Color(0xFFF7F8FB), accent, 0.07),
    outlineVariant: dark ? tintOf(const Color(0xFF2A3442), accent, 0.10) : tintOf(const Color(0xFFE3E7EE), accent, 0.10),
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
      elevation: dark ? 0 : 1.5,
      shadowColor: accent.withValues(alpha: 0.18),
      surfaceTintColor: Colors.transparent,
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
      fillColor: dark ? const Color(0xFF1C2430) : tintOf(const Color(0xFFF9FAFC), accent, 0.03),
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
