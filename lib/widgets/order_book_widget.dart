import 'dart:math';
import 'package:flame/game.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';
import '../models/stock.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/formatters.dart';

/// Flame 기반 호가창 컴포넌트
/// - 60FPS 렌더링으로 부드러운 잔량 바 애니메이션
/// - 0.5초 숫자 보간 (스무딩)
/// - 체결 시 하이라이트 효과
class OrderBookGame extends FlameGame with TapCallbacks {
  OrderBook? _orderBook;
  OrderBook? _targetOrderBook;
  double _currentPrice = 0;
  double _previousClose = 0;
  ValueChanged<double>? onPriceTap;

  // 보간용 상태
  final List<double> _askQuantities = [];
  final List<double> _bidQuantities = [];
  final List<double> _targetAskQuantities = [];
  final List<double> _targetBidQuantities = [];

  // 하이라이트 효과
  final Map<int, double> _flashAlpha = {};

  static const double _smoothSpeed = 4.0; // 보간 속도 (높을수록 빠름)

  void updateOrderBook(OrderBook orderBook, double currentPrice, double previousClose) {
    _previousClose = previousClose;

    // 가격 변동 시 플래시 효과
    if (_currentPrice != 0 && _currentPrice != currentPrice) {
      _flashAlpha[-1] = 1.0; // 현재가 라인 플래시
    }
    _currentPrice = currentPrice;

    _targetOrderBook = orderBook;

    // 타겟 잔량 설정
    _targetAskQuantities.clear();
    _targetBidQuantities.clear();
    for (final ask in orderBook.asks) {
      _targetAskQuantities.add(ask.quantity.toDouble());
    }
    for (final bid in orderBook.bids) {
      _targetBidQuantities.add(bid.quantity.toDouble());
    }

    // 최초 설정 시 즉시 반영
    if (_askQuantities.isEmpty) {
      _askQuantities.addAll(_targetAskQuantities);
      _bidQuantities.addAll(_targetBidQuantities);
      _orderBook = orderBook;
    }
  }

  @override
  Color backgroundColor() => AppColors.background;

  @override
  void update(double dt) {
    super.update(dt);

    // 잔량 보간 (스무딩)
    _interpolateList(_askQuantities, _targetAskQuantities, dt);
    _interpolateList(_bidQuantities, _targetBidQuantities, dt);

    // 플래시 감쇠
    final keysToRemove = <int>[];
    for (final entry in _flashAlpha.entries) {
      _flashAlpha[entry.key] = max(0, entry.value - dt * 3);
      if (_flashAlpha[entry.key]! <= 0) keysToRemove.add(entry.key);
    }
    for (final key in keysToRemove) {
      _flashAlpha.remove(key);
    }

    if (_targetOrderBook != null) {
      _orderBook = _targetOrderBook;
    }
  }

  void _interpolateList(List<double> current, List<double> target, double dt) {
    // 리스트 크기 맞추기
    while (current.length < target.length) {
      current.add(target[current.length]);
    }
    while (current.length > target.length) {
      current.removeLast();
    }

    for (var i = 0; i < current.length; i++) {
      final diff = target[i] - current[i];
      current[i] += diff * min(1.0, _smoothSpeed * dt);
    }
  }

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    if (_orderBook == null) {
      _drawLoading(canvas);
      return;
    }

    final ob = _orderBook!;
    final depth = ob.asks.length;
    final totalRows = depth * 2 + 1; // 매도 + 현재가 + 매수
    final rowHeight = size.y / totalRows;

    final maxQty = _getMaxQuantity();

    // ── 매도 호가 (위) ──
    for (var i = 0; i < depth; i++) {
      final y = rowHeight * i;
      final ask = ob.asks[i];
      final qty = i < _askQuantities.length ? _askQuantities[i] : ask.quantity.toDouble();
      _drawRow(canvas, y, rowHeight, ask.price, qty, maxQty, isAsk: true, index: i);
    }

    // ── 현재가 라인 (중앙) ──
    final centerY = rowHeight * depth;
    _drawCurrentPriceLine(canvas, centerY, rowHeight);

    // ── 매수 호가 (아래) ──
    for (var i = 0; i < depth; i++) {
      final y = rowHeight * (depth + 1 + i);
      final bid = ob.bids[i];
      final qty = i < _bidQuantities.length ? _bidQuantities[i] : bid.quantity.toDouble();
      _drawRow(canvas, y, rowHeight, bid.price, qty, maxQty, isAsk: false, index: i);
    }
  }

  void _drawRow(Canvas canvas, double y, double h, double price,
      double quantity, double maxQty,
      {required bool isAsk, required int index}) {
    final barRatio = maxQty > 0 ? quantity / maxQty : 0.0;
    final changeRate = _previousClose != 0
        ? ((price - _previousClose) / _previousClose) * 100
        : 0.0;

    // 배경 (매도=블루, 매수=레드)
    final bgColor = isAsk
        ? AppColors.priceDown.withValues(alpha: 0.05)
        : AppColors.priceUp.withValues(alpha: 0.05);
    canvas.drawRect(Rect.fromLTWH(0, y, size.x, h), Paint()..color = bgColor);

    // 플래시 효과
    final flashKey = isAsk ? index : index + 100;
    final flash = _flashAlpha[flashKey] ?? 0;
    if (flash > 0) {
      final flashColor = (isAsk ? AppColors.priceDown : AppColors.priceUp)
          .withValues(alpha: flash * 0.3);
      canvas.drawRect(
          Rect.fromLTWH(0, y, size.x, h), Paint()..color = flashColor);
    }

    // 잔량 바
    final barColor = isAsk ? AppColors.orderBookAsk : AppColors.orderBookBid;
    if (isAsk) {
      // 매도: 오른쪽에서 왼쪽으로
      final barWidth = (size.x * 0.35) * barRatio;
      canvas.drawRect(
        Rect.fromLTWH(size.x * 0.02, y + 2, barWidth, h - 4),
        Paint()..color = barColor,
      );
    } else {
      // 매수: 왼쪽에서 오른쪽으로
      final barWidth = (size.x * 0.35) * barRatio;
      canvas.drawRect(
        Rect.fromLTWH(size.x * 0.63, y + 2, barWidth, h - 4),
        Paint()..color = barColor,
      );
    }

    // 잔량 텍스트
    final qtyText = TextPainter(
      text: TextSpan(
        text: Formatters.volume(quantity.round()),
        style: TextStyle(
          color: isAsk ? AppColors.priceDown : AppColors.priceUp,
          fontSize: 12,
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    if (isAsk) {
      qtyText.paint(canvas, Offset(size.x * 0.05, y + (h - qtyText.height) / 2));
    } else {
      qtyText.paint(canvas, Offset(size.x * 0.65, y + (h - qtyText.height) / 2));
    }

    // 가격 텍스트 (중앙)
    final priceColor = price > _previousClose
        ? AppColors.priceUp
        : price < _previousClose
            ? AppColors.priceDown
            : AppColors.priceNeutral;

    final priceText = TextPainter(
      text: TextSpan(
        text: Formatters.price(price),
        style: TextStyle(
          color: priceColor,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    priceText.paint(
        canvas, Offset((size.x - priceText.width) / 2, y + (h - priceText.height) / 2 - 6));

    // 등락률 텍스트
    final rateText = TextPainter(
      text: TextSpan(
        text: Formatters.percent(changeRate),
        style: TextStyle(
          color: priceColor.withValues(alpha: 0.6),
          fontSize: 9,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    rateText.paint(
        canvas, Offset((size.x - rateText.width) / 2, y + (h - rateText.height) / 2 + 8));

    // 구분선
    canvas.drawLine(
      Offset(0, y + h),
      Offset(size.x, y + h),
      Paint()
        ..color = AppColors.divider.withValues(alpha: 0.3)
        ..strokeWidth = 0.5,
    );
  }

  void _drawCurrentPriceLine(Canvas canvas, double y, double h) {
    // 배경
    canvas.drawRect(
      Rect.fromLTWH(0, y, size.x, h),
      Paint()..color = AppColors.surfaceLight,
    );

    // 플래시 효과
    final flash = _flashAlpha[-1] ?? 0;
    if (flash > 0) {
      canvas.drawRect(
        Rect.fromLTWH(0, y, size.x, h),
        Paint()..color = AppColors.primary.withValues(alpha: flash * 0.3),
      );
    }

    final change = _currentPrice - _previousClose;
    final changeRate = _previousClose != 0
        ? (change / _previousClose) * 100
        : 0.0;
    final isUp = change > 0;
    final color = isUp ? AppColors.priceUp : AppColors.priceDown;

    // 현재가
    final priceText = TextPainter(
      text: TextSpan(
        text: Formatters.price(_currentPrice),
        style: TextStyle(color: color, fontSize: 16, fontWeight: FontWeight.bold),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    // 등락
    final changeText = TextPainter(
      text: TextSpan(
        text: '${isUp ? "▲" : "▼"} ${Formatters.change(change)} (${Formatters.percent(changeRate)})',
        style: TextStyle(color: color, fontSize: 11),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final totalWidth = priceText.width + 8 + changeText.width;
    final startX = (size.x - totalWidth) / 2;

    priceText.paint(canvas, Offset(startX, y + (h - priceText.height) / 2));
    changeText.paint(canvas,
        Offset(startX + priceText.width + 8, y + (h - changeText.height) / 2));
  }

  void _drawLoading(Canvas canvas) {
    final text = TextPainter(
      text: TextSpan(
        text: '호가 데이터 로딩 중...',
        style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    text.paint(canvas,
        Offset((size.x - text.width) / 2, (size.y - text.height) / 2));
  }

  double _getMaxQuantity() {
    double maxQ = 0;
    for (final q in _askQuantities) {
      if (q > maxQ) maxQ = q;
    }
    for (final q in _bidQuantities) {
      if (q > maxQ) maxQ = q;
    }
    return maxQ;
  }

  @override
  void onTapUp(TapUpEvent event) {
    if (_orderBook == null || onPriceTap == null) return;

    final ob = _orderBook!;
    final depth = ob.asks.length;
    final totalRows = depth * 2 + 1;
    final rowHeight = size.y / totalRows;
    final tapY = event.localPosition.y;
    final rowIndex = (tapY / rowHeight).floor();

    if (rowIndex < depth) {
      // 매도 호가 탭
      onPriceTap!(ob.asks[rowIndex].price);
    } else if (rowIndex > depth && rowIndex < totalRows) {
      // 매수 호가 탭
      onPriceTap!(ob.bids[rowIndex - depth - 1].price);
    }
  }
}

/// Flutter 위젯 래퍼
class OrderBookWidget extends StatefulWidget {
  final OrderBook orderBook;
  final double currentPrice;
  final double previousClose;
  final ValueChanged<double>? onPriceTap;

  const OrderBookWidget({
    super.key,
    required this.orderBook,
    required this.currentPrice,
    required this.previousClose,
    this.onPriceTap,
  });

  @override
  State<OrderBookWidget> createState() => _OrderBookWidgetState();
}

class _OrderBookWidgetState extends State<OrderBookWidget> {
  late final OrderBookGame _game;

  @override
  void initState() {
    super.initState();
    _game = OrderBookGame();
    _game.onPriceTap = widget.onPriceTap;
    _game.updateOrderBook(
        widget.orderBook, widget.currentPrice, widget.previousClose);
  }

  @override
  void didUpdateWidget(OrderBookWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    _game.onPriceTap = widget.onPriceTap;
    _game.updateOrderBook(
        widget.orderBook, widget.currentPrice, widget.previousClose);
  }

  @override
  Widget build(BuildContext context) {
    return GameWidget(game: _game);
  }
}
