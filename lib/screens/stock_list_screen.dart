import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/formatters.dart';
import '../models/stock.dart';
import '../providers/market_providers.dart';
import '../providers/portfolio_providers.dart';
import '../providers/service_providers.dart';
import '../providers/settings_providers.dart';
import '../widgets/market_status_bar.dart';
import 'trading_screen.dart';

class StockListScreen extends ConsumerStatefulWidget {
  const StockListScreen({super.key});

  @override
  ConsumerState<StockListScreen> createState() => _StockListScreenState();
}

class _StockListScreenState extends ConsumerState<StockListScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  bool _isSearching = false;
  _SortType _sortType = _SortType.marketCap;

  @override
  void dispose() {
    _searchController.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      ref.read(searchQueryProvider.notifier).state = query;
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(themeProvider);
    final marketTab = ref.watch(marketTabProvider);
    // 포트폴리오에서 바 표시에 필요한 3개 값만 선택 구독 (전체 holdings 변화에 반응 방지)
    final totalAsset = ref.watch(portfolioProvider.select((p) => p.totalAsset));
    final totalPnlRate = ref.watch(portfolioProvider.select((p) => p.totalPnlRate));
    final balance = ref.watch(portfolioProvider.select((p) => p.balance));

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: _isSearching ? _buildSearchField() : const Text('종목'),
        actions: [
          IconButton(
            icon: Icon(_isSearching ? Icons.close : Icons.search,
                color: AppColors.textPrimary),
            onPressed: () {
              setState(() {
                _isSearching = !_isSearching;
                if (!_isSearching) {
                  _searchController.clear();
                  ref.read(searchQueryProvider.notifier).state = '';
                }
              });
            },
          ),
        ],
      ),
      body: _isSearching && _searchController.text.isNotEmpty
          ? _buildSearchResults()
          : Column(
              children: [
                // 시장 현황
                const MarketStatusBar(),
                Divider(color: AppColors.divider, height: 1),

                // 고정 상단 영역
                Container(
                  color: AppColors.surface,
                  child: Column(
                    children: [
                      _buildPortfolioBar(totalAsset, totalPnlRate, balance),
                      _buildMarketTabs(marketTab),
                    ],
                  ),
                ),
                _buildSortFilters(),
                Divider(color: AppColors.divider, height: 1),

                // 종목 리스트
                Expanded(child: _buildStockList(marketTab)),
              ],
            ),
    );
  }

  // ── 포트폴리오 요약 바 ──
  Widget _buildPortfolioBar(double totalAsset, double pnlRate, double balance) {

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          // 총 자산 + 수익률
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('총 자산',
                    style:
                        TextStyle(color: AppColors.textMuted, fontSize: 10)),
                Text(Formatters.largeAmount(totalAsset),
                    style: TextStyle(
                        color: AppColors.textPrimary,
                        fontSize: 16,
                        fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          // 수익률
          Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text('수익률',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 10)),
              Text(
                Formatters.percent(pnlRate),
                style: TextStyle(
                  color: pnlRate >= 0 ? AppColors.priceUp : AppColors.priceDown,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          const SizedBox(width: 24),
          // 예수금
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text('예수금',
                  style: TextStyle(color: AppColors.textMuted, fontSize: 10)),
              Text(Formatters.largeAmount(balance),
                  style: TextStyle(
                      color: AppColors.textSecondary, fontSize: 13)),
            ],
          ),
        ],
      ),
    );
  }

  // ── 마켓 탭 ──
  Widget _buildMarketTabs(MarketTab current) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          _buildMarketChip('코스피', MarketTab.kospi, current),
          _buildMarketChip('코스닥', MarketTab.kosdaq, current),
          _buildMarketChip('미국', MarketTab.us, current),
          _buildMarketChip('코인', MarketTab.crypto, current),
        ],
      ),
    );
  }

  Widget _buildMarketChip(String label, MarketTab tab, MarketTab current) {
    final selected = tab == current;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => ref.read(marketTabProvider.notifier).state = tab,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? AppColors.primary : AppColors.surfaceLight,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? Colors.black : AppColors.textSecondary,
              fontSize: 13,
              fontWeight: selected ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  // ── 정렬 필터 ──
  Widget _buildSortFilters() {
    return Container(
      color: AppColors.background,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          _buildSortChip('시총', _SortType.marketCap),
          _buildSortChip('상승률', _SortType.gainers),
          _buildSortChip('하락률', _SortType.losers),
          _buildSortChip('거래량', _SortType.volume),
        ],
      ),
    );
  }

  Widget _buildSortChip(String label, _SortType type) {
    final selected = _sortType == type;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: GestureDetector(
        onTap: () => setState(() => _sortType = type),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: selected ? AppColors.primary : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? AppColors.primary : AppColors.textMuted,
              fontSize: 12,
              fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ),
      ),
    );
  }

  // ── 종목 리스트 ──
  Widget _buildStockList(MarketTab tab) {
    switch (tab) {
      case MarketTab.kospi:
        return _buildKrList(ref.watch(kospiListProvider));
      case MarketTab.kosdaq:
        return _buildKrList(ref.watch(kosdaqListProvider));
      case MarketTab.us:
        return _buildUsList();
      case MarketTab.crypto:
        return _buildCryptoList();
    }
  }

  Widget _buildKrList(AsyncValue<List<Map<String, String>>> stocksAsync) {
    final prices = ref.watch(priceStreamProvider).valueOrNull ?? {};

    return stocksAsync.when(
      loading: () => Center(
          child: CircularProgressIndicator(color: AppColors.primary)),
      error: (e, _) => Center(
          child: Text('로딩 실패', style: TextStyle(color: AppColors.textSecondary))),
      data: (stocks) {
        final sorted = _sortStocks(stocks, prices);
        return _buildList(sorted, prices);
      },
    );
  }

  Widget _buildUsList() {
    final stocks = ref.watch(usStockListProvider);
    final pricesAsync = ref.watch(usPriceProvider);
    final prices = pricesAsync.valueOrNull ?? {};

    final sorted = _sortStocks(stocks, prices);
    return _buildList(sorted, prices, currency: '\$');
  }

  Widget _buildCryptoList() {
    final cryptoListAsync = ref.watch(cryptoListProvider);
    final pricesAsync = ref.watch(cryptoPriceProvider);
    final prices = pricesAsync.valueOrNull ?? {};

    return cryptoListAsync.when(
      loading: () => Center(
          child: CircularProgressIndicator(color: AppColors.primary)),
      error: (_, _) => Center(
          child:
              Text('로딩 실패', style: TextStyle(color: AppColors.textSecondary))),
      data: (coins) {
        final sorted = _sortStocks(coins, prices);
        return _buildList(sorted, prices, isCrypto: true);
      },
    );
  }

  Widget _buildList(
      List<Map<String, String>> stocks, Map<String, StockPrice> prices,
      {String currency = '', bool isCrypto = false}) {
    return ListView.separated(
      itemCount: stocks.length,
      separatorBuilder: (_, _) =>
          Divider(color: AppColors.divider, height: 1),
      itemBuilder: (context, index) {
        final item = stocks[index];
        final code = item['code']!;
        final name = item['name']!;
        final market = item['market'] ?? '';
        final price = prices[code];
        return KeyedSubtree(
          key: ValueKey(code),
          child: _buildStockTile(code, name, market, price,
              rank: index + 1, currency: currency, isCrypto: isCrypto),
        );
      },
    );
  }

  // ── 검색 ──
  Widget _buildSearchField() {
    return TextField(
      controller: _searchController,
      autofocus: true,
      style: TextStyle(color: AppColors.textPrimary, fontSize: 16),
      decoration: InputDecoration(
        hintText: '종목명 또는 코드 검색',
        hintStyle: TextStyle(color: AppColors.textMuted),
        border: InputBorder.none,
      ),
      onChanged: _onSearchChanged,
    );
  }

  Widget _buildSearchResults() {
    final searchResults = ref.watch(searchResultsProvider);
    final searchPrices = ref.watch(searchPriceProvider).valueOrNull ?? {};
    final streamPrices = ref.watch(priceStreamProvider).valueOrNull ?? {};
    // 두 소스 합치기
    final prices = {...streamPrices, ...searchPrices};

    return searchResults.when(
      loading: () => Center(
          child: CircularProgressIndicator(color: AppColors.primary)),
      error: (_, _) => Center(
          child:
              Text('검색 실패', style: TextStyle(color: AppColors.textSecondary))),
      data: (results) {
        if (results.isEmpty) {
          return Center(
              child: Text('검색 결과 없음',
                  style: TextStyle(color: AppColors.textSecondary)));
        }
        return ListView.separated(
          itemCount: results.length,
          separatorBuilder: (_, _) =>
              Divider(color: AppColors.divider, height: 1),
          itemBuilder: (context, index) {
            final item = results[index];
            return KeyedSubtree(
              key: ValueKey(item['code']),
              child: _buildStockTile(
                  item['code']!, item['name']!, item['market'] ?? '',
                  prices[item['code']]),
            );
          },
        );
      },
    );
  }

  // ── 정렬 ──
  List<Map<String, String>> _sortStocks(
      List<Map<String, String>> stocks, Map<String, StockPrice> prices) {
    final sorted = List<Map<String, String>>.from(stocks);

    switch (_sortType) {
      case _SortType.marketCap:
        break; // 이미 시총순
      case _SortType.gainers:
        sorted.sort((a, b) {
          final pa = prices[a['code']]?.changeRate ?? 0;
          final pb = prices[b['code']]?.changeRate ?? 0;
          return pb.compareTo(pa);
        });
      case _SortType.losers:
        sorted.sort((a, b) {
          final pa = prices[a['code']]?.changeRate ?? 0;
          final pb = prices[b['code']]?.changeRate ?? 0;
          return pa.compareTo(pb);
        });
      case _SortType.volume:
        sorted.sort((a, b) {
          final va = prices[a['code']]?.volume ?? 0;
          final vb = prices[b['code']]?.volume ?? 0;
          return vb.compareTo(va);
        });
    }
    return sorted;
  }

  // ── 종목 타일 ──
  Widget _buildStockTile(
      String code, String name, String market, StockPrice? price,
      {int? rank, String currency = '', bool isCrypto = false}) {
    final currentPrice = price?.currentPrice ?? 0;
    final changeRate = price?.changeRate ?? 0.0;
    final isUp = (price?.changeAmount ?? 0) > 0;
    final isDown = (price?.changeAmount ?? 0) < 0;

    final color = isUp
        ? AppColors.priceUp
        : isDown
            ? AppColors.priceDown
            : AppColors.priceNeutral;

    String marketLabel = '';
    if (market == 'KOSPI') marketLabel = '코스피';
    if (market == 'KOSDAQ') marketLabel = '코스닥';
    if (market == 'NASDAQ' || market == 'NYSE') marketLabel = market;
    if (market == 'CRYPTO') marketLabel = '코인';

    return InkWell(
      onTap: () {
        HapticFeedback.lightImpact();
        ref
            .read(mockDataServiceProvider)
            .registerStock(code, name, price: currentPrice);

        Navigator.of(context).push(
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) => TradingScreen(
              stock: Stock(code: code, name: name, basePrice: currentPrice),
            ),
            transitionsBuilder: (context, animation, secondaryAnimation, child) {
              return SlideTransition(
                position: Tween<Offset>(
                  begin: const Offset(1, 0),
                  end: Offset.zero,
                ).animate(CurvedAnimation(
                  parent: animation,
                  curve: Curves.easeOutCubic,
                )),
                child: child,
              );
            },
            transitionDuration: const Duration(milliseconds: 300),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        child: Row(
          children: [
            if (rank != null)
              SizedBox(
                width: 26,
                child: Text(
                  '$rank',
                  style: TextStyle(
                    color: rank <= 3
                        ? AppColors.primary
                        : AppColors.textMuted,
                    fontSize: 12,
                    fontWeight:
                        rank <= 3 ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),

            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 14,
                          fontWeight: FontWeight.w500),
                      overflow: TextOverflow.ellipsis),
                  Row(
                    children: [
                      Text(code,
                          style: TextStyle(
                              color: AppColors.textMuted, fontSize: 10)),
                      if (marketLabel.isNotEmpty) ...[
                        const SizedBox(width: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceLight,
                            borderRadius: BorderRadius.circular(3),
                          ),
                          child: Text(marketLabel,
                              style: TextStyle(
                                  color: AppColors.textMuted, fontSize: 9)),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),

            Expanded(
              flex: 2,
              child: Text(
                currentPrice > 0
                    ? '$currency${isCrypto ? Formatters.amount(currentPrice) : Formatters.price(currentPrice)}'
                    : '-',
                style: TextStyle(
                    color: color,
                    fontSize: 13,
                    fontWeight: FontWeight.w600),
                textAlign: TextAlign.right,
              ),
            ),

            const SizedBox(width: 8),

            Container(
              width: 68,
              padding: const EdgeInsets.symmetric(vertical: 5),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(4),
              ),
              alignment: Alignment.center,
              child: Text(
                currentPrice > 0 ? Formatters.percent(changeRate) : '-',
                style: TextStyle(
                    color: color,
                    fontSize: 12,
                    fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum _SortType { marketCap, gainers, losers, volume }
