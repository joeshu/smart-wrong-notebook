import 'package:smart_wrong_notebook/src/domain/models/mistake_category.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_knowledge_link.dart';

/// 错因—知识点—题目三元关联记录。
///
/// Phase 4 基础模型：在 [QuestionKnowledgeLink]（题目×知识点）的基础上
/// 增加错因维度，形成 (题目 × 知识点 × 错因) 三元组。支持：
/// - 一题多错因（同一知识点上多种错误类型）
/// - 一错因多知识点（一次错误涉及多个知识点）
/// - 一知识点多题目（同一知识点在多道题中出错）
class MistakeKnowledgeLink {
  MistakeKnowledgeLink({
    required this.questionId,
    required this.knowledgePointId,
    required this.mistakeCategory,
    this.source = LinkSource.ai,
    this.confidence,
    this.evidence,
    this.errorStep,
    required this.createdAt,
  });

  /// 关联的题目 ID。
  final String questionId;

  /// 关联的知识点 ID。
  final String knowledgePointId;

  /// 错因分类。
  final MistakeCategory mistakeCategory;

  /// 关联来源。
  final LinkSource source;

  /// AI 映射置信度 0.0–1.0。
  final double? confidence;

  /// 关联证据（如 AI 原文片段）。
  final String? evidence;

  /// 出错的步骤序号或描述（用于"显示典型错误步骤"）。
  final String? errorStep;

  final DateTime createdAt;

  /// 唯一标识：(questionId, knowledgePointId, mistakeCategory)。
  String get key => '$questionId|$knowledgePointId|${mistakeCategory.name}';

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'questionId': questionId,
      'knowledgePointId': knowledgePointId,
      'mistakeCategory': mistakeCategory.name,
      'source': source.name,
      'confidence': confidence,
      'evidence': evidence,
      'errorStep': errorStep,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory MistakeKnowledgeLink.fromJson(Map<String, dynamic> json) {
    return MistakeKnowledgeLink(
      questionId: json['questionId'] as String,
      knowledgePointId: json['knowledgePointId'] as String,
      mistakeCategory: MistakeCategory.values.firstWhere(
        (cat) => cat.name == json['mistakeCategory'],
        orElse: () => MistakeCategory.concept,
      ),
      source: LinkSource.values.firstWhere(
        (source) => source.name == json['source'],
        orElse: () => LinkSource.ai,
      ),
      confidence: (json['confidence'] as num?)?.toDouble(),
      evidence: json['evidence'] as String?,
      errorStep: json['errorStep'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }

  @override
  String toString() =>
      'MistakeKnowledgeLink($questionId → $knowledgePointId, ${mistakeCategory.label})';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MistakeKnowledgeLink && key == other.key;

  @override
  int get hashCode => key.hashCode;
}
