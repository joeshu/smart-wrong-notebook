import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_wrong_notebook/src/data/repositories/knowledge_point_repository.dart';
import 'package:smart_wrong_notebook/src/domain/models/knowledge_point.dart';
import 'package:smart_wrong_notebook/src/domain/models/knowledge_point_seed.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';

/// 受控知识点树管理服务。
///
/// Phase 4 基础模型：负责知识点树的生命周期管理，包括首次播种、
/// 启用/停用、增删改、合并和树形操作。是 UI 层操作知识点树的入口。
class KnowledgePointManagementService {
  KnowledgePointManagementService(this._repo);

  final KnowledgePointRepository _repo;

  static const _seededKey = 'knowledge_points_seeded_v1';

  /// 确保内置知识点目录已播种。仅在首次调用时执行，后续调用幂等跳过。
  ///
  /// 返回是否实际执行了播种。
  Future<bool> ensureSeeded() async {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.getBool(_seededKey) == true) return false;

    final existing = await _repo.loadAll();
    if (existing.isNotEmpty) {
      await prefs.setBool(_seededKey, true);
      return false;
    }

    await _repo.saveAll(KnowledgePointSeed.builtins());
    await prefs.setBool(_seededKey, true);
    return true;
  }

  /// 获取全部知识点（含已停用）。
  Future<List<KnowledgePoint>> all() async {
    return _repo.loadAll();
  }

  /// 获取已启用的知识点。
  Future<List<KnowledgePoint>> enabled() async {
    final all = await _repo.loadAll();
    return all.where((kp) => kp.enabled).toList();
  }

  /// 按学科获取已启用的知识点。
  Future<List<KnowledgePoint>> enabledBySubject(Subject subject) async {
    final all = await _repo.loadAll();
    return all
        .where((kp) => kp.enabled && kp.subject == subject)
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  }

  /// 新增知识点。
  ///
  /// [parentId] 为 null 时创建根节点。返回创建的知识点。
  Future<KnowledgePoint> create({
    required String name,
    List<String>? aliases,
    String? parentId,
    Subject? subject,
    String? grade,
    int sortOrder = 0,
  }) async {
    final now = DateTime.now();
    final id = _generateId(name);
    final kp = KnowledgePoint(
      id: id,
      name: name,
      aliases: aliases ?? const <String>[],
      parentId: parentId,
      subject: subject,
      grade: grade,
      enabled: true,
      sortOrder: sortOrder,
      createdAt: now,
      updatedAt: now,
    );
    await _repo.upsert(kp);
    return kp;
  }

  /// 重命名知识点。
  Future<KnowledgePoint> rename(String id, String newName) async {
    final kp = await _repo.findById(id);
    if (kp == null) {
      throw StateError('KnowledgePoint $id not found');
    }
    final updated = kp.copyWith(name: newName, updatedAt: DateTime.now());
    await _repo.upsert(updated);
    return updated;
  }

  /// 更新别名。
  Future<KnowledgePoint> updateAliases(
      String id, List<String> aliases) async {
    final kp = await _repo.findById(id);
    if (kp == null) {
      throw StateError('KnowledgePoint $id not found');
    }
    final updated =
        kp.copyWith(aliases: aliases, updatedAt: DateTime.now());
    await _repo.upsert(updated);
    return updated;
  }

  /// 启用或停用知识点。停用时其子节点不受影响（可独立启停）。
  Future<KnowledgePoint> setEnabled(String id, bool enabled) async {
    final kp = await _repo.findById(id);
    if (kp == null) {
      throw StateError('KnowledgePoint $id not found');
    }
    final updated = kp.copyWith(enabled: enabled, updatedAt: DateTime.now());
    await _repo.upsert(updated);
    return updated;
  }

  /// 移动知识点到新的父节点下。传入 null 使其成为根节点。
  ///
  /// 会检查是否形成环（不能将节点移动到自己的后代下）。
  Future<KnowledgePoint> move(String id, String? newParentId) async {
    final kp = await _repo.findById(id);
    if (kp == null) {
      throw StateError('KnowledgePoint $id not found');
    }

    // 环检测
    if (newParentId != null) {
      final path = await _repo.ancestorPath(newParentId);
      if (path.any((ancestor) => ancestor.id == id)) {
        throw ArgumentError(
            'Cannot move $id under $newParentId: would create a cycle');
      }
    }

    final updated =
        kp.copyWith(parentId: newParentId, updatedAt: DateTime.now());
    await _repo.upsert(updated);
    return updated;
  }

  /// 合并知识点：将 [sourceId] 的子节点转移到 [targetId]，然后删除 source。
  Future<void> merge(String sourceId, String targetId) async {
    if (sourceId == targetId) {
      throw ArgumentError('Cannot merge a knowledge point with itself');
    }
    await _repo.merge(sourceId, targetId);
  }

  /// 删除知识点。如果有关联题目，调用方应先处理关联（迁移或清除）。
  Future<bool> delete(String id) async {
    return _repo.remove(id);
  }

  /// 获取树形结构：返回根节点列表，每个节点的子节点可通过 [childrenOf] 查询。
  Future<List<KnowledgePoint>> roots() async {
    final all = await _repo.loadAll();
    return all.where((kp) => kp.isRoot).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  }

  /// 获取指定节点的直接子节点。
  Future<List<KnowledgePoint>> childrenOf(String parentId) async {
    return _repo.childrenOf(parentId);
  }

  /// 生成知识点 ID：基于名称和时间戳，确保唯一性。
  String _generateId(String name) {
    final timestamp = DateTime.now().millisecondsSinceEpoch;
    return 'kp_${timestamp}_${name.hashCode.toUnsigned(20).toRadixString(36)}';
  }
}
