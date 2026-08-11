import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smart_wrong_notebook/src/domain/models/capture_analysis_state.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/features/capture/application/capture_session_controller.dart';
import 'package:smart_wrong_notebook/src/app/providers/capture_providers.dart';

final StateNotifierProvider<CaptureSessionNotifier, CaptureAnalysisState>
    captureSessionProvider = StateNotifierProvider<CaptureSessionNotifier,
        CaptureAnalysisState>((ref) => CaptureSessionNotifier(ref));

class CaptureSessionNotifier extends StateNotifier<CaptureAnalysisState> {
  CaptureSessionNotifier(this.ref)
      : _controller = CaptureSessionController(),
        super(const CaptureAnalysisState.initial());

  final Ref ref;
  final CaptureSessionController _controller;

  CaptureAnalysisState selectImage(String imagePath) =>
      _apply(() => _controller.selectImage(imagePath));
  CaptureAnalysisState beginCropping() => _apply(_controller.beginCropping);
  CaptureAnalysisState beginRecognition() =>
      _apply(_controller.beginRecognition);
  CaptureAnalysisState beginAnalysis() => _apply(_controller.beginAnalysis);
  CaptureAnalysisState requireConfirmation([String? reason]) =>
      _apply(() => _controller.requireConfirmation(reason));
  CaptureAnalysisState complete() => _apply(_controller.complete);
  CaptureAnalysisState fail(String message) => _apply(() => _controller.fail(message));
  CaptureAnalysisState markRetryable(String message, {required CaptureFailureKind kind}) =>
      _apply(() => _controller.markRetryable(message, kind: kind));
  CaptureAnalysisState cancel() => _apply(_controller.cancel);
  CaptureAnalysisState reset() => _apply(_controller.reset);

  CaptureAnalysisState endSession() {
    final next = _apply(_controller.reset);
    ref.read(currentQuestionProvider.notifier).state = null;
    return next;
  }

  CaptureAnalysisState setCurrentQuestion(QuestionRecord? record) {
    final next = state;
    ref.read(currentQuestionProvider.notifier).state = record;
    if (record == null) {
      _controller.clearDraft();
    } else if (_controller.draft == null) {
      _controller.createDraft(record);
    } else {
      _controller.updateDraft(record);
    }
    return next;
  }

  /// Restores the single in-memory draft on route re-entry, without creating
  /// another session or replacing a newer question.
  QuestionRecord? restoreDraft() {
    final draft = _controller.readDraft();
    if (draft == null) return null;
    final current = ref.read(currentQuestionProvider);
    if (current?.id != draft.question.id || current?.imagePath != draft.imagePath) {
      ref.read(currentQuestionProvider.notifier).state = draft.question;
    }
    return draft.question;
  }

  /// Updates both the legacy mirror and the one in-memory session snapshot.
  CaptureAnalysisState updateCurrentQuestion(QuestionRecord record) =>
      setCurrentQuestion(record);

  CaptureAnalysisState clearCurrentQuestion() => setCurrentQuestion(null);

  CaptureAnalysisState _apply(CaptureAnalysisState Function() transition) {
    final next = transition();
    state = next;
    final draft = _controller.readDraft();
    if (draft != null) _controller.updateDraft(draft.question);
    return next;
  }
}
