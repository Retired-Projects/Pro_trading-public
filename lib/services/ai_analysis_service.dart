import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/portfolio.dart';
import '../models/trade.dart';
import '../core/config/supabase_config.dart';

class AiAnalysisService {
  static const _functionUrl =
      '${SupabaseConfig.url}/functions/v1/analyze-investment';

  Future<String> analyze({
    required Portfolio portfolio,
    required List<TradeLog> tradeLogs,
  }) async {
    final session = Supabase.instance.client.auth.currentSession;
    if (session == null) throw Exception('로그인이 필요합니다');

    final body = {
      'portfolio': {
        'balance': portfolio.balance,
        'total_asset': portfolio.totalAsset,
        'total_evaluation': portfolio.totalEvaluation,
        'total_pnl': portfolio.totalPnl,
        'holdings': portfolio.holdings
            .map((h) => {
                  'stock_code': h.stockCode,
                  'stock_name': h.stockName,
                  'quantity': h.quantity,
                  'avg_price': h.avgPrice,
                  'current_price': h.currentPrice,
                })
            .toList(),
      },
      'trade_logs': tradeLogs
          .map((t) => {
                'stock_code': t.stockCode,
                'stock_name': t.stockName,
                'side': t.side.name,
                'price': t.price,
                'quantity': t.quantity,
                'fee': t.fee,
                'tax': t.tax,
                'executed_at': t.executedAt.toIso8601String(),
              })
          .toList(),
    };

    final http.Response response;
    try {
      response = await http
          .post(
            Uri.parse(_functionUrl),
            headers: {
              'Authorization': 'Bearer ${session.accessToken}',
              'Content-Type': 'application/json',
              'apikey': SupabaseConfig.anonKey,
            },
            body: jsonEncode(body),
          )
          .timeout(const Duration(seconds: 30));
    } on TimeoutException {
      throw Exception('분석 요청 시간이 초과되었습니다. 잠시 후 다시 시도해주세요.');
    } on http.ClientException catch (e) {
      throw Exception('네트워크 오류가 발생했습니다: ${e.message}');
    }

    final data = jsonDecode(utf8.decode(response.bodyBytes));

    if (response.statusCode != 200) {
      throw Exception(data['error'] ?? '분석에 실패했습니다 (${response.statusCode})');
    }

    return data['analysis'] as String;
  }
}
