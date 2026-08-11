import 'package:flutter_test/flutter_test.dart';
import 'package:smart_wrong_notebook/src/domain/models/ai_response_diagnostics.dart';
import 'package:smart_wrong_notebook/src/domain/models/analysis_result.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';
import 'package:smart_wrong_notebook/src/domain/services/ai_response_diagnostics_retention_service.dart';

void main() {
  const service = AiResponseDiagnosticsRetentionService();

  test('stripRawResponses removes raw response but keeps safe summary', () {
    final stripped = service.stripRawResponses(_record(raw: 'secret raw json'));

    final diagnostics = stripped.analysisResult!.responseDiagnostics!;
    expect(diagnostics.hasRawResponse, isFalse);
    expect(diagnostics.contentFingerprint, 'abc123def456');
    expect(diagnostics.contentLength, 999);
  });

  test('stripRawResponses leaves record unchanged when no raw response exists', () {
    final base = _record(raw: 'raw');
    final record = base.copyWith(
      analysisResult:
          base.analysisResult!.copyWith(responseDiagnostics: base.analysisResult!
              .responseDiagnostics!
              .withoutRawResponse()),
    );

    final stripped = service.stripRawResponses(record);

    expect(identical(stripped, record), isTrue);
  });

  test('expireRawResponses keeps unexpired raw response', () {
    final kept = service.expireRawResponses(
      _record(raw: 'raw', capturedAt: DateTime.utc(2026, 7, 25)),
      now: DateTime.utc(2026, 7, 26),
    );

    expect(kept.analysisResult?.responseDiagnostics?.rawResponse, 'raw');
  });

  test('expireRawResponses removes expired raw response', () {
    final expired = service.expireRawResponses(
      _record(raw: 'raw', capturedAt: DateTime.utc(2026, 7, 25)),
      now: DateTime.utc(2026, 8, 2),
    );

    expect(expired.analysisResult?.responseDiagnostics?.hasRawResponse, isFalse);
  });
}

QuestionRecord _record({
  required String raw,
  DateTime? capturedAt,
}) {
  return QuestionRecord.draft(
    id: 'q-diagnostics',
    imagePath: '/tmp/q.jpg',
    subject: Subject.math,
    recognizedText: 'x+1=4',
  ).copyWith(
    analysisResult: AnalysisResult(
      finalAnswer: '3',
      steps: const <String>['移项'],
      aiTags: const <String>['方程'],
      knowledgePoints: const <String>['一元一次方程'],
      mistakeReason: '',
      studyAdvice: '练习移项',
      responseDiagnostics: AiResponseDiagnostics(
        contentLength: 999,
        contentFingerprint: 'abc123def456',
        markdownWrapped: false,
        repairStrategy: 'none',
        capturedAt: capturedAt ?? DateTime.utc(2026, 7, 25),
        rawResponse: raw,
        retentionDays: 7,
      ),
    ),
  );
}
