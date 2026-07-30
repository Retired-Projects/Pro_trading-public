import 'package:flutter_riverpod/flutter_riverpod.dart';

/// 가격 알림 모델
class PriceAlert {
  final String id;
  final String stockCode;
  final String stockName;
  final double targetPrice;
  final bool isAbove; // true: 이상일 때, false: 이하일 때
  final bool triggered;
  final DateTime createdAt;

  const PriceAlert({
    required this.id,
    required this.stockCode,
    required this.stockName,
    required this.targetPrice,
    required this.isAbove,
    this.triggered = false,
    required this.createdAt,
  });

  PriceAlert copyWith({bool? triggered}) => PriceAlert(
        id: id,
        stockCode: stockCode,
        stockName: stockName,
        targetPrice: targetPrice,
        isAbove: isAbove,
        triggered: triggered ?? this.triggered,
        createdAt: createdAt,
      );
}

/// 가격 알림 상태 관리
class AlertNotifier extends StateNotifier<List<PriceAlert>> {
  AlertNotifier() : super([]);

  void addAlert(PriceAlert alert) {
    state = [alert, ...state];
  }

  void removeAlert(String id) {
    state = state.where((a) => a.id != id).toList();
  }

  /// 현재가와 비교하여 알림 트리거 확인
  List<PriceAlert> checkAlerts(Map<String, double> currentPrices) {
    final triggered = <PriceAlert>[];
    final updated = <PriceAlert>[];

    for (final alert in state) {
      if (alert.triggered) {
        updated.add(alert);
        continue;
      }

      final price = currentPrices[alert.stockCode];
      if (price == null) {
        updated.add(alert);
        continue;
      }

      final shouldTrigger = alert.isAbove
          ? price >= alert.targetPrice
          : price <= alert.targetPrice;

      if (shouldTrigger) {
        triggered.add(alert);
        updated.add(alert.copyWith(triggered: true));
      } else {
        updated.add(alert);
      }
    }

    state = updated;
    return triggered;
  }

  void clearTriggered() {
    state = state.where((a) => !a.triggered).toList();
  }
}

final alertProvider =
    StateNotifierProvider<AlertNotifier, List<PriceAlert>>((ref) {
  return AlertNotifier();
});
