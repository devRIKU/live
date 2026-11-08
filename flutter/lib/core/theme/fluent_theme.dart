import 'package:fluent_ui/fluent_ui.dart';

/// Maps Lively design tokens to FluentThemeData.
/// Source of truth: ../design-system/tokens.css (light-dark() resolved).
FluentThemeData buildFluentTheme(Brightness brightness) {
  final isDark = brightness == Brightness.dark;
  return FluentThemeData(
    brightness: brightness,
    accentColor: AccentColor.swatch({
      'darkest': const Color(0xFF003E8A),
      'darker': const Color(0xFF0050B3),
      'dark': const Color(0xFF0067C0),
      'normal': const Color(0xFF0078D4),
      'light': const Color(0xFF2B88D8),
      'lighter': const Color(0xFF71AFE5),
      'lightest': const Color(0xFFC7E0F4),
    }),
    scaffoldBackgroundColor: isDark
        ? const Color(0xFF1F1F1F)
        : const Color(0xFFF3F3F3),
    cardColor: isDark ? const Color(0xFF2D2D2D) : const Color(0xFFFFFFFF),
    navigationPaneTheme: NavigationPaneThemeData(
      backgroundColor: isDark
          ? const Color(0xFF202020)
          : const Color(0xFFF7F7F7),
    ),
    typography: const Typography.raw(
      body: TextStyle(fontFamily: 'Segoe UI', fontSize: 14),
      bodyStrong: TextStyle(fontFamily: 'Segoe UI', fontSize: 14, fontWeight: FontWeight.w600),
      title: TextStyle(fontFamily: 'Segoe UI', fontSize: 28, fontWeight: FontWeight.w600),
      subtitle: TextStyle(fontFamily: 'Segoe UI', fontSize: 20, fontWeight: FontWeight.w600),
      caption: TextStyle(fontFamily: 'Segoe UI', fontSize: 12),
    ),
  );
}