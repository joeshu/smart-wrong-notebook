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

/// 首页薄弱知识点推荐列表。
///
/// 聚合题目-知识点关联、复习日志和掌握度计算，调用
/// [RecommendationService.generate] 生成可解释推荐。依赖
/// [questionListProvider] 和 [reviewLogListProvider] 响应式刷新。
///
/// 返回值按推荐评分降序排列。无结构化关联数据时返回空列表
/// （首页 UI 会回退到旧的字符串 aiKnowledgePoints 统计）。
final FutureProvider<List<WeakPointRecommendation>>
    weakPointRecommendationsProvider =
    FutureProvider<List<WeakPointRecommendation>>((ref) async {
  // watch 响应式 provider，数据变更自动重算
  final questionsAsync = ref.watch(questionListProvider);
  final logsAsync = ref.watch(reviewLogListProvider);
  final questions = questionsAsync.maybeWhen(
    data: (q) => q,
    orElse: () => const <QuestionRecord>[],
  );
  final logs = logsAsync.maybeWhen(
    data: (l) => l,
    orElse: () => const <ReviewLog>[],
  );
  if (questions.isEmpty) return const <WeakPointRecommendation>[];

  final linkRepo = ref.read(questionKnowledgeLinkRepositoryProvider);
  final kpRepo = ref.read(knowledgePointRepositoryProvider);
  final masteryService = ref.read(knowledgePointMasteryServiceProvider);
  final recommendationService = ref.read(recommendationServiceProvider);

  // 1. 按知识点 ID 分组题目
  final allLinks = await linkRepo.allLinks();
  if (allLinks.isEmpty) return const <WeakPointRecommendation>[];

  final questionIdsByKp = <String, Set<String>>{};
  for (final link in allLinks) {
    questionIdsByKp
        .putIfAbsent(link.knowledgePointId, () => <String>{})
        .add(link.questionId);
  }

  // 2. 计算每个知识点的掌握度
  final questionMap = {for (final q in questions) q.id: q};
  final questionsByKp = <String, List<QuestionRecord>>{};
  for (final entry in questionIdsByKp.entries) {
    final related = entry.value
        .map((id) => questionMap[id])
        .whereType<QuestionRecord>()
        .toList();
    if (related.isNotEmpty) questionsByKp[entry.key] = related;
  }
  if (questionsByKp.isEmpty) return const <WeakPointRecommendation>[];

  final reviewStatsByQuestion = <String, ReviewStats>{};
  for (final log in logs) {
    final stats = reviewStatsByQuestion[log.questionRecordId] ??
        ReviewStats(forgotCount: 0, hardCount: 0, easyCount: 0);
    // ReviewLog.result 是字符串：'forgot' / 'reviewing' / 'mastered' / 'reset'
    switch (log.result) {
      case 'forgot':
        reviewStatsByQuestion[log.questionRecordId] = ReviewStats(
          forgotCount: stats.forgotCount + 1,
          hardCount: stats.hardCount,
          easyCount: stats.easyCount,
          recentReviewDates: <DateTime>[...stats.recentReviewDates, log.reviewedAt],
        );
        break;
      case 'reviewing':
        reviewStatsByQuestion[log.questionRecordId] = ReviewStats(
          forgotCount: stats.forgotCount,
          hardCount: stats.hardCount + 1,
          easyCount: stats.easyCount,
          recentReviewDates: <DateTime>[...stats.recentReviewDates, log.reviewedAt],
        );
        break;
      case 'mastered':
        reviewStatsByQuestion[log.questionRecordId] = ReviewStats(
          forgotCount: stats.forgotCount,
          hardCount: stats.hardCount,
          easyCount: stats.easyCount + 1,
          recentReviewDates: <DateTime>[...stats.recentReviewDates, log.reviewedAt],
        );
        break;
      // 'reset' 或其他值不计入统计
    }
  }

  final masteries = await masteryService.calculateBatch(
    questionsByKp: questionsByKp,
    reviewStatsByQuestion: reviewStatsByQuestion,
  );
  final masteryByKp = {for (final m in masteries) m.knowledgePointId: m};

  // 3. 生成推荐
  final inputs = <RecommendationInput>[];
  for (final mastery in masteries) {
    if (mastery.totalQuestions == 0) continue;
    final relatedQuestions = questionsByKp[mastery.knowledgePointId] ?? const [];
    inputs.add(RecommendationInput(
      knowledgePointId: mastery.knowledgePointId,
      mastery: mastery,
      questionIds: relatedQuestions.map((q) => q.id).toList(),
      errorQuestionIds: relatedQuestions
          .where((q) => q.masteryLevel != MasteryLevel.mastered)
          .map((q) => q.id)
          .toList(),
      difficultyByQuestion: {
        for (final q in relatedQuestions)
          if (q.difficulty != null) q.id: q.difficulty!,
      },
    ));
  }
  if (inputs.isEmpty) return const <WeakPointRecommendation>[];

  final recommendations = await recommendationService.generate(inputs: inputs);

  // 4. 关联知识点名称和掌握度
  final kpNameById = {for (final kp in await kpRepo.loadAll()) kp.id: kp.name};
  return recommendations.map((rec) {
    final mastery = masteryByKp[rec.knowledgePointId];
    final pendingReview = questionsByKp[rec.knowledgePointId]
            ?.where((q) =>
                q.masteryLevel == MasteryLevel.reviewing ||
                q.masteryLevel == MasteryLevel.newQuestion)
            .length ??
        0;
    return WeakPointRecommendation(
      recommendation: rec,
      knowledgePointName: kpNameById[rec.knowledgePointId] ?? rec.knowledgePointId,
      mastery: mastery,
      pendingReviewCount: pendingReview,
    );
  }).toList();
});

/// 首页薄弱知识点推荐条目（含推荐、知识点名、掌握度）。
class WeakPointRecommendation {
  const WeakPointRecommendation({
    required this.recommendation,
    required this.knowledgePointName,
    required this.mastery,
    required this.pendingReviewCount,
  });

  final Recommendation recommendation;
  final String knowledgePointName;
  final KnowledgePointMastery? mastery;
  final int pendingReviewCount;
}

/// 待确认知识点队列版本号。每次队列变化（新增/映射/忽略）后递增，
/// 触发 [pendingKnowledgePointMappingsProvider] 重新加载。
final StateProvider<int> _pendingKnowledgePointVersionProvider =
    StateProvider<int>((ref) => 0);

/// 知识点树节点 + 掌握度聚合条目（Phase 5）。
///
/// 把 [knowledgePointTreeProvider] 的全部节点与
/// [weakPointRecommendationsProvider] 计算出的掌握度合并，
/// 供知识树页面按节点展示掌握度热力图与统计。
class KnowledgeTreeNodeView {
  const KnowledgeTreeNodeView({
    required this.point,
    this.mastery,
    this.pendingReviewCount = 0,
  });

  final KnowledgePoint point;
  final KnowledgePointMastery? mastery;
  final int pendingReviewCount;

  /// 掌握度百分比，无数据时返回 null。
  double? get masteryPercentage => mastery?.masteryPercentage;
}

/// 知识树页面聚合数据：全部知识点（带掌握度）+ 薄弱 TOP5 + 掌握度分布。
class KnowledgeTreeOverview {
  const KnowledgeTreeOverview({
    required this.nodes,
    required this.weakTop5,
    required this.masteredCount,
    required this.reviewingCount,
    required this.newCount,
  });

  /// 全部知识点节点（带掌握度，可能为 null）。
  final List<KnowledgeTreeNodeView> nodes;

  /// 薄弱知识点 TOP5（按掌握度升序，仅含有题目的知识点）。
  final List<KnowledgeTreeNodeView> weakTop5;

  /// 全局掌握度分布（按题目数汇总）。
  final int masteredCount;
  final int reviewingCount;
  final int newCount;
}

/// 知识树页面聚合 provider（Phase 5）。
///
/// 合并知识点树与掌握度计算，watch [weakPointRecommendationsProvider]
/// 以响应题目/复习日志变更。返回 [KnowledgeTreeOverview] 供页面消费。
final FutureProvider<KnowledgeTreeOverview> knowledgeTreeOverviewProvider =
    FutureProvider<KnowledgeTreeOverview>((ref) async {
  final treeAsync = ref.watch(knowledgePointTreeProvider);
  final recsAsync = ref.watch(weakPointRecommendationsProvider);
  final tree = treeAsync.maybeWhen(
    data: (d) => d,
    orElse: () => const <KnowledgePoint>[],
  );
  final recs = recsAsync.maybeWhen(
    data: (d) => d,
    orElse: () => const <WeakPointRecommendation>[],
  );

  // 掌握度映射：kpId -> WeakPointRecommendation
  final recByKp = {for (final r in recs) r.recommendation.knowledgePointId: r};

  final nodes = <KnowledgeTreeNodeView>[];
  var mastered = 0;
  var reviewing = 0;
  var newQ = 0;
  for (final kp in tree) {
    final rec = recByKp[kp.id];
    final mastery = rec?.mastery;
    nodes.add(KnowledgeTreeNodeView(
      point: kp,
      mastery: mastery,
      pendingReviewCount: rec?.pendingReviewCount ?? 0,
    ));
    if (mastery != null) {
      mastered += mastery.masteredCount;
      reviewing += mastery.reviewingCount;
      newQ += mastery.newCount;
    }
  }

  // 薄弱 TOP5：仅有掌握度且 totalQuestions>0 的节点，按掌握度升序
  final weak = nodes
      .where((n) => n.mastery != null && n.mastery!.totalQuestions > 0)
      .toList()
    ..sort((a, b) =>
        a.mastery!.masteryPercentage.compareTo(b.mastery!.masteryPercentage));

  return KnowledgeTreeOverview(
    nodes: nodes,
    weakTop5: weak.take(5).toList(),
    masteredCount: mastered,
    reviewingCount: reviewing,
    newCount: newQ,
  );
});

/// 近 7 天每日复习趋势条目（Phase 8-3），供首页折线图展示。
class DailyReviewTrend {
  const DailyReviewTrend({
    required this.date,
    required this.reviewCount,
    required this.masteredCount,
  });

  /// 当天 0 点的本地时间。
  final DateTime date;

  /// 当天复习次数（含所有 result）。
  final int reviewCount;

  /// 当天标记为"掌握"的次数（result == 'mastered'）。
  final int masteredCount;
}

/// Phase 8-3：近 7 天每日复习趋势，用于首页学习趋势折线图。
///
/// watch [reviewLogListProvider] 响应复习日志变更。返回从 6 天前到今天
/// 共 7 天的 [DailyReviewTrend] 列表（按日期升序），无复习的日子计数为 0。
final FutureProvider<List<DailyReviewTrend>> reviewTrend7DaysProvider =
    FutureProvider<List<DailyReviewTrend>>((ref) async {
  final logs = ref.watch(reviewLogListProvider).maybeWhen(
        data: (l) => l,
        orElse: () => const <ReviewLog>[],
      );
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final buckets = <DateTime, _DayAccumulator>{};
  for (var i = 6; i >= 0; i -= 1) {
    final day = today.subtract(Duration(days: i));
    buckets[day] = _DayAccumulator();
  }
  for (final log in logs) {
    final at = log.reviewedAt.toLocal();
    final logDay = DateTime(at.year, at.month, at.day);
    final acc = buckets[logDay];
    if (acc == null) continue; // 不在近 7 天范围内
    acc.reviewCount += 1;
    if (log.result == 'mastered') acc.masteredCount += 1;
  }
  final sortedDays = buckets.keys.toList()..sort();
  return sortedDays
      .map((day) => DailyReviewTrend(
            date: day,
            reviewCount: buckets[day]!.reviewCount,
            masteredCount: buckets[day]!.masteredCount,
          ))
      .toList();
});

class _DayAccumulator {
  int reviewCount = 0;
  int masteredCount = 0;
}

/// 知识点详情页数据（Phase 5）：知识点 + 关联题目列表 + 掌握度。
class KnowledgePointDetail {
  const KnowledgePointDetail({
    required this.point,
    required this.questions,
    this.mastery,
  });

  final KnowledgePoint point;
  final List<QuestionRecord> questions;
  final KnowledgePointMastery? mastery;
}

/// 按知识点 ID 加载详情（Phase 5）。
///
/// watch [questionListProvider] 和 [knowledgePointTreeProvider] 以响应
/// 题目/知识点树变更。返回该知识点关联的题目列表与掌握度快照。
final FutureProviderFamily<KnowledgePointDetail, String>
    knowledgePointDetailProvider =
    FutureProvider.family<KnowledgePointDetail, String>(
        (ref, knowledgePointId) async {
  final tree = await ref.watch(knowledgePointTreeProvider.future);
  final point = tree.firstWhere(
    (kp) => kp.id == knowledgePointId,
    orElse: () => KnowledgePoint(
      id: knowledgePointId,
      name: '未知知识点',
      createdAt: DateTime.now(),
      updatedAt: DateTime.now(),
    ),
  );

  final linkRepo = ref.read(questionKnowledgeLinkRepositoryProvider);
  final questionIds = await linkRepo.questionIdsForKnowledgePoint(knowledgePointId);
  final allQuestions = ref.watch(questionListProvider).maybeWhen(
        data: (q) => q,
        orElse: () => const <QuestionRecord>[],
      );
  final idSet = questionIds.toSet();
  final questions =
      allQuestions.where((q) => idSet.contains(q.id)).toList();

  // 掌握度：从 overview 的 nodes 中取（若该知识点有题）
  final overview = ref.watch(knowledgeTreeOverviewProvider).maybeWhen(
        data: (d) => d,
        orElse: () => null,
      );
  final mastery = overview?.nodes
      .firstWhere(
        (n) => n.point.id == knowledgePointId,
        orElse: () => KnowledgeTreeNodeView(
          point: point,
          mastery: null,
        ),
      )
      .mastery;

  return KnowledgePointDetail(
    point: point,
    questions: questions,
    mastery: mastery,
  );
});

/// 通知待确认知识点队列已变更，刷新 [pendingKnowledgePointMappingsProvider]。
void invalidatePendingKnowledgePoints(WidgetRef ref) {
  ref.read(_pendingKnowledgePointVersionProvider.notifier).state++;
}

/// 全部待确认知识点列表（仅未处理项）。
///
/// Phase 4-C：消费 [PendingKnowledgePointMappingRepository.allPending]，
/// watch [_pendingKnowledgePointVersionProvider] 以在队列变更后响应式刷新。
final FutureProvider<List<PendingKnowledgePointMapping>>
    pendingKnowledgePointMappingsProvider =
    FutureProvider<List<PendingKnowledgePointMapping>>((ref) async {
  ref.watch(_pendingKnowledgePointVersionProvider);
  final repo = ref.read(pendingKnowledgePointMappingRepositoryProvider);
  return repo.allPending();
});

/// 指定题目下的待确认知识点列表。watch 全局版本号以响应队列变更。
final FutureProviderFamily<List<PendingKnowledgePointMapping>, String>
    pendingKnowledgePointsForQuestionProvider =
    FutureProvider.family<List<PendingKnowledgePointMapping>, String>(
        (ref, questionId) async {
  ref.watch(_pendingKnowledgePointVersionProvider);
  final repo = ref.read(pendingKnowledgePointMappingRepositoryProvider);
  return repo.pendingForQuestion(questionId);
});

// Shared invalidation state is defined by repository_providers.dart.

/// Call after any mutation (save, delete, review) to refresh list/review providers.
void invalidateQuestionList(WidgetRef ref) {
  ref.read(listVersionProvider.notifier).state++;
}

// --- All questions list (reactive) ---

/// 全量题目列表，基于 Drift `watch()` 响应式更新，表变更自动推送新快照。
/// 非 Drift 仓库回退到 `watchAll()` 默认实现（一次性 Future）。
final StreamProvider<List<QuestionRecord>> questionListProvider =
    StreamProvider<List<QuestionRecord>>((ref) {
  ref.watch(listVersionProvider);
  final recovery = ref.read(analysisRecoveryServiceProvider);
  return ref
      .read(questionRepositoryProvider)
      .watchAll()
      .map(recovery.recoverAll);
});

final StreamProvider<List<ReviewLog>> reviewLogListProvider =
    StreamProvider<List<ReviewLog>>((ref) {
  ref.watch(listVersionProvider);
  return ref.read(reviewLogRepositoryProvider).watchAll();
});

/// 按题目 ID 查询复习历史（Phase 6-5）。详情页记录 Tab 展示时间线用。
/// 监听 [listVersionProvider] 以便复习后（invalidate 列表版本）自动刷新。
final FutureProviderFamily<List<ReviewLog>, String>
    reviewLogsForQuestionProvider =
        FutureProviderFamily<List<ReviewLog>, String>((ref, questionId) {
  ref.watch(listVersionProvider);
  return ref.read(reviewLogRepositoryProvider).getByQuestionId(questionId);
});

/// 题目—知识点结构化关联视图（Phase 6-3）。
///
/// 把 [QuestionKnowledgeLink] 与 [KnowledgePoint] 名称、知识点掌握度
/// （从 [weakPointRecommendationsProvider] 取，无题目关联时为 null）
/// 合并成单条 UI 视图，供详情页「知识点关联」区块直接渲染。
class StructuredKnowledgeLinkView {
  const StructuredKnowledgeLinkView({
    required this.link,
    required this.knowledgePoint,
    this.masteryPercentage,
  });

  final QuestionKnowledgeLink link;
  final KnowledgePoint knowledgePoint;

  /// 知识点掌握度百分比 0–100。无题目关联或未参与计算时为 null。
  final double? masteryPercentage;

  bool get isPrimary => link.isPrimary;
}

/// 按题目 ID 查询结构化关联列表（含知识点名 + 掌握度）。
///
/// 监听 [listVersionProvider] 以便关联变更（add/remove/setPrimary）
/// 后自动刷新。
final FutureProviderFamily<List<StructuredKnowledgeLinkView>, String>
    structuredKnowledgeLinksProvider =
        FutureProviderFamily<List<StructuredKnowledgeLinkView>, String>(
            (ref, questionId) async {
  ref.watch(listVersionProvider);
  final linkRepo = ref.read(questionKnowledgeLinkRepositoryProvider);
  final kpRepo = ref.read(knowledgePointRepositoryProvider);
  final links = await linkRepo.linksForQuestion(questionId);
  if (links.isEmpty) return const <StructuredKnowledgeLinkView>[];

  final allPoints = await kpRepo.loadAll();
  final kpById = {for (final kp in allPoints) kp.id: kp};

  // 掌握度从 weakPointRecommendationsProvider 取（仅有题目关联的知识点）。
  final recommendations =
      ref.read(weakPointRecommendationsProvider).maybeWhen(
            data: (r) => r,
            orElse: () => const <WeakPointRecommendation>[],
          );
  final masteryByKp = <String, double>{
    for (final r in recommendations)
      if (r.mastery != null) r.recommendation.knowledgePointId: r.mastery!.masteryPercentage,
  };

  final views = <StructuredKnowledgeLinkView>[];
  for (final link in links) {
    final kp = kpById[link.knowledgePointId];
    if (kp == null) continue;
    views.add(StructuredKnowledgeLinkView(
      link: link,
      knowledgePoint: kp,
      masteryPercentage: masteryByKp[link.knowledgePointId],
    ));
  }
  return views;
});

class QuestionBatchGroup {
  const QuestionBatchGroup({required this.rootId, required this.questions});

  final String rootId;
  final List<QuestionRecord> questions;
}

final StreamProvider<Map<String, QuestionBatchGroup>>
    questionBatchGroupsProvider =
    StreamProvider<Map<String, QuestionBatchGroup>>((ref) {
  ref.watch(listVersionProvider);
  return ref.watch(questionListProvider).when(
        data: (all) => Stream.value(buildQuestionBatchGroups(all)),
        loading: () => const Stream.empty(),
        error: (e, _) => Stream.error(e, _),
      );
});

Map<String, QuestionBatchGroup> buildQuestionBatchGroups(
    List<QuestionRecord> questions) {
  final grouped = <String, List<QuestionRecord>>{};

  for (final question in questions) {
    final rootId = _questionBatchRootId(question);
    if (rootId == null) continue;
    grouped.putIfAbsent(rootId, () => <QuestionRecord>[]).add(question);
  }

  final result = <String, QuestionBatchGroup>{};
  for (final entry in grouped.entries) {
    if (entry.value.length < 2) continue;
    final sorted = [...entry.value]..sort(_compareBatchQuestions);
    result[entry.key] =
        QuestionBatchGroup(rootId: entry.key, questions: sorted);
  }
  return result;
}

String? questionBatchRootId(QuestionRecord question) =>
    _questionBatchRootId(question);

String? _questionBatchRootId(QuestionRecord question) {
  final rootId = question.rootQuestionId ?? question.parentQuestionId;
  return rootId == null || rootId.isEmpty ? null : rootId;
}

int _compareBatchQuestions(QuestionRecord a, QuestionRecord b) {
  final orderA = a.splitOrder;
  final orderB = b.splitOrder;
  if (orderA != null && orderB != null && orderA != orderB) {
    return orderA.compareTo(orderB);
  }
  if (orderA != null && orderB == null) return -1;
  if (orderA == null && orderB != null) return 1;
  final created = a.createdAt.compareTo(b.createdAt);
  if (created != 0) return created;
  return a.id.compareTo(b.id);
}

// --- Questions due for review ---

final StreamProvider<List<QuestionRecord>> dueReviewProvider =
    StreamProvider<List<QuestionRecord>>((ref) {
  ref.watch(listVersionProvider);
  return ref.watch(questionListProvider).when(
        data: (all) {
          const scheduler = ReviewScheduleService();
          return Stream.value(all.where(scheduler.isDue).toList());
        },
        loading: () => const Stream.empty(),
        error: (e, _) => Stream.error(e, _),
      );
});

// --- Today's review plan ---

class TodayReviewPlan {
  const TodayReviewPlan({
    required this.dueCount,
    required this.completedCount,
    required this.streakDays,
  });

  final int dueCount;
  final int completedCount;
  final int streakDays;

  int get targetCount => dueCount + completedCount;
  int get estimatedMinutes => dueCount * 3;
}

final StreamProvider<TodayReviewPlan> todayReviewPlanProvider =
    StreamProvider<TodayReviewPlan>((ref) async* {
  ref.watch(listVersionProvider);
  const scheduler = ReviewScheduleService();
  // 等待题目和复习记录两个流的首个快照，再计算计划。
  // listVersionProvider 变化时整个 StreamProvider 会重建，触发重新计算；
  // Drift watchAll() 在表变更时也会推动 questionListProvider/reviewLogListProvider
  // 发出新值，通过 listVersionProvider 间接触发刷新（保持兼容）。
  final questions = await ref.read(questionListProvider.future);
  final logs = await ref.read(reviewLogListProvider.future);
  final now = DateTime.now();
  final completedIds = <String>{};
  final reviewedDays = <DateTime>{};
  for (final log in logs) {
    final at = log.reviewedAt.toLocal();
    final day = DateTime(at.year, at.month, at.day);
    reviewedDays.add(day);
    if (day == DateTime(now.year, now.month, now.day)) {
      completedIds.add(log.questionRecordId);
    }
  }
  var streak = 0;
  var day = DateTime(now.year, now.month, now.day);
  while (reviewedDays.contains(day)) {
    streak++;
    day = day.subtract(const Duration(days: 1));
  }
  yield TodayReviewPlan(
    dueCount: questions.where(scheduler.isDue).length,
    completedCount: completedIds.length,
    streakDays: streak,
  );
});

// --- Mistake category statistics ---

final StreamProvider<Map<MistakeCategory, int>> mistakeCategoryStatsProvider =
    StreamProvider<Map<MistakeCategory, int>>((ref) {
  ref.watch(listVersionProvider);
  return ref.watch(questionListProvider).when(
        data: (all) {
          final stats = <MistakeCategory, int>{};
          for (final question in all) {
            final category = question.mistakeCategory;
            if (category != null) stats[category] = (stats[category] ?? 0) + 1;
          }
          return Stream.value(stats);
        },
        loading: () => const Stream.empty(),
        error: (e, _) => Stream.error(e, _),
      );
});
