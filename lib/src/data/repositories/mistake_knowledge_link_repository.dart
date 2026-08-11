import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_wrong_notebook/src/domain/models/mistake_category.dart';
import 'package:smart_wrong_notebook/src/domain/models/mistake_knowledge_link.dart';

/// 错因—知识点—题目三元关联的持久化仓库。
///
/// 使用 SharedPreferences + JSON 存储。维护三张索引以支持快速反查：
/// - `_byQuestion`：questionId → links（查询某题的全部错因关联）
/// - `_byKp`：knowledgePointId → links（从知识点反查错题）
/// - `_byCategory`：mistakeCategory → links（统计错因分布）
class MistakeKnowledgeLinkRepository {
  static const _key = 'mistake_knowledge_links_v1';

  final Map<String, List<MistakeKnowledgeLink>> _byQuestion = {};
  final Map<String, List<MistakeKnowledgeLink>> _byKp = {};
  final Map<MistakeCategory, List<MistakeKnowledgeLink>> _byCategory = {};

  bool _loaded = false;

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    final raw = (await SharedPreferences.getInstance()).getString(_key);
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List;
        for (final item in list) {
          final link =
              MistakeKnowledgeLink.fromJson(item as Map<String, dynamic>);
          _index(link);
        }
      } catch (_) {
        _byQuestion.clear();
        _byKp.clear();
        _byCategory.clear();
      }
    }
    _loaded = true;
  }

  void _index(MistakeKnowledgeLink link) {
    (_byQuestion[link.questionId] ??= <MistakeKnowledgeLink>[]).add(link);
    (_byKp[link.knowledgePointId] ??= <MistakeKnowledgeLink>[]).add(link);
    (_byCategory[link.mistakeCategory] ??= <MistakeKnowledgeLink>[])
        .add(link);
  }

  void _removeFromIndex(MistakeKnowledgeLink link) {
    _byQuestion[link.questionId]?.removeWhere((l) => l.key == link.key);
    _byKp[link.knowledgePointId]?.removeWhere((l) => l.key == link.key);
    _byCategory[link.mistakeCategory]?.removeWhere((l) => l.key == link.key);
  }

  Future<void> _persist() async {
    final all = <MistakeKnowledgeLink>{};
    for (final links in _byQuestion.values) {
      all.addAll(links);
    }
    final list = all.map((link) => link.toJson()).toList();
    await (await SharedPreferences.getInstance())
        .setString(_key, jsonEncode(list));
  }

  /// 添加三元关联。若已存在相同 key 则跳过。
  Future<void> addLink(MistakeKnowledgeLink link) async {
    await _ensureLoaded();
    final existing = _byQuestion[link.questionId];
    if (existing != null && existing.any((l) => l.key == link.key)) {
      return;
    }
    _index(link);
    await _persist();
  }

  /// 批量添加。
  Future<void> addLinks(List<MistakeKnowledgeLink> links) async {
    await _ensureLoaded();
    for (final link in links) {
      final existing = _byQuestion[link.questionId];
      if (existing != null && existing.any((l) => l.key == link.key)) {
        continue;
      }
      _index(link);
    }
    await _persist();
  }

  /// 移除指定三元关联。
  Future<bool> removeLink(
      String questionId, String knowledgePointId, MistakeCategory category) async {
    await _ensureLoaded();
    final questionLinks = _byQuestion[questionId];
    if (questionLinks == null) return false;
    final index = questionLinks.indexWhere(
        (l) => l.knowledgePointId == knowledgePointId && l.mistakeCategory == category);
    if (index == -1) return false;
    final removed = questionLinks.removeAt(index);
    _byKp[removed.knowledgePointId]
        ?.removeWhere((l) => l.key == removed.key);
    _byCategory[removed.mistakeCategory]
        ?.removeWhere((l) => l.key == removed.key);
    await _persist();
    return true;
  }

  /// 查询某题目的全部错因关联。
  Future<List<MistakeKnowledgeLink>> linksForQuestion(
      String questionId) async {
    await _ensureLoaded();
    return List<MistakeKnowledgeLink>.from(
        _byQuestion[questionId] ?? const []);
  }

  /// 从知识点反查错题关联。
  Future<List<MistakeKnowledgeLink>> linksForKnowledgePoint(
      String knowledgePointId) async {
    await _ensureLoaded();
    return List<MistakeKnowledgeLink>.from(
        _byKp[knowledgePointId] ?? const []);
  }

  /// 从知识点反查错题 ID（去重）。
  Future<List<String>> questionIdsForKnowledgePoint(
      String knowledgePointId) async {
    await _ensureLoaded();
    return (_byKp[knowledgePointId] ?? const <MistakeKnowledgeLink>[])
        .map((l) => l.questionId)
        .toSet()
        .toList();
  }

  /// 按错因分类查询全部关联。
  Future<List<MistakeKnowledgeLink>> linksForCategory(
      MistakeCategory category) async {
    await _ensureLoaded();
    return List<MistakeKnowledgeLink>.from(
        _byCategory[category] ?? const []);
  }

  /// 统计各错因在指定知识点中的分布。
  ///
  /// 返回 Map<MistakeCategory, int>，表示该知识点下每种错因的关联数。
  Future<Map<MistakeCategory, int>> categoryDistributionForKnowledgePoint(
      String knowledgePointId) async {
    await _ensureLoaded();
    final dist = <MistakeCategory, int>{};
    for (final link in _byKp[knowledgePointId] ?? const <MistakeKnowledgeLink>[]) {
      dist[link.mistakeCategory] = (dist[link.mistakeCategory] ?? 0) + 1;
    }
    return dist;
  }

  /// 统计全部错因分布（跨所有知识点）。
  Future<Map<MistakeCategory, int>> globalCategoryDistribution() async {
    await _ensureLoaded();
    final dist = <MistakeCategory, int>{};
    for (final category in MistakeCategory.values) {
      final count = _byCategory[category]?.length ?? 0;
      if (count > 0) dist[category] = count;
    }
    return dist;
  }

  /// 替换某题目的全部错因关联。
  Future<void> replaceLinksForQuestion(
      String questionId, List<MistakeKnowledgeLink> links) async {
    await _ensureLoaded();
    // 清除旧关联
    final oldLinks = List<MistakeKnowledgeLink>.from(
        _byQuestion[questionId] ?? const []);
    for (final old in oldLinks) {
      _removeFromIndex(old);
    }
    // 添加新关联
    for (final link in links) {
      _index(link);
    }
    await _persist();
  }

  /// 获取全部关联。
  Future<List<MistakeKnowledgeLink>> allLinks() async {
    await _ensureLoaded();
    final all = <MistakeKnowledgeLink>[];
    for (final links in _byQuestion.values) {
      all.addAll(links);
    }
    return all;
  }

  /// 仅用于测试：重置缓存。
  @visibleForTesting
  void resetForTest() {
    _byQuestion.clear();
    _byKp.clear();
    _byCategory.clear();
    _loaded = false;
  }
}
