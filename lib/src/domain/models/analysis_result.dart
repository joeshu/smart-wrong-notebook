import 'ai_analysis_contract.dart';
import 'ai_analysis_review.dart';
import 'ai_response_diagnostics.dart';
import 'mistake_category.dart';
import 'specialized_analysis.dart';
import 'subject.dart';

enum AnalysisConsistencyStatus {
  unchecked,
  consistent,
  repaired,
  needsReview,
  unverifiable,
}

enum VisualAssumptionStatus {
  none,
  reliable,
  needsReview,
}

class VisualMeasurementAssumption {
  const VisualMeasurementAssumption({
    required this.label,
    required this.meaning,
    this.usedInSolution = false,
    this.evidence = '',
    this.confidence = '',
  });

  factory VisualMeasurementAssumption.fromJson(Map<String, dynamic> json) {
    return VisualMeasurementAssumption(
      label: json['label'] as String? ?? '',
      meaning: json['meaning'] as String? ?? '',
      usedInSolution: json['usedInSolution'] as bool? ?? false,
      evidence: json['evidence'] as String? ?? '',
      confidence: json['confidence'] as String? ?? '',
    );
  }

  final String label;
  final String meaning;
  final bool usedInSolution;
  final String evidence;
  final String confidence;

  Map<String, dynamic> toJson() {
    return {
      'label': label,
      'meaning': meaning,
      'usedInSolution': usedInSolution,
      'evidence': evidence,
      'confidence': confidence,
    };
  }
}

class VisualAssumptions {
  const VisualAssumptions({
    this.targetObject = '',
    this.targetQuestion = '',
    this.measurements = const [],
    this.solutionBasis = const [],
    this.uncertainItems = const [],
    this.needsManualReview = false,
    this.reviewReason = '',
  });

  factory VisualAssumptions.fromJson(Map<String, dynamic> json) {
    final measurementsJson = json['measurements'] as List? ?? const <Object>[];
    return VisualAssumptions(
      targetObject: json['targetObject'] as String? ?? '',
      targetQuestion: json['targetQuestion'] as String? ?? '',
      measurements: measurementsJson
          .whereType<Map>()
          .map((item) => VisualMeasurementAssumption.fromJson(
                Map<String, dynamic>.from(item),
              ))
          .toList(),
      solutionBasis:
          List<String>.from(json['solutionBasis'] as List? ?? const <String>[]),
      uncertainItems: List<String>.from(
          json['uncertainItems'] as List? ?? const <String>[]),
      needsManualReview: json['needsManualReview'] as bool? ?? false,
      reviewReason: json['reviewReason'] as String? ?? '',
    );
  }

  final String targetObject;
  final String targetQuestion;
  final List<VisualMeasurementAssumption> measurements;
  final List<String> solutionBasis;
  final List<String> uncertainItems;
  final bool needsManualReview;
  final String reviewReason;

  bool get hasContent =>
      targetObject.isNotEmpty ||
      targetQuestion.isNotEmpty ||
      measurements.isNotEmpty ||
      solutionBasis.isNotEmpty ||
      uncertainItems.isNotEmpty ||
      reviewReason.isNotEmpty;

  Map<String, dynamic> toJson() {
    return {
      'targetObject': targetObject,
      'targetQuestion': targetQuestion,
      'measurements': measurements.map((item) => item.toJson()).toList(),
      'solutionBasis': solutionBasis,
      'uncertainItems': uncertainItems,
      'needsManualReview': needsManualReview,
      'reviewReason': reviewReason,
    };
  }
}

class AnalysisResult {
  const AnalysisResult({
    required this.finalAnswer,
    required this.steps,
    required this.aiTags,
    required this.knowledgePoints,
    required this.mistakeReason,
    required this.studyAdvice,
    this.subject,
    this.finalAnswerDerivation = '',
    this.reconstructedQuestionText = '',
    this.visualAssumptions,
    this.visualAssumptionStatus = VisualAssumptionStatus.none,
    this.consistencyStatus = AnalysisConsistencyStatus.unchecked,
    this.consistencyNote = '',
    this.wasVerifierUsed = false,
    this.schemaVersion = 1,
    this.promptVersion = 'legacy-v1',
    this.modelName = '',
    this.confidence,
    this.uncertainties = const <AiUncertainty>[],
    this.evidence = const <AiEvidence>[],
    this.mistakeCategory,
    this.originalQuestion = '',
    this.normalizedQuestion = '',
    this.studentAnswer = '',
    this.standardAnswer = '',
    this.solutionSteps = const <String>[],
    this.reviewPlan,
    this.isLegacyContract = true,
    this.reviewDecision = const AiAnalysisReviewDecision.unknown(),
    this.pipeline = const AiAnalysisPipelineSnapshot.notStarted(),
    this.responseDiagnostics,
    this.specializedAnalysis,
  });

  factory AnalysisResult.fromJson(Map<String, dynamic> json) {
    final subjectStr = json['subject'] as String?;
    Subject? subject;
    if (subjectStr != null && subjectStr.isNotEmpty) {
      subject = _parseSubject(subjectStr);
    }

    final confidenceJson = json['confidence'];
    final uncertaintiesJson = json['uncertainties'] as List? ?? const <Object>[];
    final evidenceJson = json['evidence'] as List? ?? const <Object>[];
    final reviewPlanJson = json['reviewPlan'];
    final reviewDecisionJson = json['reviewDecision'];
    final pipelineJson = json['pipeline'];
    final diagnosticsJson = json['responseDiagnostics'];
    final specializedJson = json['specializedAnalysis'];
    final standardAnswer = json['standardAnswer'] as String? ??
        json['finalAnswer'] as String? ??
        '';
    final solutionSteps = List<String>.from(
      json['solutionSteps'] as List? ?? json['steps'] as List? ?? const <String>[],
    );
    final normalizedQuestion = json['normalizedQuestion'] as String? ??
        json['reconstructedQuestionText'] as String? ??
        '';

    return AnalysisResult(
      subject: subject,
      finalAnswer: json['finalAnswer'] as String? ?? standardAnswer,
      finalAnswerDerivation: json['finalAnswerDerivation'] as String? ?? '',
      reconstructedQuestionText:
          json['reconstructedQuestionText'] as String? ?? normalizedQuestion,
      visualAssumptions: _parseVisualAssumptions(json['visualAssumptions']),
      visualAssumptionStatus: _parseVisualAssumptionStatus(
        json['visualAssumptionStatus'] as String?,
      ),
      steps: List<String>.from(json['steps'] as List? ?? solutionSteps),
      aiTags: List<String>.from(json['aiTags'] as List? ?? []),
      knowledgePoints:
          List<String>.from(json['knowledgePoints'] as List? ?? []),
      mistakeReason: json['mistakeReason'] as String? ?? '',
      studyAdvice: json['studyAdvice'] as String? ?? '',
      consistencyStatus: _parseConsistencyStatus(
        json['consistencyStatus'] as String?,
      ),
      consistencyNote: json['consistencyNote'] as String? ?? '',
      wasVerifierUsed: json['wasVerifierUsed'] as bool? ?? false,
      schemaVersion: json['schemaVersion'] as int? ?? 1,
      promptVersion: json['promptVersion'] as String? ?? 'legacy-v1',
      modelName: json['modelName'] as String? ?? '',
      confidence: confidenceJson is Map
          ? AiConfidence.fromJson(Map<String, dynamic>.from(confidenceJson))
          : null,
      uncertainties: uncertaintiesJson
          .whereType<Map>()
          .map((item) =>
              AiUncertainty.fromJson(Map<String, dynamic>.from(item)))
          .toList(),
      evidence: evidenceJson
          .whereType<Map>()
          .map((item) => AiEvidence.fromJson(Map<String, dynamic>.from(item)))
          .toList(),
      mistakeCategory: parseAiMistakeCategory(json['mistakeCategory']),
      originalQuestion: json['originalQuestion'] as String? ?? '',
      normalizedQuestion: normalizedQuestion,
      studentAnswer: json['studentAnswer'] as String? ?? '',
      standardAnswer: standardAnswer,
      solutionSteps: solutionSteps,
      reviewPlan: reviewPlanJson is Map
          ? AiReviewPlan.fromJson(Map<String, dynamic>.from(reviewPlanJson))
          : null,
      isLegacyContract: json['isLegacyContract'] as bool? ??
          (json['schemaVersion'] as int? ?? 1) < AiAnalysisSchema.currentVersion,
      reviewDecision: reviewDecisionJson is Map
          ? AiAnalysisReviewDecision.fromJson(
              Map<String, dynamic>.from(reviewDecisionJson),
            )
          : const AiAnalysisReviewDecision.unknown(),
      pipeline: pipelineJson is Map
          ? AiAnalysisPipelineSnapshot.fromJson(
              Map<String, dynamic>.from(pipelineJson),
            )
          : const AiAnalysisPipelineSnapshot.notStarted(),
      responseDiagnostics: diagnosticsJson is Map
          ? AiResponseDiagnostics.fromJson(
              Map<String, dynamic>.from(diagnosticsJson),
            )
          : null,
      specializedAnalysis: specializedJson is Map
          ? SpecializedAnalysis.fromJson(
              Map<String, dynamic>.from(specializedJson),
            )
          : null,
    );
  }

  static Subject? _parseSubject(String input) {
    final lower = input.toLowerCase();

    for (final s in Subject.values) {
      if (s.label == input || s.name == input) {
        return s;
      }
    }

    if (lower.contains('物理') || lower == 'wuli' || lower == 'physics') {
      return Subject.physics;
    }
    if (lower.contains('语文') || lower == 'chinese' || lower == 'chinese') {
      return Subject.chinese;
    }
    if (lower.contains('英语') ||
        lower == 'english' ||
        lower.contains('english')) {
      return Subject.english;
    }
    if (lower.contains('化学') || lower == 'chemistry') {
      return Subject.chemistry;
    }
    if (lower.contains('生物') || lower == 'biology') {
      return Subject.biology;
    }
    if (lower.contains('历史') || lower == 'history') {
      return Subject.history;
    }
    if (lower.contains('地理') || lower == 'geography') {
      return Subject.geography;
    }
    if (lower.contains('政治') || lower == 'politics') {
      return Subject.politics;
    }
    if (lower.contains('科学') || lower == 'science') {
      return Subject.science;
    }
    if (lower.contains('数学') ||
        lower == 'math' ||
        lower.contains('mathematics')) {
      return Subject.math;
    }

    return null;
  }

  static AnalysisConsistencyStatus _parseConsistencyStatus(String? value) {
    for (final status in AnalysisConsistencyStatus.values) {
      if (status.name == value) return status;
    }
    return AnalysisConsistencyStatus.unchecked;
  }

  static VisualAssumptionStatus _parseVisualAssumptionStatus(String? value) {
    for (final status in VisualAssumptionStatus.values) {
      if (status.name == value) return status;
    }
    return VisualAssumptionStatus.none;
  }

  static VisualAssumptions? _parseVisualAssumptions(Object? value) {
    if (value is Map<String, dynamic>) {
      return VisualAssumptions.fromJson(value);
    }
    if (value is Map) {
      return VisualAssumptions.fromJson(Map<String, dynamic>.from(value));
    }
    return null;
  }

  Map<String, dynamic> toJson() {
    return {
      'subject': subject?.label ?? subject?.name ?? '',
      'finalAnswer': finalAnswer,
      'finalAnswerDerivation': finalAnswerDerivation,
      'reconstructedQuestionText': reconstructedQuestionText,
      'visualAssumptions': visualAssumptions?.toJson(),
      'visualAssumptionStatus': visualAssumptionStatus.name,
      'steps': steps,
      'aiTags': aiTags,
      'knowledgePoints': knowledgePoints,
      'mistakeReason': mistakeReason,
      'studyAdvice': studyAdvice,
      'consistencyStatus': consistencyStatus.name,
      'consistencyNote': consistencyNote,
      'wasVerifierUsed': wasVerifierUsed,
      'schemaVersion': schemaVersion,
      'promptVersion': promptVersion,
      'modelName': modelName,
      'confidence': confidence?.toJson(),
      'uncertainties': uncertainties.map((item) => item.toJson()).toList(),
      'evidence': evidence.map((item) => item.toJson()).toList(),
      'mistakeCategory': mistakeCategory?.name,
      'originalQuestion': originalQuestion,
      'normalizedQuestion': normalizedQuestion,
      'studentAnswer': studentAnswer,
      'standardAnswer': standardAnswer,
      'solutionSteps': solutionSteps,
      'reviewPlan': reviewPlan?.toJson(),
      'isLegacyContract': isLegacyContract,
      'reviewDecision': reviewDecision.toJson(),
      'pipeline': pipeline.toJson(),
      'responseDiagnostics': responseDiagnostics?.toJson(),
      'specializedAnalysis': specializedAnalysis?.toJson(),
    };
  }

  final Subject? subject;
  final String finalAnswer;
  final String finalAnswerDerivation;
  final String reconstructedQuestionText;
  final VisualAssumptions? visualAssumptions;
  final VisualAssumptionStatus visualAssumptionStatus;
  final List<String> steps;
  final List<String> aiTags;
  final List<String> knowledgePoints;
  final String mistakeReason;
  final String studyAdvice;
  final AnalysisConsistencyStatus consistencyStatus;
  final String consistencyNote;
  final bool wasVerifierUsed;

  /// Contract V2 metadata. Legacy records keep schemaVersion=1 and
  /// [isLegacyContract]=true without inventing confidence or evidence.
  final int schemaVersion;
  final String promptVersion;
  final String modelName;
  final AiConfidence? confidence;
  final List<AiUncertainty> uncertainties;
  final List<AiEvidence> evidence;
  final MistakeCategory? mistakeCategory;
  final String originalQuestion;
  final String normalizedQuestion;
  final String studentAnswer;
  final String standardAnswer;
  final List<String> solutionSteps;
  final AiReviewPlan? reviewPlan;
  final bool isLegacyContract;
  final AiAnalysisReviewDecision reviewDecision;
  final AiAnalysisPipelineSnapshot pipeline;
  final AiResponseDiagnostics? responseDiagnostics;
  final SpecializedAnalysis? specializedAnalysis;

  bool get hasContractV2 =>
      schemaVersion >= AiAnalysisSchema.currentVersion && !isLegacyContract;

  List<String> lowConfidenceFields({double threshold = 0.7}) =>
      confidence?.fieldsBelow(threshold) ?? const <String>[];

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
    return AnalysisResult(
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
