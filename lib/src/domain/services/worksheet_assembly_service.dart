import 'dart:math' as math show Random;

import 'package:smart_wrong_notebook/src/domain/models/knowledge_point_mastery.dart';
import 'package:smart_wrong_notebook/src/domain/models/learning_context.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_type.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';

/// Phase 13-1：智能组卷配置。
///
/// 描述一次组卷的目标：题量、难度配比、题型配比、薄弱点权重、知识点
/// 范围与排除项。所有分布权重无需归一化——服务内部会做归一化处理，
/// 调用方只需给相对权重即可（如 foundation:3 / advanced:2 / challenge:1
/// 等价于 50%/33%/17%）。
class WorksheetAssemblyConfig {
  const WorksheetAssemblyConfig({
    required this.totalCount,
    this.difficultyDistribution = const <QuestionDifficulty, double>{
      QuestionDifficulty.foundation: 3,
      QuestionDifficulty.advanced: 2,
      QuestionDifficulty.challenge: 1,
    },
    this.questionTypeDistribution,
    this.knowledgePointWeights,
    this.subjectFilter,
    this.excludeIds = const <String>{},
    this.useWeakPointWeights = true,
    this.requireAllConstraints = false,
    this.seed,
  });

  /// 试卷总题量。
  final int totalCount;

  /// 难度分布（相对权重，服务内归一化）。
  /// null/空 → 不约束难度，按薄弱点权重均匀采样。
  final Map<QuestionDifficulty, double> difficultyDistribution;

  /// 题型分布（相对权重，服务内归一化）。
  /// null → 不约束题型。
  final Map<QuestionType, double>? questionTypeDistribution;

  /// 知识点权重（kpId → 相对权重）。
  /// 若 [useWeakPointWeights] 为 true 且本字段为 null，服务自动用
  /// `(100 - masteryPercentage)` 作权重。
  final Map<String, double>? knowledgePointWeights;

  /// 学科过滤；null = 不限学科。
  final Subject? subjectFilter;

  /// 排除的题目 ID（通常为已选入工作台的题目），不会被采样。
  final Set<String> excludeIds;

  /// 是否用薄弱点数据自动派生知识点权重。
  final bool useWeakPointWeights;

  /// 严格模式：若任一约束（难度/题型配额）无法满足，返回 unmetConstraints
  /// 并按"尽力满足"策略补足；false 时静默补足不报错。
  final bool requireAllConstraints;

  /// 随机种子，便于单测可复现。
  final int? seed;
}

/// Phase 13-1：智能组卷结果。
class WorksheetAssemblyResult {
  const WorksheetAssemblyResult({
    required this.picked,
    required this.reasons,
    required this.coverage,
    required this.unmetConstraints,
  });

  /// 最终选中的题目列表（按难度升序 → 题型稳定排序）。
  final List<QuestionRecord> picked;

  /// questionId → 选中理由列表（可解释性）。
  final Map<String, List<String>> reasons;

  /// 实际达成的分布统计。
  final WorksheetAssemblyCoverage coverage;

  /// 未满足的约束诊断信息（严格模式下用于提示用户）。
  final List<String> unmetConstraints;
}

/// Phase 13-1：组卷实际分布统计。
class WorksheetAssemblyCoverage {
  const WorksheetAssemblyCoverage({
    required this.byDifficulty,
    required this.byQuestionType,
    required this.byKnowledgePoint,
    required this.averageMasteryPercentage,
  });

  /// 按难度统计题数。
  final Map<QuestionDifficulty, int> byDifficulty;

  /// 按题型统计题数。
  final Map<QuestionType, int> byQuestionType;

  /// 按知识点统计题数（kpId → 题数）。
  final Map<String, int> byKnowledgePoint;

  /// 命中题目的平均掌握度（越低越说明击中薄弱点）。
  final double averageMasteryPercentage;
}

/// Phase 13-1：智能组卷服务。
///
/// 基于"薄弱点 + 难度 + 题型"三维加权采样生成试卷。算法步骤：
/// 1. 从题库过滤出候选池（学科、排除项、关联知识点）
/// 2. 按难度分桶，每桶按"薄弱点权重"对题目打分
/// 3. 按难度配额逐桶加权随机采样（不重复）
/// 4. 配额不足时跨桶回填
/// 5. 若启用题型约束，在每桶内再做题型配额控制
/// 6. 生成选中理由（命中薄弱点 / 难度档 / 题型覆盖）
/// 7. 计算实际分布 coverage + 未满足约束 unmetConstraints
///
/// 设计目标：
/// - 薄弱点优先：低掌握度知识点的题目采样权重更高
/// - 可解释：每道题都有"为什么选它"的理由
/// - 可控：难度/题型配比由用户配置，不足时尽力满足
/// - 可测：纯函数式 + 可注入随机种子
class WorksheetAssemblyService {
  WorksheetAssemblyService({math.Random? random}) : _random = random;

  final math.Random? _random;

  /// 难度排序权重：值越小越靠前（越简单）。
  static const Map<QuestionDifficulty, int> _difficultyOrder =
      <QuestionDifficulty, int>{
    QuestionDifficulty.foundation: 0,
    QuestionDifficulty.advanced: 1,
    QuestionDifficulty.custom: 2,
    QuestionDifficulty.challenge: 3,
  };

  /// 执行组卷。
  ///
  /// [questions] 是全量候选题库（服务内会按 subjectFilter/excludeIds 过滤）。
  /// [masteryByKp] 是知识点 ID → 掌握度快照，用于薄弱点权重计算。
  /// [questionKpLinks] 是题目 ID → 主知识点 ID 映射，用于把题目归到知识点。
  WorksheetAssemblyResult assemble({
    required List<QuestionRecord> questions,
    required Map<String, KnowledgePointMastery> masteryByKp,
    required Map<String, String> questionKpLinks,
    required WorksheetAssemblyConfig config,
  }) {
    final random = _random ?? math.Random(config.seed);
    final unmet = <String>[];

    // 1. 候选池过滤。
    final candidates = questions.where((q) {
      if (config.excludeIds.contains(q.id)) return false;
      if (config.subjectFilter != null && q.subject != config.subjectFilter) {
        return false;
      }
      return true;
    }).toList();

    if (candidates.isEmpty) {
      return WorksheetAssemblyResult(
        picked: const <QuestionRecord>[],
        reasons: const <String, List<String>>{},
        coverage: WorksheetAssemblyCoverage(
          byDifficulty: const <QuestionDifficulty, int>{},
          byQuestionType: const <QuestionType, int>{},
          byKnowledgePoint: const <String, int>{},
          averageMasteryPercentage: 0,
        ),
        unmetConstraints: <String>['候选题库为空，无法组卷'],
      );
    }

    // 2. 计算知识点权重：优先用显式配置，否则用薄弱点自动派生。
    final kpWeights = _resolveKpWeights(
      config: config,
      masteryByKp: masteryByKp,
      questionKpLinks: questionKpLinks,
      candidates: candidates,
    );

    // 3. 按难度分桶。
    final byDifficulty = _bucketByDifficulty(candidates);

    // 4. 难度配额计算（归一化到 totalCount）。
    final difficultyQuotas = _calcQuotas(
      distribution: config.difficultyDistribution,
      total: config.totalCount,
      available: {
        for (final entry in byDifficulty.entries) entry.key: entry.value.length,
      },
    );

    // 5. 题型配额（可选）。
    final typeQuotas = config.questionTypeDistribution == null
        ? null
        : _calcQuotas(
            distribution: config.questionTypeDistribution!,
            total: config.totalCount,
            available: _countByType(candidates),
          );

    // 6. 逐桶加权采样。
    final picked = <QuestionRecord>[];
    final pickedIds = <String>{};
    final reasons = <String, List<String>>{};

    for (final entry in difficultyQuotas.entries) {
      final difficulty = entry.key;
      final quota = entry.value;
      if (quota <= 0) continue;
      final pool = byDifficulty[difficulty] ?? const <QuestionRecord>[];
      if (pool.isEmpty) {
        if (config.requireAllConstraints) {
          unmet.add('难度 ${difficulty.name} 配额 $quota 道但题库为空');
        }
        continue;
      }
      final pickedInBucket = _sampleWeighted(
        pool: pool.where((q) => !pickedIds.contains(q.id)).toList(),
        quota: quota,
        kpWeights: kpWeights,
        questionKpLinks: questionKpLinks,
        masteryByKp: masteryByKp,
        typeQuotas: typeQuotas,
        pickedTypeCounts: _countByType(picked),
        random: random,
      );
      for (final q in pickedInBucket) {
        picked.add(q);
        pickedIds.add(q.id);
        reasons[q.id] = _buildReasons(
          question: q,
          difficulty: difficulty,
          masteryByKp: masteryByKp,
          questionKpLinks: questionKpLinks,
        );
      }
      if (pickedInBucket.length < quota && config.requireAllConstraints) {
        unmet.add('难度 ${difficulty.name} 仅采到 ${pickedInBucket.length}/$quota 道');
      }
      // 严格模式：题库可用量低于按权重期望的题量时，单独报难度级短缺，
      // 便于用户在 SnackBar 看到「难度 foundation 期望 5 道但题库仅 1 道」。
      if (config.requireAllConstraints) {
        final requested = _rawQuota(difficulty, config);
        if (requested > 0 && pool.length < requested) {
          unmet.add('难度 ${difficulty.name} 期望 $requested 道但题库仅 ${pool.length} 道');
        }
      }
    }

    // 7. 跨桶回填：若总数不足 totalCount，从剩余候选按薄弱点权重补足。
    if (picked.length < config.totalCount) {
      final remaining = candidates
          .where((q) => !pickedIds.contains(q.id))
          .toList();
      final fillCount = config.totalCount - picked.length;
      final filled = _sampleWeighted(
        pool: remaining,
        quota: fillCount,
        kpWeights: kpWeights,
        questionKpLinks: questionKpLinks,
        masteryByKp: masteryByKp,
        typeQuotas: typeQuotas,
        pickedTypeCounts: _countByType(picked),
        random: random,
      );
      for (final q in filled) {
        picked.add(q);
        pickedIds.add(q.id);
        reasons[q.id] = _buildReasons(
          question: q,
          difficulty: q.difficulty ?? QuestionDifficulty.custom,
          masteryByKp: masteryByKp,
          questionKpLinks: questionKpLinks,
        );
      }
      if (config.requireAllConstraints && picked.length < config.totalCount) {
        unmet.add('总数仅 ${picked.length}/${config.totalCount}，候选题不足');
      }
    }

    // 8. 题型约束诊断。
    if (typeQuotas != null && config.requireAllConstraints) {
      final actualTypeCounts = _countByType(picked);
      for (final entry in typeQuotas.entries) {
        final actual = actualTypeCounts[entry.key] ?? 0;
        if (actual < entry.value) {
          unmet.add('题型 ${entry.key.label} 仅 $actual/${entry.value} 道');
        }
      }
    }

    // 9. 排序：难度升序 → 题型稳定排序。
    picked.sort((a, b) {
      final da = a.difficulty ?? QuestionDifficulty.custom;
      final db = b.difficulty ?? QuestionDifficulty.custom;
      final cmp = (_difficultyOrder[da] ?? 2).compareTo(_difficultyOrder[db] ?? 2);
      if (cmp != 0) return cmp;
      return a.id.compareTo(b.id);
    });

    // 10. 计算 coverage。
    final coverage = _buildCoverage(
      picked: picked,
      masteryByKp: masteryByKp,
      questionKpLinks: questionKpLinks,
    );

    return WorksheetAssemblyResult(
      picked: picked,
      reasons: reasons,
      coverage: coverage,
      unmetConstraints: unmet,
    );
  }

  /// 解析知识点权重：显式配置优先；否则用 (100 - masteryPercentage) 派生。
  Map<String, double> _resolveKpWeights({
    required WorksheetAssemblyConfig config,
    required Map<String, KnowledgePointMastery> masteryByKp,
    required Map<String, String> questionKpLinks,
    required List<QuestionRecord> candidates,
  }) {
    if (config.knowledgePointWeights != null) {
      return Map<String, double>.from(config.knowledgePointWeights!);
    }
    if (!config.useWeakPointWeights) {
      // 不用薄弱点权重 → 所有知识点等权。
      return const <String, double>{};
    }
    // 自动派生：对每个候选题对应的知识点，权重 = 100 - masteryPercentage。
    // 知识点无掌握度数据时（新知识点），权重设为 50（中等优先）。
    final weights = <String, double>{};
    for (final q in candidates) {
      final kpId = questionKpLinks[q.id];
      if (kpId == null) continue;
      if (weights.containsKey(kpId)) continue;
      final mastery = masteryByKp[kpId];
      weights[kpId] = mastery == null ? 50.0 : (100 - mastery.masteryPercentage);
    }
    return weights;
  }

  /// 按难度分桶。无难度信息的题目归到 custom 桶（中等）。
  Map<QuestionDifficulty, List<QuestionRecord>> _bucketByDifficulty(
      List<QuestionRecord> questions) {
    final buckets = <QuestionDifficulty, List<QuestionRecord>>{
      for (final d in QuestionDifficulty.values) d: <QuestionRecord>[],
    };
    for (final q in questions) {
      final d = q.difficulty ?? QuestionDifficulty.custom;
      buckets[d]!.add(q);
    }
    return buckets;
  }

  /// 把相对权重分布归一化为配额（按 total 分配，不足时按比例缩放）。
  Map<T, int> _calcQuotas<T>({
    required Map<T, double> distribution,
    required int total,
    required Map<T, int> available,
  }) {
    if (distribution.isEmpty) return <T, int>{};
    final sum = distribution.values.fold<double>(0, (a, b) => a + b);
    if (sum <= 0) return <T, int>{};
    final quotas = <T, int>{};
    var allocated = 0;
    // 第一遍：按比例分配，受 available 上限约束。
    final entries = distribution.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    for (final entry in entries) {
      if (entry.value <= 0) continue;
      final raw = (entry.value / sum * total).round();
      final cap = available[entry.key] ?? 0;
      final q = raw.clamp(0, cap);
      quotas[entry.key] = q;
      allocated += q;
    }
    // 第二遍：若 allocated < total，按权重降序把差额补给还有余量的桶。
    if (allocated < total) {
      for (final entry in entries) {
        if (allocated >= total) break;
        final cap = available[entry.key] ?? 0;
        final current = quotas[entry.key] ?? 0;
        final slack = (cap - current).clamp(0, total - allocated);
        quotas[entry.key] = current + slack;
        allocated += slack;
      }
    }
    return quotas;
  }

  /// 加权随机采样（不重复）。
  ///
  /// 每道题的权重 = 知识点权重（薄弱点） × 1.0。若启用题型约束，
  /// 对已超额的题型题目权重置 0（避免继续采样）。
  List<QuestionRecord> _sampleWeighted({
    required List<QuestionRecord> pool,
    required int quota,
    required Map<String, double> kpWeights,
    required Map<String, String> questionKpLinks,
    required Map<String, KnowledgePointMastery> masteryByKp,
    Map<QuestionType, int>? typeQuotas,
    required Map<QuestionType, int> pickedTypeCounts,
    required math.Random random,
  }) {
    if (pool.isEmpty || quota <= 0) return const <QuestionRecord>[];
    final result = <QuestionRecord>[];
    final remaining = List<QuestionRecord>.from(pool);

    while (result.length < quota && remaining.isNotEmpty) {
      // 计算每道题的权重。
      final weights = <double>[];
      for (final q in remaining) {
        var w = 1.0;
        final kpId = questionKpLinks[q.id];
        if (kpId != null && kpWeights.containsKey(kpId)) {
          w = kpWeights[kpId]!;
          if (w <= 0) w = 0.01; // 避免 0 权重导致永远采不到
        }
        // 题型约束：已超额题型的题目权重置 0。
        if (typeQuotas != null && q.questionType != null) {
          final cap = typeQuotas[q.questionType!] ?? 0;
          final picked = pickedTypeCounts[q.questionType!] ?? 0;
          if (picked >= cap) {
            w = 0;
          }
        }
        weights.add(w);
      }
      final totalWeight = weights.fold<double>(0, (a, b) => a + b);
      if (totalWeight <= 0) break; // 所有题目都被题型约束屏蔽

      // 加权随机选一个。
      final r = random.nextDouble() * totalWeight;
      var acc = 0.0;
      int pickedIdx = 0;
      for (var i = 0; i < weights.length; i++) {
        acc += weights[i];
        if (r <= acc) {
          pickedIdx = i;
          break;
        }
      }
      final picked = remaining.removeAt(pickedIdx);
      result.add(picked);
      if (picked.questionType != null) {
        pickedTypeCounts[picked.questionType!] =
            (pickedTypeCounts[picked.questionType!] ?? 0) + 1;
      }
    }
    return result;
  }

  /// 为单道题生成选中理由。
  List<String> _buildReasons({
    required QuestionRecord question,
    required QuestionDifficulty difficulty,
    required Map<String, KnowledgePointMastery> masteryByKp,
    required Map<String, String> questionKpLinks,
  }) {
    final reasons = <String>[];
    final difficultyLabel = switch (difficulty) {
      QuestionDifficulty.foundation => '基础题',
      QuestionDifficulty.advanced => '进阶题',
      QuestionDifficulty.challenge => '挑战题',
      QuestionDifficulty.custom => '自定义难度题',
    };
    reasons.add('难度档：$difficultyLabel');

    final kpId = questionKpLinks[question.id];
    if (kpId != null) {
      final mastery = masteryByKp[kpId];
      if (mastery != null) {
        final pct = mastery.masteryPercentage.toStringAsFixed(0);
        if (mastery.masteryPercentage < 30) {
          reasons.add('命中薄弱知识点（掌握度 $pct%）');
        } else if (mastery.masteryPercentage < 60) {
          reasons.add('命中待巩固知识点（掌握度 $pct%）');
        } else {
          reasons.add('关联知识点掌握度 $pct%，保持复习节奏');
        }
        if (mastery.forgotCount > 0) {
          reasons.add('该知识点历史忘记 ${mastery.forgotCount} 次');
        }
      } else {
        reasons.add('关联新知识点，尚未有复习数据');
      }
    } else {
      reasons.add('未关联知识点，按难度档纳入');
    }

    if (question.questionType != null) {
      reasons.add('题型：${question.questionType!.label}');
    }
    return reasons;
  }

  /// 按权重分布计算某难度"期望"题量（未受 available 上限约束），
  /// 仅用于严格模式的短缺诊断。
  int _rawQuota(QuestionDifficulty difficulty, WorksheetAssemblyConfig config) {
    final dist = config.difficultyDistribution;
    if (dist.isEmpty) return 0;
    final sum = dist.values.fold<double>(0, (a, b) => a + b);
    if (sum <= 0) return 0;
    final w = dist[difficulty] ?? 0;
    if (w <= 0) return 0;
    return (w / sum * config.totalCount).round();
  }

  Map<QuestionType, int> _countByType(List<QuestionRecord> questions) {
    final counts = <QuestionType, int>{};
    for (final q in questions) {
      if (q.questionType == null) continue;
      counts[q.questionType!] = (counts[q.questionType!] ?? 0) + 1;
    }
    return counts;
  }

  WorksheetAssemblyCoverage _buildCoverage({
    required List<QuestionRecord> picked,
    required Map<String, KnowledgePointMastery> masteryByKp,
    required Map<String, String> questionKpLinks,
  }) {
    final byDifficulty = <QuestionDifficulty, int>{
      for (final d in QuestionDifficulty.values) d: 0,
    };
    final byQuestionType = <QuestionType, int>{};
    final byKnowledgePoint = <String, int>{};
    final masteryValues = <double>[];

    for (final q in picked) {
      final d = q.difficulty ?? QuestionDifficulty.custom;
      byDifficulty[d] = (byDifficulty[d] ?? 0) + 1;
      if (q.questionType != null) {
        byQuestionType[q.questionType!] =
            (byQuestionType[q.questionType!] ?? 0) + 1;
      }
      final kpId = questionKpLinks[q.id];
      if (kpId != null) {
        byKnowledgePoint[kpId] = (byKnowledgePoint[kpId] ?? 0) + 1;
        final mastery = masteryByKp[kpId];
        if (mastery != null) {
          masteryValues.add(mastery.masteryPercentage);
        }
      }
    }

    final avg = masteryValues.isEmpty
        ? 0.0
        : masteryValues.reduce((a, b) => a + b) / masteryValues.length;

    return WorksheetAssemblyCoverage(
      byDifficulty: byDifficulty,
      byQuestionType: byQuestionType,
      byKnowledgePoint: byKnowledgePoint,
      averageMasteryPercentage: avg,
    );
  }
}
