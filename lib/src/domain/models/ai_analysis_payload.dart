import 'ai_analysis_contract.dart';
import 'ai_analysis_review.dart';
import 'ai_response_diagnostics.dart';
import 'analysis_result.dart';
import 'generated_exercise.dart';
import 'mistake_category.dart';
import 'question_record.dart';
import 'specialized_analysis.dart';
import 'subject.dart';

class ParsedAnalysisResult extends AnalysisResult {
  const ParsedAnalysisResult({
    required super.finalAnswer,
    required super.steps,
    required super.aiTags,
    required super.knowledgePoints,
    required super.mistakeReason,
    required super.studyAdvice,
    required this.rawContent,
    super.subject,
    super.finalAnswerDerivation,
    super.reconstructedQuestionText,
    super.visualAssumptions,
    super.visualAssumptionStatus,
    super.consistencyStatus,
    super.consistencyNote,
    super.wasVerifierUsed,
    super.schemaVersion,
    super.promptVersion,
    super.modelName,
    super.confidence,
    super.uncertainties,
    super.evidence,
    super.mistakeCategory,
    super.originalQuestion,
    super.normalizedQuestion,
    super.studentAnswer,
    super.standardAnswer,
    super.solutionSteps,
    super.reviewPlan,
    super.isLegacyContract,
    super.reviewDecision,
    super.pipeline,
    super.responseDiagnostics,
    super.specializedAnalysis,
  });

  final String rawContent;

  @override
  AnalysisResult copyWith({
    Subject? subject,
    String? finalAnswer,
    String? finalAnswerDerivation,
    String? reconstructedQuestionText,
    VisualAssumptions? visualAssumptions,
    VisualAssumptionStatus? visualAssumptionStatus,
    List<String>? steps,
    List<String>? aiTags,
    List<String>? knowledgePoints,
    String? mistakeReason,
    String? studyAdvice,
    AnalysisConsistencyStatus? consistencyStatus,
    String? consistencyNote,
    bool? wasVerifierUsed,
    int? schemaVersion,
    String? promptVersion,
    String? modelName,
    AiConfidence? confidence,
    List<AiUncertainty>? uncertainties,
    List<AiEvidence>? evidence,
    MistakeCategory? mistakeCategory,
    String? originalQuestion,
    String? normalizedQuestion,
    String? studentAnswer,
    String? standardAnswer,
    List<String>? solutionSteps,
    AiReviewPlan? reviewPlan,
    bool? isLegacyContract,
    AiAnalysisReviewDecision? reviewDecision,
    AiAnalysisPipelineSnapshot? pipeline,
    AiResponseDiagnostics? responseDiagnostics,
    SpecializedAnalysis? specializedAnalysis,
  }) {
    return ParsedAnalysisResult(
      rawContent: rawContent,
      subject: subject ?? this.subject,
      finalAnswer: finalAnswer ?? this.finalAnswer,
      finalAnswerDerivation:
          finalAnswerDerivation ?? this.finalAnswerDerivation,
      reconstructedQuestionText:
          reconstructedQuestionText ?? this.reconstructedQuestionText,
      visualAssumptions: visualAssumptions ?? this.visualAssumptions,
      visualAssumptionStatus:
          visualAssumptionStatus ?? this.visualAssumptionStatus,
      steps: steps ?? this.steps,
      aiTags: aiTags ?? this.aiTags,
      knowledgePoints: knowledgePoints ?? this.knowledgePoints,
      mistakeReason: mistakeReason ?? this.mistakeReason,
      studyAdvice: studyAdvice ?? this.studyAdvice,
      consistencyStatus: consistencyStatus ?? this.consistencyStatus,
      consistencyNote: consistencyNote ?? this.consistencyNote,
      wasVerifierUsed: wasVerifierUsed ?? this.wasVerifierUsed,
      schemaVersion: schemaVersion ?? this.schemaVersion,
      promptVersion: promptVersion ?? this.promptVersion,
      modelName: modelName ?? this.modelName,
      confidence: confidence ?? this.confidence,
      uncertainties: uncertainties ?? this.uncertainties,
      evidence: evidence ?? this.evidence,
      mistakeCategory: mistakeCategory ?? this.mistakeCategory,
      originalQuestion: originalQuestion ?? this.originalQuestion,
      normalizedQuestion: normalizedQuestion ?? this.normalizedQuestion,
      studentAnswer: studentAnswer ?? this.studentAnswer,
      standardAnswer: standardAnswer ?? this.standardAnswer,
      solutionSteps: solutionSteps ?? this.solutionSteps,
      reviewPlan: reviewPlan ?? this.reviewPlan,
      isLegacyContract: isLegacyContract ?? this.isLegacyContract,
      reviewDecision: reviewDecision ?? this.reviewDecision,
      pipeline: pipeline ?? this.pipeline,
      responseDiagnostics: responseDiagnostics ?? this.responseDiagnostics,
      specializedAnalysis: specializedAnalysis ?? this.specializedAnalysis,
    );
  }
}

class CandidateAnalysisPayload {
  const CandidateAnalysisPayload({
    required this.candidateId,
    required this.order,
    required this.questionText,
    required this.analysisResult,
    required this.savedExercises,
    this.subject,
    this.aiTags = const [],
    this.aiKnowledgePoints = const [],
    this.status = CandidateAnalysisStatus.success,
    this.errorMessage,
  });

  const CandidateAnalysisPayload.failed({
    required this.candidateId,
    required this.order,
    required this.questionText,
    required this.errorMessage,
  })  : analysisResult = null,
        savedExercises = const [],
        subject = null,
        aiTags = const [],
        aiKnowledgePoints = const [],
        status = CandidateAnalysisStatus.failed;

  final String candidateId;
  final int order;
  final String questionText;
  final AnalysisResult? analysisResult;
  final List<GeneratedExercise> savedExercises;
  final Subject? subject;
  final List<String> aiTags;
  final List<String> aiKnowledgePoints;
  final CandidateAnalysisStatus status;
  final String? errorMessage;

  bool get isSuccessful =>
      status == CandidateAnalysisStatus.success && analysisResult != null;
}
