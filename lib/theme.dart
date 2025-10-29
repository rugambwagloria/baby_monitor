import 'package:flutter/material.dart';

enum ThemeType { beige, purple, pink, blue }

class ThemeConfig {
  const ThemeConfig({
    required this.type,
    required this.label,
    required this.primary,
    required this.secondary,
    required this.background,
    required this.onBackground,
    required this.surface,
  });

  final ThemeType type;
  final String label;
  final Color primary;
  final Color secondary;
  final Color background;
  final Color onBackground;
  final Color surface;
}

const Map<ThemeType, ThemeConfig> _themeConfigs = {
  ThemeType.beige: ThemeConfig(
    type: ThemeType.beige,
    label: 'Beige',
    primary: Color(0xFFF5E6CC),
    secondary: Color(0xFF8C6E54),
    background: Color(0xFFFBF8F3),
    onBackground: Color(0xFF2F2415),
    surface: Colors.white,
  ),
  ThemeType.purple: ThemeConfig(
    type: ThemeType.purple,
    label: 'Purple',
    primary: Color(0xFFD6C9F0),
    secondary: Color(0xFF8066B0),
    background: Color(0xFFF6F3FA),
    onBackground: Color(0xFF2F254B),
    surface: Colors.white,
  ),
  ThemeType.pink: ThemeConfig(
    type: ThemeType.pink,
    label: 'Pink',
    primary: Color(0xFFFFE0E9),
    secondary: Color(0xFFD6336C),
    background: Color(0xFFFFF6F9),
    onBackground: Color(0xFF4B0F27),
    surface: Colors.white,
  ),
  ThemeType.blue: ThemeConfig(
    type: ThemeType.blue,
    label: 'Blue',
    primary: Color(0xFFCCE5FF),
    secondary: Color(0xFF2A75C8),
    background: Color(0xFFF5FAFF),
    onBackground: Color(0xFF0E2A3F),
    surface: Colors.white,
  ),
};

class AppTheme {
  static ThemeData themeData(ThemeType type) {
    final config = _themeConfigs[type]!;
    final neutral = config.onBackground.withValues(alpha: 0.7);

    final base = ThemeData(
      useMaterial3: true,
      colorScheme: ColorScheme.fromSeed(
        brightness: Brightness.light,
        primary: config.secondary,
        seedColor: config.secondary,
        surface: config.surface,
      ),
      scaffoldBackgroundColor: config.background,
      cardTheme: CardThemeData(
        color: config.surface,
        margin: EdgeInsets.zero,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
      ),
      textTheme: Typography.blackMountainView.apply(
        bodyColor: config.onBackground,
        displayColor: config.onBackground,
      ),
    );

    return base.copyWith(
      appBarTheme: AppBarTheme(
        backgroundColor: config.background,
        foregroundColor: config.onBackground,
        elevation: 0,
      ),
      chipTheme: base.chipTheme.copyWith(
        selectedColor: config.secondary,
        disabledColor: config.primary.withValues(alpha: 0.5),
        labelStyle: TextStyle(
          color: config.onBackground,
          fontWeight: FontWeight.w600,
        ),
      ),
      navigationBarTheme: base.navigationBarTheme.copyWith(
        indicatorColor: config.secondary.withValues(alpha: 0.2),
        backgroundColor: config.background,
        labelTextStyle: WidgetStatePropertyAll(
          TextStyle(
            fontWeight: FontWeight.w600,
            color: config.onBackground,
          ),
        ),
        iconTheme: WidgetStatePropertyAll(
          IconThemeData(color: neutral),
        ),
      ),
      floatingActionButtonTheme: base.floatingActionButtonTheme.copyWith(
        backgroundColor: config.secondary,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: const StadiumBorder(),
      ),
    );
  }

  static ThemeConfig configFor(ThemeType type) => _themeConfigs[type]!;
}

extension ThemeTypeLabel on ThemeType {
  String get label => _themeConfigs[this]!.label;
}
