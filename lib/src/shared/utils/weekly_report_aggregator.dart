import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/domain/models/mastery_level.dart';
import 'package:smart_wrong_notebook/src/domain/models/mistake_category.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/review_log.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';

/// 命名计数对：用于错因分类 / 知识点频次等 Top-N 排行结果。
class NamedCount {
  const NamedCount(this.label, this.count);

  /// 显示标签（例如"概念不清"或"一元二次方程"）。
  final String label;

  /// 出现次数。
  final int count;

  @override
  String toString() => '$label×$count';
}

/// 学情周报聚合数据。
///
/// 聚合本周（ISO 周一 00:00 至周日 23:59:59）的错题与复习数据，
/// 供 [generateWeeklyReportHtml] 渲染 HTML 报告使用。
class WeeklyReportData {
  const WeeklyReportData({
    required this.weekStart,
    required this.weekEnd,
    required this.newQuestionsCount,
    required this.newQuestionsBySubject,
    required this.reviewedCount,
    required this.masteredCount,
    required this.masteryRate,
    required this.topMistakeCategories,
    required this.weakKnowledgePoints,
    required this.streakDays,
    required this.dailyReviewCounts,
  });

  /// 本周一 00:00。
  final DateTime weekStart;

  /// 本周日 23:59:59。
  final DateTime weekEnd;

  /// 本周新增题数。
  final int newQuestionsCount;

  /// 本周新增题按学科统计。
  final Map<Subject, int> newQuestionsBySubject;

  /// 本周完成的复习次数（reviewLogListProvider 中 reviewedAt 落在本周）。
  final int reviewedCount;

  /// 本周新掌握的题数：masteryAfter 变为 mastered 的不同题目数。
  final int masteredCount;

  /// 本周复习题中已掌握比例（0.0 ~ 1.0）。
  final double masteryRate;

  /// 本周新增题中错因分类 Top3。
  final List<NamedCount> topMistakeCategories;

  /// 本周新增题中知识点频次 Top5。
  final List<NamedCount> weakKnowledgePoints;

  /// 连续复习天数（与 todayReviewPlanProvider 中 streakDays 计算一致）。
  final int streakDays;

  /// 本周 7 天每天的复习次数，索引 0 = 周一，6 = 周日。
  final List<int> dailyReviewCounts;
}

/// 计算本周一 00:00（本地时间）。
DateTime startOfWeek(DateTime now) {
  // DateTime.weekday: Monday = 1, Sunday = 7。
  final diff = now.weekday - 1;
  return DateTime(now.year, now.month, now.day).subtract(Duration(days: diff));
}

/// 计算本周日 23:59:59（本地时间）。
DateTime endOfWeek(DateTime weekStart) {
  return weekStart
      .add(const Duration(days: 7))
      .subtract(const Duration(seconds: 1));
}

/// 聚合本周学情数据。
///
/// 调用方需要在 WidgetRef 上下文中使用，例如：
/// ```dart
/// final data = await aggregateWeeklyReport(ref);
/// ```
Future<WeeklyReportData> aggregateWeeklyReport(WidgetRef ref) async {
  final now = DateTime.now();
  final weekStart = startOfWeek(now);
  final weekEnd = endOfWeek(weekStart);

  // 并发拉取三个流的首个快照。
  final questionsFuture = ref.read(questionListProvider.future);
  final logsFuture = ref.read(reviewLogListProvider.future);
  final planFuture = ref.read(todayReviewPlanProvider.future);

  final results = await Future.wait<dynamic>([
    questionsFuture,
    logsFuture,
    planFuture,
  ]);
  final List<QuestionRecord> questions = results[0] as List<QuestionRecord>;
  final List<ReviewLog> logs = results[1] as List<ReviewLog>;
  final TodayReviewPlan plan = results[2] as TodayReviewPlan;

  // --- 本周新增题 ---
  final newQuestions = questions.where((q) {
    final created = q.createdAt;
    return !created.isBefore(weekStart) && !created.isAfter(weekEnd);
  }).toList();

  final bySubject = <Subject, int>{};
  for (final q in newQuestions) {
    bySubject[q.subject] = (bySubject[q.subject] ?? 0) + 1;
  }

  // --- 本周复习日志 ---
  bool inWeek(DateTime dt) =>
      !dt.isBefore(weekStart) && !dt.isAfter(weekEnd);

  final weekLogs = logs.where((log) => inWeek(log.reviewedAt)).toList();

  // 本周新掌握：masteryAfter 变为 mastered 的不同题目数。
  final masteredIds = <String>{};
  for (final log in weekLogs) {
    if (log.masteryAfter == MasteryLevel.mastered) {
      masteredIds.add(log.questionRecordId);
    }
  }
  final masteredCount = masteredIds.length;
  final reviewedCount = weekLogs.length;
  final masteryRate =
      reviewedCount == 0 ? 0.0 : masteredCount / reviewedCount;

  // --- 错因分类 Top3（仅本周新增题） ---
  final mistakeCounts = <MistakeCategory, int>{};
  for (final q in newQuestions) {
    final cat = q.mistakeCategory;
    if (cat == null) continue;
    mistakeCounts[cat] = (mistakeCounts[cat] ?? 0) + 1;
  }
  final topMistakeCategories = mistakeCounts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final top3 = topMistakeCategories
      .take(3)
      .map((e) => NamedCount(e.key.label, e.value))
      .toList();

  // --- 知识点频次 Top5（仅本周新增题） ---
  final kpCounts = <String, int>{};
  for (final q in newQuestions) {
    for (final kp in q.aiKnowledgePoints) {
      if (kp.isEmpty) continue;
      kpCounts[kp] = (kpCounts[kp] ?? 0) + 1;
    }
  }
  final topKp = kpCounts.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final weakKnowledgePoints =
      topKp.take(5).map((e) => NamedCount(e.key, e.value)).toList();

  // --- 7 天每日复习次数（索引 0 = 周一） ---
  final dailyCounts = List<int>.filled(7, 0);
  for (final log in weekLogs) {
    final local = log.reviewedAt;
    final dayDiff = local.difference(weekStart).inDays;
    if (dayDiff >= 0 && dayDiff < 7) {
      dailyCounts[dayDiff]++;
    }
  }

  return WeeklyReportData(
    weekStart: weekStart,
    weekEnd: weekEnd,
    newQuestionsCount: newQuestions.length,
    newQuestionsBySubject: bySubject,
    reviewedCount: reviewedCount,
    masteredCount: masteredCount,
    masteryRate: masteryRate,
    topMistakeCategories: top3,
    weakKnowledgePoints: weakKnowledgePoints,
    streakDays: plan.streakDays,
    dailyReviewCounts: dailyCounts,
  );
}
