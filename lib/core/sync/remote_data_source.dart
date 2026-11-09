import 'package:dio/dio.dart';
import '../database/app_database.dart';
import '../entitlements/entitlements.dart';

class PullResult {
  const PullResult(this.items, {this.nextCursor, this.hasMore = false});
  final List<Map<String, dynamic>> items;
  final String? nextCursor;
  final bool hasMore;
}

/// Everything the app needs from the server. Swap implementations freely.
abstract class RemoteDataSource {
  Future<void> push(OutboxItem item);
  Future<PullResult> pull(String entity, String? cursor);
  Future<Entitlements> fetchEntitlements();
}

/// Real backend (REST). Endpoints are a contract to be built with the backend:
///   POST /sync/{entity}            body: {op, id, data}
///   GET  /sync/{entity}?since=...  -> {items:[...], next_cursor, has_more}
///   GET  /me/entitlements          -> Entitlements JSON
class ApiRemoteDataSource implements RemoteDataSource {
  ApiRemoteDataSource(this._dio);
  final Dio _dio;

  @override
  Future<void> push(OutboxItem item) => _dio.post('/sync/${item.entity}',
      data: {'op': item.op, 'id': item.entityId, 'data': item.payload});

  @override
  Future<PullResult> pull(String entity, String? cursor) async {
    final r = await _dio.get('/sync/$entity',
        queryParameters: {'since': ?cursor});
    final d = r.data as Map<String, dynamic>;
    return PullResult(
      (d['items'] as List).cast<Map<String, dynamic>>(),
      nextCursor: d['next_cursor'] as String?,
      hasMore: d['has_more'] as bool? ?? false,
    );
  }

  @override
  Future<Entitlements> fetchEntitlements() async {
    final r = await _dio.get('/me/entitlements');
    return Entitlements.fromJson(r.data as Map<String, dynamic>);
  }
}

/// In-memory fake so the app is fully usable before a backend exists.
class MockRemoteDataSource implements RemoteDataSource {
  @override
  Future<void> push(OutboxItem item) async {}

  @override
  Future<PullResult> pull(String entity, String? cursor) async {
    if (cursor != null) return const PullResult([]); // nothing new
    final now = DateTime.now().toUtc().toIso8601String();
    final items = switch (entity) {
      'students' => [
          for (final (i, n) in ['Moazam Naveed', 'Ali Khan', 'Usman Tariq', 'Hamza Shah'].indexed)
            {
              'id': 'stu-$i',
              'name': n,
              'course': 'Bs.c Chemistry',
              'phone': '+92 333 444 545$i',
              'location': 'Mingora swat, Pakistan',
              'room': '${27 + i}',
              'inHostel': i != 2,
              'updatedAt': now,
            }
        ],
      'bills' => [
          for (final (i, t) in ['electricity', 'water', 'gas'].indexed)
            {
              'id': 'bill-$i',
              'studentId': null,
              'type': t,
              'month': '2022-08',
              'amount': 1200.0 + i * 350,
              'paid': t == 'water',
              'updatedAt': now,
            }
        ],
      _ => <Map<String, dynamic>>[],
    };
    return PullResult(items, nextCursor: now);
  }

  @override
  Future<Entitlements> fetchEntitlements() async =>
      Entitlements.forPlan(Plan.pro, DateTime.now().add(const Duration(days: 30)));
}
