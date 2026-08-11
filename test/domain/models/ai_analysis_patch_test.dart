import 'package:flutter_test/flutter_test.dart';
import 'package:smart_wrong_notebook/src/domain/models/ai_analysis_contract.dart';
import 'package:smart_wrong_notebook/src/domain/models/ai_analysis_patch.dart';
import 'package:smart_wrong_notebook/src/domain/models/analysis_result.dart';

void main() {
  test('parses and applies only requested fields', () {
    const current = AnalysisResult(
      finalAnswer: '5',
      steps: <String>['错误步骤'],
      aiTags: <String>['方程'],
      knowledgePoints: <String>['一元一次方程'],
      mistakeReason: '',
      studyAdvice: '保留建议',
      schemaVersion: 2,
      promptVersion: 'analysis-v2.0.0',
      modelName: 'old-model',
      confidence: AiConfidence(
        overall: 0.6,
        fields: <String, double>{'knowledgePoints': 0.9},
      ),
      isLegacyContract: false,
    );
    final patch = AiAnalysisPatchContract.parse(
      _validPatch(),
      requestedFields: const <AiAnalysisField>{
        AiAnalysisField.standardAnswer,
        AiAnalysisField.solutionSteps,
      },
      studentAnswer: '',
    );

    final updated = patch.applyTo(current);

    expect(updated.standardAnswer, '3');
    expect(updated.finalAnswer, '3');
    expect(updated.solutionSteps, ['移项得 x=3']);
    expect(updated.steps, ['移项得 x=3']);
    expect(updated.knowledgePoints, ['一元一次方程']);
    expect(updated.studyAdvice, '保留建议');
    expect(updated.confidence?.fields['knowledgePoints'], 0.9);
    expect(updated.confidence?.fields['standardAnswer'], 0.96);
  });

  test('rejects fields that were not requested', () {
    final input = _validPatch();
    (input['fields'] as Map<String, dynamic>)['studyAdvice'] = '额外改写';
    final confidence = input['confidence'] as Map<String, dynamic>;
    final confidenceValues = Map<String, dynamic>.from(
      confidence['fields'] as Map,
    )..['studyAdvice'] = 0.8;
    confidence['fields'] = confidenceValues;

    expect(
      () => AiAnalysisPatchContract.parse(
        input,
        requestedFields: const <AiAnalysisField>{
          AiAnalysisField.standardAnswer,
          AiAnalysisField.solutionSteps,
        },
        studentAnswer: '',
      ),
      throwsFormatException,
    );
  });

  test('rejects diagnosis repair without student answer', () {
    final input = _validPatch(
      fields: <String, dynamic>{
        'mistakeCategory': 'careless',
        'mistakeReason': '学生粗心',
      },
      confidenceFields: <String, dynamic>{
        'mistakeCategory': 0.7,
        'mistakeReason': 0.7,
      },
    );

    expect(
      () => AiAnalysisPatchContract.parse(
        input,
        requestedFields: const <AiAnalysisField>{
          AiAnalysisField.mistakeCategory,
          AiAnalysisField.mistakeReason,
        },
        studentAnswer: '',
      ),
      throwsFormatException,
    );
  });

  test('accepts diagnosis repair with quoted student evidence', () {
    final input = _validPatch(
      fields: <String, dynamic>{
        'mistakeCategory': 'calculation',
        'mistakeReason': '移项未变号',
      },
      confidenceFields: <String, dynamic>{
        'mistakeCategory': 0.88,
        'mistakeReason': 0.9,
      },
    )..['evidence'] = <Map<String, dynamic>>[
        {
          'field': 'mistakeReason',
          'source': 'studentAnswer',
          'quote': 'x=4+1',
          'explanation': '移项没有变号',
          'stepIndex': 0,
        },
      ];

    final patch = AiAnalysisPatchContract.parse(
      input,
      requestedFields: const <AiAnalysisField>{
        AiAnalysisField.mistakeCategory,
        AiAnalysisField.mistakeReason,
      },
      studentAnswer: 'x=4+1=5',
    );

    expect(patch.evidence.single.quote, 'x=4+1');
  });
}

Map<String, dynamic> _validPatch({
  Map<String, dynamic>? fields,
  Map<String, dynamic>? confidenceFields,
}) =>
    <String, dynamic>{
      'schemaVersion': 2,
      'promptVersion': 'analysis-v2.0.0',
      'modelName': 'fixture-model',
      'fields': fields ??
          <String, dynamic>{
            'standardAnswer': '3',
            'solutionSteps': <String>['移项得 x=3'],
          },
      'confidence': <String, dynamic>{
        'overall': 0.94,
        'fields': confidenceFields ??
            <String, dynamic>{
              'standardAnswer': 0.96,
              'solutionSteps': 0.93,
            },
      },
      'uncertainties': <Map<String, dynamic>>[],
      'evidence': <Map<String, dynamic>>[],
    };
