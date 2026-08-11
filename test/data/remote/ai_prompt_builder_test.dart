import 'package:flutter_test/flutter_test.dart';
import 'package:smart_wrong_notebook/src/data/remote/ai/ai_prompt_builder.dart';
import 'package:smart_wrong_notebook/src/data/remote/ai/ai_provider_capabilities.dart';
import 'package:smart_wrong_notebook/src/domain/models/ai_analysis_contract.dart';
import 'package:smart_wrong_notebook/src/domain/models/ai_analysis_patch.dart';
import 'package:smart_wrong_notebook/src/domain/models/analysis_result.dart';

void main() {
  const builder = AiPromptBuilder();

  test('analysis prompt declares Contract V2 and evidence policy', () {
    final prompt = builder.buildAnalysisPrompt(
      subjectName: '数学',
      correctedText: '解方程 x+1=4',
      studentAnswer: 'x=4+1=5',
      modelName: 'fixture-model',
    );

    expect(prompt, contains('schemaVersion 固定为 2'));
    expect(prompt, contains(AiAnalysisSchema.currentPromptVersion));
    expect(prompt, contains('fixture-model'));
    expect(prompt, contains('x=4+1=5'));
    expect(prompt, contains('source="studentAnswer"'));
    expect(prompt, contains('不要输出 Markdown'));
  });

  test('missing student answer explicitly forbids deterministic diagnosis', () {
    final prompt = builder.buildAnalysisPrompt(
      subjectName: '数学',
      correctedText: '解方程 x+1=4',
    );

    expect(prompt, contains('（未提供）'));
    expect(prompt, contains('mistakeCategory 必须为 null'));
    expect(prompt, contains('mistakeReason 必须为空字符串'));
  });

  test('field repair prompt requests only selected fields', () {
    const current = AnalysisResult(
      finalAnswer: '5',
      steps: <String>['x=4+1=5'],
      aiTags: <String>[],
      knowledgePoints: <String>['方程'],
      mistakeReason: '',
      studyAdvice: '',
    );
    final prompt = builder.buildFieldRepairPrompt(
      current: current,
      fields: const <AiAnalysisField>{
        AiAnalysisField.standardAnswer,
        AiAnalysisField.solutionSteps,
      },
      confirmedQuestion: '解方程 x+1=4',
      studentAnswer: '',
      modelName: 'fixture-model',
    );

    expect(prompt, contains('standardAnswer'));
    expect(prompt, contains('solutionSteps'));
    expect(prompt, isNot(contains('待修复字段：mistakeReason')));
  });

  test('response format supports json_object and strict schema envelope', () {
    expect(
      builder.responseFormat(AiStructuredOutputMode.jsonObject),
      <String, dynamic>{'type': 'json_object'},
    );
    final format = builder.responseFormat(AiStructuredOutputMode.jsonSchema)!;
    expect(format['type'], 'json_schema');
    final envelope = format['json_schema'] as Map<String, dynamic>;
    expect(envelope['strict'], isTrue);
    expect(
      (envelope['schema'] as Map<String, dynamic>)['additionalProperties'],
      isFalse,
    );
  });
}
