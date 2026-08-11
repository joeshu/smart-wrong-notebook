import 'package:smart_wrong_notebook/src/domain/models/mastery_level.dart';

/// 知识点级掌握度快照。
///
/// Phase 4 基础模型：聚合知识点下所有题目的复习数据，计算掌握度百分比。
/// 由 [KnowledgePointMasteryService] 从题目-知识点关联和复习日志中计算得出。
class KnowledgePointMastery {
  KnowledgePointMastery({
    required this.knowledgePointId,
    required this.totalQuestions,
    required this.masteredCount,
    required this.reviewingCount,
    required this.newCount,
    required this.forgotCount,
    required this.hardCount,
    required this.easyCount,
    required this.lastReviewedAt,
    required this.masteryPercentage,
    required this.calculatedAt,
    this.factors = const <String, double>{},
  });

  /// 知识点 ID。
  final String knowledgePointId;

  /// 关联题目总数（含多知识点题目按权重折算）。
  final int totalQuestions;

  /// 已掌握题数。
  final int masteredCount;

  /// 复习中题数。
  final int reviewingCount;

  /// 新题数（未复习）。
  final int newCount;

  /// 历史复习中"忘记"次数。
  final int forgotCount;

  /// 历史复习中"模糊"次数。
  final int hardCount;

  /// 历史复习中"掌握"次数。
  final int easyCount;

  /// 最近一次复习时间。
  final DateTime? lastReviewedAt;

  /// 掌握度百分比 0.0–100.0。
  final double masteryPercentage;

  /// 计算时间戳。
  final DateTime calculatedAt;

  /// 掌握度计算依据（各因子贡献值），用于 UI 展示。
  final Map<String, double> factors;

  /// 掌握度等级（基于百分比阈值）。
  MasteryLevel get level {
    if (totalQuestions == 0) return MasteryLevel.newQuestion;
    if (masteryPercentage >= 80) return MasteryLevel.mastered;
    if (masteryPercentage >= 30) return MasteryLevel.reviewing;
    return MasteryLevel.newQuestion;
  }

  /// 是否有待复习的题目。
  bool get hasPendingReviews => reviewingCount > 0 || newCount > 0;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'knowledgePointId': knowledgePointId,
      'totalQuestions': totalQuestions,
      'masteredCount': masteredCount,
      'reviewingCount': reviewingCount,
      'newCount': newCount,
      'forgotCount': forgotCount,
      'hardCount': hardCount,
      'easyCount': easyCount,
      'lastReviewedAt': lastReviewedAt?.toIso8601String(),
      'masteryPercentage': masteryPercentage,
      'calculatedAt': calculatedAt.toIso8601String(),
      'factors': factors,
    };
  }

  @override
  String toString() =>
      'KnowledgePointMastery($knowledgePointId: ${masteryPercentage.toStringAsFixed(1)}%)';
}
