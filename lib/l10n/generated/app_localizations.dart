import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'generated/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations)!;
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('zh'),
    Locale('en')
  ];

  /// No description provided for @appName.
  ///
  /// In zh, this message translates to:
  /// **'AI错题本'**
  String get appName;

  /// No description provided for @homeTab.
  ///
  /// In zh, this message translates to:
  /// **'首页'**
  String get homeTab;

  /// No description provided for @notebookTab.
  ///
  /// In zh, this message translates to:
  /// **'错题本'**
  String get notebookTab;

  /// No description provided for @reviewTab.
  ///
  /// In zh, this message translates to:
  /// **'复习'**
  String get reviewTab;

  /// No description provided for @settingsTab.
  ///
  /// In zh, this message translates to:
  /// **'设置'**
  String get settingsTab;

  /// No description provided for @homeGreeting.
  ///
  /// In zh, this message translates to:
  /// **'今天，开始学习'**
  String get homeGreeting;

  /// No description provided for @homeSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'先完成计划，再记录新的错题'**
  String get homeSubtitle;

  /// No description provided for @homeQuickStart.
  ///
  /// In zh, this message translates to:
  /// **'快速开始'**
  String get homeQuickStart;

  /// No description provided for @homeCapture.
  ///
  /// In zh, this message translates to:
  /// **'录入错题'**
  String get homeCapture;

  /// No description provided for @homeReviewPlan.
  ///
  /// In zh, this message translates to:
  /// **'今日优先 · 复习计划'**
  String get homeReviewPlan;

  /// No description provided for @homeStatsTitle.
  ///
  /// In zh, this message translates to:
  /// **'学习统计'**
  String get homeStatsTitle;

  /// No description provided for @homeRecentTitle.
  ///
  /// In zh, this message translates to:
  /// **'最近新增'**
  String get homeRecentTitle;

  /// No description provided for @homeViewAll.
  ///
  /// In zh, this message translates to:
  /// **'查看全部'**
  String get homeViewAll;

  /// No description provided for @homeMistakeCategories.
  ///
  /// In zh, this message translates to:
  /// **'常见错因'**
  String get homeMistakeCategories;

  /// No description provided for @homeEmptyTip.
  ///
  /// In zh, this message translates to:
  /// **'暂无错题，拍照开始添加'**
  String get homeEmptyTip;

  /// No description provided for @homeBatchPriority.
  ///
  /// In zh, this message translates to:
  /// **'今日优先 · 待处理事项'**
  String get homeBatchPriority;

  /// No description provided for @homeBatchRemaining.
  ///
  /// In zh, this message translates to:
  /// **'项'**
  String get homeBatchRemaining;

  /// No description provided for @homeBatchFailed.
  ///
  /// In zh, this message translates to:
  /// **'道分析失败题'**
  String get homeBatchFailed;

  /// No description provided for @homeBatchDrafts.
  ///
  /// In zh, this message translates to:
  /// **'道 OCR 草稿待确认'**
  String get homeBatchDrafts;

  /// No description provided for @homeBatchPending.
  ///
  /// In zh, this message translates to:
  /// **'道题尚未处理'**
  String get homeBatchPending;

  /// No description provided for @homeBatchRetry.
  ///
  /// In zh, this message translates to:
  /// **'重新分析'**
  String get homeBatchRetry;

  /// No description provided for @homeBatchContinueCorrection.
  ///
  /// In zh, this message translates to:
  /// **'继续校对'**
  String get homeBatchContinueCorrection;

  /// No description provided for @homeBatchContinueProcess.
  ///
  /// In zh, this message translates to:
  /// **'继续处理'**
  String get homeBatchContinueProcess;

  /// No description provided for @homeNoReviewToday.
  ///
  /// In zh, this message translates to:
  /// **'今天暂无待复习题'**
  String get homeNoReviewToday;

  /// No description provided for @homeReviewDue.
  ///
  /// In zh, this message translates to:
  /// **'题待复习'**
  String get homeReviewDue;

  /// No description provided for @homeReviewEstimated.
  ///
  /// In zh, this message translates to:
  /// **'预计 {minutes} 分钟'**
  String homeReviewEstimated(int minutes);

  /// No description provided for @homeReviewCompleted.
  ///
  /// In zh, this message translates to:
  /// **'已完成 {done} / {total}'**
  String homeReviewCompleted(int done, int total);

  /// No description provided for @homeStreakDays.
  ///
  /// In zh, this message translates to:
  /// **'连续学习 {days} 天'**
  String homeStreakDays(int days);

  /// No description provided for @homeStartReview.
  ///
  /// In zh, this message translates to:
  /// **'开始今日复习'**
  String get homeStartReview;

  /// No description provided for @homeMasterProgress.
  ///
  /// In zh, this message translates to:
  /// **'掌握进度'**
  String get homeMasterProgress;

  /// No description provided for @homeMasteredCount.
  ///
  /// In zh, this message translates to:
  /// **'{mastered} / {total} 已掌握'**
  String homeMasteredCount(int mastered, int total);

  /// No description provided for @homePendingCount.
  ///
  /// In zh, this message translates to:
  /// **'{count} 待复习'**
  String homePendingCount(int count);

  /// No description provided for @homePlanError.
  ///
  /// In zh, this message translates to:
  /// **'今日计划暂时无法读取。'**
  String get homePlanError;

  /// No description provided for @homeStatsError.
  ///
  /// In zh, this message translates to:
  /// **'学习统计暂时无法读取。'**
  String get homeStatsError;

  /// No description provided for @reviewTitle.
  ///
  /// In zh, this message translates to:
  /// **'复习'**
  String get reviewTitle;

  /// No description provided for @reviewPending.
  ///
  /// In zh, this message translates to:
  /// **'待复习'**
  String get reviewPending;

  /// No description provided for @reviewScheduled.
  ///
  /// In zh, this message translates to:
  /// **'已安排'**
  String get reviewScheduled;

  /// No description provided for @reviewHistory.
  ///
  /// In zh, this message translates to:
  /// **'复习记录'**
  String get reviewHistory;

  /// No description provided for @reviewOverallProgress.
  ///
  /// In zh, this message translates to:
  /// **'整体进度'**
  String get reviewOverallProgress;

  /// No description provided for @reviewTodayProgress.
  ///
  /// In zh, this message translates to:
  /// **'今日完成'**
  String get reviewTodayProgress;

  /// No description provided for @reviewEmptyPending.
  ///
  /// In zh, this message translates to:
  /// **'暂无待复习错题'**
  String get reviewEmptyPending;

  /// No description provided for @reviewEmptyScheduled.
  ///
  /// In zh, this message translates to:
  /// **'暂无已安排复习'**
  String get reviewEmptyScheduled;

  /// No description provided for @notebookTitle.
  ///
  /// In zh, this message translates to:
  /// **'错题本'**
  String get notebookTitle;

  /// No description provided for @notebookSearchHint.
  ///
  /// In zh, this message translates to:
  /// **'搜索错题'**
  String get notebookSearchHint;

  /// No description provided for @notebookFilterAll.
  ///
  /// In zh, this message translates to:
  /// **'全部'**
  String get notebookFilterAll;

  /// No description provided for @notebookFilterDue.
  ///
  /// In zh, this message translates to:
  /// **'待复习'**
  String get notebookFilterDue;

  /// No description provided for @notebookFilterUnmastered.
  ///
  /// In zh, this message translates to:
  /// **'未掌握'**
  String get notebookFilterUnmastered;

  /// No description provided for @notebookFilterFavorite.
  ///
  /// In zh, this message translates to:
  /// **'收藏'**
  String get notebookFilterFavorite;

  /// No description provided for @notebookFilterMore.
  ///
  /// In zh, this message translates to:
  /// **'筛选'**
  String get notebookFilterMore;

  /// No description provided for @notebookEmptyTitle.
  ///
  /// In zh, this message translates to:
  /// **'还没有错题'**
  String get notebookEmptyTitle;

  /// No description provided for @notebookEmptySubtitle.
  ///
  /// In zh, this message translates to:
  /// **'拍照录入一道错题，或导入整页试卷开始整理。'**
  String get notebookEmptySubtitle;

  /// No description provided for @notebookAdvancedFilter.
  ///
  /// In zh, this message translates to:
  /// **'高级筛选'**
  String get notebookAdvancedFilter;

  /// No description provided for @notebookClearFilters.
  ///
  /// In zh, this message translates to:
  /// **'清除全部'**
  String get notebookClearFilters;

  /// No description provided for @notebookDone.
  ///
  /// In zh, this message translates to:
  /// **'完成'**
  String get notebookDone;

  /// No description provided for @detailTitle.
  ///
  /// In zh, this message translates to:
  /// **'错题详情'**
  String get detailTitle;

  /// No description provided for @detailTabQuestion.
  ///
  /// In zh, this message translates to:
  /// **'题目'**
  String get detailTabQuestion;

  /// No description provided for @detailTabAnalysis.
  ///
  /// In zh, this message translates to:
  /// **'解析'**
  String get detailTabAnalysis;

  /// No description provided for @detailTabPractice.
  ///
  /// In zh, this message translates to:
  /// **'练习'**
  String get detailTabPractice;

  /// No description provided for @detailTabRecord.
  ///
  /// In zh, this message translates to:
  /// **'记录'**
  String get detailTabRecord;

  /// No description provided for @detailLearningProfile.
  ///
  /// In zh, this message translates to:
  /// **'学习档案'**
  String get detailLearningProfile;

  /// No description provided for @detailMistakeCategory.
  ///
  /// In zh, this message translates to:
  /// **'错因分类'**
  String get detailMistakeCategory;

  /// No description provided for @detailOriginalQuestion.
  ///
  /// In zh, this message translates to:
  /// **'原题'**
  String get detailOriginalQuestion;

  /// No description provided for @detailCorrectAnswer.
  ///
  /// In zh, this message translates to:
  /// **'正确答案'**
  String get detailCorrectAnswer;

  /// No description provided for @detailPossibleAnswer.
  ///
  /// In zh, this message translates to:
  /// **'可能解法'**
  String get detailPossibleAnswer;

  /// No description provided for @detailMistakeReason.
  ///
  /// In zh, this message translates to:
  /// **'错因分析'**
  String get detailMistakeReason;

  /// No description provided for @detailStudyAdvice.
  ///
  /// In zh, this message translates to:
  /// **'学习建议'**
  String get detailStudyAdvice;

  /// No description provided for @detailKnowledgePoints.
  ///
  /// In zh, this message translates to:
  /// **'知识点'**
  String get detailKnowledgePoints;

  /// No description provided for @detailSolutionSteps.
  ///
  /// In zh, this message translates to:
  /// **'解题步骤'**
  String get detailSolutionSteps;

  /// No description provided for @detailSimilarExercises.
  ///
  /// In zh, this message translates to:
  /// **'举一反三'**
  String get detailSimilarExercises;

  /// No description provided for @detailNoAnalysis.
  ///
  /// In zh, this message translates to:
  /// **'暂无 AI 解析结果'**
  String get detailNoAnalysis;

  /// No description provided for @settingsTitle.
  ///
  /// In zh, this message translates to:
  /// **'设置'**
  String get settingsTitle;

  /// No description provided for @settingsAppearance.
  ///
  /// In zh, this message translates to:
  /// **'外观'**
  String get settingsAppearance;

  /// No description provided for @settingsThemeSystem.
  ///
  /// In zh, this message translates to:
  /// **'系统'**
  String get settingsThemeSystem;

  /// No description provided for @settingsThemeLight.
  ///
  /// In zh, this message translates to:
  /// **'浅色'**
  String get settingsThemeLight;

  /// No description provided for @settingsThemeDark.
  ///
  /// In zh, this message translates to:
  /// **'深色'**
  String get settingsThemeDark;

  /// No description provided for @settingsReminders.
  ///
  /// In zh, this message translates to:
  /// **'提醒'**
  String get settingsReminders;

  /// No description provided for @settingsReviewReminder.
  ///
  /// In zh, this message translates to:
  /// **'复习提醒'**
  String get settingsReviewReminder;

  /// No description provided for @settingsReviewReminderSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'发送待复习错题通知'**
  String get settingsReviewReminderSubtitle;

  /// No description provided for @settingsReviewReminderSent.
  ///
  /// In zh, this message translates to:
  /// **'已发送复习提醒'**
  String get settingsReviewReminderSent;

  /// No description provided for @settingsReviewReminderNoDue.
  ///
  /// In zh, this message translates to:
  /// **'当前没有到期错题，或通知权限未开启'**
  String get settingsReviewReminderNoDue;

  /// No description provided for @settingsAiService.
  ///
  /// In zh, this message translates to:
  /// **'AI 服务'**
  String get settingsAiService;

  /// No description provided for @settingsAiProvider.
  ///
  /// In zh, this message translates to:
  /// **'AI 服务商配置'**
  String get settingsAiProvider;

  /// No description provided for @settingsLayoutProvider.
  ///
  /// In zh, this message translates to:
  /// **'试卷版面识别'**
  String get settingsLayoutProvider;

  /// No description provided for @settingsLayoutProviderSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'视觉模型 / NAS / MinerU / 自定义服务'**
  String get settingsLayoutProviderSubtitle;

  /// No description provided for @settingsAiPrompts.
  ///
  /// In zh, this message translates to:
  /// **'AI 分析偏好'**
  String get settingsAiPrompts;

  /// No description provided for @settingsContent.
  ///
  /// In zh, this message translates to:
  /// **'内容'**
  String get settingsContent;

  /// No description provided for @settingsSubjects.
  ///
  /// In zh, this message translates to:
  /// **'科目管理'**
  String get settingsSubjects;

  /// No description provided for @settingsDataSecurity.
  ///
  /// In zh, this message translates to:
  /// **'数据与安全'**
  String get settingsDataSecurity;

  /// No description provided for @settingsDataManagement.
  ///
  /// In zh, this message translates to:
  /// **'备份、恢复与存储'**
  String get settingsDataManagement;

  /// No description provided for @settingsDataManagementSubtitle.
  ///
  /// In zh, this message translates to:
  /// **'完整备份、导入恢复、导出讲义与清理数据'**
  String get settingsDataManagementSubtitle;

  /// No description provided for @providerConfigTitle.
  ///
  /// In zh, this message translates to:
  /// **'AI 服务配置'**
  String get providerConfigTitle;

  /// No description provided for @providerConfigUrlLabel.
  ///
  /// In zh, this message translates to:
  /// **'API 地址'**
  String get providerConfigUrlLabel;

  /// No description provided for @providerConfigUrlHint.
  ///
  /// In zh, this message translates to:
  /// **'https://api.openai.com/v1 或 https://openrouter.ai/api/v1'**
  String get providerConfigUrlHint;

  /// No description provided for @providerConfigModelLabel.
  ///
  /// In zh, this message translates to:
  /// **'模型'**
  String get providerConfigModelLabel;

  /// No description provided for @providerConfigModelHint.
  ///
  /// In zh, this message translates to:
  /// **'gpt-4o, gemini-2.0-flash-thinking-exp-121 等'**
  String get providerConfigModelHint;

  /// No description provided for @providerConfigApiKeyLabel.
  ///
  /// In zh, this message translates to:
  /// **'API Key'**
  String get providerConfigApiKeyLabel;

  /// No description provided for @providerConfigApiKeyHint.
  ///
  /// In zh, this message translates to:
  /// **'sk-...'**
  String get providerConfigApiKeyHint;

  /// No description provided for @providerConfigTest.
  ///
  /// In zh, this message translates to:
  /// **'测试连接'**
  String get providerConfigTest;

  /// No description provided for @providerConfigTesting.
  ///
  /// In zh, this message translates to:
  /// **'测试中...'**
  String get providerConfigTesting;

  /// No description provided for @providerConfigSave.
  ///
  /// In zh, this message translates to:
  /// **'保存'**
  String get providerConfigSave;

  /// No description provided for @providerConfigSaved.
  ///
  /// In zh, this message translates to:
  /// **'配置已保存'**
  String get providerConfigSaved;

  /// No description provided for @providerConfigIncomplete.
  ///
  /// In zh, this message translates to:
  /// **'请填写完整的配置信息'**
  String get providerConfigIncomplete;

  /// No description provided for @providerConfigUrlRequired.
  ///
  /// In zh, this message translates to:
  /// **'请输入 API 地址'**
  String get providerConfigUrlRequired;

  /// No description provided for @providerConfigModelRequired.
  ///
  /// In zh, this message translates to:
  /// **'请输入模型名称'**
  String get providerConfigModelRequired;

  /// No description provided for @providerConfigApiKeyRequired.
  ///
  /// In zh, this message translates to:
  /// **'请输入 API Key'**
  String get providerConfigApiKeyRequired;

  /// No description provided for @providerConfigTestSuccess.
  ///
  /// In zh, this message translates to:
  /// **'✓ 成功！\n\nAPI 连接正常，配置已保存！\n\n现在可以拍照测试了。'**
  String get providerConfigTestSuccess;

  /// No description provided for @providerConfigTestFailed.
  ///
  /// In zh, this message translates to:
  /// **'✗ 连接失败\n\n'**
  String get providerConfigTestFailed;

  /// No description provided for @providerConfigSaveFailed.
  ///
  /// In zh, this message translates to:
  /// **'✗ 保存失败\n\n无法读取保存的配置，请重试'**
  String get providerConfigSaveFailed;

  /// No description provided for @captureTitle.
  ///
  /// In zh, this message translates to:
  /// **'录入错题'**
  String get captureTitle;

  /// No description provided for @captureCamera.
  ///
  /// In zh, this message translates to:
  /// **'拍照'**
  String get captureCamera;

  /// No description provided for @captureCameraDesc.
  ///
  /// In zh, this message translates to:
  /// **'使用相机拍摄错题'**
  String get captureCameraDesc;

  /// No description provided for @captureGallery.
  ///
  /// In zh, this message translates to:
  /// **'相册'**
  String get captureGallery;

  /// No description provided for @captureGalleryDesc.
  ///
  /// In zh, this message translates to:
  /// **'从相册选择图片'**
  String get captureGalleryDesc;

  /// No description provided for @captureWorksheet.
  ///
  /// In zh, this message translates to:
  /// **'试卷批量导入'**
  String get captureWorksheet;

  /// No description provided for @captureWorksheetDesc.
  ///
  /// In zh, this message translates to:
  /// **'一次选择多页，逐页确认切题'**
  String get captureWorksheetDesc;

  /// No description provided for @cancel.
  ///
  /// In zh, this message translates to:
  /// **'取消'**
  String get cancel;

  /// No description provided for @save.
  ///
  /// In zh, this message translates to:
  /// **'保存'**
  String get save;

  /// No description provided for @delete.
  ///
  /// In zh, this message translates to:
  /// **'删除'**
  String get delete;

  /// No description provided for @confirm.
  ///
  /// In zh, this message translates to:
  /// **'确认'**
  String get confirm;

  /// No description provided for @retry.
  ///
  /// In zh, this message translates to:
  /// **'重试'**
  String get retry;

  /// No description provided for @edit.
  ///
  /// In zh, this message translates to:
  /// **'编辑'**
  String get edit;

  /// No description provided for @close.
  ///
  /// In zh, this message translates to:
  /// **'关闭'**
  String get close;

  /// No description provided for @next.
  ///
  /// In zh, this message translates to:
  /// **'下一步'**
  String get next;

  /// No description provided for @start.
  ///
  /// In zh, this message translates to:
  /// **'开始'**
  String get start;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
