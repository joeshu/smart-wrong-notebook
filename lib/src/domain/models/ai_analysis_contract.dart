import 'mistake_category.dart';

/// Current structured AI analysis schema.
abstract final class AiAnalysisSchema {
  static const int currentVersion = 2;
  static const String currentPromptVersion = 'analysis-v2.0.0';
}

/// Overall and field-level confidence scores in the inclusive range 0...1.
class AiConfidence {
  const AiConfidence({
    required this.overall,
    this.fields = const <String, double>{},
  });

  final double overall;
  final Map<String, double> fields;

  List<String> fieldsBelow(double threshold) => fields.entries
      .where((entry) => entry.value < threshold)
      .map((entry) => entry.key)
      .toList(growable: false);

  Map<String, dynamic> toJson() => <String, dynamic>{
        'overall': overall,
        'fields': fields,
      };

  factory AiConfidence.fromJson(Map<String, dynamic> json) {
    final rawOverall = json['overall'];
    if (rawOverall is! num) {
      throw const FormatException('AI confidence.overall 必须是数字');
    }
    final overall = rawOverall.toDouble();
    _validateScore(overall, 'confidence.overall');

    final rawFields = json['fields'];
    if (rawFields is! Map) {
      throw const FormatException('AI confidence.fields 必须是对象');
    }
    final fields = <String, double>{};
    for (final entry in rawFields.entries) {
      if (entry.key is! String || entry.value is! num) {
        throw const FormatException('AI confidence.fields 必须是字段名到数字的映射');
      }
      final score = (entry.value as num).toDouble();
      _validateScore(score, 'confidence.fields.${entry.key}');
      fields[entry.key as String] = score;
    }
    return AiConfidence(overall: overall, fields: fields);
  }

  static void _validateScore(double score, String field) {
    if (!score.isFinite || score < 0 || score > 1) {
      throw FormatException('AI $field 必须在 0 到 1 之间');
    }
  }
}

class AiUncertainty {
  const AiUncertainty({
    required this.field,
    required this.description,
    this.suggestedAction = '',
  });

  final String field;
  final String description;
  final String suggestedAction;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'field': field,
        'description': description,
        'suggestedAction': suggestedAction,
      };

  factory AiUncertainty.fromJson(Map<String, dynamic> json) => AiUncertainty(
        field: _requiredString(json, 'field', owner: 'uncertainties'),
        description:
            _requiredString(json, 'description', owner: 'uncertainties'),
        suggestedAction: _optionalString(json, 'suggestedAction'),
      );
}

enum AiEvidenceSource {
  image,
  originalQuestion,
  normalizedQuestion,
  studentAnswer,
  solutionStep,
  modelInference,
}

class AiEvidence {
  const AiEvidence({
    required this.field,
    required this.source,
    required this.quote,
    required this.explanation,
    this.stepIndex,
  });

  final String field;
  final AiEvidenceSource source;
  final String quote;
  final String explanation;
  final int? stepIndex;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'field': field,
        'source': source.name,
        'quote': quote,
        'explanation': explanation,
        if (stepIndex != null) 'stepIndex': stepIndex,
      };

  factory AiEvidence.fromJson(Map<String, dynamic> json) {
    final sourceName = _requiredString(json, 'source', owner: 'evidence');
    AiEvidenceSource? source;
    for (final candidate in AiEvidenceSource.values) {
      if (candidate.name == sourceName) {
        source = candidate;
        break;
      }
    }
    if (source == null) {
      throw FormatException('AI evidence.source 不支持: $sourceName');
    }
    final rawStepIndex = json['stepIndex'];
    if (rawStepIndex != null && rawStepIndex is! int) {
      throw const FormatException('AI evidence.stepIndex 必须是整数');
    }
    return AiEvidence(
      field: _requiredString(json, 'field', owner: 'evidence'),
      source: source,
      quote: _requiredString(json, 'quote', owner: 'evidence'),
      explanation: _requiredString(json, 'explanation', owner: 'evidence'),
      stepIndex: rawStepIndex as int?,
    );
  }
}

class AiReviewPlan {
  const AiReviewPlan({
    required this.reviewAfterDays,
    required this.focus,
    required this.reason,
  });

  final int reviewAfterDays;
  final List<String> focus;
  final String reason;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'reviewAfterDays': reviewAfterDays,
        'focus': focus,
        'reason': reason,
      };

  factory AiReviewPlan.fromJson(Map<String, dynamic> json) {
    final days = json['reviewAfterDays'];
    if (days is! int || days < 0) {
      throw const FormatException('AI reviewPlan.reviewAfterDays 必须是非负整数');
    }
    return AiReviewPlan(
      reviewAfterDays: days,
      focus: _requiredStringList(json, 'focus', owner: 'reviewPlan'),
      reason: _requiredString(json, 'reason', owner: 'reviewPlan'),
    );
  }
}

MistakeCategory? parseAiMistakeCategory(Object? value) {
  if (value == null || value == '') return null;
  if (value is! String) {
    throw const FormatException('AI mistakeCategory 必须是文本或 null');
  }
  for (final category in MistakeCategory.values) {
    if (category.name == value) return category;
  }
  throw FormatException('AI mistakeCategory 不支持: $value');
}

String _requiredString(
  Map<String, dynamic> json,
  String key, {
  required String owner,
}) {
  final value = json[key];
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('AI $owner.$key 必须是非空文本');
  }
  return value;
}

String _optionalString(Map<String, dynamic> json, String key) {
  final value = json[key];
  if (value == null) return '';
  if (value is! String) throw FormatException('AI $key 必须是文本');
  return value;
}

List<String> _requiredStringList(
  Map<String, dynamic> json,
  String key, {
  required String owner,
}) {
  final value = json[key];
  if (value is! List || value.any((item) => item is! String)) {
    throw FormatException('AI $owner.$key 必须是文本数组');
  }
  return List<String>.from(value);
}
