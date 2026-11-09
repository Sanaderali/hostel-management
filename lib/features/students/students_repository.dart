import 'dart:convert';
import 'package:drift/drift.dart';
import '../../core/database/app_database.dart';
import '../../core/sync/sync_engine.dart';

const _ser = ValueSerializer.defaults(serializeDateTimeValuesAsString: true);

class StudentsRepository implements SyncHandler {
  StudentsRepository(this._db);
  final AppDatabase _db;

  @override
  String get entity => 'students';

  Stream<List<Student>> watchAll([String query = '']) {
    final q = _db.select(_db.students)
      ..where((t) => t.name.contains(query) | t.room.contains(query))
      ..orderBy([(t) => OrderingTerm.asc(t.name)]);
    return q.watch();
  }

  /// Writes locally first (instant UI) and queues the change for the server.
  Future<void> save(StudentsCompanion s) => _db.transaction(() async {
        final row = s.copyWith(updatedAt: Value(DateTime.now().toUtc()));
        await _db.into(_db.students).insertOnConflictUpdate(row);
        final saved = await (_db.select(_db.students)
              ..where((t) => t.id.equals(row.id.value)))
            .getSingle();
        await _db.into(_db.outbox).insert(OutboxCompanion.insert(
              entity: entity,
              entityId: saved.id,
              op: 'upsert',
              payload: jsonEncode(saved.toJson(serializer: _ser)),
              createdAt: DateTime.now().toUtc(),
            ));
      });

  @override
  Future<void> applyRemote(Map<String, dynamic> json) async {
    final remote = Student.fromJson(json, serializer: _ser);
    final local = await (_db.select(_db.students)
          ..where((t) => t.id.equals(remote.id)))
        .getSingleOrNull();
    if (local != null && local.updatedAt.isAfter(remote.updatedAt)) return; // local newer
    await _db.into(_db.students).insertOnConflictUpdate(remote);
  }
}
