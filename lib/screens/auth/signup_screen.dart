import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/settings_providers.dart';
import 'signup_form_screen.dart';

class SignupScreen extends ConsumerStatefulWidget {
  /// null이면 일반 회원가입 모드, 값이 있으면 게스트 약관 동의 모드
  final Future<void> Function()? onAgreed;

  const SignupScreen({super.key, this.onAgreed});

  @override
  ConsumerState<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends ConsumerState<SignupScreen> {
  bool _agreeTerms = false;
  bool _loading = false;

  @override
  Widget build(BuildContext context) {
    ref.watch(themeProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(widget.onAgreed != null ? '게스트로 시작' : '회원가입'),
        backgroundColor: AppColors.surface,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 20),

            Text(
              '서비스 이용약관',
              style: TextStyle(
                color: AppColors.textPrimary,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              '회원가입을 위해 약관을 확인하고 동의해주세요.',
              style: TextStyle(
                color: AppColors.textSecondary,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 24),

            // 약관 전문
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surfaceLight,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: AppColors.textMuted.withValues(alpha: 0.2),
                  ),
                ),
                child: SingleChildScrollView(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('프로트레이딩 서비스 이용약관',
                          style: TextStyle(
                              color: AppColors.textPrimary,
                              fontSize: 16,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 16),
                      _termsSection(
                        '제1조 (목적)',
                        '본 약관은 프로트레이딩(이하 "서비스")의 이용 조건 및 절차, 이용자와 서비스 제공자의 권리, 의무 및 책임사항을 규정함을 목적으로 합니다.',
                      ),
                      _termsSection(
                        '제2조 (서비스의 내용)',
                        '1. 본 서비스는 모의 투자 연습을 목적으로 하는 앱입니다.\n'
                            '2. 서비스 내에서 사용되는 모든 자산은 가상 자산이며, 실제 금전적 가치가 없습니다.\n'
                            '3. 서비스에서 제공하는 시세 데이터는 실제 시장 데이터를 기반으로 하나, 실시간성을 보장하지 않습니다.',
                      ),
                      _termsSection(
                        '제3조 (이용자의 의무)',
                        '1. 이용자는 서비스를 투자 학습 및 연습 목적으로만 사용해야 합니다.\n'
                            '2. 본 서비스의 모의 투자 결과를 실제 투자 판단의 근거로 사용하여서는 안 됩니다.\n'
                            '3. 이용자는 타인의 계정을 무단으로 사용할 수 없습니다.',
                      ),
                      _termsSection(
                        '제4조 (면책 조항)',
                        '1. 서비스 제공자는 모의 투자 결과에 따른 실제 투자 손실에 대해 어떠한 책임도 지지 않습니다.\n'
                            '2. 시세 데이터의 정확성, 완전성, 적시성을 보장하지 않습니다.\n'
                            '3. 서비스 장애, 데이터 손실 등에 대해 책임을 지지 않습니다.',
                      ),
                      _termsSection(
                        '제5조 (개인정보 처리)',
                        '1. 서비스는 이메일, 닉네임 등 최소한의 개인정보만 수집합니다.\n'
                            '2. 수집된 개인정보는 서비스 제공 목적으로만 사용됩니다.\n'
                            '3. 이용자는 언제든지 계정 삭제를 요청할 수 있습니다.',
                      ),
                      _termsSection(
                        '제6조 (AI 학습 데이터 활용)',
                        '1. 서비스 내 거래 내역, 포트폴리오 구성, 투자 패턴 등의 이용 데이터는 AI 모델 학습 및 서비스 품질 개선을 위해 활용될 수 있습니다.\n'
                            '2. AI 학습에 사용되는 데이터는 개인 식별이 불가능한 형태로 익명화·집계 처리됩니다.\n'
                            '3. 이용자는 본 약관에 동의함으로써 위 데이터 활용에 명시적으로 동의합니다.\n'
                            '4. 데이터 활용에 동의하지 않는 경우 계정 삭제를 통해 서비스 이용을 중단할 수 있습니다.',
                      ),
                      _termsSection(
                        '제7조 (서비스 변경 및 중단)',
                        '서비스 제공자는 운영상 필요한 경우 서비스의 전부 또는 일부를 변경하거나 중단할 수 있습니다.',
                      ),
                      const SizedBox(height: 12),
                      Text('시행일: 2026년 4월 6일',
                          style: TextStyle(
                              color: AppColors.textMuted, fontSize: 12)),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 20),

            // 약관 동의 체크박스
            GestureDetector(
              onTap: () => setState(() => _agreeTerms = !_agreeTerms),
              child: Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: _agreeTerms
                          ? AppColors.primary
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                        color: _agreeTerms
                            ? AppColors.primary
                            : AppColors.textMuted,
                      ),
                    ),
                    child: _agreeTerms
                        ? const Icon(Icons.check,
                            size: 16, color: Colors.black)
                        : null,
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '이용약관에 동의합니다',
                    style: TextStyle(
                      color: AppColors.textPrimary,
                      fontSize: 15,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),

            // 다음 / 게스트 시작 버튼
            SizedBox(
              height: 50,
              child: ElevatedButton(
                onPressed: (_agreeTerms && !_loading)
                    ? () async {
                        if (widget.onAgreed != null) {
                          // 게스트 모드: 약관 동의 후 바로 시작
                          setState(() => _loading = true);
                          try {
                            await widget.onAgreed!();
                          } finally {
                            if (mounted) setState(() => _loading = false);
                          }
                        } else {
                          // 일반 회원가입 모드: 다음 화면으로
                          final nav = Navigator.of(context);
                          final result = await Navigator.push<bool>(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const SignupFormScreen(),
                            ),
                          );
                          if (result == true && mounted) {
                            nav.pop(true);
                          }
                        }
                      }
                    : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  foregroundColor: Colors.black,
                  disabledBackgroundColor:
                      AppColors.primary.withValues(alpha: 0.3),
                  disabledForegroundColor: Colors.black45,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _loading
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.black))
                    : Text(
                        widget.onAgreed != null ? '게스트로 시작하기' : '다음',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
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
                  fontSize: 13,
                  height: 1.6)),
        ],
      ),
    );
  }
}
