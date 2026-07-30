import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 테마 모드
enum AppThemeMode { dark, light, amoled }

const _themeKey = 'app_theme_mode';
const _fontScaleKey = 'app_font_scale';

final themeProvider =
    StateNotifierProvider<ThemeNotifier, AppThemeMode>((ref) {
  return ThemeNotifier();
});

class ThemeNotifier extends StateNotifier<AppThemeMode> {
  ThemeNotifier() : super(AppThemeMode.dark);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getString(_themeKey);
    if (value != null) {
      state = AppThemeMode.values.firstWhere(
        (e) => e.name == value,
        orElse: () => AppThemeMode.dark,
      );
    }
  }

  Future<void> set(AppThemeMode mode) async {
    state = mode;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_themeKey, mode.name);
  }
}

final fontScaleProvider =
    StateNotifierProvider<FontScaleNotifier, double>((ref) {
  return FontScaleNotifier();
});

class FontScaleNotifier extends StateNotifier<double> {
  FontScaleNotifier() : super(1.0);

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();
    final value = prefs.getDouble(_fontScaleKey);
    if (value != null) state = value;
  }

  Future<void> set(double scale) async {
    state = scale;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_fontScaleKey, scale);
  }
}
