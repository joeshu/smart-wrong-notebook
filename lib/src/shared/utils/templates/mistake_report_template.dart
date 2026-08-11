import 'package:intl/intl.dart';
import 'package:smart_wrong_notebook/src/domain/models/content_status.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/review_log.dart';
import 'package:smart_wrong_notebook/src/shared/utils/export_content_options.dart';
import 'package:smart_wrong_notebook/src/shared/utils/export_template.dart';
import 'package:smart_wrong_notebook/src/shared/utils/html_render_utils.dart';
import 'package:smart_wrong_notebook/src/shared/utils/worksheet_export_mode.dart';

/// 错题报告模板：与历史 [HtmlExportService] 行为完全一致，按学科分组、含完整解析。
///
/// - CSS 与原 `_reportCss` 完全一致（含 @page、watermark、print-header/footer、
///   cover、toc、subject-section、question-block、analysis-row、steps-box、
///   math-inline/math-display、blank-area 等所有样式）。
/// - 封面与历史 `_writeHtmlHeadToSink` 中的封面部分一致。
/// - 单题块与历史 `_writeQuestionBlock` + `_writeAnalysisBlock` 一致。
/// - `generateFooter` 返回 null（错题报告不需要尾页统计）。
class MistakeReportTemplate implements ExportTemplate {
  @override
  ExportTemplateType get type => ExportTemplateType.mistakeReport;

  @override
  String get displayName => '错题报告';

  @override
  String get description => '按学科分组、含完整解析的正式错题报告（默认样式）';

  @override
  String generateCss(PdfLayoutOptions? layoutOptions) {
    final margin =
        layoutOptions?.cssMarginBox ?? '22mm 16mm 20mm 16mm';
    final pageSize = layoutOptions?.cssPageWithOrientation ?? 'A4';
    return '''
@page {
  size: $pageSize;
  margin: $margin;
  @bottom-center {
    content: "第 " counter(page) " 页 / 共 " counter(pages) " 页";
    font-size: 9pt;
    color: #999;
  }
}
* { box-sizing: border-box; }
body {
  font-family: -apple-system, 'PingFang SC', 'Microsoft YaHei', 'Hiragino Sans GB', sans-serif;
  font-size: 11pt;
  line-height: 1.7;
  color: #1f2937;
  margin: 0;
  padding: 0;
}
.page { max-width: 190mm; margin: 0 auto; }

.watermark {
  position: fixed;
  top: 50%;
  left: 50%;
  transform: translate(-50%, -50%) rotate(-30deg);
  font-size: 60px;
  color: rgba(0,0,0,0.08);
  pointer-events: none;
  z-index: 9999;
  white-space: nowrap;
}

.print-header, .print-footer { display: none; }
@media print {
  .print-header {
    display: block;
    position: fixed;
    top: 0;
    left: 0;
    right: 0;
    text-align: center;
    font-size: 9pt;
    color: #999;
    border-bottom: 1px solid #eee;
    padding: 4px 0;
  }
  .print-footer {
    display: block;
    position: fixed;
    bottom: 0;
    left: 0;
    right: 0;
    text-align: center;
    font-size: 9pt;
    color: #999;
  }
}

.cover {
  text-align: center;
  padding-top: 60mm;
  page-break-after: always;
}
.cover h1 { font-size: 26pt; font-weight: 700; color: #6366F1; margin-bottom: 12px; }
.cover .subtitle { font-size: 13pt; color: #888; margin-bottom: 36px; }
.cover .divider { width: 60%; height: 1px; background: #ddd; margin: 0 auto 24px; }
.cover .info { font-size: 12pt; color: #555; margin-bottom: 6px; }
.name-row {
  display: flex;
  justify-content: space-around;
  margin-top: 18px;
  font-size: 12pt;
  color: #444;
}

.toc { page-break-after: always; }
.toc h2 { font-size: 20pt; font-weight: 700; margin-bottom: 20px; }
.toc-group { margin-bottom: 12px; }
.toc-group > summary {
  font-size: 12pt; font-weight: 600; color: #6366F1; cursor: pointer;
  padding: 6px 0; list-style: none;
}
.toc-group > summary::-webkit-details-marker { display: none; }
.toc-group > summary::before { content: "▼ "; font-size: 9pt; color: #aaa; }
.toc-group:not([open]) > summary::before { content: "▶ "; }
.toc-item { display: flex; justify-content: space-between; padding: 6px 0 6px 16px; font-size: 12pt; }
.toc-item .count { color: #888; font-size: 10.5pt; }
.legend { font-size: 10pt; color: #888; margin-top: 18px; line-height: 2; }

/* Phase 11-6：正文按学科分组也支持折叠 */
.subject-section { page-break-before: always; }
.subject-section > details > summary { list-style: none; cursor: pointer; }
.subject-section > details > summary::-webkit-details-marker { display: none; }
.subject-header { display: flex; align-items: center; gap: 8px; margin-bottom: 16px; }
.subject-bar { width: 4px; height: 22px; border-radius: 2px; }
.subject-title { font-size: 18pt; font-weight: 700; }
.subject-toggle { font-size: 10pt; color: #aaa; margin-left: 6px; }

.question-block {
  margin-bottom: 16px;
  padding-bottom: 12px;
  border-bottom: 1px solid #e5e7eb;
  break-inside: avoid;
}
.question-header { display: flex; align-items: center; flex-wrap: wrap; gap: 6px; margin-bottom: 8px; }
.question-index { font-size: 13pt; font-weight: 700; color: #6366F1; margin-right: 2px; }
.badge {
  display: inline-block;
  font-size: 8.5pt;
  padding: 1px 7px;
  border-radius: 999px;
  font-weight: 500;
}
.badge-new { background: #fee2e2; color: #dc2626; }
.badge-reviewing { background: #fef3c7; color: #d97706; }
.badge-mastered { background: #dcfce7; color: #16a34a; }
.badge-status { background: #f3f4f6; color: #6b7280; }
.meta { font-size: 9pt; color: #9ca3af; }

.question-body {
  background: #f5f3ff;
  border-radius: 6px;
  padding: 10px 12px;
  margin: 8px 0;
  font-size: 11pt;
  line-height: 1.8;
}
.question-image {
  max-width: 100%;
  max-height: 260px;
  object-fit: contain;
  border-radius: 6px;
  margin-top: 8px;
  display: block;
}
.question-image-placeholder {
  color: #9ca3af;
  font-size: 10pt;
  font-style: italic;
  margin-top: 8px;
}

.analysis-row { font-size: 10.5pt; margin-top: 4px; }
.analysis-label { font-weight: 600; }
.analysis-label.green { color: #16a34a; }
.analysis-label.purple { color: #7c3aed; }
.analysis-label.orange { color: #d97706; }
.analysis-label.blue { color: #6366F1; }
.steps-box {
  border-left: 2px solid #6366F1;
  padding-left: 10px;
  margin-top: 6px;
}
.step-item { font-size: 10pt; margin-bottom: 3px; }

.math-inline { display: inline; }
.math-display { display: block; margin: 6px 0; }
.katex { font-size: 1.06em; }
.blank-area {
  border: 1px dashed #c7c3ff;
  border-radius: 6px;
  background: #fafaff;
  margin-top: 8px;
}

@media print {
  .page { max-width: none; }
  .question-block { break-inside: avoid; }
  .subject-section { break-before: page; }
}
''';
  }

  @override
  String generateCover({
    required String title,
    String? studentName,
    String? className,
    required DateTime date,
    required int questionCount,
    required List<QuestionRecord> questions,
    bool anonymize = false,
    String? formattedDate,
  }) {
    final dateStr = formattedDate ??
        DateFormat(anonymize ? 'yyyy-MM-dd' : 'yyyy-MM-dd HH:mm')
            .format(date);
    final grouped = HtmlRenderUtils.groupBySubject(questions);
    final sortedSubjects = HtmlRenderUtils.sortedSubjects(grouped);
    final displayName = studentName ?? '';
    final classNameStr = className ?? '';
    final buf = StringBuffer();
    buf.writeln('  <div class="cover">');
    buf.writeln('    <h1>${HtmlRenderUtils.escapeHtml(title)}</h1>');
    buf.writeln('    <div class="subtitle">AI Wrong Notebook</div>');
    buf.writeln('    <div class="divider"></div>');
    buf.writeln('    <div class="info">共 $questionCount 道错题</div>');
    buf.writeln('    <div class="info">导出时间：$dateStr</div>');
    buf.writeln('    <div class="info">涵盖 ${sortedSubjects.length} 个学科</div>');
    buf.writeln('    <div class="name-row">');
    buf.writeln(
        '      <span>姓&emsp;名：${HtmlRenderUtils.escapeHtml(displayName.isEmpty ? '____________' : displayName)}</span>');
    buf.writeln(
        '      <span>班&emsp;级：${HtmlRenderUtils.escapeHtml(classNameStr.isEmpty ? '____________' : classNameStr)}</span>');
    buf.writeln('    </div>');
    buf.writeln('    <div class="name-row">');
    buf.writeln('      <span>日&emsp;期：$dateStr</span>');
    buf.writeln('      <span>得&emsp;分：____________</span>');
    buf.writeln('    </div>');
    buf.writeln('  </div>');
    return buf.toString();
  }

  @override
  String generateQuestionBlock({
    required QuestionRecord question,
    required int index,
    required WorksheetExportMode mode,
    required ExportContentOptions contentOptions,
    String? imageBase64,
    String? watermark,
    bool noImage = false,
  }) {
    final q = question;
    final createDateStr = HtmlRenderUtils.shortDate(q.createdAt);
    final mastery = HtmlRenderUtils.masteryLabel(q.masteryLevel);
    final buf = StringBuffer();
    buf.writeln('    <div class="question-block">');
    buf.writeln('      <div class="question-header">');
    buf.writeln('        <span class="question-index">#$index</span>');
    if (q.isFavorite) {
      buf.writeln('        <span style="color:#d97706">★</span>');
    }
    buf.writeln(
        '        <span class="badge ${HtmlRenderUtils.masteryBadgeClass(q.masteryLevel)}">${HtmlRenderUtils.escapeHtml(mastery)}</span>');
    if (q.contentStatus != ContentStatus.ready) {
      buf.writeln(
          '        <span class="badge badge-status">${HtmlRenderUtils.statusLabel(q.contentStatus)}</span>');
    }
    if (q.reviewCount > 0) {
      buf.writeln('        <span class="meta">已复习 ${q.reviewCount} 次</span>');
    }
    buf.writeln(
        '        <span class="meta" style="margin-left:auto">$createDateStr</span>');
    buf.writeln('      </div>');

    // 题干
    final questionText = q.normalizedQuestionText.isNotEmpty
        ? q.normalizedQuestionText
        : q.extractedQuestionText;
    if (questionText.isNotEmpty) {
      buf.writeln('      <div class="question-body">');
      buf.write(HtmlRenderUtils.mixedTextToHtml(questionText));
      buf.writeln('      </div>');
    }

    // 原题图片（几何图、手写痕迹等）
    if (noImage) {
      if (q.imagePath.isNotEmpty) {
        buf.writeln(
            '      <div class="question-image-placeholder">[题图省略]</div>');
      }
    } else if (imageBase64 != null) {
      buf.writeln(
          '      <img class="question-image" src="$imageBase64" alt="错题图片">');
    }

    if (mode == WorksheetExportMode.practice) {
      final blankHeight = HtmlRenderUtils.practiceBlankHeight(questionText);
      buf.writeln(
          '      <div class="blank-area" style="height:${blankHeight}px"></div>');
    } else {
      _writeAnalysisBlock(buf, q, mode);
    }

    buf.writeln('    </div>');
    return buf.toString();
  }

  void _writeAnalysisBlock(
    StringBuffer buf,
    QuestionRecord q,
    WorksheetExportMode? mode,
  ) {
    final analysis = q.analysisResult;
    if (analysis == null) return;

    if (mode == null || mode == WorksheetExportMode.answer) {
      final kps = [...analysis.knowledgePoints, ...analysis.aiTags]
          .take(5)
          .join('  ·  ');
      if (kps.isNotEmpty) {
        buf.writeln(
            '      <div class="analysis-row"><span class="analysis-label purple">知识点</span>：${HtmlRenderUtils.mixedTextToHtml(kps)}</div>');
      }
      if (analysis.mistakeReason.isNotEmpty) {
        buf.writeln(
            '      <div class="analysis-row"><span class="analysis-label">错因分析</span>：${HtmlRenderUtils.mixedTextToHtml(analysis.mistakeReason)}</div>');
      }
      if (analysis.finalAnswer.isNotEmpty) {
        buf.writeln(
            '      <div class="analysis-row"><span class="analysis-label green">正确答案</span>：${HtmlRenderUtils.mixedTextToHtml(analysis.finalAnswer)}</div>');
      }
      if (analysis.steps.isNotEmpty) {
        buf.writeln('      <div class="steps-box">');
        buf.writeln(
            '        <div class="analysis-label blue" style="margin-bottom:4px">解题步骤</div>');
        for (var i = 0; i < analysis.steps.length; i++) {
          buf.writeln(
              '        <div class="step-item">${i + 1}. ${HtmlRenderUtils.mixedTextToHtml(analysis.steps[i])}</div>');
        }
        buf.writeln('      </div>');
      }
      if (analysis.studyAdvice.isNotEmpty) {
        buf.writeln(
            '      <div class="analysis-row"><span class="analysis-label orange">学习建议</span>：${HtmlRenderUtils.mixedTextToHtml(analysis.studyAdvice)}</div>');
      }
    } else if (mode == WorksheetExportMode.correction) {
      if (analysis.mistakeReason.isNotEmpty) {
        buf.writeln(
            '      <div class="analysis-row"><span class="analysis-label">错因分析</span>：${HtmlRenderUtils.mixedTextToHtml(analysis.mistakeReason)}</div>');
      }
      if (analysis.studyAdvice.isNotEmpty) {
        buf.writeln(
            '      <div class="analysis-row"><span class="analysis-label orange">订正提示</span>：${HtmlRenderUtils.mixedTextToHtml(analysis.studyAdvice)}</div>');
      }
      final blankHeight =
          HtmlRenderUtils.practiceBlankHeight(q.normalizedQuestionText);
      buf.writeln(
          '      <div class="blank-area" style="height:${blankHeight}px"></div>');
    }
  }

  @override
  String? generateFooter({
    required List<QuestionRecord> questions,
    required List<ReviewLog>? reviewLogs,
  }) {
    return null;
  }
}
