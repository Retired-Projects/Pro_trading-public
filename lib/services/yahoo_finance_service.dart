import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import '../models/stock.dart';

/// Yahoo Finance API (무료, 키 불필요)
/// 미국 주식 시세 조회
class YahooFinanceService {
  final http.Client _client = http.Client();
  static const _headers = {'User-Agent': 'Mozilla/5.0'};
  static const _timeout = Duration(seconds: 10);

  /// 미국 주요 종목 목록 (시총 상위)
  static const List<Map<String, String>> usStocks = [
    {'code': 'AAPL', 'name': 'Apple', 'market': 'NASDAQ'},
    {'code': 'MSFT', 'name': 'Microsoft', 'market': 'NASDAQ'},
    {'code': 'GOOGL', 'name': 'Alphabet', 'market': 'NASDAQ'},
    {'code': 'AMZN', 'name': 'Amazon', 'market': 'NASDAQ'},
    {'code': 'NVDA', 'name': 'NVIDIA', 'market': 'NASDAQ'},
    {'code': 'META', 'name': 'Meta', 'market': 'NASDAQ'},
    {'code': 'TSLA', 'name': 'Tesla', 'market': 'NASDAQ'},
    {'code': 'BRK-B', 'name': 'Berkshire', 'market': 'NYSE'},
    {'code': 'JPM', 'name': 'JPMorgan', 'market': 'NYSE'},
    {'code': 'V', 'name': 'Visa', 'market': 'NYSE'},
    {'code': 'UNH', 'name': 'UnitedHealth', 'market': 'NYSE'},
    {'code': 'MA', 'name': 'Mastercard', 'market': 'NYSE'},
    {'code': 'HD', 'name': 'Home Depot', 'market': 'NYSE'},
    {'code': 'PG', 'name': 'P&G', 'market': 'NYSE'},
    {'code': 'JNJ', 'name': 'J&J', 'market': 'NYSE'},
    {'code': 'AVGO', 'name': 'Broadcom', 'market': 'NASDAQ'},
    {'code': 'XOM', 'name': 'ExxonMobil', 'market': 'NYSE'},
    {'code': 'COST', 'name': 'Costco', 'market': 'NASDAQ'},
    {'code': 'ABBV', 'name': 'AbbVie', 'market': 'NYSE'},
    {'code': 'CRM', 'name': 'Salesforce', 'market': 'NYSE'},
    {'code': 'AMD', 'name': 'AMD', 'market': 'NASDAQ'},
    {'code': 'NFLX', 'name': 'Netflix', 'market': 'NASDAQ'},
    {'code': 'ADBE', 'name': 'Adobe', 'market': 'NASDAQ'},
    {'code': 'LIN', 'name': 'Linde', 'market': 'NYSE'},
    {'code': 'ORCL', 'name': 'Oracle', 'market': 'NYSE'},
    {'code': 'DIS', 'name': 'Disney', 'market': 'NYSE'},
    {'code': 'INTC', 'name': 'Intel', 'market': 'NASDAQ'},
    {'code': 'CSCO', 'name': 'Cisco', 'market': 'NASDAQ'},
    {'code': 'BA', 'name': 'Boeing', 'market': 'NYSE'},
    {'code': 'NKE', 'name': 'Nike', 'market': 'NYSE'},
  ];

  /// 여러 종목 시세 조회 — 5개씩 배치 처리 (레이트 리밋 방지)
  static const _batchSize = 5;
  static const _batchDelay = Duration(milliseconds: 200);

  Future<Map<String, StockPrice>> fetchQuotes(List<String> symbols) async {
    final result = <String, StockPrice>{};
    for (var i = 0; i < symbols.length; i += _batchSize) {
      final batch = symbols.sublist(i, min(i + _batchSize, symbols.length));
      final prices = await Future.wait(batch.map(_fetchSingle));
      for (final price in prices) {
        if (price != null) result[price.stockCode] = price;
      }
      // 마지막 배치가 아니면 잠시 대기
      if (i + _batchSize < symbols.length) {
        await Future.delayed(_batchDelay);
      }
    }
    return result;
  }

  Future<StockPrice?> _fetchSingle(String symbol) async {
    final uri = Uri.parse(
        'https://query1.finance.yahoo.com/v8/finance/chart/$symbol?interval=1d&range=1d');
    try {
      final response = await _client.get(uri, headers: _headers).timeout(_timeout);
      if (response.statusCode != 200) return null;

      final json = jsonDecode(response.body);
      final result = json['chart']['result'][0];
      final meta = result['meta'] as Map<String, dynamic>;

      final price = (meta['regularMarketPrice'] as num).toDouble();
      final prevClose =
          (meta['chartPreviousClose'] as num?)?.toDouble() ?? price;
      final open =
          (meta['regularMarketOpen'] as num?)?.toDouble() ?? price;
      final high =
          (meta['regularMarketDayHigh'] as num?)?.toDouble() ?? price;
      final low =
          (meta['regularMarketDayLow'] as num?)?.toDouble() ?? price;
      final volume =
          (meta['regularMarketVolume'] as num?)?.toInt() ?? 0;

      return StockPrice(
        stockCode: symbol,
        currentPrice: price,
        openPrice: open,
        highPrice: high,
        lowPrice: low,
        previousClose: prevClose,
        volume: volume,
        timestamp: DateTime.now(),
      );
    } catch (_) {
      return null;
    }
  }

  /// 일봉 캔들 데이터
  Future<List<CandleData>> fetchDailyCandles(String symbol,
      {int days = 60}) async {
    final uri = Uri.parse(
        'https://query1.finance.yahoo.com/v8/finance/chart/$symbol?interval=1d&range=3mo');
    try {
      final response = await _client.get(uri, headers: _headers).timeout(_timeout);
      if (response.statusCode != 200) return [];

      final json = jsonDecode(response.body);
      final result = json['chart']['result'][0];
      final timestamps = result['timestamp'] as List<dynamic>?;
      final indicators = result['indicators']['quote'][0];

      if (timestamps == null) return [];

      final candles = <CandleData>[];
      for (var i = 0; i < timestamps.length; i++) {
        final open = (indicators['open']?[i] as num?)?.toDouble();
        final high = (indicators['high']?[i] as num?)?.toDouble();
        final low = (indicators['low']?[i] as num?)?.toDouble();
        final close = (indicators['close']?[i] as num?)?.toDouble();
        final volume = (indicators['volume']?[i] as num?)?.toInt();

        if (open == null || close == null) continue;

        candles.add(CandleData(
          timestamp: DateTime.fromMillisecondsSinceEpoch(
              (timestamps[i] as int) * 1000),
          open: open,
          high: high ?? open,
          low: low ?? open,
          close: close,
          volume: volume ?? 0,
        ));
      }
      return candles;
    } catch (_) {
      return [];
    }
  }

  void dispose() => _client.close();
}
