enum OrderType { market, limit, stopLoss, takeProfit }

enum OrderSide { buy, sell }

enum OrderStatus { pending, filled, partiallyFilled, cancelled }

/// 주문
class Order {
  final String id;
  final String stockCode;
  final String stockName;
  final OrderType type;
  final OrderSide side;
  final double price; // 주문 가격 (시장가일 경우 0)
  final double quantity;
  final double filledQuantity;
  final OrderStatus status;
  final DateTime createdAt;
  final DateTime? filledAt;

  const Order({
    required this.id,
    required this.stockCode,
    required this.stockName,
    required this.type,
    required this.side,
    required this.price,
    required this.quantity,
    this.filledQuantity = 0,
    this.status = OrderStatus.pending,
    required this.createdAt,
    this.filledAt,
  });

  double get remainingQuantity => quantity - filledQuantity;
  bool get isFilled => status == OrderStatus.filled;
  bool get isPending => status == OrderStatus.pending;

  Order copyWith({
    double? filledQuantity,
    OrderStatus? status,
    DateTime? filledAt,
  }) =>
      Order(
        id: id,
        stockCode: stockCode,
        stockName: stockName,
        type: type,
        side: side,
        price: price,
        quantity: quantity,
        filledQuantity: filledQuantity ?? this.filledQuantity,
        status: status ?? this.status,
        createdAt: createdAt,
        filledAt: filledAt ?? this.filledAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'stock_code': stockCode,
        'stock_name': stockName,
        'type': type.name,
        'side': side.name,
        'price': price,
        'quantity': quantity,
        'filled_quantity': filledQuantity,
        'status': status.name,
        'created_at': createdAt.toIso8601String(),
        'filled_at': filledAt?.toIso8601String(),
      };

  factory Order.fromJson(Map<String, dynamic> json) => Order(
        id: json['id'] as String,
        stockCode: json['stock_code'] as String,
        stockName: json['stock_name'] as String,
        type: OrderType.values.byName(json['type'] as String),
        side: OrderSide.values.byName(json['side'] as String),
        price: (json['price'] as num).toDouble(),
        quantity: (json['quantity'] as num).toDouble(),
        filledQuantity: (json['filled_quantity'] as num?)?.toDouble() ?? 0,
        status: OrderStatus.values.byName(json['status'] as String),
        createdAt: DateTime.parse(json['created_at'] as String),
        filledAt: json['filled_at'] != null
            ? DateTime.parse(json['filled_at'] as String)
            : null,
      );
}

/// 체결 이력
class TradeLog {
  final String id;
  final String orderId;
  final String stockCode;
  final String stockName;
  final OrderSide side;
  final double price;
  final double quantity;
  final double fee;
  final double tax;
  final DateTime executedAt;

  const TradeLog({
    required this.id,
    required this.orderId,
    required this.stockCode,
    required this.stockName,
    required this.side,
    required this.price,
    required this.quantity,
    required this.fee,
    required this.tax,
    required this.executedAt,
  });

  /// 총 거래 금액
  double get totalAmount => price * quantity;

  /// 실제 결제/수령 금액
  double get netAmount {
    if (side == OrderSide.buy) {
      return totalAmount + fee;
    } else {
      return totalAmount - fee - tax;
    }
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'order_id': orderId,
        'stock_code': stockCode,
        'stock_name': stockName,
        'side': side.name,
        'price': price,
        'quantity': quantity,
        'fee': fee,
        'tax': tax,
        'executed_at': executedAt.toIso8601String(),
      };

  factory TradeLog.fromJson(Map<String, dynamic> json) => TradeLog(
        id: json['id'] as String,
        orderId: json['order_id'] as String,
        stockCode: json['stock_code'] as String,
        stockName: json['stock_name'] as String,
        side: OrderSide.values.byName(json['side'] as String),
        price: (json['price'] as num).toDouble(),
        quantity: (json['quantity'] as num).toDouble(),
        fee: (json['fee'] as num).toDouble(),
        tax: (json['tax'] as num).toDouble(),
        executedAt: DateTime.parse(json['executed_at'] as String),
      );
}
