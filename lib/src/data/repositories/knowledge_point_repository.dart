import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_wrong_notebook/src/domain/models/knowledge_point.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';

/// 受控知识点树的持久化仓库。
///
/// 使用 SharedPreferences + JSON 存储，避免 Drift schema 迁移。
/// 知识点树通常不超过数百个节点，JSON 序列化性能足够。
class KnowledgePointRepository {
  static const _key = 'knowledge_points_v1';

  final Map<String, KnowledgePoint> _cache = <String, KnowledgePoint>{};
  bool _loaded = false;

  /// 加载全部知识点。
  Future<List<KnowledgePoint>> loadAll() async {
    if (_loaded) return _cache.values.toList();
    final raw = (await SharedPreferences.getInstance()).getString(_key);
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List;
        for (final item in list) {
          final kp = KnowledgePoint.fromJson(item as Map<String, dynamic>);
          _cache[kp.id] = kp;
        }
      } catch (_) {
        _cache.clear();
      }
    }
    _loaded = true;
    return _cache.values.toList();
  }

  /// 保存全部知识点（全量覆盖）。
  Future<void> saveAll(List<KnowledgePoint> points) async {
    _cache
      ..clear()
      ..addEntries(points.map((kp) => MapEntry(kp.id, kp)));
    _loaded = true;
    await _persist();
  }

  /// 新增或更新单个知识点。
  Future<void> upsert(KnowledgePoint point) async {
    await loadAll();
    _cache[point.id] = point;
    await _persist();
  }

  /// 批量新增或更新。
  Future<void> upsertAll(List<KnowledgePoint> points) async {
    await loadAll();
    for (final kp in points) {
      _cache[kp.id] = kp;
    }
    await _persist();
  }

  /// 删除知识点。返回是否实际删除。
  Future<bool> remove(String id) async {
    await loadAll();
    final removed = _cache.remove(id) != null;
    if (removed) await _persist();
    return removed;
  }

  /// 按 ID 查找。
  Future<KnowledgePoint?> findById(String id) async {
    await loadAll();
    return _cache[id];
  }

  /// 按学科筛选。
  Future<List<KnowledgePoint>> findBySubject(Subject subject) async {
    await loadAll();
    return _cache.values
        .where((kp) => kp.subject == subject)
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  }

  /// 获取直接子节点。
  Future<List<KnowledgePoint>> childrenOf(String parentId) async {
    await loadAll();
    return _cache.values
        .where((kp) => kp.parentId == parentId)
        .toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  }

  /// 从指定节点向上遍历到根节点，返回路径（含自身）。
  Future<List<KnowledgePoint>> ancestorPath(String id) async {
    await loadAll();
    final path = <KnowledgePoint>[];
    String? currentId = id;
    while (currentId != null && _cache.containsKey(currentId)) {
      final kp = _cache[currentId]!;
      path.add(kp);
      currentId = kp.parentId;
    }
    return path;
  }

  /// 按名称或别名模糊搜索（大小写不敏感）。
  Future<List<KnowledgePoint>> search(String query) async {
    await loadAll();
    final lowerQuery = query.toLowerCase();
    return _cache.values.where((kp) {
      return kp.allNames.any((name) => name.toLowerCase().contains(lowerQuery));
    }).toList();
  }

  /// 合并知识点：将 [sourceId] 的关联转移到 [targetId]，然后删除 source。
  Future<void> merge(String sourceId, String targetId) async {
    await loadAll();
    final source = _cache[sourceId];
    if (source == null) return;
    // 将 source 的子节点重新挂到 target
    for (final kp in _cache.values) {
      if (kp.parentId == sourceId) {
        _cache[kp.id] = kp.copyWith(parentId: targetId);
      }
    }
    _cache.remove(sourceId);
    await _persist();
  }

  Future<void> _persist() async {
    final list = _cache.values.map((kp) => kp.toJson()).toList();
    await (await SharedPreferences.getInstance())
        .setString(_key, jsonEncode(list));
  }

  /// 仅用于测试：重置缓存。
  @visibleForTesting
  void resetForTest() {
    _cache.clear();
    _loaded = false;
  }
}
