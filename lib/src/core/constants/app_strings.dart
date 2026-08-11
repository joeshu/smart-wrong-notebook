/// 应用字符串常量。
///
/// 这是 i18n 基础设施搭建前的旧入口，目前仍保留以避免大范围改动。
/// **新代码请优先使用 `AppLocalizations.of(context).xxx`**，
/// 字符串源文件位于 `lib/l10n/app_zh.arb`（中文，模板）和
/// `lib/l10n/app_en.arb`（英文）。修改 .arb 后执行 `flutter gen-l10n`
/// 重新生成 `lib/l10n/generated/` 下的代码。
class AppStrings {
  static const String appName = 'AI错题本';

  // Navigation
  static const String homeTab = '首页';
  static const String addTab = '添加';
  static const String notebookTab = '错题本';
  static const String reviewTab = '复习';
  static const String knowledgeTreeTab = '知识树';
  static const String settingsTab = '设置';

  // Home
  static const String homeGreeting = '今天，开始学习';
  static const String homeSubtitle = '先完成计划，再记录新的错题';
  static const String homeQuickStart = '快速开始';
  static const String homeCapture = '录入错题';
  static const String homeReviewPlan = '今日优先 · 复习计划';
  static const String homeStatsTitle = '学习统计';
  static const String homeRecentTitle = '最近新增';
  static const String homeViewAll = '查看全部';
  static const String homeMistakeCategories = '常见错因';
  static const String homeEmptyTip = '暂无错题，拍照开始添加';
  static const String homeBatchPriority = '今日优先 · 待处理事项';
  static const String homeBatchRemaining = '项';
  static const String homeBatchFailed = '道分析失败题';
  static const String homeBatchDrafts = '道 OCR 草稿待确认';
  static const String homeBatchPending = '道题尚未处理';
  static const String homeBatchRetry = '重新分析';
  static const String homeBatchContinueCorrection = '继续校对';
  static const String homeBatchContinueProcess = '继续处理';
  static const String homeNoReviewToday = '今天暂无待复习题';
  static const String homeReviewDue = '题待复习';
  static const String homeReviewEstimated = '预计 {} 分钟';
  static const String homeReviewCompleted = '已完成 {} / {}';
  static const String homeStreakDays = '连续学习 {} 天';
  static const String homeStartReview = '开始今日复习';
  static const String homeMasterProgress = '掌握进度';
  static const String homeMasteredCount = '{} / {} 已掌握';
  static const String homePendingCount = '{} 待复习';
  static const String homePlanError = '今日计划暂时无法读取。';
  static const String homeStatsError = '学习统计暂时无法读取。';

  // Review
  static const String reviewTitle = '复习';
  static const String reviewPending = '待复习';
  static const String reviewScheduled = '已安排';
  static const String reviewHistory = '复习记录';
  static const String reviewOverallProgress = '整体进度';
  static const String reviewTodayProgress = '今日完成';
  static const String reviewEmptyPending = '暂无待复习错题';
  static const String reviewEmptyScheduled = '暂无已安排复习';

  // Notebook
  static const String notebookTitle = '错题本';
  static const String notebookSearchHint = '搜索错题';
  static const String notebookFilterAll = '全部';
  static const String notebookFilterDue = '待复习';
  static const String notebookFilterUnmastered = '未掌握';
  static const String notebookFilterFavorite = '收藏';
  static const String notebookFilterMore = '筛选';
  static const String notebookEmptyTitle = '还没有错题';
  static const String notebookEmptySubtitle = '拍照录入一道错题，或导入整页试卷开始整理。';
  static const String notebookAdvancedFilter = '高级筛选';
  static const String notebookClearFilters = '清除全部';
  static const String notebookDone = '完成';

  // Question detail
  static const String detailTitle = '错题详情';
  static const String detailTabQuestion = '题目';
  static const String detailTabAnalysis = '解析';
  static const String detailTabPractice = '练习';
  static const String detailTabRecord = '记录';
  static const String detailLearningProfile = '学习档案';
  static const String detailMistakeCategory = '错因分类';
  static const String detailOriginalQuestion = '原题';
  static const String detailCorrectAnswer = '正确答案';
  static const String detailPossibleAnswer = '可能解法';
  static const String detailMistakeReason = '错因分析';
  static const String detailStudyAdvice = '学习建议';
  static const String detailKnowledgePoints = '知识点';
  static const String detailSolutionSteps = '解题步骤';
  static const String detailSimilarExercises = '举一反三';
  static const String detailNoAnalysis = '暂无 AI 解析结果';

  // Settings
  static const String settingsTitle = '设置';
  static const String settingsAppearance = '外观';
  static const String settingsThemeSystem = '系统';
  static const String settingsThemeLight = '浅色';
  static const String settingsThemeDark = '深色';
  static const String settingsReminders = '提醒';
  static const String settingsReviewReminder = '复习提醒';
  static const String settingsReviewReminderSubtitle = '发送待复习错题通知';
  static const String settingsReviewReminderSent = '已发送复习提醒';
  static const String settingsReviewReminderNoDue = '当前没有到期错题，或通知权限未开启';
  // Phase 9-3：定时复习提醒
  static const String settingsReviewReminderTime = '复习提醒时间';
  static const String settingsReviewReminderTimeSubtitle = '每天定时推送一条复习提醒';
  static const String settingsReviewReminderTimeScheduled = '已设置每日提醒';
  static const String settingsReviewReminderTimePermissionDenied = '通知权限未开启，无法设置提醒';
  static const String settingsAiService = 'AI 服务';
  static const String settingsAiProvider = 'AI 服务商配置';
  static const String settingsLayoutProvider = '试卷版面识别';
  static const String settingsLayoutProviderSubtitle = '视觉模型 / NAS / MinerU / 自定义服务';
  static const String settingsAiPrompts = 'AI 分析偏好';
  static const String settingsContent = '内容';
  static const String settingsSubjects = '科目管理';
  static const String settingsDataSecurity = '数据与安全';
  static const String settingsDataManagement = '备份、恢复与存储';
  static const String settingsDataManagementSubtitle = '完整备份、导入恢复、导出讲义与清理数据';

  // 学习分析
  static const String settingsLearningAnalytics = '学习分析';
  static const String settingsSubjectRadar = '学科能力雷达图';
  static const String settingsSubjectRadarSubtitle = '按科目查看掌握度与薄弱点';
  static const String settingsMistakeTrend = '错因趋势热力图';
  static const String settingsMistakeTrendSubtitle = '按月查看错因分布变化';
  static const String settingsWeeklyReport = '本周学情报告';
  static const String settingsWeeklyReportSubtitle = '生成复习量与掌握度周报';
  static const String settingsExportWorkbench = '导出工作台';
  static const String settingsExportWorkbenchSubtitle = '讲义 / Anki / HTML 等导出';
  static const String settingsExportShare = '导出';

  // Phase 9-3：学习设置区块
  static const String settingsLearning = '学习设置';
  static const String settingsDailyGoal = '每日复习目标';
  static const String settingsDailyGoalSubtitle = '设置目标题数、自动打卡、学习提醒';
  static const String settingsDifficultyPreference = '难度偏好';
  static const String settingsDifficultyPreferenceSubtitle = '优先推荐该难度的题目';
  static const String settingsKnowledgeTreeDepth = '知识树显示层级';
  static const String settingsKnowledgeTreeDepthSubtitle = '默认展开到知识点层';

  // Phase 9-4：关于区块
  static const String settingsAbout = '关于';
  static const String settingsAboutVersion = '版本';
  static const String settingsAboutCheckUpdate = '检查更新';
  static const String settingsAboutCheckUpdateSubtitle = '查看是否有新版本';
  static const String settingsAboutHelp = '使用帮助';
  static const String settingsAboutHelpSubtitle = '查看功能说明与常见问题';
  static const String settingsAboutFeedback = '反馈与建议';
  static const String settingsAboutFeedbackSubtitle = '通过 GitHub Issues 提交反馈';

  // Provider config
  static const String providerConfigTitle = 'AI 服务配置';
  static const String providerConfigUrlLabel = 'API 地址';
  static const String providerConfigUrlHint = 'https://api.openai.com/v1 或 https://openrouter.ai/api/v1';
  static const String providerConfigModelLabel = '模型';
  static const String providerConfigModelHint = 'gpt-4o, gemini-2.0-flash-thinking-exp-121 等';
  static const String providerConfigApiKeyLabel = 'API Key';
  static const String providerConfigApiKeyHint = 'sk-...';
  static const String providerConfigTest = '测试连接';
  static const String providerConfigTesting = '测试中...';
  static const String providerConfigSave = '保存';
  static const String providerConfigSaved = '配置已保存';
  static const String providerConfigIncomplete = '请填写完整的配置信息';
  static const String providerConfigUrlRequired = '请输入 API 地址';
  static const String providerConfigModelRequired = '请输入模型名称';
  static const String providerConfigApiKeyRequired = '请输入 API Key';
  static const String providerConfigTestSuccess = '✓ 成功！\n\nAPI 连接正常，配置已保存！\n\n现在可以拍照测试了。';
  static const String providerConfigTestFailed = '✗ 连接失败\n\n';
  static const String providerConfigSaveFailed = '✗ 保存失败\n\n无法读取保存的配置，请重试';

  // Capture
  static const String captureTitle = '录入错题';
  static const String captureCamera = '拍照';
  static const String captureCameraDesc = '使用相机拍摄错题';
  static const String captureGallery = '相册';
  static const String captureGalleryDesc = '从相册选择图片';
  static const String captureWorksheet = '试卷批量导入';
  static const String captureWorksheetDesc = '一次选择多页，逐页确认切题';

  // Common actions
  static const String cancel = '取消';
  static const String save = '保存';
  static const String delete = '删除';
  static const String confirm = '确认';
  static const String retry = '重试';
  static const String edit = '编辑';
  static const String close = '关闭';
  static const String next = '下一步';
  static const String start = '开始';
}
