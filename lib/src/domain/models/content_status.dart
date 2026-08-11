/// 题目内容处理状态。
///
/// 5 态枚举，覆盖"识别中 / 分析中 / 就绪 / 识别失败 / 分析失败"全流程。
/// 序列化用枚举名（`.name`），新增值向后兼容：老数据 `processing/ready/failed`
/// 仍能解析，新值 `analyzing/analysisFailed` 老代码读到会回落到 `processing`。
enum ContentStatus {
  /// 识别中（OCR 进行中）。
  processing,

  /// 分析中（AI 分析进行中）。
  ///
  /// 与 [processing] 区分：OCR 已成功，正在调用 AI。详情页据此显示"分析中"
  /// 而非"识别中"，并允许展示分析阶段状态。
  analyzing,

  /// 分析完成，但低置信度或不确定字段必须由用户确认。
  ///
  /// 该状态不得被列表、批量保存或复习流程视为最终 ready。
  needsConfirmation,

  /// 就绪（OCR 成功，可能已分析或未分析）。
  ///
  /// 是否已分析看 `QuestionRecord.analysisResult` 是否为 null：
  /// - `analysisResult == null` → OCR 草稿（待 AI 分析）
  /// - `analysisResult != null` → AI 已分析
  ready,

  /// 识别失败（OCR 失败）。
  ///
  /// 原图可能仍可用，但未提取到文字。失败原因看
  /// `QuestionRecord.lastAnalysisError`。
  failed,

  /// 分析失败（AI 失败，但 OCR 已成功）。
  ///
  /// 与 [failed] 区分：OCR 文字已保留（`extractedQuestionText` 非空），
  /// 仅 AI 分析失败。失败原因看 `QuestionRecord.lastAnalysisError`。
  analysisFailed,
}
