import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/theme/app_colors.dart';
import '../core/utils/formatters.dart';
import '../models/stock.dart';
import '../models/trade.dart';
import '../providers/market_providers.dart';
import '../providers/portfolio_providers.dart';
import '../providers/service_providers.dart';
import '../providers/settings_providers.dart';
import '../providers/watchlist_provider.dart';
import '../core/constants/app_constants.dart';
import '../services/trading_engine.dart';
import '../services/yahoo_finance_service.dart';
import '../widgets/candle_chart.dart';
import '../widgets/order_book_widget.dart';

class TradingScreen extends ConsumerStatefulWidget {
  final Stock stock;

  const TradingScreen({super.key, required this.stock});

  @override
  ConsumerState<TradingScreen> createState() => _TradingScreenState();
}

class _TradingScreenState extends ConsumerState<TradingScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;
  OrderSide _orderSide = OrderSide.buy;
  OrderType _orderType = OrderType.market;
  double _quantity = 0;
  double _limitPrice = 0;
  final _quantityController = TextEditingController();
  final _priceController = TextEditingController();

  /// 현재 종목이 암호화폐인지 확인
  bool get _isCrypto {
    final code = widget.stock.code;
    return !YahooFinanceService.usStocks.any((s) => s['code'] == code) &&
        !RegExp(r'^\d{6}$').hasMatch(code);
  }

  /// 코인: 소수점, 주식: 정수 포맷
  String _formatQty(double qty) {
    if (_isCrypto) {
      if (qty == qty.truncateToDouble() && qty < 1e8) {
        return qty.toInt().toString();
      }
      String s = qty.toStringAsFixed(8);
      s = s.replaceAll(RegExp(r'0+$'), '').replaceAll(RegExp(r'\.$'), '');
      return s;
    }
    return qty.toInt().toString();
  }

  /// 코인 수량 8자리 절사
  double _truncateCryptoQty(double qty) =>
      (qty * 1e8).floorToDouble() / 1e8;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _limitPrice = widget.stock.basePrice;
    _priceController.text = Formatters.price(_limitPrice);

    // 폴링 서비스에 포커스 종목 설정 + 폴링 대상 추가 + 즉시 1회 폴링
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final polling = ref.read(pollingServiceProvider);
      polling.addStockCode(widget.stock.code);
      polling.setFocusedStock(widget.stock.code);
      polling.triggerPoll(); // 검색 진입 시 즉시 시세/호가 반영
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _quantityController.dispose();
    _priceController.dispose();
    // 포커스 해제: 화면 이탈 후 집중 폴링 중단
    ref.read(pollingServiceProvider).setFocusedStock(null);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(themeProvider);
    final price = ref.watch(stockPriceProvider(widget.stock.code));
    final candlesAsync = ref.watch(candleDataProvider(widget.stock.code));
    final candles = candlesAsync.valueOrNull ?? [];
    final orderBook = ref.watch(orderBookStreamProvider).valueOrNull;
    final portfolio = ref.watch(portfolioProvider);

    final currentPrice = price?.currentPrice ?? widget.stock.basePrice;

    // 참고: PollingService._pollReal()에서 이미 모든 종목에 updateWithRealPrice 호출.
    // build()에서 중복 호출 불필요 — 제거.
    final previousClose = price?.previousClose ?? widget.stock.basePrice;
    final changeAmount = currentPrice - previousClose;
    final changeRate =
        previousClose != 0 ? (changeAmount / previousClose) * 100 : 0.0;
    final isUp = changeAmount > 0;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        backgroundColor: AppColors.surface,
        title: Column(
          children: [
            Text(widget.stock.name,
                style: TextStyle(fontSize: 16, color: AppColors.textPrimary)),
            Text(
              '${Formatters.price(currentPrice)}  ${Formatters.change(changeAmount)} (${Formatters.percent(changeRate)})',
              style: TextStyle(
                fontSize: 12,
                color: isUp ? AppColors.priceUp : AppColors.priceDown,
              ),
            ),
          ],
        ),
        centerTitle: true,
        actions: [
          _buildWatchlistButton(),
        ],
      ),
      body: Column(
        children: [
          // 차트 영역
          SizedBox(
            height: 250,
            child: CandleChartWidget(candles: candles),
          ),

          // 탭: 호가 / 주문
          Container(
            color: AppColors.surface,
            child: TabBar(
              controller: _tabController,
              indicatorColor: AppColors.primary,
              labelColor: AppColors.textPrimary,
              unselectedLabelColor: AppColors.textSecondary,
              tabs: const [
                Tab(text: '호가'),
                Tab(text: '주문'),
              ],
            ),
          ),

          // 탭 컨텐츠
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [
                // 호가창
                orderBook != null
                    ? OrderBookWidget(
                        orderBook: orderBook,
                        currentPrice: currentPrice,
                        previousClose: previousClose,
                        onPriceTap: (price) {
                          setState(() {
                            _limitPrice = price;
                            _priceController.text = Formatters.price(price);
                            _orderType = OrderType.limit;
                            _tabController.animateTo(1);
                          });
                        },
                      )
                    : Center(
                        child: CircularProgressIndicator(
                            color: AppColors.primary)),

                // 주문 패널
                _buildOrderPanel(currentPrice, portfolio),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOrderPanel(double currentPrice, portfolio) {
    final holdingMatch = portfolio.holdings
        .where((h) => h.stockCode == widget.stock.code);
    final holdingQty = holdingMatch.isNotEmpty ? holdingMatch.first.quantity : 0.0;
    final isBuy = _orderSide == OrderSide.buy;
    final sideColor = isBuy ? AppColors.priceUp : AppColors.priceDown;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // 매수/매도 토글
          Container(
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.divider),
            ),
            child: Row(
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _orderSide = OrderSide.buy),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: isBuy
                            ? AppColors.priceUp
                            : Colors.transparent,
                        borderRadius: const BorderRadius.horizontal(
                            left: Radius.circular(7)),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '매수',
                        style: TextStyle(
                          color: isBuy
                              ? Colors.white
                              : AppColors.textSecondary,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _orderSide = OrderSide.sell),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      decoration: BoxDecoration(
                        color: !isBuy
                            ? AppColors.priceDown
                            : Colors.transparent,
                        borderRadius: const BorderRadius.horizontal(
                            right: Radius.circular(7)),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '매도',
                        style: TextStyle(
                          color: !isBuy
                              ? Colors.white
                              : AppColors.textSecondary,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // 주문 유형
          Row(
            children: [
              _buildChip('시장가', _orderType == OrderType.market,
                  () => setState(() => _orderType = OrderType.market)),
              const SizedBox(width: 8),
              _buildChip('지정가', _orderType == OrderType.limit,
                  () => setState(() => _orderType = OrderType.limit)),
              const SizedBox(width: 8),
              _buildChip('손절', _orderType == OrderType.stopLoss,
                  () => setState(() {
                    _orderType = OrderType.stopLoss;
                    _orderSide = OrderSide.sell;
                  })),
              const SizedBox(width: 8),
              _buildChip('익절', _orderType == OrderType.takeProfit,
                  () => setState(() {
                    _orderType = OrderType.takeProfit;
                    _orderSide = OrderSide.sell;
                  })),
            ],
          ),
          const SizedBox(height: 12),

          // 가격 입력 (지정가/손절/익절)
          if (_orderType == OrderType.limit ||
              _orderType == OrderType.stopLoss ||
              _orderType == OrderType.takeProfit) ...[
            Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.divider),
              ),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () {
                      setState(() {
                        _limitPrice -= _getTickSize(_limitPrice);
                        _priceController.text = Formatters.price(_limitPrice);
                      });
                    },
                    icon: Icon(Icons.remove_circle,
                        color: AppColors.priceDown, size: 28),
                  ),
                  Expanded(
                    child: TextField(
                      controller: _priceController,
                      style: TextStyle(
                          color: AppColors.textPrimary,
                          fontSize: 18,
                          fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(vertical: 8),
                      ),
                      onChanged: (v) {
                        final parsed =
                            double.tryParse(v.replaceAll(',', ''));
                        if (parsed != null) _limitPrice = parsed;
                      },
                    ),
                  ),
                  IconButton(
                    onPressed: () {
                      setState(() {
                        _limitPrice += _getTickSize(_limitPrice);
                        _priceController.text = Formatters.price(_limitPrice);
                      });
                    },
                    icon: Icon(Icons.add_circle,
                        color: AppColors.priceUp, size: 28),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // 수량 입력 + 가용 정보
          Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: AppColors.divider),
                  ),
                  child: Row(
                    children: [
                      IconButton(
                        onPressed: _quantity > 0
                            ? () => setState(() {
                                  final step = _isCrypto ? 0.001 : 1.0;
                                  _quantity =
                                      (_quantity - step).clamp(0.0, double.infinity);
                                  if (_quantity < 1e-9) _quantity = 0.0;
                                  _quantityController.text = _formatQty(_quantity);
                                })
                            : null,
                        icon: Icon(Icons.remove_circle,
                            color: _quantity > 0
                                ? sideColor
                                : AppColors.textMuted,
                            size: 28),
                      ),
                      Expanded(
                        child: TextField(
                          controller: _quantityController,
                          style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 18,
                              fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                          keyboardType: _isCrypto
                              ? const TextInputType.numberWithOptions(decimal: true)
                              : TextInputType.number,
                          decoration: InputDecoration(
                            border: InputBorder.none,
                            contentPadding:
                                const EdgeInsets.symmetric(vertical: 8),
                            hintText: '수량',
                            hintStyle: TextStyle(
                                color: AppColors.textMuted,
                                fontSize: 16,
                                fontWeight: FontWeight.normal),
                          ),
                          onChanged: (v) {
                            setState(() {
                              _quantity = double.tryParse(v) ?? 0;
                            });
                          },
                        ),
                      ),
                      IconButton(
                        onPressed: () => setState(() {
                          final step = _isCrypto ? 0.001 : 1.0;
                          _quantity += step;
                          _quantityController.text = _formatQty(_quantity);
                        }),
                        icon: Icon(Icons.add_circle,
                            color: sideColor, size: 28),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    isBuy ? '구매가능' : '매도가능',
                    style: TextStyle(
                        color: AppColors.textMuted, fontSize: 10),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    isBuy
                        ? Formatters.largeAmount(
                            ref.read(portfolioProvider).availableBalance)
                        : '${_formatQty(holdingQty)}${_isCrypto ? '' : '주'}',
                    style: TextStyle(
                        color: AppColors.textSecondary,
                        fontSize: 13,
                        fontWeight: FontWeight.w600),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),

          // 퍼센트 수량 버튼
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [10, 25, 50, 100].map((pct) {
              return GestureDetector(
                onTap: () {
                  final price = _orderType == OrderType.market
                      ? currentPrice
                      : _limitPrice;
                  if (price <= 0) return;
                  double qty;
                  if (_orderSide == OrderSide.buy) {
                    final balance = ref.read(portfolioProvider).availableBalance;
                    final maxQty = balance / (price * (1 + AppConstants.tradingFeeRate));

                    qty = _isCrypto
                        ? _truncateCryptoQty(maxQty * pct / 100)
                        : (maxQty * pct / 100).floorToDouble();
                  } else {
                    final hMatch = ref.read(portfolioProvider).holdings
                        .where((h) => h.stockCode == widget.stock.code);
                    final holdQty = hMatch.isNotEmpty ? hMatch.first.quantity : 0.0;
                    qty = _isCrypto
                        ? _truncateCryptoQty(holdQty * pct / 100)
                        : (holdQty * pct / 100).floorToDouble();
                  }
                  setState(() {
                    _quantity = qty;
                    _quantityController.text = _formatQty(qty);
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: sideColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(
                        color: sideColor.withValues(alpha: 0.3)),
                  ),
                  child: Text('$pct%',
                      style: TextStyle(
                          color: sideColor,
                          fontSize: 12,
                          fontWeight: FontWeight.w500)),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 12),

          // 정보 표시
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.divider),
            ),
            child: Builder(builder: (_) {
              final orderPrice =
                  _orderType == OrderType.market ? currentPrice : _limitPrice;
              final totalAmount = orderPrice * _quantity;
              final fee = totalAmount * AppConstants.tradingFeeRate;
              final tax = _orderSide == OrderSide.sell
                  ? totalAmount * AppConstants.taxRate
                  : 0.0;
              final netAmount = _orderSide == OrderSide.buy
                  ? totalAmount + fee
                  : totalAmount - fee - tax;

              return Column(
                children: [
                  _buildInfoRow('주문가격', Formatters.price(orderPrice)),
                  const SizedBox(height: 4),
                  _buildInfoRow('주문수량', '${_formatQty(_quantity)}${_isCrypto ? '' : ' 주'}'),
                  const SizedBox(height: 4),
                  _buildInfoRow('주문금액', Formatters.price(totalAmount)),
                  const SizedBox(height: 4),
                  _buildInfoRow('수수료 (0.015%)', Formatters.price(fee)),
                  if (_orderSide == OrderSide.sell) ...[
                    const SizedBox(height: 4),
                    _buildInfoRow('세금 (0.23%)', Formatters.price(tax)),
                  ],
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Divider(color: AppColors.divider, height: 1),
                  ),
                  _buildInfoRow(
                      isBuy ? '총 결제금액' : '예상 수령액',
                      Formatters.price(netAmount),
                      bold: true),
                  const SizedBox(height: 4),
                  if (_orderSide == OrderSide.buy)
                    _buildInfoRow('가용잔고',
                        Formatters.largeAmount(ref.read(portfolioProvider).availableBalance)),
                  if (_orderSide == OrderSide.sell)
                    _buildInfoRow('보유수량', '${_formatQty(holdingQty)}${_isCrypto ? '' : ' 주'}'),
                ],
              );
            }),
          ),

          const SizedBox(height: 16),

          // 주문 버튼
          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: _quantity > 0 ? () => _showOrderConfirmDialog(currentPrice, holdingQty) : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: sideColor,
                disabledBackgroundColor: AppColors.surfaceLight,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10)),
                elevation: 0,
              ),
              child: Text(
                _orderSide == OrderSide.buy
                    ? '매수 주문'
                    : '매도 주문',
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Colors.white),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: selected ? AppColors.primary.withValues(alpha: 0.2) : AppColors.surfaceLight,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.divider,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? AppColors.primary : AppColors.textSecondary,
            fontSize: 13,
            fontWeight: selected ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value, {bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label,
              style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  fontWeight: bold ? FontWeight.w600 : FontWeight.normal)),
          Text(value,
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: bold ? 14 : 12,
                  fontWeight: bold ? FontWeight.bold : FontWeight.normal)),
        ],
      ),
    );
  }

  void _showOrderConfirmDialog(double currentPrice, double holdingQty) {
    final isBuy = _orderSide == OrderSide.buy;
    final sideText = isBuy ? '매수' : '매도';
    final sideColor = isBuy ? AppColors.priceUp : AppColors.priceDown;
    final isStopOrder = _orderType == OrderType.stopLoss ||
        _orderType == OrderType.takeProfit;
    final orderPrice =
        _orderType == OrderType.market ? currentPrice : _limitPrice;
    final totalAmount = orderPrice * _quantity;
    final fee = totalAmount * AppConstants.tradingFeeRate;
    final tax = isBuy ? 0.0 : totalAmount * AppConstants.taxRate;
    final netAmount = isBuy ? totalAmount + fee : totalAmount - fee - tax;

    String orderTypeLabel;
    switch (_orderType) {
      case OrderType.market:
        orderTypeLabel = '시장가';
      case OrderType.limit:
        orderTypeLabel = '지정가';
      case OrderType.stopLoss:
        orderTypeLabel = '손절 (지정가)';
      case OrderType.takeProfit:
        orderTypeLabel = '익절 (지정가)';
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Container(
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // 핸들 바
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: AppColors.textMuted,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // 제목
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: sideColor,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(sideText,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold)),
                ),
                const SizedBox(width: 8),
                Text('주문 확인',
                    style: TextStyle(
                        color: AppColors.textPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 16),

            // 손절/익절 안내 배너
            if (isStopOrder) ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                decoration: BoxDecoration(
                  color: (_orderType == OrderType.stopLoss
                          ? AppColors.priceDown
                          : AppColors.priceUp)
                      .withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: (_orderType == OrderType.stopLoss
                            ? AppColors.priceDown
                            : AppColors.priceUp)
                        .withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      _orderType == OrderType.stopLoss
                          ? Icons.trending_down
                          : Icons.trending_up,
                      size: 16,
                      color: _orderType == OrderType.stopLoss
                          ? AppColors.priceDown
                          : AppColors.priceUp,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _orderType == OrderType.stopLoss
                            ? '현재가가 ${Formatters.price(_limitPrice)}원 이하로 떨어지면 자동 매도합니다.'
                            : '현재가가 ${Formatters.price(_limitPrice)}원 이상으로 오르면 자동 매도합니다.',
                        style: TextStyle(
                          color: _orderType == OrderType.stopLoss
                              ? AppColors.priceDown
                              : AppColors.priceUp,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            // 주문 정보
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.background,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  _buildDialogRow('종목', widget.stock.name),
                  const SizedBox(height: 8),
                  _buildDialogRow('주문유형', orderTypeLabel),
                  const SizedBox(height: 8),
                  _buildDialogRow(
                    isStopOrder ? '트리거 가격' : '주문가격',
                    '${Formatters.price(orderPrice)}원',
                  ),
                  if (isStopOrder) ...[
                    const SizedBox(height: 8),
                    _buildDialogRow(
                      '현재가',
                      '${Formatters.price(currentPrice)}원',
                      valueColor: AppColors.textSecondary,
                    ),
                  ],
                  const SizedBox(height: 8),
                  _buildDialogRow('주문수량', '${_formatQty(_quantity)}${_isCrypto ? '' : ' 주'}'),
                  if (!isStopOrder) ...[
                    const SizedBox(height: 8),
                    _buildDialogRow('수수료 (0.015%)', '${Formatters.price(fee)}원'),
                    if (!isBuy) ...[
                      const SizedBox(height: 8),
                      _buildDialogRow('세금 (0.23%)', '${Formatters.price(tax)}원'),
                    ],
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Divider(color: AppColors.divider, height: 1),
                    ),
                    _buildDialogRow(
                        isBuy ? '총 결제금액' : '예상 수령액',
                        '${Formatters.price(netAmount)}원',
                        valueColor: sideColor, bold: true),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),

            // 버튼
            Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: 50,
                    child: OutlinedButton(
                      onPressed: () => Navigator.pop(context),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: AppColors.divider),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text('취소',
                          style: TextStyle(
                              color: AppColors.textSecondary,
                              fontSize: 15,
                              fontWeight: FontWeight.w600)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: SizedBox(
                    height: 50,
                    child: ElevatedButton(
                      onPressed: () async {
                        Navigator.pop(context);
                        await _placeOrder(currentPrice);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: sideColor,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text(
                        isStopOrder
                            ? (_orderType == OrderType.stopLoss ? '손절 등록' : '익절 등록')
                            : '$sideText 확인',
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ),
              ],
            ),

            SizedBox(height: MediaQuery.of(context).padding.bottom),
          ],
        ),
      ),
    );
  }

  Widget _buildDialogRow(String label, String value,
      {Color? valueColor, bool bold = false}) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: TextStyle(color: AppColors.textSecondary, fontSize: 13)),
        Text(value,
            style: TextStyle(
                color: valueColor ?? AppColors.textPrimary,
                fontSize: bold ? 16 : 13,
                fontWeight: bold ? FontWeight.bold : FontWeight.w500)),
      ],
    );
  }

  /// 현재 종목이 속한 시장이 열려있는지 확인
  bool _isCurrentMarketOpen() {
    final code = widget.stock.code;
    // 미국 주식 (AAPL, TSLA 등 알파벳 티커)
    if (YahooFinanceService.usStocks.any((s) => s['code'] == code)) {
      return AppConstants.isUsMarketOpen();
    }
    // 한국 주식: 코드가 6자리 숫자 (005930, 035720 등)
    if (RegExp(r'^\d{6}$').hasMatch(code)) {
      return AppConstants.isKrMarketOpen();
    }
    // 그 외 (BTC, ETH 등 암호화폐): 24시간 거래
    return true;
  }

  Future<void> _placeOrder(double currentPrice) async {
    // 장 마감 시 신규 주문 차단
    if (!_isCurrentMarketOpen()) {
      _showSnackBar('현재 장이 마감되어 주문이 불가합니다.', isError: true);
      return;
    }

    final engine = ref.read(tradingEngineProvider);
    final portfolio = ref.read(portfolioProvider);
    final holdingMatch = portfolio.holdings
        .where((h) => h.stockCode == widget.stock.code);
    final holdingQty = holdingMatch.isNotEmpty ? holdingMatch.first.quantity : 0.0;

    TradeResult result;

    if (_orderType == OrderType.market) {
      result = engine.placeMarketOrder(
        stockCode: widget.stock.code,
        stockName: widget.stock.name,
        side: _orderSide,
        quantity: _quantity,
        currentBalance: portfolio.availableBalance,
        currentHolding: holdingQty,
        overridePrice: _isCrypto ? currentPrice : null,
      );
    } else if (_orderType == OrderType.stopLoss ||
        _orderType == OrderType.takeProfit) {
      result = engine.placeStopOrder(
        stockCode: widget.stock.code,
        stockName: widget.stock.name,
        type: _orderType,
        triggerPrice: _limitPrice,
        quantity: _quantity,
        currentHolding: holdingQty,
      );
    } else {
      result = engine.placeLimitOrder(
        stockCode: widget.stock.code,
        stockName: widget.stock.name,
        side: _orderSide,
        limitPrice: _limitPrice,
        quantity: _quantity,
        currentBalance: portfolio.availableBalance,
        currentHolding: holdingQty,
        overridePrice: _isCrypto ? currentPrice : null,
      );
    }

    if (!result.isSuccess) {
      _showSnackBar(result.errorMessage ?? '주문 실패', isError: true);
      return;
    }

    final order = result.order!;
    await ref.read(ordersProvider.notifier).addOrder(order);

    if (result.isPending) {
      final typeLabel = _orderType == OrderType.stopLoss
          ? '손절'
          : _orderType == OrderType.takeProfit
              ? '익절'
              : '지정가';
      _showSnackBar('$typeLabel 주문 접수: ${Formatters.price(_limitPrice)} × ${_formatQty(_quantity)}${_isCrypto ? '' : '주'}');

      // 매수 지정가 주문 시 예수금 예약
      if (_orderSide == OrderSide.buy) {
        final totalAmount = _limitPrice * _quantity;
        final fee = totalAmount * AppConstants.tradingFeeRate;
        ref.read(portfolioProvider.notifier).reserveBalance(totalAmount + fee);
      }
    } else {
      // 체결 처리
      final tradeLog = result.tradeLog!;
      await ref.read(tradeLogsProvider.notifier).addLog(tradeLog);

      if (_orderSide == OrderSide.buy) {
        await ref.read(portfolioProvider.notifier).deductBalance(tradeLog.netAmount);
        await ref.read(portfolioProvider.notifier).addHolding(
              widget.stock.code,
              widget.stock.name,
              _quantity,
              tradeLog.price,
            );
      } else {
        await ref.read(portfolioProvider.notifier).addBalance(tradeLog.netAmount);
        await ref.read(portfolioProvider.notifier).removeHolding(
              widget.stock.code,
              _quantity,
            );
      }

      final sideText = _orderSide == OrderSide.buy ? '매수' : '매도';
      HapticFeedback.mediumImpact();
      _showSnackBar(
          '$sideText 체결: ${Formatters.price(tradeLog.price)} × ${_formatQty(_quantity)}${_isCrypto ? '' : '주'}');
    }

    // 입력 초기화
    setState(() {
      _quantity = 0;
      _quantityController.clear();
    });
  }

  Widget _buildWatchlistButton() {
    final isWatching = ref.watch(watchlistProvider.select(
        (list) => list.any((s) => s['code'] == widget.stock.code)));

    return IconButton(
      icon: Icon(
        isWatching ? Icons.star : Icons.star_border,
        color: isWatching ? AppColors.primary : AppColors.textSecondary,
      ),
      onPressed: () async {
        final added = await ref.read(watchlistProvider.notifier).toggle(
              widget.stock.code,
              widget.stock.name,
              '', // market
            );
        _showSnackBar(added ? '관심종목에 추가했습니다' : '관심종목에서 삭제했습니다');
      },
    );
  }

  void _showSnackBar(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w500)),
        backgroundColor:
            isError ? Colors.red.shade800 : const Color(0xFF3A3A5C),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  double _getTickSize(double price) {
    if (price < 2000) return 1;
    if (price < 5000) return 5;
    if (price < 20000) return 10;
    if (price < 50000) return 50;
    if (price < 200000) return 100;
    if (price < 500000) return 500;
    return 1000;
  }
}
