import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppThemeMode {
  system(label: '跟随系统', icon: Icons.brightness_auto_rounded),
  light(label: '白天模式', icon: Icons.light_mode_rounded),
  dark(label: '夜间模式', icon: Icons.dark_mode_rounded);

  final String label;
  final IconData icon;

  const AppThemeMode({required this.label, required this.icon});

  ThemeMode get materialThemeMode {
    switch (this) {
      case AppThemeMode.system:
        return ThemeMode.system;
      case AppThemeMode.light:
        return ThemeMode.light;
      case AppThemeMode.dark:
        return ThemeMode.dark;
    }
  }
}

class AppThemeController extends ChangeNotifier {
  static const _prefKey = 'app_theme_mode';

  AppThemeMode _mode = AppThemeMode.system;

  AppThemeMode get mode => _mode;
  ThemeMode get themeMode => _mode.materialThemeMode;

  bool isDark(BuildContext context) {
    if (_mode == AppThemeMode.dark) return true;
    if (_mode == AppThemeMode.light) return false;
    return MediaQuery.platformBrightnessOf(context) == Brightness.dark;
  }

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefKey);
    _mode = AppThemeMode.values.firstWhere(
      (m) => m.name == saved,
      orElse: () => AppThemeMode.system,
    );
  }

  Future<void> setMode(AppThemeMode mode) async {
    if (_mode == mode) return;
    _mode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, mode.name);
  }
}

final appThemeController = AppThemeController();
