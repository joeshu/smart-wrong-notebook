import 'package:flutter_test/flutter_test.dart';
import 'package:smart_wrong_notebook/src/domain/models/capture_analysis_state.dart';

void main() {
  group('CaptureAnalysisState contract', () {
    test('starts idle without capture data', () {
      const state = CaptureAnalysisState.initial();

      expect(state.phase, CaptureAnalysisPhase.idle);
      expect(state.imagePath, isNull);
      expect(state.errorMessage, isNull);
      expect(state.confirmationReason, isNull);
      expect(state.isTerminal, isFalse);
    });

    test('follows the normal capture and analysis path', () {
      const initial = CaptureAnalysisState.initial();
      final selected = initial.transitionTo(
        CaptureAnalysisPhase.imageSelected,
        imagePath: 'question.jpg',
      );
      final cropped = selected.transitionTo(CaptureAnalysisPhase.cropping);
      final recognizing = cropped.transitionTo(
        CaptureAnalysisPhase.recognizing,
      );
      final analyzing = recognizing.transitionTo(CaptureAnalysisPhase.analyzing);
      final ready = analyzing.transitionTo(CaptureAnalysisPhase.ready);

      expect(ready.phase, CaptureAnalysisPhase.ready);
      expect(ready.imagePath, 'question.jpg');
      expect(ready.isTerminal, isTrue);
    });

    test('allows recognition to stop for user confirmation', () {
      const state = CaptureAnalysisState(
        CaptureAnalysisPhase.recognizing,
        imagePath: 'question.jpg',
      );

      final pending = state.transitionTo(
        CaptureAnalysisPhase.needsConfirmation,
        confirmationReason: 'ambiguous answer',
      );

      expect(pending.phase, CaptureAnalysisPhase.needsConfirmation);
      expect(pending.imagePath, 'question.jpg');
      expect(pending.confirmationReason, 'ambiguous answer');
      expect(pending.errorMessage, isNull);
    });

    test('supports cancellation from an active stage and restart', () {
      const state = CaptureAnalysisState(
        CaptureAnalysisPhase.analyzing,
        imagePath: 'question.jpg',
      );

      final cancelled = state.transitionTo(CaptureAnalysisPhase.cancelled);
      final restarted = cancelled.transitionTo(CaptureAnalysisPhase.idle);

      expect(cancelled.isTerminal, isTrue);
      expect(restarted.phase, CaptureAnalysisPhase.idle);
      expect(restarted.imagePath, isNull);
    });

    test('retains failure details and permits retry from failed', () {
      const recognizing = CaptureAnalysisState(
        CaptureAnalysisPhase.recognizing,
        imagePath: 'question.jpg',
      );

      final failed = recognizing.transitionTo(
        CaptureAnalysisPhase.failed,
        errorMessage: 'OCR unavailable',
      );
      final retry = failed.transitionTo(CaptureAnalysisPhase.recognizing);

      expect(failed.errorMessage, 'OCR unavailable');
      expect(failed.confirmationReason, isNull);
      expect(retry.phase, CaptureAnalysisPhase.recognizing);
      expect(retry.errorMessage, isNull);
      expect(retry.confirmationReason, isNull);
    });

    test('rejects an illegal transition without changing the state', () {
      const state = CaptureAnalysisState.initial();

      expect(
        () => state.transitionTo(CaptureAnalysisPhase.ready),
        throwsA(isA<InvalidCaptureAnalysisTransition>()),
      );
      expect(state.phase, CaptureAnalysisPhase.idle);
    });

    test('allows retryable failure and preserves retry metadata', () {
      const state = CaptureAnalysisState(
        CaptureAnalysisPhase.analyzing,
        imagePath: 'question.jpg',
      );
      final retryable = state.transitionTo(
        CaptureAnalysisPhase.retryable,
        errorMessage: 'AI timed out',
        failureKind: CaptureFailureKind.timeout,
        retryCount: 1,
      );

      expect(retryable.isRetryable, isTrue);
      expect(retryable.isTerminal, isFalse);
      expect(retryable.failureKind, CaptureFailureKind.timeout);
      expect(retryable.retryCount, 1);
      expect(retryable.transitionTo(CaptureAnalysisPhase.analyzing).phase,
          CaptureAnalysisPhase.analyzing);
    });

    test('requires an image for imageSelected', () {
      const state = CaptureAnalysisState.initial();

      expect(
        () => state.transitionTo(CaptureAnalysisPhase.imageSelected),
        throwsA(isA<ArgumentError>()),
      );
    });

    test('keeps retryable and terminal states mutually exclusive', () {
      const analyzing = CaptureAnalysisState(
        CaptureAnalysisPhase.analyzing,
        imagePath: 'question.jpg',
      );
      final retryable = analyzing.transitionTo(
        CaptureAnalysisPhase.retryable,
        errorMessage: 'temporary OCR failure',
        failureKind: CaptureFailureKind.ocr,
        retryCount: 1,
      );
      final succeeded = retryable
          .transitionTo(CaptureAnalysisPhase.recognizing)
          .transitionTo(CaptureAnalysisPhase.analyzing)
          .transitionTo(CaptureAnalysisPhase.ready);

      expect(retryable.isRetryable, isTrue);
      expect(retryable.isTerminal, isFalse);
      expect(succeeded.phase, CaptureAnalysisPhase.ready);
      expect(succeeded.isRetryable, isFalse);
      expect(succeeded.isTerminal, isTrue);
      expect(() => retryable.transitionTo(CaptureAnalysisPhase.ready),
          throwsA(isA<InvalidCaptureAnalysisTransition>()));
    });

    test('cancellation clears failure metadata before reset', () {
      const retryable = CaptureAnalysisState(
        CaptureAnalysisPhase.retryable,
        imagePath: 'question.jpg',
        errorMessage: 'timed out',
        failureKind: CaptureFailureKind.timeout,
        retryCount: 2,
      );
      final cancelled = retryable.transitionTo(CaptureAnalysisPhase.cancelled);
      final reset = cancelled.transitionTo(CaptureAnalysisPhase.idle);

      expect(cancelled.isTerminal, isTrue);
      expect(cancelled.errorMessage, isNull);
      expect(cancelled.failureKind, isNull);
      expect(reset.phase, CaptureAnalysisPhase.idle);
      expect(reset.retryCount, 0);
    });
  });
}
