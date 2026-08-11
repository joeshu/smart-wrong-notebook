import 'package:flutter_test/flutter_test.dart';
import 'package:smart_wrong_notebook/src/data/remote/ai/ai_analysis_service.dart';
import 'package:smart_wrong_notebook/src/data/repositories/settings_repository.dart';
import 'package:smart_wrong_notebook/src/domain/models/ai_analysis_patch.dart';
import 'package:smart_wrong_notebook/src/domain/models/ai_response_diagnostics.dart';
import 'package:smart_wrong_notebook/src/domain/models/ai_analysis_payload.dart';
import 'package:smart_wrong_notebook/src/domain/models/analysis_result.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';
import 'package:smart_wrong_notebook/src/features/analysis/presentation/analysis_controller.dart';

class _Vector {
  const _Vector(this.x, this.y);

  final double x;
  final double y;
}

Map<String, _Vector> _diagramLabels(Map<String, dynamic> diagramData) {
  final labels = <String, _Vector>{};
  final elements = diagramData['elements'] as List;
  for (final element in elements.whereType<Map>()) {
    if (element['type'] == 'polygon') {
      final points = element['points'] as List;
      final rawLabels = element['labels'] as List? ?? const [];
      for (var i = 0; i < points.length && i < rawLabels.length; i++) {
        final point = points[i] as List;
        final label = rawLabels[i] as Map;
        labels[label['text'] as String] = _Vector(
          (point[0] as num).toDouble(),
          (point[1] as num).toDouble(),
        );
      }
    } else if (element['type'] == 'point') {
      labels[element['label'] as String] = _Vector(
        (element['x'] as num).toDouble(),
        (element['y'] as num).toDouble(),
      );
    }
  }
  return labels;
}

void main() {
  test(
      'fake analysis controller returns ready record with persistent exercises',
      () async {
    final controller = AnalysisController.fake();
    final record = await controller.analyze(
      questionId: 'q-1',
      correctedText: '解方程 x+2=5',
      subjectName: '数学',
    );

    expect(record.analysisResult?.finalAnswer, 'x = 3');
    expect(record.savedExercises.length, 3);
    expect(record.savedExercises.first.difficulty, '简单');
  });

  test('field retry rejects legacy analysis instead of fabricating V2 trust',
      () async {
    final service = AiAnalysisService.fake();
    const legacy = AnalysisResult(
      finalAnswer: '3',
      steps: <String>['移项'],
      aiTags: <String>[],
      knowledgePoints: <String>['方程'],
      mistakeReason: '',
      studyAdvice: '',
    );

    await expectLater(
      service.retryAnalysisFields(
        current: legacy,
        fields: const <AiAnalysisField>{AiAnalysisField.standardAnswer},
        confirmedQuestion: '解方程 x+1=4',
        subjectName: '数学',
      ),
      throwsA(isA<AiAnalysisException>()),
    );
  });

  test('diagnostics retention strips raw response by default', () async {
    final settings = InMemorySettingsRepository();
    final service = AiAnalysisService(settingsRepository: settings);
    final result = await service.applyResponseDiagnosticsRetentionForTest(
      ParsedAnalysisResult(
        rawContent: '{"secret":"student work"}',
        finalAnswer: '3',
        steps: const <String>['移项'],
        aiTags: const <String>['方程'],
        knowledgePoints: const <String>['一元一次方程'],
        mistakeReason: '',
        studyAdvice: '练习移项',
        responseDiagnostics: AiResponseDiagnostics(
          contentLength: 24,
          contentFingerprint: 'abc123def456',
          markdownWrapped: false,
          repairStrategy: 'none',
          capturedAt: DateTime.utc(2026, 7, 25),
          rawResponse: '{"secret":"student work"}',
          retentionDays: 7,
        ),
      ),
    );

    expect(result.responseDiagnostics?.hasRawResponse, isFalse);
    expect(result.responseDiagnostics?.contentFingerprint, 'abc123def456');
  });

  test('diagnostics retention stores raw response only when enabled', () async {
    final settings = InMemorySettingsRepository();
    await settings.setString(
      AiAnalysisService.diagnosticsRawResponseEnabledKey,
      'true',
    );
    await settings.setString(
      AiAnalysisService.diagnosticsRawRetentionDaysKey,
      '14',
    );
    final service = AiAnalysisService(settingsRepository: settings);
    final result = await service.applyResponseDiagnosticsRetentionForTest(
      ParsedAnalysisResult(
        rawContent: '{"raw":"model output"}',
        finalAnswer: '3',
        steps: const <String>['移项'],
        aiTags: const <String>['方程'],
        knowledgePoints: const <String>['一元一次方程'],
        mistakeReason: '',
        studyAdvice: '练习移项',
        responseDiagnostics: AiResponseDiagnostics(
          contentLength: 22,
          contentFingerprint: 'raw123456789',
          markdownWrapped: false,
          repairStrategy: 'none',
          capturedAt: DateTime.utc(2026, 7, 25),
        ),
      ),
    );

    expect(result.responseDiagnostics?.rawResponse, '{"raw":"model output"}');
    expect(result.responseDiagnostics?.retentionDays, 14);
  });

  test('service parses final answer derivation and consistency metadata', () {
    final service = AiAnalysisService.fake();
    const raw = r'''
{
  "subject": "数学",
  "finalAnswer": "25\pi/2",
  "finalAnswerDerivation": "由最后一步 \frac{1}{2}\times25\pi 得到 25\pi/2。",
  "reconstructedQuestionText": "如图，求半圆面积。",
  "steps": ["圆面积为 25\pi", "阴影面积为 25\pi/2"],
  "aiTags": ["几何"],
  "knowledgePoints": ["圆面积"],
  "mistakeReason": "漏乘二分之一",
  "studyAdvice": "注意目标区域"
}
''';

    final analysis = service.parseAnalysisResponseForTest(raw);

    expect(analysis.finalAnswer, r'25\pi/2');
    expect(analysis.finalAnswerDerivation, contains(r'\frac{1}{2}'));
    expect(analysis.reconstructedQuestionText, contains('半圆面积'));
    final restored = AnalysisResult.fromJson(
      analysis
          .copyWith(
            consistencyStatus: AnalysisConsistencyStatus.repaired,
            consistencyNote: 'AI 已复核并修正答案。',
            wasVerifierUsed: true,
          )
          .toJson(),
    );
    expect(restored.consistencyStatus, AnalysisConsistencyStatus.repaired);
    expect(restored.wasVerifierUsed, isTrue);
    expect(restored.finalAnswerDerivation, contains(r'\frac{1}{2}'));
  });

  test('service preserves strict Contract V2 metadata', () {
    final service = AiAnalysisService.fake();
    const raw = r'''
{
  "schemaVersion": 2,
  "promptVersion": "analysis-v2.0.0",
  "modelName": "fixture-model",
  "subject": "数学",
  "confidence": {
    "overall": 0.91,
    "fields": {
      "normalizedQuestion": 0.96,
      "studentAnswer": 0.75,
      "standardAnswer": 0.97,
      "solutionSteps": 0.93,
      "knowledgePoints": 0.88,
      "generatedExercises": 0.8
    }
  },
  "uncertainties": [],
  "evidence": [],
  "mistakeCategory": null,
  "originalQuestion": "x+1=4，求x",
  "normalizedQuestion": "解方程 x+1=4",
  "studentAnswer": "",
  "standardAnswer": "3",
  "solutionSteps": ["移项得 x=3"],
  "knowledgePoints": ["一元一次方程"],
  "generatedExercises": [],
  "mistakeReason": "",
  "studyAdvice": "完成后检查移项符号",
  "aiTags": ["方程"],
  "reviewPlan": {
    "reviewAfterDays": 3,
    "focus": ["移项符号"],
    "reason": "巩固基础规则"
  }
}
''';

    final analysis = service.parseAnalysisResponseForTest(raw);

    expect(analysis.hasContractV2, isTrue);
    expect(analysis.schemaVersion, 2);
    expect(analysis.promptVersion, 'analysis-v2.0.0');
    expect(analysis.modelName, 'fixture-model');
    expect(analysis.confidence?.overall, 0.91);
    expect(analysis.standardAnswer, '3');
    expect(analysis.finalAnswer, '3');
    expect(analysis.solutionSteps, ['移项得 x=3']);
    expect(analysis.reviewPlan?.reviewAfterDays, 3);
    expect(analysis.responseDiagnostics?.contentLength, raw.length);
    expect(analysis.responseDiagnostics?.contentFingerprint, isNotEmpty);
    expect(analysis.responseDiagnostics?.repairStrategy, 'none');
    expect(analysis.responseDiagnostics?.hasRawResponse, isFalse);
  });

  test('service rejects Markdown-wrapped Contract V2 response', () {
    final service = AiAnalysisService.fake();
    const wrapped = '''```json
{"schemaVersion":2}
```''';

    expect(
      () => service.parseAnalysisResponseForTest(wrapped),
      throwsA(anything),
    );
  });

  test('service parses visual assumptions and marks low confidence for review',
      () {
    final service = AiAnalysisService.fake();
    const raw = r'''
{
  "subject": "数学",
  "finalAnswer": "25\pi/2",
  "finalAnswerDerivation": "按半圆面积公式得到 25\pi/2。",
  "reconstructedQuestionText": "如图，求阴影半圆面积。",
  "visualAssumptions": {
    "targetObject": "阴影半圆",
    "targetQuestion": "求面积",
    "measurements": [
      {
        "label": "10",
        "meaning": "半圆直径",
        "usedInSolution": true,
        "evidence": "image",
        "confidence": "low"
      }
    ],
    "solutionBasis": ["半径为 5"],
    "uncertainItems": ["10 是否为直径"],
    "needsManualReview": true,
    "reviewReason": "需核对 10 的标注含义"
  },
  "steps": ["若 10 为直径，则半径为 5。", "面积为 25\pi/2。"],
  "aiTags": ["几何"],
  "knowledgePoints": ["半圆面积"],
  "mistakeReason": "未核对标注含义",
  "studyAdvice": "先确认图中关键长度"
}
''';

    final analysis = service.parseAnalysisResponseForTest(raw);
    final restored = AnalysisResult.fromJson(analysis.toJson());

    expect(restored.visualAssumptions?.targetObject, '阴影半圆');
    expect(restored.visualAssumptions?.measurements.single.label, '10');
    expect(restored.visualAssumptionStatus, VisualAssumptionStatus.needsReview);
  });

  test('service marks medium inferred solution measurement for review', () {
    final service = AiAnalysisService.fake();
    const raw = r'''
{
  "subject": "数学",
  "finalAnswer": "50-\frac{29\pi}{2}",
  "finalAnswerDerivation": "外框面积减去半圆面积。",
  "reconstructedQuestionText": "如图，求外框内、半圆外区域面积。",
  "visualAssumptions": {
    "targetObject": "外框内、半圆外区域",
    "targetQuestion": "求面积",
    "measurements": [
      {
        "label": "左斜边",
        "meaning": "半圆直径",
        "usedInSolution": true,
        "evidence": "inferred",
        "confidence": "medium"
      }
    ],
    "solutionBasis": ["半圆直径为左斜边"],
    "uncertainItems": [],
    "needsManualReview": false,
    "reviewReason": ""
  },
  "steps": ["外框面积为 50。", "半圆面积为 29\pi/2。"],
  "aiTags": ["几何"],
  "knowledgePoints": ["半圆面积"],
  "mistakeReason": "需核对读图假设",
  "studyAdvice": "确认直径位置"
}
''';

    final analysis = service.parseAnalysisResponseForTest(raw);

    expect(analysis.visualAssumptionStatus, VisualAssumptionStatus.needsReview);
  });

  test(
      'visual assumption uncertainty keeps consistent verifier result in review',
      () {
    final service = AiAnalysisService.fake();
    const analysis = AnalysisResult(
      finalAnswer: r'25\pi/2',
      finalAnswerDerivation: r'按半圆面积公式得到 25\pi/2。',
      steps: <String>[r'若 10 为直径，则半径为 5。', r'面积为 25\pi/2。'],
      aiTags: <String>['几何'],
      knowledgePoints: <String>['半圆面积'],
      mistakeReason: '图中标注含义可能不稳定。',
      studyAdvice: '先确认关键标注。',
      visualAssumptions: VisualAssumptions(
        targetObject: '阴影半圆',
        targetQuestion: '求面积',
        measurements: <VisualMeasurementAssumption>[
          VisualMeasurementAssumption(
            label: '10',
            meaning: '半圆直径',
            usedInSolution: true,
            confidence: 'low',
          ),
        ],
        uncertainItems: <String>['10 是否为直径'],
        needsManualReview: true,
        reviewReason: '需核对 10 的标注含义',
      ),
      visualAssumptionStatus: VisualAssumptionStatus.needsReview,
    );
    const verification = r'''
{
  "isConsistent": true,
  "correctFinalAnswer": "",
  "correctedFinalAnswerDerivation": "",
  "confidence": "high",
  "needsManualReview": false,
  "reason": "答案与步骤一致。"
}
''';

    final reviewed = service.applyConsistencyVerificationForTest(
      analysis,
      verification,
    );

    expect(reviewed.consistencyStatus, AnalysisConsistencyStatus.needsReview);
    expect(reviewed.consistencyNote, '需核对 10 的标注含义');
    expect(reviewed.wasVerifierUsed, isTrue);
  });

  test('service does not let visual assumption review skip answer mismatch',
      () {
    final service = AiAnalysisService.fake();
    const analysis = AnalysisResult(
      finalAnswer: r'25\pi',
      finalAnswerDerivation: r'先得到 29\pi/2，但结合常见构型改成 25\pi。',
      steps: <String>[
        r'圆心为 (-5,5)，半径为 5。',
        r'半圆面积为 \frac{1}{2}\pi\times5^2=\frac{25\pi}{2}。最终答案是 \frac{25\pi}{2}。',
      ],
      aiTags: <String>['半圆', '面积'],
      knowledgePoints: <String>['半圆面积'],
      mistakeReason: '读图假设不稳定。',
      studyAdvice: '核对关键标注。',
      visualAssumptions: VisualAssumptions(
        targetObject: '半圆',
        targetQuestion: '求面积',
        uncertainItems: <String>['3 与 7 的对应关系'],
        needsManualReview: true,
        reviewReason: '关键标注需核对',
      ),
      visualAssumptionStatus: VisualAssumptionStatus.needsReview,
    );
    const verification = r'''
{
  "isConsistent": false,
  "correctFinalAnswer": "25\\pi/2",
  "correctedFinalAnswerDerivation": "步骤最终得到 25\\pi/2。",
  "confidence": "low",
  "needsManualReview": true,
  "reason": "finalAnswer 与步骤最终结论不同。"
}
''';

    final reviewed = service.applyConsistencyVerificationForTest(
      analysis,
      verification,
    );

    expect(reviewed.finalAnswer, r'25\pi');
    expect(reviewed.consistencyStatus, AnalysisConsistencyStatus.needsReview);
    expect(reviewed.consistencyNote, 'finalAnswer 与步骤最终结论不同。');
    expect(reviewed.wasVerifierUsed, isTrue);
  });

  test('service keeps repaired visual assumptions in review state', () {
    final service = AiAnalysisService.fake();
    const analysis = AnalysisResult(
      finalAnswer: r'25\pi',
      finalAnswerDerivation: r'误把半圆当整圆。',
      steps: <String>[r'半圆面积最终应为 25\pi/2。'],
      aiTags: <String>['半圆', '面积'],
      knowledgePoints: <String>['半圆面积'],
      mistakeReason: '读图假设不稳定。',
      studyAdvice: '核对关键标注。',
      visualAssumptions: VisualAssumptions(
        targetObject: '半圆',
        targetQuestion: '求面积',
        uncertainItems: <String>['10 是否为直径'],
        needsManualReview: true,
        reviewReason: '需核对 10 的标注含义',
      ),
      visualAssumptionStatus: VisualAssumptionStatus.needsReview,
    );
    const verification = r'''
{
  "isConsistent": false,
  "correctFinalAnswer": "25\\pi/2",
  "correctedFinalAnswerDerivation": "步骤最终得到 25\\pi/2。",
  "correctedSteps": ["半圆面积最终应为 25\\pi/2。"],
  "confidence": "high",
  "needsManualReview": false,
  "reason": "finalAnswer 写成整圆面积。"
}
''';

    final reviewed = service.applyConsistencyVerificationForTest(
      analysis,
      verification,
    );

    expect(reviewed.finalAnswer, r'25\pi/2');
    expect(reviewed.consistencyStatus, AnalysisConsistencyStatus.needsReview);
    expect(reviewed.consistencyNote, contains('AI 已复核并修正答案'));
    expect(reviewed.consistencyNote, contains('需核对 10 的标注含义'));
    expect(reviewed.wasVerifierUsed, isTrue);
  });

  test('service applies high confidence verifier repair conservatively', () {
    final service = AiAnalysisService.fake();
    const analysis = AnalysisResult(
      finalAnswer: r'25\pi',
      finalAnswerDerivation: r'误把整圆面积 25\pi 当作最终答案。',
      steps: <String>[
        r'圆面积为 25\pi',
        r'阴影面积为 \frac{1}{2}\times25\pi=25\pi/2，所以答案为 25\pi/2。',
      ],
      aiTags: <String>['几何'],
      knowledgePoints: <String>['圆面积'],
      mistakeReason: r'漏乘 \frac{1}{2}',
      studyAdvice: '区分整圆和半圆面积',
    );
    const verification = r'''
{
  "isConsistent": false,
  "correctFinalAnswer": "25\\pi/2",
  "correctedFinalAnswerDerivation": "最后一步得到 25\\pi/2，因此最终答案应为 25\\pi/2。",
  "confidence": "high",
  "needsManualReview": false,
  "reason": "finalAnswer 写成整圆面积，步骤最终结论是半圆面积。"
}
''';

    final repaired = service.applyConsistencyVerificationForTest(
      analysis,
      verification,
    );

    expect(repaired.finalAnswer, r'25\pi/2');
    expect(repaired.consistencyStatus, AnalysisConsistencyStatus.repaired);
    expect(repaired.wasVerifierUsed, isTrue);
  });

  test('service marks low confidence verifier result as needs review', () {
    final service = AiAnalysisService.fake();
    const analysis = AnalysisResult(
      finalAnswer: 'C. 10',
      finalAnswerDerivation: '根据 finalAnswer 选择 C。',
      steps: <String>['设未知数', '解得 20，所以选 D。'],
      aiTags: <String>['应用题'],
      knowledgePoints: <String>['方程'],
      mistakeReason: '审题错误',
      studyAdvice: '列式后验算',
    );
    const verification = r'''
{
  "isConsistent": false,
  "correctFinalAnswer": "D. 20",
  "correctedFinalAnswerDerivation": "步骤结论为 D. 20。",
  "confidence": "low",
  "needsManualReview": true,
  "reason": "题干信息不足，无法确认。"
}
''';

    final reviewed = service.applyConsistencyVerificationForTest(
      analysis,
      verification,
    );

    expect(reviewed.finalAnswer, 'C. 10');
    expect(reviewed.consistencyStatus, AnalysisConsistencyStatus.needsReview);
    expect(reviewed.wasVerifierUsed, isTrue);
  });

  test('service does not let mistake reason mask final answer mismatch', () {
    final service = AiAnalysisService.fake();
    const analysis = AnalysisResult(
      finalAnswer: r'25\pi',
      finalAnswerDerivation: r'最终答案写成 25\pi。',
      steps: <String>[
        r'由图形关系得到半圆半径为 \sqrt{29}。',
        r'半圆面积为 \frac{1}{2}\pi\times29=29\pi/2，所以答案为 29\pi/2。',
      ],
      aiTags: <String>['半圆', '面积'],
      knowledgePoints: <String>['半圆面积'],
      mistakeReason: r'原答案 25\pi 可能来自把半圆误当整圆。',
      studyAdvice: '核对半径或直径关系。',
    );
    const verification = r'''
{
  "isConsistent": false,
  "correctFinalAnswer": "29\\pi/2",
  "correctedFinalAnswerDerivation": "步骤最终得到 29\\pi/2。",
  "confidence": "low",
  "needsManualReview": true,
  "reason": "finalAnswer 与步骤最终结论不同，需要人工核对图形关系。"
}
''';

    final reviewed = service.applyConsistencyVerificationForTest(
      analysis,
      verification,
    );

    expect(reviewed.finalAnswer, r'25\pi');
    expect(reviewed.consistencyStatus, AnalysisConsistencyStatus.needsReview);
    expect(reviewed.wasVerifierUsed, isTrue);
  });

  test('service detects semicircle area formula chain contradiction', () {
    final service = AiAnalysisService.fake();
    const analysis = AnalysisResult(
      finalAnswer: r'25\pi',
      finalAnswerDerivation: r'最后得到 \(25\pi\)。',
      steps: <String>[
        r'解得半径 \(r=5\)。',
        r'半圆面积公式为 \(S=\frac{1}{2}\pi r^2\)，代入 \(r=5\)，得 \(S=\frac{25\pi}{2}\times2=25\pi\)。',
      ],
      aiTags: <String>['半圆', '面积'],
      knowledgePoints: <String>['半圆面积'],
      mistakeReason: r'把 \(25\pi/2\) 又乘以 2。',
      studyAdvice: '确认求的是半圆还是整圆。',
    );
    const verification = r'''
{
  "isConsistent": false,
  "correctFinalAnswer": "25\\pi/2",
  "correctedFinalAnswerDerivation": "半圆面积为整圆面积的一半，因此最终答案是 25\\pi/2。",
  "confidence": "high",
  "needsManualReview": false,
  "reason": "步骤中半圆面积公式已给出 25π/2，后续多乘 2 得到 25π 是错误的。"
}
''';

    final repaired = service.applyConsistencyVerificationForTest(
      analysis,
      verification,
    );

    expect(repaired.finalAnswer, r'25\pi/2');
    expect(repaired.consistencyStatus, AnalysisConsistencyStatus.repaired);
  });

  test('service repairs semicircle formula chain steps from verifier', () {
    final service = AiAnalysisService.fake();
    const analysis = AnalysisResult(
      finalAnswer: r'25\pi',
      finalAnswerDerivation: r'最后得到 \(25\pi\)。',
      steps: <String>[
        r'解得半径 \(r=5\)。',
        r'半圆面积公式为 \(S=\frac{1}{2}\pi r^2\)，代入 \(r=5\)，得 \(S=\frac{25\pi}{2}\times2=25\pi\)。',
      ],
      aiTags: <String>['半圆', '面积'],
      knowledgePoints: <String>['半圆面积'],
      mistakeReason: r'把 \(25\pi/2\) 又乘以 2。',
      studyAdvice: '确认求的是半圆还是整圆。',
    );
    const verification = r'''
{
  "isConsistent": false,
  "correctFinalAnswer": "25\\pi/2",
  "correctedFinalAnswerDerivation": "半圆面积为整圆面积的一半，因此最终答案是 25\\pi/2。",
  "correctedSteps": [
    "解得半径 \\(r=5\\)。",
    "半圆面积公式为 \\(S=\\frac{1}{2}\\pi r^2\\)，代入 \\(r=5\\)，得 \\(S=\\frac{1}{2}\\pi\\times5^2=\\frac{25\\pi}{2}\\)。"
  ],
  "correctedMistakeReason": "误把半圆面积又乘以 2，变成了整圆面积。",
  "confidence": "high",
  "needsManualReview": false,
  "reason": "原步骤中半圆面积已经是 25π/2，后续多乘 2 得到 25π 是错误的。"
}
''';

    final repaired = service.applyConsistencyVerificationForTest(
      analysis,
      verification,
    );

    expect(repaired.finalAnswer, r'25\pi/2');
    expect(repaired.steps.join(' '), isNot(contains(r'\times2=25\pi')));
    expect(repaired.steps.join(' '), contains(r'\frac{25\pi}{2}'));
    expect(repaired.mistakeReason, contains('又乘以 2'));
    expect(repaired.consistencyStatus, AnalysisConsistencyStatus.repaired);
  });

  test('service detects generic step internal contradiction', () {
    final service = AiAnalysisService.fake();
    // A single step has two separate conclusion statements pointing to
    // different numeric values — should be flagged.
    const analysis = AnalysisResult(
      finalAnswer: r'10\pi',
      finalAnswerDerivation: r'最终面积为 10\pi。',
      steps: <String>[
        r'设半径 r，则面积为 \pi r^2。',
        r'所以面积为 25\pi/2，因此最终答案为 10\pi。',
      ],
      aiTags: <String>['圆', '面积'],
      knowledgePoints: <String>['圆面积'],
      mistakeReason: '计算有误。',
      studyAdvice: '检查计算。',
    );

    final isSuspicious = service.detectConsistencyIssueForTest(analysis);
    expect(isSuspicious, isTrue);
  });

  test('service detects graphical target mismatch for composite area question',
      () {
    final service = AiAnalysisService.fake();
    const analysis = AnalysisResult(
      finalAnswer: r'\frac{29\pi}{2}',
      finalAnswerDerivation: r'由勾股定理求出半圆面积为 \frac{29\pi}{2}。',
      reconstructedQuestionText: '如图，求该半圆的面积。',
      visualAssumptions: VisualAssumptions(
        targetObject: '以左侧斜边为直径的半圆',
        targetQuestion: '求半圆面积',
        measurements: <VisualMeasurementAssumption>[
          VisualMeasurementAssumption(
            label: '10',
            meaning: '右侧竖直高度',
            usedInSolution: true,
            evidence: 'image',
            confidence: 'high',
          ),
        ],
      ),
      steps: <String>[
        r'直径平方为 (7-3)^2+10^2=116。',
        r'半圆面积为 \frac{29\pi}{2}。',
      ],
      aiTags: <String>['半圆面积'],
      knowledgePoints: <String>['半圆面积'],
      mistakeReason: '误读目标区域',
      studyAdvice: '先确认题目求哪块区域',
    );

    final isSuspicious = service.detectConsistencyIssueForTest(
      analysis,
      questionText: '图中标注上边为3、底边为7、右边高为10，图内为半圆，求图中括号所示区域面积。',
    );
    final forceManualReview = service.consistencyIssueForcesManualReviewForTest(
      analysis,
      questionText: '图中标注上边为3、底边为7、右边高为10，图内为半圆，求图中括号所示区域面积。',
    );

    expect(isSuspicious, isTrue);
    expect(forceManualReview, isTrue);
  });

  test(
      'service does not flag steps as contradictory when conclusions are consistent',
      () {
    final service = AiAnalysisService.fake();
    const analysis = AnalysisResult(
      finalAnswer: r'25\pi/2',
      finalAnswerDerivation: r'半圆面积为 25\pi/2。',
      steps: <String>[
        r'半径为 5。',
        r'整圆面积为 25\pi。',
        r'半圆面积为 25\pi/2。',
      ],
      aiTags: <String>['半圆'],
      knowledgePoints: <String>['半圆面积'],
      mistakeReason: '无。',
      studyAdvice: '理解半圆公式。',
    );

    final isSuspicious = service.detectConsistencyIssueForTest(analysis);
    // Different steps in a derivation chain naturally have different values
    // (step 2: 整圆=25π, step 3: 半圆=25π/2). Only intra-step contradictions
    // are flagged, not inter-step intermediate calculations.
    expect(isSuspicious, isFalse);
  });

  test('service detects graphical math question conservatively', () {
    final service = AiAnalysisService.fake();

    expect(
      service.isGraphicalQuestion(
        '如图，大矩形长 175cm，高 95cm，右下角空白矩形宽 95cm，高 75cm，求其余部分面积。',
        '数学',
        imagePath: '/tmp/question.jpg',
      ),
      isTrue,
    );
    expect(
      service.isGraphicalQuestion(
        '小明去图书馆借书，第一次借了 3 本，第二次借了 2 本，一共借了几本？',
        '数学',
        imagePath: '/tmp/question.jpg',
      ),
      isFalse,
    );
    expect(
      service.isGraphicalQuestion(
        '如图所示，求阴影部分面积。',
        '语文',
        imagePath: '/tmp/question.jpg',
      ),
      isFalse,
    );
    expect(
      service.isGraphicalQuestion(
        '如图所示，求阴影部分面积。',
        '数学',
      ),
      isFalse,
    );
  });

  test('graphical analysis prompt asks model to read diagram first', () {
    final service = AiAnalysisService.fake();

    final prompt = service.buildAnalysisPromptForTest(
      '如图，求阴影部分面积。',
      '数学',
      isGraphicalQuestion: true,
    );

    expect(prompt, contains('图形/示意图题分析要求'));
    expect(prompt, contains('图片题输入说明'));
    expect(prompt, contains('只能作为参考线索，不是已确认题干'));
    expect(prompt, contains('第一目标是直接根据原图理解题目并完成解题'));
    expect(prompt, contains('不要把人工确认作为解题前置条件'));
    expect(prompt, contains('不要因此跳过解题'));
    expect(prompt, contains('不要为了写完整题干而强行命名外部轮廓'));
    expect(prompt, contains('不能自动解释成上底、下底、高、半径或直径'));
    expect(
        prompt, contains('reconstructedQuestionText 只重构与求解目标直接相关且能从图片确认的条件'));
    expect(prompt, isNot(contains('已确认题目文本')));
    expect(prompt, isNot(contains('举一反三锚点')));
  });

  test('normal analysis prompt does not include graphical instructions', () {
    final service = AiAnalysisService.fake();

    final prompt = service.buildAnalysisPromptForTest('解方程 x+2=5', '数学');

    expect(prompt, isNot(contains('图形/示意图题分析要求')));
    expect(prompt, contains('请分析以下数学科目的错题'));
  });

  test('service parses extracted question structure json', () {
    final service = AiAnalysisService.fake();
    const raw = '''
{
  "subject": "物理",
  "extractedQuestionText": "如图所示，求电阻 R 两端电压。",
  "normalizedQuestionText": "如图所示，求电阻 R 两端的电压。"
}
''';

    final extraction = service.parseExtractionResultForTest(raw);

    expect(extraction.subject, Subject.physics);
    expect(extraction.extractedQuestionText, '如图所示，求电阻 R 两端电压。');
    expect(extraction.normalizedQuestionText, '如图所示，求电阻 R 两端的电压。');
  });

  test('service parses extraction json with raw latex backslashes', () {
    final service = AiAnalysisService.fake();
    const raw = r'''
{
  "subject": "数学",
  "extractedQuestionText": "已知 \angle A=30^\circ，求 \frac{1}{2}x 的值。",
  "normalizedQuestionText": "已知 \angle A=30^\circ，求 \frac{1}{2}x 的值。"
}
''';

    final extraction = service.parseExtractionResultForTest(raw);

    expect(extraction.subject, Subject.math);
    expect(extraction.normalizedQuestionText,
        r'已知 \angle A=30^\circ，求 \frac{1}{2}x 的值。');
  });

  test('service parses extraction json with raw parenthesis latex delimiters',
      () {
    final service = AiAnalysisService.fake();
    const raw = r'''
{
  "subject": "数学",
  "extractedQuestionText": "1. 已知 \(x^2+1=5\)，求 \(x\) 的值。\n2. 若 \(\frac{a}{b}=2\)，求 \(a\)。",
  "normalizedQuestionText": "1. 已知 \(x^2+1=5\)，求 \(x\) 的值。\n2. 若 \(\frac{a}{b}=2\)，求 \(a\)。"
}
''';

    final extraction = service.parseExtractionResultForTest(raw);

    expect(extraction.subject, Subject.math);
    expect(extraction.normalizedQuestionText, contains(r'\(x^2+1=5\)'));
    expect(extraction.normalizedQuestionText, contains(r'\frac{a}{b}'));
    expect(extraction.normalizedQuestionText, contains('\n'));
  });
  test('service repairs mixed escaped delimiters and raw latex commands', () {
    final service = AiAnalysisService.fake();
    const raw = r'''
{
  "subject": "数学",
  "extractedQuestionText": "1. 已知 \\(x^2+1=5\\)，求 \\(x\\) 的值。\n2. 若 \\(\frac{a}{b}=2\\)，求 \\(a\\)。",
  "normalizedQuestionText": "1. 已知 \\(x^2+1=5\\)，求 \\(x\\) 的值。\n2. 若 \\(\frac{a}{b}=2\\)，求 \\(a\\)。"
}
''';

    final extraction = service.parseExtractionResultForTest(raw);

    expect(extraction.subject, Subject.math);
    expect(extraction.normalizedQuestionText, contains(r'\(x^2+1=5\)'));
    expect(extraction.normalizedQuestionText, isNot(contains(r'\\(')));
    expect(extraction.normalizedQuestionText, contains(r'\(\frac{a}{b}=2\)'));
    expect(extraction.normalizedQuestionText, contains('\n'));
  });
  test('service parses extraction json with literal newline in string', () {
    final service = AiAnalysisService.fake();
    const raw = r'''
{
  "subject": "数学",
  "extractedQuestionText": "1. 已知 \(x^2+1=5\)，求 \(x\) 的值。
2. 若 \(\frac{a}{b}=2\)，求 \(a\)。",
  "normalizedQuestionText": "1. 已知 \(x^2+1=5\)，求 \(x\) 的值。
2. 若 \(\frac{a}{b}=2\)，求 \(a\)。"
}
''';

    final extraction = service.parseExtractionResultForTest(raw);

    expect(extraction.subject, Subject.math);
    expect(extraction.normalizedQuestionText, contains(r'\(x^2+1=5\)'));
    expect(extraction.normalizedQuestionText, contains(r'\(\frac{a}{b}=2\)'));
  });
  test(
      'service recovers extraction json with doubled delimiters around raw frac',
      () {
    final service = AiAnalysisService.fake();
    const raw = r'''
{
  "subject": "数学",
  "extractedQuestionText": "1. 已知 \(x^2+1=5\)，求 \(x\) 的值。 \n2. 若 \(\frac{a}{b}=2\)，求 \(a\)。",
  "normalizedQuestionText": "1. 已知 \(x^2+1=5\)，求 \(x\) 的值。 \n2. 若 \(\frac{a}{b}=2\)，求 \(a\)。",
  "extra": "尾部字段"
}
''';

    final extraction = service.parseExtractionResultForTest(raw);

    expect(extraction.subject, Subject.math);
    expect(extraction.normalizedQuestionText, contains(r'\(x^2+1=5\)'));
    expect(extraction.normalizedQuestionText, isNot(contains(r'\\(')));
    expect(extraction.normalizedQuestionText, contains(r'\(\frac{a}{b}=2\)'));
  });
  test('service preserves valid json escape sequences when repairing latex',
      () {
    final service = AiAnalysisService.fake();
    const raw = r'''
{
  "subject": "数学",
  "finalAnswer": "第一行\n第二行，公式 \frac{1}{2}",
  "steps": ["使用公式 \times 2", "保留换行\n继续"],
  "aiTags": ["几何"],
  "knowledgePoints": ["角度与分式"],
  "mistakeReason": "漏看 \angle 标记",
  "studyAdvice": "规范书写"
}
''';

    final exercises = service.extractGeneratedExercisesFromContent(raw,
        questionId: 'q-latex');

    expect(exercises.length, 3);
  });

  test('service repairs raw latex without corrupting escaped delimiters', () {
    final service = AiAnalysisService.fake();
    const raw = r'''
{
  "subject": "数学",
  "finalAnswer": "\\(50-\frac{29\pi}{2}\\)",
  "finalAnswerDerivation": "外框面积 \\(50\\) 减去半圆面积 \\(\frac{29\pi}{2}\\)。",
  "visualAssumptions": {
    "targetObject": "半圆外剩余区域",
    "targetQuestion": "求面积",
    "measurements": [
      {"label": "10", "meaning": "高度", "usedInSolution": true, "evidence": "image", "confidence": "high"}
    ],
    "solutionBasis": ["外框面积减半圆面积"],
    "uncertainItems": [],
    "needsManualReview": false,
    "reviewReason": ""
  },
  "steps": ["半圆面积为 \\(\frac{29\pi}{2}\\)。"],
  "aiTags": ["几何"],
  "knowledgePoints": ["半圆面积"],
  "mistakeReason": "目标区域读错",
  "studyAdvice": "先确认目标区域"
}
''';

    final analysis = service.parseAnalysisResponseForTest(raw);

    expect(analysis.finalAnswer, r'\(50-\frac{29\pi}{2}\)');
    expect(analysis.visualAssumptions?.targetObject, '半圆外剩余区域');
    expect(analysis.visualAssumptions?.measurements.single.label, '10');
  });

  test('service falls back to default exercises when raw json has none', () {
    final service = AiAnalysisService.fake();
    const raw = '''
{
  "subject": "数学",
  "finalAnswer": "x=3",
  "steps": ["移项", "求解"],
  "aiTags": ["方程"],
  "knowledgePoints": ["一元一次方程"],
  "mistakeReason": "计算粗心",
  "studyAdvice": "多练习"
}
''';

    final exercises =
        service.extractGeneratedExercisesFromContent(raw, questionId: 'q-2');

    expect(exercises.length, 3);
    expect(exercises.first.questionId, 'q-2');
    expect(exercises.first.generationMode.name, 'practice');
  });

  test('service normalizes double backslashes in generated exercise content',
      () {
    final service = AiAnalysisService.fake();
    const raw = r'''
{
  "subject": "数学",
  "finalAnswer": "答案为 \\(x=2\\)",
  "steps": ["使用 \\frac{1}{2}"],
  "aiTags": ["方程"],
  "knowledgePoints": ["一元一次方程"],
  "mistakeReason": "计算粗心",
  "studyAdvice": "多练习",
  "generatedExercises": [
    {
      "id": "g-latex",
      "difficulty": "同级",
      "question": "解方程：\\(x^2+1=5\\)",
      "options": ["A. \\(1\\)", "B. \\(2\\)", "C. \\(3\\)", "D. \\(4\\)"],
      "answer": "B",
      "explanation": "因为 \\frac{4}{2}=2"
    }
  ]
}
''';

    final exercises = service.extractGeneratedExercisesFromContent(raw,
        questionId: 'q-latex-normalized');

    expect(exercises.single.question, r'解方程：\(x^2+1=5\)');
    expect(exercises.single.question, isNot(contains(r'\\(')));
    expect(exercises.single.explanation, r'因为 \frac{4}{2}=2');
    expect(exercises.single.options, <String>[
      r'A. \(1\)',
      r'B. \(2\)',
      r'C. \(3\)',
      r'D. \(4\)',
    ]);
  });
  test('service extracts generated exercises from raw ai json', () {
    final service = AiAnalysisService.fake();
    const raw = '''
{
  "subject": "数学",
  "finalAnswer": "x=2",
  "steps": ["移项", "求解"],
  "aiTags": ["方程"],
  "knowledgePoints": ["一元一次方程"],
  "mistakeReason": "计算粗心",
  "studyAdvice": "多练习",
  "generatedExercises": [
    {
      "id": "g1",
      "difficulty": "同级",
      "question": "2x+1=5，求 x 的值",
      "options": ["A. 1", "B. 2", "C. 3", "D. 4"],
      "answer": "B",
      "explanation": "2x=4，所以 x=2"
    }
  ]
}
''';

    final exercises =
        service.extractGeneratedExercisesFromContent(raw, questionId: 'q-1');

    expect(exercises.length, 1);
    expect(exercises.first.id, 'g1');
    expect(exercises.first.questionId, 'q-1');
    expect(exercises.first.question, '2x+1=5，求 x 的值');
    expect(exercises.first.options, ['A. 1', 'B. 2', 'C. 3', 'D. 4']);
  });

  test('analysis prompt anchors right triangle length exercises', () {
    final service = AiAnalysisService.fake();

    final prompt = service.buildAnalysisPromptForTest(
      r'如图，\(\angle ABC=90^\circ\)，\(\angle ADC=90^\circ\)，\(BD=BC\)，\(AD=6\)，\(DC=8\)，求 \(BC\) 的长度。',
      'math',
      isGraphicalQuestion: true,
    );

    expect(prompt, contains('domain=planeGeometryLength'));
    expect(prompt, contains('object=rightTriangle'));
    expect(prompt, contains('pythagorean'));
    expect(prompt, contains('简单、同级、提高'));
    expect(prompt, contains('同一知识点、同一题型、同一核心解法'));
  });

  test('service preserves square perpendicular bisector length exercises', () {
    final service = AiAnalysisService.fake();
    const raw = r'''
{
  "subject": "数学",
  "finalAnswer": "\(DF=\frac{1}{4}\)",
  "steps": ["设 \(F(2,y)\)", "由垂直平分线性质得 \(FA=FE\)", "解得 \(DF=\frac{1}{4}\)"],
  "aiTags": ["正方形", "垂直平分线", "坐标法", "线段长度"],
  "knowledgePoints": ["垂直平分线性质", "坐标法", "两点距离公式"],
  "mistakeReason": "忽略垂直平分线性质",
  "studyAdvice": "先设点坐标，再用距离相等列方程",
  "generatedExercises": [
    {"id": "sq1", "difficulty": "简单", "question": "如图，在边长为 \(4\) 的正方形 \(ABCD\) 中，点 \(E\) 是 \(BC\) 的中点，点 \(F\) 在 \(DC\) 上，且 \(F\) 在线段 \(AE\) 的垂直平分线上。求 \(DF\) 的长。", "options": ["A. \(\frac{1}{2}\)", "B. \(1\)", "C. \(\frac{3}{2}\)", "D. \(2\)"], "answer": "A", "explanation": "设 \(F(4,y)\)，由 \(FA=FE\) 得 \(4^2+(y-4)^2=2^2+y^2\)，解得 \(DF=\frac{1}{2}\)。", "diagramData": {"elements": [{"type": "polygon", "points": [[0.2,0.2],[0.2,0.8],[0.8,0.8],[0.8,0.2]]}]}},
    {"id": "sq2", "difficulty": "同级", "question": "如图，在边长为 \(8\) 的正方形 \(ABCD\) 中，点 \(E\) 是 \(BC\) 的中点，点 \(F\) 在 \(DC\) 上，直线 \(FH\) 垂直平分线段 \(AE\)。求 \(DF\) 的长。", "options": ["A. \(\frac{1}{2}\)", "B. \(1\)", "C. \(2\)", "D. \(4\)"], "answer": "B", "explanation": "设 \(F(8,y)\)，由 \(FA=FE\) 得 \(8^2+(y-8)^2=4^2+y^2\)，解得 \(y=7\)，所以 \(DF=1\)。", "diagramData": {"elements": [{"type": "polygon", "points": [[0.2,0.2],[0.2,0.8],[0.8,0.8],[0.8,0.2]]}]}},
    {"id": "sq3", "difficulty": "提升", "question": "如图，在边长为 \(6\) 的正方形 \(ABCD\) 中，点 \(E\) 是 \(BC\) 的中点，点 \(F\) 在 \(DC\) 上，且 \(F\) 在线段 \(AE\) 的垂直平分线上。求 \(DF\) 的长。", "options": ["A. \(\frac{1}{2}\)", "B. \(\frac{2}{3}\)", "C. \(\frac{3}{4}\)", "D. \(\frac{5}{4}\)"], "answer": "C", "explanation": "设 \(F(6,y)\)，由 \(FA=FE\) 得 \(6^2+(y-6)^2=3^2+y^2\)，解得 \(DF=\frac{3}{4}\)。", "diagramData": {"elements": [{"type": "polygon", "points": [[0.2,0.2],[0.2,0.8],[0.8,0.8],[0.8,0.2]]}]}}
  ]
}
''';

    final exercises = service.extractGeneratedExercisesFromContent(
      raw,
      questionId: 'q-square-bisector',
      sourceQuestionText:
          r'如图，在边长为 \(2\) 的正方形 \(ABCD\) 中，点 \(E\) 是边 \(BC\) 的中点，点 \(F\) 在边 \(DC\) 上，直线 \(FH\) 是线段 \(AE\) 的垂直平分线，求 \(DF\) 的长。',
    );

    expect(exercises.length, 3);
    expect(exercises.map((exercise) => exercise.id),
        <String>['sq1', 'sq2', 'sq3']);
    expect(exercises.map((exercise) => exercise.difficulty),
        <String>['简单', '同级', '提高']);
    expect(exercises.map((exercise) => exercise.question).join(' '),
        contains('正方形'));
    expect(exercises.map((exercise) => exercise.question).join(' '),
        contains('垂直平分'));
    expect(exercises.every((exercise) => exercise.diagramData != null), isTrue);
  });

  test(
      'service limits generic generated exercises to one practice set of three',
      () {
    final service = AiAnalysisService.fake();
    const raw = '''
{
  "subject": "英语",
  "finalAnswer": "1.C 2.B 3.C",
  "steps": ["语法选择"],
  "aiTags": ["语法选择"],
  "knowledgePoints": ["时态", "语态", "固定搭配"],
  "mistakeReason": "忽略语境",
  "studyAdvice": "圈出语法标志",
  "generatedExercises": [
    {"id": "g1", "difficulty": "简单", "question": "For years, they ______ here.", "options": ["A. live", "B. lived", "C. have lived", "D. living"], "answer": "C", "explanation": "For years 用现在完成时。"},
    {"id": "g2", "difficulty": "简单", "question": "The room ______ yesterday.", "options": ["A. cleans", "B. cleaned", "C. was cleaned", "D. has cleaned"], "answer": "C", "explanation": "room 与 clean 是被动关系。"},
    {"id": "g3", "difficulty": "同级", "question": "She is ______ in music.", "options": ["A. interest", "B. interesting", "C. interested", "D. to interest"], "answer": "C", "explanation": "be interested in。"},
    {"id": "g4", "difficulty": "提高", "question": "The habit, ______ is useful, remains.", "options": ["A. who", "B. which", "C. that", "D. what"], "answer": "B", "explanation": "非限制性定语从句用 which。"}
  ]
}
''';

    final exercises = service.extractGeneratedExercisesFromContent(raw,
        questionId: 'q-english');

    expect(exercises.length, 3);
    expect(
        exercises.map((exercise) => exercise.id), <String>['g1', 'g3', 'g4']);
    expect(exercises.map((exercise) => exercise.difficulty),
        <String>['简单', '同级', '提高']);
  });

  test('service rejects linear drift for quadratic root source and falls back',
      () {
    final service = AiAnalysisService.fake();
    const raw = r'''
{
  "subject": "数学",
  "finalAnswer": "由 \(x^2+1=5\) 可得 \(x=\pm 2\)。",
  "steps": ["先得到 \(x^2=4\)", "再开平方，得到 \(x=\pm 2\)"],
  "aiTags": ["一元二次", "平方根", "解方程"],
  "knowledgePoints": ["解含平方项的简单方程", "由 \(x^2=a\) 得 \(x=\pm \sqrt{a}\)"],
  "mistakeReason": "容易漏掉负根",
  "studyAdvice": "整理成 \(x^2=a\) 后再开平方",
  "generatedExercises": [
    {"id": "bad1", "difficulty": "简单", "question": "x+1=4，求 x 的值", "options": ["A. 2", "B. 3", "C. 4", "D. 5"], "answer": "B", "explanation": "移项得 x=4-1=3"},
    {"id": "bad2", "difficulty": "同级", "question": "2x=8，求 x 的值", "options": ["A. 2", "B. 3", "C. 4", "D. 6"], "answer": "C", "explanation": "两边同时除以 2 得 x=4"},
    {"id": "bad3", "difficulty": "提高", "question": "3x+2=11，求 x 的值", "options": ["A. 2", "B. 3", "C. 4", "D. 5"], "answer": "B", "explanation": "先减 2 再除以 3 得 x=3"}
  ]
}
''';

    final exercises = service.extractGeneratedExercisesFromContent(
      raw,
      questionId: 'q-quadratic',
      sourceQuestionText: r'已知 \(x^2+1=5\)，求 \(x\) 的值。',
    );

    expect(exercises.length, 3);
    expect(exercises.map((exercise) => exercise.id), isNot(contains('bad1')));
    expect(exercises.first.question, contains('x^2'));
    expect(exercises.any((exercise) => exercise.explanation.contains(r'\pm')),
        isTrue);
  });

  test(
      'service falls back to function evaluation exercises for function source',
      () {
    final service = AiAnalysisService.fake();
    const raw = r'''
{
  "subject": "数学",
  "finalAnswer": "把 x=3 代入 f(x)=x^2-2x+1，得 f(3)=4。",
  "steps": ["代入 x=3", "计算 3^2-2\\times3+1=4"],
  "aiTags": ["函数"],
  "knowledgePoints": ["函数值", "代入求值"],
  "mistakeReason": "代入计算错误",
  "studyAdvice": "按运算顺序计算",
  "generatedExercises": [
    {"id": "bad1", "difficulty": "简单", "question": "解方程 x^2=9，求 x", "options": ["A. 3", "B. -3", "C. \\pm3", "D. 9"], "answer": "C", "explanation": "开平方得 x=\\pm3"},
    {"id": "bad2", "difficulty": "同级", "question": "解方程 (x-1)^2=16", "options": ["A. 5", "B. -3", "C. 5或-3", "D. 16"], "answer": "C", "explanation": "开平方"},
    {"id": "bad3", "difficulty": "提高", "question": "解方程 x^2+4=20", "options": ["A. 4", "B. \\pm4", "C. 8", "D. \\pm8"], "answer": "B", "explanation": "开平方"}
  ]
}
''';

    final exercises = service.extractGeneratedExercisesFromContent(
      raw,
      questionId: 'q-function',
      sourceQuestionText: r'已知函数 \(f(x)=x^2-2x+1\)，求 \(f(3)\) 的值。',
    );

    expect(exercises.length, 3);
    expect(exercises.first.question, contains('函数'));
    expect(exercises.first.question, contains(r'f('));
    expect(exercises.map((exercise) => exercise.question).join(' '),
        isNot(contains('x^2=9')));
  });

  test('service falls back to volume exercises for cone volume source', () {
    final service = AiAnalysisService.fake();
    const raw = r'''
{
  "subject": "数学",
  "finalAnswer": "V=12\\pi",
  "steps": ["V=\\frac{1}{3}\\pi r^2h", "代入 r=3，h=4"],
  "aiTags": ["立体几何"],
  "knowledgePoints": ["圆锥体积", "公式代入"],
  "mistakeReason": "公式记错",
  "studyAdvice": "记住圆锥体积是圆柱的三分之一",
  "generatedExercises": [
    {"id": "bad1", "difficulty": "简单", "question": "解方程 x^2=49，则 x 的值是", "options": ["A. 7", "B. -7", "C. \\pm7", "D. 49"], "answer": "C", "explanation": "开平方"},
    {"id": "bad2", "difficulty": "同级", "question": "解方程 (x-1)^2=16", "options": ["A. 5", "B. -3", "C. 5或-3", "D. 16"], "answer": "C", "explanation": "开平方"},
    {"id": "bad3", "difficulty": "提高", "question": "x^2+1=50，求 x", "options": ["A. 7", "B. \\pm7", "C. 49", "D. 50"], "answer": "B", "explanation": "先移项再开平方"}
  ]
}
''';

    final exercises = service.extractGeneratedExercisesFromContent(
      raw,
      questionId: 'q-volume',
      sourceQuestionText: r'圆锥底面半径 r=3，高 h=4，求体积 V=\frac{1}{3}\pi r^2h。',
    );

    expect(exercises.length, 3);
    expect(exercises.first.question, contains('圆锥'));
    expect(exercises.map((exercise) => exercise.question).join(' '),
        isNot(contains('解方程')));
  });

  test('service rejects equation system drift to linear equation', () {
    final service = AiAnalysisService.fake();
    const raw = r'''
{
  "subject": "数学",
  "finalAnswer": "x=4,y=3",
  "steps": ["两式相加消元", "代入求 y"],
  "aiTags": ["方程组"],
  "knowledgePoints": ["加减消元"],
  "mistakeReason": "消元错误",
  "studyAdvice": "先观察系数",
  "generatedExercises": [
    {"id": "bad1", "difficulty": "简单", "question": "解方程 x+1=4", "options": ["A. 1", "B. 2", "C. 3", "D. 4"], "answer": "C", "explanation": "移项得 x=3"},
    {"id": "bad2", "difficulty": "同级", "question": "解方程 2x=8", "options": ["A. 2", "B. 3", "C. 4", "D. 5"], "answer": "C", "explanation": "除以 2"},
    {"id": "bad3", "difficulty": "提高", "question": "解方程 3x+2=11", "options": ["A. 2", "B. 3", "C. 4", "D. 5"], "answer": "B", "explanation": "移项"}
  ]
}
''';

    final exercises = service.extractGeneratedExercisesFromContent(
      raw,
      questionId: 'q-system',
      sourceQuestionText: r'解方程组：\begin{cases} x+y=7 \\ x-y=1 \end{cases}',
    );

    expect(exercises.length, 3);
    expect(exercises.first.question, contains('方程组'));
    expect(exercises.first.question, contains('cases'));
  });

  test('service rejects triangle angle drift to algebra equation', () {
    final service = AiAnalysisService.fake();
    const raw = r'''
{
  "subject": "数学",
  "finalAnswer": "70°",
  "steps": ["三角形内角和为 180°", "180-50-60=70"],
  "aiTags": ["三角形"],
  "knowledgePoints": ["内角和"],
  "mistakeReason": "角度关系不清",
  "studyAdvice": "先标出已知角",
  "generatedExercises": [
    {"id": "bad1", "difficulty": "简单", "question": "解方程 x+1=4", "options": ["A. 1", "B. 2", "C. 3", "D. 4"], "answer": "C", "explanation": "移项得 x=3"},
    {"id": "bad2", "difficulty": "同级", "question": "解方程 2x=8", "options": ["A. 2", "B. 3", "C. 4", "D. 5"], "answer": "C", "explanation": "除以 2"},
    {"id": "bad3", "difficulty": "提高", "question": "解方程 3x+2=11", "options": ["A. 2", "B. 3", "C. 4", "D. 5"], "answer": "B", "explanation": "移项"}
  ]
}
''';

    final exercises = service.extractGeneratedExercisesFromContent(
      raw,
      questionId: 'q-triangle',
      sourceQuestionText:
          r'在 \triangle ABC 中，\angle A=50^\circ，\angle B=60^\circ，求 \angle C。',
    );

    expect(exercises.length, 3);
    expect(exercises.first.question, contains(r'\triangle'));
    expect(exercises.map((exercise) => exercise.question).join(' '),
        isNot(contains('解方程 x+1')));
  });

  test('service preserves valid function evaluation generated exercises', () {
    final service = AiAnalysisService.fake();
    const raw = r'''
{
  "subject": "数学",
  "finalAnswer": "4",
  "steps": ["代入 x=3"],
  "aiTags": ["函数"],
  "knowledgePoints": ["函数值"],
  "mistakeReason": "代入错误",
  "studyAdvice": "先代入再计算",
  "generatedExercises": [
    {"id": "good-f", "difficulty": "同级", "question": "已知函数 f(x)=x^2+1，求 f(2)", "options": ["A. 3", "B. 4", "C. 5", "D. 6"], "answer": "C", "explanation": "代入 x=2，f(2)=4+1=5"}
  ]
}
''';

    final exercises = service.extractGeneratedExercisesFromContent(
      raw,
      questionId: 'q-function-valid',
      sourceQuestionText: r'已知函数 \(f(x)=x^2-2x+1\)，求 \(f(3)\) 的值。',
    );

    expect(exercises.length, 3);
    expect(exercises.map((exercise) => exercise.id), contains('good-f'));
    expect(exercises[1].id, 'good-f');
    expect(exercises.map((exercise) => exercise.question).join(' '),
        contains('函数'));
  });

  test('service preserves valid volume generated exercises', () {
    final service = AiAnalysisService.fake();
    const raw = r'''
{
  "subject": "数学",
  "finalAnswer": "12\\pi",
  "steps": ["代入体积公式"],
  "aiTags": ["立体几何"],
  "knowledgePoints": ["圆锥体积"],
  "mistakeReason": "公式错误",
  "studyAdvice": "区分圆锥和圆柱公式",
  "generatedExercises": [
    {"id": "good-v", "difficulty": "同级", "question": "圆锥底面半径为 2，高为 6，求体积", "options": ["A. 6π", "B. 8π", "C. 10π", "D. 12π"], "answer": "B", "explanation": "体积 V=1/3πr^2h=1/3π×4×6=8π"}
  ]
}
''';

    final exercises = service.extractGeneratedExercisesFromContent(
      raw,
      questionId: 'q-volume-valid',
      sourceQuestionText: r'圆锥底面半径 r=3，高 h=4，求体积 V=\frac{1}{3}\pi r^2h。',
    );

    expect(exercises.length, 3);
    expect(exercises.map((exercise) => exercise.id), contains('good-v'));
    expect(exercises[1].id, 'good-v');
    expect(exercises.map((exercise) => exercise.question).join(' '),
        contains('圆锥'));
  });

  test(
      'service falls back to proportional relation exercises for fraction source',
      () {
    final service = AiAnalysisService.fake();
    const raw = r'''
{
  "subject": "数学",
  "finalAnswer": "a=6,b=3",
  "steps": ["由 \\(\\frac{a}{b}=2\\) 得 \\(a=2b\\)", "代入 \\(a+b=9\\)"],
  "aiTags": ["分式关系", "代入法", "二元关系"],
  "knowledgePoints": ["比值关系", "和式条件"],
  "mistakeReason": "比例关系转化错误",
  "studyAdvice": "先把比值转成倍数关系",
  "generatedExercises": [
    {"id": "bad1", "difficulty": "简单", "question": "解方程 \\(x^2=9\\)，求 \\(x\\)", "options": ["A. \\(3\\)", "B. \\(-3\\)", "C. \\(\\pm3\\)", "D. \\(9\\)"], "answer": "C", "explanation": "开平方"},
    {"id": "bad2", "difficulty": "同级", "question": "解方程组：\\begin{cases} x+y=5 \\\\ x-y=1 \\end{cases}", "options": ["A. 1", "B. 2", "C. 3", "D. 4"], "answer": "C", "explanation": "加减消元"},
    {"id": "bad3", "difficulty": "提高", "question": "已知函数 f(x)=x^2，求 f(3)", "options": ["A. 3", "B. 6", "C. 9", "D. 12"], "answer": "C", "explanation": "代入"}
  ]
}
''';

    final exercises = service.extractGeneratedExercisesFromContent(
      raw,
      questionId: 'q-proportion',
      sourceQuestionText: r'若 \(\frac{a}{b}=2\)，且 \(a+b=9\)，求 \(a,b\)。',
    );

    expect(exercises.length, 3);
    expect(exercises.first.question, contains(r'\frac'));
    expect(exercises.map((exercise) => exercise.question).join(' '),
        isNot(contains('方程组')));
    expect(exercises.map((exercise) => exercise.question).join(' '),
        isNot(contains('x^2')));
  });

  test(
      'service preserves valid slots and fills invalid slots for strong source',
      () {
    final service = AiAnalysisService.fake();
    const raw = r'''
{
  "subject": "数学",
  "finalAnswer": "4",
  "steps": ["代入 x=3"],
  "aiTags": ["函数"],
  "knowledgePoints": ["函数值"],
  "mistakeReason": "代入错误",
  "studyAdvice": "先代入再计算",
  "generatedExercises": [
    {"id": "good-f", "difficulty": "同级", "question": "已知函数 f(x)=x^2+1，求 f(2)", "options": ["A. 3", "B. 4", "C. 5", "D. 6"], "answer": "C", "explanation": "代入 x=2，f(2)=4+1=5"},
    {"id": "bad-q", "difficulty": "简单", "question": "解方程 x+1=4", "options": ["A. 1", "B. 2", "C. 3", "D. 4"], "answer": "C", "explanation": "移项"},
    {"id": "bad-geo", "difficulty": "提高", "question": "一个圆半径为 5，求面积", "options": ["A. 5π", "B. 10π", "C. 25π", "D. 50π"], "answer": "C", "explanation": "圆面积"}
  ]
}
''';

    final exercises = service.extractGeneratedExercisesFromContent(
      raw,
      questionId: 'q-partial-strong',
      sourceQuestionText: r'已知函数 \(f(x)=x^2-2x+1\)，求 \(f(3)\) 的值。',
    );

    expect(exercises.length, 3);
    expect(exercises.map((exercise) => exercise.id), contains('good-f'));
    expect(exercises.map((exercise) => exercise.id), isNot(contains('bad-q')));
    expect(
        exercises.map((exercise) => exercise.id), isNot(contains('bad-geo')));
    expect(exercises.map((exercise) => exercise.difficulty),
        <String>['简单', '同级', '提高']);
    expect(exercises[1].id, 'good-f');
    expect(exercises.map((exercise) => exercise.question).join(' '),
        contains('函数'));
  });

  test('service preserves valid proportional relation generated exercises', () {
    final service = AiAnalysisService.fake();
    const raw = r'''
{
  "subject": "数学",
  "finalAnswer": "a=6,b=3",
  "steps": ["由 \\(\\frac{a}{b}=2\\) 得 \\(a=2b\\)"],
  "aiTags": ["分式关系", "代入法"],
  "knowledgePoints": ["比值关系", "和式条件"],
  "mistakeReason": "比例关系转化错误",
  "studyAdvice": "先转化再代入",
  "generatedExercises": [
    {"id": "good-ratio", "difficulty": "同级", "question": "若 \\(\\frac{x}{y}=3\\)，且 \\(x+y=16\\)，求 \\(x\\) 的值。", "options": ["A. \\(4\\)", "B. \\(8\\)", "C. \\(12\\)", "D. \\(16\\)"], "answer": "C", "explanation": "由 \\(\\frac{x}{y}=3\\) 得 \\(x=3y\\)，代入 \\(x+y=16\\) 得 \\(4y=16\\)，所以 \\(x=12\\)。"}
  ]
}
''';

    final exercises = service.extractGeneratedExercisesFromContent(
      raw,
      questionId: 'q-proportion-valid',
      sourceQuestionText: r'若 \(\frac{a}{b}=2\)，且 \(a+b=9\)，求 \(a,b\)。',
    );

    expect(exercises.length, 3);
    expect(exercises.map((exercise) => exercise.id), contains('good-ratio'));
    expect(exercises[1].id, 'good-ratio');
    expect(exercises.map((exercise) => exercise.question).join(' '),
        contains(r'\frac'));
  });

  test('service triangle fallback wraps angle latex in inline math', () {
    final service = AiAnalysisService.fake();
    const raw = r'''
{
  "subject": "数学",
  "finalAnswer": "70°",
  "steps": ["三角形内角和为 180°"],
  "aiTags": ["三角形"],
  "knowledgePoints": ["内角和"],
  "mistakeReason": "角度关系不清",
  "studyAdvice": "先标出已知角",
  "generatedExercises": []
}
''';

    final exercises = service.extractGeneratedExercisesFromContent(
      raw,
      questionId: 'q-triangle-fallback-format',
      sourceQuestionText:
          r'在 \(\triangle ABC\) 中，若 \(AB=AC\)，且 \(\angle A=40^\circ\)，求 \(\angle B\)。',
    );

    expect(exercises.first.question, contains(r'\(\angle A=50^\circ\)'));
    expect(exercises.first.question, isNot(contains(r'\\angle')));
    expect(exercises.first.explanation, contains(r'\(180^\circ\)'));
  });

  test('service rejects exterior angle diagram when D is not on AB extension',
      () {
    final service = AiAnalysisService.fake();
    const raw = r'''
{
  "subject": "数学",
  "finalAnswer": "70°",
  "steps": ["等腰三角形底角相等"],
  "aiTags": ["等腰三角形", "外角"],
  "knowledgePoints": ["三角形外角"],
  "mistakeReason": "外角位置不清",
  "studyAdvice": "先画延长线",
  "generatedExercises": [
    {
      "id": "bad-exterior",
      "difficulty": "提高",
      "question": "在 \\(\\triangle ABC\\) 中，若 \\(AB=AC\\)，点 \\(D\\) 在 \\(AB\\) 的延长线上，且外角 \\(\\angle DAC=120^\\circ\\)，求 \\(\\angle B\\)。",
      "options": ["A. \\(50^\\circ\\)", "B. \\(55^\\circ\\)", "C. \\(60^\\circ\\)", "D. \\(65^\\circ\\)"],
      "answer": "C",
      "explanation": "外角 120°，所以顶角 60°，底角 60°。",
      "diagramData": {
        "elements": [
          {"type": "polygon", "points": [[0.5,0.22],[0.2,0.82],[0.82,0.82]], "labels": [{"text":"A","x":0.5,"y":0.14},{"text":"B","x":0.15,"y":0.87},{"text":"C","x":0.87,"y":0.87}]},
          {"type": "line", "x1":0.5,"y1":0.22,"x2":0.36,"y2":0.02,"style":"solid","role":"known"},
          {"type":"point","x":0.36,"y":0.02,"label":"D","role":"label"},
          {"type":"tickMark","x1":0.5,"y1":0.22,"x2":0.2,"y2":0.82,"ticks":1},
          {"type":"tickMark","x1":0.5,"y1":0.22,"x2":0.82,"y2":0.82,"ticks":1},
          {"type":"angleArc","vx":0.5,"vy":0.22,"startAngle":20,"sweepAngle":120,"r":0.1,"label":"120°"},
          {"type":"angleArc","vx":0.2,"vy":0.82,"startAngle":0,"sweepAngle":60,"r":0.08,"label":"?"}
        ],
        "auxiliaryLines": []
      }
    }
  ]
}
''';

    final exercises = service.extractGeneratedExercisesFromContent(
      raw,
      questionId: 'q-exterior-diagram',
      sourceQuestionText:
          r'在 \(\triangle ABC\) 中，若 \(AB=AC\)，且 \(\angle A=40^\circ\)，求 \(\angle B\)。',
    );

    expect(exercises.map((exercise) => exercise.id),
        isNot(contains('bad-exterior')));
    final hard =
        exercises.singleWhere((exercise) => exercise.difficulty == '提高');
    expect(hard.question, contains('外角'));
    expect(hard.question, contains(r'\(\angle DAC=120^\circ\)'));

    final labels = _diagramLabels(hard.diagramData!);
    final a = labels['A']!;
    final b = labels['B']!;
    final d = labels['D']!;
    final ab = _Vector(b.x - a.x, b.y - a.y);
    final ad = _Vector(d.x - a.x, d.y - a.y);
    final cross = (ab.x * ad.y - ab.y * ad.x).abs();
    final dot = ab.x * ad.x + ab.y * ad.y;

    expect(cross, lessThan(0.001));
    expect(dot, lessThan(0));
    final externalArc = (hard.diagramData!['elements'] as List)
        .whereType<Map>()
        .where((element) => element['type'] == 'angleArc')
        .singleWhere((element) => element['label'] == '120°');
    expect(externalArc['role'], 'external');
  });
  test('service preserves valid quadratic root generated exercises', () {
    final service = AiAnalysisService.fake();
    const raw = r'''
{
  "subject": "数学",
  "finalAnswer": "\(x=\pm2\)",
  "steps": ["\(x^2=4\)", "\(x=\pm2\)"],
  "aiTags": ["一元二次", "平方根"],
  "knowledgePoints": ["由 \(x^2=a\) 求正负根"],
  "mistakeReason": "漏负根",
  "studyAdvice": "注意正负根",
  "generatedExercises": [
    {"id": "good1", "difficulty": "同级", "question": "已知 \(x^2=16\)，求 \(x\) 的值。", "options": ["A. \(4\)", "B. \(-4\)", "C. \(\pm4\)", "D. \(16\)"], "answer": "C", "explanation": "由 \(x^2=16\) 得 \(x=\pm4\)。"}
  ]
}
''';

    final exercises = service.extractGeneratedExercisesFromContent(
      raw,
      questionId: 'q-valid-quadratic',
      sourceQuestionText: r'已知 \(x^2+1=5\)，求 \(x\) 的值。',
    );

    expect(exercises.length, 3);
    expect(exercises.map((exercise) => exercise.id), contains('good1'));
    expect(exercises[1].id, 'good1');
    expect(exercises.first.question, contains('x^2'));
  });

  test(
      'service falls back to right triangle length exercises for pythagorean source',
      () {
    final service = AiAnalysisService.fake();
    const raw = r'''
{
  "subject": "数学",
  "finalAnswer": "5",
  "steps": ["先用勾股定理求 AC", "再结合等长关系求 BC"],
  "aiTags": ["直角三角形", "勾股定理"],
  "knowledgePoints": ["勾股定理", "线段长度"],
  "mistakeReason": "容易把中间量当答案",
  "studyAdvice": "先找直角三角形",
  "generatedExercises": [
    {"id": "bad1", "difficulty": "简单", "question": "解方程 x+1=4，求 x 的值", "options": ["A. 1", "B. 2", "C. 3", "D. 4"], "answer": "C", "explanation": "移项得 x=3"},
    {"id": "bad2", "difficulty": "同级", "question": "一个圆的半径为 5，求面积", "options": ["A. 10π", "B. 25π", "C. 50π", "D. 100π"], "answer": "B", "explanation": "圆面积公式"},
    {"id": "bad3", "difficulty": "提高", "question": "函数 f(x)=x^2，求 f(3)", "options": ["A. 3", "B. 6", "C. 9", "D. 12"], "answer": "C", "explanation": "代入"}
  ]
}
''';

    final exercises = service.extractGeneratedExercisesFromContent(
      raw,
      questionId: 'q-right-triangle',
      sourceQuestionText:
          r'如图，\(\angle ABC=90^\circ\)，\(\angle ADC=90^\circ\)，\(BD=BC\)，\(AD=6\)，\(DC=8\)，求 \(BC\) 的长度。',
    );

    expect(exercises.length, 3);
    expect(exercises.map((exercise) => exercise.id), isNot(contains('bad1')));
    expect(exercises.map((exercise) => exercise.question).join(' '),
        contains('直角'));
    expect(exercises.map((exercise) => exercise.explanation).join(' '),
        contains('勾股'));
    expect(exercises.every((exercise) => exercise.diagramData != null), isTrue);
  });

  test('service rejects diagramData exercise when it drifts from source topic',
      () {
    final service = AiAnalysisService.fake();
    const raw = r'''
{
  "subject": "数学",
  "finalAnswer": "\(\frac{25\pi}{2}\)",
  "steps": ["半圆面积"],
  "aiTags": ["半圆", "面积"],
  "knowledgePoints": ["半圆面积"],
  "mistakeReason": "漏乘二分之一",
  "studyAdvice": "先判断目标区域",
  "generatedExercises": [
    {"id": "bad-diagram", "difficulty": "简单", "question": "解方程 x+1=4，求 x 的值", "options": ["A. 1", "B. 2", "C. 3", "D. 4"], "answer": "C", "explanation": "移项得 x=3", "diagramData": {"elements": [{"type": "line", "x1": 0.1, "y1": 0.2, "x2": 0.8, "y2": 0.2}]}}
  ]
}
''';

    final exercises = service.extractGeneratedExercisesFromContent(
      raw,
      questionId: 'q-diagram-quality-gate',
      sourceQuestionText: r'如图，一个半径为 5 cm 的圆，求阴影半圆面积。',
    );

    expect(exercises.length, 3);
    expect(exercises.map((exercise) => exercise.id),
        isNot(contains('bad-diagram')));
    expect(exercises.map((exercise) => exercise.question).join(' '),
        contains('半圆'));
  });

  test('service rejects equation drift for circle area source and falls back',
      () {
    final service = AiAnalysisService.fake();
    const raw = r'''
{
  "subject": "数学",
  "finalAnswer": "\(\frac{25\pi}{2}\)",
  "steps": ["整圆面积是 \(25\pi\)", "半圆面积是 \(\frac{25\pi}{2}\)"],
  "aiTags": ["圆", "面积", "半圆"],
  "knowledgePoints": ["圆面积", "半圆面积"],
  "mistakeReason": "漏乘二分之一",
  "studyAdvice": "先判断目标区域是整圆还是部分圆",
  "generatedExercises": [
    {"id": "bad1", "difficulty": "简单", "question": "解方程 x+1=4，求 x 的值", "options": ["A. 1", "B. 2", "C. 3", "D. 4"], "answer": "C", "explanation": "移项得 x=3"},
    {"id": "bad2", "difficulty": "同级", "question": "解方程 2x=8", "options": ["A. 2", "B. 3", "C. 4", "D. 5"], "answer": "C", "explanation": "除以 2"},
    {"id": "bad3", "difficulty": "提高", "question": "解方程 3x+2=11", "options": ["A. 2", "B. 3", "C. 4", "D. 5"], "answer": "B", "explanation": "移项"}
  ]
}
''';

    final exercises = service.extractGeneratedExercisesFromContent(
      raw,
      questionId: 'q-circle-area',
      sourceQuestionText: r'如图，一个半径为 5 cm 的圆，求阴影半圆面积。',
    );

    expect(exercises.length, 3);
    expect(exercises.map((exercise) => exercise.id), isNot(contains('bad1')));
    expect(exercises.first.question, contains('半圆'));
    expect(exercises.map((exercise) => exercise.question).join(' '),
        isNot(contains('解方程')));
    expect(exercises.map((exercise) => exercise.question).join(' '),
        isNot(contains('圆环')));
  });

  test('service preserves valid circle area generated exercises', () {
    final service = AiAnalysisService.fake();
    const raw = r'''
{
  "subject": "数学",
  "finalAnswer": "\(\frac{25\pi}{2}\)",
  "steps": ["整圆面积是 \(25\pi\)", "半圆面积是 \(\frac{25\pi}{2}\)"],
  "aiTags": ["圆", "面积", "半圆"],
  "knowledgePoints": ["圆面积", "半圆面积"],
  "mistakeReason": "漏乘二分之一",
  "studyAdvice": "先判断目标区域是整圆还是部分圆",
  "generatedExercises": [
    {"id": "good-circle", "difficulty": "同级", "question": "一个半圆的半径为 6 cm，求半圆面积。", "options": ["A. \(12\pi\)", "B. \(18\pi\)", "C. \(36\pi\)", "D. \(72\pi\)"], "answer": "B", "explanation": "整圆面积为 \(36\pi\)，半圆面积是一半，所以是 \(18\pi\)。", "diagramData": {"elements": [{"type": "arc", "cx": 0.5, "cy": 0.6, "r": 0.3, "startAngle": 180, "sweepAngle": 180}]}}
  ]
}
''';

    final exercises = service.extractGeneratedExercisesFromContent(
      raw,
      questionId: 'q-circle-valid',
      sourceQuestionText: r'如图，一个半径为 5 cm 的圆，求阴影半圆面积。',
    );

    expect(exercises.length, 3);
    expect(exercises.map((exercise) => exercise.id), contains('good-circle'));
    expect(exercises[1].id, 'good-circle');
    expect(exercises.map((exercise) => exercise.question).join(' '),
        contains('半圆'));
  });

  test('service does not treat framed semicircle-only source as composite area',
      () {
    final service = AiAnalysisService.fake();
    const raw = r'''
{
  "subject": "数学",
  "finalAnswer": "\(25\pi/2\)",
  "steps": ["左斜边是半圆直径", "半圆面积为 \(25\pi/2\)"],
  "aiTags": ["半圆面积", "勾股定理"],
  "knowledgePoints": ["半圆面积"],
  "mistakeReason": "直径读错",
  "studyAdvice": "先确认半圆直径",
  "generatedExercises": [
    {"id": "semi-only", "difficulty": "同级", "question": "如图，外框上边长为 4，下边长为 10，右边高为 8，左侧斜边为半圆直径。求该半圆的面积。", "options": ["A. \(25\pi/2\)", "B. \(25\pi\)", "C. \(50\pi\)", "D. \(10\pi\)"], "answer": "A", "explanation": "水平差为 6，高为 8，直径为 10，半圆面积为 \(25\pi/2\)。", "diagramData": {"elements": [{"type": "arc", "cx": 0.5, "cy": 0.5, "r": 0.3, "startAngle": 180, "sweepAngle": 180}]}}
  ]
}
''';

    final exercises = service.extractGeneratedExercisesFromContent(
      raw,
      questionId: 'q-framed-semicircle-only',
      sourceQuestionText: '如图，外框上边长为 3，下边长为 7，右边高为 10，左侧斜边为半圆直径，求该半圆的面积。',
    );

    expect(exercises.length, 3);
    expect(exercises.map((exercise) => exercise.id), contains('semi-only'));
    expect(exercises[1].id, 'semi-only');
    expect(exercises[1].question, contains('求该半圆的面积'));
  });

  test(
      'service falls back to pythagorean semicircle exercises for framed semicircle source',
      () {
    final service = AiAnalysisService.fake();
    const raw = r'''
{
  "subject": "数学",
  "finalAnswer": "\(\frac{29\pi}{2}\)",
  "steps": ["左斜边是半圆直径", "由勾股定理求出直径平方", "半圆面积为 \(\frac{29\pi}{2}\)"],
  "aiTags": ["半圆面积", "勾股定理"],
  "knowledgePoints": ["半圆面积", "勾股定理"],
  "mistakeReason": "直径读错",
  "studyAdvice": "先由水平差和高求直径",
  "generatedExercises": []
}
''';

    final exercises = service.extractGeneratedExercisesFromContent(
      raw,
      questionId: 'q-framed-semicircle-fallback',
      sourceQuestionText: '如图，外框上边长为 3，下边长为 7，右边高为 10，左侧斜边为半圆直径，求该半圆的面积。',
    );

    expect(exercises.length, 3);
    expect(exercises.first.question, contains('上边长'));
    expect(exercises.first.question, contains('左侧斜边为半圆直径'));
    expect(exercises.map((exercise) => exercise.explanation).join(' '),
        contains('勾股'));
    expect(exercises.map((exercise) => exercise.question).join(' '),
        isNot(contains('半径为 4')));
    expect(exercises.every((exercise) => exercise.diagramData != null), isTrue);
    final diagramTexts = (exercises.first.diagramData!['elements'] as List)
        .whereType<Map>()
        .where((element) => element['type'] == 'text')
        .map((element) => element['text'])
        .join(' ');
    expect(diagramTexts, contains('求半圆面积'));
    expect(diagramTexts, isNot(contains('求此区域')));
  });

  test('service parameterizes framed semicircle fallback from source numbers',
      () {
    final service = AiAnalysisService.fake();
    const raw = r'''
{
  "subject": "数学",
  "finalAnswer": "\(\frac{25\pi}{2}\)",
  "steps": ["左侧斜边是半圆直径", "由水平差和高求直径", "求半圆面积"],
  "aiTags": ["半圆面积", "勾股定理"],
  "knowledgePoints": ["半圆面积", "勾股定理"],
  "mistakeReason": "直径读错",
  "studyAdvice": "先确认上下边和高",
  "generatedExercises": []
}
''';

    final exercises = service.extractGeneratedExercisesFromContent(
      raw,
      questionId: 'q-param-framed-semicircle',
      sourceQuestionText: '如图，外框上边长为 6，下边长为 14，右边高为 15，左侧斜边为半圆直径，求该半圆的面积。',
    );

    expect(exercises.length, 3);
    expect(exercises[1].question, contains('上边长为 6'));
    expect(exercises[1].question, contains('下边长为 14'));
    expect(exercises[1].question, contains('右边高为 15'));
    expect(exercises[1].options?[1], contains('289π/8'));
    expect(exercises[1].answer, 'B');
    expect(exercises[1].explanation, contains('水平差为 8'));
    expect(exercises[1].explanation, contains('直径平方为 289'));
    final diagramTexts = (exercises[1].diagramData!['elements'] as List)
        .whereType<Map>()
        .where((element) => element['type'] == 'text')
        .map((element) => element['text'])
        .join(' ');
    expect(diagramTexts, contains('6'));
    expect(diagramTexts, contains('14'));
    expect(diagramTexts, contains('15'));
    expect(diagramTexts, contains('求半圆面积'));
  });

  test('service rejects solid geometry drift for composite semicircle area',
      () {
    final service = AiAnalysisService.fake();
    const raw = r'''
{
  "subject": "数学",
  "finalAnswer": "\(25\pi\)",
  "steps": ["半圆面积公式为 \(S=\frac{1}{2}\pi r^2\)", "代入 \(r=5\)，得 \(S=\frac{25\pi}{2}\times2=25\pi\)"],
  "aiTags": ["半圆", "面积", "梯形"],
  "knowledgePoints": ["半圆面积", "切线关系"],
  "mistakeReason": "混淆半圆和整圆面积",
  "studyAdvice": "先确认目标区域",
  "generatedExercises": [
    {"id": "bad-solid", "difficulty": "简单", "question": "圆锥底面半径为 r=2，高为 h=3，则体积 V 为", "options": ["A. \(4\pi\)", "B. \(8\pi\)", "C. \(12\pi\)", "D. \(6\pi\)"], "answer": "A", "explanation": "\(V=\frac{1}{3}\pi r^2h=4\pi\)"}
  ]
}
''';

    final exercises = service.extractGeneratedExercisesFromContent(
      raw,
      questionId: 'q-semicircle-no-solid',
      sourceQuestionText: '如图，上边长为3，下边长为7，右边高为10，半圆以左侧斜边为直径，求外边界与半圆弧之间区域的面积。',
    );

    expect(exercises.length, 3);
    expect(
        exercises.map((exercise) => exercise.id), isNot(contains('bad-solid')));
    expect(exercises.map((exercise) => exercise.question).join(' '),
        isNot(contains('圆锥')));
    expect(exercises.map((exercise) => exercise.question).join(' '),
        isNot(contains('体积')));
    expect(exercises.first.question, contains('上边'));
    expect(exercises.first.question, contains('半圆'));
  });

  test('service replaces invalid composite semicircle exercise by slot', () {
    final service = AiAnalysisService.fake();
    const raw = r'''
{
  "subject": "数学",
  "finalAnswer": "13\pi",
  "steps": ["直径为 2\sqrt{26}", "半圆面积为 13\pi"],
  "aiTags": ["半圆", "面积", "勾股定理"],
  "knowledgePoints": ["半圆面积", "勾股定理"],
  "mistakeReason": "读图假设需核对",
  "studyAdvice": "先确认直径",
  "generatedExercises": [
    {"id": "good-simple", "difficulty": "简单", "question": "如图，上边长为 2，下边长为 5，右边高为 4，半圆以左侧斜边为直径。求右侧外边界与半圆弧之间区域的面积。", "options": ["A. 14-25π/8", "B. 14-25π/4", "C. 20-25π/8", "D. 14-5π/2"], "answer": "A", "explanation": "外边界面积为 14，半圆面积为 25π/8，目标面积为 14-25π/8。", "diagramData": {"elements": [{"type": "line", "x1": 0.1, "y1": 0.2, "x2": 0.8, "y2": 0.2}]}},
    {"id": "good-same", "difficulty": "同级", "question": "如图，上边长为 3，下边长为 7，右边高为 10，半圆以左侧斜边为直径。求右侧外边界与半圆弧之间区域的面积。", "options": ["A. 50-29π", "B. 50-29π/2", "C. 40-29π/2", "D. 50-58π"], "answer": "B", "explanation": "外边界面积为 50，半圆面积为 29π/2，目标面积为 50-29π/2。", "diagramData": {"elements": [{"type": "line", "x1": 0.1, "y1": 0.2, "x2": 0.8, "y2": 0.2}]}},
    {"id": "bad-conflict", "difficulty": "提高", "question": "如图，上边长为 4，下边长为 10，右边高为 8，半圆以左侧斜边为直径。求右侧外边界与半圆弧之间区域的面积。", "options": ["A. 56-50π", "B. 48-25π", "C. 56-25π", "D. 56-25π/2"], "answer": "C", "explanation": "外边界面积为 56，半圆面积为 25π/2。注意这里目标面积应为 56-25π/2，因此答案为 D。", "diagramData": {"elements": [{"type": "line", "x1": 0.1, "y1": 0.2, "x2": 0.8, "y2": 0.2}]}}
  ]
}
''';

    final exercises = service.extractGeneratedExercisesFromContent(
      raw,
      questionId: 'q-self-invalidating',
      sourceQuestionText: '如图，上边长为3，下边长为7，右边高为10，半圆以左侧斜边为直径，求外边界与半圆弧之间区域的面积。',
    );

    expect(exercises.length, 3);
    expect(exercises.map((exercise) => exercise.id), contains('good-simple'));
    expect(exercises.map((exercise) => exercise.id), contains('good-same'));
    expect(exercises.map((exercise) => exercise.id),
        isNot(contains('bad-conflict')));
    expect(exercises[2].question, contains('上边长为 4'));
    expect(
      exercises.map((exercise) => exercise.explanation).join(' '),
      isNot(contains('选项中没有')),
    );
    expect(exercises.every((exercise) => exercise.diagramData != null), isTrue);
  });

  test(
      'service rejects generated exercise when explanation states different correct option',
      () {
    final service = AiAnalysisService.fake();
    const raw = r'''
{
  "subject": "数学",
  "finalAnswer": "50-\frac{29\pi}{2}",
  "steps": ["外框面积为 50。", "半圆面积为 29\pi/2。"],
  "aiTags": ["半圆面积", "组合图形"],
  "knowledgePoints": ["整体减部分"],
  "mistakeReason": "目标区域读错",
  "studyAdvice": "先确认目标区域",
  "generatedExercises": [
    {"id": "bad-correct-option", "difficulty": "同级", "question": "如图，上边长为 5，下边长为 11，右边高为 8，半圆以左侧斜边为直径。求外框内、半圆外的区域面积。", "options": ["A. 64-25π", "B. 64-50π", "C. 128-25π", "D. 64-25π/2"], "answer": "A", "explanation": "外框面积为 64，半圆面积为 25π/2，因此剩余面积为 64-25π/2，正确选项为 D。", "diagramData": {"elements": [{"type": "line", "x1": 0.1, "y1": 0.2, "x2": 0.8, "y2": 0.2}]}}
  ]
}
''';

    final exercises = service.extractGeneratedExercisesFromContent(
      raw,
      questionId: 'q-correct-option-conflict',
      sourceQuestionText:
          '图中外框由上水平边、右竖边、下水平边和左斜边围成，上水平边长为 3，下水平边长为 7，右竖边高为 10；左斜边作为半圆的直径，半圆位于外框内。求外框内、半圆外的括号状区域面积。',
    );

    expect(exercises.length, 3);
    expect(exercises.map((exercise) => exercise.id),
        isNot(contains('bad-correct-option')));
    expect(exercises[1].answer, 'B');
    expect(exercises[1].question, contains('上边长为 3'));
  });

  test(
      'service rejects generated exercise when answer option value conflicts with explanation conclusion',
      () {
    final service = AiAnalysisService.fake();
    const raw = r'''
{
  "subject": "数学",
  "finalAnswer": "50-\frac{29\pi}{2}",
  "steps": ["外框面积为 50。", "半圆面积为 29\pi/2。"],
  "aiTags": ["半圆面积", "组合图形"],
  "knowledgePoints": ["整体减部分"],
  "mistakeReason": "目标区域读错",
  "studyAdvice": "先确认目标区域",
  "generatedExercises": [
    {"id": "bad-value-conflict", "difficulty": "同级", "question": "如图，上边长为 5，下边长为 11，右边高为 8，半圆以左侧斜边为直径。求外框内、半圆外的区域面积。", "options": ["A. 64-25π", "B. 64-50π", "C. 128-25π", "D. 64-25π/2"], "answer": "A", "explanation": "外框面积为 64，半圆面积为 25π/2，因此剩余面积为 64-25π/2。", "diagramData": {"elements": [{"type": "line", "x1": 0.1, "y1": 0.2, "x2": 0.8, "y2": 0.2}]}}
  ]
}
''';

    final exercises = service.extractGeneratedExercisesFromContent(
      raw,
      questionId: 'q-option-value-conflict',
      sourceQuestionText:
          '图中外框由上水平边、右竖边、下水平边和左斜边围成，上水平边长为 3，下水平边长为 7，右竖边高为 10；左斜边作为半圆的直径，半圆位于外框内。求外框内、半圆外的括号状区域面积。',
    );

    expect(exercises.length, 3);
    expect(exercises.map((exercise) => exercise.id),
        isNot(contains('bad-value-conflict')));
    expect(exercises[1].answer, 'B');
    expect(exercises[1].options?[1], contains(r'50-\frac{29\pi}{2}'));
  });

  test('service rejects semicircle-only target for composite area source', () {
    final service = AiAnalysisService.fake();
    const raw = r'''
{
  "subject": "数学",
  "finalAnswer": "50-\frac{29\pi}{2}",
  "steps": ["外框面积为 50。", "半圆面积为 29\pi/2。"],
  "aiTags": ["半圆面积", "勾股定理", "组合图形", "面积差"],
  "knowledgePoints": ["半圆面积", "整体减部分"],
  "mistakeReason": "需先确认目标区域",
  "studyAdvice": "先求外框面积，再减半圆面积",
  "generatedExercises": [
    {"id": "bad-target", "difficulty": "简单", "question": "如图，外框上水平边长为 4，下水平边长为 10，右侧竖直边高为 8，左斜边为半圆直径。求该半圆的面积。", "options": ["A. 25π/2", "B. 25π", "C. 50π", "D. 10π"], "answer": "A", "explanation": "水平差为 6，高为 8，半圆直径为 10，半圆面积为 25π/2。", "diagramData": {"elements": [{"type": "polygon", "points": [[0.3,0.2],[0.8,0.2],[0.8,0.8],[0.1,0.8]]}]}},
    {"id": "good-same", "difficulty": "同级", "question": "如图，外框上水平边长为 5，下水平边长为 11，右侧竖直边高为 8，左斜边为半圆直径。求外框内、半圆外的括号状区域面积。", "options": ["A. 64-25π", "B. 64-25π/2", "C. 88-25π/2", "D. 64-50π/2"], "answer": "B", "explanation": "外框面积为 64。由勾股定理得半圆直径为 10，半径为 5，半圆面积为 25π/2，目标面积为 64-25π/2。", "diagramData": {"elements": [{"type": "polygon", "points": [[0.3,0.2],[0.8,0.2],[0.8,0.8],[0.1,0.8]]}]}},
    {"id": "good-hard", "difficulty": "提高", "question": "如图，外框上水平边长为 5，下水平边长为 13，右侧竖直边高为 15，左斜边为半圆直径。求外框内、半圆外的括号状区域面积。", "options": ["A. 135-289π/4", "B. 135-289π/8", "C. 90-289π/8", "D. 135-17π/2"], "answer": "B", "explanation": "外框面积为 135。斜边直径为 17，半径为 17/2，半圆面积为 289π/8，所以目标面积为 135-289π/8。", "diagramData": {"elements": [{"type": "polygon", "points": [[0.3,0.2],[0.8,0.2],[0.8,0.8],[0.1,0.8]]}]}}
  ]
}
''';

    final exercises = service.extractGeneratedExercisesFromContent(
      raw,
      questionId: 'q-target-consistency',
      sourceQuestionText:
          '图中外框由上水平边、右竖边、下水平边和左斜边围成，上水平边长为 3，下水平边长为 7，右竖边高为 10；左斜边作为半圆的直径，半圆位于外框内。求外框内、半圆外的括号状区域面积。',
    );

    expect(exercises.length, 3);
    expect(exercises.map((exercise) => exercise.id),
        isNot(contains('bad-target')));
    expect(exercises.map((exercise) => exercise.id), contains('good-same'));
    expect(exercises.map((exercise) => exercise.id), contains('good-hard'));
    expect(exercises.first.question, contains('半圆弧之间区域'));
    expect(exercises.every((exercise) => exercise.diagramData != null), isTrue);
  });

  test('service replaces composite semicircle exercise missing diagramData',
      () {
    final service = AiAnalysisService.fake();
    const raw = r'''
{
  "subject": "数学",
  "finalAnswer": "50-\frac{29\pi}{2}",
  "steps": ["外框面积为 50。", "半圆面积为 29\pi/2。"],
  "aiTags": ["半圆面积", "组合图形"],
  "knowledgePoints": ["整体减部分"],
  "mistakeReason": "目标区域读错",
  "studyAdvice": "先确认目标区域",
  "generatedExercises": [
    {"id": "missing-diagram", "difficulty": "简单", "question": "如图，上边长为 2，下边长为 5，右边高为 4，半圆以左侧斜边为直径。求右侧外边界与半圆弧之间区域的面积。", "options": ["A. 14-25π/8", "B. 14-25π/4", "C. 20-25π/8", "D. 14-5π/2"], "answer": "A", "explanation": "外边界面积为 14，半圆面积为 25π/8，目标面积为 14-25π/8。"},
    {"id": "valid-same", "difficulty": "同级", "question": "如图，上边长为 3，下边长为 7，右边高为 10，半圆以左侧斜边为直径。求右侧外边界与半圆弧之间区域的面积。", "options": ["A. 50-29π", "B. 50-29π/2", "C. 40-29π/2", "D. 50-58π"], "answer": "B", "explanation": "外边界面积为 50，半圆面积为 29π/2，目标面积为 50-29π/2。", "diagramData": {"elements": [{"type": "line", "x1": 0.1, "y1": 0.2, "x2": 0.8, "y2": 0.2}]}}
  ]
}
''';

    final exercises = service.extractGeneratedExercisesFromContent(
      raw,
      questionId: 'q-composite-missing-diagram',
      sourceQuestionText:
          '图中外框由上水平边、右竖边、下水平边和左斜边围成，上水平边长为 3，下水平边长为 7，右竖边高为 10；左斜边作为半圆的直径，半圆位于外框内。求外框内、半圆外的括号状区域面积。',
    );

    expect(exercises.length, 3);
    expect(exercises.map((exercise) => exercise.id),
        isNot(contains('missing-diagram')));
    expect(exercises.map((exercise) => exercise.id), contains('valid-same'));
    expect(exercises.every((exercise) => exercise.diagramData != null), isTrue);
  });

  test(
      'service preserves composite semicircle exercises with outer frame wording',
      () {
    final service = AiAnalysisService.fake();
    const raw = r'''
{
  "subject": "数学",
  "finalAnswer": "50-\frac{29\pi}{2}",
  "steps": ["外框面积为 50。", "半圆面积为 29\pi/2。"],
  "aiTags": ["半圆面积", "勾股定理", "组合图形", "面积差"],
  "knowledgePoints": ["半圆面积", "整体减部分"],
  "mistakeReason": "需先确认半圆直径",
  "studyAdvice": "先求外框面积，再减半圆面积",
  "generatedExercises": [
    {"id": "ai-simple", "difficulty": "简单", "question": "如图，外框上水平边长为 4，下水平边长为 10，右侧竖直边高为 8，左斜边为半圆直径。求外框内、半圆外的括号状区域面积。", "options": ["A. 56-25π/2", "B. 56-25π", "C. 80-25π/2", "D. 40-25π/2"], "answer": "A", "explanation": "外框面积为 56。半圆直径由水平差和竖直差用勾股定理求得为 10，半圆面积为 25π/2，所以剩余面积为 56-25π/2。", "diagramData": {"elements": [{"type": "polygon", "points": [[0.3,0.2],[0.8,0.2],[0.8,0.8],[0.1,0.8]]}]}},
    {"id": "ai-same", "difficulty": "同级", "question": "如图，外框上水平边长为 5，下水平边长为 11，右侧竖直边高为 8，左斜边为半圆直径。求外框内、半圆外的括号状区域面积。", "options": ["A. 64-25π", "B. 64-25π/2", "C. 88-25π/2", "D. 64-50π/2"], "answer": "B", "explanation": "外框面积为 64。由勾股定理得半圆直径为 10，半径为 5，半圆面积为 25π/2，目标面积为 64-25π/2。", "diagramData": {"elements": [{"type": "polygon", "points": [[0.3,0.2],[0.8,0.2],[0.8,0.8],[0.1,0.8]]}]}},
    {"id": "ai-hard", "difficulty": "提高", "question": "如图，外框上水平边长为 5，下水平边长为 13，右侧竖直边高为 15，左斜边为半圆直径。求外框内、半圆外的括号状区域面积。", "options": ["A. 135-289π/4", "B. 135-289π/8", "C. 90-289π/8", "D. 135-17π/2"], "answer": "B", "explanation": "外框面积为 135。斜边直径为 17，半径为 17/2，半圆面积为 289π/8，所以目标面积为 135-289π/8。", "diagramData": {"elements": [{"type": "polygon", "points": [[0.3,0.2],[0.8,0.2],[0.8,0.8],[0.1,0.8]]}]}}
  ]
}
''';

    final exercises = service.extractGeneratedExercisesFromContent(
      raw,
      questionId: 'q-outer-frame-wording',
      sourceQuestionText:
          '图中外框由上水平边、右竖边、下水平边和左斜边围成，上水平边长为 3，下水平边长为 7，右竖边高为 10；左斜边作为半圆的直径，半圆位于外框内。求外框内、半圆外的括号状区域面积。',
    );

    expect(exercises.map((exercise) => exercise.id),
        <String>['ai-simple', 'ai-same', 'ai-hard']);
    expect(exercises.every((exercise) => exercise.diagramData != null), isTrue);
  });

  // Phase 13-2：generateVariants 独立变式题生成测试。
  group('generateVariants', () {
    test('Fake 服务无 AI 配置时走兜底题，返回 3 道练习题', () async {
      final service = AiAnalysisService.fake();
      final exercises = await service.generateVariants(
        questionId: 'q-variant-1',
        sourceQuestionText: '解方程 x + 2 = 5',
        subjectName: '数学',
      );
      expect(exercises.length, 3);
      // 兜底题难度档依次为 简单 / 同级 / 提高。
      expect(exercises.map((e) => e.difficulty).toList(),
          <String>['简单', '同级', '提高']);
      expect(exercises.every((e) => e.question.isNotEmpty), isTrue);
      expect(exercises.every((e) => e.options?.length == 4), isTrue);
    });

    test('圆面积源题生成的兜底变式题包含 diagramData', () async {
      final service = AiAnalysisService.fake();
      final exercises = await service.generateVariants(
        questionId: 'q-circle',
        sourceQuestionText: '一个圆的半径为 5，求圆的面积。',
        subjectName: '数学',
      );
      expect(exercises.length, 3);
      // 圆面积兜底题应包含几何图。
      expect(exercises.every((e) => e.diagramData != null), isTrue);
    });

    test('题干为空时仍能返回兜底题（Fake 路径不依赖文本）', () async {
      final service = AiAnalysisService.fake();
      final exercises = await service.generateVariants(
        questionId: 'q-empty',
        sourceQuestionText: '',
        subjectName: '数学',
      );
      // 兜底题 generic 路径返回 3 道。
      expect(exercises.length, 3);
    });

    test('buildVariantsPromptForTest 包含 anchor 与漂移检测要求', () {
      final service = AiAnalysisService.fake();
      final prompt = service.buildVariantsPromptForTest(
        sourceQuestionText: '直角三角形两直角边长分别为 3 和 4，求斜边长。',
        subjectName: '数学',
      );
      // 应包含举一反三锚点（直角三角形长度域）。
      expect(prompt, contains('domain=planeGeometryLength'));
      expect(prompt, contains('object=rightTriangle'));
      expect(prompt, contains('pythagorean'));
      // 应包含漂移检测要求。
      expect(prompt, contains('简单、同级、提高'));
      expect(prompt, contains('同一知识点、同一题型、同一核心解法'));
      // 应包含几何题 diagramData 要求。
      expect(prompt, contains('diagramData'));
      // 应包含 JSON 返回格式说明。
      expect(prompt, contains('"generatedExercises"'));
    });
  });
}
