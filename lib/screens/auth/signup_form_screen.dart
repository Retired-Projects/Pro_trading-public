import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/settings_providers.dart';

class SignupFormScreen extends ConsumerStatefulWidget {
  const SignupFormScreen({super.key});

  @override
  ConsumerState<SignupFormScreen> createState() => _SignupFormScreenState();
}

class _SignupFormScreenState extends ConsumerState<SignupFormScreen> {
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();
  final _nicknameController = TextEditingController();
  bool _loading = false;
  String? _error;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _confirmController.dispose();
    _nicknameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(themeProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('정보 입력'),
        backgroundColor: AppColors.surface,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 20),

            // 닉네임
            _buildField(_nicknameController, '닉네임', Icons.person_outline),
            const SizedBox(height: 16),

            // 이메일
            _buildField(_emailController, '이메일', Icons.email_outlined,
                keyboardType: TextInputType.emailAddress),
            const SizedBox(height: 16),

            // 비밀번호
            _buildField(_passwordController, '비밀번호 (6자 이상)', Icons.lock_outline,
                obscure: true),
            const SizedBox(height: 16),

            // 비밀번호 확인
            _buildField(_confirmController, '비밀번호 확인', Icons.lock_outline,
                obscure: true),
            const SizedBox(height: 24),

            // 에러 메시지
            if (_error != null)
              Container(
                padding: const EdgeInsets.all(12),
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: Colors.red.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_error!,
                    style:
                        const TextStyle(color: Colors.redAccent, fontSize: 13)),
              ),

            // 가입 버튼
            SizedBox(
              height: 50,
              child: ElevatedButton(
                onPressed: _loading ? null : _signup,
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
                    : const Text('가입하기',
                        style: TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildField(
      TextEditingController controller, String hint, IconData icon,
      {bool obscure = false,
      TextInputType keyboardType = TextInputType.text}) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      style: TextStyle(color: AppColors.textPrimary),
      decoration: InputDecoration(
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
      ),
    );
  }

  Future<void> _signup() async {
    final nickname = _nicknameController.text.trim();
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    final confirm = _confirmController.text;

    if (nickname.isEmpty || email.isEmpty || password.isEmpty) {
      setState(() => _error = '모든 필드를 입력해주세요.');
      return;
    }
    if (password.length < 6) {
      setState(() => _error = '비밀번호는 6자 이상이어야 합니다.');
      return;
    }
    if (password != confirm) {
      setState(() => _error = '비밀번호가 일치하지 않습니다.');
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final supabase = Supabase.instance.client;
      await supabase.auth.signUp(
        email: email,
        password: password,
        data: {'nickname': nickname},
      );

      if (mounted) {
        Navigator.pop(context, true);
      }
    } on AuthException catch (e) {
      setState(() => _error = e.message);
    } catch (e) {
      setState(() => _error = '회원가입에 실패했습니다.');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
}
