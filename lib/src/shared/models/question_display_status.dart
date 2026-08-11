import 'package:flutter/material.dart';

import 'package:smart_wrong_notebook/src/domain/models/content_status.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_colors.dart';

/// 错题的统一展示状态。
///
/// 由 [inferQuestionDisplayStatus] 从 `QuestionRecord` 的
/// `contentStatus` + `analysisResult` 派生，全仓库（首页、题卡、详情页、
/// 批量任务）共用同一套文案与配色，避免各页面硬编码导致口径分裂。
///
/// 与 [ContentStatus] 的区别：[ContentStatus] 是持久化的粗粒度处理状态，
/// [QuestionDisplayStatus] 是面向用户的细粒度展示状态，额外区分了
/// "已识别待分析"与"已分析"。
enum QuestionDisplayStatus {
  /// 识别中（OCR 进行中）。
  recognizing,

  /// 分析中（AI 分析进行中）。
  analyzing,

  /// 已识别待分析（OCR 成功，未交给 AI）。
  recognized,

  /// AI 分析完成，但低置信度字段尚未确认。
  needsConfirmation,

  /// 已分析（AI 分析成功）。
  analyzed,

  /// 识别失败（OCR 失败）。
  recognitionFailed,

  /// 分析失败（AI 失败，OCR 已成功）。
  analysisFailed,
}

extension QuestionDisplayStatusX on QuestionDisplayStatus {
  /// 统一展示文案，用于状态标签。
  String get label {
    switch (this) {
      case QuestionDisplayStatus.recognizing:
        return '识别中';
      case QuestionDisplayStatus.analyzing:
        return '分析中';
      case QuestionDisplayStatus.recognized:
        return '待 AI 分析';
      case QuestionDisplayStatus.needsConfirmation:
        return '待人工确认';
      case QuestionDisplayStatus.analyzed:
        return 'AI 已分析';
      case QuestionDisplayStatus.recognitionFailed:
        return '识别失败';
      case QuestionDisplayStatus.analysisFailed:
        return '分析失败';
    }
  }

  /// 统一前景色，用于标签文字与图标。
  Color get foregroundColor {
    switch (this) {
      case QuestionDisplayStatus.recognizing:
      case QuestionDisplayStatus.analyzing:
        return AppColors.info;
      case QuestionDisplayStatus.recognized:
        return AppColors.primary;
      case QuestionDisplayStatus.needsConfirmation:
        return AppColors.warning;
      case QuestionDisplayStatus.analyzed:
        return AppColors.success;
      case QuestionDisplayStatus.recognitionFailed:
      case QuestionDisplayStatus.analysisFailed:
        return AppColors.danger;
    }
  }

  /// 统一背景色（浅色），用于标签底色。
  Color backgroundColor(Brightness brightness) {
    switch (this) {
      case QuestionDisplayStatus.recognizing:
      case QuestionDisplayStatus.analyzing:
        return brightness == Brightness.dark
            ? AppColors.info.withValues(alpha: 0.24)
            : AppColors.infoContainerLight;
      case QuestionDisplayStatus.recognized:
        return brightness == Brightness.dark
            ? AppColors.primary.withValues(alpha: 0.24)
            : AppColors.primaryContainerLight;
      case QuestionDisplayStatus.needsConfirmation:
        return brightness == Brightness.dark
            ? AppColors.warning.withValues(alpha: 0.24)
            : AppColors.warningContainerLight;
      case QuestionDisplayStatus.analyzed:
        return brightness == Brightness.dark
            ? AppColors.success.withValues(alpha: 0.24)
            : AppColors.successContainerLight;
      case QuestionDisplayStatus.recognitionFailed:
      case QuestionDisplayStatus.analysisFailed:
        return brightness == Brightness.dark
            ? AppColors.danger.withValues(alpha: 0.24)
            : AppColors.dangerContainerLight;
    }
  }

  /// 是否为失败态（识别失败或分析失败）。
  bool get isFailed =>
      this == QuestionDisplayStatus.recognitionFailed ||
      this == QuestionDisplayStatus.analysisFailed;

  /// 是否为进行中态（识别中或分析中）。
  bool get isInProgress =>
      this == QuestionDisplayStatus.recognizing ||
      this == QuestionDisplayStatus.analyzing;
}

/// 从 [QuestionRecord] 派生统一展示状态。
///
/// 推导规则：
/// - `processing` → recognizing
/// - `analyzing` → analyzing
/// - `ready` + `analysisResult == null` → recognized（OCR 草稿，待 AI 分析）
/// - `ready` + `analysisResult != null` → analyzed
/// - `failed` → recognitionFailed
/// - `analysisFailed` → analysisFailed
///
/// 老数据（枚举扩展前）只有 `processing/ready/failed`，能正确回落：
/// - 老的 `failed` 一律视为 recognitionFailed（无法区分是否 OCR 已成功）
/// - 老的 `ready` 根据 analysisResult 区分 recognized/analyzed
QuestionDisplayStatus inferQuestionDisplayStatus(QuestionRecord question) {
  switch (question.contentStatus) {
    case ContentStatus.processing:
      return QuestionDisplayStatus.recognizing;
    case ContentStatus.analyzing:
      return QuestionDisplayStatus.analyzing;
    case ContentStatus.needsConfirmation:
      return QuestionDisplayStatus.needsConfirmation;
    case ContentStatus.ready:
      return question.analysisResult == null
          ? QuestionDisplayStatus.recognized
          : QuestionDisplayStatus.analyzed;
    case ContentStatus.failed:
      return QuestionDisplayStatus.recognitionFailed;
    case ContentStatus.analysisFailed:
      return QuestionDisplayStatus.analysisFailed;
  }
}
