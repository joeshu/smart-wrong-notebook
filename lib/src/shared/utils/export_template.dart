import 'package:flutter/cupertino.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/review_log.dart';
import 'package:smart_wrong_notebook/src/shared/utils/export_content_options.dart';
import 'package:smart_wrong_notebook/src/shared/utils/pdf_layout_options.dart';
import 'package:smart_wrong_notebook/src/shared/utils/worksheet_export_mode.dart';

// 重新导出 PdfLayoutOptions 及其 CSS 扩展，让所有 import 本文件的代码
// （如 templates/ 下的模板实现）无需单独 import pdf_layout_options.dart。
export 'package:smart_wrong_notebook/src/shared/utils/pdf_layout_options.dart';

/// 导出模板类型。
enum ExportTemplateType {
  /// 错题报告：按学科分组，含完整解析的正式错题报告。
  mistakeReport,

  /// 学习报告：卡片式布局，封面含统计概览，尾页含 SVG 图表。
  studyReport,

  /// 复习卡：每题一页正面 + 一页背面，适合双面打印做闪卡。
  reviewCard,

  /// 试卷模板：题目与答案分离，适合打印做正式考试卷。
  /// 题干在前（练习卷样式带答题留白），答案与解析集中在文末。
  examPaper,

  /// 错题卡模板：单题一卡，适合裁剪复习。
  /// 每题独立成块（不分页），紧凑排列，方便剪贴到错题本。
  errorCard,
}

/// [ExportTemplateType] 的 UI 元数据扩展：用于导出工作台等界面展示。
extension ExportTemplateTypeUi on ExportTemplateType {
  /// 中文显示名（用于 UI RadioListTile / 卡片标题）。
  String get label => switch (this) {
        ExportTemplateType.mistakeReport => '错题报告',
        ExportTemplateType.studyReport => '学习报告',
        ExportTemplateType.reviewCard => '复习卡',
        ExportTemplateType.examPaper => '试卷',
        ExportTemplateType.errorCard => '错题卡',
      };

  /// 中文描述（用于 UI RadioListTile 副标题 / 卡片说明）。
  String get description => switch (this) {
        ExportTemplateType.mistakeReport => '按学科分组、含完整解析的正式错题报告（默认样式）',
        ExportTemplateType.studyReport => '卡片式布局、含统计概览与 SVG 图表的学习总结',
        ExportTemplateType.reviewCard => '每题一页正面 + 一页背面，适合双面打印做闪卡',
        ExportTemplateType.examPaper => '题目与答案分离：题干在前带答题留白，答案解析集中在文末',
        ExportTemplateType.errorCard => '单题一卡、紧凑排列，适合裁剪贴到错题本',
      };

  /// UI 图标（用于卡片左侧标识）。
  IconData get icon => switch (this) {
        ExportTemplateType.mistakeReport => CupertinoIcons.doc_richtext,
        ExportTemplateType.studyReport => CupertinoIcons.chart_bar_alt_fill,
        ExportTemplateType.reviewCard => CupertinoIcons.rectangle_on_rectangle,
        ExportTemplateType.examPaper => CupertinoIcons.doc_text,
        ExportTemplateType.errorCard => CupertinoIcons.scissors,
      };

  /// 适用场景说明（Phase 11-2，用于模板卡片底部「适用场景」标签）。
  String get useCase => switch (this) {
        ExportTemplateType.mistakeReport => '家长签字 / 月度汇总',
        ExportTemplateType.studyReport => '期中期末复习总结',
        ExportTemplateType.reviewCard => '考前冲刺 / 碎片化复习',
        ExportTemplateType.examPaper => '打印考试 / 课堂测验',
        ExportTemplateType.errorCard => '错题本手抄 / 剪贴整理',
      };
}

/// 导出模板接口：负责生成 HTML 报告的 CSS、封面、单题块、尾页。
///
/// 不同模板实现不同的视觉风格与功能侧重：
/// - [MistakeReportTemplate]：与历史行为完全一致，按学科分组、含完整解析。
/// - [StudyReportTemplate]：卡片式布局，封面含统计概览，尾页含 SVG 图表。
/// - [ReviewCardTemplate]：每题一页正面 + 一页背面，适合双面打印做闪卡。
///
/// 服务层（[HtmlExportService]）负责图片预处理、KaTeX 内联、流式写入、
/// 文件管理、缓存等通用逻辑；模板只负责内容样式与结构。
abstract class ExportTemplate {
  /// 模板类型标识。
  ExportTemplateType get type;

  /// 中文显示名（用于 UI RadioListTile）。
  String get displayName;

  /// 中文描述（用于 UI RadioListTile 副标题）。
  String get description;

  /// 生成 HTML 内联 CSS（不含 KaTeX CSS，KaTeX 由服务层注入）。
  ///
  /// [layoutOptions] 为空时使用模板默认排版。
  String generateCss(PdfLayoutOptions? layoutOptions);

  /// 生成封面 HTML（含 `<div class="cover">...</div>`）。
  ///
  /// [studentName] 已经过脱敏处理（脱敏时为 'X 同学'）。
  /// [date] 为导出时间；[formattedDate] 非空时模板应优先使用（兼容外部传入的格式化日期）。
  /// [anonymize] 为 true 时模板应隐藏日期的时分秒部分。
  /// [questions] 用于学科分布等统计信息展示。
  String generateCover({
    required String title,
    String? studentName,
    String? className,
    required DateTime date,
    required int questionCount,
    required List<QuestionRecord> questions,
    bool anonymize = false,
    String? formattedDate,
  });

  /// 生成单题 HTML 片段（不含外层 subject-section 包装）。
  ///
  /// [index] 为题目在本次导出中的全局序号（从 1 开始）。
  /// [mode] 控制练习卷 / 答案卷 / 订正卷模式。
  /// [contentOptions] 控制各字段是否渲染（部分模板会尊重，部分模板保持历史行为）。
  /// [imageBase64] 为题图 data URI 字符串（如 `data:image/jpeg;base64,...`），为空表示无图或加载失败。
  /// [noImage] 为 true 表示跳过题图（用占位文本代替）。
  /// [watermark] 非空时模板可选择在题目块上叠加水印（多数模板由服务层统一渲染水印，可忽略）。
  String generateQuestionBlock({
    required QuestionRecord question,
    required int index,
    required WorksheetExportMode mode,
    required ExportContentOptions contentOptions,
    String? imageBase64,
    String? watermark,
    bool noImage = false,
  });

  /// 生成尾页 / 统计 HTML，返回 null 表示该模板不需要尾页。
  ///
  /// [reviewLogs] 用于学习报告模板的复习趋势图，可为空。
  String? generateFooter({
    required List<QuestionRecord> questions,
    required List<ReviewLog>? reviewLogs,
  });
}
