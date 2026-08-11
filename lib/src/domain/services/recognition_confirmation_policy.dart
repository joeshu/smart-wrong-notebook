import 'package:smart_wrong_notebook/src/domain/models/question_region.dart';

/// Recognition fields shared by single-question and worksheet review flows.
abstract final class RecognitionReviewField {
  static const stem = 'stem';
  static const options = 'options';
  static const studentAnswer = 'studentAnswer';
  static const formulas = 'formulas';
  static const tables = 'tables';
  static const diagram = 'diagram';
  static const questionAssembly = 'questionAssembly';
  static const authorRoles = 'authorRoles';
  static const specialistBlocks = 'specialistBlocks';

  static const all = <String>{
    stem,
    options,
    studentAnswer,
    formulas,
    tables,
    diagram,
    questionAssembly,
    authorRoles,
    specialistBlocks,
  };
}

/// Result categories for the shared recognition gate.
enum RecognitionConfirmationDecision { autoPass, mustConfirm, ignorePrompt, hardBlock }

/// Stable internal codes. Presentation copy may change without changing the
/// recognition gate's field and hard-block behavior.
enum RecognitionRiskCode {
  stem,
  options,
  studentAnswer,
  formulaAndTable,
  formula,
  table,
  diagram,
  spatialEdge,
  spatialOverlap,
  spatialArea,
  spatialAspectRatio,
  captureOcclusion,
  captureCutOff,
  capturePerspective,
  captureLighting,
  privacyReview,
  questionAssembly,
  authorRoles,
  specialistBlocks,
  qualityAdvisory,
  unknown,
}

abstract final class RecognitionRiskClassifier {
  static RecognitionRiskCode classify(String message) {
    if (message.contains('重叠')) return RecognitionRiskCode.spatialOverlap;
    if (message.contains('宽高比')) {
      return RecognitionRiskCode.spatialAspectRatio;
    }
    if (message.contains('面积')) return RecognitionRiskCode.spatialArea;
    if (message.contains('边缘') || message.contains('贴边')) {
      return RecognitionRiskCode.spatialEdge;
    }
    if (message.contains('遮挡')) return RecognitionRiskCode.captureOcclusion;
    if (message.contains('截断') || message.contains('未拍全')) {
      return RecognitionRiskCode.captureCutOff;
    }
    if (message.contains('透视') || message.contains('弯曲')) {
      return RecognitionRiskCode.capturePerspective;
    }
    if (message.contains('反光') || message.contains('阴影') ||
        message.contains('光照')) {
      return RecognitionRiskCode.captureLighting;
    }
    if (message.contains('隐私') || message.contains('姓名') ||
        message.contains('学校')) {
      return RecognitionRiskCode.privacyReview;
    }
    if (message.contains('父题') || message.contains('大题与小题') ||
        message.contains('阅读顺序') || message.contains('跨栏')) {
      return RecognitionRiskCode.questionAssembly;
    }
    if (message.contains('角色不确定') || message.contains('逐块确认')) {
      return RecognitionRiskCode.authorRoles;
    }
    if (message.contains('专用内容尚未完成') || message.contains('重试此块')) {
      return RecognitionRiskCode.specialistBlocks;
    }
    if (message.contains('公式') && message.contains('表格')) {
      return RecognitionRiskCode.formulaAndTable;
    }
    if (message.contains('公式')) return RecognitionRiskCode.formula;
    if (message.contains('表格')) return RecognitionRiskCode.table;
    if (message.contains('图形')) return RecognitionRiskCode.diagram;
    if (message.contains('选项') || message.contains('候选')) {
      return RecognitionRiskCode.options;
    }
    if (message.contains('作答') || message.contains('答案')) {
      return RecognitionRiskCode.studentAnswer;
    }
    if (message.contains('题干') ||
        message.contains('文字') ||
        message.contains('为空')) {
      return RecognitionRiskCode.stem;
    }
    if (message.contains('提示') || message.contains('建议重拍')) {
      return RecognitionRiskCode.qualityAdvisory;
    }
    return RecognitionRiskCode.unknown;
  }
}

class RecognitionConfirmationEvaluation {
  const RecognitionConfirmationEvaluation({
    required this.decision,
    this.requiredFields = const <String>{},
  });

  final RecognitionConfirmationDecision decision;
  final Set<String> requiredFields;
}

/// Pure gate policy. UI code must use this before auto/batch confirmation.
class RecognitionConfirmationPolicy {
  const RecognitionConfirmationPolicy({this.highConfidenceThreshold = .85});

  static const requiredTag = '__system_recognition_confirmation_required';
  final double highConfidenceThreshold;

  /// Shared worksheet decision. Priority is hardBlock > mustConfirm > autoPass.
  RecognitionConfirmationEvaluation evaluateRegion(
    QuestionRegion region,
    Iterable<String> risks, {
    bool imageAvailable = true,
  }) {
    final riskList = risks.toList(growable: false);
    final fields = fieldsRequiringConfirmation(region, riskList);
    if (region.reviewStatus == QuestionRegionReviewStatus.ignored ||
        hasSpatialRisk(riskList)) {
      // Keep field-level findings for the repair UI, while the decision remains
      // hardBlock until the candidate is no longer ignored/spatially invalid.
      return RecognitionConfirmationEvaluation(
        decision: RecognitionConfirmationDecision.hardBlock,
        requiredFields: fields,
      );
    }
    if (!imageAvailable || fields.isNotEmpty || riskList.isNotEmpty) {
      return RecognitionConfirmationEvaluation(
        decision: !imageAvailable || fields.isNotEmpty
            ? RecognitionConfirmationDecision.mustConfirm
            : _isIgnoreOnlyRisk(riskList)
                ? RecognitionConfirmationDecision.ignorePrompt
                : RecognitionConfirmationDecision.mustConfirm,
        requiredFields: fields,
      );
    }
    return RecognitionConfirmationEvaluation(
      decision: canAutoConfirm(region, riskList)
          ? RecognitionConfirmationDecision.autoPass
          : RecognitionConfirmationDecision.mustConfirm,
      requiredFields: fields,
    );
  }

  /// Shared single-question decision without UI or status side effects.
  RecognitionConfirmationEvaluation evaluateQuestion({
    required double? confidence,
    required String stem,
    required String options,
    required String studentAnswer,
    required bool imageAvailable,
    Iterable<String> risks = const <String>[],
  }) {
    final riskList = risks.toList(growable: false);
    final fields = fieldsRequiringQuestionConfirmation(
      confidence: confidence,
      stem: stem,
      options: options,
      studentAnswer: studentAnswer,
      risks: riskList,
    );
    if (hasSpatialRisk(riskList)) {
      return RecognitionConfirmationEvaluation(
        decision: RecognitionConfirmationDecision.hardBlock,
        requiredFields: fields,
      );
    }
    if (fields.isNotEmpty || riskList.isNotEmpty || !imageAvailable) {
      return RecognitionConfirmationEvaluation(
        decision: !imageAvailable || fields.isNotEmpty
            ? RecognitionConfirmationDecision.mustConfirm
            : _isIgnoreOnlyRisk(riskList)
                ? RecognitionConfirmationDecision.ignorePrompt
                : RecognitionConfirmationDecision.mustConfirm,
        requiredFields: fields,
      );
    }
    return RecognitionConfirmationEvaluation(
      decision: confidence != null &&
              confidence >= highConfidenceThreshold &&
              stem.trim().isNotEmpty &&
              imageAvailable
          ? RecognitionConfirmationDecision.autoPass
          : RecognitionConfirmationDecision.mustConfirm,
    );
  }

  bool isHighConfidence(QuestionRegion region) =>
      region.confidence >= highConfidenceThreshold;

  /// Shared decision for the single-question confirmation screen.
  Set<String> fieldsRequiringQuestionConfirmation({
    required double? confidence,
    required String stem,
    required String options,
    required String studentAnswer,
    Iterable<String> risks = const <String>[],
  }) {
    final fields = <String>{};
    final effectiveConfidence = confidence ?? 0;
    if (effectiveConfidence < highConfidenceThreshold || stem.trim().isEmpty) {
      fields.add(RecognitionReviewField.stem);
    }
    if (options.trim().isNotEmpty && effectiveConfidence < highConfidenceThreshold) {
      fields.add(RecognitionReviewField.options);
    }
    if (studentAnswer.trim().isNotEmpty && effectiveConfidence < highConfidenceThreshold) {
      fields.add(RecognitionReviewField.studentAnswer);
    }
    for (final risk in risks) {
      _addFieldForRisk(fields, RecognitionRiskClassifier.classify(risk));
    }
    return fields;
  }

  bool canAutoConfirmQuestion({
    required double? confidence,
    required String stem,
    required bool imageAvailable,
    Iterable<String> risks = const <String>[],
  }) =>
      (confidence ?? 0) >= highConfidenceThreshold &&
      stem.trim().isNotEmpty &&
      imageAvailable &&
      risks.isEmpty;

  bool canProceedQuestion({
    required double? confidence,
    required String stem,
    required String options,
    required String studentAnswer,
    required Set<String> confirmedFields,
    bool imageAvailable = true,
    Iterable<String> risks = const <String>[],
  }) {
    final riskList = risks.toList(growable: false);
    final evaluation = evaluateQuestion(
      confidence: confidence,
      stem: stem,
      options: options,
      studentAnswer: studentAnswer,
      imageAvailable: imageAvailable,
      risks: riskList,
    );
    if (evaluation.decision == RecognitionConfirmationDecision.hardBlock ||
        !imageAvailable) {
      return false;
    }
    return evaluation.requiredFields.every(confirmedFields.contains);
  }

  Set<String> fieldsRequiringConfirmation(
    QuestionRegion region,
    List<String> risks,
  ) {
    final fields = <String>{};
    final text = (region.recognizedText ?? '').trim();
    if (text.isEmpty || region.confidence < highConfidenceThreshold) {
      fields.add(RecognitionReviewField.stem);
    }
    for (final risk in risks) {
      _addFieldForRisk(fields, RecognitionRiskClassifier.classify(risk));
    }
    return fields;
  }

  bool hasSpatialRisk(List<String> risks) => risks
      .map(RecognitionRiskClassifier.classify)
      .any(_isHardBlockCode);

  bool _isIgnoreOnlyRisk(List<String> risks) => risks.isNotEmpty && risks.every(
        (risk) => RecognitionRiskClassifier.classify(risk) ==
            RecognitionRiskCode.qualityAdvisory,
      );

  static bool _isSpatialCode(RecognitionRiskCode code) =>
      code == RecognitionRiskCode.spatialEdge ||
      code == RecognitionRiskCode.spatialOverlap ||
      code == RecognitionRiskCode.spatialArea ||
      code == RecognitionRiskCode.spatialAspectRatio;

  static bool _isHardBlockCode(RecognitionRiskCode code) =>
      _isSpatialCode(code) ||
      code == RecognitionRiskCode.captureOcclusion ||
      code == RecognitionRiskCode.captureCutOff;

  static void _addFieldForRisk(
    Set<String> fields,
    RecognitionRiskCode code,
  ) {
    switch (code) {
      case RecognitionRiskCode.stem:
        fields.add(RecognitionReviewField.stem);
      case RecognitionRiskCode.options:
        fields.add(RecognitionReviewField.options);
      case RecognitionRiskCode.studentAnswer:
        fields.add(RecognitionReviewField.studentAnswer);
      case RecognitionRiskCode.formulaAndTable:
        fields
          ..add(RecognitionReviewField.formulas)
          ..add(RecognitionReviewField.tables);
      case RecognitionRiskCode.formula:
        fields.add(RecognitionReviewField.formulas);
      case RecognitionRiskCode.table:
        fields.add(RecognitionReviewField.tables);
      case RecognitionRiskCode.diagram:
        fields.add(RecognitionReviewField.diagram);
      case RecognitionRiskCode.questionAssembly:
        fields.add(RecognitionReviewField.questionAssembly);
      case RecognitionRiskCode.authorRoles:
        fields.add(RecognitionReviewField.authorRoles);
      case RecognitionRiskCode.specialistBlocks:
        fields.add(RecognitionReviewField.specialistBlocks);
      case RecognitionRiskCode.spatialEdge:
      case RecognitionRiskCode.spatialOverlap:
      case RecognitionRiskCode.spatialArea:
      case RecognitionRiskCode.spatialAspectRatio:
      case RecognitionRiskCode.captureOcclusion:
      case RecognitionRiskCode.captureCutOff:
      case RecognitionRiskCode.capturePerspective:
      case RecognitionRiskCode.captureLighting:
      case RecognitionRiskCode.privacyReview:
      case RecognitionRiskCode.qualityAdvisory:
      case RecognitionRiskCode.unknown:
        break;
    }
  }

  bool canAutoConfirm(QuestionRegion region, List<String> risks) =>
      region.reviewStatus != QuestionRegionReviewStatus.ignored &&
      isHighConfidence(region) &&
      (region.recognizedText ?? '').trim().isNotEmpty &&
      risks.isEmpty;

  bool canProceed(QuestionRegion region, List<String> risks) {
    if (region.reviewStatus == QuestionRegionReviewStatus.ignored) return false;
    if (hasSpatialRisk(risks)) return false;
    final required = fieldsRequiringConfirmation(region, risks);
    return required.every(region.confirmedFields.contains);
  }
}
