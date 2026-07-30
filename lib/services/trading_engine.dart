import 'package:uuid/uuid.dart';
import '../models/trade.dart';
import '../core/constants/app_constants.dart';
import 'mock_data_service.dart';

/// 체결 엔진
/// - 시장가/지정가 주문 처리
/// - 현재가와 주문가 비교하여 즉시 체결 / 미체결 관리
/// - 수수료 및 세금 계산
class TradingEngine {
  final MockDataService _mockDataService;
  final _uuid = const Uuid();

  // 미체결 지정가 주문 목록
  final List<Order> _pendingOrders = [];

  TradingEngine(this._mockDataService);

  /// 시장가 주문
  TradeResult placeMarketOrder({
    required String stockCode,
    required String stockName,
    required OrderSide side,
    required double quantity,
    required double currentBalance,
    required double currentHolding,
    double? overridePrice,
  }) {
    final double executionPrice;
    if (overridePrice != null) {
      executionPrice = overridePrice;
    } else {
      final price = _mockDataService.getPrice(stockCode);
      if (price == null) {
        return TradeResult.failure('시세 정보를 가져올 수 없습니다.');
      }
      executionPrice = price.currentPrice;
    }

    // 매수 시 잔고 확인
    if (side == OrderSide.buy) {
      final totalCost = executionPrice * quantity;
      final fee = totalCost * AppConstants.tradingFeeRate;
      if (totalCost + fee > currentBalance) {
        return TradeResult.failure('잔고가 부족합니다. (가용 잔고 확인 필)');
      }
    }

    // 매도 시 보유량 확인
    if (side == OrderSide.sell) {
      if (quantity > currentHolding) {
        return TradeResult.failure('보유 수량이 부족합니다.');
      }
    }

    final orderId = _uuid.v4();
    final tradeLogId = _uuid.v4();
    final now = DateTime.now();

    final fee = executionPrice * quantity * AppConstants.tradingFeeRate;
    final tax = side == OrderSide.sell
        ? executionPrice * quantity * AppConstants.taxRate
        : 0.0;

    final order = Order(
      id: orderId,
      stockCode: stockCode,
      stockName: stockName,
      type: OrderType.market,
      side: side,
      price: executionPrice,
      quantity: quantity,
      filledQuantity: quantity,
      status: OrderStatus.filled,
      createdAt: now,
      filledAt: now,
    );

    final tradeLog = TradeLog(
      id: tradeLogId,
      orderId: orderId,
      stockCode: stockCode,
      stockName: stockName,
      side: side,
      price: executionPrice,
      quantity: quantity,
      fee: fee,
      tax: tax,
      executedAt: now,
    );

    return TradeResult.success(order: order, tradeLog: tradeLog);
  }

  /// 지정가 주문
  TradeResult placeLimitOrder({
    required String stockCode,
    required String stockName,
    required OrderSide side,
    required double limitPrice,
    required double quantity,
    required double currentBalance,
    required double currentHolding,
    double? overridePrice,
  }) {
    // 매수 시 잔고 확인
    if (side == OrderSide.buy) {
      final totalCost = limitPrice * quantity;
      final fee = totalCost * AppConstants.tradingFeeRate;
      if (totalCost + fee > currentBalance) {
        return TradeResult.failure('잔고가 부족합니다. (가용 잔고 확인 필)');
      }
    }

    // 매도 시 보유량 확인
    if (side == OrderSide.sell) {
      if (quantity > currentHolding) {
        return TradeResult.failure('보유 수량이 부족합니다.');
      }
    }

    final double currentPriceForLimit;
    if (overridePrice != null) {
      currentPriceForLimit = overridePrice;
    } else {
      final price = _mockDataService.getPrice(stockCode);
      if (price == null) {
        return TradeResult.failure('시세 정보를 가져올 수 없습니다.');
      }
      currentPriceForLimit = price.currentPrice;
    }

    final orderId = _uuid.v4();
    final now = DateTime.now();

    // 즉시 체결 가능 여부 확인
    final canFillImmediately = side == OrderSide.buy
        ? limitPrice >= currentPriceForLimit
        : limitPrice <= currentPriceForLimit;

    if (canFillImmediately) {
      final executionPrice = currentPriceForLimit;
      final fee = executionPrice * quantity * AppConstants.tradingFeeRate;
      final tax = side == OrderSide.sell
          ? executionPrice * quantity * AppConstants.taxRate
          : 0.0;

      final order = Order(
        id: orderId,
        stockCode: stockCode,
        stockName: stockName,
        type: OrderType.limit,
        side: side,
        price: limitPrice,
        quantity: quantity,
        filledQuantity: quantity,
        status: OrderStatus.filled,
        createdAt: now,
        filledAt: now,
      );

      final tradeLog = TradeLog(
        id: _uuid.v4(),
        orderId: orderId,
        stockCode: stockCode,
        stockName: stockName,
        side: side,
        price: executionPrice,
        quantity: quantity,
        fee: fee,
        tax: tax,
        executedAt: now,
      );

      return TradeResult.success(order: order, tradeLog: tradeLog);
    }

    // 미체결 - 대기 주문으로 등록
    final order = Order(
      id: orderId,
      stockCode: stockCode,
      stockName: stockName,
      type: OrderType.limit,
      side: side,
      price: limitPrice,
      quantity: quantity,
      status: OrderStatus.pending,
      createdAt: now,
    );

    _pendingOrders.add(order);
    return TradeResult.pending(order: order);
  }

  /// 손절/익절 주문 등록 (보유 종목에 대해 자동 매도)
  TradeResult placeStopOrder({
    required String stockCode,
    required String stockName,
    required OrderType type, // stopLoss or takeProfit
    required double triggerPrice,
    required double quantity,
    required double currentHolding,
  }) {
    if (quantity > currentHolding) {
      return TradeResult.failure('보유 수량이 부족합니다.');
    }

    final orderId = _uuid.v4();
    final now = DateTime.now();

    final order = Order(
      id: orderId,
      stockCode: stockCode,
      stockName: stockName,
      type: type,
      side: OrderSide.sell,
      price: triggerPrice,
      quantity: quantity,
      status: OrderStatus.pending,
      createdAt: now,
    );

    _pendingOrders.add(order);
    return TradeResult.pending(order: order);
  }

  /// 미체결 주문을 현재 시세와 비교하여 체결 처리
  /// [isMarketOpen] 종목 코드를 받아 해당 시장이 열려있는지 반환하는 함수
  List<TradeResult> checkPendingOrders({
    required bool Function(String stockCode) isMarketOpen,
  }) {
    final results = <TradeResult>[];
    final toRemove = <int>[];

    for (var i = 0; i < _pendingOrders.length; i++) {
      final order = _pendingOrders[i];

      // 해당 종목 시장이 마감된 경우 체결 스킵
      if (!isMarketOpen(order.stockCode)) continue;

      final price = _mockDataService.getPrice(order.stockCode);
      if (price == null) continue;

      bool canFill;
      if (order.type == OrderType.stopLoss) {
        // 손절: 현재가가 손절가 이하로 떨어지면 체결
        canFill = price.currentPrice <= order.price;
      } else if (order.type == OrderType.takeProfit) {
        // 익절: 현재가가 익절가 이상으로 오르면 체결
        canFill = price.currentPrice >= order.price;
      } else {
        // 일반 지정가
        canFill = order.side == OrderSide.buy
            ? order.price >= price.currentPrice
            : order.price <= price.currentPrice;
      }

      if (canFill) {
        final now = DateTime.now();
        final executionPrice = price.currentPrice;
        final fee =
            executionPrice * order.quantity * AppConstants.tradingFeeRate;
        final tax = order.side == OrderSide.sell
            ? executionPrice * order.quantity * AppConstants.taxRate
            : 0.0;

        final filledOrder = order.copyWith(
          filledQuantity: order.quantity,
          status: OrderStatus.filled,
          filledAt: now,
        );

        final tradeLog = TradeLog(
          id: _uuid.v4(),
          orderId: order.id,
          stockCode: order.stockCode,
          stockName: order.stockName,
          side: order.side,
          price: executionPrice,
          quantity: order.quantity,
          fee: fee,
          tax: tax,
          executedAt: now,
        );

        results.add(TradeResult.success(order: filledOrder, tradeLog: tradeLog));
        toRemove.add(i);
      }
    }

    // 체결된 주문 제거 (역순으로)
    for (final i in toRemove.reversed) {
      _pendingOrders.removeAt(i);
    }

    return results;
  }

  /// 주문 취소
  Order? cancelOrder(String orderId) {
    final index = _pendingOrders.indexWhere((o) => o.id == orderId);
    if (index >= 0) {
      final order = _pendingOrders.removeAt(index);
      return order.copyWith(status: OrderStatus.cancelled);
    }
    return null;
  }

  List<Order> get pendingOrders => List.unmodifiable(_pendingOrders);
}

/// 주문 결과
class TradeResult {
  final bool isSuccess;
  final bool isPending;
  final String? errorMessage;
  final Order? order;
  final TradeLog? tradeLog;

  const TradeResult._({
    required this.isSuccess,
    this.isPending = false,
    this.errorMessage,
    this.order,
    this.tradeLog,
  });

  factory TradeResult.success({
    required Order order,
    required TradeLog tradeLog,
  }) =>
      TradeResult._(isSuccess: true, order: order, tradeLog: tradeLog);

  factory TradeResult.pending({required Order order}) =>
      TradeResult._(isSuccess: true, isPending: true, order: order);

  factory TradeResult.failure(String message) =>
      TradeResult._(isSuccess: false, errorMessage: message);
}
