import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme/app_colors.dart';
import '../core/constants/app_constants.dart';
import '../providers/settings_providers.dart';

/// 시장 현황 상태 바
class MarketStatusBar extends ConsumerWidget {
  const MarketStatusBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(themeProvider);
    final krOpen = AppConstants.isKrMarketOpen();
    final usOpen = AppConstants.isUsMarketOpen();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: AppColors.surface,
      child: Row(
        children: [
          _buildMarketChip('KR', krOpen),
          const SizedBox(width: 8),
          _buildMarketChip('US', usOpen),
          const SizedBox(width: 8),
          _buildMarketChip('CRYPTO', true),
          const Spacer(),
          Icon(
            Icons.circle,
            size: 8,
            color: (krOpen || usOpen)
                ? Colors.greenAccent
                : AppColors.textMuted,
          ),
          const SizedBox(width: 6),
          Text(
            (krOpen || usOpen) ? '장 운영중' : '장 마감',
            style: TextStyle(
              color: (krOpen || usOpen)
                  ? Colors.greenAccent
                  : AppColors.textMuted,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMarketChip(String label, bool isOpen) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: isOpen
            ? Colors.greenAccent.withValues(alpha: 0.15)
            : AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: isOpen
              ? Colors.greenAccent.withValues(alpha: 0.4)
              : AppColors.divider,
          width: 0.5,
        ),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: isOpen ? Colors.greenAccent : AppColors.textMuted,
          fontSize: 10,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
