import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/stock.dart';

/// Twelve Data API 서비스
/// - 무료 티어: 분당 8회, 일 800회
/// - 배치 호출로 1 API콜에 8종목 동시 조회
/// - 한국 주��은 유료 → 미국 대형주 사용
class TwelveDataService {
  static const String _baseUrl = 'https://api.twelvedata.com';
  static const String _apiKey = String.fromEnvironment('TWELVE_DATA_API_KEY');

  final http.Client _client = http.Client();

  /// 여러 종목의 시세를 한 번에 조회 (배��)
  Future<Map<String, StockPrice>> fetchQuotes(List<String> symbols) async {
    final symbolParam = symbols.join(',');
    final uri = Uri.parse(
        '$_baseUrl/quote?symbol=$symbolParam&apikey=$_apiKey');

    try {
      final response = await _client.get(uri);
      if (response.statusCode != 200) return {};

      final json = jsonDecode(response.body);
      final result = <String, StockPrice>{};

      // 단일 종목일 때는 바로 객체, 여러 종목일 때는 Map
      if (symbols.length == 1) {
        final data = json as Map<String, dynamic>;
        if (data.containsKey('code')) return {}; // 에러
        final price = _parseQuote(symbols.first, data);
        if (price != null) result[symbols.first] = price;
      } else {
        for (final symbol in symbols) {
          final data = json[symbol] as Map<String, dynamic>?;
          if (data == null || data.containsKey('code')) continue;
          final price = _parseQuote(symbol, data);
          if (price != null) result[symbol] = price;
        }
      }

      return result;
    } catch (e) {
      return {};
    }
  }

  /// 캔들 데이터 조회 (화면 진입 시 1회)
  Future<List<CandleData>> fetchTimeSeries(String symbol,
      {String interval = '1min', int outputSize = 60}) async {
    final uri = Uri.parse(
        '$_baseUrl/time_series?symbol=$symbol&interval=$interval&outputsize=$outputSize&apikey=$_apiKey');

    try {
      final response = await _client.get(uri);
      if (response.statusCode != 200) return [];

      final json = jsonDecode(response.body);
      if (json['status'] == 'error') return [];

      final values = json['values'] as List<dynamic>;
      return values.map((v) {
        return CandleData(
          timestamp: DateTime.parse(v['datetime']),
          open: double.parse(v['open']),
          high: double.parse(v['high']),
          low: double.parse(v['low']),
          close: double.parse(v['close']),
          volume: int.parse(v['volume']),
        );
      }).toList().reversed.toList(); // 오래된 순으로 정렬
    } catch (e) {
      return [];
    }
  }

  StockPrice? _parseQuote(String symbol, Map<String, dynamic> data) {
    try {
      final close = double.tryParse(data['close']?.toString() ?? '');
      final open = double.tryParse(data['open']?.toString() ?? '');
      final high = double.tryParse(data['high']?.toString() ?? '');
      final low = double.tryParse(data['low']?.toString() ?? '');
      final prevClose =
          double.tryParse(data['previous_close']?.toString() ?? '');
      final volume = int.tryParse(data['volume']?.toString() ?? '');

      if (close == null || open == null || prevClose == null) return null;

      return StockPrice(
        stockCode: symbol,
        currentPrice: close,
        openPrice: open,
        highPrice: high ?? close,
        lowPrice: low ?? close,
        previousClose: prevClose,
        volume: volume ?? 0,
        timestamp: DateTime.now(),
      );
    } catch (e) {
      return null;
    }
  }

  void dispose() {
    _client.close();
  }
}
