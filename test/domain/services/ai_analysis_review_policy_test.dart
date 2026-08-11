import 'package:flutter_test/flutter_test.dart';
import 'package:smart_wrong_notebook/src/domain/models/ai_analysis_contract.dart';
import 'package:smart_wrong_notebook/src/domain/models/ai_analysis_review.dart';
import 'package:smart_wrong_notebook/src/domain/models/analysis_result.dart';
import 'package:smart_wrong_notebook/src/domain/services/ai_analysis_review_policy.dart';

void main() {
  const policy = AiAnalysisReviewPolicy();

  test('auto-approves complete high-confidence V2 analysis', () {
    final decision = policy.evaluate(
      _analysis(),
      hasStudentAnswer: false,
      now: DateTime.utc(2026, 7, 25),
    );

    expect(decision.disposition, AiAnalysisReviewDisposition.autoApproved);
    expect(decision.fields, isEmpty);
    expect(
      policy.completedPipeline(decision).status,
      AiAnalysisPipelineStatus.completed,
    );
  });

  test('blocks low-confidence critical field', () {
    final decision = policy.evaluate(
      _analysis(confidenceOverrides: <String, double>{'standardAnswer': 0.4}),
      hasStudentAnswer: false,
    );

    expect(decision.requiresConfirmation, isTrue);
    expect(decision.fields, contains('standardAnswer'));
    expect(decision.reasons.join(' '), contains('40%'));
    expect(
      policy.completedPipeline(decision).currentStage,
      AiAnalysisPipelineStage.questionConfirmation,
    );
  });

  test('student-answer confidence is ignored when answer was not provided', () {
    final decision = policy.evaluate(
      _analysis(confidenceOverrides: <String, double>{'studentAnswer': 0.1}),
      hasStudentAnswer: false,
    );
    expect(decision.fields, isNot(contains('studentAnswer')));
  });

  test('student-answer confidence is required when answer was provided', () {
    final decision = policy.evaluate(
      _analysis(confidenceOverrides: <String, double>{'studentAnswer': 0.1}),
      hasStudentAnswer: true,
    );
    expect(decision.fields, contains('studentAnswer'));
  });

  test('critical uncertainty blocks automatic approval', () {
    final decision = policy.evaluate(
      _analysis(
        uncertainties: const <AiUncertainty>[
          AiUncertainty(
            field: 'normalizedQuestion',
            description: '选项 C 无法辨认',
          ),
        ],
      ),
      hasStudentAnswer: false,
    );
    expect(decision.fields, contains('normalizedQuestion'));
  });

  test('legacy analysis must be confirmed without fabricated confidence', () {
    const legacy = AnalysisResult(
      finalAnswer: '3',
      steps: <String>['移项'],
      aiTags: <String>[],
      knowledgePoints: <String>['方程'],
      mistakeReason: '',
      studyAdvice: '',
    );
    final decision = policy.evaluate(legacy, hasStudentAnswer: false);

    expect(decision.requiresConfirmation, isTrue);
    expect(decision.fields, ['analysis']);
  });

  test('unverifiable consistency blocks automatic approval', () {
    final decision = policy.evaluate(
      _analysis().copyWith(
        consistencyStatus: AnalysisConsistencyStatus.unverifiable,
        consistencyNote: '无法自动提取答案结论',
      ),
      hasStudentAnswer: false,
    );
    expect(decision.fields, contains('standardAnswer'));
  });
}

AnalysisResult _analysis({
  Map<String, double> confidenceOverrides = const <String, double>{},
  List<AiUncertainty> uncertainties = const <AiUncertainty>[],
}) {
  return AnalysisResult(
    finalAnswer: '3',
    steps: const <String>['移项得 x=3'],
    aiTags: const <String>['方程'],
    knowledgePoints: const <String>['一元一次方程'],
    mistakeReason: '',
    studyAdvice: '检查符号',
    schemaVersion: 2,
    promptVersion: 'analysis-v2.0.0',
    modelName: 'fixture-model',
    confidence: AiConfidence(
      overall: 0.9,
      fields: <String, double>{
        'normalizedQuestion': 0.95,
        'studentAnswer': 0.9,
        'standardAnswer': 0.94,
        'solutionSteps': 0.91,
        'knowledgePoints': 0.85,
        'generatedExercises': 0.8,
        ...confidenceOverrides,
      },
    ),
    uncertainties: uncertainties,
    standardAnswer: '3',
    solutionSteps: const <String>['移项得 x=3'],
    normalizedQuestion: '解方程 x+1=4',
    reviewPlan: const AiReviewPlan(
      reviewAfterDays: 2,
      focus: <String>['移项'],
      reason: '巩固规则',
    ),
    consistencyStatus: AnalysisConsistencyStatus.consistent,
    isLegacyContract: false,
  );
}
