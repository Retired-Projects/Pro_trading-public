class SupabaseConfig {
  // --dart-define 으로 주입 (빌드/실행 시 필수):
  //   flutter run \
  //     --dart-define=SUPABASE_URL=https://xxx.supabase.co \
  //     --dart-define=SUPABASE_ANON_KEY=eyJ...
  //     --dart-define=TWELVE_DATA_API_KEY=your_key
  static const String url = String.fromEnvironment('SUPABASE_URL');
  static const String anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
}
