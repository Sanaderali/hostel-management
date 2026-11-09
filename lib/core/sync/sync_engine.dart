import 'dart:async';
import 'package:drift/drift.dart';
import '../database/app_database.dart';
import 'remote_data_source.dart';

/// Implemented by each module's repository so the engine can apply server
/// changes without knowing about specific tables.
abstract class SyncHandler {
  String get entity;
  Future<void> applyRemote(Map<String, dynamic> json);
}

/// Offline-first sync: push the outbox, then pull only changes since the
/// last cursor. Safe to call any time; concurrent calls are coalesced.
class SyncEngine {
  SyncEngine(this._db, this._remote, this._handlers);
  final AppDatabase _db;
  final RemoteDataSource _remote;
  final List<SyncHandler> _handlers;
  Future<void>? _running;

  Future<void> sync() => _running ??= _run().whenComplete(() => _running = null);

  Future<void> _run() async {
    await _push();
    for (final h in _handlers) {
      await _pull(h);
    }
  }

  Future<void> _push() async {
    final items = await (_db.select(_db.outbox)
          ..orderBy([(t) => OrderingTerm.asc(t.seq)]))
        .get();
    for (final item in items) {
      try {
        await _remote.push(item);
        await (_db.delete(_db.outbox)..where((t) => t.seq.equals(item.seq))).go();
      } catch (_) {
        await (_db.update(_db.outbox)..where((t) => t.seq.equals(item.seq)))
            .write(OutboxCompanion(attempts: Value(item.attempts + 1)));
        return; // keep ordering; retry on next sync
      }
    }
  }

  Future<void> _pull(SyncHandler h) async {
    var cursor = await (_db.select(_db.syncCursors)
          ..where((t) => t.entity.equals(h.entity)))
        .getSingleOrNull()
        .then((r) => r?.cursor);
    while (true) {
      final res = await _remote.pull(h.entity, cursor);
      await _db.transaction(() async {
        for (final json in res.items) {
          await h.applyRemote(json);
        }
        if (res.nextCursor != null) {
          await _db.into(_db.syncCursors).insertOnConflictUpdate(
              SyncCursorsCompanion.insert(entity: h.entity, cursor: res.nextCursor!));
        }
      });
      cursor = res.nextCursor ?? cursor;
      if (!res.hasMore) break;
    }
  }
}
