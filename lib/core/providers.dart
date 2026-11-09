import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../features/bills/bills_repository.dart';
import '../features/students/students_repository.dart';
import 'api/account_api.dart';
import 'auth/auth_controller.dart';
import 'config/app_config.dart';
import 'database/app_database.dart';
import 'entitlements/entitlements.dart';
import 'sync/remote_data_source.dart';
import 'sync/sync_engine.dart';

final sharedPrefsProvider = Provider<SharedPreferences>((_) => throw UnimplementedError());

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();
  ref.onDispose(db.close);
  return db;
});

/// One Dio for the whole app: adds the bearer token, signs out on 401.
final dioProvider = Provider<Dio>((ref) {
  final dio = Dio(
    BaseOptions(baseUrl: AppConfig.apiBaseUrl, connectTimeout: const Duration(seconds: 10)),
  );
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (o, h) {
        final t = ref.read(authProvider)?.token;
        if (t != null) o.headers['Authorization'] = 'Bearer $t';
        h.next(o);
      },
      onError: (e, h) {
        final isLogin = e.requestOptions.path.endsWith('/auth/login');
        if (e.response?.statusCode == 401 && !isLogin) ref.read(authProvider.notifier).logout();
        h.next(e);
      },
    ),
  );
  return dio;
});

final remoteProvider = Provider<RemoteDataSource>(
  (ref) => AppConfig.useMockBackend
      ? MockRemoteDataSource()
      : ApiRemoteDataSource(ref.watch(dioProvider)),
);

final accountApiProvider = Provider<AccountApi>(
  (ref) => AppConfig.useMockBackend ? MockAccountApi() : DioAccountApi(ref.watch(dioProvider)),
);

final studentsRepoProvider = Provider((ref) => StudentsRepository(ref.watch(databaseProvider)));
final billsRepoProvider = Provider((ref) => BillsRepository(ref.watch(databaseProvider)));

/// Register every module's SyncHandler here.
final syncHandlersProvider = Provider<List<SyncHandler>>(
  (ref) => [ref.watch(studentsRepoProvider), ref.watch(billsRepoProvider)],
);

final syncEngineProvider = Provider(
  (ref) => SyncEngine(
    ref.watch(databaseProvider),
    ref.watch(remoteProvider),
    ref.watch(syncHandlersProvider),
  ),
);

/// If the platform cannot report connectivity (e.g. Linux without NetworkManager)
/// assume online: real requests fail gracefully and are retried from the outbox.
final isOnlineProvider = StreamProvider<bool>((ref) async* {
  bool online(List<ConnectivityResult> r) => !r.contains(ConnectivityResult.none);
  try {
    final c = Connectivity();
    yield online(await c.checkConnectivity());
    yield* c.onConnectivityChanged.map(online);
  } catch (_) {
    yield true;
  }
});

final pendingChangesProvider = StreamProvider<int>((ref) {
  final db = ref.watch(databaseProvider);
  return db.select(db.outbox).watch().map((r) => r.length);
});

/// Triggers sync on start and whenever connectivity returns.
final syncCoordinatorProvider = Provider<void>((ref) {
  Future<void> trySync() async {
    try {
      await ref.read(syncEngineProvider).sync();
      await ref.read(entitlementsProvider.notifier).refresh();
    } catch (_) {
      /* offline or server down: retry on next trigger */
    }
  }

  ref.listen(isOnlineProvider, (_, next) {
    if (next.value == true && ref.read(authProvider) != null) trySync();
  }, fireImmediately: true);
  ref.listen(authProvider, (prev, next) {
    if (prev == null && next != null) trySync(); // just logged in
  });
});

class ThemeModeController extends Notifier<ThemeMode> {
  static const _key = 'theme_mode';
  @override
  ThemeMode build() {
    final saved = ref.read(sharedPrefsProvider).getString(_key);
    return ThemeMode.values.asNameMap()[saved] ?? ThemeMode.system;
  }

  void set(ThemeMode m) {
    state = m;
    ref.read(sharedPrefsProvider).setString(_key, m.name);
  }
}

final themeModeProvider = NotifierProvider<ThemeModeController, ThemeMode>(ThemeModeController.new);

class EntitlementsController extends Notifier<Entitlements> {
  static const _key = 'entitlements';
  @override
  Entitlements build() {
    final raw = ref.read(sharedPrefsProvider).getString(_key);
    if (raw == null) return Entitlements.free;
    try {
      return Entitlements.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return Entitlements.free;
    }
  }

  Future<void> refresh() async {
    final e = await ref.read(remoteProvider).fetchEntitlements();
    state = e;
    await ref.read(sharedPrefsProvider).setString(_key, jsonEncode(e.toJson()));
  }
}

final entitlementsProvider = NotifierProvider<EntitlementsController, Entitlements>(
  EntitlementsController.new,
);

/// `ref.watch(hasFeatureProvider(Feature.bills))`
final hasFeatureProvider = Provider.family<bool, Feature>(
  (ref, f) => ref.watch(entitlementsProvider).has(f),
);
