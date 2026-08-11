// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appName => 'AI Wrong-Question Notebook';

  @override
  String get homeTab => 'Home';

  @override
  String get notebookTab => 'Notebook';

  @override
  String get reviewTab => 'Review';

  @override
  String get settingsTab => 'Settings';

  @override
  String get homeGreeting => 'Today, start learning';

  @override
  String get homeSubtitle =>
      'Finish your plan first, then add new wrong questions';

  @override
  String get homeQuickStart => 'Quick Start';

  @override
  String get homeCapture => 'Add Wrong Question';

  @override
  String get homeReviewPlan => 'Today\'s Priority · Review Plan';

  @override
  String get homeStatsTitle => 'Study Stats';

  @override
  String get homeRecentTitle => 'Recently Added';

  @override
  String get homeViewAll => 'View All';

  @override
  String get homeMistakeCategories => 'Common Mistakes';

  @override
  String get homeEmptyTip => 'No questions yet. Take a photo to add one.';

  @override
  String get homeBatchPriority => 'Today\'s Priority · Pending';

  @override
  String get homeBatchRemaining => 'item(s)';

  @override
  String get homeBatchFailed => 'failed analysis';

  @override
  String get homeBatchDrafts => 'OCR draft(s) to confirm';

  @override
  String get homeBatchPending => 'question(s) pending';

  @override
  String get homeBatchRetry => 'Re-analyze';

  @override
  String get homeBatchContinueCorrection => 'Continue correcting';

  @override
  String get homeBatchContinueProcess => 'Continue';

  @override
  String get homeNoReviewToday => 'No questions due for review today';

  @override
  String get homeReviewDue => 'due for review';

  @override
  String homeReviewEstimated(int minutes) {
    return 'About $minutes min';
  }

  @override
  String homeReviewCompleted(int done, int total) {
    return '$done / $total done';
  }

  @override
  String homeStreakDays(int days) {
    return '$days-day streak';
  }

  @override
  String get homeStartReview => 'Start today\'s review';

  @override
  String get homeMasterProgress => 'Mastery progress';

  @override
  String homeMasteredCount(int mastered, int total) {
    return '$mastered / $total mastered';
  }

  @override
  String homePendingCount(int count) {
    return '$count to review';
  }

  @override
  String get homePlanError => 'Today\'s plan is temporarily unavailable.';

  @override
  String get homeStatsError => 'Study stats are temporarily unavailable.';

  @override
  String get reviewTitle => 'Review';

  @override
  String get reviewPending => 'Pending';

  @override
  String get reviewScheduled => 'Scheduled';

  @override
  String get reviewHistory => 'Review History';

  @override
  String get reviewOverallProgress => 'Overall Progress';

  @override
  String get reviewTodayProgress => 'Today\'s Progress';

  @override
  String get reviewEmptyPending => 'No questions due for review';

  @override
  String get reviewEmptyScheduled => 'No scheduled reviews';

  @override
  String get notebookTitle => 'Notebook';

  @override
  String get notebookSearchHint => 'Search questions';

  @override
  String get notebookFilterAll => 'All';

  @override
  String get notebookFilterDue => 'Due';

  @override
  String get notebookFilterUnmastered => 'Unmastered';

  @override
  String get notebookFilterFavorite => 'Favorites';

  @override
  String get notebookFilterMore => 'Filter';

  @override
  String get notebookEmptyTitle => 'No questions yet';

  @override
  String get notebookEmptySubtitle =>
      'Take a photo to add a wrong question, or import a worksheet to begin.';

  @override
  String get notebookAdvancedFilter => 'Advanced filters';

  @override
  String get notebookClearFilters => 'Clear all';

  @override
  String get notebookDone => 'Done';

  @override
  String get detailTitle => 'Question Detail';

  @override
  String get detailTabQuestion => 'Question';

  @override
  String get detailTabAnalysis => 'Analysis';

  @override
  String get detailTabPractice => 'Practice';

  @override
  String get detailTabRecord => 'Record';

  @override
  String get detailLearningProfile => 'Learning Profile';

  @override
  String get detailMistakeCategory => 'Mistake Category';

  @override
  String get detailOriginalQuestion => 'Original Question';

  @override
  String get detailCorrectAnswer => 'Correct Answer';

  @override
  String get detailPossibleAnswer => 'Possible Solution';

  @override
  String get detailMistakeReason => 'Mistake Analysis';

  @override
  String get detailStudyAdvice => 'Study Advice';

  @override
  String get detailKnowledgePoints => 'Knowledge Points';

  @override
  String get detailSolutionSteps => 'Solution Steps';

  @override
  String get detailSimilarExercises => 'Similar Exercises';

  @override
  String get detailNoAnalysis => 'No AI analysis yet';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsAppearance => 'Appearance';

  @override
  String get settingsThemeSystem => 'System';

  @override
  String get settingsThemeLight => 'Light';

  @override
  String get settingsThemeDark => 'Dark';

  @override
  String get settingsReminders => 'Reminders';

  @override
  String get settingsReviewReminder => 'Review Reminder';

  @override
  String get settingsReviewReminderSubtitle =>
      'Send notifications for due questions';

  @override
  String get settingsReviewReminderSent => 'Review reminder sent';

  @override
  String get settingsReviewReminderNoDue =>
      'No due questions, or notification permission not granted';

  @override
  String get settingsAiService => 'AI Service';

  @override
  String get settingsAiProvider => 'AI Provider Config';

  @override
  String get settingsLayoutProvider => 'Worksheet Layout Recognition';

  @override
  String get settingsLayoutProviderSubtitle =>
      'Vision model / NAS / MinerU / Custom service';

  @override
  String get settingsAiPrompts => 'AI Analysis Preferences';

  @override
  String get settingsContent => 'Content';

  @override
  String get settingsSubjects => 'Subject Management';

  @override
  String get settingsDataSecurity => 'Data & Security';

  @override
  String get settingsDataManagement => 'Backup, Restore & Storage';

  @override
  String get settingsDataManagementSubtitle =>
      'Backup, restore, export handouts and clear data';

  @override
  String get providerConfigTitle => 'AI Service Config';

  @override
  String get providerConfigUrlLabel => 'API URL';

  @override
  String get providerConfigUrlHint =>
      'https://api.openai.com/v1 or https://openrouter.ai/api/v1';

  @override
  String get providerConfigModelLabel => 'Model';

  @override
  String get providerConfigModelHint =>
      'gpt-4o, gemini-2.0-flash-thinking-exp-121, etc.';

  @override
  String get providerConfigApiKeyLabel => 'API Key';

  @override
  String get providerConfigApiKeyHint => 'sk-...';

  @override
  String get providerConfigTest => 'Test Connection';

  @override
  String get providerConfigTesting => 'Testing...';

  @override
  String get providerConfigSave => 'Save';

  @override
  String get providerConfigSaved => 'Config saved';

  @override
  String get providerConfigIncomplete => 'Please fill in all required fields';

  @override
  String get providerConfigUrlRequired => 'Please enter API URL';

  @override
  String get providerConfigModelRequired => 'Please enter model name';

  @override
  String get providerConfigApiKeyRequired => 'Please enter API Key';

  @override
  String get providerConfigTestSuccess =>
      '✓ Success!\n\nAPI connection is working. Config saved!\n\nYou can now take a photo to test.';

  @override
  String get providerConfigTestFailed => '✗ Connection failed\n\n';

  @override
  String get providerConfigSaveFailed =>
      '✗ Save failed\n\nCould not read saved config, please retry';

  @override
  String get captureTitle => 'Add Wrong Question';

  @override
  String get captureCamera => 'Camera';

  @override
  String get captureCameraDesc => 'Take a photo of the question';

  @override
  String get captureGallery => 'Gallery';

  @override
  String get captureGalleryDesc => 'Pick an image from gallery';

  @override
  String get captureWorksheet => 'Batch Worksheet Import';

  @override
  String get captureWorksheetDesc =>
      'Select multiple pages, confirm splits per page';

  @override
  String get cancel => 'Cancel';

  @override
  String get save => 'Save';

  @override
  String get delete => 'Delete';

  @override
  String get confirm => 'Confirm';

  @override
  String get retry => 'Retry';

  @override
  String get edit => 'Edit';

  @override
  String get close => 'Close';

  @override
  String get next => 'Next';

  @override
  String get start => 'Start';
}
