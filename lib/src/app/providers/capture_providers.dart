import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smart_wrong_notebook/src/app/onboarding_notifier.dart';
import 'package:smart_wrong_notebook/src/app/theme/app_visual_style.dart';
import 'package:smart_wrong_notebook/src/data/local/app_database.dart' hide QuestionRecord, ReviewLog, GeneratedExercise;
import 'package:smart_wrong_notebook/src/data/files/image_storage_service.dart';
import 'package:smart_wrong_notebook/src/data/remote/ai/ai_analysis_service.dart';
import 'package:smart_wrong_notebook/src/data/repositories/drift_question_repository.dart';
import 'package:smart_wrong_notebook/src/data/repositories/drift_review_log_repository.dart';
import 'package:smart_wrong_notebook/src/data/repositories/drift_settings_repository.dart';
import 'package:smart_wrong_notebook/src/data/repositories/question_repository.dart';
import 'package:smart_wrong_notebook/src/data/repositories/knowledge_point_repository.dart';
import 'package:smart_wrong_notebook/src/data/repositories/mistake_knowledge_link_repository.dart';
import 'package:smart_wrong_notebook/src/data/repositories/pending_knowledge_point_mapping_repository.dart';
import 'package:smart_wrong_notebook/src/data/repositories/question_knowledge_link_repository.dart';
import 'package:smart_wrong_notebook/src/data/repositories/layout_provider_repository.dart';
import 'package:smart_wrong_notebook/src/data/repositories/worksheet_draft_repository.dart';
import 'package:smart_wrong_notebook/src/data/repositories/settings_repository.dart';
import 'package:smart_wrong_notebook/src/domain/repositories/review_log_repository.dart';
import 'package:smart_wrong_notebook/src/data/services/capture_service.dart';
import 'package:smart_wrong_notebook/src/data/services/notification_service.dart';
import 'package:smart_wrong_notebook/src/data/services/ocr_service.dart';
import 'package:smart_wrong_notebook/src/data/services/question_region_crop_service.dart';
import 'package:smart_wrong_notebook/src/data/services/question_split_service.dart';
import 'package:smart_wrong_notebook/src/data/services/vision_document_layout_service.dart';
import 'package:smart_wrong_notebook/src/domain/models/capture_mode.dart';
import 'package:smart_wrong_notebook/src/domain/models/content_status.dart';
import 'package:smart_wrong_notebook/src/domain/models/layout_provider_config.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_split_result.dart';
import 'package:smart_wrong_notebook/src/domain/models/generated_exercise.dart';
import 'package:smart_wrong_notebook/src/domain/models/knowledge_point.dart';
import 'package:smart_wrong_notebook/src/domain/models/knowledge_point_mastery.dart';
import 'package:smart_wrong_notebook/src/domain/models/mastery_level.dart';
import 'package:smart_wrong_notebook/src/domain/models/mistake_category.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_type.dart';
import 'package:smart_wrong_notebook/src/domain/models/learning_context.dart';
import 'package:smart_wrong_notebook/src/domain/models/pending_knowledge_point_mapping.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_knowledge_link.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_split_session.dart';
import 'package:smart_wrong_notebook/src/domain/models/recommendation.dart';
import 'package:smart_wrong_notebook/src/domain/models/review_log.dart';
import 'package:smart_wrong_notebook/src/domain/models/worksheet_draft.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';
import 'package:smart_wrong_notebook/src/domain/services/knowledge_point_mapping_service.dart';
import 'package:smart_wrong_notebook/src/domain/services/knowledge_point_management_service.dart';
import 'package:smart_wrong_notebook/src/domain/services/knowledge_point_mastery_service.dart';
import 'package:smart_wrong_notebook/src/domain/services/analysis_recovery_service.dart';
import 'package:smart_wrong_notebook/src/domain/services/worksheet_assembly_service.dart';
import 'package:smart_wrong_notebook/src/domain/services/recommendation_service.dart';
import 'package:smart_wrong_notebook/src/domain/services/review_schedule_service.dart';
import 'package:smart_wrong_notebook/src/shared/models/question_display_status.dart';
import 'package:smart_wrong_notebook/src/shared/utils/export_history_service.dart';


import 'service_providers.dart';

// --- Current question flow ---

final StateProvider<QuestionRecord?> currentQuestionProvider =
    StateProvider<QuestionRecord?>((ref) => null);

enum PracticeContextSource { analysis, notebook }

class PracticeContext {
  const PracticeContext({
    required this.source,
    this.candidateId,
    this.candidateOrder,
    required this.returnRoute,
  });

  final PracticeContextSource source;
  final String? candidateId;
  final int? candidateOrder;
  final String returnRoute;
}

final StateProvider<PracticeContext?> currentPracticeContextProvider =
    StateProvider<PracticeContext?>((ref) => null);

final StateProvider<QuestionSplitSession?> currentQuestionSplitSessionProvider =
    StateProvider<QuestionSplitSession?>((ref) => null);

Future<QuestionSplitSession> buildQuestionSplitSession(
  QuestionRecord source, {
  QuestionSplitService splitter = const QuestionSplitService(),
}) async {
  final result = source.splitResult ??
      await _resolveSplitResult(source, splitter: splitter);

  final hasMultipleCandidates = result.hasMultipleCandidates;

  return QuestionSplitSession(
    source: source,
    strategy: result.strategy,
    drafts: result.candidates.map((candidate) {
      final snapshot = source.candidateAnalyses
          .where((analysis) => analysis.order == candidate.order)
          .cast<CandidateAnalysisSnapshot?>()
          .firstWhere((analysis) => analysis != null, orElse: () => null);
      final canSave =
          !hasMultipleCandidates || (snapshot?.isSuccessful ?? false);
      return QuestionSplitDraft(
        id: '${source.id}-${candidate.order - 1}',
        text: candidate.text,
        selected: canSave,
        originalOrder: candidate.order,
        contentFormat: source.contentFormat,
        canSave: canSave,
        disabledReason: canSave ? null : '解析失败，暂不可保存',
      );
    }).toList(),
  );
}

Future<QuestionSplitResult> _resolveSplitResult(
  QuestionRecord source, {
  required QuestionSplitService splitter,
}) async {
  final normalized = source.normalizedQuestionText.trim();
  final extracted = source.extractedQuestionText.trim();
  final seedText = normalized.isNotEmpty ? normalized : extracted;
  return splitter.split(seedText, subject: source.subject);
}

QuestionRecord buildSplitQuestionRecord({
  required QuestionRecord source,
  required QuestionSplitDraft draft,
  required int sortOrder,
}) {
  final trimmedText = draft.text.trim();
  final now = DateTime.now();
  final candidateSnapshot = source.candidateAnalyses
      .where((candidate) {
        return candidate.order == draft.originalOrder;
      })
      .cast<CandidateAnalysisSnapshot?>()
      .firstWhere(
        (candidate) => candidate != null,
        orElse: () => null,
      );
  final hasMultipleCandidates =
      source.splitResult?.hasMultipleCandidates ?? false;
  final analysisResult = candidateSnapshot?.analysisResult ??
      (hasMultipleCandidates ? null : source.analysisResult);
  final savedExercises = (candidateSnapshot?.savedExercises ??
          (hasMultipleCandidates
              ? const <GeneratedExercise>[]
              : source.savedExercises))
      .asMap()
      .entries
      .map((entry) {
    final order = entry.value.order ?? entry.key;
    final roundIndex = entry.value.roundIndex ?? 1;
    return entry.value.copyWith(
      id: '${source.id}-$sortOrder-round-$roundIndex-exercise-${order + 1}',
      questionId: '${source.id}-$sortOrder',
      order: order,
    );
  }).toList();
  final aiTags = candidateSnapshot?.aiTags ??
      (hasMultipleCandidates ? const <String>[] : source.aiTags);
  final aiKnowledgePoints = candidateSnapshot?.aiKnowledgePoints ??
      (hasMultipleCandidates ? const <String>[] : source.aiKnowledgePoints);
  final subject =
      candidateSnapshot?.subject ?? analysisResult?.subject ?? source.subject;

  return QuestionRecord(
    id: '${source.id}-$sortOrder',
    imagePath: source.imagePath,
    subject: subject,
    extractedQuestionText: trimmedText,
    normalizedQuestionText: trimmedText,
    contentFormat: draft.contentFormat ?? source.contentFormat,
    tags: source.tags,
    createdAt: now,
    updatedAt: now,
    lastReviewedAt: null,
    reviewCount: 0,
    isFavorite: false,
    contentStatus: source.contentStatus,
    masteryLevel: MasteryLevel.newQuestion,
    analysisResult: analysisResult,
    savedExercises: savedExercises,
    aiTags: aiTags,
    aiKnowledgePoints: aiKnowledgePoints,
    customTags: source.customTags,
    parentQuestionId: source.id,
    rootQuestionId: source.rootQuestionId ?? source.id,
    splitOrder: sortOrder,
  );
}

// --- Capture mode (printed / handwritten / mixed) ---
//
// 录入时用户选择的识别模式，决定 AI 识别时如何处理图片中的印刷与手写内容。
// 默认 [CaptureMode.printed]，与原有"忽略手写批改"行为保持一致。
final StateProvider<CaptureMode> captureModeProvider =
    StateProvider<CaptureMode>((ref) => CaptureMode.printed);
