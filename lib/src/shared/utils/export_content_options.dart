/// 导出内容选项：控制各导出格式中需要包含哪些字段。
///
/// 不同导出场景（Markdown / Anki / CSV / JSON）共用这套开关，
/// 默认开启常用字段；扩展字段（OCR 原文 / 完整 AI 分析 / 复习历史 /
/// 知识点树路径）默认关闭，避免现有导出突然多出冗长内容。
class ExportContentOptions {
  const ExportContentOptions({
    this.includeImage = true,
    this.includeKnowledgePoints = true,
    this.includeMistakeReason = true,
    this.includeCorrectAnswer = true,
    this.includeSolutionSteps = true,
    this.includeStudyAdvice = true,
    this.includeReviewCount = true,
    this.includeFavoriteMark = true,
    this.includeDates = true,
    this.includeExercises = true,
    // Phase 11-4：扩展字段，默认关闭。
    this.includeOcrText = false,
    this.includeAiAnalysis = false,
    this.includeReviewHistory = false,
    this.includeKnowledgeTree = false,
  });

  /// 是否包含题图（题图引用或"见原图"说明）。
  final bool includeImage;

  /// 是否包含知识点。
  final bool includeKnowledgePoints;

  /// 是否包含错因分析。
  final bool includeMistakeReason;

  /// 是否包含正确答案。
  final bool includeCorrectAnswer;

  /// 是否包含解题步骤。
  final bool includeSolutionSteps;

  /// 是否包含学习建议。
  final bool includeStudyAdvice;

  /// 是否包含复习次数。
  final bool includeReviewCount;

  /// 是否包含收藏标记。
  final bool includeFavoriteMark;

  /// 是否包含创建/复习日期。
  final bool includeDates;

  /// 是否包含变式练习（生成的同类题）。
  final bool includeExercises;

  /// 是否包含题目 OCR 识别原文（含布局块/公式/表格原始输出）。
  ///
  /// 用于校对场景：导出后可对照识别质量。默认关闭，避免冗长。
  final bool includeOcrText;

  /// 是否包含完整 AI 分析原文（含 raw 字段、提示词版本等元信息）。
  ///
  /// 与 [includeSolutionSteps]/[includeMistakeReason]/[includeStudyAdvice]
  /// 不同：本字段输出 AI 返回的完整结构化原文，便于离线复盘。
  final bool includeAiAnalysis;

  /// 是否包含复习历史时间线（每次复习的日期、评分、掌握度变化）。
  ///
  /// 与 [includeReviewCount]（仅次数）不同：本字段输出全部 ReviewLog。
  final bool includeReviewHistory;

  /// 是否包含知识点树路径（从根节点到当前知识点的完整面包屑路径）。
  ///
  /// 与 [includeKnowledgePoints]（仅名称）不同：本字段输出
  /// `数学 > 代数 > 二次方程` 形式的完整层级路径。
  final bool includeKnowledgeTree;

  /// 默认全开选项（含扩展字段），方便调用方快速获取一份"完整导出"配置。
  static const ExportContentOptions all = ExportContentOptions(
    includeOcrText: true,
    includeAiAnalysis: true,
    includeReviewHistory: true,
    includeKnowledgeTree: true,
  );

  /// 全关，调用方再逐项打开。
  static const ExportContentOptions none = ExportContentOptions(
    includeImage: false,
    includeKnowledgePoints: false,
    includeMistakeReason: false,
    includeCorrectAnswer: false,
    includeSolutionSteps: false,
    includeStudyAdvice: false,
    includeReviewCount: false,
    includeFavoriteMark: false,
    includeDates: false,
    includeExercises: false,
    includeOcrText: false,
    includeAiAnalysis: false,
    includeReviewHistory: false,
    includeKnowledgeTree: false,
  );

  ExportContentOptions copyWith({
    bool? includeImage,
    bool? includeKnowledgePoints,
    bool? includeMistakeReason,
    bool? includeCorrectAnswer,
    bool? includeSolutionSteps,
    bool? includeStudyAdvice,
    bool? includeReviewCount,
    bool? includeFavoriteMark,
    bool? includeDates,
    bool? includeExercises,
    bool? includeOcrText,
    bool? includeAiAnalysis,
    bool? includeReviewHistory,
    bool? includeKnowledgeTree,
  }) {
    return ExportContentOptions(
      includeImage: includeImage ?? this.includeImage,
      includeKnowledgePoints:
          includeKnowledgePoints ?? this.includeKnowledgePoints,
      includeMistakeReason: includeMistakeReason ?? this.includeMistakeReason,
      includeCorrectAnswer:
          includeCorrectAnswer ?? this.includeCorrectAnswer,
      includeSolutionSteps:
          includeSolutionSteps ?? this.includeSolutionSteps,
      includeStudyAdvice: includeStudyAdvice ?? this.includeStudyAdvice,
      includeReviewCount: includeReviewCount ?? this.includeReviewCount,
      includeFavoriteMark: includeFavoriteMark ?? this.includeFavoriteMark,
      includeDates: includeDates ?? this.includeDates,
      includeExercises: includeExercises ?? this.includeExercises,
      includeOcrText: includeOcrText ?? this.includeOcrText,
      includeAiAnalysis: includeAiAnalysis ?? this.includeAiAnalysis,
      includeReviewHistory:
          includeReviewHistory ?? this.includeReviewHistory,
      includeKnowledgeTree:
          includeKnowledgeTree ?? this.includeKnowledgeTree,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExportContentOptions &&
          runtimeType == other.runtimeType &&
          includeImage == other.includeImage &&
          includeKnowledgePoints == other.includeKnowledgePoints &&
          includeMistakeReason == other.includeMistakeReason &&
          includeCorrectAnswer == other.includeCorrectAnswer &&
          includeSolutionSteps == other.includeSolutionSteps &&
          includeStudyAdvice == other.includeStudyAdvice &&
          includeReviewCount == other.includeReviewCount &&
          includeFavoriteMark == other.includeFavoriteMark &&
          includeDates == other.includeDates &&
          includeExercises == other.includeExercises &&
          includeOcrText == other.includeOcrText &&
          includeAiAnalysis == other.includeAiAnalysis &&
          includeReviewHistory == other.includeReviewHistory &&
          includeKnowledgeTree == other.includeKnowledgeTree;

  @override
  int get hashCode => Object.hash(
        includeImage,
        includeKnowledgePoints,
        includeMistakeReason,
        includeCorrectAnswer,
        includeSolutionSteps,
        includeStudyAdvice,
        includeReviewCount,
        includeFavoriteMark,
        includeDates,
        includeExercises,
        includeOcrText,
        includeAiAnalysis,
        includeReviewHistory,
        includeKnowledgeTree,
      );
}
