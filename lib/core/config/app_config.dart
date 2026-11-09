import 'package:flutter/foundation.dart';

/// Build-time config.
///   --dart-define=API_BASE_URL=https://api.example.com/api/v1
///   --dart-define=USE_MOCK_BACKEND=true   (UI-only demo, no server needed)
class AppConfig {
  static const useMockBackend = bool.fromEnvironment('USE_MOCK_BACKEND');

  static String get apiBaseUrl {
    const fromEnv = String.fromEnvironment('API_BASE_URL');
    if (fromEnv.isNotEmpty) return fromEnv;
    // Android emulator reaches the host machine via 10.0.2.2.
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return 'http://10.0.2.2:8080/api/v1';
    }
    return 'http://localhost:8080/api/v1';
  }
}
