import 'package:smart_wrong_notebook/src/domain/models/ai_analysis_review.dart';
import 'package:smart_wrong_notebook/src/domain/models/content_status.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';

/// The explicit user action that turns a gated result into a trusted record.
enum AiConfirmationSource {
  currentResult,
  editedByUser,
  retriedFields,
}

class AiAnalysisConfirmationService {
  const AiAnalysisConfirmationService();

  QuestionRecord confirm(
    QuestionRecord record, {
    AiConfirmationSource source = AiConfirmationSource.currentResult,
    DateTime? confirmedAt,
  }) {
    final result = record.analysisResult;
    if (result == null) {
      throw const AiAnalysisConfirmationException('没有可确认的 AI 分析结果');
    }
    if (record.contentStatus != ContentStatus.needsConfirmation ||
        !result.reviewDecision.requiresConfirmation) {
      throw const AiAnalysisConfirmationException('当前题目不在待确认状态');
    }

    final timestamp = confirmedAt ?? DateTime.now();
    final fields = result.reviewDecision.fields.isEmpty
        ? const <String>['analysis']
        : result.reviewDecision.fields;
    final confirmedDecision = AiAnalysisReviewDecision(
      disposition: AiAnalysisReviewDisposition.autoApproved,
      fields: fields,
      reasons: <String>[
        '用户已确认当前 AI 结果',
        'confirmationSource=${source.name}',
        'confirmedAt=${timestamp.toIso8601String()}',
      ],
      evaluatedAt: timestamp,
      confirmedAt: timestamp,
      confirmedFields: fields,
      confirmationSource: source.name,
    );
    final confirmedPipeline = AiAnalysisPipelineSnapshot(
      status: AiAnalysisPipelineStatus.completed,
      completedStages: AiAnalysisPipelineStage.values,
      message: '用户已确认 AI 分析结果',
    );
    return record.copyWith(
      contentStatus: ContentStatus.ready,
      analysisResult: result.copyWith(
        reviewDecision: confirmedDecision,
        pipeline: confirmedPipeline,
      ),
    );
  }
}

class AiAnalysisConfirmationException implements Exception {
  const AiAnalysisConfirmationException(this.message);

  final String message;

  @override
  String toString() => message;
}
