import 'dart:convert';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_knowledge_link.dart';

/// 题目—知识点关联的持久化仓库。
///
/// 使用 SharedPreferences + JSON 存储。内部维护两张索引：
/// `_byQuestion`（questionId → links）和 `_byKp`（knowledgePointId → links），
/// 支持双向快速查询。关联数据量与题目数同阶，JSON 性能足够。
class QuestionKnowledgeLinkRepository {
  static const _key = 'question_knowledge_links_v1';

  /// questionId → links
  final Map<String, List<QuestionKnowledgeLink>> _byQuestion = {};

  /// knowledgePointId → links
  final Map<String, List<QuestionKnowledgeLink>> _byKp = {};

  bool _loaded = false;

  Future<void> _ensureLoaded() async {
    if (_loaded) return;
    final raw = (await SharedPreferences.getInstance()).getString(_key);
    if (raw != null && raw.isNotEmpty) {
      try {
        final list = jsonDecode(raw) as List;
        for (final item in list) {
          final link =
              QuestionKnowledgeLink.fromJson(item as Map<String, dynamic>);
          _index(link);
        }
      } catch (_) {
        _byQuestion.clear();
        _byKp.clear();
      }
    }
    _loaded = true;
  }

  void _index(QuestionKnowledgeLink link) {
    (_byQuestion[link.questionId] ??= <QuestionKnowledgeLink>[]).add(link);
    (_byKp[link.knowledgePointId] ??= <QuestionKnowledgeLink>[]).add(link);
  }

  Future<void> _persist() async {
    final all = <QuestionKnowledgeLink>{};
    for (final links in _byQuestion.values) {
      all.addAll(links);
    }
    final list = all.map((link) => link.toJson()).toList();
    await (await SharedPreferences.getInstance())
        .setString(_key, jsonEncode(list));
  }

  /// 添加关联。若已存在相同 (questionId, knowledgePointId) 则跳过。
  Future<void> addLink(QuestionKnowledgeLink link) async {
    await _ensureLoaded();
    final existing = _byQuestion[link.questionId];
    if (existing != null &&
        existing.any((l) => l.knowledgePointId == link.knowledgePointId)) {
      return;
    }
    _index(link);
    await _persist();
  }

  /// 批量添加关联。
  Future<void> addLinks(List<QuestionKnowledgeLink> links) async {
    await _ensureLoaded();
    for (final link in links) {
      final existing = _byQuestion[link.questionId];
      if (existing != null &&
          existing.any((l) => l.knowledgePointId == link.knowledgePointId)) {
        continue;
      }
      _index(link);
    }
    await _persist();
  }

  /// 移除指定关联。返回是否实际移除。
  ///
  /// Phase 6-3：若移除的是主关联且仍有其他关联，自动把剩余首条设为主关联，
  /// 保证一题始终有一个主关联（除非关联全部移除）。
  Future<bool> removeLink(String questionId, String knowledgePointId) async {
    await _ensureLoaded();
    final questionLinks = _byQuestion[questionId];
    if (questionLinks == null) return false;
    final index = questionLinks
        .indexWhere((l) => l.knowledgePointId == knowledgePointId);
    if (index == -1) return false;
    final removed = questionLinks.removeAt(index);
    final kpLinks = _byKp[knowledgePointId];
    kpLinks?.removeWhere((l) => l.questionId == questionId);
    if (removed.isPrimary && questionLinks.isNotEmpty) {
      // 调用 setPrimary 会自动 _persist；剩余首条已在 questionLinks 中。
      await setPrimary(questionId, questionLinks.first.knowledgePointId);
      return true;
    }
    await _persist();
    return true;
  }

  /// 查询某题目的全部关联。
  Future<List<QuestionKnowledgeLink>> linksForQuestion(
      String questionId) async {
    await _ensureLoaded();
    return List<QuestionKnowledgeLink>.from(_byQuestion[questionId] ?? const []);
  }

  /// 查询某知识点关联的全部题目 ID。
  Future<List<String>> questionIdsForKnowledgePoint(
      String knowledgePointId) async {
    await _ensureLoaded();
    return (_byKp[knowledgePointId] ?? const <QuestionKnowledgeLink>[])
        .map((l) => l.questionId)
        .toList();
  }

  /// 查询某知识点的全部关联记录。
  Future<List<QuestionKnowledgeLink>> linksForKnowledgePoint(
      String knowledgePointId) async {
    await _ensureLoaded();
    return List<QuestionKnowledgeLink>.from(
        _byKp[knowledgePointId] ?? const []);
  }

  /// 替换某题目的全部关联（先清除再批量添加）。
  Future<void> replaceLinksForQuestion(
      String questionId, List<QuestionKnowledgeLink> links) async {
    await _ensureLoaded();
    // 清除旧关联
    final oldLinks = _byQuestion.remove(questionId) ?? const [];
    for (final old in oldLinks) {
      _byKp[old.knowledgePointId]?.removeWhere((l) => l.questionId == questionId);
    }
    // 添加新关联
    for (final link in links) {
      _index(link);
    }
    await _persist();
  }

  /// Phase 6-3：把指定知识点设为该题的主知识点。
  ///
  /// 同题其它关联的 [QuestionKnowledgeLink.isPrimary] 会被置为 `false`，
  /// 保证一题最多一条 primary。若指定关联不存在则什么都不做。
  Future<void> setPrimary(String questionId, String knowledgePointId) async {
    await _ensureLoaded();
    final links = _byQuestion[questionId];
    if (links == null) return;
    final hasTarget =
        links.any((l) => l.knowledgePointId == knowledgePointId);
    if (!hasTarget) return;
    final newLinks = links.map((link) {
      final shouldBePrimary = link.knowledgePointId == knowledgePointId;
      if (link.isPrimary == shouldBePrimary) return link;
      return QuestionKnowledgeLink(
        questionId: link.questionId,
        knowledgePointId: link.knowledgePointId,
        source: link.source,
        confidence: link.confidence,
        evidence: link.evidence,
        createdAt: link.createdAt,
        isPrimary: shouldBePrimary,
      );
    }).toList();
    await replaceLinksForQuestion(questionId, newLinks);
  }

  /// 获取全部关联（用于统计聚合）。
  Future<List<QuestionKnowledgeLink>> allLinks() async {
    await _ensureLoaded();
    final all = <QuestionKnowledgeLink>[];
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
    _loaded = false;
  }
}
