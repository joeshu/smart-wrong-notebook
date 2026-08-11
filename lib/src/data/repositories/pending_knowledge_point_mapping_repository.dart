import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_wrong_notebook/src/domain/models/pending_knowledge_point_mapping.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_knowledge_link.dart';

/// 「待确认知识点」队列的持久化仓库。
///
/// Phase 4-C：当 AI 返回的知识点文本无法映射到受控节点时，把每条未匹配
/// 文本写入本队列，等待用户在错题详情页手动映射或忽略。已处理的记录
/// 通过 [resolve] 标记，不再出现在待确认列表中。
///
/// 实现沿用 [SharedPreferences] + JSON 数组，与
/// [QuestionKnowledgeLinkRepository] 风格一致。
class PendingKnowledgePointMappingRepository {
  static const _key = 'pending_knowledge_point_mappings_v1';

  /// 全部记录（含已处理），按 `id` 索引。
  final Map<String, PendingKnowledgePointMapping> _byId = {};

  /// questionId → 该题目下的全部记录（含已处理）。
  final Map<String, List<PendingKnowledgePointMapping>> _byQuestion = {};

  bool _loaded = false;

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    final raw = (await SharedPreferences.getInstance()).getString(_key);
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List;
        for (final item in list) {
          final mapping = PendingKnowledgePointMapping.fromJson(
              item as Map<String, dynamic>);
          _index(mapping);
        }
      } catch (_) {
        _byId.clear();
        _byQuestion.clear();
      }
    }
    _loaded = true;
  }

  void _index(PendingKnowledgePointMapping mapping) {
    _byId[mapping.id] = mapping;
    (_byQuestion[mapping.questionId] ??=
            <PendingKnowledgePointMapping>[])
        .add(mapping);
  }

  Future<void> _persist() async {
    final list =
        _byId.values.map((mapping) => mapping.toJson()).toList();
    await (await SharedPreferences.getInstance())
        .setString(_key, jsonEncode(list));
  }

  /// 添加一条待确认记录。同题目下已存在相同 `originalText`（去空格、
  /// 大小写不敏感）且仍在待确认队列中的记录会被跳过，避免重复入库。
  Future<void> add(PendingKnowledgePointMapping mapping) async {
    await _ensureLoaded();
    if (_hasPendingDuplicate(mapping.questionId, mapping.originalText)) {
      return;
    }
    _index(mapping);
    await _persist();
  }

  /// 批量添加。同上，已存在的待确认重复项会被跳过。
  Future<void> addMany(List<PendingKnowledgePointMapping> mappings) async {
    await _ensureLoaded();
    for (final mapping in mappings) {
      if (_hasPendingDuplicate(mapping.questionId, mapping.originalText)) {
        continue;
      }
      _index(mapping);
    }
    await _persist();
  }

  bool _hasPendingDuplicate(String questionId, String originalText) {
    final existing = _byQuestion[questionId];
    if (existing == null) return false;
    final lower = originalText.trim().toLowerCase();
    return existing.any((m) =>
        m.isPending && m.originalText.trim().toLowerCase() == lower);
  }

  /// 查询某题目下仍在待确认队列中的记录。
  Future<List<PendingKnowledgePointMapping>> pendingForQuestion(
      String questionId) async {
    await _ensureLoaded();
    return (_byQuestion[questionId] ?? const <PendingKnowledgePointMapping>[])
        .where((m) => m.isPending)
        .toList();
  }

  /// 查询全部仍在待确认队列中的记录。
  Future<List<PendingKnowledgePointMapping>> allPending() async {
    await _ensureLoaded();
    return _byId.values.where((m) => m.isPending).toList();
  }

  /// 查询全部记录（含已处理项），用于完整备份与审计恢复。
  Future<List<PendingKnowledgePointMapping>> allMappings() async {
    await _ensureLoaded();
    return _byId.values.toList();
  }

  /// 按 ID 合并恢复全部记录，避免重复导入已处理映射。
  Future<void> upsertAll(List<PendingKnowledgePointMapping> mappings) async {
    await _ensureLoaded();
    for (final mapping in mappings) {
      final existing = _byId[mapping.id];
      if (existing != null) {
        _byQuestion[existing.questionId]
            ?.removeWhere((item) => item.id == existing.id);
      }
      _index(mapping);
    }
    await _persist();
  }

  /// 标记某条记录为已处理。`resolution` 不能为 null。
  /// 标记后该记录不再出现在待确认列表中，但仍保留在持久化中以便审计。
  Future<void> resolve(
    String id, {
    required PendingKnowledgePointResolution resolution,
    DateTime? resolvedAt,
  }) async {
    await _ensureLoaded();
    final existing = _byId[id];
    if (existing == null) return;
    final updated = existing.copyWith(
      resolvedAt: resolvedAt ?? DateTime.now(),
      resolution: resolution,
    );
    _replace(updated);
    await _persist();
  }

  void _replace(PendingKnowledgePointMapping updated) {
    _byId[updated.id] = updated;
    final list = _byQuestion[updated.questionId];
    if (list == null) return;
    final index = list.indexWhere((m) => m.id == updated.id);
    if (index >= 0) list[index] = updated;
  }

  /// 仅用于测试：重置缓存。
  @visibleForTesting
  void resetForTest() {
    _byId.clear();
    _byQuestion.clear();
    _loaded = false;
  }
}
