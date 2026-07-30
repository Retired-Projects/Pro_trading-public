import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/stock.dart';
import '../core/constants/app_constants.dart';
import '../services/yahoo_finance_service.dart';
import 'service_providers.dart';

/// 현재 선택된 마켓 탭
enum MarketTab { kospi, kosdaq, us, crypto }

final marketTabProvider = StateProvider<MarketTab>((ref) => MarketTab.kospi);

/// 실시간 시세 데이터 Provider (한국 주식)
final priceStreamProvider =
    StreamProvider<Map<String, StockPrice>>((ref) {
  final polling = ref.watch(pollingServiceProvider);
  return polling.priceStream;
});

/// 특정 종목 시세
final stockPriceProvider =
    Provider.family<StockPrice?, String>((ref, stockCode) {
  final krPrices = ref.watch(priceStreamProvider).valueOrNull;
  if (krPrices != null && krPrices.containsKey(stockCode)) {
    return krPrices[stockCode];
  }
  final usPrices = ref.watch(usPriceProvider).valueOrNull;
  if (usPrices != null && usPrices.containsKey(stockCode)) {
    return usPrices[stockCode];
  }
  final cryptoPrices = ref.watch(cryptoPriceProvider).valueOrNull;
  if (cryptoPrices != null && cryptoPrices.containsKey(stockCode)) {
    return cryptoPrices[stockCode];
  }
  return null;
});

/// 호가창 데이터
final orderBookStreamProvider = StreamProvider<OrderBook>((ref) {
  final polling = ref.watch(pollingServiceProvider);
  return polling.orderBookStream;
});

/// 캔들 데이터 (autoDispose: 화면 이탈 시 해제, 종목마다 별도 캐시 방지)
final candleDataProvider =
    FutureProvider.autoDispose.family<List<CandleData>, String>((ref, stockCode) async {
  // 미국 주식인지 확인
  final isUS = YahooFinanceService.usStocks
      .any((s) => s['code'] == stockCode);
  if (isUS) {
    final yahoo = ref.watch(yahooFinanceServiceProvider);
    return yahoo.fetchDailyCandles(stockCode);
  }

  // 코인인지 확인
  final cryptoList = ref.watch(cryptoListProvider).valueOrNull ?? [];
  final cryptoMatch = cryptoList
      .where((c) => c['code'] == stockCode)
      .toList();
  if (cryptoMatch.isNotEmpty) {
    final coinId = cryptoMatch.first['id'];
    if (coinId != null) {
      final gecko = ref.watch(coinGeckoServiceProvider);
      return gecko.fetchDailyCandles(coinId);
    }
    // id가 없으면 심볼로 조회
    final gecko = ref.watch(coinGeckoServiceProvider);
    final id = await gecko.getIdBySymbol(stockCode);
    if (id != null) {
      return gecko.fetchDailyCandles(id);
    }
    return [];
  }

  final naver = ref.watch(naverFinanceServiceProvider);
  final candles = await naver.fetchDailyCandles(stockCode);
  final mockData = ref.read(mockDataServiceProvider);
  mockData.setCandles(stockCode, candles);
  return candles;
});

// ─── 한국 주식 ───

final kospiListProvider =
    FutureProvider<List<Map<String, String>>>((ref) async {
  final naver = ref.watch(naverFinanceServiceProvider);
  return naver.fetchStockList('KOSPI', pageSize: AppConstants.kospiLoadSize);
});

final kosdaqListProvider =
    FutureProvider<List<Map<String, String>>>((ref) async {
  final naver = ref.watch(naverFinanceServiceProvider);
  return naver.fetchStockList('KOSDAQ', pageSize: AppConstants.kosdaqLoadSize);
});

/// 전체 한국 주식 (코스피 + 코스닥)
final stockListProvider =
    FutureProvider<List<Map<String, String>>>((ref) async {
  final naver = ref.watch(naverFinanceServiceProvider);
  return naver.fetchAllStocks(
    kospiSize: AppConstants.kospiLoadSize,
    kosdaqSize: AppConstants.kosdaqLoadSize,
  );
});

/// 종목 코드 목록
final stockCodesProvider = Provider<List<String>>((ref) {
  final stocks = ref.watch(stockListProvider).valueOrNull ?? [];
  return stocks.map((s) => s['code']!).toList();
});

// ─── 미국 주식 ───

final usStockListProvider = Provider<List<Map<String, String>>>((ref) {
  return YahooFinanceService.usStocks;
});

final usPriceProvider =
    FutureProvider<Map<String, StockPrice>>((ref) async {
  final yahoo = ref.watch(yahooFinanceServiceProvider);
  final symbols =
      YahooFinanceService.usStocks.map((s) => s['code']!).toList();
  return yahoo.fetchQuotes(symbols);
});

// ─── 코인 ───

final cryptoListProvider =
    FutureProvider<List<Map<String, String>>>((ref) async {
  final gecko = ref.watch(coinGeckoServiceProvider);
  return gecko.fetchCoinList(perPage: 50);
});

final cryptoPriceProvider =
    FutureProvider<Map<String, StockPrice>>((ref) async {
  final gecko = ref.watch(coinGeckoServiceProvider);
  return gecko.fetchQuotes(perPage: 50);
});

// ─── 검색 ───

final searchQueryProvider = StateProvider<String>((ref) => '');

/// 검색 결과 (autoDispose: 검색 쿼리 변경 시 이전 결과 즉시 해제)
final searchResultsProvider =
    FutureProvider.autoDispose<List<Map<String, String>>>((ref) async {
  final query = ref.watch(searchQueryProvider);
  if (query.isEmpty) return [];
  final naver = ref.watch(naverFinanceServiceProvider);
  return naver.searchStocks(query);
});

/// 검색 결과 종목들의 시세 조회 (autoDispose: 검색창 닫으면 해제)
final searchPriceProvider =
    FutureProvider.autoDispose<Map<String, StockPrice>>((ref) async {
  final results = ref.watch(searchResultsProvider).valueOrNull ?? [];
  if (results.isEmpty) return {};
  final codes = results.map((s) => s['code']!).toList();
  final naver = ref.watch(naverFinanceServiceProvider);
  return naver.fetchQuotes(codes);
});
