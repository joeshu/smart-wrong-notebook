import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smart_wrong_notebook/src/app/onboarding_notifier.dart';
import 'package:smart_wrong_notebook/src/app/theme/app_visual_style.dart';
import 'package:smart_wrong_notebook/src/data/local/app_database.dart' hide QuestionRecord, ReviewLog, GeneratedExercise;
import 'package:smart_wrong_notebook/src/data/files/image_storage_service.dart';
import 'package:smart_wrong_notebook/src/data/remote/ai/ai_analysis_service.dart';
import 'package:smart_wrong_notebook/src/data/repositories/drift_question_repository.dart';
import 'package:smart_wrong_notebook/src/data/repositories/drift_review_log_repository.dart';
import 'package:smart_wrong_notebook/src/data/repositories/drift_settings_repository.dart';
import 'package:smart_wrong_notebook/src/data/repositories/question_repository.dart';
import 'package:smart_wrong_notebook/src/data/repositories/knowledge_point_repository.dart';
import 'package:smart_wrong_notebook/src/data/repositories/mistake_knowledge_link_repository.dart';
import 'package:smart_wrong_notebook/src/data/repositories/pending_knowledge_point_mapping_repository.dart';
import 'package:smart_wrong_notebook/src/data/repositories/question_knowledge_link_repository.dart';
import 'package:smart_wrong_notebook/src/data/repositories/layout_provider_repository.dart';
import 'package:smart_wrong_notebook/src/data/repositories/worksheet_import_repository.dart';
import 'package:smart_wrong_notebook/src/data/repositories/worksheet_draft_repository.dart';
import 'package:smart_wrong_notebook/src/data/repositories/settings_repository.dart';
import 'package:smart_wrong_notebook/src/domain/repositories/review_log_repository.dart';
import 'package:smart_wrong_notebook/src/data/services/capture_service.dart';
import 'package:smart_wrong_notebook/src/data/services/notification_service.dart';
import 'package:smart_wrong_notebook/src/data/services/ocr_service.dart';
import 'package:smart_wrong_notebook/src/data/services/question_region_crop_service.dart';
import 'package:smart_wrong_notebook/src/data/services/question_split_service.dart';
import 'package:smart_wrong_notebook/src/data/services/vision_document_layout_service.dart';
import 'package:smart_wrong_notebook/src/domain/models/capture_mode.dart';
import 'package:smart_wrong_notebook/src/domain/models/content_status.dart';
import 'package:smart_wrong_notebook/src/domain/models/layout_provider_config.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_split_result.dart';
import 'package:smart_wrong_notebook/src/domain/models/generated_exercise.dart';
import 'package:smart_wrong_notebook/src/domain/models/knowledge_point.dart';
import 'package:smart_wrong_notebook/src/domain/models/knowledge_point_mastery.dart';
import 'package:smart_wrong_notebook/src/domain/models/mastery_level.dart';
import 'package:smart_wrong_notebook/src/domain/models/mistake_category.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_type.dart';
import 'package:smart_wrong_notebook/src/domain/models/learning_context.dart';
import 'package:smart_wrong_notebook/src/domain/models/pending_knowledge_point_mapping.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_knowledge_link.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_split_session.dart';
import 'package:smart_wrong_notebook/src/domain/models/recommendation.dart';
import 'package:smart_wrong_notebook/src/domain/models/review_log.dart';
import 'package:smart_wrong_notebook/src/domain/models/worksheet_import_session.dart';
import 'package:smart_wrong_notebook/src/domain/models/worksheet_draft.dart';
import 'package:smart_wrong_notebook/src/domain/models/worksheet_review_summary.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';
import 'package:smart_wrong_notebook/src/domain/services/knowledge_point_mapping_service.dart';
import 'package:smart_wrong_notebook/src/domain/services/knowledge_point_management_service.dart';
import 'package:smart_wrong_notebook/src/domain/services/knowledge_point_mastery_service.dart';
import 'package:smart_wrong_notebook/src/domain/services/analysis_recovery_service.dart';
import 'package:smart_wrong_notebook/src/domain/services/worksheet_assembly_service.dart';
import 'package:smart_wrong_notebook/src/domain/services/recommendation_service.dart';
import 'package:smart_wrong_notebook/src/domain/services/review_schedule_service.dart';
import 'package:smart_wrong_notebook/src/shared/models/question_display_status.dart';
import 'package:smart_wrong_notebook/src/shared/utils/export_history_service.dart';

// Shared invalidation counter used by the question/review projections.
final StateProvider<int> listVersionProvider = StateProvider<int>((ref) => 0);

// --- Repository providers (default implementations) ---

const bool _isFlutterTest = bool.fromEnvironment('FLUTTER_TEST');

/// 默认业务数据库实例。
///
/// 生产环境在 [main] 中覆盖为启动阶段创建的实例；测试或独立入口使用
/// 默认实现时，所有 Drift 仓库也会共享这一实例，而不是各自打开数据库。
final Provider<AppDatabase> appDatabaseProvider = Provider<AppDatabase>((ref) {
  const isTest = bool.fromEnvironment('FLUTTER_TEST');
  final database = isTest ? AppDatabase.memory() : AppDatabase();
  if (isTest) {
    ref.onDispose(database.close);
  }
  return database;
});

final Provider<QuestionRepository> questionRepositoryProvider =
    Provider<QuestionRepository>((ref) {
  if (_isFlutterTest) return InMemoryQuestionRepository();
  return DriftQuestionRepository(ref.read(appDatabaseProvider));
});

final Provider<LayoutProviderRepository> layoutProviderRepositoryProvider =
    Provider<LayoutProviderRepository>((ref) => LayoutProviderRepository());

final Provider<WorksheetImportRepository> worksheetImportRepositoryProvider =
    Provider<WorksheetImportRepository>((ref) => WorksheetImportRepository());

/// 受控知识点树仓库（Phase 4）。
final Provider<KnowledgePointRepository> knowledgePointRepositoryProvider =
    Provider<KnowledgePointRepository>((ref) => KnowledgePointRepository());

/// 题目—知识点关联仓库（Phase 4）。
final Provider<QuestionKnowledgeLinkRepository>
    questionKnowledgeLinkRepositoryProvider =
    Provider<QuestionKnowledgeLinkRepository>(
        (ref) => QuestionKnowledgeLinkRepository());

/// 「待确认知识点」队列仓库（Phase 4-C）。
/// AI 返回但未匹配到受控节点的知识点文本会被持久化到本队列，
/// 用户可在错题详情页手动映射或忽略。
final Provider<PendingKnowledgePointMappingRepository>
    pendingKnowledgePointMappingRepositoryProvider =
    Provider<PendingKnowledgePointMappingRepository>((ref) {
  return PendingKnowledgePointMappingRepository();
});

/// 错因—知识点—题目三元关联仓库（Phase 4）。
final Provider<MistakeKnowledgeLinkRepository>
    mistakeKnowledgeLinkRepositoryProvider =
    Provider<MistakeKnowledgeLinkRepository>(
        (ref) => MistakeKnowledgeLinkRepository());

/// 知识点树快照，供 UI 消费。调用 [knowledgePointRepositoryProvider] 加载后
/// 缓存在 StateController 中，通过 [_knowledgePointVersionProvider] 触发刷新。
final StateProvider<int> _knowledgePointVersionProvider =
    StateProvider<int>((ref) => 0);

final FutureProvider<List<KnowledgePoint>> knowledgePointTreeProvider =
    FutureProvider<List<KnowledgePoint>>((ref) async {
  ref.watch(_knowledgePointVersionProvider);
  return ref.read(knowledgePointRepositoryProvider).loadAll();
});

/// 知识点树变更后调用，刷新 [knowledgePointTreeProvider]。
void invalidateKnowledgePointTree(WidgetRef ref) {
  ref.read(_knowledgePointVersionProvider.notifier).state++;
}

/// 知识点映射服务（Phase 4）：AI 自由文本 → 受控知识点 ID。
/// Phase 4-C：注入 [PendingKnowledgePointMappingRepository]，
/// 未匹配文本会进入待确认队列供 UI 手动映射。
final Provider<KnowledgePointMappingService> knowledgePointMappingServiceProvider =
    Provider<KnowledgePointMappingService>((ref) {
  return KnowledgePointMappingService(
    ref.read(knowledgePointRepositoryProvider),
    ref.read(questionKnowledgeLinkRepositoryProvider),
    pendingRepo: ref.read(pendingKnowledgePointMappingRepositoryProvider),
  );
});

/// 知识点树管理服务（Phase 4）：CRUD、启用/停用、合并、首次播种。
final Provider<KnowledgePointManagementService>
    knowledgePointManagementServiceProvider =
    Provider<KnowledgePointManagementService>((ref) {
  return KnowledgePointManagementService(
    ref.read(knowledgePointRepositoryProvider),
  );
});

/// 知识点掌握度计算服务（Phase 4）。
final Provider<KnowledgePointMasteryService>
    knowledgePointMasteryServiceProvider =
    Provider<KnowledgePointMasteryService>((ref) {
  return KnowledgePointMasteryService(
    ref.read(questionKnowledgeLinkRepositoryProvider),
  );
});

/// 薄弱点推荐服务（Phase 4）。
final Provider<RecommendationService> recommendationServiceProvider =
    Provider<RecommendationService>((ref) {
  return RecommendationService();
});

final Provider<SettingsRepository> settingsRepositoryProvider =
    Provider<SettingsRepository>((ref) {
  if (_isFlutterTest) return InMemorySettingsRepository();
  return DriftSettingsRepository(ref.read(appDatabaseProvider));
});

// Production overrides this with a real OnboardingNotifier in main().
final Provider<OnboardingNotifier> onboardingNotifierProvider =
    Provider<OnboardingNotifier>((ref) {
  return OnboardingNotifier(initialDone: true);
});

// Production overrides this with DriftReviewLogRepository in main().
final Provider<ReviewLogRepository> reviewLogRepositoryProvider =
    Provider<ReviewLogRepository>(
        (ref) => _isFlutterTest
            ? InMemoryReviewLogRepository()
            : DriftReviewLogRepository(ref.read(appDatabaseProvider)));
