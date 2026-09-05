// lib/core/database/app_database.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Central Drift Database Definition
// Single database instance managing all local tables, DAOs, and migrations.
// ═══════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart';
import 'connection/connection.dart';

import 'tables/sync_queue_table.dart';
import 'tables/cached_entities_table.dart';
import 'daos/sync_queue_dao.dart';
import 'daos/cached_entities_dao.dart';
import 'daos/cached_users_dao.dart';
import 'daos/cached_property_listings_dao.dart';
import 'daos/cached_vehicle_listings_dao.dart';
import 'daos/cached_bookings_dao.dart';
import 'daos/cached_driver_profiles_dao.dart';
import 'daos/cached_trips_deliveries_dao.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [
    SyncQueueTable,
    CachedPropertiesTable,
    CachedRidesTable,
    CachedWalletsTable,
    CachedTransactionsTable,
    CachedUsersTable,
    CachedPropertyListingsTable,
    CachedVehicleListingsTable,
    CachedBookingsTable,
    CachedDriverProfilesTable,
    CachedDriverVehiclesTable,
    CachedTripsDeliveriesTable,
  ],
  daos: [
    SyncQueueDao,
    CachedPropertiesDao,
    CachedRidesDao,
    CachedWalletsDao,
    CachedUsersDao,
    CachedPropertyListingsDao,
    CachedVehicleListingsDao,
    CachedBookingsDao,
    CachedDriverProfilesDao,
    CachedTripsDeliveriesDao,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(openConnection());

  /// Constructor for testing with in-memory database.
  AppDatabase.forTesting(super.e);

  @override
  int get schemaVersion => 5;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (Migrator m) async {
          await m.createAll();
        },
        onUpgrade: (Migrator m, int from, int to) async {
          if (from < 2) {
            await m.createTable(cachedUsersTable);
          }
          if (from < 3) {
            await m.createTable(cachedPropertyListingsTable);
            await m.createTable(cachedVehicleListingsTable);
          }
          if (from < 4) {
            await m.createTable(cachedBookingsTable);
          }
          if (from < 5) {
            await m.createTable(cachedDriverProfilesTable);
            await m.createTable(cachedDriverVehiclesTable);
            await m.createTable(cachedTripsDeliveriesTable);
          }
        },
        beforeOpen: (details) async {
          // Enable WAL mode for better concurrent read/write performance
          await customStatement('PRAGMA journal_mode=WAL');
          // Enable foreign keys
          await customStatement('PRAGMA foreign_keys=ON');
        },
      );
}
