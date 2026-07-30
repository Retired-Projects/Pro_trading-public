import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/formatters.dart';
import '../providers/settings_providers.dart';

/// 유저 랭킹 데이터 (총 자산 기준)
/// get_leaderboard() RPC를 통해 nickname과 total_asset만 노출 (RLS 우회 없이 안전)
final leaderboardProvider =
    FutureProvider<List<Map<String, dynamic>>>((ref) async {
  final supabase = Supabase.instance.client;

  final data = await supabase.rpc('get_leaderboard') as List<dynamic>;

  final result = data.map((p) {
    return <String, dynamic>{
      'nickname': p['nickname'] as String? ?? '트레이더',
      'balance': (p['total_asset'] as num?)?.toDouble() ?? 0,
    };
  }).toList();

  result.sort((a, b) =>
      ((b['balance'] as double)).compareTo(a['balance'] as double));

  // 닉네임이 '트레이더'(기본값)인 유저는 순서대로 번호 부여 (새 Map 생성, 원본 변이 금지)
  int counter = 1;
  return result.map((user) {
    if ((user['nickname'] as String?) == '트레이더') {
      return <String, dynamic>{...user, 'nickname': '트레이더 ${counter++}'};
    }
    return user;
  }).toList();
});

class LeaderboardScreen extends ConsumerWidget {
  const LeaderboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(themeProvider);
    final leaderboard = ref.watch(leaderboardProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('유저 랭킹'),
        backgroundColor: AppColors.surface,
        actions: [
          IconButton(
            icon: Icon(Icons.refresh, color: AppColors.textSecondary),
            onPressed: () => ref.invalidate(leaderboardProvider),
          ),
        ],
      ),
      body: leaderboard.when(
        loading: () => Center(
            child: CircularProgressIndicator(color: AppColors.primary)),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.error_outline, color: AppColors.textSecondary, size: 48),
                const SizedBox(height: 12),
                Text('랭킹 로딩 실패',
                    style: TextStyle(color: AppColors.textPrimary, fontSize: 16)),
                const SizedBox(height: 8),
                Text(e.toString(),
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.textSecondary, fontSize: 12)),
                const SizedBox(height: 16),
                TextButton(
                  onPressed: () => ref.invalidate(leaderboardProvider),
                  child: Text('다시 시도', style: TextStyle(color: AppColors.primary)),
                ),
              ],
            ),
          ),
        ),
        data: (users) {
          if (users.isEmpty) {
            return Center(
                child: Text('아직 참가자가 없습니다',
                    style: TextStyle(color: AppColors.textSecondary)));
          }

          return Column(
            children: [
              // 상위 3명 하이라이트
              if (users.length >= 3) _buildTopThree(users),

              Divider(color: AppColors.divider, height: 1),

              // 전체 리스트
              Expanded(
                child: ListView.separated(
                  itemCount: users.length,
                  separatorBuilder: (_, _) =>
                      Divider(color: AppColors.divider, height: 1),
                  itemBuilder: (context, index) {
                    final user = users[index];
                    return _buildUserTile(user, index + 1);
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildTopThree(List<Map<String, dynamic>> users) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      color: AppColors.surface,
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          if (users.length > 1)
            _buildTopUser(users[1], 2, 50),
          _buildTopUser(users[0], 1, 64),
          if (users.length > 2)
            _buildTopUser(users[2], 3, 50),
        ],
      ),
    );
  }

  Widget _buildTopUser(Map<String, dynamic> user, int rank, double size) {
    final colors = [AppColors.primary, Colors.grey.shade400, Colors.orange.shade700];
    final medals = ['', '', ''];

    return Column(
      children: [
        Text(medals[rank - 1],
            style: const TextStyle(fontSize: 24)),
        const SizedBox(height: 4),
        CircleAvatar(
          radius: size / 2,
          backgroundColor: colors[rank - 1].withValues(alpha: 0.3),
          child: Text(
            (user['nickname'] as String? ?? '?')[0].toUpperCase(),
            style: TextStyle(
              color: colors[rank - 1],
              fontSize: size * 0.4,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          user['nickname'] as String? ?? '트레이더',
          style: TextStyle(
              color: AppColors.textPrimary,
              fontSize: 13,
              fontWeight: FontWeight.w600),
          overflow: TextOverflow.ellipsis,
        ),
        const SizedBox(height: 2),
        Text(
          Formatters.largeAmount(
              (user['balance'] as num?)?.toDouble() ?? 0),
          style: TextStyle(
            color: colors[rank - 1],
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  Widget _buildUserTile(Map<String, dynamic> user, int rank) {
    final balance = (user['balance'] as num?)?.toDouble() ?? 0;
    final pnl = balance - 100000000; // 초기 1억 대비
    final pnlRate = (pnl / 100000000) * 100;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          // 순위
          SizedBox(
            width: 32,
            child: Text(
              '$rank',
              style: TextStyle(
                color: rank <= 3 ? AppColors.primary : AppColors.textMuted,
                fontSize: 14,
                fontWeight: rank <= 3 ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ),

          // 프로필
          CircleAvatar(
            radius: 18,
            backgroundColor: AppColors.surfaceLight,
            child: Text(
              (user['nickname'] as String? ?? '?')[0].toUpperCase(),
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(width: 12),

          // 닉네임
          Expanded(
            child: Text(
              user['nickname'] as String? ?? '트레이더',
              style: TextStyle(
                  color: AppColors.textPrimary, fontSize: 14),
            ),
          ),

          // 총 자산
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(Formatters.largeAmount(balance),
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 14,
                      fontWeight: FontWeight.w600)),
              Text(
                Formatters.percent(pnlRate),
                style: TextStyle(
                  color: pnl >= 0 ? AppColors.priceUp : AppColors.priceDown,
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
