import 'package:flutter_test/flutter_test.dart';
import 'package:smart_wrong_notebook/src/data/remote/ai/ai_analysis_response_contract.dart';

void main() {
  group('legacy V1 compatibility', () {
    test('normalizes omitted optional analysis fields without inventing trust', () {
      final result = AiAnalysisResponseContract.normalize({
        'finalAnswer': '42',
        'steps': ['列式'],
      });

      expect(result['subject'], '');
      expect(result['aiTags'], isEmpty);
      expect(result['knowledgePoints'], isEmpty);
      expect(result['steps'], ['列式']);
      expect(result['schemaVersion'], 1);
      expect(result['promptVersion'], 'legacy-v1');
      expect(result['confidence'], isNull);
      expect(result['isLegacyContract'], isTrue);
      expect(result['standardAnswer'], '42');
      expect(result['solutionSteps'], ['列式']);
    });

    test('rejects non-string AI list members', () {
      expect(
        () => AiAnalysisResponseContract.normalize({
          'finalAnswer': '42',
          'steps': ['第一步', 2],
        }),
        throwsFormatException,
      );
    });

    test('rejects an empty AI analysis response', () {
      expect(
        () => AiAnalysisResponseContract.normalize({}),
        throwsFormatException,
      );
    });

    test('can disable legacy compatibility at strict boundary', () {
      expect(
        () => AiAnalysisResponseContract.normalize(
          {'finalAnswer': '42'},
          allowLegacy: false,
        ),
        throwsFormatException,
      );
    });
  });

  group('strict V2 contract', () {
    test('accepts complete V2 payload and publishes legacy aliases', () {
      final result = AiAnalysisResponseContract.normalize(_validV2());

      expect(result['schemaVersion'], 2);
      expect(result['isLegacyContract'], isFalse);
      expect(result['finalAnswer'], '3');
      expect(result['steps'], ['移项得 x=3']);
      expect(result['reconstructedQuestionText'], '解方程 x+1=4');
      expect(result['mistakeCategory'], 'calculation');
    });

    test('rejects unsupported schema version', () {
      final payload = _validV2()..['schemaVersion'] = 3;
      expect(
        () => AiAnalysisResponseContract.normalize(payload),
        throwsFormatException,
      );
    });

    test('rejects missing field-level confidence', () {
      final payload = _validV2();
      final confidence = Map<String, dynamic>.from(
        payload['confidence'] as Map<String, dynamic>,
      );
      final fields = Map<String, dynamic>.from(
        confidence['fields'] as Map<String, dynamic>,
      )..remove('standardAnswer');
      payload['confidence'] = <String, dynamic>{
        ...confidence,
        'fields': fields,
      };

      expect(
        () => AiAnalysisResponseContract.normalize(payload),
        throwsFormatException,
      );
    });

    test('rejects confidence outside 0 to 1', () {
      final payload = _validV2();
      payload['confidence'] = <String, dynamic>{
        'overall': 1.2,
        'fields': (payload['confidence'] as Map)['fields'],
      };
      expect(
        () => AiAnalysisResponseContract.normalize(payload),
        throwsFormatException,
      );
    });

    test('rejects deterministic mistake diagnosis without student answer', () {
      final payload = _validV2()
        ..['studentAnswer'] = ''
        ..['mistakeCategory'] = 'careless';
      expect(
        () => AiAnalysisResponseContract.normalize(payload),
        throwsFormatException,
      );
    });

    test('rejects mistake diagnosis without student-answer evidence', () {
      final payload = _validV2()
        ..['evidence'] = <Map<String, dynamic>>[
          {
            'field': 'mistakeReason',
            'source': 'modelInference',
            'quote': '可能算错',
            'explanation': '没有引用学生原步骤',
          },
        ];
      expect(
        () => AiAnalysisResponseContract.normalize(payload),
        throwsFormatException,
      );
    });

    test('rejects malformed generated exercise', () {
      final payload = _validV2();
      final exercise = Map<String, dynamic>.from(
        (payload['generatedExercises'] as List).first as Map,
      )..['options'] = <String>['A. 1', 'B. 2'];
      payload['generatedExercises'] = <Map<String, dynamic>>[exercise];
      expect(
        () => AiAnalysisResponseContract.normalize(payload),
        throwsFormatException,
      );
    });
  });
}

Map<String, dynamic> _validV2() => <String, dynamic>{
      'schemaVersion': 2,
      'promptVersion': 'analysis-v2.0.0',
      'modelName': 'fixture-model',
      'subject': '数学',
      'confidence': <String, dynamic>{
        'overall': 0.88,
        'fields': <String, dynamic>{
          'normalizedQuestion': 0.95,
          'studentAnswer': 0.82,
          'standardAnswer': 0.96,
          'solutionSteps': 0.92,
          'knowledgePoints': 0.86,
          'generatedExercises': 0.78,
        },
      },
      'uncertainties': <Map<String, dynamic>>[
        {
          'field': 'studentAnswer',
          'description': '末尾数字略模糊',
          'suggestedAction': '请核对原图',
        },
      ],
      'evidence': <Map<String, dynamic>>[
        {
          'field': 'mistakeReason',
          'source': 'studentAnswer',
          'quote': 'x=4+1',
          'explanation': '移项时符号没有改变',
          'stepIndex': 0,
        },
      ],
      'mistakeCategory': 'calculation',
      'originalQuestion': 'x+1=4，求x',
      'normalizedQuestion': '解方程 x+1=4',
      'studentAnswer': 'x=4+1=5',
      'standardAnswer': '3',
      'solutionSteps': <String>['移项得 x=3'],
      'knowledgePoints': <String>['一元一次方程移项'],
      'generatedExercises': <Map<String, dynamic>>[
        {
          'id': 'e1',
          'difficulty': '同级',
          'question': 'x+2=5，求x',
          'options': <String>['A. 1', 'B. 2', 'C. 3', 'D. 4'],
          'answer': 'C',
          'explanation': '移项得 x=3',
        },
      ],
      'mistakeReason': '学生在移项时没有改变符号。',
      'studyAdvice': '移项后先检查符号。',
      'aiTags': <String>['方程', '移项'],
      'reviewPlan': <String, dynamic>{
        'reviewAfterDays': 2,
        'focus': <String>['移项符号'],
        'reason': '需要尽快巩固符号变化规则',
      },
    };
