import 'package:flutter_test/flutter_test.dart';
import 'package:smart_wrong_notebook/src/data/remote/ai/ai_json_decoder.dart';

void main() {
  const decoder = AiJsonDecoder();

  test('decodes plain JSON without repair', () {
    final result = decoder.decode('{"subject":"数学","steps":["列式"]}');

    expect(result.value['subject'], '数学');
    expect(result.repairStrategy, AiJsonRepairStrategy.none);
    expect(result.markdownWrapped, isFalse);
    expect(result.contentFingerprint, hasLength(12));
  });

  test('detects Markdown wrapping without hiding it from contract layer', () {
    final result = decoder.decode('''```json
{"subject":"数学"}
```''');

    expect(result.value['subject'], '数学');
    expect(result.markdownWrapped, isTrue);
  });

  test('repairs raw LaTeX escapes and literal newlines', () {
    const raw = r'''{
  "subject": "数学",
  "question": "已知 \frac{1}{2}x=3，
求 x"
}''';
    final result = decoder.decode(raw);

    expect(result.repairStrategy, AiJsonRepairStrategy.invalidEscapes);
    expect(result.value['question'], contains(r'\frac{1}{2}'));
    expect(result.value['question'], contains('\n'));
  });

  test('recovers legacy flat string fields as final fallback', () {
    const raw = '{"subject":"数学", "finalAnswer":"3", "steps":["移项"] trailing}';
    final result = decoder.decode(raw);

    expect(result.repairStrategy, AiJsonRepairStrategy.flatFieldRecovery);
    expect(result.value['subject'], '数学');
    expect(result.value['finalAnswer'], '3');
  });

  test('diagnostic summary never contains raw student content', () {
    const secretStudentContent = '学生隐私答案-987654';
    final result = decoder.decode(
      '{"studentAnswer":"$secretStudentContent"}',
    );

    expect(result.diagnosticSummary, isNot(contains(secretStudentContent)));
    expect(result.diagnosticSummary, contains('fingerprint='));
    expect(result.diagnosticSummary, contains('studentAnswer'));
  });

  test('rejects non-object top-level JSON', () {
    expect(
      () => decoder.decode('[1,2,3]'),
      throwsA(isA<AiJsonDecodingException>()),
    );
  });
}
