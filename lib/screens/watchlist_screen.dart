import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/formatters.dart';
import '../providers/settings_providers.dart';
import '../models/stock.dart';
import '../providers/market_providers.dart';
import '../providers/watchlist_provider.dart';
import '../providers/service_providers.dart';
import 'trading_screen.dart';

class WatchlistScreen extends ConsumerWidget {
  const WatchlistScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(themeProvider);
    final watchlist = ref.watch(watchlistProvider);
    final prices = ref.watch(priceStreamProvider).valueOrNull ?? {};

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('관심종목'),
        backgroundColor: AppColors.surface,
      ),
      body: watchlist.isEmpty
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.star_border, size: 48, color: AppColors.textMuted),
                  SizedBox(height: 12),
                  Text('관심종목이 없습니다',
                      style:
                          TextStyle(color: AppColors.textSecondary, fontSize: 15)),
                  SizedBox(height: 6),
                  Text('종목 상세에서 ★ 버튼을 눌러 추가하세요',
                      style:
                          TextStyle(color: AppColors.textMuted, fontSize: 13)),
                ],
              ),
            )
          : ListView.separated(
              itemCount: watchlist.length,
              separatorBuilder: (_, _) =>
                  Divider(color: AppColors.divider, height: 1),
              itemBuilder: (context, index) {
                final item = watchlist[index];
                final code = item['code']!;
                final name = item['name']!;
                final market = item['market'] ?? '';
                final price = prices[code];

                return _buildTile(context, ref, code, name, market, price);
              },
            ),
    );
  }

  Widget _buildTile(BuildContext context, WidgetRef ref, String code,
      String name, String market, StockPrice? price) {
    final currentPrice = price?.currentPrice ?? 0;
    final changeRate = price?.changeRate ?? 0.0;
    final isUp = (price?.changeAmount ?? 0) > 0;
    final isDown = (price?.changeAmount ?? 0) < 0;

    final color = isUp
        ? AppColors.priceUp
        : isDown
            ? AppColors.priceDown
            : AppColors.priceNeutral;

    return Dismissible(
      key: ValueKey(code),
      direction: DismissDirection.endToStart,
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 20),
        color: Colors.red.shade800,
        child:
            const Icon(Icons.delete_outline, color: Colors.white),
      ),
      onDismissed: (_) {
        ref.read(watchlistProvider.notifier).remove(code);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('$name 관심종목에서 삭제',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w500)),
            backgroundColor: const Color(0xFF3A3A5C),
            action: SnackBarAction(
              label: '취소',
              textColor: AppColors.primary,
              onPressed: () {
                ref
                    .read(watchlistProvider.notifier)
                    .add(code, name, market);
              },
            ),
          ),
        );
      },
      child: InkWell(
        onTap: () {
          ref
              .read(mockDataServiceProvider)
              .registerStock(code, name, price: currentPrice);
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => TradingScreen(
                stock:
                    Stock(code: code, name: name, basePrice: currentPrice),
              ),
            ),
          );
        },
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: Row(
            children: [
              // 별 아이콘
              Icon(Icons.star, color: AppColors.primary, size: 18),
              const SizedBox(width: 10),

              // 종목명
              Expanded(
                flex: 3,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name,
                        style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 14,
                            fontWeight: FontWeight.w500),
                        overflow: TextOverflow.ellipsis),
                    Row(
                      children: [
                        Text(code,
                            style: TextStyle(
                                color: AppColors.textMuted, fontSize: 10)),
                        if (market.isNotEmpty) ...[
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 1),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceLight,
                              borderRadius: BorderRadius.circular(3),
                            ),
                            child: Text(
                              market == 'KOSPI'
                                  ? '코스피'
                                  : market == 'KOSDAQ'
                                      ? '코스닥'
                                      : market,
                              style: TextStyle(
                                  color: AppColors.textMuted, fontSize: 9),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              // 현재가
              Expanded(
                flex: 2,
                child: Text(
                  currentPrice > 0 ? Formatters.price(currentPrice) : '-',
                  style: TextStyle(
                      color: color,
                      fontSize: 14,
                      fontWeight: FontWeight.w600),
                  textAlign: TextAlign.right,
                ),
              ),

              const SizedBox(width: 8),

              // 등락률
              Container(
                width: 68,
                padding: const EdgeInsets.symmetric(vertical: 5),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                ),
                alignment: Alignment.center,
                child: Text(
                  currentPrice > 0 ? Formatters.percent(changeRate) : '-',
                  style: TextStyle(
                      color: color,
                      fontSize: 12,
                      fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
