import 'package:smart_wrong_notebook/src/domain/models/question_knowledge_link.dart';

/// AI 知识点字符串未匹配到受控节点时进入「待确认」队列。
///
/// Phase 4-C：当 [KnowledgePointMappingService.createLinksForQuestion]
/// 返回未匹配文本时，把每条未匹配文本持久化为本记录，等待用户手动
/// 映射到已有知识点或忽略。已映射/已忽略的记录会从队列中移除。
///
/// 持久化由 [PendingKnowledgePointMappingRepository] 完成，
/// UI 入口在错题详情页 `_AnalysisTab`。
class PendingKnowledgePointMapping {
  PendingKnowledgePointMapping({
    required this.id,
    required this.questionId,
    required this.originalText,
    required this.createdAt,
    this.source = LinkSource.ai,
    this.resolvedAt,
    this.resolution,
  });

  /// 唯一 ID，建议使用 uuid。
  final String id;

  /// 关联的题目 ID。
  final String questionId;

  /// AI 返回的原始知识点文本。
  final String originalText;

  /// 来源：AI 分析、迁移、手动等。
  final LinkSource source;

  final DateTime createdAt;

  /// 处理时间，null 表示仍在待确认队列中。
  final DateTime? resolvedAt;

  /// 处理结果，null 表示未处理。
  /// `mapped` = 已映射到受控知识点，`ignored` = 用户忽略。
  final PendingKnowledgePointResolution? resolution;

  /// 是否仍在待确认队列中。
  bool get isPending => resolvedAt == null && resolution == null;

  PendingKnowledgePointMapping copyWith({
    DateTime? resolvedAt,
    PendingKnowledgePointResolution? resolution,
  }) {
    return PendingKnowledgePointMapping(
      id: id,
      questionId: questionId,
      originalText: originalText,
      source: source,
      createdAt: createdAt,
      resolvedAt: resolvedAt ?? this.resolvedAt,
      resolution: resolution ?? this.resolution,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'questionId': questionId,
      'originalText': originalText,
      'source': source.name,
      'createdAt': createdAt.toIso8601String(),
      'resolvedAt': resolvedAt?.toIso8601String(),
      'resolution': resolution?.name,
    };
  }

  factory PendingKnowledgePointMapping.fromJson(Map<String, dynamic> json) {
    LinkSource parseSource(String? name) {
      if (name == null) return LinkSource.ai;
      return LinkSource.values.firstWhere(
        (s) => s.name == name,
        orElse: () => LinkSource.ai,
      );
    }

    PendingKnowledgePointResolution? parseResolution(String? name) {
      if (name == null) return null;
      return PendingKnowledgePointResolution.values.firstWhere(
        (r) => r.name == name,
        orElse: () => PendingKnowledgePointResolution.mapped,
      );
    }

    return PendingKnowledgePointMapping(
      id: json['id'] as String,
      questionId: json['questionId'] as String,
      originalText: json['originalText'] as String,
      source: parseSource(json['source'] as String?),
      createdAt: DateTime.parse(json['createdAt'] as String),
      resolvedAt: json['resolvedAt'] == null
          ? null
          : DateTime.parse(json['resolvedAt'] as String),
      resolution: parseResolution(json['resolution'] as String?),
    );
  }

  @override
  String toString() =>
      'PendingKnowledgePointMapping($questionId, "$originalText", ${resolution?.name ?? "pending"})';
}

/// 待确认知识点的处理结果。
enum PendingKnowledgePointResolution {
  /// 已映射到受控知识点。
  mapped,

  /// 用户主动忽略（不创建关联）。
  ignored,
}
