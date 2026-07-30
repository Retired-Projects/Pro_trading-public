import 'package:intl/intl.dart';

class Formatters {
  static final _priceFormat = NumberFormat('#,###');
  static final _decimalFormat = NumberFormat('#,###.##');
  static final _percentFormat = NumberFormat('+#,##0.00;-#,##0.00');

  /// 가격 포맷 (예: 71,500)
  static String price(double value) => _priceFormat.format(value.round());

  /// 금액 포맷 (소수점 포함)
  static String amount(double value) => _decimalFormat.format(value);

  /// 퍼센트 포맷 (예: +2.35, -1.20)
  static String percent(double value) => '${_percentFormat.format(value)}%';

  /// 변동 금액 포맷 (예: +1,500, -2,000)
  static String change(double value) {
    final prefix = value > 0 ? '+' : '';
    return '$prefix${_priceFormat.format(value.round())}';
  }

  /// 거래량 축약 (예: 1.2만, 3.5억)
  static String volume(int value) {
    if (value >= 100000000) {
      return '${(value / 100000000).toStringAsFixed(1)}억';
    } else if (value >= 10000) {
      return '${(value / 10000).toStringAsFixed(1)}만';
    }
    return _priceFormat.format(value);
  }

  /// 큰 금액 축약 (예: 1억 234만)
  static String largeAmount(double value) {
    if (value >= 100000000) {
      final eok = (value / 100000000).floor();
      final man = ((value % 100000000) / 10000).floor();
      if (man > 0) {
        return '$eok억 ${_priceFormat.format(man)}만';
      }
      return '$eok억';
    } else if (value >= 10000) {
      return '${_priceFormat.format((value / 10000).floor())}만';
    }
    return _priceFormat.format(value.round());
  }
}
