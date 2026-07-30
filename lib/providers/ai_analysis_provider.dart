import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../services/ai_analysis_service.dart';
import '../services/supabase_service.dart';
import '../models/portfolio.dart';
import '../models/trade.dart';
import 'service_providers.dart';

const _kMinTrades = 3;

String _prefDate(String userId) => 'ai_report_date_$userId';
String _prefResult(String userId) => 'ai_report_result_$userId';

class AiAnalysisState {
  final bool isLoading;
  final String? result;
  final String? error;
  /// 오늘 이미 분석 완료 여부
  final bool analyzedToday;

  const AiAnalysisState({
    this.isLoading = false,
    this.result,
    this.error,
    this.analyzedToday = false,
  });

  AiAnalysisState copyWith({
    bool? isLoading,
    String? result,
    String? error,
    bool? analyzedToday,
  }) =>
      AiAnalysisState(
        isLoading: isLoading ?? this.isLoading,
        result: result ?? this.result,
        error: error ?? this.error,
        analyzedToday: analyzedToday ?? this.analyzedToday,
      );
}

class AiAnalysisNotifier extends StateNotifier<AiAnalysisState> {
  final _service = AiAnalysisService();
  final Ref _ref;

  AiAnalysisNotifier(this._ref) : super(const AiAnalysisState()) {
    _loadCached();
  }

  String? get _currentUserId =>
      Supabase.instance.client.auth.currentUser?.id;

  /// 앱 시작 시 오늘 캐시된 결과 복원
  Future<void> _loadCached() async {
    final userId = _currentUserId;
    if (userId == null) return;

    final prefs = await SharedPreferences.getInstance();
    final savedDate = prefs.getString(_prefDate(userId));
    final savedResult = prefs.getString(_prefResult(userId));
    final today = _todayStr();

    if (savedDate == today && savedResult != null && savedResult.isNotEmpty) {
      state = AiAnalysisState(result: savedResult, analyzedToday: true);
    }
  }

  Future<void> analyze(Portfolio portfolio, List<TradeLog> tradeLogs) async {
    // 거래 최소 횟수 체크
    if (tradeLogs.length < _kMinTrades) {
      state = state.copyWith(
        error: '거래 내역이 $_kMinTrades회 이상이어야 리포트를 발급받을 수 있습니다.\n현재: ${tradeLogs.length}회',
      );
      return;
    }

    final userId = _currentUserId;
    if (userId == null) {
      state = state.copyWith(error: '로그인이 필요합니다');
      return;
    }

    // 1일 1회 제한
    final prefs = await SharedPreferences.getInstance();
    final savedDate = prefs.getString(_prefDate(userId));
    if (savedDate == _todayStr()) {
      final cached = prefs.getString(_prefResult(userId));
      if (cached != null && cached.isNotEmpty) {
        state = AiAnalysisState(result: cached, analyzedToday: true);
        return;
      }
    }

    state = const AiAnalysisState(isLoading: true);
    try {
      final result = await _service.analyze(
        portfolio: portfolio,
        tradeLogs: tradeLogs,
      );

      // 캐시 저장
      await prefs.setString(_prefDate(userId), _todayStr());
      await prefs.setString(_prefResult(userId), result);

      state = AiAnalysisState(result: result, analyzedToday: true);
      // 히스토리 캐시 무효화 → 새 리포트 반영
      _ref.invalidate(aiReportsHistoryProvider);
    } catch (e) {
      state = AiAnalysisState(
        error: e.toString().replaceAll('Exception: ', ''),
      );
    }
  }

  String _todayStr() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }
}

final aiAnalysisProvider =
    StateNotifierProvider<AiAnalysisNotifier, AiAnalysisState>((ref) {
  return AiAnalysisNotifier(ref);
});

/// 내 AI 리포트 히스토리 (Supabase에서 최신순 조회)
final aiReportsHistoryProvider = FutureProvider<List<AiReport>>((ref) async {
  final userId = ref.watch(userIdProvider);
  if (userId == null) return [];
  final service = ref.read(supabaseServiceProvider);
  return service.getAiReports(userId);
});
