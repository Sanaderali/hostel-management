import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'app_database.g.dart';

class Students extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  TextColumn get course => text().withDefault(const Constant(''))();
  TextColumn get phone => text().withDefault(const Constant(''))();
  TextColumn get location => text().withDefault(const Constant(''))();
  TextColumn get room => text().withDefault(const Constant(''))();
  BoolColumn get inHostel => boolean().withDefault(const Constant(true))();
  DateTimeColumn get updatedAt => dateTime()();
  @override
  Set<Column> get primaryKey => {id};
}

class Bills extends Table {
  TextColumn get id => text()();
  TextColumn get studentId => text().nullable()();
  TextColumn get type => text()(); // electricity | water | gas | ...
  TextColumn get month => text()(); // "2022-08"
  RealColumn get amount => real().withDefault(const Constant(0))();
  BoolColumn get paid => boolean().withDefault(const Constant(false))();
  DateTimeColumn get updatedAt => dateTime()();
  @override
  Set<Column> get primaryKey => {id};
}

/// Local writes waiting to be pushed to the server (offline queue).
@DataClassName('OutboxItem')
class Outbox extends Table {
  IntColumn get seq => integer().autoIncrement()();
  TextColumn get entity => text()();
  TextColumn get entityId => text()();
  TextColumn get op => text()(); // upsert | delete
  TextColumn get payload => text()(); // JSON
  DateTimeColumn get createdAt => dateTime()();
  IntColumn get attempts => integer().withDefault(const Constant(0))();
}

/// Per-entity "last synced" cursor so we only ever download deltas.
class SyncCursors extends Table {
  TextColumn get entity => text()();
  TextColumn get cursor => text()();
  @override
  Set<Column> get primaryKey => {entity};
}

@DriftDatabase(tables: [Students, Bills, Outbox, SyncCursors])
class AppDatabase extends _$AppDatabase {
  AppDatabase([QueryExecutor? executor])
      : super(executor ?? driftDatabase(name: 'hostel_db'));

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (m, from, to) async {
          // Add stepwise migrations here as modules add tables/columns.
        },
      );
}
