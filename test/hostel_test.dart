import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hostel_management/core/database/app_database.dart';
import 'package:hostel_management/core/entitlements/entitlements.dart';
import 'package:hostel_management/core/sync/remote_data_source.dart';
import 'package:hostel_management/core/sync/sync_engine.dart';
import 'package:hostel_management/features/bills/bills_repository.dart';
import 'package:hostel_management/features/students/students_repository.dart';

class _FlakyRemote extends MockRemoteDataSource {
  bool online = false;
  final pushed = <String>[];
  @override
  Future<void> push(OutboxItem item) async {
    if (!online) throw Exception('offline');
    pushed.add(item.entityId);
  }
}

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase(NativeDatabase.memory()));
  tearDown(() => db.close());

  test('entitlements gate features and expire to free tier', () {
    final pro = Entitlements.forPlan(Plan.pro, DateTime.now().add(const Duration(days: 1)));
    expect(pro.has(Feature.reports), isTrue);
    final lapsed = Entitlements.forPlan(Plan.pro, DateTime.now().subtract(const Duration(days: 1)));
    expect(lapsed.has(Feature.reports), isFalse);
    expect(lapsed.has(Feature.students), isTrue);
    expect(Entitlements.fromJson(pro.toJson()).plan, Plan.pro);
  });

  test('offline writes are queued, then pushed once online; pull is delta-only', () async {
    final students = StudentsRepository(db);
    final remote = _FlakyRemote();
    final engine = SyncEngine(db, remote, [students, BillsRepository(db)]);

    await students.save(StudentsCompanion.insert(
        id: 'local-1', name: 'Offline Student', updatedAt: DateTime.now()));
    await engine.sync(); // offline: push fails, item stays queued
    expect((await db.select(db.outbox).get()).single.attempts, 1);

    remote.online = true;
    await engine.sync();
    expect(await db.select(db.outbox).get(), isEmpty);
    expect(remote.pushed, ['local-1']);
    expect((await db.select(db.students).get()).length, 5); // 4 seeded + 1 local
    expect(await db.select(db.syncCursors).get(), hasLength(2));

    await engine.sync(); // cursor set -> nothing new downloaded
    expect((await db.select(db.students).get()).length, 5);
  });
}
