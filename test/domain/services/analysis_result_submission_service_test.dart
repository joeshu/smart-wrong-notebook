import 'package:flutter_test/flutter_test.dart';
import 'package:smart_wrong_notebook/src/data/repositories/question_repository.dart';
import 'package:smart_wrong_notebook/src/domain/models/analysis_result.dart';
import 'package:smart_wrong_notebook/src/domain/models/content_status.dart';
import 'package:smart_wrong_notebook/src/domain/models/mastery_level.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';
import 'package:smart_wrong_notebook/src/domain/services/analysis_result_submission_service.dart';

class _FailingQuestionRepository extends InMemoryQuestionRepository {
  bool fail = true;

  @override
  Future<void> saveDraft(QuestionRecord record) async {
    if (fail) throw StateError('write failed');
    await super.saveDraft(record);
  }

  @override
  Future<void> saveDrafts(List<QuestionRecord> records) async {
    if (fail) throw StateError('write failed');
    await super.saveDrafts(records);
  }
}

QuestionRecord _analyzed(String id, {ContentStatus status = ContentStatus.ready}) {
  final now = DateTime(2026, 8, 11);
  return QuestionRecord(
    id: id,
    imagePath: 'image-$id.jpg',
    subject: Subject.math,
    extractedQuestionText: '1 + 1 = ?',
    normalizedQuestionText: '1 + 1 = ?',
    contentFormat: QuestionContentFormat.plain,
    tags: const <String>[],
    createdAt: now,
    updatedAt: now,
    lastReviewedAt: null,
    reviewCount: 0,
    isFavorite: false,
    contentStatus: status,
    masteryLevel: MasteryLevel.newQuestion,
    analysisResult: AnalysisResult(
      finalAnswer: '2',
      steps: const <String>['计算'],
      aiTags: const <String>['计算'],
      knowledgePoints: const <String>['加法'],
      mistakeReason: '粗心',
      studyAdvice: '检查计算',
      subject: Subject.math,
    ),
  );
}

void main() {
  group('AnalysisResultSubmissionService', () {
    test('saves the stable id and verifies the complete result before returning', () async {
      final repository = InMemoryQuestionRepository();
      final service = AnalysisResultSubmissionService(repository);

      final saved = await service.submit(_analyzed('q-1'));

      expect(saved.id, 'q-1');
      expect(saved.analysisResult, isNotNull);
      expect(await repository.getById('q-1'), saved);
    });

    test('reused result is submitted to the current stable id', () async {
      final repository = InMemoryQuestionRepository();
      final service = AnalysisResultSubmissionService(repository);
      final reused = _analyzed('new-capture-id');

      await service.submit(reused);

      expect(await repository.getById('new-capture-id'), reused);
      expect(await repository.getById('old-capture-id'), isNull);
    });

    test('submits every batch result before the caller advances the queue', () async {
      final repository = InMemoryQuestionRepository();
      final service = AnalysisResultSubmissionService(repository);

      await service.submitAll(<QuestionRecord>[
        _analyzed('q-1'),
        _analyzed('q-2', status: ContentStatus.needsConfirmation),
      ]);

      expect(await repository.getById('q-1'), isNotNull);
      expect(await repository.getById('q-2'), isNotNull);
    });

    test('propagates save failure and does not report a submitted result', () async {
      final repository = _FailingQuestionRepository();
      final service = AnalysisResultSubmissionService(repository);

      await expectLater(
        service.submit(_analyzed('q-fail')),
        throwsA(isA<StateError>()),
      );
      expect(await repository.getById('q-fail'), isNull);
    });

    test('repeated submission remains one stable repository row', () async {
      final repository = InMemoryQuestionRepository();
      final service = AnalysisResultSubmissionService(repository);
      final result = _analyzed('q-repeat');

      await service.submit(result);
      await service.submit(result);

      expect(await repository.listAll(), hasLength(1));
    });
  });
}
