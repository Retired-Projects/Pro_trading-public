import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/stock.dart';

/// 네이버 금융 API 서비스
/// - 무료, API 키 불필요, 호출 제한 없음
/// - 배치 시세 조회 (여러 종목 동시)
/// - 일봉/주봉 캔들 데이터
class NaverFinanceService {
  final http.Client _client = http.Client();

  static const _headers = {'User-Agent': 'Mozilla/5.0'};
  static const _timeout = Duration(seconds: 15);

  // fetchQuotes 응답 캐시 (2초 TTL — 폴링 간격 내 중복 호출 방지)
  Map<String, StockPrice>? _quotesCache;
  DateTime? _quotesCacheTime;
  static const _quotesCacheDuration = Duration(seconds: 2);

  /// 여러 종목의 실시간 시세를 한 번에 조회
  Future<Map<String, StockPrice>> fetchQuotes(List<String> codes) async {
    // 캐시 유효 시 재사용
    if (_quotesCache != null && _quotesCacheTime != null &&
        DateTime.now().difference(_quotesCacheTime!) < _quotesCacheDuration) {
      return _quotesCache!;
    }

    final symbolParam = codes.join(',');
    final uri = Uri.parse(
        'https://polling.finance.naver.com/api/realtime/domestic/stock/$symbolParam');

    try {
      final response = await _client.get(uri, headers: _headers).timeout(_timeout);
      if (response.statusCode != 200) {
        return {};
      }

      final json = jsonDecode(response.body);
      final datas = json['datas'] as List<dynamic>;
      final result = <String, StockPrice>{};

      for (final item in datas) {
        final code = item['itemCode'] as String;
        final price = _parseRealtimeQuote(item);
        if (price != null) result[code] = price;
      }

      // 캐시 갱신
      _quotesCache = result;
      _quotesCacheTime = DateTime.now();
      return result;
    } catch (e) {
      return {};
    }
  }

  /// 단일 종목 기본 정보 (종목명, 시총 등)
  Future<Map<String, dynamic>?> fetchBasicInfo(String code) async {
    final uri =
        Uri.parse('https://m.stock.naver.com/api/stock/$code/basic');

    try {
      final response = await _client.get(uri, headers: _headers).timeout(_timeout);
      if (response.statusCode != 200) return null;
      return jsonDecode(response.body) as Map<String, dynamic>;
    } catch (e) {
      return null;
    }
  }

  /// 시가총액 상위 종목 리스트 (코스피/코스닥)
  /// [market]: 'KOSPI' 또는 'KOSDAQ'
  /// [pageSize]: 가져올 종목 수 (상한 없음)
  Future<List<Map<String, String>>> fetchStockList(String market,
      {int pageSize = 100}) async {
    final uri = Uri.parse(
        'https://m.stock.naver.com/api/stocks/marketValue/$market?page=1&pageSize=$pageSize');

    try {
      final response = await _client.get(uri, headers: _headers).timeout(_timeout);
      if (response.statusCode != 200) {
        return [];
      }

      final json = jsonDecode(response.body);
      final stocks = json['stocks'] as List<dynamic>;

      return stocks.map((s) => {
            'code': s['itemCode'] as String,
            'name': s['stockName'] as String,
            'market': market,
          }).toList();
    } catch (e) {
      return [];
    }
  }

  /// 코스피 + 코스닥 전체 종목 가져오기
  Future<List<Map<String, String>>> fetchAllStocks({
    int kospiSize = 100,
    int kosdaqSize = 50,
  }) async {
    final results = await Future.wait([
      fetchStockList('KOSPI', pageSize: kospiSize),
      fetchStockList('KOSDAQ', pageSize: kosdaqSize),
    ]);
    return [...results[0], ...results[1]];
  }

  /// 종목 검색 (자동완성)
  Future<List<Map<String, String>>> searchStocks(String query) async {
    if (query.isEmpty) return [];

    final uri = Uri.parse(
        'https://ac.stock.naver.com/ac?q=${Uri.encodeComponent(query)}&target=stock');

    try {
      final response = await _client.get(uri, headers: _headers).timeout(_timeout);
      if (response.statusCode != 200) return [];

      final json = jsonDecode(response.body);
      final items = json['items'] as List<dynamic>;

      return items
          .where((item) {
            final type = item['typeCode'] as String? ?? '';
            return type == 'KOSPI' || type == 'KOSDAQ';
          })
          .map((item) => {
                'code': item['code'] as String,
                'name': item['name'] as String,
                'market': item['typeCode'] as String,
              })
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// 일봉 캔들 데이터 조회
  Future<List<CandleData>> fetchDailyCandles(String code,
      {int pageSize = 60}) async {
    final uri = Uri.parse(
        'https://m.stock.naver.com/api/stock/$code/price?pageSize=$pageSize&type=day');

    try {
      final response = await _client.get(uri, headers: _headers).timeout(_timeout);
      if (response.statusCode != 200) return [];

      final json = jsonDecode(response.body) as List<dynamic>;
      final candles = <CandleData>[];

      for (final item in json) {
        try {
          candles.add(CandleData(
            timestamp: DateTime.parse(item['localTradedAt']),
            open: _parsePrice(item['openPrice']),
            high: _parsePrice(item['highPrice']),
            low: _parsePrice(item['lowPrice']),
            close: _parsePrice(item['closePrice']),
            volume: item['accumulatedTradingVolume'] is int
                ? item['accumulatedTradingVolume']
                : int.tryParse(
                        item['accumulatedTradingVolume']?.toString() ?? '0') ??
                    0,
          ));
        } catch (_) {}
      }

      return candles.reversed.toList(); // 오래된 순
    } catch (e) {
      return [];
    }
  }

  StockPrice? _parseRealtimeQuote(Map<String, dynamic> data) {
    try {
      final code = data['itemCode'] as String;

      // Raw 값이 있으면 우선 사용 (숫자형), 없으면 문자열 파싱
      final close = _tryRaw(data, 'closePriceRaw') ??
          _parsePrice(data['closePrice']);
      final open = _tryRaw(data, 'openPriceRaw') ??
          _parsePrice(data['openPrice']);
      final high = _tryRaw(data, 'highPriceRaw') ??
          _parsePrice(data['highPrice']);
      final low = _tryRaw(data, 'lowPriceRaw') ??
          _parsePrice(data['lowPrice']);

      // 전일 종가 = 현재가 - 전일대비
      final change = _tryRaw(data, 'compareToPreviousClosePriceRaw') ??
          _parsePrice(data['compareToPreviousClosePrice']);
      final previousClose = close - change;

      final volume = _tryRaw(data, 'accumulatedTradingVolumeRaw')?.toInt() ??
          _parseVolume(data['accumulatedTradingVolume']);

      return StockPrice(
        stockCode: code,
        currentPrice: close,
        openPrice: open,
        highPrice: high,
        lowPrice: low,
        previousClose: previousClose,
        volume: volume,
        timestamp: DateTime.now(),
      );
    } catch (e) {
      return null;
    }
  }

  double? _tryRaw(Map<String, dynamic> data, String key) {
    final val = data[key];
    if (val == null) return null;
    if (val is num) return val.toDouble();
    return double.tryParse(val.toString());
  }

  double _parsePrice(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    final str = value.toString().replaceAll(',', '').replaceAll('+', '');
    return double.tryParse(str) ?? 0;
  }

  int _parseVolume(dynamic value) {
    if (value == null) return 0;
    if (value is int) return value;
    final str = value.toString().replaceAll(',', '');
    return int.tryParse(str) ?? 0;
  }

  void dispose() {
    _client.close();
  }
}
