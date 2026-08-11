import 'package:flutter_test/flutter_test.dart';

import 'package:smart_wrong_notebook/src/domain/models/capture_analysis_state.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';
import 'package:smart_wrong_notebook/src/features/capture/application/capture_session_controller.dart';

void main() {
  group('CaptureSessionController', () {
    test('starts idle with no capture data', () {
      final controller = CaptureSessionController();

      expect(controller.state.phase, CaptureAnalysisPhase.idle);
      expect(controller.state.imagePath, isNull);
      expect(controller.state.errorMessage, isNull);
      expect(controller.state.confirmationReason, isNull);
    });

    test('follows the normal single-question capture path', () {
      final controller = CaptureSessionController();

      expect(controller.selectImage('memory://question.png').phase,
          CaptureAnalysisPhase.imageSelected);
      expect(controller.beginRecognition().phase,
          CaptureAnalysisPhase.recognizing);
      expect(controller.beginAnalysis().phase, CaptureAnalysisPhase.analyzing);
      expect(controller.complete().phase, CaptureAnalysisPhase.ready);
      expect(controller.state.imagePath, 'memory://question.png');
    });

    test('can skip cropping', () {
      final controller = CaptureSessionController();

      controller.selectImage('memory://question.png');
      expect(controller.beginRecognition().phase,
          CaptureAnalysisPhase.recognizing);
    });

    test('continues from confirmation into analysis and completion', () {
      final controller = CaptureSessionController();

      controller.selectImage('memory://question.png');
      controller.beginRecognition();
      final confirmation = controller.requireConfirmation('check answer');
      expect(confirmation.phase, CaptureAnalysisPhase.needsConfirmation);
      expect(confirmation.confirmationReason, 'check answer');
      expect(confirmation.errorMessage, isNull);
      expect(controller.beginAnalysis().phase, CaptureAnalysisPhase.analyzing);
      expect(controller.complete().phase, CaptureAnalysisPhase.ready);
    });

    test('can fail and retry recognition', () {
      final controller = CaptureSessionController();

      controller.selectImage('memory://question.png');
      controller.beginRecognition();
      final failed = controller.fail('recognition failed');
      expect(failed.phase, CaptureAnalysisPhase.failed);
      expect(failed.errorMessage, 'recognition failed');
      expect(failed.confirmationReason, isNull);
      expect(controller.beginRecognition().phase,
          CaptureAnalysisPhase.recognizing);
      expect(controller.state.imagePath, 'memory://question.png');
      expect(controller.state.errorMessage, isNull);
      expect(controller.state.confirmationReason, isNull);
    });

    test('can retry analysis after an analysis failure without losing image', () {
      final controller = CaptureSessionController();

      controller.selectImage('memory://question.png');
      controller.beginRecognition();
      controller.beginAnalysis();
      final failed = controller.fail('analysis timed out');

      expect(failed.phase, CaptureAnalysisPhase.failed);
      expect(controller.beginAnalysis().phase,
          CaptureAnalysisPhase.analyzing);
      expect(controller.state.imagePath, 'memory://question.png');
    });

    test('keeps OCR failure recoverable and clears it on a new recognition run', () {
      final controller = CaptureSessionController();
      controller.selectImage('memory://question.png');
      controller.beginRecognition();
      final failed = controller.markRetryable(
        'OCR unavailable',
        kind: CaptureFailureKind.ocr,
      );

      expect(failed.phase, CaptureAnalysisPhase.retryable);
      expect(failed.failureKind, CaptureFailureKind.ocr);
      expect(failed.imagePath, 'memory://question.png');
      expect(controller.beginRecognition().errorMessage, isNull);
      expect(controller.state.failureKind, isNull);
      expect(controller.state.imagePath, 'memory://question.png');
    });

    test('cancellation is idempotent at the session boundary after a retry', () {
      final controller = CaptureSessionController();
      controller.selectImage('memory://question.png');
      controller.beginRecognition();
      controller.markRetryable('temporary failure', kind: CaptureFailureKind.ai);
      final cancelled = controller.cancel();

      expect(cancelled.phase, CaptureAnalysisPhase.cancelled);
      expect(cancelled.imagePath, 'memory://question.png');
      expect(cancelled.errorMessage, isNull);
      expect(cancelled.failureKind, isNull);
      expect(controller.reset().phase, CaptureAnalysisPhase.idle);
      expect(controller.state.imagePath, isNull);
      expect(controller.state.retryCount, 0);
      expect(() => controller.cancel(),
          throwsA(isA<InvalidCaptureAnalysisTransition>()));
    });

    test('a late retry cannot mutate a terminal successful snapshot', () {
      final controller = CaptureSessionController();
      controller.selectImage('memory://question.png');
      controller.beginRecognition();
      controller.beginAnalysis();
      final ready = controller.complete();

      expect(ready.phase, CaptureAnalysisPhase.ready);
      expect(() => controller.markRetryable(
            'late callback',
            kind: CaptureFailureKind.ai,
          ), throwsA(isA<InvalidCaptureAnalysisTransition>()));
      expect(controller.state.phase, CaptureAnalysisPhase.ready);
      expect(controller.state.imagePath, 'memory://question.png');
    });

    test('re-entering the same draft updates content without duplicating the session', () {
      final controller = CaptureSessionController();
      final first = QuestionRecord.draft(
        id: 'q-1',
        imagePath: 'memory://question.png',
        subject: Subject.math,
        recognizedText: 'OCR text',
      );
      final corrected = first.copyWith(extractedQuestionText: 'corrected text');

      controller.selectImage(first.imagePath);
      controller.createDraft(first);
      controller.updateDraft(corrected);
      controller.updateDraft(corrected);

      expect(controller.draft?.question.id, 'q-1');
      expect(controller.draft?.recognizedText, 'corrected text');
      expect(controller.state.phase, CaptureAnalysisPhase.imageSelected);
    });

    test('marks timeout retryable and increments retry count', () {
      final controller = CaptureSessionController();
      controller.selectImage('memory://question.png');
      controller.beginRecognition();
      controller.beginAnalysis();

      final retryable = controller.markRetryable(
        'analysis timed out',
        kind: CaptureFailureKind.timeout,
      );

      expect(retryable.phase, CaptureAnalysisPhase.retryable);
      expect(retryable.failureKind, CaptureFailureKind.timeout);
      expect(retryable.retryCount, 1);
      expect(controller.beginAnalysis().phase, CaptureAnalysisPhase.analyzing);
    });

    test('retries OCR and AI failures without stale error metadata', () {
      final controller = CaptureSessionController();
      controller.selectImage('memory://question.png');
      controller.beginRecognition();

      final ocrRetry = controller.markRetryable(
        'OCR unavailable',
        kind: CaptureFailureKind.ocr,
      );
      expect(ocrRetry.retryCount, 1);
      controller.beginRecognition();
      controller.beginAnalysis();

      final aiRetry = controller.markRetryable(
        'AI unavailable',
        kind: CaptureFailureKind.ai,
      );
      expect(aiRetry.phase, CaptureAnalysisPhase.retryable);
      expect(aiRetry.failureKind, CaptureFailureKind.ai);
      expect(aiRetry.retryCount, 2);
      expect(aiRetry.errorMessage, 'AI unavailable');
    });

    test('converts retry beyond policy limit to terminal failed', () {
      final controller = CaptureSessionController(
        retryPolicy: const CaptureRetryPolicy(maxRetries: 1),
      );
      controller.selectImage('memory://question.png');
      controller.beginRecognition();
      controller.beginAnalysis();
      expect(controller.markRetryable('first', kind: CaptureFailureKind.ai).phase,
          CaptureAnalysisPhase.retryable);
      controller.beginAnalysis();

      final failed = controller.markRetryable(
        'second',
        kind: CaptureFailureKind.timeout,
      );
      expect(failed.phase, CaptureAnalysisPhase.failed);
      expect(failed.failureKind, CaptureFailureKind.timeout);
      expect(() => controller.markRetryable(
            'duplicate',
            kind: CaptureFailureKind.ai,
          ), throwsA(isA<InvalidCaptureAnalysisTransition>()));
    });

    test('backoff is bounded by the shared retry policy', () {
      const policy = CaptureRetryPolicy(
        maxRetries: 3,
        initialBackoff: Duration(seconds: 2),
        maxBackoff: Duration(seconds: 5),
      );
      expect(policy.backoffFor(0), Duration.zero);
      expect(policy.backoffFor(1), const Duration(seconds: 2));
      expect(policy.backoffFor(2), const Duration(seconds: 4));
      expect(policy.backoffFor(3), const Duration(seconds: 5));
      expect(policy.canRetry(3), isTrue);
      expect(policy.canRetry(4), isFalse);
    });

    test('can cancel and reset the session', () {
      final controller = CaptureSessionController();

      controller.selectImage('memory://question.png');
      controller.beginCropping();
      expect(controller.cancel().phase, CaptureAnalysisPhase.cancelled);
      expect(controller.reset().phase, CaptureAnalysisPhase.idle);
      expect(controller.state.imagePath, isNull);
    });

    test('rejects operations that are not valid for the current phase', () {
      final controller = CaptureSessionController();

      expect(() => controller.beginRecognition(),
          throwsA(isA<InvalidCaptureAnalysisTransition>()));
      controller.selectImage('memory://question.png');
      expect(() => controller.complete(),
          throwsA(isA<InvalidCaptureAnalysisTransition>()));
    });

    test('rejects an empty image path', () {
      final controller = CaptureSessionController();

      expect(() => controller.selectImage('   '), throwsArgumentError);
    });

    test('returns immutable snapshots without changing older states', () {
      final controller = CaptureSessionController();
      final initial = controller.state;
      final selected = controller.selectImage('memory://question.png');

      expect(initial.phase, CaptureAnalysisPhase.idle);
      expect(initial.imagePath, isNull);
      expect(selected.phase, CaptureAnalysisPhase.imageSelected);
      expect(controller.state, isNot(same(initial)));
      expect(() => initial.transitionTo(CaptureAnalysisPhase.imageSelected,
          imagePath: 'memory://other.png'), returnsNormally);
      expect(initial.phase, CaptureAnalysisPhase.idle);
    });
    test('keeps one in-memory draft and supports update, read, and clear', () {
      final controller = CaptureSessionController();
      final first = QuestionRecord.draft(
        id: 'q-1', imagePath: 'memory://first.png', subject: Subject.math,
        recognizedText: 'first text',
      );
      final updated = first.copyWith(
        imagePath: 'memory://cropped.png',
        extractedQuestionText: 'recognized text',
      );
      controller.selectImage(first.imagePath);
      controller.createDraft(first);
      expect(controller.readDraft()?.imagePath, first.imagePath);
      controller.updateDraft(updated);
      expect(controller.readDraft()?.recognizedText, 'recognized text');
      expect(controller.readDraft(), same(controller.draft));
      controller.clearDraft();
      expect(controller.readDraft(), isNull);
    });

    test('reset clears the volatile draft', () {
      final controller = CaptureSessionController();
      final question = QuestionRecord.draft(
        id: 'q-1', imagePath: 'memory://question.png', subject: Subject.math,
        recognizedText: '',
      );
      controller.selectImage(question.imagePath);
      controller.createDraft(question);
      controller.reset();
      expect(controller.readDraft(), isNull);
      expect(controller.state.phase, CaptureAnalysisPhase.idle);
    });
  });
}
