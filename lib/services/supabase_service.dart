import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/portfolio.dart';
import '../models/trade.dart';
import '../core/constants/app_constants.dart';

/// 토큰을 SHA-256 해시로 변환하여 내부 이메일 생성
/// 표시되는 토큰으로 이메일을 역추적할 수 없도록 보호
String _tokenToEmail(String token) {
  final bytes = utf8.encode(token);
  final hash = sha256.convert(bytes).toString().substring(0, 24);
  return '$hash@protrading.app';
}

class AiReport {
  final String reportDate;
  final String content;
  final int tradeCount;
  final double totalAsset;
  final double totalReturn;

  const AiReport({
    required this.reportDate,
    required this.content,
    required this.tradeCount,
    required this.totalAsset,
    required this.totalReturn,
  });

  factory AiReport.fromMap(Map<String, dynamic> map) => AiReport(
        reportDate: map['report_date'] as String,
        content: map['content'] as String,
        tradeCount: (map['trade_count'] as num).toInt(),
        totalAsset: (map['total_asset'] as num).toDouble(),
        totalReturn: (map['total_return'] as num).toDouble(),
      );
}

/// Supabase CRUD 서비스
/// 사용자 데이터(잔고, 보유종목, 주문, 체결이력)를 관리
class SupabaseService {
  final SupabaseClient _client = Supabase.instance.client;

  // ─── 프로필 (잔고) ───

  /// 사용자 프로필 조회 또는 생성
  Future<Map<String, dynamic>> getOrCreateProfile(String userId) async {
    final existing = await _client
        .from('profiles')
        .select()
        .eq('user_id', userId)
        .maybeSingle();

    if (existing != null) return existing;

    // 닉네임을 auth user_metadata에서 가져오기
    final user = _client.auth.currentUser;
    final nickname =
        user?.userMetadata?['nickname'] as String? ?? '트레이더';

    final newProfile = {
      'user_id': userId,
      'nickname': nickname,
      'balance': AppConstants.initialBalance,
    };

    final result =
        await _client.from('profiles').insert(newProfile).select().single();
    return result;
  }

  /// 잔고 업데이트
  Future<void> updateBalance(String userId, double newBalance) async {
    await _client
        .from('profiles')
        .update({'balance': newBalance, 'updated_at': DateTime.now().toIso8601String()})
        .eq('user_id', userId);
  }

  /// 총 자산 업데이트 (예수금 + 보유종목 매입금액)
  Future<void> updateTotalAsset(String userId, double totalAsset) async {
    await _client
        .from('profiles')
        .update({'total_asset': totalAsset, 'updated_at': DateTime.now().toIso8601String()})
        .eq('user_id', userId);
  }

  /// 마지막 접속일 업데이트
  Future<void> updateLastLoginAt(String userId) async {
    await _client
        .from('profiles')
        .update({'last_login_at': DateTime.now().toIso8601String()})
        .eq('user_id', userId);
  }

  // ─── 보유 종목 ───

  /// 보유 종목 전체 조회
  Future<List<Holding>> getHoldings(String userId) async {
    final data =
        await _client.from('holdings').select().eq('user_id', userId);

    return (data as List)
        .map((json) => Holding.fromJson(json))
        .where((h) => h.quantity > 0)
        .toList();
  }

  /// 보유 종목 추가/업데이트 (매수 시)
  Future<void> upsertHolding(
      String userId, String stockCode, String stockName, double quantity, double avgPrice) async {
    await _client.from('holdings').upsert(
      {
        'user_id': userId,
        'stock_code': stockCode,
        'stock_name': stockName,
        'quantity': quantity,
        'avg_price': avgPrice,
        'updated_at': DateTime.now().toIso8601String(),
      },
      onConflict: 'user_id,stock_code',
    );
  }

  /// 보유 종목 삭제 (수량 0)
  Future<void> deleteHolding(String userId, String stockCode) async {
    await _client
        .from('holdings')
        .delete()
        .eq('user_id', userId)
        .eq('stock_code', stockCode);
  }

  // ─── 주문 ───

  /// 주문 저장
  Future<void> insertOrder(String userId, Order order) async {
    await _client.from('orders').insert({
      'id': order.id,
      'user_id': userId,
      'stock_code': order.stockCode,
      'stock_name': order.stockName,
      'type': order.type.name,
      'side': order.side.name,
      'price': order.price,
      'quantity': order.quantity,
      'filled_quantity': order.filledQuantity,
      'status': order.status.name,
      'created_at': order.createdAt.toIso8601String(),
      'filled_at': order.filledAt?.toIso8601String(),
    });
  }

  /// 주문 상태 업데이트
  Future<void> updateOrderStatus(String orderId, OrderStatus status,
      {double? filledQuantity, DateTime? filledAt}) async {
    final updates = <String, dynamic>{'status': status.name};
    if (filledQuantity != null) updates['filled_quantity'] = filledQuantity;
    if (filledAt != null) updates['filled_at'] = filledAt.toIso8601String();

    await _client.from('orders').update(updates).eq('id', orderId);
  }

  /// 미체결 주문 조회
  Future<List<Order>> getPendingOrders(String userId) async {
    final data = await _client
        .from('orders')
        .select()
        .eq('user_id', userId)
        .eq('status', 'pending')
        .order('created_at', ascending: false);

    return (data as List).map((json) => Order.fromJson(json)).toList();
  }

  // ─── 체결 이력 ───

  /// 체결 이력 저장
  Future<void> insertTradeLog(String userId, TradeLog log) async {
    await _client.from('trade_logs').insert({
      'id': log.id,
      'user_id': userId,
      'order_id': log.orderId,
      'stock_code': log.stockCode,
      'stock_name': log.stockName,
      'side': log.side.name,
      'price': log.price,
      'quantity': log.quantity,
      'fee': log.fee,
      'tax': log.tax,
      'executed_at': log.executedAt.toIso8601String(),
    });
  }

  /// 체결 이력 조회
  Future<List<TradeLog>> getTradeLogs(String userId, {int limit = 50}) async {
    final data = await _client
        .from('trade_logs')
        .select()
        .eq('user_id', userId)
        .order('executed_at', ascending: false)
        .limit(limit);

    return (data as List).map((json) => TradeLog.fromJson(json)).toList();
  }

  // ─── 관심종목 ───

  /// 관심종목 조회
  Future<List<Map<String, String>>> getWatchlist(String userId) async {
    final data = await _client
        .from('watchlist')
        .select()
        .eq('user_id', userId)
        .order('created_at', ascending: false);

    return (data as List)
        .map((json) => {
              'code': json['stock_code'] as String,
              'name': json['stock_name'] as String,
              'market': json['market'] as String,
            })
        .toList();
  }

  /// 관심종목 추가
  Future<void> addToWatchlist(
      String userId, String stockCode, String stockName, String market) async {
    await _client.from('watchlist').upsert(
      {
        'user_id': userId,
        'stock_code': stockCode,
        'stock_name': stockName,
        'market': market,
      },
      onConflict: 'user_id,stock_code',
    );
  }

  /// 관심종목 삭제
  Future<void> removeFromWatchlist(String userId, String stockCode) async {
    await _client
        .from('watchlist')
        .delete()
        .eq('user_id', userId)
        .eq('stock_code', stockCode);
  }

  /// 관심종목 여부 확인
  Future<bool> isInWatchlist(String userId, String stockCode) async {
    final data = await _client
        .from('watchlist')
        .select('id')
        .eq('user_id', userId)
        .eq('stock_code', stockCode)
        .maybeSingle();
    return data != null;
  }

  // ─── 인증 ───

  // ─── 토큰 인증 ───

  /// 토큰으로 새 계정 생성 (최초 1회)
  /// 토큰이 곧 비밀번호 — 잃어버리면 복구 불가
  Future<String> signUpWithToken(String token, {String nickname = '트레이더'}) async {
    final email = _tokenToEmail(token);
    final response = await _client.auth.signUp(
      email: email,
      password: token,
      data: {'nickname': nickname},
    );
    final user = response.user;
    if (user == null) throw Exception('계정 생성에 실패했습니다.');
    return user.id;
  }

  /// 토큰으로 기존 계정 로그인
  Future<String> signInWithToken(String token) async {
    final email = _tokenToEmail(token);
    final response = await _client.auth.signInWithPassword(
      email: email,
      password: token,
    );
    final user = response.user;
    if (user == null) throw Exception('로그인에 실패했습니다.');
    return user.id;
  }

  /// 로그아웃
  Future<void> signOut() async {
    await _client.auth.signOut();
  }

  /// 현재 사용자 ID
  String? get currentUserId => _client.auth.currentUser?.id;

  // ─── AI 리포트 ───

  /// 내 AI 리포트 전체 조회 (최신순)
  Future<List<AiReport>> getAiReports(String userId) async {
    final rows = await _client
        .from('ai_reports')
        .select('report_date, content, trade_count, total_asset, total_return')
        .eq('user_id', userId)
        .order('report_date', ascending: false);
    return (rows as List).map((r) => AiReport.fromMap(r)).toList();
  }
}
