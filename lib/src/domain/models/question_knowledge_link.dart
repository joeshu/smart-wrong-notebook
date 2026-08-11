/// 题目与知识点的关联来源。
enum LinkSource {
  /// AI 分析自动映射。
  ai,

  /// 用户手动绑定。
  manual,

  /// 从旧的 `aiKnowledgePoints` 字符串迁移而来。
  migrated,
}

/// 题目—知识点关联记录。
///
/// Phase 4 基础模型：建立结构化的三元关联（题目 × 知识点 × 错因），
/// 替代原先仅靠 `aiKnowledgePoints` 字符串数组的松散关系。关联记录
/// 保存来源、置信度和证据，支持后续的掌握度统计和推荐评分。
///
/// Phase 6-3 新增 [isPrimary]：标记主知识点（一题最多一条 primary）。
/// 旧数据缺失该字段时反序列化为 `false`，UI 层会把第一条关联当作
/// primary 的 fallback 展示，避免历史数据被迫迁移。
class QuestionKnowledgeLink {
  QuestionKnowledgeLink({
    required this.questionId,
    required this.knowledgePointId,
    this.source = LinkSource.ai,
    this.confidence,
    this.evidence,
    required this.createdAt,
    this.isPrimary = false,
  });

  /// 关联的题目 ID。
  final String questionId;

  /// 关联的知识点 ID。
  final String knowledgePointId;

  /// 关联来源。
  final LinkSource source;

  /// AI 映射置信度 0.0–1.0，手动绑定为 null。
  final double? confidence;

  /// 关联证据（如 AI 原文片段、用户备注）。
  final String? evidence;

  final DateTime createdAt;

  /// 是否为主知识点。一题最多一条 [isPrimary] 为 `true` 的关联。
  final bool isPrimary;

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'questionId': questionId,
      'knowledgePointId': knowledgePointId,
      'source': source.name,
      'confidence': confidence,
      'evidence': evidence,
      'createdAt': createdAt.toIso8601String(),
      'isPrimary': isPrimary,
    };
  }

  factory QuestionKnowledgeLink.fromJson(Map<String, dynamic> json) {
    return QuestionKnowledgeLink(
      questionId: json['questionId'] as String,
      knowledgePointId: json['knowledgePointId'] as String,
      source: LinkSource.values.firstWhere(
        (source) => source.name == json['source'],
        orElse: () => LinkSource.ai,
      ),
      confidence: (json['confidence'] as num?)?.toDouble(),
      evidence: json['evidence'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      isPrimary: (json['isPrimary'] as bool?) ?? false,
    );
  }

  @override
  String toString() =>
      'QuestionKnowledgeLink($questionId → $knowledgePointId, ${source.name}, '
      'primary=$isPrimary)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is QuestionKnowledgeLink &&
          questionId == other.questionId &&
          knowledgePointId == other.knowledgePointId;

  @override
  int get hashCode => Object.hash(questionId, knowledgePointId);
}
