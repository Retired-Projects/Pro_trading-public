class AppConstants {
  // Polling — 장중 30초, 장외 폴링 없음
  static const Duration pollingInterval = Duration(seconds: 30);
  static const Duration microTickInterval = Duration(milliseconds: 1000);

  /// 현재 어떤 시장이라도 열려있는지 확인 (폴링 여부 결정용)
  static bool isAnyMarketOpen() =>
      isKrMarketOpen() || isUsMarketOpen() || isCryptoMarketOpen();

  // Trading
  static const double initialBalance = 100000000; // 1억원
  static const double tradingFeeRate = 0.00015; // 0.015% 수수료
  static const double taxRate = 0.0023; // 0.23% 세금 (매도 시)

  // Chart
  static const int maxCandleCount = 60;
  static const int orderBookDepth = 5; // 호가 5단계

  // Animation
  static const Duration smoothingDuration = Duration(milliseconds: 500);

  // 종목 로딩 설정
  static const int kospiLoadSize = 100;
  static const int kosdaqLoadSize = 50;

  /// 한국 주식 정규장 운영시간 (KST 09:00~15:30, 평일)
  /// - 장전 시간외(~09:00), 에프터마켓(15:30~), NXT 등 비정규 세션 모두 제외
  static bool isKrMarketOpen() {
    final now = DateTime.now();
    if (now.weekday >= 6) return false; // 토/일
    final time = now.hour * 60 + now.minute;
    return time >= 540 && time < 930; // 09:00 이상 ~ 15:30 미만
  }

  /// 미국 주식시장 운영시간 (KST 23:30~06:00, 평일 기준 / 서머타임: 22:30~05:00)
  static bool isUsMarketOpen() {
    final now = DateTime.now();
    final weekday = now.weekday;
    final hour = now.hour;
    // 야간 세션: 월~금 KST 22:30 ~ 다음날 06:00
    if (hour >= 22 && weekday <= 5) return true;
    if (hour < 6 && weekday >= 2 && weekday <= 6) return true;
    return false;
  }

  /// 암호화폐는 24시간 운영
  static bool isCryptoMarketOpen() => true;
}
