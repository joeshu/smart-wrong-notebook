import 'dart:convert';

import 'package:drift/drift.dart';
import 'package:smart_wrong_notebook/src/data/local/app_database.dart' as db;
import 'package:smart_wrong_notebook/src/domain/models/mastery_level.dart';
import 'package:smart_wrong_notebook/src/domain/models/review_log.dart' as domain;
import 'package:smart_wrong_notebook/src/domain/repositories/review_log_repository.dart';

/// Stores the complete review-log domain model in Drift.
///
/// The existing table predates result/mastery fields. `notes` therefore carries
/// a small versioned payload while the legacy columns remain queryable.
class DriftReviewLogRepository implements ReviewLogRepository {
  DriftReviewLogRepository(this._database);
  final db.AppDatabase _database;

  @override
  Future<void> insert(domain.ReviewLog log) async {
    await _database.into(_database.reviewLogs).insert(
          db.ReviewLogsCompanion.insert(
            questionId: log.questionRecordId,
            reviewedAt: log.reviewedAt,
            wasCorrect: log.result == 'mastered',
            notes: Value(jsonEncode(<String, dynamic>{
              'version': 1,
              'id': log.id,
              'result': log.result,
              'masteryAfter': log.masteryAfter.name,
            })),
          ),
        );
  }

  @override
  Future<List<domain.ReviewLog>> getByQuestionId(String questionId) async {
    final rows = await (_database.select(_database.reviewLogs)
          ..where((table) => table.questionId.equals(questionId))
          ..orderBy([(table) => OrderingTerm.asc(table.reviewedAt)]))
        .get();
    return rows.map(_toDomain).toList();
  }

  @override
  Future<List<domain.ReviewLog>> listAll() async {
    final rows = await (_database.select(_database.reviewLogs)
          ..orderBy([(table) => OrderingTerm.asc(table.reviewedAt)]))
        .get();
    return rows.map(_toDomain).toList();
  }

  @override
  Future<void> clear() async {
    await _database.delete(_database.reviewLogs).go();
  }

  /// 响应式订阅：reviewLogs 表变更时自动推送新快照。
  @override
  Stream<List<domain.ReviewLog>> watchAll() {
    return (_database.select(_database.reviewLogs)
          ..orderBy([(table) => OrderingTerm.asc(table.reviewedAt)]))
        .watch()
        .map((rows) => rows.map(_toDomain).toList());
  }

  @override
  Future<void> deleteByIds(Set<String> ids) async {
    if (ids.isEmpty) return;
    final rows = await _database.select(_database.reviewLogs).get();
    final rowIds = <int>[];
    for (final row in rows) {
      try {
        final payload = row.notes == null ? null : jsonDecode(row.notes!);
        if (payload is Map && ids.contains(payload['id'])) rowIds.add(row.id);
      } catch (_) {}
    }
    if (rowIds.isNotEmpty) {
      await (_database.delete(_database.reviewLogs)..where((table) => table.id.isIn(rowIds))).go();
    }
  }

  domain.ReviewLog _toDomain(db.ReviewLog row) {
    Map<String, dynamic>? payload;
    try {
      final decoded = row.notes == null ? null : jsonDecode(row.notes!);
      if (decoded is Map) payload = Map<String, dynamic>.from(decoded);
    } catch (_) {}
    final result = payload?['result'] is String
        ? payload!['result'] as String
        : (row.wasCorrect ? 'mastered' : 'reviewing');
    final masteryName = payload?['masteryAfter'];
    final mastery = MasteryLevel.values.firstWhere(
      (level) => level.name == masteryName,
      orElse: () => row.wasCorrect
          ? MasteryLevel.mastered
          : MasteryLevel.reviewing,
    );
    return domain.ReviewLog(
      id: payload?['id'] is String ? payload!['id'] as String : '${row.id}',
      questionRecordId: row.questionId,
      reviewedAt: row.reviewedAt,
      result: result,
      masteryAfter: mastery,
    );
  }
}
