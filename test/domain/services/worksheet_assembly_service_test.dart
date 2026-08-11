import 'dart:math' as math show Random;

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_wrong_notebook/src/domain/models/content_status.dart';
import 'package:smart_wrong_notebook/src/domain/models/knowledge_point_mastery.dart';
import 'package:smart_wrong_notebook/src/domain/models/learning_context.dart';
import 'package:smart_wrong_notebook/src/domain/models/mastery_level.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_type.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';
import 'package:smart_wrong_notebook/src/domain/services/worksheet_assembly_service.dart';

/// Phase 13-1：WorksheetAssemblyService 单测。
///
/// 覆盖：加权采样命中薄弱点、难度配额、题型约束、不足回填、选中理由、
/// 严格模式 unmetConstraints、空候选池兜底。
void main() {
  QuestionRecord _q(
    String id, {
    QuestionDifficulty? difficulty,
    QuestionType? type,
    String kpId = 'kp-default',
  }) {
    final createdAt = DateTime(2026, 1, 1);
    return QuestionRecord(
      id: id,
      imagePath: '',
      subject: Subject.math,
      extractedQuestionText: '题干 $id',
      normalizedQuestionText: '题干 $id',
      contentFormat: QuestionContentFormat.plain,
      tags: difficulty == null
          ? const <String>[]
          : <String>['__system_difficulty:${difficulty.name}'],
      createdAt: createdAt,
      updatedAt: createdAt,
      lastReviewedAt: null,
      reviewCount: 1,
      isFavorite: false,
      contentStatus: ContentStatus.ready,
      masteryLevel: MasteryLevel.reviewing,
      analysisResult: null,
      questionType: type,
    );
  }

  KnowledgePointMastery _mastery(String kpId, double pct) {
    return KnowledgePointMastery(
      knowledgePointId: kpId,
      totalQuestions: 5,
      masteredCount: 0,
      reviewingCount: 5,
      newCount: 0,
      forgotCount: 2,
      hardCount: 1,
      easyCount: 2,
      lastReviewedAt: DateTime(2026, 7, 1),
      masteryPercentage: pct,
      calculatedAt: DateTime(2026, 7, 22),
      factors: const <String, double>{},
    );
  }

  WorksheetAssemblyService _service({int? seed}) =>
      WorksheetAssemblyService(random: math.Random(seed ?? 42));

  test('空候选池返回空结果并报告约束未满足', () {
    final result = _service().assemble(
      questions: const <QuestionRecord>[],
      masteryByKp: const <String, KnowledgePointMastery>{},
      questionKpLinks: const <String, String>{},
      config: const WorksheetAssemblyConfig(totalCount: 5),
    );
    expect(result.picked, isEmpty);
    expect(result.unmetConstraints, contains('候选题库为空，无法组卷'));
    expect(result.coverage.averageMasteryPercentage, 0);
  });

  test('按难度配额采样：foundation 3 / advanced 2 / challenge 1', () {
    final questions = <QuestionRecord>[
      for (var i = 0; i < 10; i++)
        _q('f$i', difficulty: QuestionDifficulty.foundation),
      for (var i = 0; i < 10; i++)
        _q('a$i', difficulty: QuestionDifficulty.advanced),
      for (var i = 0; i < 10; i++)
        _q('c$i', difficulty: QuestionDifficulty.challenge),
    ];
    final result = _service().assemble(
      questions: questions,
      masteryByKp: const <String, KnowledgePointMastery>{},
      questionKpLinks: const <String, String>{},
      config: const WorksheetAssemblyConfig(
        totalCount: 6,
        difficultyDistribution: <QuestionDifficulty, double>{
          QuestionDifficulty.foundation: 3,
          QuestionDifficulty.advanced: 2,
          QuestionDifficulty.challenge: 1,
        },
        useWeakPointWeights: false,
      ),
    );
    expect(result.picked.length, 6);
    expect(result.coverage.byDifficulty[QuestionDifficulty.foundation], 3);
    expect(result.coverage.byDifficulty[QuestionDifficulty.advanced], 2);
    expect(result.coverage.byDifficulty[QuestionDifficulty.challenge], 1);
  });

  test('薄弱点加权：低掌握度知识点题目命中比例更高', () {
    // 5 道 kp-weak（掌握度 10%）+ 5 道 kp-strong（掌握度 95%）。
    final questions = <QuestionRecord>[
      for (var i = 0; i < 5; i++)
        _q('weak$i', difficulty: QuestionDifficulty.foundation, kpId: 'kp-weak'),
      for (var i = 0; i < 5; i++)
        _q('strong$i',
            difficulty: QuestionDifficulty.foundation, kpId: 'kp-strong'),
    ];
    final masteryByKp = <String, KnowledgePointMastery>{
      'kp-weak': _mastery('kp-weak', 10),
      'kp-strong': _mastery('kp-strong', 95),
    };
    final questionKpLinks = <String, String>{
      for (final q in questions) q.id: q.id.startsWith('weak') ? 'kp-weak' : 'kp-strong',
    };
    // 重复采样 5 次，统计 weak 命中数应明显高于 strong（>50% 概率）。
    var weakHits = 0;
    for (var seed = 0; seed < 5; seed++) {
      final result = _service(seed: seed).assemble(
        questions: questions,
        masteryByKp: masteryByKp,
        questionKpLinks: questionKpLinks,
        config: const WorksheetAssemblyConfig(
          totalCount: 5,
          useWeakPointWeights: true,
        ),
      );
      weakHits += result.picked.where((q) => q.id.startsWith('weak')).length;
    }
    // 5 次 × 5 题 = 25 次采样，weak 应占大多数（>50%）。
    expect(weakHits, greaterThan(12));
  });

  test('薄弱点加权：关闭开关后等权采样', () {
    final questions = <QuestionRecord>[
      for (var i = 0; i < 5; i++)
        _q('weak$i', difficulty: QuestionDifficulty.foundation, kpId: 'kp-weak'),
      for (var i = 0; i < 5; i++)
        _q('strong$i',
            difficulty: QuestionDifficulty.foundation, kpId: 'kp-strong'),
    ];
    final masteryByKp = <String, KnowledgePointMastery>{
      'kp-weak': _mastery('kp-weak', 10),
      'kp-strong': _mastery('kp-strong', 95),
    };
    final questionKpLinks = <String, String>{
      for (final q in questions) q.id: q.id.startsWith('weak') ? 'kp-weak' : 'kp-strong',
    };
    // 关闭薄弱点加权 → coverage.averageMasteryPercentage 应接近 (10+95)/2 ≈ 52.5
    final result = _service(seed: 1).assemble(
      questions: questions,
      masteryByKp: masteryByKp,
      questionKpLinks: questionKpLinks,
      config: const WorksheetAssemblyConfig(
        totalCount: 10,
        useWeakPointWeights: false,
      ),
    );
    expect(result.picked.length, 10);
    // 等权采样，平均掌握度应在 40-65 之间（随机波动）。
    expect(result.coverage.averageMasteryPercentage, inInclusiveRange(30, 70));
  });

  test('选中理由包含难度档与命中薄弱知识点', () {
    final questions = <QuestionRecord>[
      _q('q1', difficulty: QuestionDifficulty.foundation, kpId: 'kp-weak'),
    ];
    final masteryByKp = <String, KnowledgePointMastery>{
      'kp-weak': _mastery('kp-weak', 25),
    };
    final result = _service().assemble(
      questions: questions,
      masteryByKp: masteryByKp,
      questionKpLinks: const <String, String>{'q1': 'kp-weak'},
      config: const WorksheetAssemblyConfig(totalCount: 1),
    );
    final reasons = result.reasons['q1']!;
    expect(reasons, anyElement(contains('基础题')));
    expect(reasons, anyElement(contains('薄弱知识点')));
    expect(reasons, anyElement(contains('忘记 2 次')));
  });

  test('不足回填：题库总数小于 totalCount 时全部命中', () {
    final questions = <QuestionRecord>[
      _q('q1', difficulty: QuestionDifficulty.foundation),
      _q('q2', difficulty: QuestionDifficulty.advanced),
    ];
    final result = _service().assemble(
      questions: questions,
      masteryByKp: const <String, KnowledgePointMastery>{},
      questionKpLinks: const <String, String>{},
      config: const WorksheetAssemblyConfig(totalCount: 10),
    );
    expect(result.picked.length, 2);
  });

  test('严格模式：难度配额无法满足时报 unmetConstraints', () {
    // 题库只有 foundation 1 道，但配置要求 foundation 5 道。
    final questions = <QuestionRecord>[
      _q('only', difficulty: QuestionDifficulty.foundation),
    ];
    final result = _service().assemble(
      questions: questions,
      masteryByKp: const <String, KnowledgePointMastery>{},
      questionKpLinks: const <String, String>{},
      config: const WorksheetAssemblyConfig(
        totalCount: 5,
        difficultyDistribution: <QuestionDifficulty, double>{
          QuestionDifficulty.foundation: 5,
        },
        requireAllConstraints: true,
      ),
    );
    expect(result.picked.length, 1);
    expect(result.unmetConstraints, isNotEmpty);
    expect(
      result.unmetConstraints.any((s) => s.contains('foundation')),
      isTrue,
    );
  });

  test('排除已选题目（excludeIds）', () {
    final questions = <QuestionRecord>[
      _q('picked', difficulty: QuestionDifficulty.foundation),
      _q('fresh1', difficulty: QuestionDifficulty.foundation),
      _q('fresh2', difficulty: QuestionDifficulty.foundation),
    ];
    final result = _service().assemble(
      questions: questions,
      masteryByKp: const <String, KnowledgePointMastery>{},
      questionKpLinks: const <String, String>{},
      config: const WorksheetAssemblyConfig(
        totalCount: 2,
        excludeIds: <String>{'picked'},
        useWeakPointWeights: false,
      ),
    );
    expect(result.picked.map((q) => q.id).toList(),
        containsAll(<String>['fresh1', 'fresh2']));
    expect(result.picked.any((q) => q.id == 'picked'), isFalse);
  });

  test('题型约束：超额题型的题目不再被采样', () {
    final questions = <QuestionRecord>[
      for (var i = 0; i < 6; i++)
        _q('single$i',
            difficulty: QuestionDifficulty.foundation,
            type: QuestionType.singleChoice),
      for (var i = 0; i < 6; i++)
        _q('fill$i',
            difficulty: QuestionDifficulty.foundation,
            type: QuestionType.fillIn),
    ];
    final result = _service().assemble(
      questions: questions,
      masteryByKp: const <String, KnowledgePointMastery>{},
      questionKpLinks: const <String, String>{},
      config: const WorksheetAssemblyConfig(
        totalCount: 4,
        difficultyDistribution: <QuestionDifficulty, double>{
          QuestionDifficulty.foundation: 4,
        },
        questionTypeDistribution: <QuestionType, double>{
          QuestionType.singleChoice: 3,
          QuestionType.fillIn: 1,
        },
        useWeakPointWeights: false,
      ),
    );
    expect(result.picked.length, 4);
    expect(result.coverage.byQuestionType[QuestionType.singleChoice], 3);
    expect(result.coverage.byQuestionType[QuestionType.fillIn], 1);
  });

  test('排序：按难度升序输出（foundation → advanced → challenge）', () {
    final questions = <QuestionRecord>[
      _q('c1', difficulty: QuestionDifficulty.challenge),
      _q('f1', difficulty: QuestionDifficulty.foundation),
      _q('a1', difficulty: QuestionDifficulty.advanced),
    ];
    final result = _service().assemble(
      questions: questions,
      masteryByKp: const <String, KnowledgePointMastery>{},
      questionKpLinks: const <String, String>{},
      config: const WorksheetAssemblyConfig(
        totalCount: 3,
        useWeakPointWeights: false,
      ),
    );
    final difficulties = result.picked
        .map((q) => q.difficulty)
        .toList();
    expect(difficulties, <QuestionDifficulty?>[
      QuestionDifficulty.foundation,
      QuestionDifficulty.advanced,
      QuestionDifficulty.challenge,
    ]);
  });

  test('未关联知识点的题目仍能被采样，理由标明"未关联知识点"', () {
    final questions = <QuestionRecord>[
      _q('lonely', difficulty: QuestionDifficulty.foundation),
    ];
    final result = _service().assemble(
      questions: questions,
      masteryByKp: const <String, KnowledgePointMastery>{},
      questionKpLinks: const <String, String>{}, // 无关联
      config: const WorksheetAssemblyConfig(totalCount: 1),
    );
    expect(result.picked.length, 1);
    expect(result.reasons['lonely']!, anyElement(contains('未关联知识点')));
  });
}
