import 'package:flutter_test/flutter_test.dart';
import 'package:smart_wrong_notebook/src/domain/models/ai_analysis_contract.dart';
import 'package:smart_wrong_notebook/src/domain/models/ai_analysis_review.dart';
import 'package:smart_wrong_notebook/src/domain/models/ai_response_diagnostics.dart';
import 'package:smart_wrong_notebook/src/domain/models/analysis_result.dart';
import 'package:smart_wrong_notebook/src/domain/models/mistake_category.dart';

void main() {
  test('Contract V2 analysis survives JSON round trip', () {
    final result = AnalysisResult(
      finalAnswer: '3',
      steps: <String>['移项得 x=3'],
      aiTags: <String>['方程'],
      knowledgePoints: <String>['一元一次方程'],
      mistakeReason: '移项时符号错误',
      studyAdvice: '检查移项符号',
      schemaVersion: AiAnalysisSchema.currentVersion,
      promptVersion: AiAnalysisSchema.currentPromptVersion,
      modelName: 'fixture-model',
      confidence: AiConfidence(
        overall: 0.86,
        fields: <String, double>{
          'normalizedQuestion': 0.95,
          'studentAnswer': 0.65,
          'standardAnswer': 0.96,
          'solutionSteps': 0.91,
          'knowledgePoints': 0.84,
          'generatedExercises': 0.76,
        },
      ),
      uncertainties: <AiUncertainty>[
        AiUncertainty(
          field: 'studentAnswer',
          description: '末尾数字不清晰',
          suggestedAction: '核对原图',
        ),
      ],
      evidence: <AiEvidence>[
        AiEvidence(
          field: 'mistakeReason',
          source: AiEvidenceSource.studentAnswer,
          quote: 'x=4+1',
          explanation: '移项未变号',
          stepIndex: 0,
        ),
      ],
      mistakeCategory: MistakeCategory.calculation,
      originalQuestion: 'x+1=4，求x',
      normalizedQuestion: '解方程 x+1=4',
      studentAnswer: 'x=4+1=5',
      standardAnswer: '3',
      solutionSteps: <String>['移项得 x=3'],
      reviewPlan: AiReviewPlan(
        reviewAfterDays: 2,
        focus: <String>['移项符号'],
        reason: '需要及时巩固',
      ),
      reviewDecision: AiAnalysisReviewDecision(
        disposition: AiAnalysisReviewDisposition.needsConfirmation,
        fields: <String>['studentAnswer'],
        reasons: <String>['studentAnswer 置信度低'],
        evaluatedAt: DateTime.utc(2026, 7, 25),
      ),
      pipeline: AiAnalysisPipelineSnapshot(
        status: AiAnalysisPipelineStatus.waitingForConfirmation,
        currentStage: AiAnalysisPipelineStage.questionConfirmation,
        completedStages: <AiAnalysisPipelineStage>[
          AiAnalysisPipelineStage.solving,
        ],
        message: '等待确认',
      ),
      responseDiagnostics: AiResponseDiagnostics(
        contentLength: 1234,
        contentFingerprint: 'abc123def456',
        markdownWrapped: false,
        repairStrategy: 'none',
        capturedAt: DateTime.utc(2026, 7, 25),
      ),
      isLegacyContract: false,
    );

    final restored = AnalysisResult.fromJson(result.toJson());

    expect(restored.hasContractV2, isTrue);
    expect(restored.promptVersion, AiAnalysisSchema.currentPromptVersion);
    expect(restored.modelName, 'fixture-model');
    expect(restored.confidence?.overall, 0.86);
    expect(restored.lowConfidenceFields(threshold: 0.7), ['studentAnswer']);
    expect(restored.uncertainties.single.field, 'studentAnswer');
    expect(restored.evidence.single.source, AiEvidenceSource.studentAnswer);
    expect(restored.mistakeCategory, MistakeCategory.calculation);
    expect(restored.reviewPlan?.reviewAfterDays, 2);
    expect(restored.reviewDecision.requiresConfirmation, isTrue);
    expect(restored.reviewDecision.fields, ['studentAnswer']);
    expect(
      restored.pipeline.status,
      AiAnalysisPipelineStatus.waitingForConfirmation,
    );
    expect(
      restored.pipeline.currentStage,
      AiAnalysisPipelineStage.questionConfirmation,
    );
    expect(restored.responseDiagnostics?.contentLength, 1234);
    expect(restored.responseDiagnostics?.contentFingerprint, 'abc123def456');
    expect(restored.responseDiagnostics?.hasRawResponse, isFalse);
  });

  test('legacy analysis remains readable without fabricated confidence', () {
    final restored = AnalysisResult.fromJson(<String, dynamic>{
      'subject': '数学',
      'finalAnswer': '3',
      'steps': <String>['移项'],
      'aiTags': <String>[],
      'knowledgePoints': <String>['一元一次方程'],
      'mistakeReason': '',
      'studyAdvice': '',
    });

    expect(restored.schemaVersion, 1);
    expect(restored.isLegacyContract, isTrue);
    expect(restored.hasContractV2, isFalse);
    expect(restored.confidence, isNull);
    expect(restored.standardAnswer, '3');
    expect(restored.solutionSteps, ['移项']);
  });

  test('copyWith retains Contract V2 audit metadata', () {
    const original = AnalysisResult(
      finalAnswer: '3',
      steps: <String>['移项'],
      aiTags: <String>[],
      knowledgePoints: <String>['方程'],
      mistakeReason: '',
      studyAdvice: '',
      schemaVersion: 2,
      promptVersion: 'analysis-v2.0.0',
      modelName: 'fixture-model',
      confidence: AiConfidence(overall: 0.9),
      isLegacyContract: false,
    );

    final updated = original.copyWith(consistencyNote: '答案一致');

    expect(updated.schemaVersion, 2);
    expect(updated.promptVersion, 'analysis-v2.0.0');
    expect(updated.modelName, 'fixture-model');
    expect(updated.confidence?.overall, 0.9);
    expect(updated.isLegacyContract, isFalse);
  });
}
