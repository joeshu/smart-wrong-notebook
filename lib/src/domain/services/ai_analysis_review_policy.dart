import 'package:smart_wrong_notebook/src/domain/models/ai_analysis_contract.dart';
import 'package:smart_wrong_notebook/src/domain/models/ai_analysis_review.dart';
import 'package:smart_wrong_notebook/src/domain/models/analysis_result.dart';

class AiAnalysisReviewPolicy {
  const AiAnalysisReviewPolicy({
    this.overallThreshold = 0.72,
    this.defaultFieldThreshold = 0.70,
  });

  final double overallThreshold;
  final double defaultFieldThreshold;

  static const Map<String, double> criticalFieldThresholds = <String, double>{
    'normalizedQuestion': 0.80,
    'studentAnswer': 0.70,
    'standardAnswer': 0.82,
    'solutionSteps': 0.78,
    'knowledgePoints': 0.68,
    'generatedExercises': 0.62,
  };

  AiAnalysisReviewDecision evaluate(
    AnalysisResult result, {
    required bool hasStudentAnswer,
    DateTime? now,
  }) {
    final fields = <String>{};
    final reasons = <String>[];
    final confidence = result.confidence;

    if (!result.hasContractV2 || confidence == null) {
      return AiAnalysisReviewDecision(
        disposition: AiAnalysisReviewDisposition.needsConfirmation,
        fields: const <String>['analysis'],
        reasons: const <String>['分析缺少 Contract V2 置信度，必须人工确认或完整重试'],
        evaluatedAt: now ?? DateTime.now(),
      );
    }

    if (confidence.overall < overallThreshold) {
      fields.add('analysis');
      reasons.add('整体置信度低于 ${(overallThreshold * 100).round()}%');
    }

    for (final entry in criticalFieldThresholds.entries) {
      if (entry.key == 'studentAnswer' && !hasStudentAnswer) continue;
      final score = confidence.fields[entry.key];
      if (score == null) {
        fields.add(entry.key);
        reasons.add('${entry.key} 缺少置信度');
      } else if (score < entry.value) {
        fields.add(entry.key);
        reasons.add(
          '${entry.key} 置信度 ${(score * 100).round()}% '
          '低于 ${(entry.value * 100).round()}%',
        );
      }
    }

    const criticalUncertaintyFields = <String>{
      'normalizedQuestion',
      'studentAnswer',
      'standardAnswer',
      'solutionSteps',
      'mistakeReason',
    };
    for (final uncertainty in result.uncertainties) {
      if (criticalUncertaintyFields.contains(uncertainty.field)) {
        fields.add(uncertainty.field);
        reasons.add('${uncertainty.field} 存在不确定项：${uncertainty.description}');
      }
    }

    if (result.visualAssumptionStatus == VisualAssumptionStatus.needsReview) {
      fields.add('visualAssumptions');
      reasons.add('图中关键标注或关系需要人工核对');
    }
    if (result.consistencyStatus == AnalysisConsistencyStatus.needsReview ||
        result.consistencyStatus == AnalysisConsistencyStatus.unverifiable) {
      fields.add('standardAnswer');
      reasons.add(result.consistencyNote.trim().isEmpty
          ? '答案一致性无法自动确认'
          : result.consistencyNote.trim());
    }

    if (hasStudentAnswer &&
        (result.mistakeReason.trim().isNotEmpty ||
            result.mistakeCategory != null)) {
      final hasEvidence = result.evidence.any(
        (item) =>
            item.field == 'mistakeReason' &&
            item.source == AiEvidenceSource.studentAnswer,
      );
      if (!hasEvidence) {
        fields.add('mistakeReason');
        reasons.add('错因没有引用学生作答证据');
      }
    }

    return AiAnalysisReviewDecision(
      disposition: fields.isEmpty
          ? AiAnalysisReviewDisposition.autoApproved
          : AiAnalysisReviewDisposition.needsConfirmation,
      fields: fields.toList(growable: false)..sort(),
      reasons: reasons.toSet().toList(growable: false),
      evaluatedAt: now ?? DateTime.now(),
    );
  }

  AiAnalysisPipelineSnapshot completedPipeline(
    AiAnalysisReviewDecision decision,
  ) {
    final completed = AiAnalysisPipelineStage.values
        .where((stage) => stage != AiAnalysisPipelineStage.questionConfirmation)
        .toList(growable: false);
    if (decision.requiresConfirmation) {
      return AiAnalysisPipelineSnapshot(
        status: AiAnalysisPipelineStatus.waitingForConfirmation,
        currentStage: AiAnalysisPipelineStage.questionConfirmation,
        completedStages: completed,
        message: 'AI 分析已完成，存在需要人工确认的字段',
      );
    }
    return AiAnalysisPipelineSnapshot(
      status: AiAnalysisPipelineStatus.completed,
      completedStages: AiAnalysisPipelineStage.values,
      message: 'AI 分析和可信度校验已完成',
    );
  }
}
