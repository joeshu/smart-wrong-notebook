import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_wrong_notebook/src/data/remote/ai/ai_analysis_service.dart';
import 'package:smart_wrong_notebook/src/data/repositories/settings_repository.dart';
import 'package:smart_wrong_notebook/src/domain/models/ai_provider_config.dart';
import 'package:smart_wrong_notebook/src/domain/models/analysis_result.dart';
import 'package:smart_wrong_notebook/src/domain/models/generated_exercise.dart';

void main() {
  group('fixture regression config', () {
    test('builds single fixture case from environment', () {
      final cases = _fixtureCasesFromEnvironment(<String, String>{
        'AI_FIXTURE_IMAGE': '/tmp/example.png',
        'AI_FIXTURE_SUBJECT': 'math',
        'AI_FIXTURE_TEXT': '请识别这道数学题。',
      });

      expect(cases, hasLength(1));
      expect(cases.single.id, 'example');
      expect(cases.single.imagePath, '/tmp/example.png');
      expect(cases.single.subject, 'math');
      expect(cases.single.prompt, '请识别这道数学题。');
    });

    test('builds default local batch fixture cases', () {
      final cases = _fixtureCasesFromEnvironment(
        const <String, String>{'AI_FIXTURE_SET': 'local'},
        fixtureRoot: 'test/fixtures',
      );

      expect(cases.map((fixture) => fixture.id), contains('semicircle'));
      expect(cases.map((fixture) => fixture.id), contains('shuxue-jihe'));
      expect(cases.map((fixture) => fixture.id), contains('duoti'));
      expect(cases.map((fixture) => fixture.id), contains('wuli-dianzu'));
      expect(cases.map((fixture) => fixture.id), contains('yuwen'));
      expect(cases.map((fixture) => fixture.id), contains('yingyu'));
      expect(
        cases.singleWhere((fixture) => fixture.id == 'wuli-dianzu').subject,
        'physics',
      );
    });

    test('builds explicit json batch fixture cases', () {
      final cases = _fixtureCasesFromEnvironment(<String, String>{
        'AI_FIXTURE_CASES': jsonEncode(<Map<String, String>>[
          <String, String>{
            'id': 'case-a',
            'image': '/tmp/a.png',
            'subject': 'math',
            'text': '题目 A',
          },
          <String, String>{
            'image': '/tmp/b.png',
            'subject': 'english',
            'text': '题目 B',
          },
        ]),
      });

      expect(cases, hasLength(2));
      expect(cases.first.id, 'case-a');
      expect(cases.last.id, 'b');
      expect(cases.last.subject, 'english');
      expect(cases.last.prompt, '题目 B');
    });
  });

  test('analyzes a local image fixture with app AI service', () async {
    final fixtureCases = _fixtureCasesFromEnvironment(Platform.environment);
    if (fixtureCases.isEmpty) {
      markTestSkipped(
        'Set AI_FIXTURE_IMAGE, AI_FIXTURE_CASES, or AI_FIXTURE_SET=local '
        'to run local image regression.',
      );
      return;
    }

    final config = _readConfigFromEnvironment();
    final service = AiAnalysisService(
      settingsRepository: _ToolSettingsRepository(config),
    );

    final reports = <Map<String, dynamic>>[];
    for (final fixture in fixtureCases) {
      final imageFile = File(fixture.imagePath);
      expect(
        imageFile.existsSync(),
        isTrue,
        reason: 'Image file must exist for fixture ${fixture.id}.',
      );

      // ignore: avoid_print
      print('\n[TEST] fixture: ${fixture.id}');

      final result = await service.analyzeExtractedQuestion(
        correctedText: fixture.prompt,
        subjectName: fixture.subject,
        imagePath: imageFile.path,
      );
      // ignore: avoid_print
      print(
          '[TEST] result type: ${result.runtimeType}, isParsed: ${result is ParsedAnalysisResult}');
      final generatedExercises = result is ParsedAnalysisResult
          ? service.extractGeneratedExercisesFromContent(
              result.rawContent,
              questionId: fixture.id,
              analysis: result,
              sourceQuestionText: fixture.prompt,
            )
          : service.extractGeneratedExercises(
              result,
              questionId: fixture.id,
              sourceQuestionText: fixture.prompt,
            );
      // ignore: avoid_print
      print('[TEST] generatedExercises count: ${generatedExercises.length}');
      for (final ex in generatedExercises) {
        // ignore: avoid_print
        print(
            '[TEST] exercise: ${ex.id}, hasDiagram: ${ex.diagramData != null}, q: ${ex.question.substring(0, ex.question.length.clamp(0, 40))}');
      }

      final report = _buildReport(result, generatedExercises)
        ..['fixture'] = fixture.toJson();
      reports.add(report);

      const encoder = JsonEncoder.withIndent('  ');
      // ignore: avoid_print
      print(encoder.convert(report));

      final qualityGate = report['qualityGate']! as Map<String, dynamic>;
      final warnings = qualityGate['warnings'] as List;
      if (warnings.isNotEmpty) {
        // ignore: avoid_print
        print('\n⚠️  WARNINGS (needs manual review, not a test failure):');
        for (final w in warnings) {
          // ignore: avoid_print
          print('  - $w');
        }
      }

      expect(
        qualityGate['passed'],
        isTrue,
        reason:
            'Fixture ${fixture.id}: ${(qualityGate['issues'] as List).join('\n')}',
      );
    }

    // ignore: avoid_print
    print(
        '\n[TEST] fixture summary: ${reports.length} fixture(s) passed gate.');
  }, timeout: const Timeout(Duration(minutes: 5)));
}

class _FixtureCase {
  const _FixtureCase({
    required this.id,
    required this.imagePath,
    required this.subject,
    required this.prompt,
  });

  final String id;
  final String imagePath;
  final String subject;
  final String prompt;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'imagePath': imagePath,
        'subject': subject,
        'prompt': prompt,
      };
}

List<_FixtureCase> _fixtureCasesFromEnvironment(
  Map<String, String> environment, {
  String fixtureRoot = 'test/fixtures',
}) {
  final rawCases = environment['AI_FIXTURE_CASES']?.trim();
  if (rawCases != null && rawCases.isNotEmpty) {
    final decoded = jsonDecode(rawCases);
    if (decoded is! List) {
      fail('AI_FIXTURE_CASES must be a JSON array.');
    }
    return decoded
        .whereType<Map>()
        .map((item) => _fixtureCaseFromMap(Map<String, dynamic>.from(item)))
        .toList();
  }

  final imagePath = environment['AI_FIXTURE_IMAGE']?.trim();
  if (imagePath != null && imagePath.isNotEmpty) {
    return <_FixtureCase>[
      _FixtureCase(
        id: _fixtureIdFromPath(imagePath),
        imagePath: imagePath,
        subject: environment['AI_FIXTURE_SUBJECT']?.trim().isNotEmpty == true
            ? environment['AI_FIXTURE_SUBJECT']!.trim()
            : 'math',
        prompt: environment['AI_FIXTURE_TEXT']?.trim().isNotEmpty == true
            ? environment['AI_FIXTURE_TEXT']!.trim()
            : '请根据图片识别题目并解答。',
      ),
    ];
  }

  if (environment['AI_FIXTURE_SET']?.trim().toLowerCase() == 'local') {
    return _defaultLocalFixtureCases(fixtureRoot);
  }

  return const <_FixtureCase>[];
}

_FixtureCase _fixtureCaseFromMap(Map<String, dynamic> item) {
  final image = (item['image'] ?? item['imagePath'])?.toString().trim() ?? '';
  if (image.isEmpty) fail('Each AI_FIXTURE_CASES item must include image.');
  final text = (item['text'] ?? item['prompt'])?.toString().trim() ?? '';
  return _FixtureCase(
    id: item['id']?.toString().trim().isNotEmpty == true
        ? item['id'].toString().trim()
        : _fixtureIdFromPath(image),
    imagePath: image,
    subject: item['subject']?.toString().trim().isNotEmpty == true
        ? item['subject'].toString().trim()
        : 'math',
    prompt: text.isNotEmpty ? text : '请根据图片识别题目并解答。',
  );
}

List<_FixtureCase> _defaultLocalFixtureCases(String fixtureRoot) {
  String path(String name) => '$fixtureRoot/$name';
  return <_FixtureCase>[
    _FixtureCase(
      id: 'semicircle',
      imagePath: path('semicircle.png'),
      subject: 'math',
      prompt: '图中标注上边为3、底边为7、右边高为10，图内为半圆，求图中括号所示区域面积。',
    ),
    _FixtureCase(
      id: 'shuxue-jihe',
      imagePath: path('shuxue-jihe.png'),
      subject: 'math',
      prompt:
          '请识别图片中的数学几何题，整理完整题干；若需要读图推断，请标出不确定项，并生成同题型举一反三练习，图形题练习应包含 diagramData。',
    ),
    _FixtureCase(
      id: 'duoti',
      imagePath: path('duoti.png'),
      subject: 'math',
      prompt: '请识别图片中的所有题目，按题号分别整理题干并分析；如果图片包含多道题，请不要只分析其中一道。',
    ),
    _FixtureCase(
      id: 'wuli-dianzu',
      imagePath: path('wuli-dianzu.png'),
      subject: 'physics',
      prompt: '请识别图片中的物理电学题，整理题干并分析电阻/电路关系，给出最终答案和举一反三练习。',
    ),
    _FixtureCase(
      id: 'yuwen',
      imagePath: path('yuwen.png'),
      subject: 'chinese',
      prompt: '请识别图片中的语文题，整理完整题干并分析作答思路，生成同题型举一反三练习。',
    ),
    _FixtureCase(
      id: 'yingyu',
      imagePath: path('yingyu.png'),
      subject: 'english',
      prompt: '请识别图片中的英语题，整理完整题干并分析作答思路，生成同题型举一反三练习。',
    ),
  ];
}

String _fixtureIdFromPath(String imagePath) {
  final normalized = imagePath.replaceAll('\\', '/');
  final filename = normalized.split('/').last;
  final dot = filename.lastIndexOf('.');
  return dot > 0 ? filename.substring(0, dot) : filename;
}

AiProviderConfig _readConfigFromEnvironment() {
  final baseUrl = _env('AI_BASE_URL');
  final apiKey = _env('AI_API_KEY');
  final model = _env('AI_MODEL');

  final missing = <String>[
    if (baseUrl == null || baseUrl.trim().isEmpty) 'AI_BASE_URL',
    if (apiKey == null || apiKey.trim().isEmpty) 'AI_API_KEY',
    if (model == null || model.trim().isEmpty) 'AI_MODEL',
  ];
  if (missing.isNotEmpty) {
    fail('Missing environment variables: ${missing.join(', ')}.');
  }

  return AiProviderConfig(
    id: 'tool-env',
    displayName: 'Tool Environment',
    baseUrl: baseUrl!.trim(),
    model: model!.trim(),
    apiKey: apiKey!.trim(),
  );
}

Map<String, dynamic> _buildReport(
  AnalysisResult result,
  List<GeneratedExercise> generatedExercises,
) {
  return <String, dynamic>{
    'finalAnswer': result.finalAnswer,
    'finalAnswerDerivation': result.finalAnswerDerivation,
    'steps': result.steps,
    'visualAssumptions': result.visualAssumptions?.toJson(),
    'visualAssumptionStatus': result.visualAssumptionStatus.name,
    'consistencyStatus': result.consistencyStatus.name,
    'consistencyNote': result.consistencyNote,
    'wasVerifierUsed': result.wasVerifierUsed,
    'generatedExercises': generatedExercises
        .map((exercise) => <String, dynamic>{
              'id': exercise.id,
              'difficulty': exercise.difficulty,
              'question': exercise.question,
              'options': exercise.options,
              'answer': exercise.answer,
              'explanation': exercise.explanation,
            })
        .toList(),
    'qualityGate': _evaluateQualityGate(result, generatedExercises),
  };
}

Map<String, dynamic> _evaluateQualityGate(
  AnalysisResult result,
  List<GeneratedExercise> generatedExercises,
) {
  final issues = <String>[];
  final warnings = <String>[];
  final finalAnswerTokens = _extractConclusionTokens(result.finalAnswer);
  final derivationTokens =
      _extractConclusionTokens(result.finalAnswerDerivation);
  final stepTokens = <String>{
    for (final step in result.steps.reversed.take(2))
      ..._extractConclusionTokens(step),
  };

  if (result.finalAnswer.trim().isEmpty) {
    issues.add('finalAnswer is empty');
  }
  if (result.steps.isEmpty) {
    issues.add('steps is empty');
  }

  final hasAnswerStepConflict = finalAnswerTokens.isNotEmpty &&
      stepTokens.isNotEmpty &&
      finalAnswerTokens.intersection(stepTokens).isEmpty;
  if (hasAnswerStepConflict) {
    issues.add(
      'finalAnswer conflicts with final steps: '
      '${finalAnswerTokens.join(', ')} vs ${stepTokens.join(', ')}',
    );
  }

  final hasAnswerDerivationConflict = finalAnswerTokens.isNotEmpty &&
      derivationTokens.isNotEmpty &&
      finalAnswerTokens.intersection(derivationTokens).isEmpty;
  if (hasAnswerDerivationConflict) {
    issues.add(
      'finalAnswer conflicts with finalAnswerDerivation: '
      '${finalAnswerTokens.join(', ')} vs ${derivationTokens.join(', ')}',
    );
  }

  final answerFamily = <String>{
    ...finalAnswerTokens,
    ...derivationTokens,
    ...stepTokens,
  }.where(_isHighRiskPiAreaAnswer).toSet();
  if (answerFamily.length > 1) {
    issues.add(
      'multiple high-risk area answers appear: ${answerFamily.join(', ')}',
    );
  }

  if (result.visualAssumptionStatus == VisualAssumptionStatus.needsReview &&
      result.consistencyStatus != AnalysisConsistencyStatus.needsReview) {
    issues.add(
        'visual assumptions need review but consistencyStatus is not needsReview');
  }

  // needsReview with internally consistent results is a warning, not a failure.
  // The App will correctly show "可能解法/需核对" — this is the desired behavior
  // for image-based geometry problems where label interpretation is uncertain.
  if (result.consistencyStatus == AnalysisConsistencyStatus.needsReview) {
    final isInternallyConsistent =
        !hasAnswerStepConflict && !hasAnswerDerivationConflict;
    if (isInternallyConsistent) {
      warnings.add(
          'analysis needs manual review (App will show 可能解法): ${result.consistencyNote}');
    } else {
      issues.add(
          'analysis requires manual review with internal conflicts: ${result.consistencyNote}');
    }
  }

  for (final exercise in generatedExercises) {
    if (_hasGeneratedExerciseSelfInvalidation(exercise)) {
      issues.add('generated exercise self-invalidates: ${exercise.id}');
    }
  }

  return <String, dynamic>{
    'passed': issues.isEmpty,
    'issues': issues,
    'warnings': warnings,
    'finalAnswerTokens': finalAnswerTokens.toList(),
    'derivationTokens': derivationTokens.toList(),
    'stepConclusionTokens': stepTokens.toList(),
  };
}

Set<String> _extractConclusionTokens(String text) {
  final normalized = text
      .replaceAll('\\(', ' ')
      .replaceAll('\\)', ' ')
      .replaceAll('\\[', ' ')
      .replaceAll('\\]', ' ')
      .replaceAll('π', r'\pi')
      .replaceAll(' ', '')
      .toLowerCase();
  final tokens = <String>{};

  for (final match in RegExp(r'[a-z][\.、:]?').allMatches(normalized)) {
    final token = match.group(0)!.replaceAll(RegExp(r'[\.、:]'), '');
    if (token.length == 1) tokens.add(token.toUpperCase());
  }

  for (final match
      in RegExp(r'\\frac\{([^{}]+)\}\{([^{}]+)\}').allMatches(normalized)) {
    tokens.add('${match.group(1)!}/${match.group(2)!}');
  }

  for (final match in RegExp(
    r'\d+(?:\.\d+)?(?:\\pi|pi)?(?:/\d+(?:\.\d+)?)?|(?:\\pi|pi)(?:/\d+(?:\.\d+)?)?',
  ).allMatches(normalized)) {
    final token = match.group(0)!;
    if (RegExp(r'\d|\\pi|pi').hasMatch(token)) {
      tokens.add(token.replaceAll('pi', r'\pi'));
    }
  }

  return tokens.where((token) => token.isNotEmpty).toSet();
}

bool _hasGeneratedExerciseSelfInvalidation(GeneratedExercise exercise) {
  final text =
      '${exercise.question} ${exercise.explanation} ${exercise.options?.join(' ') ?? ''}';
  return <String>[
    '选项中没有',
    '没有该值',
    '无正确选项',
    '选项设计不严谨',
    '选项有误',
    '原选项设计',
    '需重新检查',
    '需要重新检查',
    '修正后应',
    '应为修正',
    '无法从选项',
    '题目不严谨',
    '本题无解',
  ].any(text.contains);
}

bool _isHighRiskPiAreaAnswer(String token) {
  final normalized = token.replaceAll(' ', '').replaceAll('pi', r'\pi');
  return normalized == r'25\pi' ||
      normalized == r'25\pi/2' ||
      normalized == r'29\pi/2' ||
      normalized == r'25\pi}{2' ||
      normalized == r'29\pi}{2';
}

String? _env(String key) => Platform.environment[key];

class _ToolSettingsRepository implements SettingsRepository {
  _ToolSettingsRepository(this._config);

  AiProviderConfig _config;
  final Map<String, String> _strings = <String, String>{};

  @override
  Future<AiProviderConfig?> getAiProviderConfig() async => _config;

  @override
  Future<void> saveAiProviderConfig(AiProviderConfig config) async {
    _config = config;
  }

  @override
  Future<String?> getString(String key) async => _strings[key];

  @override
  Future<void> setString(String key, String value) async {
    _strings[key] = value;
  }

  @override
  Future<bool> isQuickCaptureEnabled() async {
    final value = await getString('quick_capture_enabled');
    return value == 'true';
  }

  @override
  Future<void> setQuickCaptureEnabled(bool enabled) async {
    await setString('quick_capture_enabled', enabled ? 'true' : 'false');
  }
}
