import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_wrong_notebook/src/domain/models/knowledge_point_mastery.dart';
import 'package:smart_wrong_notebook/src/domain/models/learning_context.dart';
import 'package:smart_wrong_notebook/src/domain/models/recommendation.dart';

/// 薄弱点优先推荐服务。
///
/// Phase 4 基础模型：基于知识点掌握度、错因分布和复习历史生成可解释
/// 推荐列表。推荐评分纳入：
/// 1. 掌握度（越低越优先）
/// 2. 忘记/模糊次数（越多越优先）
/// 3. 最近复习时间（越久越优先）
/// 4. 错因严重程度（concept > strategy > calculation > 其他）
/// 5. 知识点覆盖度（推荐分布在不同知识点）
/// 6. 题目难度（基础题占比高 → 适合弱基础学生优先；推荐题目按由易到难排序）
///
/// 推荐结果按评分降序排列，相关题目按难度升序（由易到难）排序，
/// 支持去重、忽略和标记无效。
class RecommendationService {
  RecommendationService();

  static const _ignoredKey = 'recommendations_ignored_v1';

  /// 难度排序权重：值越小越靠前（越简单）。
  /// `custom` 视为中等难度，排在 advanced 之后、challenge 之前。
  static const Map<QuestionDifficulty, int> _difficultyOrder =
      <QuestionDifficulty, int>{
    QuestionDifficulty.foundation: 0,
    QuestionDifficulty.advanced: 1,
    QuestionDifficulty.custom: 2,
    QuestionDifficulty.challenge: 3,
  };

  /// 生成推荐列表。
  ///
  /// [inputs] 是各知识点的掌握度快照和关联题目信息。
  /// 返回按评分降序排列的推荐列表，已排除忽略和标记无效的项。
  Future<List<Recommendation>> generate({
    required List<RecommendationInput> inputs,
    DateTime? now,
  }) async {
    final at = now ?? DateTime.now();
    final ignoredIds = await _loadIgnored();

    final recommendations = <Recommendation>[];

    for (final input in inputs) {
      if (input.mastery.totalQuestions == 0) continue;

      final recs = _generateForKnowledgePoint(input, at);
      recommendations.addAll(recs);
    }

    // 去重：同一知识点同一类型只保留评分最高的
    final deduped = <String, Recommendation>{};
    for (final rec in recommendations) {
      final key = '${rec.type.name}|${rec.knowledgePointId}';
      final existing = deduped[key];
      if (existing == null || rec.score > existing.score) {
        deduped[key] = rec;
      }
    }

    // 过滤已忽略/标记无效
    final valid = deduped.values
        .where((rec) => !ignoredIds.contains(rec.id))
        .toList();

    // 按评分降序排列（高分优先 = 更薄弱）
    valid.sort((a, b) => b.score.compareTo(a.score));

    return valid;
  }

  List<Recommendation> _generateForKnowledgePoint(
      RecommendationInput input, DateTime at) {
    final recs = <Recommendation>[];
    final mastery = input.mastery;
    final reasons = <String>[];
    double score = 0.0;

    // 1. 掌握度因子（越低分越高）
    final masteryScore = (100 - mastery.masteryPercentage).clamp(0.0, 100.0);
    score += masteryScore * 0.4; // 权重 40%
    if (mastery.masteryPercentage < 30) {
      reasons.add('该知识点掌握度仅 ${mastery.masteryPercentage.toStringAsFixed(0)}%，需要重点复习');
    } else if (mastery.masteryPercentage < 60) {
      reasons.add('该知识点掌握度 ${mastery.masteryPercentage.toStringAsFixed(0)}%，仍有提升空间');
    }

    // 2. 忘记/模糊次数因子
    final mistakeScore = (mastery.forgotCount * 3 + mastery.hardCount * 1.5)
        .clamp(0.0, 30.0);
    score += mistakeScore * 0.25; // 权重 25%
    if (mastery.forgotCount > 0) {
      reasons.add('历史复习中忘记 ${mastery.forgotCount} 次，需巩固记忆');
    }
    if (mastery.hardCount > 0) {
      reasons.add('历史复习中模糊 ${mastery.hardCount} 次，理解不够扎实');
    }

    // 3. 最近复习时间因子
    double recencyScore = 0.0;
    if (mastery.lastReviewedAt != null) {
      final daysSinceReview = at.difference(mastery.lastReviewedAt!).inDays;
      recencyScore = (daysSinceReview * 1.5).clamp(0.0, 20.0);
    } else {
      recencyScore = 25.0; // 从未复习，优先级高于已久未复习的知识点
      reasons.add('该知识点尚未复习');
    }
    score += recencyScore * 0.2; // 权重 20%
    if (mastery.lastReviewedAt != null) {
      final days = at.difference(mastery.lastReviewedAt!).inDays;
      if (days > 14) {
        reasons.add('已 $days 天未复习，建议及时回顾');
      }
    }

    // 4. 新题占比因子
    if (mastery.totalQuestions > 0) {
      final newRatio = mastery.newCount / mastery.totalQuestions;
      final newScore = (newRatio * 15).clamp(0.0, 15.0);
      score += newScore * 0.15; // 权重 15%
      if (newRatio > 0.5) {
        reasons.add('该知识点 ${mastery.newCount} 道新题尚未练习');
      }
    }

    // 确保有推荐原因
    if (reasons.isEmpty) {
      reasons.add('建议保持复习节奏，巩固掌握度');
    }

    // 5. 难度提示：统计相关题目难度分布，若以基础题为主则提示适合优先
    final difficultyStats = _summarizeDifficulty(input);
    if (difficultyStats != null) {
      final foundationRatio = difficultyStats.foundationCount /
          difficultyStats.totalCount;
      if (foundationRatio >= 0.5 && difficultyStats.totalCount >= 2) {
        reasons.add('该知识点以基础题为主（${difficultyStats.foundationCount}/${difficultyStats.totalCount}），建议先巩固基础');
      } else if (foundationRatio == 0 && difficultyStats.challengeCount > 0) {
        reasons.add('该知识点题目偏难（${difficultyStats.challengeCount} 道挑战题），建议先复习基础再攻坚');
      }
    }

    final recId = 'rec_${input.knowledgePointId}_${at.millisecondsSinceEpoch}';

    // 由易到难排序相关题目 ID
    final sortedQuestionIds =
        _sortByDifficultyAscending(input.questionIds, input.difficultyByQuestion);
    final sortedErrorQuestionIds = _sortByDifficultyAscending(
        input.errorQuestionIds, input.difficultyByQuestion);

    // 生成复习推荐（如果有待复习的题目）
    if (mastery.hasPendingReviews && input.questionIds.isNotEmpty) {
      recs.add(Recommendation(
        id: '${recId}_review',
        type: RecommendationType.review,
        knowledgePointId: input.knowledgePointId,
        questionId: sortedQuestionIds.first,
        relatedQuestionIds: sortedQuestionIds,
        score: score,
        reasons: reasons,
        createdAt: at,
      ));
    }

    // 生成专项练习推荐（如果掌握度较低）
    if (mastery.masteryPercentage < 60) {
      recs.add(Recommendation(
        id: '${recId}_practice',
        type: RecommendationType.practice,
        knowledgePointId: input.knowledgePointId,
        relatedQuestionIds: sortedErrorQuestionIds,
        score: score * 0.9, // 练习推荐略低于复习
        reasons: <String>[...reasons, '建议生成专项练习题强化薄弱环节'],
        createdAt: at,
      ));
    }

    return recs;
  }

  /// 把题目 ID 按难度升序（foundation → advanced → custom → challenge）
  /// 排序。未提供难度的题目视为 foundation，排在最前；同难度保持原顺序。
  List<String> _sortByDifficultyAscending(
    List<String> questionIds,
    Map<String, QuestionDifficulty> difficultyByQuestion,
  ) {
    if (questionIds.isEmpty) return questionIds;
    final indexed = questionIds.asMap().entries.toList();
    indexed.sort((a, b) {
      final da = difficultyByQuestion[a.value] ?? QuestionDifficulty.foundation;
      final db = difficultyByQuestion[b.value] ?? QuestionDifficulty.foundation;
      final cmp =
          (_difficultyOrder[da] ?? 0).compareTo(_difficultyOrder[db] ?? 0);
      if (cmp != 0) return cmp;
      return a.key.compareTo(b.key); // 稳定排序
    });
    return indexed.map((e) => e.value).toList();
  }

  /// 统计 [RecommendationInput.questionIds] 的难度分布，用于推荐原因描述。
  /// 全部题目都没有难度信息时返回 null。
  _DifficultyStats? _summarizeDifficulty(RecommendationInput input) {
    if (input.difficultyByQuestion.isEmpty ||
        input.questionIds.isEmpty) {
      return null;
    }
    int foundation = 0;
    int advanced = 0;
    int challenge = 0;
    int custom = 0;
    int known = 0;
    for (final qid in input.questionIds) {
      final d = input.difficultyByQuestion[qid];
      if (d == null) continue;
      known++;
      switch (d) {
        case QuestionDifficulty.foundation:
          foundation++;
          break;
        case QuestionDifficulty.advanced:
          advanced++;
          break;
        case QuestionDifficulty.challenge:
          challenge++;
          break;
        case QuestionDifficulty.custom:
          custom++;
          break;
      }
    }
    if (known == 0) return null;
    return _DifficultyStats(
      totalCount: known,
      foundationCount: foundation,
      advancedCount: advanced,
      challengeCount: challenge,
      customCount: custom,
    );
  }

  /// 忽略推荐。
  Future<void> ignore(String recommendationId) async {
    final ignored = await _loadIgnored();
    ignored.add(recommendationId);
    await _saveIgnored(ignored);
  }

  /// 标记推荐无效。
  Future<void> markInvalid(String recommendationId) async {
    final ignored = await _loadIgnored();
    ignored.add(recommendationId);
    await _saveIgnored(ignored);
  }

  /// 清除所有忽略记录（练习完成后可调用以更新推荐）。
  Future<void> clearIgnored() async {
    await _saveIgnored(<String>{});
  }

  Future<Set<String>> _loadIgnored() async {
    final raw = (await SharedPreferences.getInstance()).getString(_ignoredKey);
    if (raw == null || raw.isEmpty) return <String>{};
    try {
      final list = jsonDecode(raw) as List;
      return list.map((item) => '$item').toSet();
    } catch (_) {
      return <String>{};
    }
  }

  Future<void> _saveIgnored(Set<String> ids) async {
    await (await SharedPreferences.getInstance())
        .setString(_ignoredKey, jsonEncode(ids.toList()));
  }

  /// 仅用于测试：重置忽略列表。
  @visibleForTesting
  Future<void> resetForTest() async {
    await _saveIgnored(<String>{});
  }
}

/// 难度分布统计结果（内部用）。
class _DifficultyStats {
  const _DifficultyStats({
    required this.totalCount,
    required this.foundationCount,
    required this.advancedCount,
    required this.challengeCount,
    required this.customCount,
  });

  final int totalCount;
  final int foundationCount;
  final int advancedCount;
  final int challengeCount;
  final int customCount;
}
