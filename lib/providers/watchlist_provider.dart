import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'service_providers.dart';

/// 관심종목 상태 관리
class WatchlistNotifier extends StateNotifier<List<Map<String, String>>> {
  final Ref ref;

  WatchlistNotifier(this.ref) : super([]);

  /// Supabase에서 로드
  Future<void> load() async {
    final userId = ref.read(userIdProvider);
    if (userId == null) return;
    final supabase = ref.read(supabaseServiceProvider);
    state = await supabase.getWatchlist(userId);
  }

  /// 관심종목 추가
  Future<void> add(String code, String name, String market) async {
    final userId = ref.read(userIdProvider);
    if (userId == null) return;

    // 이미 있으면 스킵
    if (state.any((s) => s['code'] == code)) return;

    final supabase = ref.read(supabaseServiceProvider);
    await supabase.addToWatchlist(userId, code, name, market);
    state = [{'code': code, 'name': name, 'market': market}, ...state];
  }

  /// 관심종목 삭제
  Future<void> remove(String code) async {
    final userId = ref.read(userIdProvider);
    if (userId == null) return;

    final supabase = ref.read(supabaseServiceProvider);
    await supabase.removeFromWatchlist(userId, code);
    state = state.where((s) => s['code'] != code).toList();
  }

  /// 관심종목 토글
  Future<bool> toggle(String code, String name, String market) async {
    if (isWatching(code)) {
      await remove(code);
      return false;
    } else {
      await add(code, name, market);
      return true;
    }
  }

  bool isWatching(String code) => state.any((s) => s['code'] == code);
}

final watchlistProvider =
    StateNotifierProvider<WatchlistNotifier, List<Map<String, String>>>((ref) {
  return WatchlistNotifier(ref);
});
