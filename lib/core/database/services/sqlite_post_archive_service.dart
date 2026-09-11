// lib/core/database/services/sqlite_post_archive_service.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Native SQLite Post Archive & Audit Ledger Service
// Permanently stores user-deleted property & vehicle posts in SQLite WAL
// storage so administrators can inspect and retrieve them at any time.
// ═══════════════════════════════════════════════════════════════════════

import 'dart:convert';
import 'package:drift/drift.dart';
import '../app_database.dart';

class SqlitePostArchiveService {
  final AppDatabase db;

  SqlitePostArchiveService(this.db);

  /// Ensure the archived_posts SQLite table exists
  Future<void> initializeTable() async {
    await db.customStatement('''
      CREATE TABLE IF NOT EXISTS archived_posts (
        id TEXT PRIMARY KEY,
        post_type TEXT NOT NULL,
        owner_id TEXT NOT NULL,
        title TEXT NOT NULL,
        description TEXT NOT NULL,
        category TEXT NOT NULL,
        price REAL NOT NULL,
        currency TEXT NOT NULL DEFAULT 'SLE',
        location TEXT NOT NULL,
        bedrooms INTEGER,
        bathrooms INTEGER,
        private_contact_phone TEXT,
        image_urls_json TEXT,
        original_created_at INTEGER,
        archived_at INTEGER NOT NULL
      )
    ''');
  }

  /// Permanently archive a deleted post into local SQLite
  Future<void> archivePost({
    required String id,
    required String postType,
    required String ownerId,
    required String title,
    required String description,
    required String category,
    required double price,
    String currency = 'SLE',
    required String location,
    int? bedrooms,
    int? bathrooms,
    String? privateContactPhone,
    List<String>? imageUrls,
    int? originalCreatedAt,
  }) async {
    await initializeTable();
    await db.customStatement('''
      INSERT OR REPLACE INTO archived_posts (
        id, post_type, owner_id, title, description, category,
        price, currency, location, bedrooms, bathrooms,
        private_contact_phone, image_urls_json, original_created_at, archived_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''', [
      id,
      postType,
      ownerId,
      title,
      description,
      category,
      price,
      currency,
      location,
      bedrooms,
      bathrooms,
      privateContactPhone,
      jsonEncode(imageUrls ?? []),
      originalCreatedAt ?? DateTime.now().millisecondsSinceEpoch,
      DateTime.now().millisecondsSinceEpoch,
    ]);
  }

  /// Retrieve all archived posts from SQLite (newest first)
  Future<List<Map<String, dynamic>>> getAllArchivedPosts() async {
    await initializeTable();
    final rows = await db.customSelect(
      'SELECT * FROM archived_posts ORDER BY archived_at DESC'
    ).get();
    return rows.map((r) => Map<String, dynamic>.from(r.data)).toList();
  }

  /// Retrieve an individual archived post by ID
  Future<Map<String, dynamic>?> getArchivedPostById(String id) async {
    await initializeTable();
    final rows = await db.customSelect(
      'SELECT * FROM archived_posts WHERE id = ? LIMIT 1',
      variables: [Variable.withString(id)],
    ).get();
    if (rows.isEmpty) return null;
    return Map<String, dynamic>.from(rows.first.data);
  }

  /// Count total archived posts in local SQLite
  Future<int> getArchivedPostCount() async {
    await initializeTable();
    final rows = await db.customSelect('SELECT COUNT(*) as count FROM archived_posts').get();
    if (rows.isEmpty) return 0;
    return (rows.first.data['count'] as num?)?.toInt() ?? 0;
  }
}
