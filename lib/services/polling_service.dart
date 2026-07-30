import 'dart:async';
import 'dart:math';
import 'package:flutter/widgets.dart';
import '../core/constants/app_constants.dart';
import '../models/stock.dart';
import 'naver_finance_service.dart';
import 'mock_data_service.dart';
import 'yahoo_finance_service.dart';

/// 폴링 대상 종목 코드 관리

/// 지능형 폴링 서비스
/// - 3초마다 네이버 금융 API로 실시간 시세 조회
/// - API 호출 사이에 마이크로 틱으로 호가 잔량 미세 진동
/// - 앱 백그라운드 시 자동 정지/재개
class PollingService with WidgetsBindingObserver {
  final NaverFinanceService _naverService;
  final MockDataService _mockDataService;
  Timer? _pollTimer;
  Timer? _microTickTimer;
  bool _isActive = false;
  final _random = Random();

  // 마지막으로 수신한 실제 시세 (향후 보간용)
  Map<String, StockPrice> lastPrices = {};

  // 스트림
  late final StreamController<Map<String, StockPrice>> _priceController;
  final _orderBookController = StreamController<OrderBook>.broadcast();

  Stream<Map<String, StockPrice>> get priceStream => _priceController.stream;
  Stream<OrderBook> get orderBookStream => _orderBookController.stream;

  String? _focusedStockCode;
  List<String> _stockCodes = [];
  bool _isPolling = false; // 중첩 호출 방지

  // 장 마감 시 정적 호가창을 이미 전송한 종목 추적 (중복 전송 방지)
  final Set<String> _staticOrderBookSent = {};

  PollingService(this._naverService, this._mockDataService) {
    // UI가 처음 구독할 때: 캐시된 가격이 있으면 즉시 전달,
    // 없으면 즉시 1회 poll 트리거 (처음 가입/앱 실행 시 즉시 시세 표시)
    _priceController = StreamController<Map<String, StockPrice>>.broadcast(
      onListen: () {
        if (lastPrices.isNotEmpty) {
          Future.microtask(() {
            if (!_priceController.isClosed) {
              _priceController.add(lastPrices);
            }
          });
        } else if (_isActive) {
          triggerPoll();
        }
      },
    );
  }

  /// 폴링 대상 종목 설정
  void setStockCodes(List<String> codes) {
    _stockCodes = List.from(codes);
  }

  /// 폴링 대상에 종목 추가 (검색 진입 시)
  void addStockCode(String code) {
    if (!_stockCodes.contains(code)) {
      _stockCodes.add(code);
    }
  }

  void start() {
    if (_isActive) return;
    _isActive = true;
    WidgetsBinding.instance.addObserver(this);
    _startTimers();
  }

  void stop() {
    _isActive = false;
    _pollTimer?.cancel();
    _pollTimer = null;
    _microTickTimer?.cancel();
    _microTickTimer = null;
    WidgetsBinding.instance.removeObserver(this);
  }

  void setFocusedStock(String? stockCode) {
    if (_focusedStockCode != stockCode) {
      _staticOrderBookSent.remove(stockCode);
    }
    _focusedStockCode = stockCode;
  }

  /// 즉시 1회 폴링 트리거 (신규 종목 진입 시 사용)
  void triggerPoll() {
    _pollReal();
  }

  void _startTimers() {
    _pollTimer?.cancel();
    _microTickTimer?.cancel();

    // 메인 폴링: 3초마다 실제 API 호출
    _pollTimer =
        Timer.periodic(AppConstants.pollingInterval, (_) => _pollReal());

    // 마이크로 틱: 0.5초마다 호가 잔량 미세 진동
    _microTickTimer =
        Timer.periodic(AppConstants.microTickInterval, (_) => _microTick());

    // 즉시 1회 실행
    _pollReal();
  }

  /// 포커스된 종목의 시장이 열려있는지 확인
  bool _isMarketOpen() {
    final code = _focusedStockCode;
    if (code == null) return false;
    // 미국 주식 (알파벳 티커)
    if (YahooFinanceService.usStocks.any((s) => s['code'] == code)) {
      return AppConstants.isUsMarketOpen();
    }
    // 한국 주식 (6자리 숫자)
    if (RegExp(r'^\d{6}$').hasMatch(code)) {
      return AppConstants.isKrMarketOpen();
    }
    // 암호화폐: 24시간
    return AppConstants.isCryptoMarketOpen();
  }

  /// 한국 주식 코드 여부 확인 (6자리 숫자)
  static bool _isKrStock(String code) => RegExp(r'^\d{6}$').hasMatch(code);

  /// 실제 API에서 시세 가져오기
  Future<void> _pollReal() async {
    if (_isPolling) return; // 이전 폴링이 아직 진행 중이면 skip
    _isPolling = true;
    try {
      await _pollRealInternal();
    } finally {
      _isPolling = false;
    }
  }

  Future<void> _pollRealInternal() async {
    final krOpen = AppConstants.isKrMarketOpen();

    // 장외 시간엔 API 호출 없음 (에프터마켓/NXT 포함)
    // 단, 호가창 초기 표시는 1회 유지
    if (!AppConstants.isAnyMarketOpen()) {
      if (_focusedStockCode != null &&
          !_staticOrderBookSent.contains(_focusedStockCode)) {
        final orderBook = _mockDataService.getOrderBook(_focusedStockCode!);
        _orderBookController.add(orderBook);
        _staticOrderBookSent.add(_focusedStockCode!);
      }
      return;
    }

    try {
      if (_stockCodes.isEmpty) return;
      final rawPrices = await _naverService.fetchQuotes(_stockCodes);

      if (rawPrices.isNotEmpty) {
        // 에프터마켓/NXT 등 비정규 세션 가격 반영 방지:
        // 한국 주식은 정규장(09:00~15:30) 시간에만 가격 업데이트.
        // 장 외 시간에는 이미 보유한 마지막 정규장 종가를 유지.
        final filteredPrices = <String, StockPrice>{};
        for (final entry in rawPrices.entries) {
          final code = entry.key;
          if (_isKrStock(code) && !krOpen && lastPrices.containsKey(code)) {
            // 장 외 시간: 기존 정규장 종가 유지
            filteredPrices[code] = lastPrices[code]!;
          } else {
            // 정규장 또는 최초 진입(기준가 없음): API 값 사용
            filteredPrices[code] = entry.value;
            _mockDataService.updateWithRealPrice(code, entry.value.currentPrice);
          }
        }

        lastPrices = filteredPrices;
        _priceController.add(filteredPrices);
      }
    } catch (e, st) {
      if (krOpen) {
        final mockPrices = _mockDataService.updatePrices();
        _priceController.add(mockPrices);
      } else if (lastPrices.isNotEmpty) {
        _priceController.add(lastPrices);
      }
    }

    // 호가창 업데이트
    if (_focusedStockCode != null) {
      if (_isMarketOpen()) {
        // 장 운영 중: 매 폴링마다 새 호가창 생성 (잔량 업데이트)
        _staticOrderBookSent.remove(_focusedStockCode);
        final orderBook = _mockDataService.getOrderBook(_focusedStockCode!);
        _orderBookController.add(orderBook);
      } else if (!_staticOrderBookSent.contains(_focusedStockCode)) {
        // 장 마감: 최초 1회만 정적 호가창 표시 (이후 잔량 변동 없음)
        final orderBook = _mockDataService.getOrderBook(_focusedStockCode!);
        _orderBookController.add(orderBook);
        _staticOrderBookSent.add(_focusedStockCode!);
      }
    }
  }

  /// 마이크로 틱: 호가 잔량 미세 진동 (살아있는 시장 느낌)
  void _microTick() {
    if (_focusedStockCode == null) return;

    // 장 종료 시 호가창 진동 멈춤
    if (!_isMarketOpen()) return;

    // 호가 잔량을 ±1~2% 범위에서 미세하게 변동
    final orderBook =
        _mockDataService.vibrateOrderBook(_focusedStockCode!, _random);
    if (orderBook != null) {
      _orderBookController.add(orderBook);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
        _pollTimer?.cancel();
        _pollTimer = null;
        _microTickTimer?.cancel();
        _microTickTimer = null;
        break;
      case AppLifecycleState.resumed:
        if (_isActive) _startTimers();
        break;
      default:
        break;
    }
  }

  void dispose() {
    stop();
    _priceController.close();
    _orderBookController.close();
  }
}
