import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/theme/app_colors.dart';
import '../providers/settings_providers.dart';
import '../widgets/confirm_bottom_sheet.dart';
import 'auth/terms_screen.dart';
import 'auth/token_auth_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  final _nicknameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final user = Supabase.instance.client.auth.currentUser;
    _nicknameController.text =
        user?.userMetadata?['nickname'] as String? ?? '';
  }

  @override
  void dispose() {
    _nicknameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(themeProvider);
    final fontScale = ref.watch(fontScaleProvider);
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          // 고정 헤더
          Container(
            color: AppColors.surface,
            child: SafeArea(
              bottom: false,
              child: Column(
                children: [
                  SizedBox(
                    height: 52,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        Text(
                          '설정',
                          style: TextStyle(
                            color: AppColors.textPrimary,
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Divider(color: AppColors.divider, height: 1),
                ],
              ),
            ),
          ),
          // 스크롤 영역
          Expanded(
            child: ListView(
              children: [
                // ── 계정 ──
                // 닉네임 변경
                _buildSectionHeader('계정'),
                _buildTile(
                  icon: Icons.person_outline,
                  title: '닉네임 변경',
                  subtitle: _nicknameController.text.isEmpty
                      ? '설정되지 않음'
                      : _nicknameController.text,
                  onTap: () => _showNicknameDialog(),
                ),

                Divider(color: AppColors.divider, height: 1),

                // ── 화면 설정 ──
                _buildSectionHeader('화면 설정'),

                // 테마
                _buildTile(
                  icon: Icons.palette_outlined,
                  title: '테마',
                  trailing: DropdownButton<AppThemeMode>(
                    value: theme,
                    dropdownColor: AppColors.surfaceLight,
                    style: TextStyle(color: AppColors.textPrimary, fontSize: 14),
                    underline: const SizedBox.shrink(),
                    items: const [
                      DropdownMenuItem(
                          value: AppThemeMode.dark, child: Text('다크')),
                      DropdownMenuItem(
                          value: AppThemeMode.light, child: Text('라이트')),
                      DropdownMenuItem(
                          value: AppThemeMode.amoled, child: Text('AMOLED')),
                    ],
                    onChanged: (v) {
                      if (v != null) ref.read(themeProvider.notifier).set(v);
                    },
                  ),
                ),

                // 글씨 크기
                _buildTile(
                  icon: Icons.text_fields,
                  title: '글씨 크기',
                  subtitle: _fontScaleLabel(fontScale),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Row(
                    children: [
                      Text('가',
                          style: TextStyle(
                              color: AppColors.textMuted, fontSize: 12)),
                      Expanded(
                        child: Slider(
                          value: fontScale,
                          min: 0.8,
                          max: 1.4,
                          divisions: 6,
                          activeColor: AppColors.primary,
                          inactiveColor: AppColors.surfaceLight,
                          label: _fontScaleLabel(fontScale),
                          onChanged: (v) =>
                              ref.read(fontScaleProvider.notifier).set(v),
                        ),
                      ),
                      Text('가',
                          style: TextStyle(
                              color: AppColors.textMuted, fontSize: 20)),
                    ],
                  ),
                ),

                Divider(color: AppColors.divider, height: 1),

                // ── 정보 ──
                _buildSectionHeader('정보'),

                _buildTile(
                  icon: Icons.description_outlined,
                  title: '이용약관',
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const TermsScreen()),
                  ),
                ),

                _buildTile(
                  icon: Icons.info_outline,
                  title: '앱 버전',
                  subtitle: '1.0.0',
                ),

                Divider(color: AppColors.divider, height: 1),

                // ── 계정 관리 ──
                _buildSectionHeader('계정 관리'),

                // 로그아웃
                _buildTile(
                  icon: Icons.logout,
                  title: '로그아웃',
                  titleColor: AppColors.textSecondary,
                  onTap: () => _showLogoutDialog(),
                ),

                // 회원탈퇴
                _buildTile(
                  icon: Icons.delete_forever,
                  title: '회원탈퇴',
                  titleColor: Colors.redAccent,
                  onTap: () => _showDeleteDialog(),
                ),

                const SizedBox(height: 40),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(title,
          style: TextStyle(
              color: AppColors.primary,
              fontSize: 13,
              fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildTile({
    required IconData icon,
    required String title,
    String? subtitle,
    Color? titleColor,
    Widget? trailing,
    VoidCallback? onTap,
  }) {
    return ListTile(
      leading: Icon(icon, color: titleColor ?? AppColors.textSecondary, size: 22),
      title: Text(title,
          style: TextStyle(
              color: titleColor ?? AppColors.textPrimary, fontSize: 15)),
      subtitle: subtitle != null
          ? Text(subtitle,
              style:
                  TextStyle(color: AppColors.textMuted, fontSize: 12))
          : null,
      trailing: trailing ??
          (onTap != null
              ? Icon(Icons.chevron_right,
                  color: AppColors.textMuted, size: 20)
              : null),
      onTap: onTap,
    );
  }

  String _fontScaleLabel(double scale) {
    if (scale <= 0.85) return '아주 작게';
    if (scale <= 0.95) return '작게';
    if (scale <= 1.05) return '보통';
    if (scale <= 1.15) return '크게';
    if (scale <= 1.25) return '아주 크게';
    return '최대';
  }

  void _showNicknameDialog() {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: Text('닉네임 변경',
            style: TextStyle(color: AppColors.textPrimary)),
        content: TextField(
          controller: _nicknameController,
          style: TextStyle(color: AppColors.textPrimary),
          decoration: InputDecoration(
            hintText: '새 닉네임',
            hintStyle: TextStyle(color: AppColors.textMuted),
            filled: true,
            fillColor: AppColors.surfaceLight,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide.none,
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('취소',
                style: TextStyle(color: AppColors.textSecondary)),
          ),
          TextButton(
            onPressed: () async {
              final nickname = _nicknameController.text.trim();
              if (nickname.isEmpty) return;

              await Supabase.instance.client.auth
                  .updateUser(UserAttributes(data: {'nickname': nickname}));

              // profiles 테이블도 업데이트
              final userId =
                  Supabase.instance.client.auth.currentUser?.id;
              if (userId != null) {
                await Supabase.instance.client
                    .from('profiles')
                    .update({'nickname': nickname}).eq('user_id', userId);
              }

              if (ctx.mounted) Navigator.pop(ctx);
              // mounted 가드: 다이얼로그 닫히는 동안 위젯이 해제될 수 있음
              if (mounted) {
                setState(() {});
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content: Text('닉네임이 변경되었습니다',
                          style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w500)),
                      backgroundColor: const Color(0xFF3A3A5C)),
                );
              }
            },
            child: Text('변경',
                style: TextStyle(color: AppColors.primary)),
          ),
        ],
      ),
    );
  }

  void _showLogoutDialog() async {
    final confirmed = await ConfirmBottomSheet.show(
      context,
      title: '로그아웃',
      message: '정말 로그아웃 하시겠습니까?',
      confirmText: '로그아웃',
      confirmColor: Colors.redAccent,
      icon: Icons.logout,
    );

    if (confirmed == true && mounted) {
      await Supabase.instance.client.auth.signOut();
      const secureStorage = FlutterSecureStorage(
        aOptions: AndroidOptions(encryptedSharedPreferences: true),
      );
      await secureStorage.delete(key: 'user_token');
      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const TokenAuthScreen()),
          (route) => false,
        );
      }
    }
  }

  void _showDeleteDialog() async {
    final confirmed = await ConfirmBottomSheet.show(
      context,
      title: '회원탈퇴',
      message: '탈퇴 시 모든 데이터(거래이력, 보유종목, 잔고)가\n영구적으로 삭제됩니다.\n정말 탈퇴하시겠습니까?',
      confirmText: '탈퇴하기',
      confirmColor: Colors.redAccent,
      icon: Icons.delete_forever,
    );

    if (confirmed != true || !mounted) return;

    try {
      final response = await Supabase.instance.client.functions
          .invoke('delete-account');

      if (response.status != 200) {
        final error = response.data?['error'] ?? '알 수 없는 오류';
        throw Exception(error);
      }

      await Supabase.instance.client.auth.signOut();

      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const TokenAuthScreen()),
          (route) => false,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('탈퇴 실패: $e'),
              backgroundColor: Colors.red.shade800),
        );
      }
    }
  }
}
