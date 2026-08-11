import 'package:smart_wrong_notebook/src/domain/models/ai_analysis_contract.dart';
import 'package:smart_wrong_notebook/src/domain/models/specialized_analysis.dart';

/// Versioned validation at the AI network boundary.
///
/// V2 responses are strict: every contract field must be present with the
/// expected type. Legacy payloads remain readable through an explicit V1
/// compatibility mapping, but are marked as legacy and receive no fabricated
/// confidence score.
class AiAnalysisResponseContract {
  const AiAnalysisResponseContract._();

  static const version = AiAnalysisSchema.currentVersion;

  static Map<String, dynamic> normalize(
    Map<String, dynamic> input, {
    bool allowLegacy = true,
  }) {
    final rawVersion = input['schemaVersion'];
    if (rawVersion == null) {
      if (!allowLegacy) {
        throw const FormatException('AI 响应缺少 schemaVersion');
      }
      return _normalizeLegacyV1(input);
    }
    if (rawVersion is! int) {
      throw const FormatException('AI schemaVersion 必须是整数');
    }
    if (rawVersion != version) {
      throw FormatException('不支持的 AI schemaVersion: $rawVersion');
    }
    return _normalizeV2(input);
  }

  static Map<String, dynamic> _normalizeV2(Map<String, dynamic> input) {
    final result = Map<String, dynamic>.from(input);

    final confidence = AiConfidence.fromJson(
      _requiredMap(result, 'confidence'),
    );
    final uncertainties = _requiredObjectList(result, 'uncertainties')
        .map(AiUncertainty.fromJson)
        .toList(growable: false);
    final evidence = _requiredObjectList(result, 'evidence')
        .map(AiEvidence.fromJson)
        .toList(growable: false);
    final reviewPlan = AiReviewPlan.fromJson(
      _requiredMap(result, 'reviewPlan'),
    );
    final specializedRaw = result['specializedAnalysis'];
    if (specializedRaw != null && specializedRaw is! Map) {
      throw const FormatException('AI specializedAnalysis 必须是对象或 null');
    }
    final specializedAnalysis = specializedRaw is Map
        ? SpecializedAnalysis.fromJson(
            Map<String, dynamic>.from(specializedRaw),
          )
        : null;

    final subject = _requiredString(result, 'subject');
    final originalQuestion = _requiredString(result, 'originalQuestion');
    final normalizedQuestion = _requiredString(result, 'normalizedQuestion');
    final studentAnswer = _requiredString(result, 'studentAnswer', allowEmpty: true);
    final standardAnswer = _requiredString(result, 'standardAnswer');
    final solutionSteps = _requiredStringList(result, 'solutionSteps');
    final knowledgePoints = _requiredStringList(result, 'knowledgePoints');
    final generatedExercises = _requiredObjectList(result, 'generatedExercises');
    final modelName = _requiredString(result, 'modelName');
    final promptVersion = _requiredString(result, 'promptVersion');
    final mistakeReason = _requiredString(result, 'mistakeReason', allowEmpty: true);
    final studyAdvice = _requiredString(result, 'studyAdvice', allowEmpty: true);
    final aiTags = _requiredStringList(result, 'aiTags');
    final mistakeCategory = parseAiMistakeCategory(result['mistakeCategory']);

    if (solutionSteps.isEmpty) {
      throw const FormatException('AI solutionSteps 不得为空');
    }
    if (knowledgePoints.isEmpty) {
      throw const FormatException('AI knowledgePoints 不得为空');
    }

    const confidenceFields = <String>{
      'normalizedQuestion',
      'studentAnswer',
      'standardAnswer',
      'solutionSteps',
      'knowledgePoints',
      'generatedExercises',
    };
    final missingConfidence = confidenceFields.difference(confidence.fields.keys.toSet());
    if (missingConfidence.isNotEmpty) {
      throw FormatException(
        'AI confidence.fields 缺少字段: ${missingConfidence.join(', ')}',
      );
    }

    if (studentAnswer.trim().isEmpty) {
      if (mistakeCategory != null || mistakeReason.trim().isNotEmpty) {
        throw const FormatException('缺少 studentAnswer 时不得给出确定性错因');
      }
    } else if (mistakeCategory != null || mistakeReason.trim().isNotEmpty) {
      final hasMistakeEvidence = evidence.any(
        (item) =>
            item.field == 'mistakeReason' &&
            item.source == AiEvidenceSource.studentAnswer,
      );
      if (!hasMistakeEvidence) {
        throw const FormatException('AI 错因分析必须引用 studentAnswer 证据');
      }
    }

    for (var index = 0; index < generatedExercises.length; index++) {
      _validateGeneratedExercise(generatedExercises[index], index);
    }

    result
      ..['schemaVersion'] = version
      ..['confidence'] = confidence.toJson()
      ..['uncertainties'] =
          uncertainties.map((item) => item.toJson()).toList(growable: false)
      ..['evidence'] = evidence.map((item) => item.toJson()).toList(growable: false)
      ..['mistakeCategory'] = mistakeCategory?.name
      ..['reviewPlan'] = reviewPlan.toJson()
      // Compatibility aliases consumed by the current presentation/domain path.
      ..['finalAnswer'] = standardAnswer
      ..['steps'] = solutionSteps
      ..['reconstructedQuestionText'] = normalizedQuestion
      ..['subject'] = subject
      ..['originalQuestion'] = originalQuestion
      ..['normalizedQuestion'] = normalizedQuestion
      ..['studentAnswer'] = studentAnswer
      ..['standardAnswer'] = standardAnswer
      ..['solutionSteps'] = solutionSteps
      ..['knowledgePoints'] = knowledgePoints
      ..['generatedExercises'] = generatedExercises
      ..['modelName'] = modelName
      ..['promptVersion'] = promptVersion
      ..['mistakeReason'] = mistakeReason
      ..['studyAdvice'] = studyAdvice
      ..['aiTags'] = aiTags
      ..['specializedAnalysis'] = specializedAnalysis?.toJson()
      ..['isLegacyContract'] = false;
    return result;
  }

  static Map<String, dynamic> _normalizeLegacyV1(Map<String, dynamic> input) {
    const textKeys = <String>[
      'subject',
      'finalAnswer',
      'finalAnswerDerivation',
      'reconstructedQuestionText',
      'mistakeReason',
      'studyAdvice',
    ];
    const listKeys = <String>[
      'steps',
      'aiTags',
      'knowledgePoints',
    ];

    final result = Map<String, dynamic>.from(input);
    for (final key in textKeys) {
      final value = result[key];
      if (value == null) {
        result[key] = '';
      } else if (value is! String) {
        throw FormatException('AI 响应字段 $key 必须是文本');
      }
    }
    for (final key in listKeys) {
      final value = result[key];
      if (value == null) {
        result[key] = <String>[];
      } else if (value is List && value.every((item) => item is String)) {
        result[key] = List<String>.from(value);
      } else {
        throw FormatException('AI 响应字段 $key 必须是文本数组');
      }
    }

    final rawExercises = result['generatedExercises'];
    if (rawExercises == null) {
      result['generatedExercises'] = <Map<String, dynamic>>[];
    } else if (rawExercises is! List) {
      throw const FormatException('AI 响应字段 generatedExercises 必须是数组');
    }

    final hasUsableContent = textKeys.any(
          (key) => (result[key] as String).trim().isNotEmpty,
        ) ||
        listKeys.any((key) => (result[key] as List).isNotEmpty);
    if (!hasUsableContent) {
      throw const FormatException('AI 响应不包含可用分析内容');
    }

    final finalAnswer = result['finalAnswer'] as String;
    final steps = List<String>.from(result['steps'] as List);
    final reconstructed = result['reconstructedQuestionText'] as String;
    result
      ..['schemaVersion'] = 1
      ..['confidence'] = null
      ..['uncertainties'] = <Map<String, dynamic>>[]
      ..['evidence'] = <Map<String, dynamic>>[]
      ..['mistakeCategory'] = null
      ..['originalQuestion'] = ''
      ..['normalizedQuestion'] = reconstructed
      ..['studentAnswer'] = ''
      ..['standardAnswer'] = finalAnswer
      ..['solutionSteps'] = steps
      ..['modelName'] = ''
      ..['promptVersion'] = 'legacy-v1'
      ..['reviewPlan'] = null
      ..['specializedAnalysis'] = null
      ..['isLegacyContract'] = true;
    return result;
  }

  static void _validateGeneratedExercise(
    Map<String, dynamic> exercise,
    int index,
  ) {
    for (final key in <String>['id', 'difficulty', 'question', 'answer', 'explanation']) {
      final value = exercise[key];
      if (value is! String || value.trim().isEmpty) {
        throw FormatException('AI generatedExercises[$index].$key 必须是非空文本');
      }
    }
    final options = exercise['options'];
    if (options is! List ||
        options.length != 4 ||
        options.any((item) => item is! String || item.trim().isEmpty)) {
      throw FormatException('AI generatedExercises[$index].options 必须包含 4 个文本选项');
    }
  }

  static String _requiredString(
    Map<String, dynamic> json,
    String key, {
    bool allowEmpty = false,
  }) {
    if (!json.containsKey(key)) throw FormatException('AI 响应缺少字段 $key');
    final value = json[key];
    if (value is! String || !allowEmpty && value.trim().isEmpty) {
      throw FormatException('AI $key 必须是${allowEmpty ? '' : '非空'}文本');
    }
    return value;
  }

  static List<String> _requiredStringList(
    Map<String, dynamic> json,
    String key,
  ) {
    if (!json.containsKey(key)) throw FormatException('AI 响应缺少字段 $key');
    final value = json[key];
    if (value is! List || value.any((item) => item is! String)) {
      throw FormatException('AI $key 必须是文本数组');
    }
    return List<String>.from(value);
  }

  static Map<String, dynamic> _requiredMap(
    Map<String, dynamic> json,
    String key,
  ) {
    final value = json[key];
    if (value is! Map) throw FormatException('AI $key 必须是对象');
    return Map<String, dynamic>.from(value);
  }

  static List<Map<String, dynamic>> _requiredObjectList(
    Map<String, dynamic> json,
    String key,
  ) {
    final value = json[key];
    if (value is! List || value.any((item) => item is! Map)) {
      throw FormatException('AI $key 必须是对象数组');
    }
    return value
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList(growable: false);
  }
}
