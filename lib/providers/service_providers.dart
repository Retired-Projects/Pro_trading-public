import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/mock_data_service.dart';
import '../services/polling_service.dart';
import '../services/trading_engine.dart';
import '../services/supabase_service.dart';
import '../services/naver_finance_service.dart';
import '../services/yahoo_finance_service.dart';
import '../services/coingecko_service.dart';

final supabaseServiceProvider = Provider<SupabaseService>((ref) {
  return SupabaseService();
});

final naverFinanceServiceProvider = Provider<NaverFinanceService>((ref) {
  final service = NaverFinanceService();
  ref.onDispose(() => service.dispose());
  return service;
});

final yahooFinanceServiceProvider = Provider<YahooFinanceService>((ref) {
  final service = YahooFinanceService();
  ref.onDispose(() => service.dispose());
  return service;
});

final coinGeckoServiceProvider = Provider<CoinGeckoService>((ref) {
  final service = CoinGeckoService();
  ref.onDispose(() => service.dispose());
  return service;
});

final mockDataServiceProvider = Provider<MockDataService>((ref) {
  return MockDataService();
});

final pollingServiceProvider = Provider<PollingService>((ref) {
  final naver = ref.watch(naverFinanceServiceProvider);
  final mockData = ref.watch(mockDataServiceProvider);
  final service = PollingService(naver, mockData);
  ref.onDispose(() => service.dispose());
  return service;
});

final tradingEngineProvider = Provider<TradingEngine>((ref) {
  final mockData = ref.watch(mockDataServiceProvider);
  return TradingEngine(mockData);
});

/// 현재 사용자 ID
final userIdProvider = StateProvider<String?>((ref) => null);
