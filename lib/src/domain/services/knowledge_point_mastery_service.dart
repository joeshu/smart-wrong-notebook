import 'dart:math' as math show log;

import 'package:smart_wrong_notebook/src/data/repositories/question_knowledge_link_repository.dart';
import 'package:smart_wrong_notebook/src/domain/models/knowledge_point_mastery.dart';
import 'package:smart_wrong_notebook/src/domain/models/learning_context.dart';
import 'package:smart_wrong_notebook/src/domain/models/mastery_level.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_knowledge_link.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';

/// 知识点掌握度计算服务。
///
/// Phase 12-1 算法升级：从「基础分 - 硬扣分」模型改为加权因子模型。
///
/// 最终掌握度 = Σ(因子子分数 × 权重) - 扣分项，clamp 到 [0, 100]。
///
/// **因子权重表：**
/// | 因子 | 权重 | 子分数（0–100）来源 |
/// |---|---|---|
/// | 最近复习正确率 | 40% | easy / (easy+hard+forgot)，无记录按 mastery 折算 |
/// | 累计复习次数 | 20% | log(1+n)/log(1+10) 饱和曲线 + 衰减系数 |
/// | 难度分布 | 10% | 高难度题占比加权 |
/// | 基础掌握度 | 30% | mastered=100 / reviewing=55 / new=15 |
///
/// **扣分项（直接从总和减）：**
/// - forgotPenalty：每次忘记扣 5 分
/// - hardPenalty：每次模糊扣 2 分
/// - newQuestionPenalty：新题占比 > 50% 时扣 10 分
///
/// 旧版字段（baseScore/forgotPenalty/hardPenalty/newQuestionPenalty）保留在
/// [KnowledgePointMastery.factors] 中以兼容 UI 展示；新增 accuracy/recency/
/// difficulty 三个因子子分数 key。
class KnowledgePointMasteryService {
  KnowledgePointMasteryService(this._linkRepo);

  final QuestionKnowledgeLinkRepository _linkRepo;

  /// 衰减起始天数（超过此天数开始衰减）。
  static const int _decayStartDays = 7;

  /// 每日衰减率。
  static const double _dailyDecayRate = 0.02;

  /// 忘记扣分。
  static const double _forgotPenalty = 5.0;

  /// 模糊扣分。
  static const double _hardPenalty = 2.0;

  /// 新题占比阈值。
  static const double _newQuestionRatioThreshold = 0.5;

  /// 新题占比超阈值的额外扣分。
  static const double _newQuestionPenalty = 10.0;

  /// 复习次数饱和上限（达到此时 recency 子分数=100）。
  static const int _recencySaturationReviews = 10;

  /// 无复习统计但有 lastReviewedAt 时的折算分（表示至少复习过一次）。
  static const double _recencyFallbackScore = 60.0;

  // 因子权重（合计 1.0）。
  static const double _weightAccuracy = 0.40;
  static const double _weightRecency = 0.20;
  static const double _weightDifficulty = 0.10;
  static const double _weightBase = 0.30;

  /// 计算指定知识点的掌握度。
  ///
  /// [questions] 是该知识点关联的全部题目（调用方通过 linkRepo 查出 ID 后
  /// 从 questionRepository 加载）。[reviewStatsByQuestion] 是每道题的
  /// 复习统计（forgot/hard/easy 次数），由调用方从 reviewLogRepository 聚合。
  Future<KnowledgePointMastery> calculate({
    required String knowledgePointId,
    required List<QuestionRecord> questions,
    required Map<String, ReviewStats> reviewStatsByQuestion,
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();

    if (questions.isEmpty) {
      return KnowledgePointMastery(
        knowledgePointId: knowledgePointId,
        totalQuestions: 0,
        masteredCount: 0,
        reviewingCount: 0,
        newCount: 0,
        forgotCount: 0,
        hardCount: 0,
        easyCount: 0,
        lastReviewedAt: null,
        masteryPercentage: 0,
        calculatedAt: at,
      );
    }

    // 查询每道题关联的知识点数，用于基础分权重计算。
    final kpCountByQuestion = <String, int>{};
    for (final q in questions) {
      final links = await _linkRepo.linksForQuestion(q.id);
      kpCountByQuestion[q.id] = links.length;
    }

    int masteredCount = 0;
    int reviewingCount = 0;
    int newCount = 0;
    int forgotCount = 0;
    int hardCount = 0;
    int easyCount = 0;
    DateTime? lastReviewedAt;

    // 基础分加权累计（按 1/N 知识点权重）。
    double weightedBaseScore = 0.0;
    double totalWeight = 0.0;

    // 难度因子累计：每题难度权重 × 1/N。
    double weightedDifficulty = 0.0;

    for (final q in questions) {
      final weight = 1.0 / (kpCountByQuestion[q.id] ?? 1).clamp(1, 10);
      totalWeight += weight;

      // 基础分（mastered=100 / reviewing=55 / new=15）。
      double baseScore;
      switch (q.masteryLevel) {
        case MasteryLevel.mastered:
          masteredCount++;
          baseScore = 100.0;
          break;
        case MasteryLevel.reviewing:
          reviewingCount++;
          baseScore = 55.0;
          break;
        case MasteryLevel.newQuestion:
          newCount++;
          baseScore = 15.0;
          break;
      }

      weightedBaseScore += baseScore * weight;

      // 难度因子：challenge=1.0, advanced=0.7, foundation=0.3, custom/null=0.5。
      final diffScore = _difficultyWeight(q.difficulty);
      weightedDifficulty += diffScore * weight;

      // 收集 lastReviewedAt（取最新）。
      final reviewedAt = q.lastReviewedAt;
      if (reviewedAt != null) {
        if (lastReviewedAt == null || reviewedAt.isAfter(lastReviewedAt)) {
          lastReviewedAt = reviewedAt;
        }
      }
    }

    // 聚合复习统计。
    for (final stats in reviewStatsByQuestion.values) {
      forgotCount += stats.forgotCount;
      hardCount += stats.hardCount;
      easyCount += stats.easyCount;
    }

    // ── 因子 1：最近复习正确率（40%）──
    // 有复习记录时按 easy/(easy+hard+forgot)，无记录时按 mastery 折算。
    final accuracyScore = _accuracyFactor(
      questions: questions,
      reviewStatsByQuestion: reviewStatsByQuestion,
      kpCountByQuestion: kpCountByQuestion,
    );

    // ── 因子 2：累计复习次数 + 衰减（20%）──
    final recencyScore = _recencyFactor(
      questions: questions,
      reviewStatsByQuestion: reviewStatsByQuestion,
      kpCountByQuestion: kpCountByQuestion,
      at: at,
    );

    // ── 因子 3：难度分布（10%）──
    final difficultyScore = totalWeight > 0
        ? (weightedDifficulty / totalWeight) * 100
        : 0.0;

    // ── 因子 4：基础掌握度（30%）──
    final baseFactorScore = totalWeight > 0
        ? (weightedBaseScore / totalWeight)
        : 0.0;

    // 加权求和。
    double percentage = accuracyScore * _weightAccuracy +
        recencyScore * _weightRecency +
        difficultyScore * _weightDifficulty +
        baseFactorScore * _weightBase;

    // 扣分项。
    final forgotPenalty = forgotCount * _forgotPenalty;
    final hardPenalty = hardCount * _hardPenalty;
    final newRatio = newCount / questions.length;
    final newQuestionPenalty =
        newRatio > _newQuestionRatioThreshold ? _newQuestionPenalty : 0.0;

    percentage -= forgotPenalty;
    percentage -= hardPenalty;
    percentage -= newQuestionPenalty;

    percentage = percentage.clamp(0.0, 100.0);

    // 记录计算因子（用于 UI 展示"掌握度计算依据"）。
    final factors = <String, double>{
      // 新因子子分数（0-100）。
      'accuracy': accuracyScore,
      'recency': recencyScore,
      'difficulty': difficultyScore,
      'baseScore': baseFactorScore,
      // 权重（便于 UI 展示比例）。
      'accuracyWeight': _weightAccuracy * 100,
      'recencyWeight': _weightRecency * 100,
      'difficultyWeight': _weightDifficulty * 100,
      'baseWeight': _weightBase * 100,
      // 扣分项（保持原 key 兼容旧 UI）。
      'forgotPenalty': forgotPenalty,
      'hardPenalty': hardPenalty,
      'newQuestionPenalty': newQuestionPenalty,
    };

    return KnowledgePointMastery(
      knowledgePointId: knowledgePointId,
      totalQuestions: questions.length,
      masteredCount: masteredCount,
      reviewingCount: reviewingCount,
      newCount: newCount,
      forgotCount: forgotCount,
      hardCount: hardCount,
      easyCount: easyCount,
      lastReviewedAt: lastReviewedAt,
      masteryPercentage: percentage,
      calculatedAt: at,
      factors: factors,
    );
  }

  /// 计算最近复习正确率因子子分数（0-100）。
  ///
  /// 按题目 1/N 权重聚合：每题有复习记录时取 easy/(easy+hard+forgot)，
  /// 无记录时按 masteryLevel 折算（mastered=95 / reviewing=50 / new=10）。
  double _accuracyFactor({
    required List<QuestionRecord> questions,
    required Map<String, ReviewStats> reviewStatsByQuestion,
    required Map<String, int> kpCountByQuestion,
  }) {
    double weighted = 0.0;
    double totalWeight = 0.0;
    for (final q in questions) {
      final weight = 1.0 / (kpCountByQuestion[q.id] ?? 1).clamp(1, 10);
      totalWeight += weight;
      final stats = reviewStatsByQuestion[q.id];
      double score;
      if (stats != null && stats.totalReviews > 0) {
        score = stats.easyCount / stats.totalReviews * 100;
      } else {
        switch (q.masteryLevel) {
          case MasteryLevel.mastered:
            score = 95.0;
            break;
          case MasteryLevel.reviewing:
            score = 50.0;
            break;
          case MasteryLevel.newQuestion:
            score = 10.0;
            break;
        }
      }
      weighted += score * weight;
    }
    return totalWeight > 0 ? weighted / totalWeight : 0.0;
  }

  /// 计算累计复习次数因子子分数（0-100），含时间衰减。
  ///
  /// 按题目 1/N 权重聚合：每题复习次数走 log(1+n)/log(1+saturation) 饱和曲线，
  /// 无 stats 但 lastReviewedAt 非空时折算 60，无 stats 无 lastReviewedAt 为 0。
  /// 每题子分数再乘以衰减系数（7 天内 1.0，超过每日 -2%）。
  double _recencyFactor({
    required List<QuestionRecord> questions,
    required Map<String, ReviewStats> reviewStatsByQuestion,
    required Map<String, int> kpCountByQuestion,
    required DateTime at,
  }) {
    double weighted = 0.0;
    double totalWeight = 0.0;
    final logSat = _log1p(_recencySaturationReviews);
    for (final q in questions) {
      final weight = 1.0 / (kpCountByQuestion[q.id] ?? 1).clamp(1, 10);
      totalWeight += weight;
      final stats = reviewStatsByQuestion[q.id];
      double score;
      if (stats != null && stats.totalReviews > 0) {
        final ratio = _log1p(stats.totalReviews) / logSat;
        score = (ratio * 100).clamp(0.0, 100.0);
      } else if (q.lastReviewedAt != null) {
        score = _recencyFallbackScore;
      } else {
        score = 0.0;
      }

      // 衰减系数：7 天内 1.0，超过每日 -2%（下限 0）。
      double decayMultiplier = 1.0;
      final reviewedAt = q.lastReviewedAt;
      if (reviewedAt != null) {
        final daysSince = at.difference(reviewedAt).inDays;
        if (daysSince > _decayStartDays) {
          final decayDays = daysSince - _decayStartDays;
          decayMultiplier =
              (1.0 - decayDays * _dailyDecayRate).clamp(0.0, 1.0);
        }
      }
      weighted += score * decayMultiplier * weight;
    }
    return totalWeight > 0 ? weighted / totalWeight : 0.0;
  }

  /// log(1 + n)（自然对数）。
  double _log1p(int n) {
    if (n <= 0) return 0.0;
    return math.log(n + 1);
  }

  /// 难度权重：challenge=1.0, advanced=0.7, foundation=0.3, custom/null=0.5。
  double _difficultyWeight(QuestionDifficulty? difficulty) {
    switch (difficulty) {
      case QuestionDifficulty.challenge:
        return 1.0;
      case QuestionDifficulty.advanced:
        return 0.7;
      case QuestionDifficulty.foundation:
        return 0.3;
      case QuestionDifficulty.custom:
      case null:
        return 0.5;
    }
  }

  /// 批量计算多个知识点的掌握度。
  ///
  /// [questionsByKp] 是知识点 ID → 关联题目列表的映射。
  /// [reviewStatsByQuestion] 是全局的题目复习统计（所有题目共享）。
  Future<List<KnowledgePointMastery>> calculateBatch({
    required Map<String, List<QuestionRecord>> questionsByKp,
    required Map<String, ReviewStats> reviewStatsByQuestion,
    DateTime? now,
  }) async {
    final results = <KnowledgePointMastery>[];
    for (final entry in questionsByKp.entries) {
      final mastery = await calculate(
        knowledgePointId: entry.key,
        questions: entry.value,
        reviewStatsByQuestion: reviewStatsByQuestion,
        now: now,
      );
      results.add(mastery);
    }
    return results;
  }
}

/// 题目复习统计快照。
class ReviewStats {
  ReviewStats({
    required this.forgotCount,
    required this.hardCount,
    required this.easyCount,
    this.recentReviewDates = const <DateTime>[],
  });

  final int forgotCount;
  final int hardCount;
  final int easyCount;
  final List<DateTime> recentReviewDates;

  int get totalReviews => forgotCount + hardCount + easyCount;
}
