import 'dart:math';
import 'package:flame/game.dart';
import 'package:flame/events.dart';
import 'package:flutter/material.dart';
import '../models/stock.dart';
import '../core/theme/app_colors.dart';

/// Flame 기반 고급 캔들 차트 컴포넌트
/// - 캔들스틱 + 거래량 바 + 이동평균선(MA5/MA20) + 크로스헤어
class CandleChartGame extends FlameGame with ScaleDetector, PanDetector {
  List<CandleData> _candles = [];
  double _scrollOffset = 0;
  double _scale = 1.0;

  // 크로스헤어
  double? _crosshairX;
  double? _crosshairY;
  int? _crosshairIndex;

  // 차트 영역 패딩
  static const double _topPadding = 16;
  static const double _bottomPadding = 24;
  static const double _rightPadding = 70;
  static const double _leftPadding = 10;
  static const double _volumeRatio = 0.18; // 하단 18%를 거래량 영역으로

  void updateCandles(List<CandleData> candles) {
    _candles = candles;
  }

  @override
  Color backgroundColor() => AppColors.background;

  @override
  void render(Canvas canvas) {
    super.render(canvas);
    if (_candles.isEmpty) {
      _drawEmptyState(canvas);
      return;
    }

    final chartWidth = size.x - _leftPadding - _rightPadding;
    final totalHeight = size.y - _topPadding - _bottomPadding;
    final candleChartHeight = totalHeight * (1 - _volumeRatio);
    final volumeTop = _topPadding + candleChartHeight + 4;
    final volumeHeight = totalHeight * _volumeRatio - 4;

    // 가격 범위 계산
    double minPrice = double.infinity;
    double maxPrice = double.negativeInfinity;
    int maxVolume = 0;
    for (final candle in _candles) {
      minPrice = min(minPrice, candle.low);
      maxPrice = max(maxPrice, candle.high);
      maxVolume = max(maxVolume, candle.volume);
    }
    final priceRange = maxPrice - minPrice;
    final padding = priceRange * 0.08;
    minPrice -= padding;
    maxPrice += padding;
    if (maxVolume == 0) maxVolume = 1;

    final candleWidth = (chartWidth / _candles.length) * _scale;
    final bodyWidth = candleWidth * 0.6;

    // 가격→Y 변환
    double priceToY(double price) {
      return _topPadding +
          candleChartHeight * (1 - (price - minPrice) / (maxPrice - minPrice));
    }

    // 그리드
    _drawGrid(canvas, candleChartHeight, minPrice, maxPrice);

    // 이동평균선 (MA5, MA20)
    _drawMovingAverage(canvas, 5, Colors.orange, candleWidth, priceToY);
    _drawMovingAverage(canvas, 20, Colors.cyan, candleWidth, priceToY);

    // 캔들 + 거래량
    for (var i = 0; i < _candles.length; i++) {
      final candle = _candles[i];
      final x = _leftPadding + i * candleWidth + _scrollOffset;

      if (x < _leftPadding - candleWidth || x > size.x - _rightPadding) {
        continue;
      }

      final color = candle.isBullish ? AppColors.priceUp : AppColors.priceDown;
      final paint = Paint()..color = color;
      final wickPaint = Paint()
        ..color = color
        ..strokeWidth = 1.5;

      final openY = priceToY(candle.open);
      final closeY = priceToY(candle.close);
      final highY = priceToY(candle.high);
      final lowY = priceToY(candle.low);
      final centerX = x + candleWidth / 2;

      // 꼬리 (wick)
      canvas.drawLine(Offset(centerX, highY), Offset(centerX, lowY), wickPaint);

      // 몸통 (body)
      final bodyTop = min(openY, closeY);
      final bodyBottom = max(openY, closeY);
      final bodyHeight = max(bodyBottom - bodyTop, 1.0);

      if (candle.isBullish) {
        final borderPaint = Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5;
        canvas.drawRect(
          Rect.fromLTWH(centerX - bodyWidth / 2, bodyTop, bodyWidth, bodyHeight),
          borderPaint,
        );
        canvas.drawRect(
          Rect.fromLTWH(centerX - bodyWidth / 2, bodyTop, bodyWidth, bodyHeight),
          Paint()..color = color.withValues(alpha: 0.3),
        );
      } else {
        canvas.drawRect(
          Rect.fromLTWH(centerX - bodyWidth / 2, bodyTop, bodyWidth, bodyHeight),
          paint,
        );
      }

      // 거래량 바
      if (candle.volume > 0) {
        final volH = (candle.volume / maxVolume) * volumeHeight;
        final volPaint = Paint()..color = color.withValues(alpha: 0.4);
        canvas.drawRect(
          Rect.fromLTWH(
            centerX - bodyWidth / 2,
            volumeTop + volumeHeight - volH,
            bodyWidth,
            volH,
          ),
          volPaint,
        );
      }
    }

    // 현재가 라인
    if (_candles.isNotEmpty) {
      final lastPrice = _candles.last.close;
      final y = priceToY(lastPrice);
      _drawDashedLine(canvas, y);

      // 현재가 라벨
      final labelPaint = Paint()..color = AppColors.primary;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(size.x - _rightPadding + 2, y - 9, _rightPadding - 4, 18),
          const Radius.circular(3),
        ),
        labelPaint,
      );
      _drawText(canvas, _formatPrice(lastPrice), size.x - _rightPadding + 5, y - 6,
          fontSize: 9, color: Colors.black, bold: true);
    }

    // MA 범례
    _drawLegend(canvas);

    // 크로스헤어
    _drawCrosshair(canvas, candleWidth, priceToY, minPrice, maxPrice);

    // 거래량 구분선
    final sepPaint = Paint()
      ..color = AppColors.divider.withValues(alpha: 0.5)
      ..strokeWidth = 0.5;
    canvas.drawLine(
      Offset(_leftPadding, volumeTop - 2),
      Offset(size.x - _rightPadding, volumeTop - 2),
      sepPaint,
    );
  }

  /// 이동평균선 그리기
  void _drawMovingAverage(Canvas canvas, int period, Color color,
      double candleWidth, double Function(double) priceToY) {
    if (_candles.length < period) return;

    final paint = Paint()
      ..color = color.withValues(alpha: 0.8)
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    final path = Path();
    bool started = false;

    for (var i = period - 1; i < _candles.length; i++) {
      double sum = 0;
      for (var j = i - period + 1; j <= i; j++) {
        sum += _candles[j].close;
      }
      final ma = sum / period;
      final x = _leftPadding + i * candleWidth + _scrollOffset + candleWidth / 2;
      final y = priceToY(ma);

      if (x < _leftPadding || x > size.x - _rightPadding) continue;

      if (!started) {
        path.moveTo(x, y);
        started = true;
      } else {
        path.lineTo(x, y);
      }
    }

    canvas.drawPath(path, paint);
  }

  /// MA 범례
  void _drawLegend(Canvas canvas) {
    final y = 4.0;
    // MA5
    final ma5Paint = Paint()
      ..color = Colors.orange
      ..strokeWidth = 2;
    canvas.drawLine(Offset(_leftPadding, y + 5), Offset(_leftPadding + 14, y + 5), ma5Paint);
    _drawText(canvas, 'MA5', _leftPadding + 17, y, fontSize: 9, color: Colors.orange);

    // MA20
    final ma20Paint = Paint()
      ..color = Colors.cyan
      ..strokeWidth = 2;
    canvas.drawLine(Offset(_leftPadding + 52, y + 5), Offset(_leftPadding + 66, y + 5), ma20Paint);
    _drawText(canvas, 'MA20', _leftPadding + 69, y, fontSize: 9, color: Colors.cyan);

    // VOL
    _drawText(canvas, 'VOL', _leftPadding + 110, y, fontSize: 9, color: AppColors.textMuted);
  }

  /// 크로스헤어
  void _drawCrosshair(Canvas canvas, double candleWidth,
      double Function(double) priceToY, double minPrice, double maxPrice) {
    if (_crosshairX == null || _crosshairY == null) return;

    final dashPaint = Paint()
      ..color = AppColors.textSecondary.withValues(alpha: 0.6)
      ..strokeWidth = 0.5;

    // 수평선
    _drawDashedLineAt(canvas, _crosshairY!, _leftPadding, size.x - _rightPadding, dashPaint, horizontal: true);
    // 수직선
    _drawDashedLineAt(canvas, _crosshairX!, _topPadding, size.y - _bottomPadding, dashPaint, horizontal: false);

    // 가격 라벨
    if (_crosshairY! >= _topPadding && _crosshairY! <= _topPadding + (size.y - _topPadding - _bottomPadding) * (1 - _volumeRatio)) {
      final chartHeight = (size.y - _topPadding - _bottomPadding) * (1 - _volumeRatio);
      final price = maxPrice - ((_crosshairY! - _topPadding) / chartHeight) * (maxPrice - minPrice);
      final bgPaint = Paint()..color = AppColors.surfaceLight;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(size.x - _rightPadding + 2, _crosshairY! - 9, _rightPadding - 4, 18),
          const Radius.circular(3),
        ),
        bgPaint,
      );
      _drawText(canvas, _formatPrice(price), size.x - _rightPadding + 5, _crosshairY! - 6,
          fontSize: 9, color: AppColors.textPrimary);
    }

    // 선택된 캔들 정보
    if (_crosshairIndex != null && _crosshairIndex! < _candles.length) {
      final c = _candles[_crosshairIndex!];
      final info = 'O ${_formatPrice(c.open)}  H ${_formatPrice(c.high)}  L ${_formatPrice(c.low)}  C ${_formatPrice(c.close)}';
      final bgPaint = Paint()..color = AppColors.surface.withValues(alpha: 0.9);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(_leftPadding, _topPadding - 2, info.length * 5.5 + 10, 14),
          const Radius.circular(3),
        ),
        bgPaint,
      );
      _drawText(canvas, info, _leftPadding + 4, _topPadding - 1,
          fontSize: 8, color: AppColors.textSecondary);
    }
  }

  void _drawDashedLine(Canvas canvas, double y) {
    final dashPaint = Paint()
      ..color = AppColors.primary.withValues(alpha: 0.8)
      ..strokeWidth = 1;
    const dashWidth = 5.0;
    const dashSpace = 3.0;
    double startX = _leftPadding;
    while (startX < size.x - _rightPadding) {
      canvas.drawLine(
        Offset(startX, y),
        Offset(min(startX + dashWidth, size.x - _rightPadding), y),
        dashPaint,
      );
      startX += dashWidth + dashSpace;
    }
  }

  void _drawDashedLineAt(Canvas canvas, double pos, double start, double end,
      Paint paint, {required bool horizontal}) {
    const dash = 4.0;
    const space = 3.0;
    double cur = start;
    while (cur < end) {
      final to = min(cur + dash, end);
      if (horizontal) {
        canvas.drawLine(Offset(cur, pos), Offset(to, pos), paint);
      } else {
        canvas.drawLine(Offset(pos, cur), Offset(pos, to), paint);
      }
      cur += dash + space;
    }
  }

  void _drawGrid(Canvas canvas, double chartHeight, double minPrice, double maxPrice) {
    final gridPaint = Paint()
      ..color = AppColors.divider.withValues(alpha: 0.3)
      ..strokeWidth = 0.5;

    const gridLines = 5;
    final priceStep = (maxPrice - minPrice) / gridLines;

    for (var i = 0; i <= gridLines; i++) {
      final price = minPrice + priceStep * i;
      final y = _topPadding +
          chartHeight * (1 - (price - minPrice) / (maxPrice - minPrice));

      canvas.drawLine(
        Offset(_leftPadding, y),
        Offset(size.x - _rightPadding, y),
        gridPaint,
      );

      _drawText(canvas, _formatPrice(price), size.x - _rightPadding + 5, y - 6,
          fontSize: 10, color: AppColors.textMuted);
    }
  }

  void _drawEmptyState(Canvas canvas) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: '데이터 로딩 중...',
        style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(canvas,
        Offset((size.x - textPainter.width) / 2, (size.y - textPainter.height) / 2));
  }

  void _drawText(Canvas canvas, String text, double x, double y,
      {double fontSize = 10, Color? color, bool bold = false}) {
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color ?? AppColors.textMuted,
          fontSize: fontSize,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(canvas, Offset(x, y));
  }

  String _formatPrice(double price) {
    if (price >= 1000) return price.round().toString();
    if (price >= 1) return price.toStringAsFixed(1);
    return price.toStringAsFixed(4);
  }

  @override
  void onScaleUpdate(ScaleUpdateInfo info) {
    _scale = (_scale * info.scale.global.x).clamp(0.5, 3.0);
  }

  @override
  void onPanUpdate(DragUpdateInfo info) {
    final dx = info.delta.global.x;
    final dy = info.delta.global.y;

    // 주로 수평 이동이면 스크롤, 아니면 크로스헤어
    if (dx.abs() > dy.abs() + 2) {
      _scrollOffset += dx;
      _crosshairX = null;
      _crosshairY = null;
      _crosshairIndex = null;
    }
  }

  @override
  void onPanEnd(DragEndInfo info) {
    _crosshairX = null;
    _crosshairY = null;
    _crosshairIndex = null;
  }

  /// 탭으로 크로스헤어 활성화
  void handleTapDown(Offset position) {
    _crosshairX = position.dx;
    _crosshairY = position.dy;

    // 가장 가까운 캔들 인덱스 찾기
    if (_candles.isNotEmpty) {
      final chartWidth = size.x - _leftPadding - _rightPadding;
      final candleWidth = (chartWidth / _candles.length) * _scale;
      final idx = ((position.dx - _leftPadding - _scrollOffset) / candleWidth).round();
      _crosshairIndex = idx.clamp(0, _candles.length - 1);
    }
  }

  void handleTapUp() {
    // 크로스헤어를 잠시 유지 후 사라지게
    Future.delayed(const Duration(seconds: 2), () {
      _crosshairX = null;
      _crosshairY = null;
      _crosshairIndex = null;
    });
  }
}

/// Flutter 위젯으로 감싸는 래퍼
class CandleChartWidget extends StatefulWidget {
  final List<CandleData> candles;

  const CandleChartWidget({super.key, required this.candles});

  @override
  State<CandleChartWidget> createState() => _CandleChartWidgetState();
}

class _CandleChartWidgetState extends State<CandleChartWidget> {
  late final CandleChartGame _game;

  @override
  void initState() {
    super.initState();
    _game = CandleChartGame();
    _game.updateCandles(widget.candles);
  }

  @override
  void didUpdateWidget(CandleChartWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    _game.updateCandles(widget.candles);
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (details) => _game.handleTapDown(details.localPosition),
      onTapUp: (_) => _game.handleTapUp(),
      child: GameWidget(game: _game),
    );
  }
}
