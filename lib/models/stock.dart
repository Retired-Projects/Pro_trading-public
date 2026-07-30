/// 종목 기본 정보
class Stock {
  final String code;
  final String name;
  final double basePrice; // 기준가 (전일 종가)

  const Stock({
    required this.code,
    required this.name,
    required this.basePrice,
  });

  Map<String, dynamic> toJson() => {
        'code': code,
        'name': name,
        'base_price': basePrice,
      };

  factory Stock.fromJson(Map<String, dynamic> json) => Stock(
        code: json['code'] as String,
        name: json['name'] as String,
        basePrice: (json['base_price'] as num).toDouble(),
      );
}

/// 실시간 시세 데이터
class StockPrice {
  final String stockCode;
  final double currentPrice;
  final double openPrice;
  final double highPrice;
  final double lowPrice;
  final double previousClose;
  final int volume;
  final DateTime timestamp;

  const StockPrice({
    required this.stockCode,
    required this.currentPrice,
    required this.openPrice,
    required this.highPrice,
    required this.lowPrice,
    required this.previousClose,
    required this.volume,
    required this.timestamp,
  });

  double get changeAmount => currentPrice - previousClose;
  double get changeRate => previousClose != 0
      ? ((currentPrice - previousClose) / previousClose) * 100
      : 0;
  bool get isUp => changeAmount > 0;
  bool get isDown => changeAmount < 0;

  Map<String, dynamic> toJson() => {
        'stock_code': stockCode,
        'current_price': currentPrice,
        'open_price': openPrice,
        'high_price': highPrice,
        'low_price': lowPrice,
        'previous_close': previousClose,
        'volume': volume,
        'timestamp': timestamp.toIso8601String(),
      };

  factory StockPrice.fromJson(Map<String, dynamic> json) => StockPrice(
        stockCode: json['stock_code'] as String,
        currentPrice: (json['current_price'] as num).toDouble(),
        openPrice: (json['open_price'] as num).toDouble(),
        highPrice: (json['high_price'] as num).toDouble(),
        lowPrice: (json['low_price'] as num).toDouble(),
        previousClose: (json['previous_close'] as num).toDouble(),
        volume: json['volume'] as int,
        timestamp: DateTime.parse(json['timestamp'] as String),
      );

  StockPrice copyWith({
    double? currentPrice,
    double? highPrice,
    double? lowPrice,
    int? volume,
    DateTime? timestamp,
  }) =>
      StockPrice(
        stockCode: stockCode,
        currentPrice: currentPrice ?? this.currentPrice,
        openPrice: openPrice,
        highPrice: highPrice ?? this.highPrice,
        lowPrice: lowPrice ?? this.lowPrice,
        previousClose: previousClose,
        volume: volume ?? this.volume,
        timestamp: timestamp ?? this.timestamp,
      );
}

/// 캔들 데이터 (차트용)
class CandleData {
  final DateTime timestamp;
  final double open;
  final double high;
  final double low;
  final double close;
  final int volume;

  const CandleData({
    required this.timestamp,
    required this.open,
    required this.high,
    required this.low,
    required this.close,
    required this.volume,
  });

  bool get isBullish => close >= open;
}

/// 호가 데이터
class OrderBookEntry {
  final double price;
  final int quantity;

  const OrderBookEntry({
    required this.price,
    required this.quantity,
  });
}

class OrderBook {
  final String stockCode;
  final List<OrderBookEntry> asks; // 매도 호가 (위에서 아래로, 높은 가격→낮은 가격)
  final List<OrderBookEntry> bids; // 매수 호가 (위에서 아래로, 높은 가격→낮은 가격)

  const OrderBook({
    required this.stockCode,
    required this.asks,
    required this.bids,
  });
}
