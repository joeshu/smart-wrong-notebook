import 'package:smart_wrong_notebook/src/data/repositories/knowledge_point_repository.dart';
import 'package:smart_wrong_notebook/src/data/repositories/pending_knowledge_point_mapping_repository.dart';
import 'package:smart_wrong_notebook/src/data/repositories/question_knowledge_link_repository.dart';
import 'package:smart_wrong_notebook/src/domain/models/knowledge_point.dart';
import 'package:smart_wrong_notebook/src/domain/models/pending_knowledge_point_mapping.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_knowledge_link.dart';

/// AI 知识点字符串 → 受控知识点 ID 的映射结果。
class KnowledgePointMatch {
  KnowledgePointMatch({
    required this.originalText,
    this.knowledgePointId,
    this.confidence = 0.0,
    this.matchedName,
  });

  /// AI 返回的原始知识点文本。
  final String originalText;

  /// 匹配到的受控知识点 ID，未匹配为 null。
  final String? knowledgePointId;

  /// 匹配置信度 0.0–1.0。
  final double confidence;

  /// 匹配到的知识点名称（用于 UI 展示）。
  final String? matchedName;

  bool get isMatched => knowledgePointId != null;
}

/// 将 AI 返回的自由文本知识点映射到受控知识点树。
///
/// Phase 4 基础模型：AI 返回的 `knowledgePoints` / `aiKnowledgePoints` 是
/// 自由文本，需要通过此服务映射到 [KnowledgePoint] 受控节点。映射策略：
/// 1. 精确匹配名称或别名（大小写不敏感）
/// 2. 包含匹配（文本包含知识点名称或别名）
/// 3. 未匹配的进入待确认队列
class KnowledgePointMappingService {
  KnowledgePointMappingService(this._kpRepo, this._linkRepo,
      {PendingKnowledgePointMappingRepository? pendingRepo})
      : _pendingRepo = pendingRepo;

  final KnowledgePointRepository _kpRepo;
  final QuestionKnowledgeLinkRepository _linkRepo;

  /// 待确认知识点队列仓库。注入后未匹配的文本会被持久化到待确认队列，
  /// 用户可在错题详情页手动映射或忽略。null 时不持久化（旧行为）。
  final PendingKnowledgePointMappingRepository? _pendingRepo;

  /// 将一组知识点字符串映射到受控节点。
  ///
  /// 返回每个字符串的匹配结果，未匹配的 [KnowledgePointMatch.isMatched]
  /// 为 false，可收集后展示给用户手动确认。
  Future<List<KnowledgePointMatch>> mapStrings(
      List<String> knowledgePointTexts) async {
    final allPoints = await _kpRepo.loadAll();
    final lowerIndex = <String, KnowledgePoint>{};
    for (final kp in allPoints) {
      if (!kp.enabled) continue;
      for (final name in kp.allNames) {
        lowerIndex[name.toLowerCase()] = kp;
      }
    }

    final results = <KnowledgePointMatch>[];
    for (final text in knowledgePointTexts) {
      final trimmed = text.trim();
      if (trimmed.isEmpty) continue;

      final match = _matchSingle(trimmed, lowerIndex);
      results.add(match);
    }
    return results;
  }

  KnowledgePointMatch _matchSingle(
      String text, Map<String, KnowledgePoint> lowerIndex) {
    final lower = text.toLowerCase();

    // 1. 精确匹配
    final exact = lowerIndex[lower];
    if (exact != null) {
      return KnowledgePointMatch(
        originalText: text,
        knowledgePointId: exact.id,
        confidence: 1.0,
        matchedName: exact.name,
      );
    }

    // 2. 包含匹配（文本包含知识点名称，或反之）
    // 要求知识点名称至少 3 个字符，避免"力学""圆"等过短名称误匹配
    KnowledgePoint? bestMatch;
    double bestScore = 0.0;
    for (final entry in lowerIndex.entries) {
      if (entry.key.length < 3) continue;
      if (lower.contains(entry.key) || entry.key.contains(lower)) {
        // 匹配长度占比作为置信度
        final score =
            entry.key.length / lower.length.clamp(1, double.maxFinite);
        if (score > bestScore) {
          bestScore = score.clamp(0.3, 0.9);
          bestMatch = entry.value;
        }
      }
    }

    if (bestMatch != null) {
      return KnowledgePointMatch(
        originalText: text,
        knowledgePointId: bestMatch.id,
        confidence: bestScore,
        matchedName: bestMatch.name,
      );
    }

    // 3. 未匹配
    return KnowledgePointMatch(originalText: text);
  }

  /// 为指定题目创建知识点关联。
  ///
  /// 将匹配结果转为 [QuestionKnowledgeLink] 并持久化。多个字符串匹配到
  /// 同一知识点的只保留一条（取最高置信度）。未匹配的字符串：
  /// - 若注入了 [pendingRepo]，会被写入待确认队列（[PendingKnowledgePointMapping]），
  ///   返回值仍是未匹配文本列表（便于调用方记录日志或继续处理）。
  /// - 否则未匹配文本仅返回，不持久化（旧行为）。
  Future<List<String>> createLinksForQuestion({
    required String questionId,
    required List<String> knowledgePointTexts,
    LinkSource source = LinkSource.ai,
  }) async {
    final matches = await mapStrings(knowledgePointTexts);
    final unmatched = <String>[];
    final now = DateTime.now();

    // 按 knowledgePointId 去重，保留置信度最高的
    final bestByKp = <String, KnowledgePointMatch>{};
    for (final match in matches) {
      if (match.isMatched) {
        final existing = bestByKp[match.knowledgePointId!];
        if (existing == null || match.confidence > existing.confidence) {
          bestByKp[match.knowledgePointId!] = match;
        }
      } else {
        unmatched.add(match.originalText);
      }
    }

    final links = bestByKp.values.toList().asMap().entries.map((entry) {
      final match = entry.value;
      return QuestionKnowledgeLink(
        questionId: questionId,
        knowledgePointId: match.knowledgePointId!,
        source: source,
        confidence: match.confidence,
        evidence: match.originalText,
        createdAt: now,
      );
    }).toList();

    if (links.isNotEmpty) {
      // Phase 6-3：保留之前的 primary 知识点（若仍在新关联中），
      // 否则把第一条设为 primary。一题最多一条 isPrimary=true。
      final oldLinks = await _linkRepo.linksForQuestion(questionId);
      final oldPrimaryId = oldLinks
          .where((l) => l.isPrimary)
          .firstOrNull
          ?.knowledgePointId;
      final hasOldPrimaryInNew =
          oldPrimaryId != null && links.any((l) => l.knowledgePointId == oldPrimaryId);
      final newLinks = links.asMap().entries.map((entry) {
        final link = entry.value;
        final shouldBePrimary =
            hasOldPrimaryInNew ? link.knowledgePointId == oldPrimaryId : entry.key == 0;
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
      await _linkRepo.replaceLinksForQuestion(questionId, newLinks);
    }

    // Phase 4-C：把未匹配文本写入待确认队列，供 UI 手动映射。
    if (_pendingRepo != null && unmatched.isNotEmpty) {
      final pending = <PendingKnowledgePointMapping>[];
      for (final text in unmatched) {
        pending.add(PendingKnowledgePointMapping(
          id: 'pending_${questionId}_${text.hashCode.abs()}',
          questionId: questionId,
          originalText: text,
          source: source,
          createdAt: now,
        ));
      }
      await _pendingRepo.addMany(pending);
    }

    return unmatched;
  }

  /// 批量迁移：将多个题目的 `aiKnowledgePoints` 转为结构化关联。
  ///
  /// 返回每个题目未匹配的知识点文本，可汇总后展示给用户。
  Future<Map<String, List<String>>> migrateFromQuestionRecords(
    List<({String id, List<String> aiKnowledgePoints})> questions,
  ) async {
    final allUnmatched = <String, List<String>>{};

    for (final q in questions) {
      if (q.aiKnowledgePoints.isEmpty) continue;
      final unmatched = await createLinksForQuestion(
        questionId: q.id,
        knowledgePointTexts: q.aiKnowledgePoints,
        source: LinkSource.migrated,
      );
      if (unmatched.isNotEmpty) {
        allUnmatched[q.id] = unmatched;
      }
    }

    return allUnmatched;
  }
}
