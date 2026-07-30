import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/portfolio.dart';
import '../models/trade.dart';
import '../core/constants/app_constants.dart';
import 'service_providers.dart';

/// 포트폴리오 상태 관리 (Supabase 연동)
class PortfolioNotifier extends StateNotifier<Portfolio> {
  final Ref ref;
  Timer? _balanceSyncDebounce;

  PortfolioNotifier(this.ref)
      : super(const Portfolio(
          balance: AppConstants.initialBalance,
          holdings: [],
        ));

  @override
  void dispose() {
    _balanceSyncDebounce?.cancel();
    super.dispose();
  }

  /// Supabase에서 데이터 로드
  Future<void> loadFromSupabase() async {
    final userId = ref.read(userIdProvider);
    if (userId == null) return;

    final supabase = ref.read(supabaseServiceProvider);

    final profile = await supabase.getOrCreateProfile(userId);
    final holdings = await supabase.getHoldings(userId);

    state = Portfolio(
      balance: (profile['balance'] as num).toDouble(),
      holdings: holdings,
    );

    // 미체결 주문 기반으로 예약 예수금 계산
    final pendingOrders = await supabase.getPendingOrders(userId);
    double reserved = 0;
    for (final o in pendingOrders) {
      if (o.side == OrderSide.buy) {
        final amt = o.price * o.quantity;
        reserved += amt + (amt * AppConstants.tradingFeeRate);
      }
    }
    state = state.copyWith(reservedBalance: reserved);

    // 로그인 시 총 자산 동기화
    await _syncTotalAsset();

  }

  /// 잔고 차감 (매수 시) + Supabase 동기화
  Future<void> deductBalance(double amount) async {
    final newBalance = state.balance - amount;
    state = state.copyWith(balance: newBalance);
    await _syncBalance(newBalance);
  }

  /// 잔고 추가 (매도 시) + Supabase 동기화
  Future<void> addBalance(double amount) async {
    final newBalance = state.balance + amount;
    state = state.copyWith(balance: newBalance);
    await _syncBalance(newBalance);
  }

  /// 보유 종목 추가/업데이트 (매수 체결) + Supabase 동기화
  Future<void> addHolding(
      String stockCode, String stockName, double quantity, double price) async {
    final holdings = List<Holding>.from(state.holdings);
    final existingIndex =
        holdings.indexWhere((h) => h.stockCode == stockCode);

    double newQty;
    double newAvgPrice;

    if (existingIndex >= 0) {
      final existing = holdings[existingIndex];
      newQty = existing.quantity + quantity;
      newAvgPrice =
          ((existing.avgPrice * existing.quantity) + (price * quantity)) /
              newQty;
      holdings[existingIndex] = existing.copyWith(
        quantity: newQty,
        avgPrice: newAvgPrice,
      );
    } else {
      newQty = quantity;
      newAvgPrice = price;
      holdings.add(Holding(
        stockCode: stockCode,
        stockName: stockName,
        quantity: quantity,
        avgPrice: price,
        currentPrice: price,
      ));
    }

    state = state.copyWith(holdings: holdings);
    await _syncHolding(stockCode, stockName, newQty, newAvgPrice);
  }

  /// 보유 종목 감소 (매도 체결) + Supabase 동기화
  Future<void> removeHolding(String stockCode, double quantity) async {
    final holdings = List<Holding>.from(state.holdings);
    final existingIndex =
        holdings.indexWhere((h) => h.stockCode == stockCode);

    if (existingIndex >= 0) {
      final existing = holdings[existingIndex];
      final newQty = existing.quantity - quantity;
      if (newQty <= 1e-9) {
        holdings.removeAt(existingIndex);
        await _deleteHolding(stockCode);
      } else {
        holdings[existingIndex] = existing.copyWith(quantity: newQty);
        await _syncHolding(
            stockCode, existing.stockName, newQty, existing.avgPrice);
      }
    }

    state = state.copyWith(holdings: holdings);
  }

  /// 보유 종목 현재가 업데이트 (로컬만, Supabase 불필요)
  void updateCurrentPrices(Map<String, double> prices) {
    final holdings = state.holdings.map((h) {
      final newPrice = prices[h.stockCode];
      if (newPrice != null) {
        return h.copyWith(currentPrice: newPrice);
      }
      return h;
    }).toList();
    state = state.copyWith(holdings: holdings);
  }

  /// 예수금 묶기 (미체결 주문 등록 시)
  void reserveBalance(double amount) {
    state = state.copyWith(reservedBalance: state.reservedBalance + amount);
  }

  /// 예수금 묶음 해제 (주문 취소 또는 체결 시)
  void unreserveBalance(double amount) {
    final newVal = state.reservedBalance - amount;
    state = state.copyWith(reservedBalance: newVal < 0 ? 0 : newVal);
  }

  // ─── Supabase 동기화 헬퍼 ───

  /// 잔고 동기화: 연속 거래 시 500ms 디바운싱으로 API 호출 최소화
  Future<void> _syncBalance(double balance) async {

    _balanceSyncDebounce?.cancel();
    _balanceSyncDebounce = Timer(const Duration(milliseconds: 500), () async {
      final userId = ref.read(userIdProvider);
      if (userId == null) return;
      final supabase = ref.read(supabaseServiceProvider);
      // 타이머 실행 시점의 최신 잔고 사용 (파라미터 아님)
      await supabase.updateBalance(userId, state.balance);
      await _syncTotalAsset();
    });
  }

  /// 총 자산(예수금 + 보유종목 매입금액)을 profiles에 동기화
  Future<void> _syncTotalAsset() async {
    final userId = ref.read(userIdProvider);
    if (userId == null) return;
    final supabase = ref.read(supabaseServiceProvider);
    final holdingsCost =
        state.holdings.fold(0.0, (sum, h) => sum + h.totalCost);
    final totalAsset = state.balance + holdingsCost;
    try {
      await supabase.updateTotalAsset(userId, totalAsset);
    } catch (_) {
      // total_asset 컬럼이 없을 수 있음 — 무시
    }
  }

  Future<void> _syncHolding(
      String stockCode, String stockName, double qty, double avgPrice) async {
    final userId = ref.read(userIdProvider);
    if (userId == null) return;
    final supabase = ref.read(supabaseServiceProvider);
    await supabase.upsertHolding(userId, stockCode, stockName, qty, avgPrice);
  }

  Future<void> _deleteHolding(String stockCode) async {
    final userId = ref.read(userIdProvider);
    if (userId == null) return;
    final supabase = ref.read(supabaseServiceProvider);
    await supabase.deleteHolding(userId, stockCode);
  }
}

final portfolioProvider =
    StateNotifierProvider<PortfolioNotifier, Portfolio>((ref) {
  return PortfolioNotifier(ref);
});

/// 주문 내역 (Supabase 연동)
class OrdersNotifier extends StateNotifier<List<Order>> {
  final Ref ref;
  OrdersNotifier(this.ref) : super([]);

  Future<void> addOrder(Order order) async {
    state = [order, ...state];
    final userId = ref.read(userIdProvider);
    if (userId == null) return;
    final supabase = ref.read(supabaseServiceProvider);
    await supabase.insertOrder(userId, order);
  }

  Future<void> updateOrder(String orderId, Order updatedOrder) async {
    state = state.map((o) => o.id == orderId ? updatedOrder : o).toList();
    final userId = ref.read(userIdProvider);
    if (userId == null) return;
    final supabase = ref.read(supabaseServiceProvider);
    await supabase.updateOrderStatus(
      orderId,
      updatedOrder.status,
      filledQuantity: updatedOrder.filledQuantity,
      filledAt: updatedOrder.filledAt,
    );
  }

  /// Supabase에서 미체결 주문 로드
  Future<void> loadPendingOrders() async {
    final userId = ref.read(userIdProvider);
    if (userId == null) return;
    final supabase = ref.read(supabaseServiceProvider);
    final orders = await supabase.getPendingOrders(userId);
    state = orders;
  }

  /// 미체결 주문 취소
  Future<void> cancelOrder(String orderId) async {
    final cancelled = state.map((o) {
      if (o.id == orderId) return o.copyWith(status: OrderStatus.cancelled);
      return o;
    }).toList();
    state = cancelled;

    final userId = ref.read(userIdProvider);
    if (userId == null) return;
    final supabase = ref.read(supabaseServiceProvider);
    await supabase.updateOrderStatus(orderId, OrderStatus.cancelled);

    // 예수금 예약 해제
    final cancelledOrder = state.firstWhere((o) => o.id == orderId);
    if (cancelledOrder.side == OrderSide.buy) {
      final totalAmount = cancelledOrder.price * cancelledOrder.quantity;
      final fee = totalAmount * AppConstants.tradingFeeRate;
      ref.read(portfolioProvider.notifier).unreserveBalance(totalAmount + fee);
    }
  }


  /// 체결 완료 처리 (자동 체결 시)
  Future<void> fillOrder(String orderId, double filledQty, DateTime filledAt) async {
    state = state.map((o) {
      if (o.id == orderId) {
        return o.copyWith(
          filledQuantity: filledQty,
          status: OrderStatus.filled,
          filledAt: filledAt,
        );
      }
      return o;
    }).toList();

    final supabase = ref.read(supabaseServiceProvider);
    await supabase.updateOrderStatus(
      orderId,
      OrderStatus.filled,
      filledQuantity: filledQty,
      filledAt: filledAt,
    );
  }
}

final ordersProvider =
    StateNotifierProvider<OrdersNotifier, List<Order>>((ref) {
  return OrdersNotifier(ref);
});

/// 체결 이력 (Supabase 연동)
class TradeLogsNotifier extends StateNotifier<List<TradeLog>> {
  final Ref ref;
  TradeLogsNotifier(this.ref) : super([]);

  Future<void> addLog(TradeLog log) async {
    state = [log, ...state];
    final userId = ref.read(userIdProvider);
    if (userId == null) return;
    final supabase = ref.read(supabaseServiceProvider);
    await supabase.insertTradeLog(userId, log);
  }

  /// Supabase에서 체결 이력 로드
  Future<void> loadTradeLogs() async {
    final userId = ref.read(userIdProvider);
    if (userId == null) return;
    final supabase = ref.read(supabaseServiceProvider);
    final logs = await supabase.getTradeLogs(userId);
    state = logs;
  }
}

final tradeLogsProvider =
    StateNotifierProvider<TradeLogsNotifier, List<TradeLog>>((ref) {
  return TradeLogsNotifier(ref);
});
