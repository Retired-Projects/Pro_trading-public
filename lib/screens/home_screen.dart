import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/constants/app_constants.dart';
import '../core/theme/app_colors.dart';
import '../models/trade.dart';
import '../providers/service_providers.dart';
import '../providers/portfolio_providers.dart';
import '../providers/market_providers.dart';
import '../providers/settings_providers.dart';
import '../providers/watchlist_provider.dart';
import '../services/yahoo_finance_service.dart';
import 'stock_list_screen.dart';
import 'watchlist_screen.dart';
import 'portfolio_screen.dart';
import 'leaderboard_screen.dart';
import 'ai_report_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  int _currentIndex = 0;
  bool _initialized = false;

  final _screens = const [
    StockListScreen(),
    WatchlistScreen(),
    PortfolioScreen(),
    LeaderboardScreen(),
    AiReportScreen(),
    SettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _initialize());
  }

  Future<void> _initialize() async {
    if (_initialized) return;
    _initialized = true;

    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      ref.read(userIdProvider.notifier).state = user.id;

      // 모든 초기 데이터를 병렬로 로드
      await Future.wait([
        ref.read(portfolioProvider.notifier).loadFromSupabase(),
        ref.read(ordersProvider.notifier).loadPendingOrders(),
        ref.read(tradeLogsProvider.notifier).loadTradeLogs(),
        ref.read(watchlistProvider.notifier).load(),
        ref.read(supabaseServiceProvider).updateLastLoginAt(user.id),
      ]);
    }

    // 종목 로드 & 폴링 시작
    final stocks = await ref.read(stockListProvider.future);
    final codes = stocks.map((s) => s['code']!).toList();
    ref.read(pollingServiceProvider).setStockCodes(codes);
    ref.read(pollingServiceProvider).start();
  }

  /// 종목 코드로 해당 시장이 열려있는지 판단
  bool _isMarketOpenFor(String stockCode) {
    // 미국 주식 (알파벳 티커)
    if (YahooFinanceService.usStocks.any((s) => s['code'] == stockCode)) {
      return AppConstants.isUsMarketOpen();
    }
    // 한국 주식: 6자리 숫자 코드
    if (RegExp(r'^\d{6}$').hasMatch(stockCode)) {
      return AppConstants.isKrMarketOpen();
    }
    // 그 외 (BTC, ETH 등 암호화폐): 24시간 거래
    return true;
  }

  /// 미체결 주문 자동 체결 처리
  Future<void> _checkAndFillPendingOrders() async {
    final engine = ref.read(tradingEngineProvider);
    final results = engine.checkPendingOrders(isMarketOpen: _isMarketOpenFor);
    if (results.isEmpty) return;

    for (final result in results) {
      if (!result.isSuccess || result.isPending) continue;
      final order = result.order!;
      final tradeLog = result.tradeLog!;

      await ref.read(tradeLogsProvider.notifier).addLog(tradeLog);
      await ref.read(ordersProvider.notifier).fillOrder(
        order.id,
        order.filledQuantity,
        order.filledAt!,
      );

      if (order.side == OrderSide.buy) {
        // 예약 정보 해제
        final reservedAmount = order.price * order.quantity * (1 + AppConstants.tradingFeeRate);
        ref.read(portfolioProvider.notifier).unreserveBalance(reservedAmount);

        await ref.read(portfolioProvider.notifier).deductBalance(tradeLog.netAmount);
        await ref.read(portfolioProvider.notifier).addHolding(
          order.stockCode,
          order.stockName,
          order.quantity,
          tradeLog.price,
        );
      } else {

        await ref.read(portfolioProvider.notifier).addBalance(tradeLog.netAmount);
        await ref.read(portfolioProvider.notifier).removeHolding(
          order.stockCode,
          order.quantity,
        );
      }

      // 체결 알림
      if (mounted) {
        final typeLabel = order.type == OrderType.stopLoss
            ? '손절'
            : order.type == OrderType.takeProfit
                ? '익절'
                : '지정가';
        final sideLabel = order.side == OrderSide.buy ? '매수' : '매도';
        HapticFeedback.mediumImpact();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '$typeLabel $sideLabel 체결: ${order.stockName} × ${order.quantity}주',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500),
            ),
            backgroundColor: order.side == OrderSide.buy
                ? const Color(0xFF1B5E20)
                : const Color(0xFFB71C1C),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    ref.read(pollingServiceProvider).stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(themeProvider);
    // 가격 업데이트 시마다 미체결 주문 체결 확인 (미체결 주문이 있을 때만)
    ref.listen(priceStreamProvider, (_, next) {
      if (!next.hasValue) return;
      final hasPending = ref.read(
        ordersProvider.select((orders) => orders.any((o) => o.isPending)),
      );
      if (hasPending) _checkAndFillPendingOrders();
    });

    final pendingCount = ref.watch(
      ordersProvider.select((orders) => orders.where((o) => o.isPending).length),
    );

    return Scaffold(
      body: Column(
        children: [
          // 모의 투자 안내 배너
          SafeArea(
            bottom: false,
            child: Container(
              width: double.infinity,
              color: AppColors.primary.withValues(alpha: 0.12),
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Text(
                '모의 투자 서비스 — 실제 투자가 아닙니다',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.primary,
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 0.3,
                ),
              ),
            ),
          ),
          Expanded(
            child: IndexedStack(
              index: _currentIndex,
              children: _screens,
            ),
          ),
        ],
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _currentIndex,
        onTap: (index) {
          HapticFeedback.selectionClick();
          setState(() => _currentIndex = index);
        },
        backgroundColor: AppColors.surface,
        selectedItemColor: AppColors.primary,
        unselectedItemColor: AppColors.textSecondary,
        type: BottomNavigationBarType.fixed,
        items: [
          const BottomNavigationBarItem(
            icon: Icon(Icons.candlestick_chart),
            label: '종목',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.star),
            label: '관심',
          ),
          BottomNavigationBarItem(
            icon: pendingCount > 0
                ? Badge(
                    label: Text('$pendingCount',
                        style: const TextStyle(fontSize: 10)),
                    child: const Icon(Icons.account_balance_wallet),
                  )
                : const Icon(Icons.account_balance_wallet),
            label: '자산',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.emoji_events),
            label: '랭킹',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.analytics_outlined),
            label: '분석',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: '설정',
          ),
        ],
      ),
    );
  }
}
