// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Chinese (`zh`).
class AppLocalizationsZh extends AppLocalizations {
  AppLocalizationsZh([String locale = 'zh']) : super(locale);

  @override
  String get appName => 'AI错题本';

  @override
  String get homeTab => '首页';

  @override
  String get notebookTab => '错题本';

  @override
  String get reviewTab => '复习';

  @override
  String get settingsTab => '设置';

  @override
  String get homeGreeting => '今天，开始学习';

  @override
  String get homeSubtitle => '先完成计划，再记录新的错题';

  @override
  String get homeQuickStart => '快速开始';

  @override
  String get homeCapture => '录入错题';

  @override
  String get homeReviewPlan => '今日优先 · 复习计划';

  @override
  String get homeStatsTitle => '学习统计';

  @override
  String get homeRecentTitle => '最近新增';

  @override
  String get homeViewAll => '查看全部';

  @override
  String get homeMistakeCategories => '常见错因';

  @override
  String get homeEmptyTip => '暂无错题，拍照开始添加';

  @override
  String get homeBatchPriority => '今日优先 · 待处理事项';

  @override
  String get homeBatchRemaining => '项';

  @override
  String get homeBatchFailed => '道分析失败题';

  @override
  String get homeBatchDrafts => '道 OCR 草稿待确认';

  @override
  String get homeBatchPending => '道题尚未处理';

  @override
  String get homeBatchRetry => '重新分析';

  @override
  String get homeBatchContinueCorrection => '继续校对';

  @override
  String get homeBatchContinueProcess => '继续处理';

  @override
  String get homeNoReviewToday => '今天暂无待复习题';

  @override
  String get homeReviewDue => '题待复习';

  @override
  String homeReviewEstimated(int minutes) {
    return '预计 $minutes 分钟';
  }

  @override
  String homeReviewCompleted(int done, int total) {
    return '已完成 $done / $total';
  }

  @override
  String homeStreakDays(int days) {
    return '连续学习 $days 天';
  }

  @override
  String get homeStartReview => '开始今日复习';

  @override
  String get homeMasterProgress => '掌握进度';

  @override
  String homeMasteredCount(int mastered, int total) {
    return '$mastered / $total 已掌握';
  }

  @override
  String homePendingCount(int count) {
    return '$count 待复习';
  }

  @override
  String get homePlanError => '今日计划暂时无法读取。';

  @override
  String get homeStatsError => '学习统计暂时无法读取。';

  @override
  String get reviewTitle => '复习';

  @override
  String get reviewPending => '待复习';

  @override
  String get reviewScheduled => '已安排';

  @override
  String get reviewHistory => '复习记录';

  @override
  String get reviewOverallProgress => '整体进度';

  @override
  String get reviewTodayProgress => '今日完成';

  @override
  String get reviewEmptyPending => '暂无待复习错题';

  @override
  String get reviewEmptyScheduled => '暂无已安排复习';

  @override
  String get notebookTitle => '错题本';

  @override
  String get notebookSearchHint => '搜索错题';

  @override
  String get notebookFilterAll => '全部';

  @override
  String get notebookFilterDue => '待复习';

  @override
  String get notebookFilterUnmastered => '未掌握';

  @override
  String get notebookFilterFavorite => '收藏';

  @override
  String get notebookFilterMore => '筛选';

  @override
  String get notebookEmptyTitle => '还没有错题';

  @override
  String get notebookEmptySubtitle => '拍照录入一道错题，或导入整页试卷开始整理。';

  @override
  String get notebookAdvancedFilter => '高级筛选';

  @override
  String get notebookClearFilters => '清除全部';

  @override
  String get notebookDone => '完成';

  @override
  String get detailTitle => '错题详情';

  @override
  String get detailTabQuestion => '题目';

  @override
  String get detailTabAnalysis => '解析';

  @override
  String get detailTabPractice => '练习';

  @override
  String get detailTabRecord => '记录';

  @override
  String get detailLearningProfile => '学习档案';

  @override
  String get detailMistakeCategory => '错因分类';

  @override
  String get detailOriginalQuestion => '原题';

  @override
  String get detailCorrectAnswer => '正确答案';

  @override
  String get detailPossibleAnswer => '可能解法';

  @override
  String get detailMistakeReason => '错因分析';

  @override
  String get detailStudyAdvice => '学习建议';

  @override
  String get detailKnowledgePoints => '知识点';

  @override
  String get detailSolutionSteps => '解题步骤';

  @override
  String get detailSimilarExercises => '举一反三';

  @override
  String get detailNoAnalysis => '暂无 AI 解析结果';

  @override
  String get settingsTitle => '设置';

  @override
  String get settingsAppearance => '外观';

  @override
  String get settingsThemeSystem => '系统';

  @override
  String get settingsThemeLight => '浅色';

  @override
  String get settingsThemeDark => '深色';

  @override
  String get settingsReminders => '提醒';

  @override
  String get settingsReviewReminder => '复习提醒';

  @override
  String get settingsReviewReminderSubtitle => '发送待复习错题通知';

  @override
  String get settingsReviewReminderSent => '已发送复习提醒';

  @override
  String get settingsReviewReminderNoDue => '当前没有到期错题，或通知权限未开启';

  @override
  String get settingsAiService => 'AI 服务';

  @override
  String get settingsAiProvider => 'AI 服务商配置';

  @override
  String get settingsLayoutProvider => '试卷版面识别';

  @override
  String get settingsLayoutProviderSubtitle => '视觉模型 / NAS / MinerU / 自定义服务';

  @override
  String get settingsAiPrompts => 'AI 分析偏好';

  @override
  String get settingsContent => '内容';

  @override
  String get settingsSubjects => '科目管理';

  @override
  String get settingsDataSecurity => '数据与安全';

  @override
  String get settingsDataManagement => '备份、恢复与存储';

  @override
  String get settingsDataManagementSubtitle => '完整备份、导入恢复、导出讲义与清理数据';

  @override
  String get providerConfigTitle => 'AI 服务配置';

  @override
  String get providerConfigUrlLabel => 'API 地址';

  @override
  String get providerConfigUrlHint =>
      'https://api.openai.com/v1 或 https://openrouter.ai/api/v1';

  @override
  String get providerConfigModelLabel => '模型';

  @override
  String get providerConfigModelHint =>
      'gpt-4o, gemini-2.0-flash-thinking-exp-121 等';

  @override
  String get providerConfigApiKeyLabel => 'API Key';

  @override
  String get providerConfigApiKeyHint => 'sk-...';

  @override
  String get providerConfigTest => '测试连接';

  @override
  String get providerConfigTesting => '测试中...';

  @override
  String get providerConfigSave => '保存';

  @override
  String get providerConfigSaved => '配置已保存';

  @override
  String get providerConfigIncomplete => '请填写完整的配置信息';

  @override
  String get providerConfigUrlRequired => '请输入 API 地址';

  @override
  String get providerConfigModelRequired => '请输入模型名称';

  @override
  String get providerConfigApiKeyRequired => '请输入 API Key';

  @override
  String get providerConfigTestSuccess =>
      '✓ 成功！\n\nAPI 连接正常，配置已保存！\n\n现在可以拍照测试了。';

  @override
  String get providerConfigTestFailed => '✗ 连接失败\n\n';

  @override
  String get providerConfigSaveFailed => '✗ 保存失败\n\n无法读取保存的配置，请重试';

  @override
  String get captureTitle => '录入错题';

  @override
  String get captureCamera => '拍照';

  @override
  String get captureCameraDesc => '使用相机拍摄错题';

  @override
  String get captureGallery => '相册';

  @override
  String get captureGalleryDesc => '从相册选择图片';

  @override
  String get captureWorksheet => '试卷批量导入';

  @override
  String get captureWorksheetDesc => '一次选择多页，逐页确认切题';

  @override
  String get cancel => '取消';

  @override
  String get save => '保存';

  @override
  String get delete => '删除';

  @override
  String get confirm => '确认';

  @override
  String get retry => '重试';

  @override
  String get edit => '编辑';

  @override
  String get close => '关闭';

  @override
  String get next => '下一步';

  @override
  String get start => '开始';
}
