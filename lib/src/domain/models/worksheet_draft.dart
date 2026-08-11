/// 组卷草稿 / 历史组卷。
///
/// 保存用户在工作台选中的题目 ID 顺序列表和命名，便于跨会话恢复、
/// 复用历史组卷或基于已有组卷复制派生新组卷。
class WorksheetDraft {
  WorksheetDraft({
    required this.id,
    required this.name,
    required this.questionIds,
    required this.createdAt,
    required this.updatedAt,
  });

  /// 从 JSON 构造（持久化恢复）。
  factory WorksheetDraft.fromJson(Map<String, dynamic> json) {
    return WorksheetDraft(
      id: json['id'] as String,
      name: json['name'] as String,
      questionIds: ((json['questionIds'] as List?) ?? const <Object>[])
          .map((item) => '$item')
          .toList(growable: false),
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  final String id;
  final String name;
  final List<String> questionIds;
  final DateTime createdAt;
  final DateTime updatedAt;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'name': name,
        'questionIds': questionIds,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  WorksheetDraft copyWith({
    String? id,
    String? name,
    List<String>? questionIds,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) =>
      WorksheetDraft(
        id: id ?? this.id,
        name: name ?? this.name,
        questionIds: questionIds ?? this.questionIds,
        createdAt: createdAt ?? this.createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
      );
}
