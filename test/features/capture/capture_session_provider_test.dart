import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/domain/models/capture_analysis_state.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';

void main() {
  group('captureSessionProvider', () {
    test('defaults to idle and keeps the legacy provider available', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(captureSessionProvider).phase,
          CaptureAnalysisPhase.idle);
      expect(container.read(currentQuestionProvider), isNull);
    });

    test('selectImage updates the session state synchronously', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      final state = container.read(captureSessionProvider.notifier)
          .selectImage('memory://question.png');

      expect(state.phase, CaptureAnalysisPhase.imageSelected);
      expect(container.read(captureSessionProvider).imagePath,
          'memory://question.png');
    });

    test('setCurrentQuestion writes the compatibility mirror', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final record = QuestionRecord.draft(
        id: 'q-1',
        imagePath: 'memory://question.png',
        subject: Subject.math,
        recognizedText: '2 + 2',
      );

      final state = container.read(captureSessionProvider.notifier)
          .setCurrentQuestion(record);

      expect(state.phase, CaptureAnalysisPhase.idle);
      expect(container.read(currentQuestionProvider), same(record));
    });

    test('session transition completes before the mirror is written', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final record = QuestionRecord.draft(
        id: 'q-1',
        imagePath: 'memory://question.png',
        subject: Subject.math,
        recognizedText: '2 + 2',
      );
      final notifier = container.read(captureSessionProvider.notifier);

      notifier.selectImage('memory://question.png');
      notifier.setCurrentQuestion(record);

      expect(container.read(captureSessionProvider).phase,
          CaptureAnalysisPhase.imageSelected);
      expect(container.read(currentQuestionProvider), same(record));
    });

    test('illegal transition does not write the mirror', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final oldRecord = QuestionRecord.draft(
        id: 'old', imagePath: 'memory://old.png', subject: Subject.math,
        recognizedText: 'old',
      );
      final notifier = container.read(captureSessionProvider.notifier);
      notifier.setCurrentQuestion(oldRecord);

      expect(() => notifier.complete(),
          throwsA(isA<InvalidCaptureAnalysisTransition>()));
      expect(container.read(currentQuestionProvider), same(oldRecord));
      expect(container.read(captureSessionProvider).phase,
          CaptureAnalysisPhase.idle);

    });

    test('clearing the mirror does not reset the session', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(captureSessionProvider.notifier);
      notifier.selectImage('memory://question.png');
      notifier.setCurrentQuestion(QuestionRecord.draft(
        id: 'q-1', imagePath: 'memory://question.png', subject: Subject.math,
        recognizedText: '2 + 2',
      ));

      notifier.clearCurrentQuestion();

      expect(container.read(currentQuestionProvider), isNull);
      expect(container.read(captureSessionProvider).phase,
          CaptureAnalysisPhase.imageSelected);
    });

    test('endSession clears the current question and its in-memory draft', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(captureSessionProvider.notifier);
      final record = QuestionRecord.draft(
        id: 'q-replace',
        imagePath: 'memory://old.png',
        subject: Subject.math,
        recognizedText: '旧题干',
      );

      notifier.selectImage(record.imagePath);
      notifier.setCurrentQuestion(record);
      notifier.endSession();

      expect(container.read(currentQuestionProvider), isNull);
      expect(container.read(captureSessionProvider).phase,
          CaptureAnalysisPhase.idle);
      expect(notifier.restoreDraft(), isNull);
    });

    test('disposes cleanly', () {
      final container = ProviderContainer();
      container.read(captureSessionProvider);
      expect(container.dispose, returnsNormally);
    });
  });
}
