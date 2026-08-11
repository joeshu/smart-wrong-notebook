import 'package:flutter_test/flutter_test.dart';
import 'package:smart_wrong_notebook/src/domain/models/content_status.dart';
import 'package:smart_wrong_notebook/src/domain/models/mastery_level.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';
import 'package:smart_wrong_notebook/src/domain/services/analysis_recovery_service.dart';

QuestionRecord _record({
  ContentStatus status = ContentStatus.analyzing,
  Object? analysisResult,
  String? lastAnalysisError,
}) {
  final now = DateTime(2026);
  return QuestionRecord(
    id: 'q-1',
    imagePath: '/tmp/q-1.jpg',
    subject: Subject.math,
    extractedQuestionText: '题目',
    normalizedQuestionText: '题目',
    contentFormat: QuestionContentFormat.plain,
    tags: const <String>[],
    createdAt: now,
    updatedAt: now,
    lastReviewedAt: null,
    reviewCount: 0,
    isFavorite: false,
    contentStatus: status,
    masteryLevel: MasteryLevel.newQuestion,
    analysisResult: null,
    lastAnalysisError: lastAnalysisError,
  );
}

void main() {
  const service = AnalysisRecoveryService();

  test('marks interrupted analyzing records as analysisFailed', () {
    final recovered = service.recoverInterrupted(_record());

    expect(recovered.contentStatus, ContentStatus.analysisFailed);
    expect(recovered.lastAnalysisError, AnalysisRecoveryService.interruptedMessage);
  });

  test('does not change non-analyzing records', () {
    final ready = _record(status: ContentStatus.ready);

    expect(service.recoverInterrupted(ready), same(ready));
  });

  test('recovers interrupted OCR processing while preserving text', () {
    final recovered = service.recoverInterrupted(
      _record(status: ContentStatus.processing),
    );

    expect(recovered.contentStatus, ContentStatus.analysisFailed);
    expect(recovered.lastAnalysisError,
        AnalysisRecoveryService.recognitionInterruptedMessage);
    expect(recovered.extractedQuestionText, '题目');
    expect(recovered.normalizedQuestionText, '题目');
  });

  test('preserves an existing failure reason when recovering interrupted work', () {
    final recovered = service.recoverInterrupted(
      _record(
        status: ContentStatus.analyzing,
        lastAnalysisError: '网络超时',
      ),
    );

    expect(recovered.contentStatus, ContentStatus.analysisFailed);
    expect(recovered.lastAnalysisError, '网络超时');
  });

  test('recoverAll applies the same ContentStatus boundary to every record', () {
    final records = service.recoverAll(<QuestionRecord>[
      _record(status: ContentStatus.processing),
      _record(status: ContentStatus.analyzing),
      _record(status: ContentStatus.failed),
    ]);

    expect(records, hasLength(3));
    expect(records[0].contentStatus, ContentStatus.analysisFailed);
    expect(records[1].contentStatus, ContentStatus.analysisFailed);
    expect(records[2].contentStatus, ContentStatus.failed);
  });
}
