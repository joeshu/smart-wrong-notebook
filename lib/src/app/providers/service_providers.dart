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
import 'package:smart_wrong_notebook/src/data/repositories/worksheet_import_repository.dart';
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
import 'package:smart_wrong_notebook/src/domain/models/worksheet_import_session.dart';
import 'package:smart_wrong_notebook/src/domain/models/worksheet_draft.dart';
import 'package:smart_wrong_notebook/src/domain/models/worksheet_review_summary.dart';
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


import 'repository_providers.dart';

// --- Service providers ---

final Provider<AiAnalysisService> aiAnalysisServiceProvider =
    Provider<AiAnalysisService>((ref) {
  return AiAnalysisService(
      settingsRepository: ref.read(settingsRepositoryProvider));
});

final Provider<ImageStorageService> imageStorageServiceProvider =
    Provider<ImageStorageService>((ref) {
  return ImageStorageService();
});

final Provider<OcrService> ocrServiceProvider = Provider<OcrService>((ref) {
  return OcrService();
});

final Provider<VisionDocumentLayoutService> visionDocumentLayoutServiceProvider =
    Provider<VisionDocumentLayoutService>((ref) {
  return VisionDocumentLayoutService(ref.read(aiAnalysisServiceProvider));
});

final Provider<QuestionRegionCropService> questionRegionCropServiceProvider =
    Provider<QuestionRegionCropService>((ref) {
  return QuestionRegionCropService(
      storage: ref.read(imageStorageServiceProvider));
});

final Provider<QuestionSplitService> questionSplitServiceProvider =
    Provider<QuestionSplitService>((ref) {
  return QuestionSplitService(
      aiAnalysisService: ref.read(aiAnalysisServiceProvider));
});

final Provider<AnalysisRecoveryService> analysisRecoveryServiceProvider =
    Provider<AnalysisRecoveryService>((ref) => const AnalysisRecoveryService());

final Provider<NotificationService> notificationServiceProvider =
    Provider<NotificationService>((ref) {
  return NotificationService(
      questionRepository: ref.read(questionRepositoryProvider));
});

final Provider<CaptureService> captureServiceProvider =
    Provider<CaptureService>((ref) {
  return CaptureService(storage: ref.read(imageStorageServiceProvider));
});
