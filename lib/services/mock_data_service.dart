import 'dart:math';
import '../models/stock.dart';
import '../core/constants/app_constants.dart';

/// 가상 데이터 서비스
/// - 실제 API 데이터가 없을 때 폴백으로 가상 시세 생성
/// - 실제 가격 기반으로 합성 호가창 생성
/// - 호가 잔량 미세 진동 (마이크로 틱)
class MockDataService {
  final _random = Random();
  final Map<String, double> _realPrices = {};
  final Map<String, String> _stockNames = {};
  final Map<String, StockPrice> _prices = {};
  final Map<String, List<CandleData>> _candles = {};
  final Map<String, OrderBook> _orderBooks = {};

  /// 종목 등록 (동적으로 추가)
  void registerStock(String code, String name, {double? price}) {
    _stockNames[code] = name;
    if (price != null) _realPrices[code] = price;
    if (!_prices.containsKey(code)) {
      final p = price ?? 100000;
      _prices[code] = StockPrice(
        stockCode: code,
        currentPrice: p,
        openPrice: p,
        highPrice: p,
        lowPrice: p,
        previousClose: p,
        volume: 0,
        timestamp: DateTime.now(),
      );
      _candles[code] = [];
    }
  }

  /// 실제 API 가격으로 업데이트 (TradingEngine에서도 사용 가능하도록 _prices도 동기화)
  void updateWithRealPrice(String stockCode, double price) {
    _realPrices[stockCode] = price;
    final existing = _prices[stockCode];
    if (existing != null) {
      _prices[stockCode] = existing.copyWith(
        currentPrice: price,
        timestamp: DateTime.now(),
      );
    } else {
      _prices[stockCode] = StockPrice(
        stockCode: stockCode,
        currentPrice: price,
        openPrice: price,
        highPrice: price,
        lowPrice: price,
        previousClose: price,
        volume: 0,
        timestamp: DateTime.now(),
      );
    }
  }

  /// mock 시세 업데이트 (API 실패 시 폴백)
  Map<String, StockPrice> updatePrices() {
    for (final entry in _prices.entries) {
      final prev = entry.value;
      final change = _generatePriceChange(prev.currentPrice);
      final newPrice = prev.currentPrice + change;

      _prices[entry.key] = prev.copyWith(
        currentPrice: newPrice,
        highPrice: max(prev.highPrice, newPrice),
        lowPrice: min(prev.lowPrice, newPrice),
        volume: prev.volume + _random.nextInt(10000) + 100,
        timestamp: DateTime.now(),
      );
    }
    return Map.unmodifiable(_prices);
  }

  StockPrice? getPrice(String stockCode) => _prices[stockCode];

  List<CandleData> getCandles(String stockCode) =>
      List.unmodifiable(_candles[stockCode] ?? []);

  /// 캔들 데이터 설정 (API에서 가져온 데이터)
  void setCandles(String stockCode, List<CandleData> candles) {
    _candles[stockCode] = List.from(candles);
  }

  /// 실제 가격 기반 합성 호가창 생성
  OrderBook getOrderBook(String stockCode) {
    final currentPrice = _realPrices[stockCode] ?? 100000;
    final tickSize = _getTickSize(currentPrice);
    final depth = AppConstants.orderBookDepth;

    // 매도 호가 (현재가 위로 5단계, 높은 가격 → 낮은 가격)
    final asks = List.generate(depth, (i) {
      final price = currentPrice + tickSize * (depth - i);
      // 현재가에 가까울수록 잔량이 많은 경향
      final baseQty = 500 + _random.nextInt(3000);
      final proximityBonus = (depth - i) < 2 ? _random.nextInt(2000) : 0;
      return OrderBookEntry(
        price: price,
        quantity: baseQty + proximityBonus,
      );
    });

    // 매수 호가 (현재가 아래로 5단계, 높은 가격 → 낮은 가격)
    final bids = List.generate(depth, (i) {
      final price = currentPrice - tickSize * (i + 1);
      final baseQty = 500 + _random.nextInt(3000);
      final proximityBonus = i < 2 ? _random.nextInt(2000) : 0;
      return OrderBookEntry(
        price: price,
        quantity: baseQty + proximityBonus,
      );
    });

    _orderBooks[stockCode] =
        OrderBook(stockCode: stockCode, asks: asks, bids: bids);
    return _orderBooks[stockCode]!;
  }

  /// 호가 잔량 미세 진동 (±1~2%, 살아있는 시장 느낌)
  OrderBook? vibrateOrderBook(String stockCode, Random random) {
    final existing = _orderBooks[stockCode];
    if (existing == null) return null;

    final newAsks = existing.asks.map((e) {
      final change = e.quantity * (random.nextDouble() * 0.04 - 0.02);
      return OrderBookEntry(
        price: e.price,
        quantity: max(10, e.quantity + change.round()),
      );
    }).toList();

    final newBids = existing.bids.map((e) {
      final change = e.quantity * (random.nextDouble() * 0.04 - 0.02);
      return OrderBookEntry(
        price: e.price,
        quantity: max(10, e.quantity + change.round()),
      );
    }).toList();

    _orderBooks[stockCode] =
        OrderBook(stockCode: stockCode, asks: newAsks, bids: newBids);
    return _orderBooks[stockCode]!;
  }

  double _generatePriceChange(double currentPrice) {
    return (_random.nextDouble() * 2 - 1) * currentPrice * 0.005;
  }

  /// 호가 단위 (한국 주식시장 기준)
  double _getTickSize(double price) {
    if (price < 2000) return 1;
    if (price < 5000) return 5;
    if (price < 20000) return 10;
    if (price < 50000) return 50;
    if (price < 200000) return 100;
    if (price < 500000) return 500;
    return 1000;
  }
}
