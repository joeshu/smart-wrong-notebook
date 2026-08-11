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

// --- Theme mode ---

final StateNotifierProvider<AppVisualStyleNotifier, AppVisualStyle>
    appVisualStyleProvider =
    StateNotifierProvider<AppVisualStyleNotifier, AppVisualStyle>((ref) {
  return AppVisualStyleNotifier(ref.read(settingsRepositoryProvider));
});

class AppVisualStyleNotifier extends StateNotifier<AppVisualStyle> {
  AppVisualStyleNotifier(this._settingsRepo) : super(AppVisualStyle.academic) {
    _load();
  }

  final SettingsRepository _settingsRepo;

  Future<void> _load() async {
    final value = await _settingsRepo.getString('app_visual_style');
    state = AppVisualStyle.values.firstWhere(
      (style) => style.name == value,
      orElse: () => AppVisualStyle.academic,
    );
  }

  Future<void> setStyle(AppVisualStyle style) async {
    state = style;
    await _settingsRepo.setString('app_visual_style', style.name);
  }
}

final StateNotifierProvider<ThemeModeNotifier, ThemeMode> themeModeProvider =
    StateNotifierProvider<ThemeModeNotifier, ThemeMode>((ref) {
  return ThemeModeNotifier(ref.read(settingsRepositoryProvider));
});

class ThemeModeNotifier extends StateNotifier<ThemeMode> {
  ThemeModeNotifier(this._settingsRepo) : super(ThemeMode.system) {
    _load();
  }

  final SettingsRepository _settingsRepo;

  Future<void> _load() async {
    final value = await _settingsRepo.getString('theme_mode');
    final mode = switch (value) {
      'light' => ThemeMode.light,
      'dark' => ThemeMode.dark,
      _ => ThemeMode.system,
    };
    state = mode;
  }

  Future<void> setMode(ThemeMode mode) async {
    state = mode;
    final value = switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    };
    await _settingsRepo.setString('theme_mode', value);
  }
}

final StateNotifierProvider<ReviewReminderNotifier, bool> reviewReminderEnabledProvider =
    StateNotifierProvider<ReviewReminderNotifier, bool>((ref) {
  return ReviewReminderNotifier(ref.read(settingsRepositoryProvider));
});

class ReviewReminderNotifier extends StateNotifier<bool> {
  ReviewReminderNotifier(this._settingsRepo) : super(true) {
    _load();
  }

  final SettingsRepository _settingsRepo;

  Future<void> _load() async {
    final value = await _settingsRepo.getString('review_reminder_enabled');
    state = value != 'false';
  }

  Future<void> setEnabled(bool enabled) async {
    state = enabled;
    await _settingsRepo.setString('review_reminder_enabled', enabled ? 'true' : 'false');
  }
}

/// Phase 9-3：定时复习提醒时间（24 小时制）。
///
/// 默认 20:00，持久化到 settings 仓库的 `review_reminder_time` 字段
/// （格式 `HH:MM`）。开启 [reviewReminderEnabledProvider] 后由调用方
/// 读取本 provider 并调用 [NotificationService.scheduleDailyReminder]。
final StateNotifierProvider<ReviewReminderTimeNotifier, TimeOfDay>
    reviewReminderTimeProvider = StateNotifierProvider<ReviewReminderTimeNotifier,
        TimeOfDay>((ref) {
  return ReviewReminderTimeNotifier(ref.read(settingsRepositoryProvider));
});

class ReviewReminderTimeNotifier extends StateNotifier<TimeOfDay> {
  ReviewReminderTimeNotifier(this._settingsRepo)
      : super(const TimeOfDay(hour: 20, minute: 0)) {
    _load();
  }

  final SettingsRepository _settingsRepo;

  Future<void> _load() async {
    final value = await _settingsRepo.getString('review_reminder_time');
    if (value == null || !value.contains(':')) return;
    final parts = value.split(':');
    if (parts.length != 2) return;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return;
    if (h < 0 || h > 23 || m < 0 || m > 59) return;
    state = TimeOfDay(hour: h, minute: m);
  }

  Future<void> setTime(TimeOfDay time) async {
    state = time;
    final hh = time.hour.toString().padLeft(2, '0');
    final mm = time.minute.toString().padLeft(2, '0');
    await _settingsRepo.setString('review_reminder_time', '$hh:$mm');
  }
}
