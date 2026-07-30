import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/theme/app_colors.dart';
import '../../providers/settings_providers.dart';

class TermsScreen extends ConsumerWidget {
  const TermsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(themeProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: const Text('이용약관'),
        backgroundColor: AppColors.surface,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('프로트레이딩 서비스 이용약관',
                style: TextStyle(
                    color: AppColors.textPrimary,
                    fontSize: 18,
                    fontWeight: FontWeight.bold)),
            SizedBox(height: 16),
            _Section(
              title: '제1조 (목적)',
              body:
                  '본 약관은 프로트레이딩(이하 "서비스")의 이용 조건 및 절차, 이용자와 서비스 제공자의 권리, 의무 및 책임사항을 규정함을 목적으로 합니다.',
            ),
            _Section(
              title: '제2조 (서비스의 내용)',
              body:
                  '1. 본 서비스는 모의 투자 연습을 목적으로 하는 앱입니다.\n'
                  '2. 서비스 내에서 사용되는 모든 자산은 가상 자산이며, 실제 금전적 가치가 없습니다.\n'
                  '3. 서비스에서 제공하는 시세 데이터는 실제 시장 데이터를 기반으로 하나, 실시간성을 보장하지 않습니다.',
            ),
            _Section(
              title: '제3조 (이용자의 의무)',
              body: '1. 이용자는 서비스를 투자 학습 및 연습 목적으로만 사용해야 합니다.\n'
                  '2. 본 서비스의 모의 투자 결과를 실제 투자 판단의 근거로 사용하여서는 안 됩니다.\n'
                  '3. 이용자는 타인의 계정을 무단으로 사용할 수 없습니다.',
            ),
            _Section(
              title: '제4조 (면책 조항)',
              body:
                  '1. 서비스 제공자는 모의 투자 결과에 따른 실제 투자 손실에 대해 어떠한 책임도 지지 않습니다.\n'
                  '2. 시세 데이터의 정확성, 완전성, 적시성을 보장하지 않습니다.\n'
                  '3. 서비스 장애, 데이터 손실 등에 대해 책임을 지지 않습니다.',
            ),
            _Section(
              title: '제5조 (개인정보 처리)',
              body: '1. 서비스는 이메일, 닉네임 등 최소한의 개인정보만 수집합니다.\n'
                  '2. 수집된 개인정보는 서비스 제공 목적으로만 사용됩니다.\n'
                  '3. 이용자는 언제든지 계정 삭제를 요청할 수 있습니다.',
            ),
            _Section(
              title: '제6조 (AI 학습 데이터 활용)',
              body: '1. 서비스 내 거래 내역, 포트폴리오 구성, 투자 패턴 등의 이용 데이터는 AI 모델 학습 및 서비스 품질 개선을 위해 활용될 수 있습니다.\n'
                  '2. AI 학습에 사용되는 데이터는 개인 식별이 불가능한 형태로 익명화·집계 처리됩니다.\n'
                  '3. 이용자는 본 약관에 동의함으로써 위 데이터 활용에 명시적으로 동의합니다.\n'
                  '4. 데이터 활용에 동의하지 않는 경우 계정 삭제를 통해 서비스 이용을 중단할 수 있습니다.',
            ),
            _Section(
              title: '제7조 (서비스 변경 및 중단)',
              body:
                  '서비스 제공자는 운영상 필요한 경우 서비스의 전부 또는 일부를 변경하거나 중단할 수 있습니다.',
            ),
            SizedBox(height: 20),
            Text('시행일: 2026년 4월 6일',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _Section extends StatelessWidget {
  final String title;
  final String body;

  const _Section({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: TextStyle(
                  color: AppColors.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
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
