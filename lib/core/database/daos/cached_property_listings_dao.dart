// lib/core/database/daos/cached_property_listings_dao.dart
// ═══════════════════════════════════════════════════════════════════════
// DAO for CachedPropertyListingsTable — Real estate marketplace cache.
// ═══════════════════════════════════════════════════════════════════════

import 'package:drift/drift.dart';
import '../app_database.dart';
import '../tables/cached_entities_table.dart';

part 'cached_property_listings_dao.g.dart';

@DriftAccessor(tables: [CachedPropertyListingsTable])
class CachedPropertyListingsDao extends DatabaseAccessor<AppDatabase>
    with _$CachedPropertyListingsDaoMixin {
  CachedPropertyListingsDao(super.db);

  /// Watch all cached properties, newest first.
  Stream<List<CachedPropertyListing>> watchAll() {
    return (select(cachedPropertyListingsTable)
          ..orderBy([(t) => OrderingTerm.desc(t.cachedAt)]))
        .watch();
  }

  /// Watch cached properties filtered by category.
  Stream<List<CachedPropertyListing>> watchByCategory(String category) {
    return (select(cachedPropertyListingsTable)
          ..where((t) => t.category.equals(category))
          ..orderBy([(t) => OrderingTerm.desc(t.cachedAt)]))
        .watch();
  }

  /// Get all cached properties.
  Future<List<CachedPropertyListing>> getAll() {
    return (select(cachedPropertyListingsTable)
          ..orderBy([(t) => OrderingTerm.desc(t.cachedAt)]))
        .get();
  }

  /// Upsert a single property listing into the cache.
  Future<void> insertOrUpdate(
      CachedPropertyListingsTableCompanion property) async {
    await into(cachedPropertyListingsTable).insertOnConflictUpdate(property);
  }

  /// Batch upsert multiple property listings into the cache.
  Future<void> insertAll(
      List<CachedPropertyListingsTableCompanion> properties) async {
    await batch((b) {
      b.insertAllOnConflictUpdate(cachedPropertyListingsTable, properties);
    });
  }

  /// Delete a single property by ID.
  Future<void> deleteById(String id) async {
    await (delete(cachedPropertyListingsTable)..where((t) => t.id.equals(id)))
        .go();
  }

  /// Clear the entire property cache.
  Future<void> clearAll() async {
    await delete(cachedPropertyListingsTable).go();
  }
}
