import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../core/theme/app_colors.dart';
import '../core/constants/app_constants.dart';
import '../core/utils/formatters.dart';
import '../providers/portfolio_providers.dart';
import '../providers/ai_analysis_provider.dart';
import '../providers/settings_providers.dart';
import '../services/supabase_service.dart';

const _kMinTrades = 3;

class AiReportScreen extends ConsumerStatefulWidget {
  const AiReportScreen({super.key});

  @override
  ConsumerState<AiReportScreen> createState() => _AiReportScreenState();
}

class _AiReportScreenState extends ConsumerState<AiReportScreen> {
  /// null = 오늘(현재 생성/캐시된 리포트), String = 과거 날짜
  String? _selectedDate;

  /// _parseSections 결과 캐시 — 동일 리포트 텍스트 반복 파싱 방지
  final _parsedCache = <String, List<(String, String)>>{};

  @override
  Widget build(BuildContext context) {
    ref.watch(themeProvider);
    final tradeLogs = ref.watch(tradeLogsProvider);
    final portfolio = ref.watch(portfolioProvider);
    final analysisState = ref.watch(aiAnalysisProvider);
    final historyAsync = ref.watch(aiReportsHistoryProvider);

    final tradeCount = tradeLogs.length;
    final hasEnough = tradeCount >= _kMinTrades;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('AI 모의 투자 리포트'),
        backgroundColor: AppColors.surface,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(32),
          child: Container(
            width: double.infinity,
            color: Colors.red.shade900.withValues(alpha: 0.25),
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Text(
              '⚠️  이 리포트는 모의 투자용입니다. 실제 투자에 활용하지 마세요.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.red.shade300,
                fontSize: 11,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
      ),
      body: historyAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, __) => _buildBody(
          context, analysisState, portfolio, tradeLogs, hasEnough, tradeCount, [],
        ),
        data: (history) => _buildBody(
          context, analysisState, portfolio, tradeLogs, hasEnough, tradeCount, history,
        ),
      ),
    );
  }

  Widget _buildBody(
    BuildContext context,
    AiAnalysisState analysisState,
    portfolio,
    tradeLogs,
    bool hasEnough,
    int tradeCount,
    List<AiReport> history,
  ) {
    final today = _todayStr();

    // 선택된 날짜의 리포트 결정
    AiReport? selectedHistoryReport;
    bool isViewingToday = _selectedDate == null || _selectedDate == today;

    if (!isViewingToday && _selectedDate != null) {
      selectedHistoryReport = history.where((r) => r.reportDate == _selectedDate).firstOrNull;
    }

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // 상단 요약 카드
        _buildSummaryCard(portfolio, tradeCount),

        // 날짜 탭 (히스토리가 있을 때만)
        if (history.isNotEmpty) ...[
          const SizedBox(height: 12),
          _buildDateTabs(history, today),
        ],

        const SizedBox(height: 12),

        // 리포트 본문
        if (isViewingToday) ...[
          // 오늘 리포트 (기존 로직)
          if (analysisState.isLoading)
            _buildLoadingCard()
          else if (analysisState.result != null)
            _buildReportCard(analysisState.result!, analysisState.analyzedToday)
          else if (analysisState.error != null)
            _buildErrorCard(analysisState.error!)
          else
            _buildEmptyCard(context, hasEnough, tradeCount, portfolio, tradeLogs),

          const SizedBox(height: 20),

          if (!analysisState.isLoading && analysisState.error != null && hasEnough)
            _buildAnalyzeButton(context, portfolio, tradeLogs),
        ] else ...[
          // 과거 날짜 리포트
          if (selectedHistoryReport != null)
            _buildHistoryReportCard(selectedHistoryReport)
          else
            _buildNotFoundCard(),
        ],
      ],
    );
  }

  Widget _buildDateTabs(List<AiReport> history, String today) {
    // '오늘' 탭 + 과거 날짜들
    final dates = <String>['오늘'];
    for (final r in history) {
      if (r.reportDate != today) dates.add(r.reportDate);
    }

    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: dates.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final d = dates[i];
          final isToday = d == '오늘';
          final isSelected = isToday
              ? (_selectedDate == null || _selectedDate == today)
              : _selectedDate == d;

          String label;
          if (isToday) {
            label = '오늘';
          } else {
            final dt = DateTime.parse(d);
            label = DateFormat('M/d').format(dt);
          }

          return GestureDetector(
            onTap: () => setState(() {
              _selectedDate = isToday ? null : d;
            }),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: isSelected ? const Color(0xFF6C63FF) : AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: isSelected
                      ? const Color(0xFF6C63FF)
                      : AppColors.divider,
                ),
              ),
              child: Text(
                label,
                style: TextStyle(
                  color: isSelected ? Colors.white : AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight:
                      isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildHistoryReportCard(AiReport report) {
    final dt = DateTime.parse(report.reportDate);
    final dateLabel = DateFormat('yyyy년 M월 d일').format(dt);
    final sections = _parseSections(report.content);
    final isUp = report.totalReturn >= 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 헤더
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF6C63FF),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          ),
          child: Row(
            children: [
              const Text(
                'AI 모의 투자 리포트',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    dateLabel,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 11,
                    ),
                  ),
                  Text(
                    '${isUp ? "+" : ""}${report.totalReturn.toStringAsFixed(2)}%  거래 ${report.tradeCount}회',
                    style: TextStyle(
                      color: isUp
                          ? Colors.greenAccent.withValues(alpha: 0.9)
                          : Colors.redAccent.withValues(alpha: 0.9),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),

        // 섹션
        if (sections.isNotEmpty)
          ...sections.map((s) => _buildSection(s.$1, s.$2))
        else
          Container(
            padding: const EdgeInsets.all(16),
            color: AppColors.surface,
            child: Text(
              report.content,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                height: 1.7,
              ),
            ),
          ),

        Container(
          height: 12,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius:
                const BorderRadius.vertical(bottom: Radius.circular(12)),
          ),
        ),
      ],
    );
  }

  Widget _buildNotFoundCard() {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: Text(
        '해당 날짜의 리포트를 찾을 수 없습니다.',
        style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
      ),
    );
  }

  // ─── 기존 위젯들 (오늘 탭) ───

  Widget _buildSummaryCard(portfolio, int tradeCount) {
    final totalReturn =
        ((portfolio.totalAsset - AppConstants.initialBalance) /
                AppConstants.initialBalance) *
            100;
    final isUp = totalReturn >= 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text(
                '투자 현황',
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                ),
              ),
              const Spacer(),
              Text(
                '총 거래 ${tradeCount}회',
                style: TextStyle(
                  color: AppColors.textMuted,
                  fontSize: 12,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '${Formatters.largeAmount(portfolio.totalAsset)}원',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(width: 10),
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  '${isUp ? "+" : ""}${totalReturn.toStringAsFixed(2)}%',
                  style: TextStyle(
                    color: isUp ? AppColors.priceUp : AppColors.priceDown,
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _buildMiniStat('보유 종목', '${portfolio.holdings.length}개'),
              _buildDivider(),
              _buildMiniStat('예수금',
                  '${Formatters.largeAmount(portfolio.balance)}원'),
              _buildDivider(),
              _buildMiniStat(
                '평가손익',
                '${portfolio.totalPnl >= 0 ? "+" : ""}${Formatters.largeAmount(portfolio.totalPnl)}원',
                color: portfolio.totalPnl >= 0
                    ? AppColors.priceUp
                    : AppColors.priceDown,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildMiniStat(String label, String value, {Color? color}) {
    return Expanded(
      child: Column(
        children: [
          Text(label,
              style: TextStyle(color: AppColors.textMuted, fontSize: 10)),
          const SizedBox(height: 3),
          Text(
            value,
            style: TextStyle(
              color: color ?? AppColors.textPrimary,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildDivider() =>
      Container(width: 1, height: 32, color: AppColors.divider);

  Widget _buildLoadingCard() {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 60),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
      ),
      alignment: Alignment.center,
      child: Column(
        children: [
          SizedBox(
            width: 32,
            height: 32,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: const Color(0xFF6C63FF),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'AI가 거래 내역을 분석하고 있습니다',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '최대 10초 정도 소요됩니다',
            style: TextStyle(
              color: AppColors.textMuted,
              fontSize: 11,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReportCard(String result, bool analyzedToday) {
    final today = DateFormat('yyyy년 M월 d일').format(DateTime.now());
    final sections = _parseSections(result);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: const Color(0xFF6C63FF),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
          ),
          child: Row(
            children: [
              const Text(
                'AI 모의 투자 리포트',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const Spacer(),
              Text(today,
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.8),
                  fontSize: 11,
                ),
              ),
              if (analyzedToday) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    '오늘 완료',
                    style: TextStyle(color: Colors.white, fontSize: 9),
                  ),
                ),
              ],
            ],
          ),
        ),

        if (sections.isNotEmpty)
          ...sections.map((s) => _buildSection(s.$1, s.$2))
        else
          Container(
            padding: const EdgeInsets.all(16),
            color: AppColors.surface,
            child: Text(
              result,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                height: 1.7,
              ),
            ),
          ),

        Container(
          height: 12,
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius:
                const BorderRadius.vertical(bottom: Radius.circular(12)),
          ),
        ),

        const SizedBox(height: 8),

        if (analyzedToday)
          Center(
            child: Text(
              '리포트는 하루 1회만 발급됩니다',
              style: TextStyle(color: AppColors.textMuted, fontSize: 11),
            ),
          ),
      ],
    );
  }

  List<(String, String)> _parseSections(String text) {
    // 캐시 히트 시 재파싱 생략
    if (_parsedCache.containsKey(text)) return _parsedCache[text]!;

    final result = <(String, String)>[];
    final lines = text.split('\n');
    String currentTitle = '';
    final currentBody = StringBuffer();

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
        if (currentTitle.isNotEmpty) {
          result.add((currentTitle, currentBody.toString().trim()));
          currentBody.clear();
        }
        currentTitle = trimmed.substring(1, trimmed.length - 1);
      } else {
        if (currentTitle.isNotEmpty) {
          currentBody.writeln(line);
        }
      }
    }
    if (currentTitle.isNotEmpty) {
      result.add((currentTitle, currentBody.toString().trim()));
    }

    _parsedCache[text] = result;
    return result;
  }

  Widget _buildSection(String title, String body) {
    return Container(
      color: AppColors.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Divider(color: AppColors.divider, height: 1),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 6),
            child: Text(
              title,
              style: const TextStyle(
                color: Color(0xFF6C63FF),
                fontSize: 12,
                fontWeight: FontWeight.bold,
                letterSpacing: 0.5,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: Text(
              body,
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 13,
                height: 1.7,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard(String error) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.priceDown.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.warning_amber_rounded,
              color: AppColors.priceDown, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              error,
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyCard(
    BuildContext context,
    bool hasEnough,
    int tradeCount,
    portfolio,
    tradeLogs,
  ) {
    if (!hasEnough) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 48, horizontal: 24),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          children: [
            Icon(Icons.bar_chart, color: AppColors.textMuted, size: 40),
            const SizedBox(height: 16),
            Text(
              '거래 ${_kMinTrades}회 이상 필요',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '최소 ${_kMinTrades}회 이상 거래해야\nAI 리포트를 받을 수 있습니다',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 13,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: tradeCount / _kMinTrades,
                backgroundColor: AppColors.surfaceLight,
                color: const Color(0xFF6C63FF),
                minHeight: 6,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '$tradeCount / $_kMinTrades 회',
              style: TextStyle(
                color: AppColors.textMuted,
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    }
    return _buildAnalyzeButton(context, portfolio, tradeLogs);
  }

  Widget _buildAnalyzeButton(BuildContext context, portfolio, tradeLogs) {
    return GestureDetector(
      onTap: () =>
          ref.read(aiAnalysisProvider.notifier).analyze(portfolio, tradeLogs),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFF6C63FF), Color(0xFF9C63FF)],
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: Column(
          children: [
            const Text(
              'AI 리포트 발급',
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              '하루 1회 무료 발급',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.75),
                fontSize: 11,
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _todayStr() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';
  }
}
