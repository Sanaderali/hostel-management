import 'package:dio/dio.dart';

class AuthSession {
  const AuthSession({required this.token, required this.email, required this.name});
  final String token, email, name;
}

class ApiAccess {
  const ApiAccess({required this.enabled, required this.scopes, required this.rateLimit});
  final bool enabled;
  final List<String> scopes;
  final int rateLimit;
  factory ApiAccess.fromJson(Map<String, dynamic> j) => ApiAccess(
    enabled: j['enabled'] as bool,
    scopes: (j['scopes'] as List).cast<String>(),
    rateLimit: j['rateLimit'] as int,
  );
}

class ApiKeyInfo {
  const ApiKeyInfo({
    required this.id,
    required this.name,
    required this.prefix,
    required this.scopes,
    required this.createdAt,
    this.lastUsedAt,
    this.revoked = false,
    this.fullKey,
  });
  final String id, name, prefix;
  final List<String> scopes;
  final DateTime createdAt;
  final DateTime? lastUsedAt;
  final bool revoked;

  /// Only set right after creation. The server never shows it again.
  final String? fullKey;

  ApiKeyInfo asRevoked() => ApiKeyInfo(
    id: id,
    name: name,
    prefix: prefix,
    scopes: scopes,
    createdAt: createdAt,
    revoked: true,
  );
  ApiKeyInfo withoutSecret() =>
      ApiKeyInfo(id: id, name: name, prefix: prefix, scopes: scopes, createdAt: createdAt);

  factory ApiKeyInfo.fromJson(Map<String, dynamic> j) => ApiKeyInfo(
    id: j['id'] as String,
    name: j['name'] as String,
    prefix: j['prefix'] as String,
    scopes: (j['scopes'] as List).cast<String>(),
    createdAt: DateTime.parse(j['createdAt'] as String),
    lastUsedAt: j['lastUsedAt'] == null ? null : DateTime.parse(j['lastUsedAt'] as String),
    revoked: j['revokedAt'] != null,
    fullKey: j['key'] as String?,
  );
}

/// Account-level calls: login and the user's own API keys.
abstract class AccountApi {
  Future<AuthSession> login(String email, String password);
  Future<ApiAccess> apiAccess();
  Future<List<ApiKeyInfo>> keys();
  Future<ApiKeyInfo> createKey(String name, List<String> scopes);
  Future<void> revokeKey(String id);
}

String errorMessage(Object e) {
  if (e is DioException) {
    final data = e.response?.data;
    if (data is Map && data['error'] is Map) return data['error']['message'] as String;
    if (e.response == null) return 'Cannot reach the server. Check your connection.';
  }
  return e.toString();
}

class DioAccountApi implements AccountApi {
  DioAccountApi(this._dio);
  final Dio _dio;

  @override
  Future<AuthSession> login(String email, String password) async {
    final r = await _dio.post('/auth/login', data: {'email': email, 'password': password});
    final d = r.data as Map<String, dynamic>;
    final u = d['user'] as Map<String, dynamic>;
    return AuthSession(
      token: d['token'] as String,
      email: u['email'] as String,
      name: u['name'] as String,
    );
  }

  @override
  Future<ApiAccess> apiAccess() async {
    final r = await _dio.get('/me');
    final a = (r.data as Map<String, dynamic>)['apiAccess'];
    return a == null
        ? const ApiAccess(enabled: false, scopes: [], rateLimit: 0)
        : ApiAccess.fromJson(a as Map<String, dynamic>);
  }

  @override
  Future<List<ApiKeyInfo>> keys() async {
    final r = await _dio.get('/me/api-keys');
    return [
      for (final k in (r.data['data'] as List)) ApiKeyInfo.fromJson(k as Map<String, dynamic>),
    ];
  }

  @override
  Future<ApiKeyInfo> createKey(String name, List<String> scopes) async {
    final r = await _dio.post('/me/api-keys', data: {'name': name, 'scopes': scopes});
    return ApiKeyInfo.fromJson(r.data as Map<String, dynamic>);
  }

  @override
  Future<void> revokeKey(String id) => _dio.delete('/me/api-keys/$id');
}

/// UI-only demo (USE_MOCK_BACKEND=true).
class MockAccountApi implements AccountApi {
  final _keys = <ApiKeyInfo>[];
  static const _scopes = ['students:read', 'students:write', 'bills:read', 'bills:write'];

  @override
  Future<AuthSession> login(String email, String password) async =>
      AuthSession(token: 'mock', email: email, name: 'Demo');

  @override
  Future<ApiAccess> apiAccess() async =>
      const ApiAccess(enabled: true, scopes: _scopes, rateLimit: 60);

  @override
  Future<List<ApiKeyInfo>> keys() async => List.of(_keys);

  @override
  Future<ApiKeyInfo> createKey(String name, List<String> scopes) async {
    final k = ApiKeyInfo(
      id: '${_keys.length}',
      name: name,
      prefix: 'hk_demo0000_…',
      scopes: scopes,
      createdAt: DateTime.now(),
      fullKey: 'hk_demo0000_mockkeymockkeymockkeymockkey',
    );
    _keys.add(k.withoutSecret());
    return k;
  }

  @override
  Future<void> revokeKey(String id) async {
    final i = _keys.indexWhere((k) => k.id == id);
    if (i >= 0) _keys[i] = _keys[i].asRevoked();
  }
}
