import 'question_record.dart';

/// Pure domain state for the capture -> recognition -> analysis workflow.
enum CaptureAnalysisPhase {
  idle,
  imageSelected,
  cropping,
  recognizing,
  analyzing,
  needsConfirmation,
  ready,
  retryable,
  failed,
  cancelled,
}

enum CaptureFailureKind { ocr, ai, timeout, unknown, cancelled }

/// Volatile, in-memory snapshot for the current capture route.
class CaptureSessionDraft {
  const CaptureSessionDraft({required this.question, required this.phase});

  final QuestionRecord question;
  final CaptureAnalysisPhase phase;

  String get imagePath => question.imagePath;
  String get recognizedText => question.recognizedText;
}

/// Central defaults for recoverable remote work. The policy is pure so callers
/// do not invent retry limits or delay calculations in individual screens.
class CaptureRetryPolicy {
  const CaptureRetryPolicy({
    this.maxRetries = 3,
    this.initialBackoff = const Duration(seconds: 2),
    this.maxBackoff = const Duration(seconds: 30),
  });

  final int maxRetries;
  final Duration initialBackoff;
  final Duration maxBackoff;

  bool canRetry(int retryCount) => retryCount <= maxRetries;

  Duration backoffFor(int retryCount) {
    if (retryCount <= 0) return Duration.zero;
    var seconds = initialBackoff.inSeconds;
    for (var index = 1; index < retryCount; index++) {
      seconds = (seconds * 2).clamp(0, maxBackoff.inSeconds).toInt();
    }
    return Duration(seconds: seconds.clamp(0, maxBackoff.inSeconds).toInt());
  }
}

class InvalidCaptureAnalysisTransition implements Exception {
  const InvalidCaptureAnalysisTransition(this.from, this.to);

  final CaptureAnalysisPhase from;
  final CaptureAnalysisPhase to;

  @override
  String toString() =>
      'Invalid capture analysis transition: ${from.name} -> ${to.name}';
}

class CaptureAnalysisState {
  const CaptureAnalysisState(
    this.phase, {
    this.imagePath,
    this.errorMessage,
    this.confirmationReason,
    this.failureKind,
    this.retryCount = 0,
  });

  const CaptureAnalysisState.initial()
      : phase = CaptureAnalysisPhase.idle,
        imagePath = null,
        errorMessage = null,
        confirmationReason = null,
        failureKind = null,
        retryCount = 0;

  final CaptureAnalysisPhase phase;
  final String? imagePath;
  final String? errorMessage;
  final String? confirmationReason;
  final CaptureFailureKind? failureKind;
  final int retryCount;

  bool get isTerminal =>
      phase == CaptureAnalysisPhase.ready ||
      phase == CaptureAnalysisPhase.failed ||
      phase == CaptureAnalysisPhase.cancelled;

  bool get isRetryable => phase == CaptureAnalysisPhase.retryable;

  CaptureAnalysisState transitionTo(
    CaptureAnalysisPhase next, {
    String? imagePath,
    String? errorMessage,
    String? confirmationReason,
    CaptureFailureKind? failureKind,
    int? retryCount,
  }) {
    if (!_allowedTransitions[phase]!.contains(next)) {
      throw InvalidCaptureAnalysisTransition(phase, next);
    }
    if (next == CaptureAnalysisPhase.imageSelected &&
        (imagePath ?? this.imagePath)?.trim().isEmpty != false) {
      throw ArgumentError.value(imagePath, 'imagePath', 'must not be empty');
    }
    if ((next == CaptureAnalysisPhase.failed ||
            next == CaptureAnalysisPhase.retryable) &&
        (errorMessage ?? '').trim().isEmpty) {
      throw ArgumentError.value(
          errorMessage, 'errorMessage', 'must describe the failure');
    }
    if (next == CaptureAnalysisPhase.idle) {
      return const CaptureAnalysisState.initial();
    }
    return CaptureAnalysisState(
      next,
      imagePath: imagePath ?? this.imagePath,
      errorMessage: next == CaptureAnalysisPhase.failed ||
              next == CaptureAnalysisPhase.retryable
          ? errorMessage
          : null,
      confirmationReason: next == CaptureAnalysisPhase.needsConfirmation
          ? confirmationReason
          : null,
      failureKind: next == CaptureAnalysisPhase.failed ||
              next == CaptureAnalysisPhase.retryable
          ? failureKind
          : null,
      retryCount: retryCount ??
          (next == CaptureAnalysisPhase.ready ||
                  next == CaptureAnalysisPhase.cancelled
              ? 0
              : this.retryCount),
    );
  }

  static const Map<CaptureAnalysisPhase, Set<CaptureAnalysisPhase>>
      _allowedTransitions = {
    CaptureAnalysisPhase.idle: {
      CaptureAnalysisPhase.imageSelected,
      // 复制粘贴录入无图片，不经过 imageSelected，直接进入分析阶段。
      CaptureAnalysisPhase.analyzing,
    },
    CaptureAnalysisPhase.imageSelected: {
      CaptureAnalysisPhase.idle,
      CaptureAnalysisPhase.cropping,
      CaptureAnalysisPhase.recognizing,
      CaptureAnalysisPhase.cancelled,
    },
    CaptureAnalysisPhase.cropping: {
      CaptureAnalysisPhase.recognizing,
      CaptureAnalysisPhase.cancelled,
    },
    CaptureAnalysisPhase.recognizing: {
      CaptureAnalysisPhase.analyzing,
      CaptureAnalysisPhase.needsConfirmation,
      CaptureAnalysisPhase.retryable,
      CaptureAnalysisPhase.failed,
      CaptureAnalysisPhase.cancelled,
    },
    CaptureAnalysisPhase.analyzing: {
      CaptureAnalysisPhase.ready,
      CaptureAnalysisPhase.needsConfirmation,
      CaptureAnalysisPhase.retryable,
      CaptureAnalysisPhase.failed,
      CaptureAnalysisPhase.cancelled,
      // 允许分析中直接结束会话回 idle（endSession：复制粘贴录入保存草稿失败等场景）
      CaptureAnalysisPhase.idle,
    },
    CaptureAnalysisPhase.needsConfirmation: {
      CaptureAnalysisPhase.analyzing,
      CaptureAnalysisPhase.ready,
      CaptureAnalysisPhase.cancelled,
    },
    CaptureAnalysisPhase.ready: {CaptureAnalysisPhase.idle},
    CaptureAnalysisPhase.failed: {
      CaptureAnalysisPhase.recognizing,
      CaptureAnalysisPhase.analyzing,
      CaptureAnalysisPhase.idle,
    },
    CaptureAnalysisPhase.retryable: {
      CaptureAnalysisPhase.recognizing,
      CaptureAnalysisPhase.analyzing,
      CaptureAnalysisPhase.cancelled,
      CaptureAnalysisPhase.idle,
    },
    CaptureAnalysisPhase.cancelled: {CaptureAnalysisPhase.idle},
  };
}
