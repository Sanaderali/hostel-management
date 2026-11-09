import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../api/account_api.dart';
import '../config/app_config.dart';
import '../providers.dart';

/// Holds the logged-in session (null = signed out). Token is cached so the app
/// opens straight into the offline data, even without internet.
class AuthController extends Notifier<AuthSession?> {
  static const _t = 'auth_token', _e = 'auth_email', _n = 'auth_name';

  @override
  AuthSession? build() {
    if (AppConfig.useMockBackend) {
      return const AuthSession(token: 'mock', email: 'demo@local', name: 'Demo');
    }
    final p = ref.read(sharedPrefsProvider);
    final token = p.getString(_t);
    if (token == null) return null;
    return AuthSession(token: token, email: p.getString(_e) ?? '', name: p.getString(_n) ?? '');
  }

  Future<void> login(String email, String password) async {
    final s = await ref.read(accountApiProvider).login(email.trim(), password);
    final p = ref.read(sharedPrefsProvider);
    await p.setString(_t, s.token);
    await p.setString(_e, s.email);
    await p.setString(_n, s.name);
    state = s;
  }

  /// Signing out removes the token AND this hostel's local data, so the next
  /// user of the device never sees it.
  Future<void> logout() async {
    final p = ref.read(sharedPrefsProvider);
    for (final k in [_t, _e, _n, 'entitlements']) {
      await p.remove(k);
    }
    await ref.read(databaseProvider).wipe();
    ref.invalidate(entitlementsProvider);
    state = null;
  }
}

final authProvider = NotifierProvider<AuthController, AuthSession?>(AuthController.new);
