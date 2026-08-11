import '../../../domain/models/capture_analysis_state.dart';
import '../../../domain/models/question_record.dart';

/// Pure application-layer coordinator for one capture session.
///
/// This class deliberately delegates transition validation and snapshot
/// creation to [CaptureAnalysisState] and has no Flutter or persistence
/// dependencies.
class CaptureSessionController {
  CaptureSessionController({
    CaptureAnalysisState? initialState,
    this.retryPolicy = const CaptureRetryPolicy(),
  }) : _state = initialState ?? const CaptureAnalysisState.initial();

  CaptureAnalysisState _state;
  CaptureSessionDraft? _draft;
  final CaptureRetryPolicy retryPolicy;

  CaptureAnalysisState get state => _state;
  CaptureSessionDraft? get draft => _draft;

  CaptureSessionDraft createDraft(QuestionRecord question) {
    return _draft = CaptureSessionDraft(question: question, phase: _state.phase);
  }

  CaptureSessionDraft updateDraft(QuestionRecord question) {
    return _draft = CaptureSessionDraft(question: question, phase: _state.phase);
  }

  CaptureSessionDraft? readDraft() => _draft;

  void clearDraft() => _draft = null;

  CaptureAnalysisState selectImage(String imagePath) => _transition(
        CaptureAnalysisPhase.imageSelected,
        imagePath: imagePath,
      );

  CaptureAnalysisState beginCropping() => _transition(
        CaptureAnalysisPhase.cropping,
      );

  CaptureAnalysisState beginRecognition() => _transition(
        CaptureAnalysisPhase.recognizing,
      );

  CaptureAnalysisState beginAnalysis() => _transition(
        CaptureAnalysisPhase.analyzing,
      );

  CaptureAnalysisState requireConfirmation([String? reason]) => _transition(
        CaptureAnalysisPhase.needsConfirmation,
        confirmationReason: reason,
      );

  CaptureAnalysisState complete() => _transition(
        CaptureAnalysisPhase.ready,
      );

  CaptureAnalysisState fail(String message) => _transition(
        CaptureAnalysisPhase.failed,
        errorMessage: message,
      );

  CaptureAnalysisState markRetryable(
    String message, {
    required CaptureFailureKind kind,
  }) {
    final nextRetryCount = _state.retryCount + 1;
    if (!retryPolicy.canRetry(nextRetryCount)) {
      return _transition(
        CaptureAnalysisPhase.failed,
        errorMessage: message,
        failureKind: kind,
      );
    }
    return _transition(
      CaptureAnalysisPhase.retryable,
      errorMessage: message,
      failureKind: kind,
      retryCount: nextRetryCount,
    );
  }

  CaptureAnalysisState cancel() => _transition(
        CaptureAnalysisPhase.cancelled,
      );

  CaptureAnalysisState reset() {
    final next = _transition(CaptureAnalysisPhase.idle);
    clearDraft();
    return next;
  }

  CaptureAnalysisState _transition(
    CaptureAnalysisPhase next, {
    String? imagePath,
    String? errorMessage,
    String? confirmationReason,
    CaptureFailureKind? failureKind,
    int? retryCount,
  }) {
    return _state = _state.transitionTo(
      next,
      imagePath: imagePath,
      errorMessage: errorMessage,
      confirmationReason: confirmationReason,
      failureKind: failureKind,
      retryCount: retryCount,
    );
  }
}
