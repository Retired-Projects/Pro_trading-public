import 'dart:io';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class VersionCheckResult {
  final bool needsUpdate;
  final String? storeUrl;

  const VersionCheckResult({required this.needsUpdate, this.storeUrl});
}

class VersionCheckService {
  /// 현재 앱 버전과 Supabase app_config.min_version을 비교합니다.
  /// 네트워크 오류 등 예외 발생 시 업데이트 불필요로 처리 (앱 진입 허용).
  static Future<VersionCheckResult> check() async {
    try {
      final info = await PackageInfo.fromPlatform();
      final current = info.version; // e.g. "1.0.5"

      final data = await Supabase.instance.client
          .from('app_config')
          .select('min_version, store_url_android, store_url_ios')
          .single();

      final minVersion = data['min_version'] as String;
      final needsUpdate = _compare(current, minVersion) < 0;

      String? storeUrl;
      if (needsUpdate) {
        storeUrl = Platform.isIOS
            ? data['store_url_ios'] as String?
            : data['store_url_android'] as String?;
      }

      return VersionCheckResult(needsUpdate: needsUpdate, storeUrl: storeUrl);
    } catch (_) {
      return const VersionCheckResult(needsUpdate: false);
    }
  }

  /// v1 < v2 이면 음수, 같으면 0, v1 > v2 이면 양수
  static int _compare(String v1, String v2) {
    int parse(String s) => int.tryParse(s) ?? 0;
    final p1 = v1.split('.').map(parse).toList();
    final p2 = v2.split('.').map(parse).toList();
    for (var i = 0; i < 3; i++) {
      final a = i < p1.length ? p1[i] : 0;
      final b = i < p2.length ? p2[i] : 0;
      if (a != b) return a - b;
    }
    return 0;
  }
}
