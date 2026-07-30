/// 보유 종목
class Holding {
  final String stockCode;
  final String stockName;
  final double quantity;
  final double avgPrice; // 평균 매수 단가
  final double currentPrice;

  const Holding({
    required this.stockCode,
    required this.stockName,
    required this.quantity,
    required this.avgPrice,
    required this.currentPrice,
  });

  /// 매입 금액
  double get totalCost => avgPrice * quantity;

  /// 평가 금액
  double get totalValue => currentPrice * quantity;

  /// 평가 손익
  double get pnl => totalValue - totalCost;

  /// 수익률 (%)
  double get pnlRate => totalCost != 0 ? (pnl / totalCost) * 100 : 0;

  bool get isProfit => pnl > 0;
  bool get isLoss => pnl < 0;

  Holding copyWith({
    double? quantity,
    double? avgPrice,
    double? currentPrice,
  }) =>
      Holding(
        stockCode: stockCode,
        stockName: stockName,
        quantity: quantity ?? this.quantity,
        avgPrice: avgPrice ?? this.avgPrice,
        currentPrice: currentPrice ?? this.currentPrice,
      );

  Map<String, dynamic> toJson() => {
        'stock_code': stockCode,
        'stock_name': stockName,
        'quantity': quantity,
        'avg_price': avgPrice,
        'current_price': currentPrice,
      };

  factory Holding.fromJson(Map<String, dynamic> json) => Holding(
        stockCode: json['stock_code'] as String,
        stockName: json['stock_name'] as String,
        quantity: (json['quantity'] as num).toDouble(),
        avgPrice: (json['avg_price'] as num).toDouble(),
        currentPrice: (json['current_price'] as num?)?.toDouble() ??
            (json['avg_price'] as num).toDouble(),
      );
}

/// 사용자 포트폴리오 전체
class Portfolio {
  final double balance; // 예수금
  final double reservedBalance; // 미체결 주문으로 묶인 금액
  final List<Holding> holdings;

  const Portfolio({
    required this.balance,
    this.reservedBalance = 0,
    required this.holdings,
  });

  /// 가용 예수금 (전체 예수금 - 주문 중 금액)
  double get availableBalance => balance - reservedBalance;

  /// 총 평가 금액
  double get totalEvaluation =>
      holdings.fold(0.0, (sum, h) => sum + h.totalValue);

  /// 총 자산 (예수금 + 평가금)
  double get totalAsset => balance + totalEvaluation;

  /// 총 매입 금액
  double get totalCost => holdings.fold(0.0, (sum, h) => sum + h.totalCost);

  /// 총 평가 손익
  double get totalPnl => totalEvaluation - totalCost;

  /// 총 수익률
  double get totalPnlRate => totalCost != 0 ? (totalPnl / totalCost) * 100 : 0;

  Portfolio copyWith({
    double? balance,
    double? reservedBalance,
    List<Holding>? holdings,
  }) =>
      Portfolio(
        balance: balance ?? this.balance,
        reservedBalance: reservedBalance ?? this.reservedBalance,
        holdings: holdings ?? this.holdings,
      );
}

