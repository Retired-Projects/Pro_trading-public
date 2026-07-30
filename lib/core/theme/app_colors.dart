import 'dart:ui';

import '../../providers/settings_providers.dart';

class AppColors {
  static AppThemeMode _mode = AppThemeMode.dark;

  static void setMode(AppThemeMode mode) {
    if (_mode == mode) return; // 동일 모드 중복 호출 방지
    _mode = mode;
  }

  static bool get _isLight => _mode == AppThemeMode.light;

  // Background
  static Color get background =>
      _isLight ? const Color(0xFFF2F3F5) : const Color(0xFF121222);
  static Color get surface =>
      _isLight ? const Color(0xFFFFFFFF) : const Color(0xFF1A1A2E);
  static Color get surfaceLight =>
      _isLight ? const Color(0xFFE8EAF0) : const Color(0xFF252540);

  // Trading colors (Korean standard: red=up, blue=down)
  static const Color priceUp = Color(0xFFFF4444);
  static const Color priceDown = Color(0xFF4444FF);
  static Color get priceNeutral =>
      _isLight ? const Color(0xFF555555) : const Color(0xFFCCCCCC);

  // Accent
  static Color get primary =>
      _isLight ? const Color(0xFFE6A800) : const Color(0xFFFFD700);
  static Color get secondary =>
      _isLight ? const Color(0xFF00B894) : const Color(0xFF00D4AA);

  // Text
  static Color get textPrimary =>
      _isLight ? const Color(0xFF1A1A1A) : const Color(0xFFEEEEEE);
  static Color get textSecondary =>
      _isLight ? const Color(0xFF666666) : const Color(0xFF888888);
  static Color get textMuted =>
      _isLight ? const Color(0xFFAAAAAA) : const Color(0xFF555555);

  // UI
  static Color get divider =>
      _isLight ? const Color(0xFFDDE0E6) : const Color(0xFF2A2A3E);
  static Color get orderBookBid =>
      _isLight ? const Color(0x22FF4444) : const Color(0x33FF4444);
  static Color get orderBookAsk =>
      _isLight ? const Color(0x224444FF) : const Color(0x334444FF);
}
