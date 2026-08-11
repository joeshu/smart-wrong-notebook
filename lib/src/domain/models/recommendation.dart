import 'package:smart_wrong_notebook/src/domain/models/knowledge_point_mastery.dart';
import 'package:smart_wrong_notebook/src/domain/models/learning_context.dart';

/// 推荐类型。
enum RecommendationType {
  /// 复习已收录的错题。
  review,

  /// 专项练习（基于薄弱知识点生成新题）。
  practice,

  /// 相似题推荐（基于已有题目找相似题）。
  similar,
}

/// 可解释的薄弱点推荐。
///
/// Phase 4 基础模型：基于知识点掌握度、错因分布和复习历史生成推荐，
/// 包含推荐原因（可解释性）和评分（用于排序）。
class Recommendation {
  Recommendation({
    required this.id,
    required this.type,
    required this.knowledgePointId,
    this.questionId,
    this.relatedQuestionIds = const <String>[],
    required this.score,
    required this.reasons,
    required this.createdAt,
    this.ignored = false,
    this.markedInvalid = false,
  });

  /// 推荐唯一 ID。
  final String id;

  /// 推荐类型。
  final RecommendationType type;

  /// 关联知识点 ID。
  final String knowledgePointId;

  /// 关联题目 ID（复习/相似题推荐时有值）。
  final String? questionId;

  /// 相关题目 ID 列表（专项练习时的种子题目）。
  final List<String> relatedQuestionIds;

  /// 推荐评分 0.0–100.0，越高越优先。
  final double score;

  /// 推荐原因列表（可解释性）。
  final List<String> reasons;

  final DateTime createdAt;

  /// 用户是否忽略此推荐。
  final bool ignored;

  /// 用户是否标记此推荐无效。
  final bool markedInvalid;

  /// 是否有效（未被忽略且未被标记无效）。
  bool get isValid => !ignored && !markedInvalid;

  Recommendation copyWith({
    bool? ignored,
    bool? markedInvalid,
  }) {
    return Recommendation(
      id: id,
      type: type,
      knowledgePointId: knowledgePointId,
      questionId: questionId,
      relatedQuestionIds: relatedQuestionIds,
      score: score,
      reasons: reasons,
      createdAt: createdAt,
      ignored: ignored ?? this.ignored,
      markedInvalid: markedInvalid ?? this.markedInvalid,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'type': type.name,
      'knowledgePointId': knowledgePointId,
      'questionId': questionId,
      'relatedQuestionIds': relatedQuestionIds,
      'score': score,
      'reasons': reasons,
      'createdAt': createdAt.toIso8601String(),
      'ignored': ignored,
      'markedInvalid': markedInvalid,
    };
  }

  factory Recommendation.fromJson(Map<String, dynamic> json) {
    return Recommendation(
      id: json['id'] as String,
      type: RecommendationType.values.firstWhere(
        (t) => t.name == json['type'],
        orElse: () => RecommendationType.review,
      ),
      knowledgePointId: json['knowledgePointId'] as String,
      questionId: json['questionId'] as String?,
      relatedQuestionIds: ((json['relatedQuestionIds'] as List?) ?? const <Object>[])
          .map((item) => '$item')
          .toList(),
      score: (json['score'] as num).toDouble(),
      reasons: ((json['reasons'] as List?) ?? const <Object>[])
          .map((item) => '$item')
          .toList(),
      createdAt: DateTime.parse(json['createdAt'] as String),
      ignored: (json['ignored'] as bool?) ?? false,
      markedInvalid: (json['markedInvalid'] as bool?) ?? false,
    );
  }

  @override
  String toString() =>
      'Recommendation($type, $knowledgePointId, score=${score.toStringAsFixed(1)})';
}

/// 推荐评分输入。
class RecommendationInput {
  RecommendationInput({
    required this.knowledgePointId,
    required this.mastery,
    required this.questionIds,
    required this.errorQuestionIds,
    this.overdueQuestionIds = const <String>[],
    this.difficultyByQuestion = const <String, QuestionDifficulty>{},
  });

  final String knowledgePointId;
  final KnowledgePointMastery mastery;
  final List<String> questionIds;
  final List<String> errorQuestionIds;
  final List<String> overdueQuestionIds;

  /// 题目 ID → 难度映射，用于「由易到难」排序推荐题目。
  /// 缺失难度的题目按 [QuestionDifficulty.foundation] 处理。
  final Map<String, QuestionDifficulty> difficultyByQuestion;
}
