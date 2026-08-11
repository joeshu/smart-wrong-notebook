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


import 'repository_providers.dart';
import 'service_providers.dart';
import 'review_providers.dart';

/// Holds selected worksheet pages while the user processes them one by one.
/// Persistence/queueing is intentionally added in the next import slice.
final StateProvider<LayoutProviderConfig> layoutProviderConfigProvider =
    StateProvider<LayoutProviderConfig>((ref) =>
        const LayoutProviderConfig(type: LayoutProviderType.currentVision));

final StateProvider<LayoutProviderType?> oneShotLayoutProviderTypeProvider =
    StateProvider<LayoutProviderType?>((ref) => null);

Future<LayoutProviderConfig> restoreLayoutProviderConfig(WidgetRef ref) async {
  final config = await ref.read(layoutProviderRepositoryProvider).load();
  ref.read(layoutProviderConfigProvider.notifier).state = config;
  return config;
}

Future<void> persistLayoutProviderConfig(
    WidgetRef ref, LayoutProviderConfig config) async {
  await ref.read(layoutProviderRepositoryProvider).save(config);
  ref.read(layoutProviderConfigProvider.notifier).state = config;
}

final StateProvider<List<String>> worksheetDraftQuestionIdsProvider =
    StateProvider<List<String>>((ref) => const <String>[]);

/// Phase 8-4：试卷预览页要展示的题目 ID 列表（保留顺序）。
///
/// 工作台预览按钮写入后跳 `/worksheet/preview`，预览页首帧读取。
final StateProvider<List<String>> worksheetPreviewQuestionIdsProvider =
    StateProvider<List<String>>((ref) => const <String>[]);

/// Phase 13-1：智能组卷服务（基于薄弱点 + 难度 + 题型加权采样）。
final Provider<WorksheetAssemblyService> worksheetAssemblyServiceProvider =
    Provider<WorksheetAssemblyService>((ref) {
  return WorksheetAssemblyService();
});

/// Phase 13-1：智能组卷所需的输入数据快照。
///
/// 把题目列表、知识点掌握度、题目-知识点主关联聚合成一次调用所需
/// 的数据，避免 service 直接 watch provider（保持 service 纯函数式）。
/// 参数类型为 [WidgetRef]：当前唯一调用方是组卷工作台（ConsumerState），
/// `WidgetRef.read` 与 `Ref.read` 语义一致，复用同一份聚合逻辑。
Future<WorksheetAssemblyInput> fetchWorksheetAssemblyInput(
  WidgetRef ref,
) async {
  final questions = await ref.read(questionListProvider.future);
  final linkRepo = ref.read(questionKnowledgeLinkRepositoryProvider);
  final allLinks = await linkRepo.allLinks();
  // 取每道题的主知识点（isPrimary=true 优先，否则取第一条）。
  final questionKpLinks = <String, String>{};
  for (final link in allLinks) {
    final existing = questionKpLinks[link.questionId];
    if (link.isPrimary || existing == null) {
      questionKpLinks[link.questionId] = link.knowledgePointId;
    }
  }
  // 掌握度快照：复用 weakPointRecommendationsProvider 已经算好的结果。
  final masteryByKp = <String, KnowledgePointMastery>{};
  final recs = ref.read(weakPointRecommendationsProvider).maybeWhen(
        data: (list) => list,
        orElse: () => const <WeakPointRecommendation>[],
      );
  for (final rec in recs) {
    if (rec.mastery != null) {
      masteryByKp[rec.recommendation.knowledgePointId] = rec.mastery!;
    }
  }
  return WorksheetAssemblyInput(
    questions: questions,
    masteryByKp: masteryByKp,
    questionKpLinks: questionKpLinks,
  );
}

/// Phase 13-1：智能组卷输入数据包。
class WorksheetAssemblyInput {
  const WorksheetAssemblyInput({
    required this.questions,
    required this.masteryByKp,
    required this.questionKpLinks,
  });

  final List<QuestionRecord> questions;
  final Map<String, KnowledgePointMastery> masteryByKp;
  final Map<String, String> questionKpLinks;
}

/// 组卷草稿与历史组卷仓库（Phase 5）。
final Provider<WorksheetDraftRepository> worksheetDraftRepositoryProvider =
    Provider<WorksheetDraftRepository>((ref) {
  return WorksheetDraftRepository();
});

/// 所有已保存的组卷草稿（按 updatedAt 降序）。
/// 在工作台「历史」对话框中消费；保存/删除后调用 invalidate 刷新。
final FutureProvider<List<WorksheetDraft>> savedWorksheetDraftsProvider =
    FutureProvider<List<WorksheetDraft>>((ref) {
  return ref.watch(worksheetDraftRepositoryProvider).loadAll();
});

final StateProvider<WorksheetImportSession?> currentWorksheetImportProvider =
    StateProvider<WorksheetImportSession?>((ref) => null);

/// 从持久化仓库恢复上次未完成的导入批次。
///
/// 在 app 启动时调用，避免 App 被系统杀掉后批次状态丢失。
/// 返回恢复的 session（同时写入 [currentWorksheetImportProvider]）；
/// 无草稿时返回 null。
Future<WorksheetImportSession?> restoreWorksheetImport(WidgetRef ref) async {
  final restored = await ref.read(worksheetImportRepositoryProvider).load();
  ref.read(currentWorksheetImportProvider.notifier).state = restored;
  return restored;
}

/// 仅读取持久化仓库中的批次，不依赖 WidgetRef。
/// 用于 app 启动时（ProviderScope 尚未建立）预加载批次。
Future<WorksheetImportSession?> loadWorksheetImportSession(
    WorksheetImportRepository repository) async {
  return repository.load();
}

Future<void> persistWorksheetImport(
    WidgetRef ref, WorksheetImportSession? session) async {
  final repository = ref.read(worksheetImportRepositoryProvider);
  if (session == null) {
    await repository.clear();
  } else {
    await repository.save(session);
  }
  ref.read(currentWorksheetImportProvider.notifier).state = session;
}

final StateProvider<WorksheetReviewSummary?> currentWorksheetReviewSummaryProvider =
    StateProvider<WorksheetReviewSummary?>((ref) => null);

/// Whether the worksheet importer should continue through remaining question
/// candidates without opening a result page after every successful analysis.
final StateProvider<bool> worksheetAutoAnalyzeProvider =
    StateProvider<bool>((ref) => false);

/// 统一更新 [worksheetAutoAnalyzeProvider] 并把状态同步进当前 session（持久化）。
///
/// 在跨进程恢复时，[WorksheetImportRepository.load] 会从持久化读回 autoAnalyze，
/// 启动后由 main.dart 通过 override 写入 [worksheetAutoAnalyzeProvider]；运行期
/// 调用本 helper 才能保证两者一致。session 不存在时仅更新内存状态（兼容单题
/// 流程或测试场景）。
Future<void> setWorksheetAutoAnalyze(WidgetRef ref, bool value) async {
  ref.read(worksheetAutoAnalyzeProvider.notifier).state = value;
  final session = ref.read(currentWorksheetImportProvider);
  if (session == null || session.autoAnalyze == value) return;
  await persistWorksheetImport(ref, session.copyWith(autoAnalyze: value));
}

// --- Notebook filter state ---

final StateProvider<Subject?> selectedSubjectFilterProvider =
    StateProvider<Subject?>((ref) => null);

final StateProvider<MasteryLevel?> selectedMasteryFilterProvider =
    StateProvider<MasteryLevel?>((ref) => null);

final StateProvider<bool> unmasteredOnlyFilterProvider =
    StateProvider<bool>((ref) => false);

final StateProvider<MistakeCategory?> selectedMistakeCategoryFilterProvider =
    StateProvider<MistakeCategory?>((ref) => null);

enum QuestionSort { newest, oldest, nextReview, mastery, subject }

enum QuestionDateRange { all, last7Days, last30Days }

final StateProvider<QuestionDateRange> questionDateRangeProvider =
    StateProvider<QuestionDateRange>((ref) => QuestionDateRange.all);

final StateProvider<bool> dueOnlyFilterProvider =
    StateProvider<bool>((ref) => false);

final StateProvider<bool> favoritesOnlyFilterProvider =
    StateProvider<bool>((ref) => false);

final StateProvider<bool> failedOnlyFilterProvider =
    StateProvider<bool>((ref) => false);

/// 仅显示识别失败题目（ContentStatus.failed → recognitionFailed）。
/// 与 [failedOnlyFilterProvider] 互补：后者同时匹配识别失败与分析失败，
/// 此 Provider 仅匹配识别失败，便于首页"分开统计识别失败与 AI 分析失败"。
final StateProvider<bool> recognitionFailedOnlyFilterProvider =
    StateProvider<bool>((ref) => false);

/// 仅显示 AI 分析失败题目（ContentStatus.analysisFailed → analysisFailed）。
final StateProvider<bool> analysisFailedOnlyFilterProvider =
    StateProvider<bool>((ref) => false);

/// 仅显示待校对题目（OCR 已成功但低置信度，需人工确认）。
/// 与 [pendingAiOnlyFilterProvider] 互补：后者仅匹配 recognized 状态，
/// 此 Provider 额外要求 ocrConfidence < 0.7，便于首页"分开统计待校对与低置信度"。
final StateProvider<bool> pendingProofreadOnlyFilterProvider =
    StateProvider<bool>((ref) => false);

final StateProvider<bool> pendingAiOnlyFilterProvider =
    StateProvider<bool>((ref) => false);

final StateProvider<bool> lowConfidenceOnlyFilterProvider =
    StateProvider<bool>((ref) => false);

final StateProvider<QuestionSort> questionSortProvider =
    StateProvider<QuestionSort>((ref) => QuestionSort.newest);

final StateProvider<String?> selectedSourceFilterProvider =
    StateProvider<String?>((ref) => null);

final StateProvider<String?> selectedLearningStageFilterProvider =
    StateProvider<String?>((ref) => null);

final StateProvider<QuestionDifficulty?> selectedDifficultyFilterProvider =
    StateProvider<QuestionDifficulty?>((ref) => null);

final StateProvider<AttemptStatus?> selectedAttemptStatusFilterProvider =
    StateProvider<AttemptStatus?>((ref) => null);

/// 题型筛选（Phase 6-2）。`null` 表示不限制题型。
final StateProvider<QuestionType?> selectedQuestionTypeFilterProvider =
    StateProvider<QuestionType?>((ref) => null);

final StateProvider<String> searchQueryProvider =
    StateProvider<String>((ref) => '');

final StateProvider<String?> selectedKnowledgePointFilterProvider =
    StateProvider<String?>((ref) => null);

// 多选标签过滤
final StateProvider<List<String>> selectedTagsFilterProvider =
    StateProvider<List<String>>((ref) => []);

final StreamProvider<List<String>> allLearningStagesProvider =
    StreamProvider<List<String>>((ref) {
  ref.watch(listVersionProvider);
  return ref.watch(questionListProvider).when(
        data: (all) => Stream.value(all
            .map((question) => question.learningStage)
            .whereType<String>()
            .toSet()
            .toList()
          ..sort()),
        loading: () => const Stream.empty(),
        error: (e, _) => Stream.error(e, _),
      );
});

final StreamProvider<List<String>> allSourcesProvider =
    StreamProvider<List<String>>((ref) {
  ref.watch(listVersionProvider);
  return ref.watch(questionListProvider).when(
        data: (all) {
          final sources = all
              .map((question) => question.source)
              .whereType<String>()
              .toSet();
          return Stream.value(sources.toList()..sort());
        },
        loading: () => const Stream.empty(),
        error: (e, _) => Stream.error(e, _),
      );
});

// --- All tags provider ---
final StreamProvider<List<String>> allTagsProvider =
    StreamProvider<List<String>>((ref) {
  ref.watch(listVersionProvider);
  return ref.watch(questionListProvider).when(
        data: (all) {
          final tags = <String>{};
          for (final q in all) {
            tags.addAll(q.aiTags);
            tags.addAll(q.aiKnowledgePoints);
            tags.addAll(q.customTags);
          }
          return Stream.value(tags.toList()..sort());
        },
        loading: () => const Stream.empty(),
        error: (e, _) => Stream.error(e, _),
      );
});

final StreamProvider<List<String>> allKnowledgePointsProvider =
    StreamProvider<List<String>>((ref) {
  ref.watch(listVersionProvider);
  return ref.watch(questionListProvider).when(
        data: (all) {
          final points = <String>{};
          for (final question in all) {
            points.addAll(question.aiKnowledgePoints);
          }
          return Stream.value(points.toList()..sort());
        },
        loading: () => const Stream.empty(),
        error: (e, _) => Stream.error(e, _),
      );
});

// --- Filtered notebook list ---

final StreamProvider<List<QuestionRecord>> filteredQuestionListProvider =
    StreamProvider<List<QuestionRecord>>((ref) {
  ref.watch(listVersionProvider);

  final subject = ref.watch(selectedSubjectFilterProvider);
  final mastery = ref.watch(selectedMasteryFilterProvider);
  final unmasteredOnly = ref.watch(unmasteredOnlyFilterProvider);
  final mistakeCategory = ref.watch(selectedMistakeCategoryFilterProvider);
  final dueOnly = ref.watch(dueOnlyFilterProvider);
  final favoritesOnly = ref.watch(favoritesOnlyFilterProvider);
  final failedOnly = ref.watch(failedOnlyFilterProvider);
  final recognitionFailedOnly = ref.watch(recognitionFailedOnlyFilterProvider);
  final analysisFailedOnly = ref.watch(analysisFailedOnlyFilterProvider);
  final pendingProofreadOnly = ref.watch(pendingProofreadOnlyFilterProvider);
  final pendingAiOnly = ref.watch(pendingAiOnlyFilterProvider);
  final lowConfidenceOnly = ref.watch(lowConfidenceOnlyFilterProvider);
  final dateRange = ref.watch(questionDateRangeProvider);
  final source = ref.watch(selectedSourceFilterProvider);
  final learningStage = ref.watch(selectedLearningStageFilterProvider);
  final difficulty = ref.watch(selectedDifficultyFilterProvider);
  final attemptStatus = ref.watch(selectedAttemptStatusFilterProvider);
  final questionType = ref.watch(selectedQuestionTypeFilterProvider);
  final sort = ref.watch(questionSortProvider);
  final query = ref.watch(searchQueryProvider).toLowerCase();
  final knowledgePoint = ref.watch(selectedKnowledgePointFilterProvider);
  final selectedTags = ref.watch(selectedTagsFilterProvider);

  const scheduler = ReviewScheduleService();
  final now = DateTime.now();

  return ref.watch(questionListProvider).when(
        data: (all) {
          final filtered = all.where((QuestionRecord q) {
            if (subject != null && q.subject != subject) return false;
            if (mastery != null && q.masteryLevel != mastery) return false;
            if (unmasteredOnly && q.masteryLevel == MasteryLevel.mastered) {
              return false;
            }
            if (mistakeCategory != null && q.mistakeCategory != mistakeCategory) {
              return false;
            }
            if (dueOnly && !scheduler.isDue(q)) return false;
            if (favoritesOnly && !q.isFavorite) return false;
            if (failedOnly && !inferQuestionDisplayStatus(q).isFailed) {
              return false;
            }
            if (recognitionFailedOnly &&
                inferQuestionDisplayStatus(q) !=
                    QuestionDisplayStatus.recognitionFailed) {
              return false;
            }
            if (analysisFailedOnly &&
                inferQuestionDisplayStatus(q) !=
                    QuestionDisplayStatus.analysisFailed) {
              return false;
            }
            if (pendingProofreadOnly &&
                !(inferQuestionDisplayStatus(q) ==
                        QuestionDisplayStatus.recognized &&
                    q.ocrConfidence != null &&
                    q.ocrConfidence! < 0.7)) {
              return false;
            }
            if (pendingAiOnly &&
                inferQuestionDisplayStatus(q) !=
                    QuestionDisplayStatus.recognized) {
              return false;
            }
            if (lowConfidenceOnly &&
                !(q.ocrConfidence != null && q.ocrConfidence! < 0.7)) {
              return false;
            }
            if (!_isWithinDateRange(q.createdAt, dateRange, now)) return false;
            if (source != null && q.source != source) return false;
            if (learningStage != null && q.learningStage != learningStage) {
              return false;
            }
            if (difficulty != null && q.difficulty != difficulty) return false;
            if (attemptStatus != null && q.attemptStatus != attemptStatus) {
              return false;
            }
            if (questionType != null && q.questionType != questionType) {
              return false;
            }
            if (query.isNotEmpty &&
                !q.normalizedQuestionText.toLowerCase().contains(query)) {
              return false;
            }
            if (knowledgePoint != null && knowledgePoint.isNotEmpty) {
              final kps = q.aiKnowledgePoints;
              if (!kps.any((kp) => kp.contains(knowledgePoint))) return false;
            }
            if (selectedTags.isNotEmpty) {
              final allQTags = [...q.aiKnowledgePoints, ...q.customTags];
              for (final tag in selectedTags) {
                if (!allQTags.any((t) => t.contains(tag))) return false;
              }
            }
            return true;
          }).toList();

          filtered.sort((a, b) {
            switch (sort) {
              case QuestionSort.newest:
                return b.createdAt.compareTo(a.createdAt);
              case QuestionSort.oldest:
                return a.createdAt.compareTo(b.createdAt);
              case QuestionSort.nextReview:
                final aAt = a.nextReviewAt ?? a.createdAt;
                final bAt = b.nextReviewAt ?? b.createdAt;
                return aAt.compareTo(bAt);
              case QuestionSort.mastery:
                // 掌握度低到高：newQuestion(0) → reviewing(1) → mastered(2)，
                // 同档内按最新录入优先，便于优先处理最需要关注的题。
                final byMastery =
                    a.masteryLevel.index.compareTo(b.masteryLevel.index);
                if (byMastery != 0) return byMastery;
                return b.createdAt.compareTo(a.createdAt);
              case QuestionSort.subject:
                // 按科目 label 排序，同科目内按最新录入优先。
                final bySubject = a.subject.label.compareTo(b.subject.label);
                if (bySubject != 0) return bySubject;
                return b.createdAt.compareTo(a.createdAt);
            }
          });
          return Stream.value(filtered);
        },
        loading: () => const Stream.empty(),
        error: (e, _) => Stream.error(e, _),
      );
});

bool _isWithinDateRange(
  DateTime createdAt,
  QuestionDateRange range,
  DateTime now,
) {
  switch (range) {
    case QuestionDateRange.all:
      return true;
    case QuestionDateRange.last7Days:
      return !createdAt.isBefore(now.subtract(const Duration(days: 7)));
    case QuestionDateRange.last30Days:
      return !createdAt.isBefore(now.subtract(const Duration(days: 30)));
  }
}

// --- Export history ---

/// 导出历史版本号。每次导出完成后递增，触发 [exportHistoryProvider] 重新加载。
final StateProvider<int> _exportHistoryVersionProvider =
    StateProvider<int>((ref) => 0);

/// 通知导出历史已变更，刷新 [exportHistoryProvider]。
void invalidateExportHistory(WidgetRef ref) {
  ref.read(_exportHistoryVersionProvider.notifier).state++;
}

/// 最近导出记录（最多 10 条，按时间倒序）。
///
/// watch [_exportHistoryVersionProvider] 以在导出完成后响应式刷新。
/// 数据源为 [ExportHistoryService.list]。
final FutureProvider<List<ExportHistoryEntry>> exportHistoryProvider =
    FutureProvider<List<ExportHistoryEntry>>((ref) async {
  ref.watch(_exportHistoryVersionProvider);
  return ExportHistoryService.list();
});
