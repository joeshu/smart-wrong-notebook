import 'package:flutter_test/flutter_test.dart';
import 'package:smart_wrong_notebook/src/domain/models/ai_analysis_review.dart';
import 'package:smart_wrong_notebook/src/domain/models/analysis_result.dart';
import 'package:smart_wrong_notebook/src/domain/models/content_status.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';
import 'package:smart_wrong_notebook/src/domain/services/ai_analysis_confirmation_service.dart';

void main() {
  const service = AiAnalysisConfirmationService();

  test('explicit confirmation promotes gated result to ready', () {
    final record = _record();
    final confirmed = service.confirm(
      record,
      source: AiConfirmationSource.editedByUser,
      confirmedAt: DateTime.utc(2026, 7, 25),
    );

    expect(confirmed.contentStatus, ContentStatus.ready);
    expect(confirmed.analysisResult?.reviewDecision.disposition,
        AiAnalysisReviewDisposition.autoApproved);
    expect(confirmed.analysisResult?.pipeline.status,
        AiAnalysisPipelineStatus.completed);
    expect(
      confirmed.analysisResult?.reviewDecision.reasons.join(' '),
      contains('confirmationSource=editedByUser'),
    );
  });

  test('cannot confirm a record without analysis', () {
    final record = QuestionRecord.draft(
      id: 'q-no-analysis',
      imagePath: '/tmp/q-no-analysis.jpg',
      subject: Subject.math,
      recognizedText: '解方程 x+1=4',
    ).copyWith(contentStatus: ContentStatus.needsConfirmation);
    expect(
      () => service.confirm(record),
      throwsA(isA<AiAnalysisConfirmationException>()),
    );
  });

  test('cannot silently reconfirm a final ready record', () {
    final record = _record(status: ContentStatus.ready);
    expect(
      () => service.confirm(record),
      throwsA(isA<AiAnalysisConfirmationException>()),
    );
  });
}

QuestionRecord _record({
  ContentStatus status = ContentStatus.needsConfirmation,
  AnalysisResult? analysisResult,
}) {
  return QuestionRecord.draft(
    id: 'q-confirm',
    imagePath: '/tmp/q-confirm.jpg',
    subject: Subject.math,
    recognizedText: '解方程 x+1=4',
  ).copyWith(
    contentStatus: status,
    analysisResult: analysisResult ?? const AnalysisResult(
      finalAnswer: '3',
      steps: <String>['移项得 x=3'],
      aiTags: <String>['方程'],
      knowledgePoints: <String>['一元一次方程'],
      mistakeReason: '',
      studyAdvice: '检查符号',
      reviewDecision: AiAnalysisReviewDecision(
        disposition: AiAnalysisReviewDisposition.needsConfirmation,
        fields: <String>['standardAnswer'],
        reasons: <String>['标准答案置信度不足'],
      ),
      pipeline: AiAnalysisPipelineSnapshot(
        status: AiAnalysisPipelineStatus.waitingForConfirmation,
        currentStage: AiAnalysisPipelineStage.questionConfirmation,
      ),
    ),
  ).copyWith(contentStatus: status);
}
