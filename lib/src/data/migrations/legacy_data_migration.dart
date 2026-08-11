import 'package:smart_wrong_notebook/src/data/repositories/knowledge_point_repository.dart';
import 'package:smart_wrong_notebook/src/data/repositories/pending_knowledge_point_mapping_repository.dart';
import 'package:smart_wrong_notebook/src/data/repositories/question_knowledge_link_repository.dart';
import 'package:smart_wrong_notebook/src/data/repositories/question_repository.dart';
import 'package:smart_wrong_notebook/src/data/repositories/settings_repository.dart';
import 'package:smart_wrong_notebook/src/domain/repositories/review_log_repository.dart';
import 'package:smart_wrong_notebook/src/domain/services/knowledge_point_management_service.dart';
import 'package:smart_wrong_notebook/src/domain/services/knowledge_point_mapping_service.dart';

/// Imports pre-Drift app data exactly once, without deleting the legacy copy.
/// Completion markers are written only after a full successful migration.
///
/// 知识点迁移（Phase 4）是可选步骤：仅当注入了 [knowledgePointRepo]、
/// [questionKnowledgeLinkRepo] 和 [legacyQuestions]（用于读取题目列表）
/// 时才会执行。迁移分两步：
/// 1. 播种内置受控知识点树（[KnowledgePointManagementService.ensureSeeded]）
/// 2. 把现有题目的 `aiKnowledgePoints` 自由文本映射为结构化关联
///    （[KnowledgePointMappingService.migrateFromQuestionRecords]）
class LegacyDataMigration {
  LegacyDataMigration({
    required this.settings,
    required this.questions,
    required this.legacyQuestions,
    required this.reviewLogs,
    required this.legacyReviewLogs,
    this.knowledgePointRepo,
    this.questionKnowledgeLinkRepo,
    this.pendingKnowledgePointRepo,
  });

  static const questionMigrationKey = 'legacy_questions_to_drift_v1';
  static const reviewLogMigrationKey = 'legacy_review_logs_to_drift_v1';
  static const knowledgePointMigrationKey = 'knowledge_point_links_v1';
  static const statusKey = 'legacy_migration_status_v1';
  static const lastErrorKey = 'legacy_migration_last_error_v1';
  static const lastAttemptKey = 'legacy_migration_last_attempt_v1';

  final SettingsRepository settings;
  final QuestionRepository questions;
  final QuestionRepository legacyQuestions;
  final ReviewLogRepository reviewLogs;
  final ReviewLogRepository legacyReviewLogs;

  /// 受控知识点树仓库。注入后启用知识点树播种和题目—知识点关联迁移。
  final KnowledgePointRepository? knowledgePointRepo;

  /// 题目—知识点关联仓库。注入后启用关联迁移。
  final QuestionKnowledgeLinkRepository? questionKnowledgeLinkRepo;

  /// 「待确认知识点」队列仓库。注入后未匹配的 AI 知识点文本会被
  /// 持久化到队列中，用户可在错题详情页手动映射或忽略。null 时未匹配文本
  /// 仅被丢弃（旧行为）。
  final PendingKnowledgePointMappingRepository? pendingKnowledgePointRepo;

  Future<void> migrateIfNeeded() async {
    await settings.setString(lastAttemptKey, DateTime.now().toIso8601String());
    await settings.setString(statusKey, 'running');
    try {
      await _migrateQuestions();
      await _migrateReviewLogs();
      await _migrateKnowledgePointLinks();
      await settings.setString(statusKey, 'done');
      await settings.setString(lastErrorKey, '');
    } catch (error) {
      await settings.setString(statusKey, 'retryable');
      await settings.setString(lastErrorKey, '$error');
    }
  }

  Future<void> _migrateQuestions() async {
    if (await settings.getString(questionMigrationKey) == 'done') return;
    try {
      if ((await questions.listAll()).isEmpty) {
        final legacy = await legacyQuestions.listAll();
        if (legacy.isNotEmpty) await questions.saveDrafts(legacy);
      }
      await settings.setString(questionMigrationKey, 'done');
    } catch (error) {
      await settings.setString(lastErrorKey, 'questions: $error');
      // Keep the marker unset so a transient failure can retry next launch.
      rethrow;
    }
  }

  Future<void> _migrateReviewLogs() async {
    if (await settings.getString(reviewLogMigrationKey) == 'done') return;
    try {
      if ((await reviewLogs.listAll()).isEmpty) {
        final legacy = await legacyReviewLogs.listAll();
        for (final log in legacy) {
          await reviewLogs.insert(log);
        }
      }
      await settings.setString(reviewLogMigrationKey, 'done');
    } catch (error) {
      await settings.setString(lastErrorKey, 'review logs: $error');
      // Keep the marker unset so a transient failure can retry next launch.
      rethrow;
    }
  }

  /// 把现有题目的 `aiKnowledgePoints` 自由文本映射为受控知识点关联。
  ///
  /// 仅在注入了知识点仓库和关联仓库时执行。先播种内置知识点树，
  /// 再遍历所有题目（从生产仓库 [questions] 读取，而非 legacy），
  /// 调用 [KnowledgePointMappingService.migrateFromQuestionRecords]
  /// 生成结构化关联。未匹配的文本会被跳过（可在 UI 中手动确认）。
  Future<void> _migrateKnowledgePointLinks() async {
    if (knowledgePointRepo == null || questionKnowledgeLinkRepo == null) return;
    if (await settings.getString(knowledgePointMigrationKey) == 'done') return;
    try {
      // 1. 播种内置受控知识点树（幂等）
      final management = KnowledgePointManagementService(knowledgePointRepo!);
      await management.ensureSeeded();

      // 2. 读取所有题目，提取 aiKnowledgePoints
      final allQuestions = await questions.listAll();
      if (allQuestions.isEmpty) {
        await settings.setString(knowledgePointMigrationKey, 'done');
        return;
      }

      final inputs = <({String id, List<String> aiKnowledgePoints})>[
        for (final q in allQuestions)
          if (q.aiKnowledgePoints.isNotEmpty)
            (id: q.id, aiKnowledgePoints: q.aiKnowledgePoints),
      ];

      if (inputs.isNotEmpty) {
        final mapping = KnowledgePointMappingService(
          knowledgePointRepo!,
          questionKnowledgeLinkRepo!,
          pendingRepo: pendingKnowledgePointRepo,
        );
        // 未匹配的文本会被写入 pendingKnowledgePointRepo（若注入），
        // 供错题详情页 UI 让用户手动映射到受控知识点。
        await mapping.migrateFromQuestionRecords(inputs);
      }
      await settings.setString(knowledgePointMigrationKey, 'done');
    } catch (error) {
      await settings.setString(lastErrorKey, 'knowledge points: $error');
      // Keep the marker unset so a transient failure can retry next launch.
      rethrow;
    }
  }
}
