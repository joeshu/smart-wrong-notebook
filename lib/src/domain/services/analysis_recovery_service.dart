import 'package:smart_wrong_notebook/src/domain/models/content_status.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';

/// Normalizes interrupted analysis jobs after app restart or route recovery.
///
/// This intentionally operates on the domain model only. Persistence layers can
/// call it before showing a question queue, without coupling to Flutter widgets.
class AnalysisRecoveryService {
  const AnalysisRecoveryService();

  static const interruptedMessage = '分析被中断，请重试';
  static const recognitionInterruptedMessage = '识别被中断，请重试';

  QuestionRecord recoverInterrupted(QuestionRecord record) {
    if (record.analysisResult != null) return record;
    if (record.contentStatus == ContentStatus.processing) {
      return record.copyWith(
        contentStatus: ContentStatus.analysisFailed,
        lastAnalysisError:
            record.lastAnalysisError ?? recognitionInterruptedMessage,
      );
    }
    if (record.contentStatus != ContentStatus.analyzing) return record;
    return record.copyWith(
      contentStatus: ContentStatus.analysisFailed,
      lastAnalysisError: record.lastAnalysisError ?? interruptedMessage,
    );
  }

  List<QuestionRecord> recoverAll(Iterable<QuestionRecord> records) {
    return records.map(recoverInterrupted).toList(growable: false);
  }
}
