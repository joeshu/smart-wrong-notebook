import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_wrong_notebook/src/data/repositories/question_repository.dart';
import 'package:smart_wrong_notebook/src/domain/models/capture_analysis_state.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';
import 'package:smart_wrong_notebook/src/features/analysis/presentation/analysis_controller.dart';
import 'package:smart_wrong_notebook/src/features/capture/presentation/capture_controller.dart';
import 'package:smart_wrong_notebook/src/features/capture/application/capture_session_controller.dart';

void main() {
  QuestionRecord recordFor(String id, String imagePath) => QuestionRecord.draft(
        id: id,
        imagePath: imagePath,
        subject: Subject.math,
        recognizedText: '1 + 1 = 2',
      );

  test('quick entry closes the full fake capture-to-readable loop', () async {
    final capture = CaptureController.fake();
    final analysis = AnalysisController.fake();
    final repository = InMemoryQuestionRepository();
    final session = CaptureSessionController();

    final draft = await capture.createDraftFromFile(File('/tmp/quick.jpg'));
    // Quick entry skips crop/correction but still records recognition before AI.
    session.selectImage(draft.imagePath);
    session.beginRecognition();
    session.beginAnalysis();
    final analyzed = await analysis.analyze(
      questionId: draft.id,
      imagePath: draft.imagePath,
      correctedText: '1 + 1 = 2',
      subjectName: draft.subject.name,
    );
    await repository.saveDraft(analyzed);
    session.complete();

    final readable = await repository.getById(draft.id);
    expect(session.state.phase, CaptureAnalysisPhase.ready);
    expect(readable, isNotNull);
    expect(readable!.contentStatus.name, 'ready');
    expect(readable.imagePath, draft.imagePath);
    expect(readable.subject, draft.subject);
    expect(readable.correctedText, '1 + 1 = 2');
    expect(readable.analysisResult, isNotNull);
    expect(readable.savedExercises, isNotEmpty);
  });

  test('detailed entry preserves the legacy crop and confirmation route', () async {
    final capture = CaptureController.fake();
    final analysis = AnalysisController.fake();
    final repository = InMemoryQuestionRepository();
    final session = CaptureSessionController();

    final draft = await capture.createDraftFromFile(File('/tmp/detailed.jpg'));
    session.selectImage(draft.imagePath);
    session.beginCropping();
    session.beginRecognition();
    session.requireConfirmation('请确认 OCR 题干');
    await repository.saveDraft(draft.copyWith(
      normalizedQuestionText: '校对后的题干',
    ));
    session.beginAnalysis();
    final analyzed = await analysis.analyze(
      questionId: draft.id,
      imagePath: draft.imagePath,
      correctedText: '校对后的题干',
      subjectName: draft.subject.name,
    );
    await repository.saveDraft(analyzed);
    session.complete();

    final readable = await repository.getById(draft.id);
    expect(session.state.phase, CaptureAnalysisPhase.ready);
    expect(readable!.correctedText, '校对后的题干');
    expect(readable.analysisResult, isNotNull);
  });

  test('failure, retry, and cancellation retain the selected capture', () async {
    final session = CaptureSessionController();
    session.selectImage('memory://retry.jpg');
    session.beginRecognition();
    final retryable = session.markRetryable(
      'OCR unavailable',
      kind: CaptureFailureKind.ocr,
    );

    expect(retryable.phase, CaptureAnalysisPhase.retryable);
    expect(session.beginRecognition().imagePath, 'memory://retry.jpg');
    session.cancel();
    expect(session.state.phase, CaptureAnalysisPhase.cancelled);
    expect(session.state.imagePath, 'memory://retry.jpg');
    session.reset();
    expect(session.state.phase, CaptureAnalysisPhase.idle);
    expect(session.state.imagePath, isNull);
  });

  test('re-entering and saving the same id remains idempotent and readable', () async {
    final repository = InMemoryQuestionRepository();
    final session = CaptureSessionController();
    final record = recordFor('q-duplicate', 'memory://same.jpg');

    session.selectImage(record.imagePath);
    await repository.saveDraft(record);
    session.reset();
    session.selectImage(record.imagePath);
    await repository.saveDraft(record.copyWith(
      normalizedQuestionText: '用户确认后的题干',
    ));
    await repository.saveDraft(record.copyWith(
      normalizedQuestionText: '最终保存的题干',
    ));

    final all = await repository.listAll();
    final readable = await repository.getById(record.id);
    expect(all, hasLength(1));
    expect(readable!.correctedText, '最终保存的题干');
  });
}
