import 'subject.dart';

/// 受控知识点树节点。
///
/// Phase 4 基础模型：建立结构化知识点体系，替代原先散落在
/// `aiKnowledgePoints` 字符串数组中的自由文本。每个节点有唯一 ID、
/// 支持父子层级（年级 → 学科 → 章节 → 知识点）、别名和启用/停用状态。
class KnowledgePoint {
  KnowledgePoint({
    required this.id,
    required this.name,
    this.aliases = const <String>[],
    this.parentId,
    this.subject,
    this.grade,
    this.enabled = true,
    this.sortOrder = 0,
    required this.createdAt,
    required this.updatedAt,
  });

  /// 稳定唯一 ID，格式 `kp_<ulid>` 或内置目录的语义化 ID。
  final String id;

  /// 知识点显示名称。
  final String name;

  /// 别名列表，用于 AI 映射时的模糊匹配。
  final List<String> aliases;

  /// 父节点 ID，根节点为 null。
  final String? parentId;

  /// 学科，用于按学科筛选知识点树。
  final Subject? subject;

  /// 年级，用于按年级筛选知识点树。
  final String? grade;

  /// 是否启用，停用的知识点不参与推荐和映射。
  final bool enabled;

  /// 同级排序权重，越小越靠前。
  final int sortOrder;

  final DateTime createdAt;
  final DateTime updatedAt;

  /// 是否为根节点。
  bool get isRoot => parentId == null;

  /// 名称 + 别名的全量匹配集合（小写），用于 AI 映射。
  List<String> get allNames => <String>[name, ...aliases];

  /// 哨兵对象，用于区分"未传入"与"传入 null"。
  static const Object _sentinel = Object();

  KnowledgePoint copyWith({
    String? name,
    List<String>? aliases,
    Object? parentId = _sentinel,
    Subject? subject,
    String? grade,
    bool? enabled,
    int? sortOrder,
    DateTime? updatedAt,
  }) {
    return KnowledgePoint(
      id: id,
      name: name ?? this.name,
      aliases: aliases ?? this.aliases,
      parentId: identical(parentId, _sentinel)
          ? this.parentId
          : parentId as String?,
      subject: subject ?? this.subject,
      grade: grade ?? this.grade,
      enabled: enabled ?? this.enabled,
      sortOrder: sortOrder ?? this.sortOrder,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'name': name,
      'aliases': aliases,
      'parentId': parentId,
      'subject': subject?.name,
      'grade': grade,
      'enabled': enabled,
      'sortOrder': sortOrder,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  factory KnowledgePoint.fromJson(Map<String, dynamic> json) {
    return KnowledgePoint(
      id: json['id'] as String,
      name: json['name'] as String,
      aliases: ((json['aliases'] as List?) ?? const <Object>[])
          .map((item) => '$item')
          .toList(),
      parentId: json['parentId'] as String?,
      subject: _parseSubject(json['subject'] as String?),
      grade: json['grade'] as String?,
      enabled: (json['enabled'] as bool?) ?? true,
      sortOrder: (json['sortOrder'] as num?)?.toInt() ?? 0,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  static Subject? _parseSubject(String? name) {
    if (name == null) return null;
    for (final subject in Subject.values) {
      if (subject.name == name) return subject;
    }
    return null;
  }

  @override
  String toString() => 'KnowledgePoint($id, $name)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is KnowledgePoint && id == other.id;

  @override
  int get hashCode => id.hashCode;
}
