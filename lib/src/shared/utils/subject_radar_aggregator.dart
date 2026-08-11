import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/domain/models/mastery_level.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';

/// 学科能力雷达图聚合数据。
///
/// 聚合全量题目的掌握度分布，按学科分组并计算 [SubjectScore.abilityScore]，
/// 供 [generateSubjectRadarHtml] 渲染为 HTML 雷达图报告使用。
class SubjectRadarData {
  const SubjectRadarData({
    required this.generatedAt,
    required this.scores,
    required this.totalQuestions,
    required this.totalMastered,
    required this.totalReviewing,
    required this.totalNew,
    required this.bySubjectTotals,
  });

  /// 报告生成时间。
  final DateTime generatedAt;

  /// 按得分升序排列的学科得分列表，便于图表渲染。
  final List<SubjectScore> scores;

  /// 全量题目总数。
  final int totalQuestions;

  /// 已掌握题目总数。
  final int totalMastered;

  /// 学习中（reviewing）题目总数。
  final int totalReviewing;

  /// 待学习（newQuestion）题目总数。
  final int totalNew;

  /// 学科标签 -> 题数。
  final Map<String, int> bySubjectTotals;
}

/// 单个学科的能力得分快照。
class SubjectScore {
  const SubjectScore({
    required this.subject,
    required this.total,
    required this.mastered,
    required this.reviewing,
    required this.newQuestions,
    required this.abilityScore,
  });

  final Subject subject;

  /// 该学科题目总数。
  final int total;

  /// 已掌握题数。
  final int mastered;

  /// 学习中题数。
  final int reviewing;

  /// 待学习题数。
  final int newQuestions;

  /// 能力得分 0-100，公式：(mastered*1.0 + reviewing*0.5) / total * 100，
  /// total=0 时为 0。
  final double abilityScore;
}

/// 聚合学科能力雷达数据。
///
/// 调用方需要在 WidgetRef 上下文中使用：
/// ```dart
/// final data = await aggregateSubjectRadar(ref);
/// ```
Future<SubjectRadarData> aggregateSubjectRadar(WidgetRef ref) async {
  // 用 Future.wait 并发拉取（与 weekly_report_aggregator 保持一致的模式；
  // 当前仅有一个 provider，后续扩展可追加并行流）。
  final results = await Future.wait<dynamic>([
    ref.read(questionListProvider.future),
  ]);
  final List<QuestionRecord> questions = results[0] as List<QuestionRecord>;
  return aggregateSubjectRadarFromQuestions(questions);
}

/// 纯函数实现，便于单元测试直接复用。
@visibleForTesting
SubjectRadarData aggregateSubjectRadarFromQuestions(
  List<QuestionRecord> questions, {
  DateTime? generatedAt,
}) {
  final stats = <Subject, _SubjectStats>{};
  for (final q in questions) {
    final s = stats.putIfAbsent(q.subject, () => _SubjectStats());
    s.total++;
    switch (q.masteryLevel) {
      case MasteryLevel.mastered:
        s.mastered++;
        break;
      case MasteryLevel.reviewing:
        s.reviewing++;
        break;
      case MasteryLevel.newQuestion:
        s.newQuestion++;
        break;
    }
  }

  final scores = <SubjectScore>[];
  var totalQuestions = 0;
  var totalMastered = 0;
  var totalReviewing = 0;
  var totalNew = 0;
  final bySubjectTotals = <String, int>{};

  for (final entry in stats.entries) {
    final subject = entry.key;
    final s = entry.value;
    if (s.total == 0) continue;
    final abilityScore =
        (s.mastered * 1.0 + s.reviewing * 0.5) / s.total * 100;
    scores.add(SubjectScore(
      subject: subject,
      total: s.total,
      mastered: s.mastered,
      reviewing: s.reviewing,
      newQuestions: s.newQuestion,
      abilityScore: abilityScore,
    ));
    totalQuestions += s.total;
    totalMastered += s.mastered;
    totalReviewing += s.reviewing;
    totalNew += s.newQuestion;
    bySubjectTotals[subject.label] = s.total;
  }

  scores.sort((a, b) => a.abilityScore.compareTo(b.abilityScore));

  return SubjectRadarData(
    generatedAt: generatedAt ?? DateTime.now(),
    scores: scores,
    totalQuestions: totalQuestions,
    totalMastered: totalMastered,
    totalReviewing: totalReviewing,
    totalNew: totalNew,
    bySubjectTotals: bySubjectTotals,
  );
}

class _SubjectStats {
  int total = 0;
  int mastered = 0;
  int reviewing = 0;
  int newQuestion = 0;
}
