import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/service_providers.dart';
import '../../providers/settings_providers.dart';
import '../../providers/portfolio_providers.dart';
import '../../providers/market_providers.dart';
import '../home_screen.dart';
import 'signup_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(themeProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 80),

              // 로고
              Icon(Icons.candlestick_chart,
                  size: 64, color: AppColors.primary),
              const SizedBox(height: 16),
              Text('ProTrading',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 28,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Text('모의 투자로 실력을 키우세요',
                  textAlign: TextAlign.center,
                  style:
                      TextStyle(color: AppColors.textSecondary, fontSize: 14)),
              const SizedBox(height: 48),

              // 이메일
              TextField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                style: TextStyle(color: AppColors.textPrimary),
                decoration: _inputDecoration('이메일', Icons.email_outlined),
              ),
              const SizedBox(height: 16),

              // 비밀번호
              TextField(
                controller: _passwordController,
                obscureText: true,
                style: TextStyle(color: AppColors.textPrimary),
                decoration: _inputDecoration('비밀번호', Icons.lock_outline),
              ),
              const SizedBox(height: 24),

              // 에러
              if (_error != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(_error!,
                      style: const TextStyle(
                          color: Colors.redAccent, fontSize: 13)),
                ),

              // 로그인 버튼
              SizedBox(
                height: 50,
                child: ElevatedButton(
                  onPressed: _loading ? null : _login,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: _loading
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.black))
                      : const Text('로그인',
                          style: TextStyle(
                              fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 16),

              // 회원가입
              SizedBox(
                height: 50,
                child: OutlinedButton(
                  onPressed: () async {
                    final result = await Navigator.push<bool>(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const SignupScreen()),
                    );
                    if (result == true && mounted) {
                      setState(() =>
                          _error = '가입 완료! 이메일을 확인 후 로그인해주세요.');
                    }
                  },
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: AppColors.primary),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text('회원가입',
                      style: TextStyle(
                          color: AppColors.primary,
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
                ),
              ),
              const SizedBox(height: 24),

            ],
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint, IconData icon) {
    return InputDecoration(
      hintText: hint,
      hintStyle: TextStyle(color: AppColors.textMuted),
      prefixIcon: Icon(icon, color: AppColors.textSecondary),
      filled: true,
      fillColor: AppColors.surfaceLight,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: AppColors.primary),
      ),
    );
  }

  Future<void> _login() async {
    final email = _emailController.text.trim();
    final password = _passwordController.text;

    if (email.isEmpty || password.isEmpty) {
      setState(() => _error = '이메일과 비밀번호를 입력해주세요.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      await Supabase.instance.client.auth
          .signInWithPassword(email: email, password: password);
      await _initAndNavigate();
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = '로그인에 실패했습니다.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // 게스트/토큰 로그인은 token_auth_screen.dart로 이전됨

  Future<void> _initAndNavigate() async {
    final userId = Supabase.instance.client.auth.currentUser!.id;
    ref.read(userIdProvider.notifier).state = userId;

    // Supabase 데이터 로드
    await ref.read(portfolioProvider.notifier).loadFromSupabase();
    await ref.read(ordersProvider.notifier).loadPendingOrders();
    await ref.read(tradeLogsProvider.notifier).loadTradeLogs();

    // 종목 로드 & 폴링 시작
    final stocks = await ref.read(stockListProvider.future);
    final codes = stocks.map((s) => s['code']!).toList();
    ref.read(pollingServiceProvider).setStockCodes(codes);
    ref.read(pollingServiceProvider).start();

    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const HomeScreen()),
      );
    }
  }
}
