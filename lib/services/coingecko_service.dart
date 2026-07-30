import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/stock.dart';

/// CoinGecko API (무료, 키 불필요)
/// 암호화폐 시세 조회
class CoinGeckoService {
  final http.Client _client = http.Client();

  /// 시총 상위 코인 목록 가져오기
  Future<List<Map<String, String>>> fetchCoinList({int perPage = 50}) async {
    final uri = Uri.parse(
        'https://api.coingecko.com/api/v3/coins/markets'
        '?vs_currency=krw&order=market_cap_desc&per_page=$perPage&page=1');

    try {
      final response = await _client.get(uri);
      if (response.statusCode != 200) return [];

      final json = jsonDecode(response.body) as List<dynamic>;
      return json.map((c) => {
            'code': (c['symbol'] as String).toUpperCase(),
            'name': c['name'] as String,
            'market': 'CRYPTO',
            'id': c['id'] as String,
          }).toList();
    } catch (_) {
      return [];
    }
  }

  /// 코인 시세 조회 (KRW 기준)
  Future<Map<String, StockPrice>> fetchQuotes({int perPage = 50}) async {
    final uri = Uri.parse(
        'https://api.coingecko.com/api/v3/coins/markets'
        '?vs_currency=krw&order=market_cap_desc&per_page=$perPage&page=1'
        '&sparkline=false&price_change_percentage=24h');

    try {
      final response = await _client.get(uri);
      if (response.statusCode != 200) return {};

      final json = jsonDecode(response.body) as List<dynamic>;
      final result = <String, StockPrice>{};

      for (final coin in json) {
        final symbol = (coin['symbol'] as String).toUpperCase();
        final price = (coin['current_price'] as num?)?.toDouble() ?? 0;
        final high24 = (coin['high_24h'] as num?)?.toDouble() ?? price;
        final low24 = (coin['low_24h'] as num?)?.toDouble() ?? price;
        final changePercent =
            (coin['price_change_percentage_24h'] as num?)?.toDouble() ?? 0;
        final volume = (coin['total_volume'] as num?)?.toInt() ?? 0;

        // 전일 종가 역산
        final previousClose =
            changePercent != 0 ? price / (1 + changePercent / 100) : price;

        result[symbol] = StockPrice(
          stockCode: symbol,
          currentPrice: price,
          openPrice: previousClose,
          highPrice: high24,
          lowPrice: low24,
          previousClose: previousClose,
          volume: volume,
          timestamp: DateTime.now(),
        );
      }

      return result;
    } catch (_) {
      return {};
    }
  }

  /// 코인 일봉 캔들 데이터 (차트용)
  Future<List<CandleData>> fetchDailyCandles(String coinId) async {
    final uri = Uri.parse(
        'https://api.coingecko.com/api/v3/coins/$coinId/ohlc'
        '?vs_currency=krw&days=30');

    try {
      final response = await _client.get(uri);
      if (response.statusCode != 200) return [];

      final json = jsonDecode(response.body) as List<dynamic>;
      return json.map((item) {
        final list = item as List<dynamic>;
        return CandleData(
          timestamp:
              DateTime.fromMillisecondsSinceEpoch((list[0] as num).toInt()),
          open: (list[1] as num).toDouble(),
          high: (list[2] as num).toDouble(),
          low: (list[3] as num).toDouble(),
          close: (list[4] as num).toDouble(),
          volume: 0,
        );
      }).toList();
    } catch (_) {
      return [];
    }
  }

  /// 심볼(BTC 등)로 CoinGecko id(bitcoin 등) 조회
  Future<String?> getIdBySymbol(String symbol) async {
    final uri = Uri.parse(
        'https://api.coingecko.com/api/v3/coins/markets'
        '?vs_currency=krw&order=market_cap_desc&per_page=100&page=1');

    try {
      final response = await _client.get(uri);
      if (response.statusCode != 200) return null;

      final json = jsonDecode(response.body) as List<dynamic>;
      for (final coin in json) {
        if ((coin['symbol'] as String).toUpperCase() == symbol.toUpperCase()) {
          return coin['id'] as String;
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  void dispose() => _client.close();
}
