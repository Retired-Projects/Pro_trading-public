import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/service_providers.dart';
import '../../providers/settings_providers.dart';
import '../../providers/portfolio_providers.dart';
import '../../providers/market_providers.dart';
import '../../services/version_check_service.dart';
import '../home_screen.dart';

const _secureTokenKey = 'user_token';

// 토큰을 암호화 저장소(iOS Keychain / Android Keystore)에 보관
const _secureStorage = FlutterSecureStorage(
  aOptions: AndroidOptions(
    encryptedSharedPreferences: true,
  ),
);

/// 저장된 토큰 자동 로그인 시도
/// - 토큰 있음 → 로그인 → HomeScreen
/// - 토큰 없음 → TokenAuthScreen
Future<bool> tryAutoLogin(WidgetRef ref) async {
  final token = await _secureStorage.read(key: _secureTokenKey);
  if (token == null) return false;

  try {
    final supabase = ref.read(supabaseServiceProvider);
    final userId = await supabase.signInWithToken(token);
    await _initApp(ref, userId);
    return true;
  } catch (_) {
    // 저장된 토큰이 유효하지 않으면 삭제
    await _secureStorage.delete(key: _secureTokenKey);
    return false;
  }
}

Future<void> _initApp(WidgetRef ref, String userId) async {
  ref.read(userIdProvider.notifier).state = userId;
  await ref.read(portfolioProvider.notifier).loadFromSupabase();
  await ref.read(ordersProvider.notifier).loadPendingOrders();
  await ref.read(tradeLogsProvider.notifier).loadTradeLogs();
  final stocks = await ref.read(stockListProvider.future);
  final codes = stocks.map((s) => s['code']!).toList();
  ref.read(pollingServiceProvider).setStockCodes(codes);
  ref.read(pollingServiceProvider).start();
}

/// 토큰 생성: XXXX-XXXX-XXXX-XXXX-XXXX-XXXX (혼동 없는 문자만 사용)
String generateToken() {
  const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  final random = Random.secure();
  final parts = List.generate(
    6,
    (_) => List.generate(4, (_) => chars[random.nextInt(chars.length)]).join(),
  );
  return parts.join('-');
}

class TokenAuthScreen extends ConsumerStatefulWidget {
  const TokenAuthScreen({super.key});

  @override
  ConsumerState<TokenAuthScreen> createState() => _TokenAuthScreenState();
}

class _TokenAuthScreenState extends ConsumerState<TokenAuthScreen> {
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _autoLogin();
  }

  Future<void> _autoLogin() async {
    // 1. 강제 업데이트 체크 (로그인보다 먼저)
    final versionResult = await VersionCheckService.check();
    if (versionResult.needsUpdate && mounted) {
      setState(() => _loading = false);
      _showForceUpdateDialog(versionResult.storeUrl);
      return;
    }

    // 2. 자동 로그인
    final success = await tryAutoLogin(ref);
    if (success && mounted) {
      _navigateHome();
    } else if (mounted) {
      setState(() => _loading = false);
    }
  }

  void _showForceUpdateDialog(String? storeUrl) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          backgroundColor: AppColors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.system_update_rounded, color: AppColors.primary, size: 24),
              const SizedBox(width: 10),
              Text(
                '업데이트 필요',
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ],
          ),
          content: Text(
            '원활한 서비스 이용을 위해\n최신 버전으로 업데이트해 주세요.',
            style: TextStyle(
              color: AppColors.textSecondary,
              fontSize: 14,
              height: 1.6,
            ),
          ),
          actions: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: storeUrl != null
                    ? () => launchUrl(
                          Uri.parse(storeUrl),
                          mode: LaunchMode.externalApplication,
                        )
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10)),
                ),
                child: const Text(
                  '업데이트',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _navigateHome() {
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(builder: (_) => const HomeScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(themeProvider);

    if (_loading) {
      return Scaffold(
        backgroundColor: AppColors.background,
        body: Center(
          child: CircularProgressIndicator(color: AppColors.primary),
        ),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.candlestick_chart, size: 64, color: AppColors.primary),
              const SizedBox(height: 16),
              Text(
                'ProTrading',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '모의 투자로 실력을 키우세요',
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 14),
              ),

              const SizedBox(height: 60),

              if (_error != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _error!,
                    style:
                        const TextStyle(color: Colors.redAccent, fontSize: 13),
                  ),
                ),

              // 새로 시작
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _loading ? null : _showTermsAndStart,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text(
                    '새로 시작하기',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(height: 16),

              // 기존 코드 복구
              SizedBox(
                height: 52,
                child: OutlinedButton(
                  onPressed: _loading ? null : _showRestoreDialog,
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: AppColors.primary),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: Text(
                    '기존 코드로 복구',
                    style: TextStyle(
                      color: AppColors.primary,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// 약관 동의 바텀시트 → 동의 시 _startNew() 진행
  Future<void> _showTermsAndStart() async {
    bool agreed = false;
    bool scrolledToEnd = false;
    bool showScrollError = false;
    final scrollController = ScrollController();
    void Function(void Function())? sheetSetState;

    scrollController.addListener(() {
      if (!scrolledToEnd &&
          scrollController.hasClients &&
          scrollController.position.pixels >=
              scrollController.position.maxScrollExtent - 32) {
        scrolledToEnd = true;
        sheetSetState?.call(() {});
      }
    });

    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          sheetSetState = setSheetState;

          return Container(
            height: MediaQuery.of(context).size.height * 0.82,
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(20)),
            ),
            child: Column(
              children: [
                // 핸들
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(top: 12, bottom: 16),
                  decoration: BoxDecoration(
                    color: AppColors.textMuted,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Text(
                    '서비스 이용약관',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: SingleChildScrollView(
                    controller: scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _termsSection('제1조 (목적)',
                            '본 약관은 프로트레이딩(이하 "서비스")의 이용 조건 및 절차, 이용자와 서비스 제공자의 권리, 의무 및 책임사항을 규정함을 목적으로 합니다.'),
                        _termsSection('제2조 (서비스의 내용)',
                            '1. 본 서비스는 모의 투자 연습을 목적으로 하는 앱입니다.\n'
                            '2. 서비스 내 모든 자산은 가상 자산이며 실제 금전적 가치가 없습니다.\n'
                            '3. 시세 데이터는 실제 시장 데이터를 기반으로 하나 실시간성을 보장하지 않습니다.'),
                        _termsSection('제3조 (이용자의 의무)',
                            '1. 서비스는 투자 학습 및 연습 목적으로만 사용해야 합니다.\n'
                            '2. 모의 투자 결과를 실제 투자 판단의 근거로 사용해서는 안 됩니다.\n'
                            '3. 타인의 계정을 무단으로 사용할 수 없습니다.'),
                        _termsSection('제4조 (면책 조항)',
                            '1. 서비스 제공자는 모의 투자 결과에 따른 실제 투자 손실에 대해 책임을 지지 않습니다.\n'
                            '2. 시세 데이터의 정확성·완전성·적시성을 보장하지 않습니다.\n'
                            '3. 서비스 장애, 데이터 손실 등에 대해 책임을 지지 않습니다.'),
                        _termsSection('제5조 (개인정보 처리)',
                            '1. 서비스는 최소한의 개인정보만 수집합니다.\n'
                            '2. 수집된 개인정보는 서비스 제공 목적으로만 사용됩니다.\n'
                            '3. 이용자는 언제든지 계정 삭제를 요청할 수 있습니다.'),
                        _termsSection('제6조 (AI 학습 데이터 활용)',
                            '1. 거래 내역, 포트폴리오 구성, 투자 패턴 등의 이용 데이터는 AI 모델 학습 및 서비스 품질 개선을 위해 활용될 수 있습니다.\n'
                            '2. AI 학습에 사용되는 데이터는 개인 식별이 불가능한 형태로 익명화·집계 처리됩니다.\n'
                            '3. 데이터 활용에 동의하지 않는 경우 계정 삭제를 통해 서비스 이용을 중단할 수 있습니다.'),
                        _termsSection('제7조 (서비스 변경 및 중단)',
                            '서비스 제공자는 운영상 필요한 경우 서비스의 전부 또는 일부를 변경하거나 중단할 수 있습니다.'),
                        Text('시행일: 2026년 4월 6일',
                            style: TextStyle(
                                color: AppColors.textMuted, fontSize: 11)),
                        const SizedBox(height: 8),
                      ],
                    ),
                  ),
                ),
                // 동의 체크박스 + 버튼
                Container(
                  padding: EdgeInsets.fromLTRB(
                      20, 12, 20, MediaQuery.of(context).padding.bottom + 16),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    border: Border(
                        top: BorderSide(
                            color: AppColors.divider, width: 1)),
                  ),
                  child: Column(
                    children: [
                      AnimatedSize(
                        duration: const Duration(milliseconds: 200),
                        child: showScrollError
                            ? Container(
                                width: double.infinity,
                                margin: const EdgeInsets.only(bottom: 8),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: Colors.red.shade900.withValues(alpha: 0.3),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(
                                      color: Colors.red.shade700, width: 1),
                                ),
                                child: Row(
                                  children: [
                                    Icon(Icons.info_outline,
                                        color: Colors.red.shade300, size: 14),
                                    const SizedBox(width: 6),
                                    Text(
                                      '약관을 끝까지 읽어주세요.',
                                      style: TextStyle(
                                          color: Colors.red.shade300,
                                          fontSize: 12),
                                    ),
                                  ],
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                      GestureDetector(
                        onTap: () {
                          if (!scrolledToEnd) {
                            setSheetState(() => showScrollError = true);
                            Future.delayed(const Duration(seconds: 2), () {
                              sheetSetState?.call(() => showScrollError = false);
                            });
                            return;
                          }
                          setSheetState(() => agreed = !agreed);
                        },
                        child: Row(
                          children: [
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 150),
                              width: 22,
                              height: 22,
                              decoration: BoxDecoration(
                                color: agreed
                                    ? AppColors.primary
                                    : Colors.transparent,
                                borderRadius: BorderRadius.circular(5),
                                border: Border.all(
                                  color: agreed
                                      ? AppColors.primary
                                      : AppColors.textMuted,
                                  width: 2,
                                ),
                              ),
                              child: agreed
                                  ? const Icon(Icons.check,
                                      color: Colors.black,
                                      size: 14)
                                  : null,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                '이용약관 전체 내용에 동의합니다.',
                                style: TextStyle(
                                  color: scrolledToEnd
                                      ? AppColors.textPrimary
                                      : AppColors.textMuted,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        height: 50,
                        width: double.infinity,
                        child: ElevatedButton(
                          onPressed: agreed
                              ? () => Navigator.pop(ctx, true)
                              : null,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            disabledBackgroundColor:
                                AppColors.surfaceLight,
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12)),
                          ),
                          child: Text(
                            '동의하고 시작하기',
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: agreed
                                  ? Colors.black
                                  : AppColors.textMuted,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );

    scrollController.dispose();
    if (confirmed == true && mounted) {
      final nickname = await Navigator.push<String>(
        context,
        MaterialPageRoute(
          builder: (_) => NicknameSetupScreen(onConfirm: (name) {
            Navigator.pop(context, name);
          }),
        ),
      );
      if (nickname != null && nickname.isNotEmpty) {
        await _startNew(nickname: nickname);
      }
    }
  }

  Widget _termsSection(String title, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 14,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          Text(body,
              style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 12,
                  height: 1.6)),
        ],
      ),
    );
  }

  Future<void> _startNew({required String nickname}) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    final token = generateToken();

    try {
      final supabase = ref.read(supabaseServiceProvider);
      final userId = await supabase.signUpWithToken(token, nickname: nickname);

      await _initApp(ref, userId);

      if (mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            fullscreenDialog: true,
            builder: (_) => TokenSaveScreen(
              token: token,
              onDone: () async {
                // 사용자가 코드 저장 확인 후에만 암호화 저장소에 보관
                await _secureStorage.write(
                    key: _secureTokenKey, value: token);
                _navigateHome();
              },
            ),
          ),
        );
      }
    } catch (e) {
      setState(() => _error = '오류: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }


  void _showRestoreDialog() {
    final controller = TextEditingController();
    String? dialogError;

    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: AppColors.surface,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text(
            '코드로 복구',
            style: TextStyle(
                color: AppColors.textPrimary, fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '기존에 발급받은 코드를 입력하세요.',
                style:
                    TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 18,
                  letterSpacing: 2,
                  fontWeight: FontWeight.bold,
                ),
                decoration: InputDecoration(
                  hintText: 'XXXX-XXXX-XXXX-XXXX-XXXX-XXXX',
                  hintStyle: TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 15,
                      letterSpacing: 1),
                  filled: true,
                  fillColor: AppColors.surfaceLight,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(color: AppColors.primary),
                  ),
                ),
                onChanged: (_) {
                  if (dialogError != null) {
                    setDialogState(() => dialogError = null);
                  }
                },
              ),
              if (dialogError != null) ...[
                const SizedBox(height: 8),
                Text(
                  dialogError!,
                  style: const TextStyle(
                      color: Colors.redAccent, fontSize: 12),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('취소',
                  style: TextStyle(color: AppColors.textSecondary)),
            ),
            TextButton(
              onPressed: () async {
                final token = controller.text.trim().toUpperCase();
                if (token.isEmpty) return;

                setDialogState(() => dialogError = null);
                Navigator.pop(ctx);
                await _restoreWithToken(token);
              },
              child: Text(
                '복구',
                style: TextStyle(
                    color: AppColors.primary, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _restoreWithToken(String token) async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final supabase = ref.read(supabaseServiceProvider);
      final userId = await supabase.signInWithToken(token);

      await _secureStorage.write(key: _secureTokenKey, value: token);

      await _initApp(ref, userId);

      if (mounted) _navigateHome();
    } catch (_) {
      setState(() => _error = '코드가 올바르지 않습니다. 다시 확인해주세요.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}

/// 닉네임 설정 전용 페이지
class NicknameSetupScreen extends StatefulWidget {
  final void Function(String nickname) onConfirm;

  const NicknameSetupScreen({super.key, required this.onConfirm});

  @override
  State<NicknameSetupScreen> createState() => _NicknameSetupScreenState();
}

class _NicknameSetupScreenState extends State<NicknameSetupScreen> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _confirm() {
    final name = _controller.text.trim();
    if (name.isEmpty) {
      setState(() => _error = '닉네임을 입력해주세요.');
      return;
    }
    widget.onConfirm(name);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Icon(Icons.person_outline, size: 56, color: AppColors.primary),
              const SizedBox(height: 24),
              Text(
                '닉네임을 설정해주세요',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                '리더보드와 프로필에 표시됩니다.\n나중에 설정에서 변경할 수 있습니다.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textSecondary,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
              const SizedBox(height: 48),
              TextField(
                controller: _controller,
                autofocus: true,
                maxLength: 12,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                ),
                decoration: InputDecoration(
                  hintText: '닉네임 입력',
                  hintStyle: TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 20,
                    fontWeight: FontWeight.normal,
                  ),
                  filled: true,
                  fillColor: AppColors.surface,
                  counterStyle: TextStyle(color: AppColors.textMuted, fontSize: 11),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: AppColors.primary, width: 2),
                  ),
                  errorText: _error,
                  errorStyle: const TextStyle(color: Colors.redAccent, fontSize: 12),
                  errorBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: const BorderSide(color: Colors.redAccent),
                  ),
                ),
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
                onSubmitted: (_) => _confirm(),
              ),
              const SizedBox(height: 24),
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  onPressed: _confirm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                  child: const Text(
                    '시작하기',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 발급된 토큰 저장 안내 전용 페이지
class TokenSaveScreen extends StatefulWidget {
  final String token;
  final Future<void> Function() onDone;

  const TokenSaveScreen({super.key, required this.token, required this.onDone});

  @override
  State<TokenSaveScreen> createState() => _TokenSaveScreenState();
}

class _TokenSaveScreenState extends State<TokenSaveScreen> {
  bool _copied = false;
  bool _confirmed = false;

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.background,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 28),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: 60),
                Icon(Icons.key_rounded, size: 56, color: AppColors.primary),
                const SizedBox(height: 20),
                Text(
                  '내 고유 코드',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 26,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '이 코드로만 계정을 복구할 수 있습니다.\n반드시 안전한 곳에 저장해두세요.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: AppColors.textSecondary,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 36),

                // 토큰 복사 박스
                GestureDetector(
                  onTap: () {
                    Clipboard.setData(ClipboardData(text: widget.token));
                    setState(() => _copied = true);
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(
                        vertical: 20, horizontal: 20),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: _copied
                            ? AppColors.primary
                            : AppColors.textMuted.withValues(alpha: 0.3),
                        width: _copied ? 2 : 1,
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            widget.token,
                            style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 3,
                              height: 1.6,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Icon(
                          _copied ? Icons.check_circle : Icons.copy_rounded,
                          color: _copied
                              ? AppColors.primary
                              : AppColors.textSecondary,
                          size: 26,
                        ),
                      ],
                    ),
                  ),
                ),

                if (_copied) ...[
                  const SizedBox(height: 8),
                  Text(
                    '클립보드에 복사되었습니다',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: AppColors.primary, fontSize: 12),
                  ),
                ],

                const SizedBox(height: 28),

                // 경고 박스
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.red.shade900.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: Colors.red.shade800.withValues(alpha: 0.5)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.warning_amber_rounded,
                          color: Colors.red.shade400, size: 20),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '이 코드를 잃어버리면 계정을 영구적으로 복구할 수 없습니다.',
                          style: TextStyle(
                            color: Colors.red.shade300,
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // 확인 체크박스
                GestureDetector(
                  onTap: () => setState(() => _confirmed = !_confirmed),
                  child: Row(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        width: 22,
                        height: 22,
                        decoration: BoxDecoration(
                          color: _confirmed
                              ? AppColors.primary
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(5),
                          border: Border.all(
                            color: _confirmed
                                ? AppColors.primary
                                : AppColors.textMuted,
                            width: 2,
                          ),
                        ),
                        child: _confirmed
                            ? const Icon(Icons.check,
                                color: Colors.black, size: 14)
                            : null,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          '코드를 저장했으며, 분실 시 복구가 불가능함을 확인했습니다.',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 13,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                const Spacer(),

                // 시작하기 버튼 (체크 후 표시)
                AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  child: _confirmed
                      ? Padding(
                          padding: const EdgeInsets.only(bottom: 32),
                          child: SizedBox(
                            height: 52,
                            child: ElevatedButton(
                              onPressed: widget.onDone,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: AppColors.primary,
                                foregroundColor: Colors.black,
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(14)),
                              ),
                              child: const Text(
                                '시작하기',
                                style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold),
                              ),
                            ),
                          ),
                        )
                      : const SizedBox(height: 32),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
