import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'core/config/supabase_config.dart';
import 'core/theme/app_colors.dart';
import 'core/theme/app_theme.dart';
import 'providers/settings_providers.dart';
import 'screens/auth/token_auth_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Supabase.initialize(
    url: SupabaseConfig.url,
    anonKey: SupabaseConfig.anonKey,
  );

  final container = ProviderContainer();
  await container.read(themeProvider.notifier).load();
  await container.read(fontScaleProvider.notifier).load();

  runApp(UncontrolledProviderScope(
    container: container,
    child: const ProTradingApp(),
  ));
}

class ProTradingApp extends ConsumerWidget {
  const ProTradingApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fontScale = ref.watch(fontScaleProvider);
    final themeMode = ref.watch(themeProvider);

    // AppColors의 모드를 동기화
    AppColors.setMode(themeMode);

    final themeData = switch (themeMode) {
      AppThemeMode.light => AppTheme.lightTheme,
      AppThemeMode.amoled => AppTheme.amoledTheme,
      AppThemeMode.dark => AppTheme.darkTheme,
    };

    return MaterialApp(
      title: '프로트레이딩',
      debugShowCheckedModeBanner: false,
      theme: themeData,
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(fontScale),
          ),
          child: ColoredBox(
            color: AppColors.surface,
            child: SafeArea(
              bottom: false,
              child: child!,
            ),
          ),
        );
      },
      home: const TokenAuthScreen(),
    );
  }
}
