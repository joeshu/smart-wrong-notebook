import 'package:smart_wrong_notebook/src/domain/models/knowledge_point.dart';
import 'package:smart_wrong_notebook/src/domain/models/knowledge_point_seed.dart';

/// 知识点树模板（Phase 9-2）。
///
/// 模板是一组预置的 [KnowledgePoint] 集合，用户可一键应用覆盖或合并
/// 到现有知识树中。当前版本仅提供「默认模板」与「空白模板」两个内置
/// 模板；后续可按教材版本（人教版/北师大版）扩展。
class KnowledgePointTemplate {
  KnowledgePointTemplate({
    required this.id,
    required this.name,
    required this.description,
    required this.points,
  });

  /// 模板唯一 ID。
  final String id;

  /// 显示名称。
  final String name;

  /// 描述（适用场景）。
  final String description;

  /// 模板包含的知识点列表。
  final List<KnowledgePoint> points;

  /// 根节点数量。
  int get rootCount => points.where((p) => p.isRoot).length;
}

/// 模板应用方式。
enum TemplateApplyMode {
  /// 清空现有知识树，写入模板内容。
  replace,

  /// 保留现有知识点，按 ID 合并（已存在的 ID 跳过）。
  merge,
}

/// 内置模板注册表。
class KnowledgePointTemplateRegistry {
  KnowledgePointTemplateRegistry._();

  /// 全部内置模板（每次调用返回新实例）。
  static List<KnowledgePointTemplate> builtins() {
    return <KnowledgePointTemplate>[
      KnowledgePointTemplate(
        id: 'default',
        name: '默认模板',
        description: '内置基础知识点目录（数学 / 物理 / 化学）',
        points: KnowledgePointSeed.builtins(),
      ),
      KnowledgePointTemplate(
        id: 'empty',
        name: '空白模板',
        description: '从零开始构建你的知识树',
        points: const <KnowledgePoint>[],
      ),
    ];
  }

  /// 按 ID 查找内置模板。
  static KnowledgePointTemplate? findById(String id) {
    for (final t in builtins()) {
      if (t.id == id) return t;
    }
    return null;
  }
}
