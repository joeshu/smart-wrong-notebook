import 'ai_analysis_contract.dart';
import 'analysis_result.dart';

/// Fields that can be repaired without rerunning the complete analysis.
enum AiAnalysisField {
  normalizedQuestion,
  studentAnswer,
  standardAnswer,
  solutionSteps,
  knowledgePoints,
  mistakeCategory,
  mistakeReason,
  studyAdvice,
  reviewPlan,
}

class AiAnalysisPatch {
  const AiAnalysisPatch({
    required this.promptVersion,
    required this.modelName,
    required this.fields,
    required this.confidence,
    required this.uncertainties,
    required this.evidence,
  });

  final String promptVersion;
  final String modelName;
  final Map<AiAnalysisField, dynamic> fields;
  final AiConfidence confidence;
  final List<AiUncertainty> uncertainties;
  final List<AiEvidence> evidence;

  AnalysisResult applyTo(AnalysisResult current) {
    final json = current.toJson();
    for (final entry in fields.entries) {
      json[entry.key.name] = entry.value;
      switch (entry.key) {
        case AiAnalysisField.normalizedQuestion:
          json['reconstructedQuestionText'] = entry.value;
          break;
        case AiAnalysisField.standardAnswer:
          json['finalAnswer'] = entry.value;
          break;
        case AiAnalysisField.solutionSteps:
          json['steps'] = entry.value;
          break;
        case AiAnalysisField.studentAnswer:
        case AiAnalysisField.knowledgePoints:
        case AiAnalysisField.mistakeCategory:
        case AiAnalysisField.mistakeReason:
        case AiAnalysisField.studyAdvice:
        case AiAnalysisField.reviewPlan:
          break;
      }
    }

    final mergedConfidence = <String, double>{
      ...?current.confidence?.fields,
      ...confidence.fields,
    };
    json
      ..['schemaVersion'] = AiAnalysisSchema.currentVersion
      ..['promptVersion'] = promptVersion
      ..['modelName'] = modelName
      ..['confidence'] = AiConfidence(
        overall: confidence.overall,
        fields: mergedConfidence,
      ).toJson()
      ..['uncertainties'] = _mergeUncertainties(current)
      ..['evidence'] = _mergeEvidence(current)
      ..['isLegacyContract'] = false;
    return AnalysisResult.fromJson(json);
  }

  List<Map<String, dynamic>> _mergeUncertainties(AnalysisResult current) {
    final repaired = fields.keys.map((field) => field.name).toSet();
    return <AiUncertainty>[
      ...current.uncertainties.where((item) => !repaired.contains(item.field)),
      ...uncertainties,
    ].map((item) => item.toJson()).toList(growable: false);
  }

  List<Map<String, dynamic>> _mergeEvidence(AnalysisResult current) {
    final repaired = fields.keys.map((field) => field.name).toSet();
    return <AiEvidence>[
      ...current.evidence.where((item) => !repaired.contains(item.field)),
      ...evidence,
    ].map((item) => item.toJson()).toList(growable: false);
  }
}

class AiAnalysisPatchContract {
  const AiAnalysisPatchContract._();

  static AiAnalysisPatch parse(
    Map<String, dynamic> input, {
    required Set<AiAnalysisField> requestedFields,
    required String studentAnswer,
  }) {
    if (input['schemaVersion'] != AiAnalysisSchema.currentVersion) {
      throw const FormatException('AI 字段修复响应 schemaVersion 必须为 2');
    }
    final promptVersion = _requiredString(input, 'promptVersion');
    final modelName = _requiredString(input, 'modelName');
    final rawFields = input['fields'];
    if (rawFields is! Map) {
      throw const FormatException('AI 字段修复 fields 必须是对象');
    }

    const diagnosisFields = <AiAnalysisField>{
      AiAnalysisField.mistakeCategory,
      AiAnalysisField.mistakeReason,
    };
    final requestedDiagnosis = requestedFields.intersection(diagnosisFields);
    if (requestedDiagnosis.isNotEmpty &&
        requestedDiagnosis.length != diagnosisFields.length) {
      throw const FormatException(
        'mistakeCategory 与 mistakeReason 必须一起修复',
      );
    }

    final fields = <AiAnalysisField, dynamic>{};
    for (final entry in rawFields.entries) {
      final field = _parseField(entry.key);
      if (!requestedFields.contains(field)) {
        throw FormatException('AI 返回了未请求的修复字段: ${field.name}');
      }
      fields[field] = _validateFieldValue(field, entry.value);
    }
    final missing = requestedFields.difference(fields.keys.toSet());
    if (missing.isNotEmpty) {
      throw FormatException(
        'AI 字段修复缺少: ${missing.map((field) => field.name).join(', ')}',
      );
    }

    final rawConfidence = input['confidence'];
    if (rawConfidence is! Map) {
      throw const FormatException('AI 字段修复 confidence 必须是对象');
    }
    final confidence = AiConfidence.fromJson(
      Map<String, dynamic>.from(rawConfidence),
    );
    final confidenceMissing = requestedFields
        .map((field) => field.name)
        .where((field) => !confidence.fields.containsKey(field))
        .toList();
    if (confidenceMissing.isNotEmpty) {
      throw FormatException(
        'AI 字段修复 confidence.fields 缺少: ${confidenceMissing.join(', ')}',
      );
    }

    final uncertainties = _objectList(input, 'uncertainties')
        .map(AiUncertainty.fromJson)
        .toList(growable: false);
    final evidence = _objectList(input, 'evidence')
        .map(AiEvidence.fromJson)
        .toList(growable: false);
    final category = fields[AiAnalysisField.mistakeCategory];
    final reason = fields[AiAnalysisField.mistakeReason];
    final hasDiagnosis = category != null || reason is String && reason.trim().isNotEmpty;
    if (studentAnswer.trim().isEmpty && hasDiagnosis) {
      throw const FormatException('缺少 studentAnswer 时不得局部生成确定性错因');
    }
    if (hasDiagnosis &&
        !evidence.any((item) =>
            item.field == 'mistakeReason' &&
            item.source == AiEvidenceSource.studentAnswer)) {
      throw const FormatException('AI 局部错因修复必须引用 studentAnswer 证据');
    }

    return AiAnalysisPatch(
      promptVersion: promptVersion,
      modelName: modelName,
      fields: fields,
      confidence: confidence,
      uncertainties: uncertainties,
      evidence: evidence,
    );
  }

  static AiAnalysisField _parseField(Object? value) {
    if (value is String) {
      for (final field in AiAnalysisField.values) {
        if (field.name == value) return field;
      }
    }
    throw FormatException('不支持的 AI 修复字段: $value');
  }

  static dynamic _validateFieldValue(AiAnalysisField field, dynamic value) {
    switch (field) {
      case AiAnalysisField.solutionSteps:
      case AiAnalysisField.knowledgePoints:
        if (value is! List || value.any((item) => item is! String)) {
          throw FormatException('AI 修复字段 ${field.name} 必须是文本数组');
        }
        return List<String>.from(value);
      case AiAnalysisField.mistakeCategory:
        if (value != null && value is! String) {
          throw const FormatException('AI 修复字段 mistakeCategory 必须是文本或 null');
        }
        parseAiMistakeCategory(value);
        return value;
      case AiAnalysisField.reviewPlan:
        if (value is! Map) {
          throw const FormatException('AI 修复字段 reviewPlan 必须是对象');
        }
        return AiReviewPlan.fromJson(Map<String, dynamic>.from(value)).toJson();
      case AiAnalysisField.normalizedQuestion:
      case AiAnalysisField.studentAnswer:
      case AiAnalysisField.standardAnswer:
      case AiAnalysisField.mistakeReason:
      case AiAnalysisField.studyAdvice:
        if (value is! String) {
          throw FormatException('AI 修复字段 ${field.name} 必须是文本');
        }
        return value;
    }
  }

  static String _requiredString(Map<String, dynamic> input, String key) {
    final value = input[key];
    if (value is! String || value.trim().isEmpty) {
      throw FormatException('AI 字段修复 $key 必须是非空文本');
    }
    return value;
  }

  static List<Map<String, dynamic>> _objectList(
    Map<String, dynamic> input,
    String key,
  ) {
    final value = input[key];
    if (value is! List || value.any((item) => item is! Map)) {
      throw FormatException('AI 字段修复 $key 必须是对象数组');
    }
    return value
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList(growable: false);
  }
}
