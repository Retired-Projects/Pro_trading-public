import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/formatters.dart';
import '../providers/settings_providers.dart';
import '../core/constants/app_constants.dart';
import '../models/stock.dart';
import '../models/portfolio.dart';
import '../models/trade.dart';
import '../providers/market_providers.dart';
import '../providers/portfolio_providers.dart';
import '../providers/service_providers.dart';
import 'trading_screen.dart';

class PortfolioScreen extends ConsumerStatefulWidget {
  const PortfolioScreen({super.key});

  @override
  ConsumerState<PortfolioScreen> createState() => _PortfolioScreenState();
}

class _PortfolioScreenState extends ConsumerState<PortfolioScreen> {
  @override
  Widget build(BuildContext context) {
    ref.watch(themeProvider);
    final portfolio = ref.watch(portfolioProvider);
    final tradeLogs = ref.watch(tradeLogsProvider);
    final orders = ref.watch(ordersProvider);
    final pendingOrders = orders.where((o) => o.isPending).toList();

    // 현재가 업데이트: ref.listen으로 처리 (build 사이클 외부, 리빌드 루프 방지)
    ref.listen(priceStreamProvider, (_, next) {
      final prices = next.valueOrNull;
      if (prices == null) return;
      final priceMap = {
        for (final e in prices.entries) e.key: e.value.currentPrice
      };
      ref.read(portfolioProvider.notifier).updateCurrentPrices(priceMap);
    });

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('내 자산'),
        backgroundColor: AppColors.surface,
      ),
      body: ListView(
        children: [
          // 자산 요약 카드
          _buildAssetSummary(portfolio),

          const SizedBox(height: 4),

          // 매매 통계 카드
          _buildTradeStats(tradeLogs),

          const SizedBox(height: 4),

          // 자산 비중 차트
          if (portfolio.holdings.isNotEmpty) ...[
            _buildAllocationChart(portfolio),
            const SizedBox(height: 4),
          ],

          // 미체결 주문 섹션
          if (pendingOrders.isNotEmpty) ...[
            _buildPendingOrders(context, ref, pendingOrders),
            const SizedBox(height: 4),
          ],

          // 보유 종목 헤더
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            color: AppColors.surface,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('보유 종목',
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
                Text('${portfolio.holdings.length}종목',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 12)),
              ],
            ),
          ),

          // 보유 종목 리스트
          if (portfolio.holdings.isEmpty)
            Container(
              padding: const EdgeInsets.all(40),
              alignment: Alignment.center,
              child: Text('보유 종목이 없습니다',
                  style: TextStyle(color: AppColors.textSecondary)),
            )
          else
            ...portfolio.holdings.map((holding) => Column(
                  children: [
                    _buildHoldingTile(context, holding),
                    Divider(color: AppColors.divider, height: 1),
                  ],
                )),

          const SizedBox(height: 4),

          // 체결 이력
          _buildTradeHistory(ref, tradeLogs),

          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildAssetSummary(Portfolio portfolio) {
    final totalReturn =
        ((portfolio.totalAsset - AppConstants.initialBalance) /
                AppConstants.initialBalance) *
            100;
    final isUp = totalReturn >= 0;

    return Container(
      padding: const EdgeInsets.all(20),
      color: AppColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('총 자산',
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 13)),
                    const SizedBox(height: 4),
                    Text(
                      '${Formatters.largeAmount(portfolio.totalAsset)}원',
                      style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              // 총 수익률 배지
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: isUp
                      ? AppColors.priceUp.withValues(alpha: 0.15)
                      : AppColors.priceDown.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '${isUp ? "+" : ""}${totalReturn.toStringAsFixed(2)}%',
                  style: TextStyle(
                    color: isUp ? AppColors.priceUp : AppColors.priceDown,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildSummaryItem(
                    '총 예수금', Formatters.largeAmount(portfolio.balance), null),
              ),
              Container(width: 1, height: 40, color: AppColors.divider),
              Expanded(
                child: _buildSummaryItem(
                    '가용 예수금', Formatters.largeAmount(portfolio.availableBalance), AppColors.primary),
              ),
              Container(width: 1, height: 40, color: AppColors.divider),
              Expanded(
                child: _buildSummaryItem('평가금',
                    Formatters.largeAmount(portfolio.totalEvaluation), null),
              ),

              Container(width: 1, height: 40, color: AppColors.divider),
              Expanded(
                child: _buildSummaryItem(
                  '평가손익',
                  Formatters.change(portfolio.totalPnl),
                  portfolio.totalPnl >= 0
                      ? AppColors.priceUp
                      : AppColors.priceDown,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 수익률 게이지 카드
  Widget _buildPerformanceCard(Portfolio portfolio) {
    final totalReturn =
        ((portfolio.totalAsset - AppConstants.initialBalance) /
                AppConstants.initialBalance) *
            100;
    final isUp = totalReturn >= 0;

    // -50% ~ +100% 범위 게이지
    final gaugeValue = (totalReturn / 100).clamp(-0.5, 1.0);
    final normalized = (gaugeValue + 0.5) / 1.5; // 0~1로 정규화

    return Container(
      padding: const EdgeInsets.all(16),
      color: AppColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('초기자금 1억 대비',
                  style: TextStyle(
                      color: AppColors.textSecondary, fontSize: 12)),
              Text(
                '${isUp ? "+" : ""}${Formatters.change(portfolio.totalAsset - AppConstants.initialBalance)}원',
                style: TextStyle(
                  color: isUp ? AppColors.priceUp : AppColors.priceDown,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // 게이지 바
          ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: Stack(
              children: [
                Container(
                  height: 8,
                  decoration: BoxDecoration(
                    color: AppColors.surfaceLight,
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                FractionallySizedBox(
                  widthFactor: normalized.clamp(0.0, 1.0),
                  child: Container(
                    height: 8,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: isUp
                            ? [AppColors.priceUp.withValues(alpha: 0.5), AppColors.priceUp]
                            : [AppColors.priceDown, AppColors.priceDown.withValues(alpha: 0.5)],
                      ),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('-50%',
                  style:
                      TextStyle(color: AppColors.textMuted, fontSize: 9)),
              Text('0%',
                  style:
                      TextStyle(color: AppColors.textMuted, fontSize: 9)),
              Text('+100%',
                  style:
                      TextStyle(color: AppColors.textMuted, fontSize: 9)),
            ],
          ),
        ],
      ),
    );
  }

  /// 자산 비중 도넛 차트
  Widget _buildAllocationChart(Portfolio portfolio) {
    final colors = [
      const Color(0xFFFFD700), // gold
      const Color(0xFF4FC3F7), // blue
      const Color(0xFFFF7043), // orange
      const Color(0xFF66BB6A), // green
      const Color(0xFFAB47BC), // purple
      const Color(0xFFEC407A), // pink
      const Color(0xFF26C6DA), // cyan
      const Color(0xFFFF8A65), // deep orange
    ];

    final total = portfolio.totalAsset;
    final items = <_AllocationItem>[];

    // 예수금
    items.add(_AllocationItem(
      label: '예수금',
      value: portfolio.balance,
      ratio: portfolio.balance / total,
      color: AppColors.textMuted,
    ));

    // 보유종목별
    for (var i = 0; i < portfolio.holdings.length; i++) {
      final h = portfolio.holdings[i];
      items.add(_AllocationItem(
        label: h.stockName,
        value: h.totalValue,
        ratio: h.totalValue / total,
        color: colors[i % colors.length],
      ));
    }

    return Container(
      padding: const EdgeInsets.all(16),
      color: AppColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('자산 비중',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Row(
            children: [
              // 도넛 차트
              SizedBox(
                width: 120,
                height: 120,
                child: CustomPaint(
                  painter: _DonutChartPainter(items),
                ),
              ),
              const SizedBox(width: 16),
              // 범례
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: items.map((item) {
                    return Padding(
                      padding: const EdgeInsets.symmetric(vertical: 3),
                      child: Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: item.color,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              item.label,
                              style: TextStyle(
                                  color: AppColors.textSecondary,
                                  fontSize: 11),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          Text(
                            '${(item.ratio * 100).toStringAsFixed(1)}%',
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 매매 통계 카드 (승률, 거래수, 실현손익)
  Widget _buildTradeStats(List<TradeLog> logs) {
    int winCount = 0;
    int lossCount = 0;
    double totalRealizedPnl = 0;

    // 매수 평단 추적을 위한 임시 맵
    final avgPriceMap = <String, double>{};
    final qtyMap = <String, double>{};

    // 시간순 정렬
    final sorted = List<TradeLog>.from(logs)
      ..sort((a, b) => a.executedAt.compareTo(b.executedAt));

    for (final log in sorted) {
      if (log.side == OrderSide.buy) {
        final prev = avgPriceMap[log.stockCode];
        final prevQty = qtyMap[log.stockCode] ?? 0;
        if (prev != null && prevQty > 0) {
          final newQty = prevQty + log.quantity;
          avgPriceMap[log.stockCode] =
              (prev * prevQty + log.price * log.quantity) / newQty;
          qtyMap[log.stockCode] = newQty;
        } else {
          avgPriceMap[log.stockCode] = log.price;
          qtyMap[log.stockCode] = log.quantity;
        }
      } else {
        final avgBuy = avgPriceMap[log.stockCode];
        if (avgBuy != null) {
          final realizedPnl =
              (log.price - avgBuy) * log.quantity - log.fee - log.tax;
          totalRealizedPnl += realizedPnl;
          if (realizedPnl > 0) {
            winCount++;
          } else if (realizedPnl < 0) {
            lossCount++;
          }
          // 보유량 감소
          final prevQty = qtyMap[log.stockCode] ?? 0;
          final newQty = prevQty - log.quantity;
          if (newQty <= 0) {
            qtyMap.remove(log.stockCode);
            avgPriceMap.remove(log.stockCode);
          } else {
            qtyMap[log.stockCode] = newQty;
          }
        }
      }
    }

    final totalTrades = winCount + lossCount;
    final winRate = totalTrades > 0 ? (winCount / totalTrades) * 100 : 0.0;
    final isProfit = totalRealizedPnl >= 0;

    if (logs.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      color: AppColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('매매 통계',
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _buildStatItem(
                  '총 거래',
                  '${logs.length}회',
                  null,
                  Icons.swap_horiz,
                ),
              ),
              Container(width: 1, height: 44, color: AppColors.divider),
              Expanded(
                child: _buildStatItem(
                  '승률',
                  totalTrades > 0
                      ? '${winRate.toStringAsFixed(1)}%'
                      : '-',
                  totalTrades > 0
                      ? (winRate >= 50 ? AppColors.priceUp : AppColors.priceDown)
                      : null,
                  Icons.emoji_events_outlined,
                ),
              ),
              Container(width: 1, height: 44, color: AppColors.divider),
              Expanded(
                child: _buildStatItem(
                  '실현손익',
                  totalTrades > 0
                      ? '${isProfit ? "+" : ""}${Formatters.change(totalRealizedPnl)}'
                      : '-',
                  totalTrades > 0
                      ? (isProfit ? AppColors.priceUp : AppColors.priceDown)
                      : null,
                  Icons.account_balance_outlined,
                ),
              ),
            ],
          ),
          if (totalTrades > 0) ...[
            const SizedBox(height: 10),
            // 승/패 바
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: Row(
                children: [
                  Expanded(
                    flex: winCount > 0 ? winCount : 1,
                    child: Container(
                      height: 6,
                      color: AppColors.priceUp,
                    ),
                  ),
                  Expanded(
                    flex: lossCount > 0 ? lossCount : 1,
                    child: Container(
                      height: 6,
                      color: lossCount > 0
                          ? AppColors.priceDown
                          : Colors.transparent,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('수익 $winCount회',
                    style: TextStyle(
                        color: AppColors.priceUp,
                        fontSize: 10,
                        fontWeight: FontWeight.w500)),
                Text('손실 $lossCount회',
                    style: TextStyle(
                        color: lossCount > 0
                            ? AppColors.priceDown
                            : AppColors.textMuted,
                        fontSize: 10,
                        fontWeight: FontWeight.w500)),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildStatItem(String label, String value, Color? valueColor,
      IconData icon) {
    return Column(
      children: [
        Icon(icon, size: 16, color: AppColors.textMuted),
        const SizedBox(height: 4),
        Text(label,
            style: TextStyle(color: AppColors.textMuted, fontSize: 10)),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            color: valueColor ?? AppColors.textPrimary,
            fontSize: 13,
            fontWeight: FontWeight.bold,
          ),
        ),
      ],
    );
  }

  /// 미체결 주문 섹션
  Widget _buildPendingOrders(
      BuildContext context, WidgetRef ref, List<Order> pendingOrders) {
    return Container(
      color: AppColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: Row(
              children: [
                Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.only(right: 8),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                  ),
                ),
                Text('미체결 주문',
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
                const SizedBox(width: 6),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text('${pendingOrders.length}',
                      style: TextStyle(
                          color: AppColors.primary,
                          fontSize: 10,
                          fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
          ...pendingOrders.map((order) {
            final isBuy = order.side == OrderSide.buy;
            final sideColor =
                isBuy ? AppColors.priceUp : AppColors.priceDown;
            final typeLabel = order.type == OrderType.stopLoss
                ? '손절'
                : order.type == OrderType.takeProfit
                    ? '익절'
                    : '지정가';

            return Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                border:
                    Border(bottom: BorderSide(color: AppColors.divider)),
              ),
              child: Row(
                children: [
                  // 유형 배지
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: sideColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(isBuy ? '매수' : '매도',
                            style: TextStyle(
                                color: sideColor,
                                fontSize: 10,
                                fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(height: 3),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceLight,
                          borderRadius: BorderRadius.circular(3),
                        ),
                        child: Text(typeLabel,
                            style: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 9)),
                      ),
                    ],
                  ),
                  const SizedBox(width: 12),

                  // 종목명 + 수량
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(order.stockName,
                            style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w500),
                            overflow: TextOverflow.ellipsis),
                        Text(
                          '${Formatters.price(order.price)}원 × ${order.quantity}주',
                          style: TextStyle(
                              color: AppColors.textSecondary, fontSize: 11),
                        ),
                      ],
                    ),
                  ),

                  // 취소 버튼
                  TextButton(
                    onPressed: () => _showCancelDialog(context, ref, order),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 6),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text('취소',
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 12)),
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 4),
        ],
      ),
    );
  }

  void _showCancelDialog(
      BuildContext context, WidgetRef ref, Order order) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('주문 취소',
            style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.bold)),
        content: Text(
          '${order.stockName} ${order.type == OrderType.stopLoss ? "손절" : order.type == OrderType.takeProfit ? "익절" : "지정가"} 주문을 취소하시겠습니까?',
          style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('닫기',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              // TradingEngine에서도 취소
              ref.read(tradingEngineProvider).cancelOrder(order.id);
              // Provider 상태 업데이트
              await ref.read(ordersProvider.notifier).cancelOrder(order.id);
            },
            child: Text('취소 확인',
                style: TextStyle(
                    color: AppColors.priceDown,
                    fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryItem(String label, String value, Color? valueColor) {
    return Column(
      children: [
        Text(label,
            style: TextStyle(color: AppColors.textMuted, fontSize: 11)),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: valueColor ?? AppColors.textPrimary,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }

  Widget _buildHoldingTile(BuildContext context, Holding holding) {
    return GestureDetector(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => TradingScreen(
              stock: Stock(
                code: holding.stockCode,
                name: holding.stockName,
                basePrice: holding.currentPrice,
              ),
            ),
          ),
        );
      },
      child: Container(
        color: AppColors.background,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(holding.stockName,
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w500)),
                  Text(
                      '${holding.quantity}주 · 평단 ${Formatters.price(holding.avgPrice)}',
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 11)),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(Formatters.price(holding.currentPrice),
                      style: TextStyle(
                          color: AppColors.textPrimary, fontSize: 14)),
                  Text(Formatters.price(holding.totalValue),
                      style: TextStyle(
                          color: AppColors.textSecondary, fontSize: 11)),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              width: 80,
              padding: const EdgeInsets.symmetric(vertical: 6),
              decoration: BoxDecoration(
                color: holding.isProfit
                    ? AppColors.priceUp.withValues(alpha: 0.15)
                    : holding.isLoss
                        ? AppColors.priceDown.withValues(alpha: 0.15)
                        : AppColors.surfaceLight,
                borderRadius: BorderRadius.circular(4),
              ),
              alignment: Alignment.center,
              child: Text(
                Formatters.percent(holding.pnlRate),
                style: TextStyle(
                  color: holding.isProfit
                      ? AppColors.priceUp
                      : holding.isLoss
                          ? AppColors.priceDown
                          : AppColors.textSecondary,
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }


  Widget _buildTradeHistory(WidgetRef ref, List<TradeLog> logs) {
    if (logs.isEmpty) return const SizedBox.shrink();

    final dateFormat = DateFormat('MM.dd HH:mm');
    final displayLogs = logs.take(20).toList();

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('최근 체결',
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600)),
                Text('${logs.length}건',
                    style: TextStyle(
                        color: AppColors.textSecondary, fontSize: 11)),
              ],
            ),
          ),
          ...displayLogs.map((log) {
            final isBuy = log.side == OrderSide.buy;
            final sideColor = isBuy ? AppColors.priceUp : AppColors.priceDown;
            final totalAmt = log.price * log.quantity;

            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                border:
                    Border(bottom: BorderSide(color: AppColors.divider, width: 0.5)),
              ),
              child: Row(
                children: [
                  // 매수/매도 배지
                  Container(
                    width: 32,
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    decoration: BoxDecoration(
                      color: sideColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    alignment: Alignment.center,
                    child: Text(isBuy ? '매수' : '매도',
                        style: TextStyle(
                            color: sideColor,
                            fontSize: 10,
                            fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 10),

                  // 종목명 + 시간
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(log.stockName,
                            style: TextStyle(
                                color: AppColors.textPrimary,
                                fontSize: 13,
                                fontWeight: FontWeight.w500),
                            overflow: TextOverflow.ellipsis),
                        Text(dateFormat.format(log.executedAt),
                            style: TextStyle(
                                color: AppColors.textMuted, fontSize: 10)),
                      ],
                    ),
                  ),

                  // 금액 + 수량
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '${Formatters.price(log.price)}원',
                        style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 12,
                            fontWeight: FontWeight.w500),
                      ),
                      Text(
                        '${log.quantity}주 · ${Formatters.largeAmount(totalAmt)}',
                        style: TextStyle(
                            color: AppColors.textSecondary, fontSize: 10),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }),
          if (logs.length > 20)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                '최근 20건만 표시됩니다',
                style: TextStyle(color: AppColors.textMuted, fontSize: 11),
                textAlign: TextAlign.center,
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}

/// 도넛 차트용 데이터
class _AllocationItem {
  final String label;
  final double value;
  final double ratio;
  final Color color;

  _AllocationItem({
    required this.label,
    required this.value,
    required this.ratio,
    required this.color,
  });
}

/// 도넛 차트 페인터
class _DonutChartPainter extends CustomPainter {
  final List<_AllocationItem> items;

  _DonutChartPainter(this.items);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = min(size.width, size.height) / 2;
    final strokeWidth = radius * 0.35;
    final rect = Rect.fromCircle(center: center, radius: radius - strokeWidth / 2);

    double startAngle = -pi / 2;

    for (final item in items) {
      final sweepAngle = item.ratio * 2 * pi;
      final paint = Paint()
        ..color = item.color
        ..style = PaintingStyle.stroke
        ..strokeWidth = strokeWidth
        ..strokeCap = StrokeCap.butt;

      canvas.drawArc(rect, startAngle, sweepAngle - 0.02, false, paint);
      startAngle += sweepAngle;
    }
  }

  @override
  bool shouldRepaint(covariant _DonutChartPainter oldDelegate) {
    if (oldDelegate.items.length != items.length) return true;
    for (var i = 0; i < items.length; i++) {
      if (oldDelegate.items[i].ratio != items[i].ratio ||
          oldDelegate.items[i].color != items[i].color) {
        return true;
      }
    }
    return false;
  }
}
