/// Build-time config. Override with `--dart-define=API_BASE_URL=https://...`
/// and `--dart-define=USE_MOCK_BACKEND=false` once the real backend exists.
class AppConfig {
  static const apiBaseUrl =
      String.fromEnvironment('API_BASE_URL', defaultValue: 'http://10.0.2.2:8000/api/v1');
  static const useMockBackend =
      bool.fromEnvironment('USE_MOCK_BACKEND', defaultValue: true);
}
