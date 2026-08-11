enum AnalysisProfile {
  generic,
  algebraEquation,
  equationSystem,
  geometry,
  proofArgument,
}

extension AnalysisProfileX on AnalysisProfile {
  String get label => switch (this) {
        AnalysisProfile.generic => '通用分析',
        AnalysisProfile.algebraEquation => '方程解析',
        AnalysisProfile.equationSystem => '方程组解析',
        AnalysisProfile.geometry => '几何解析',
        AnalysisProfile.proofArgument => '证明审查',
      };

  String get shortLabel => switch (this) {
        AnalysisProfile.generic => '通用',
        AnalysisProfile.algebraEquation => '方程',
        AnalysisProfile.equationSystem => '方程组',
        AnalysisProfile.geometry => '几何',
        AnalysisProfile.proofArgument => '证明',
      };
}

class SpecializedReasoningStep {
  const SpecializedReasoningStep({
    required this.index,
    required this.statement,
    this.basis = '',
    this.dependsOn = const <int>[],
  });

  final int index;
  final String statement;
  final String basis;
  final List<int> dependsOn;

  factory SpecializedReasoningStep.fromJson(Map<String, dynamic> json) =>
      SpecializedReasoningStep(
        index: (json['index'] as num?)?.toInt() ?? 0,
        statement: json['statement'] as String? ?? '',
        basis: json['basis'] as String? ?? '',
        dependsOn: (json['dependsOn'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<num>()
            .map((value) => value.toInt())
            .toList(growable: false),
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'index': index,
        'statement': statement,
        'basis': basis,
        'dependsOn': dependsOn,
      };
}

class SpecializedAnalysis {
  const SpecializedAnalysis({
    required this.profile,
    this.givens = const <String>[],
    this.goal = '',
    this.entities = const <String>[],
    this.relations = const <String>[],
    this.constraints = const <String>[],
    this.reasoningSteps = const <SpecializedReasoningStep>[],
    this.verification = const <String>[],
    this.risks = const <String>[],
    this.isModelProvided = true,
  });

  final AnalysisProfile profile;
  final List<String> givens;
  final String goal;
  final List<String> entities;
  final List<String> relations;
  final List<String> constraints;
  final List<SpecializedReasoningStep> reasoningSteps;
  final List<String> verification;
  final List<String> risks;

  /// False means the app built a conservative view from the generic analysis.
  final bool isModelProvided;

  factory SpecializedAnalysis.fromJson(Map<String, dynamic> json) =>
      SpecializedAnalysis(
        profile: AnalysisProfile.values.firstWhere(
          (value) => value.name == json['profile'],
          orElse: () => AnalysisProfile.generic,
        ),
        givens: _strings(json['givens']),
        goal: json['goal'] as String? ?? '',
        entities: _strings(json['entities']),
        relations: _strings(json['relations']),
        constraints: _strings(json['constraints']),
        reasoningSteps: (json['reasoningSteps'] as List<dynamic>? ??
                const <dynamic>[])
            .whereType<Map>()
            .map((item) => SpecializedReasoningStep.fromJson(
                Map<String, dynamic>.from(item)))
            .toList(growable: false),
        verification: _strings(json['verification']),
        risks: _strings(json['risks']),
        isModelProvided: json['isModelProvided'] as bool? ?? true,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'profile': profile.name,
        'givens': givens,
        'goal': goal,
        'entities': entities,
        'relations': relations,
        'constraints': constraints,
        'reasoningSteps': reasoningSteps.map((step) => step.toJson()).toList(),
        'verification': verification,
        'risks': risks,
        'isModelProvided': isModelProvided,
      };

  SpecializedAnalysis copyWith({
    List<String>? verification,
    List<String>? risks,
  }) =>
      SpecializedAnalysis(
        profile: profile,
        givens: givens,
        goal: goal,
        entities: entities,
        relations: relations,
        constraints: constraints,
        reasoningSteps: reasoningSteps,
        verification: verification ?? this.verification,
        risks: risks ?? this.risks,
        isModelProvided: isModelProvided,
      );

  static List<String> _strings(Object? value) =>
      (value as List<dynamic>? ?? const <dynamic>[])
          .whereType<String>()
          .where((item) => item.trim().isNotEmpty)
          .toList(growable: false);
}

class AnalysisProfileClassifier {
  const AnalysisProfileClassifier();

  AnalysisProfile classify(String questionText) {
    final text = questionText.toLowerCase();
    final geometry = RegExp(
      r'三角形|四边形|圆|直线|线段|角|平行|垂直|全等|相似|切线|triangle|angle|circle|\\triangle|\\angle',
    ).hasMatch(text);
    if (geometry) return AnalysisProfile.geometry;

    final equationSystem = RegExp(
      r'方程组|联立|消元|begin\s*\{?cases|\\begin\{cases\}',
    ).hasMatch(text);
    if (equationSystem) return AnalysisProfile.equationSystem;

    final proof = RegExp(r'证明|求证|试证|说明.*成立|proof').hasMatch(text);
    if (proof) return AnalysisProfile.proofArgument;

    final equation = RegExp(r'解方程|方程的解|求\s*[a-z]\s*的值|[a-z]\s*[+\-*/].*=')
        .hasMatch(text);
    if (equation) return AnalysisProfile.algebraEquation;
    return AnalysisProfile.generic;
  }
}

class SpecializedAnalysisEnricher {
  const SpecializedAnalysisEnricher({
    this.classifier = const AnalysisProfileClassifier(),
  });

  final AnalysisProfileClassifier classifier;

  SpecializedAnalysis? enrich({
    required String questionText,
    required List<String> solutionSteps,
    SpecializedAnalysis? modelAnalysis,
  }) {
    final profile = classifier.classify(questionText);
    if (modelAnalysis != null && modelAnalysis.profile != AnalysisProfile.generic) {
      return _withValidation(modelAnalysis);
    }
    if (profile == AnalysisProfile.generic) return null;

    final split = RegExp(r'(求证|证明|求|解)')
        .firstMatch(questionText);
    final goal = split == null
        ? questionText.trim()
        : questionText.substring(split.start).trim();
    final given = split == null
        ? <String>[]
        : <String>[questionText.substring(0, split.start).trim()]
            .where((item) => item.isNotEmpty)
            .toList(growable: false);
    final entities = profile == AnalysisProfile.geometry
        ? _geometryEntities(questionText)
        : const <String>[];
    final relations = profile == AnalysisProfile.geometry
        ? _geometryRelations(questionText)
        : const <String>[];
    final constraints = <String>[
      if (questionText.contains('/')) '检查分母不为 0',
      if (questionText.contains('√') || questionText.contains(r'\sqrt'))
        '检查根号内非负',
    ];
    final analysis = SpecializedAnalysis(
      profile: profile,
      givens: given,
      goal: goal,
      entities: entities,
      relations: relations,
      constraints: constraints,
      reasoningSteps: <SpecializedReasoningStep>[
        for (var index = 0; index < solutionSteps.length; index++)
          SpecializedReasoningStep(
            index: index + 1,
            statement: solutionSteps[index],
          ),
      ],
      isModelProvided: false,
    );
    return _withValidation(analysis);
  }

  SpecializedAnalysis _withValidation(SpecializedAnalysis analysis) {
    final risks = <String>{...analysis.risks};
    if ((analysis.profile == AnalysisProfile.algebraEquation ||
            analysis.profile == AnalysisProfile.equationSystem) &&
        analysis.verification.isEmpty) {
      risks.add('尚未完成代回验证，请核对最终解是否满足原方程');
    }
    if (analysis.profile == AnalysisProfile.geometry &&
        analysis.entities.isEmpty) {
      risks.add('未提取到明确图形对象，请结合原图核对点、线和角');
    }
    if (analysis.profile == AnalysisProfile.proofArgument &&
        analysis.reasoningSteps.any((step) => step.basis.trim().isEmpty)) {
      risks.add('部分证明步骤缺少明确依据');
    }
    return analysis.copyWith(risks: risks.toList(growable: false));
  }

  List<String> _geometryEntities(String text) {
    final entities = <String>{};
    for (final match in RegExp(r'\b[A-Z]{1,3}\b').allMatches(text)) {
      entities.add(match.group(0)!);
    }
    for (final keyword in <String>['三角形', '圆', '直线', '线段', '角']) {
      if (text.contains(keyword)) entities.add(keyword);
    }
    return entities.toList(growable: false);
  }

  List<String> _geometryRelations(String text) {
    final result = <String>[];
    for (final relation in <String>['平行', '垂直', '全等', '相似', '相切', '相等']) {
      if (text.contains(relation)) result.add(relation);
    }
    return result;
  }
}
