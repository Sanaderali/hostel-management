import 'dart:convert';

import 'package:drift/drift.dart';

import '../../core/database/app_database.dart';
import '../../core/sync/sync_engine.dart';

const _ser = ValueSerializer.defaults(serializeDateTimeValuesAsString: true);

enum BillFilter { all, paid, unpaid }

class BillsRepository implements SyncHandler {
  BillsRepository(this._db);
  final AppDatabase _db;

  @override
  String get entity => 'bills';

  Stream<List<Bill>> watch(BillFilter f) {
    final q = _db.select(_db.bills)
      ..where(
        (t) => switch (f) {
          BillFilter.all => const Constant(true),
          BillFilter.paid => t.paid.equals(true),
          BillFilter.unpaid => t.paid.equals(false),
        },
      )
      ..orderBy([(t) => OrderingTerm.desc(t.month)]);
    return q.watch();
  }

  Future<void> setPaid(Bill bill, bool paid) => _db.transaction(() async {
    final updated = bill.copyWith(paid: paid, updatedAt: DateTime.now().toUtc());
    await _db.into(_db.bills).insertOnConflictUpdate(updated);
    await _db
        .into(_db.outbox)
        .insert(
          OutboxCompanion.insert(
            entity: entity,
            entityId: bill.id,
            op: 'upsert',
            payload: jsonEncode(updated.toJson(serializer: _ser)),
            createdAt: DateTime.now().toUtc(),
          ),
        );
  });

  @override
  Future<void> applyRemote(Map<String, dynamic> json) async {
    final remote = Bill.fromJson(json, serializer: _ser);
    final local = await (_db.select(
      _db.bills,
    )..where((t) => t.id.equals(remote.id))).getSingleOrNull();
    if (local != null && local.updatedAt.isAfter(remote.updatedAt)) return;
    await _db.into(_db.bills).insertOnConflictUpdate(remote);
  }
}
