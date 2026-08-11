import 'package:intl/intl.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/review_log.dart';
import 'package:smart_wrong_notebook/src/shared/utils/export_content_options.dart';
import 'package:smart_wrong_notebook/src/shared/utils/export_template.dart';
import 'package:smart_wrong_notebook/src/shared/utils/html_render_utils.dart';
import 'package:smart_wrong_notebook/src/shared/utils/worksheet_export_mode.dart';

/// 试卷模板：题目与答案分离，适合打印做正式考试卷。
///
/// 设计要点：
/// - 题干在前（按学科分组），practice 模式带答题留白，correction 模式带错因+订正留白。
/// - 题块**不输出答案**，所有题目的答案与解析集中在 [generateFooter] 输出的
///   「参考答案」区，实现"题目与答案分离"的试卷语义。
/// - answer 模式：题块仅题干（无留白），答案仍在文末 — 等价于"题干卷 + 答案卷"合订。
/// - 走分组分支（按学科），与错题报告一致；不显示掌握程度 badge 等学习元信息
///   （试卷不需要这些干扰信息）。
/// - 尊重 [ExportContentOptions] 字段开关。
class ExamPaperTemplate implements ExportTemplate {
  @override
  ExportTemplateType get type => ExportTemplateType.examPaper;

  @override
  String get displayName => '试卷';

  @override
  String get description => '题目与答案分离：题干在前带答题留白，答案解析集中在文末';

  @override
  String generateCss(PdfLayoutOptions? layoutOptions) {
    final margin = layoutOptions?.cssMarginBox ?? '22mm 16mm 20mm 16mm';
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
  font-family: -apple-system, 'PingFang SC', 'Microsoft YaHei', 'Hiragino Sans GB', serif;
  font-size: 11.5pt;
  line-height: 1.8;
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

/* ── 封面 ─────────────────────────────────────────────────── */
.cover {
  text-align: center;
  padding-top: 60mm;
  page-break-after: always;
}
.cover h1 { font-size: 28pt; font-weight: 700; color: #1f2937; margin-bottom: 12px; letter-spacing: 4px; }
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

/* ── 目录 ─────────────────────────────────────────────────── */
.toc { page-break-after: always; }
.toc h2 { font-size: 20pt; font-weight: 700; margin-bottom: 20px; }
.toc-group { margin-bottom: 12px; }
.toc-group > summary {
  font-size: 12pt; font-weight: 600; color: #1f2937; cursor: pointer;
  padding: 6px 0; list-style: none;
}
.toc-group > summary::-webkit-details-marker { display: none; }
.toc-group > summary::before { content: "▼ "; font-size: 9pt; color: #aaa; }
.toc-group:not([open]) > summary::before { content: "▶ "; }
.toc-item { display: flex; justify-content: space-between; padding: 6px 0 6px 16px; font-size: 12pt; }
.toc-item .count { color: #888; font-size: 10.5pt; }

/* ── 学科分区（Phase 11-6：支持折叠） ─────────────────────── */
.subject-section { page-break-before: always; }
.subject-section > details > summary { list-style: none; cursor: pointer; }
.subject-section > details > summary::-webkit-details-marker { display: none; }
.subject-header { display: flex; align-items: center; gap: 8px; margin-bottom: 16px; border-bottom: 2px solid #1f2937; padding-bottom: 6px; }
.subject-bar { width: 4px; height: 22px; border-radius: 2px; }
.subject-title { font-size: 18pt; font-weight: 700; letter-spacing: 2px; }

/* ── 题目块（试卷风格：简洁、无学习元信息） ───────────────── */
.question-block {
  margin-bottom: 18px;
  padding-bottom: 10px;
  break-inside: avoid;
}
.question-header { display: flex; align-items: baseline; gap: 6px; margin-bottom: 6px; }
.question-index { font-size: 12pt; font-weight: 700; color: #1f2937; margin-right: 2px; }
.meta { font-size: 9pt; color: #9ca3af; margin-left: auto; }

.question-body {
  font-size: 11.5pt;
  line-height: 1.9;
  margin: 4px 0;
}
.question-image {
  max-width: 100%;
  max-height: 260px;
  object-fit: contain;
  border-radius: 4px;
  margin-top: 8px;
  display: block;
}
.question-image-placeholder {
  color: #9ca3af;
  font-size: 10pt;
  font-style: italic;
  margin-top: 8px;
}

/* 答题留白：试卷风格用实线分隔，比错题报告的虚线框更正式 */
.blank-area {
  border-bottom: 1px solid #d1d5db;
  margin-top: 10px;
}

/* 订正模式：错因提示 */
.analysis-row { font-size: 10.5pt; margin-top: 4px; color: #555; }
.analysis-label { font-weight: 600; color: #d97706; }

/* ── 参考答案区（文末） ───────────────────────────────────── */
.answer-section { page-break-before: always; }
.answer-section h2 {
  font-size: 20pt;
  font-weight: 700;
  text-align: center;
  letter-spacing: 6px;
  margin-bottom: 20px;
  padding-bottom: 8px;
  border-bottom: 2px solid #1f2937;
}
.answer-block {
  margin-bottom: 14px;
  padding-bottom: 8px;
  border-bottom: 1px dashed #e5e7eb;
  break-inside: avoid;
}
.answer-index { font-size: 12pt; font-weight: 700; color: #1f2937; margin-right: 4px; }
.answer-subject { font-size: 9pt; color: #888; }
.answer-label { font-weight: 600; font-size: 10.5pt; }
.answer-label.green { color: #16a34a; }
.answer-label.purple { color: #7c3aed; }
.answer-label.blue { color: #2563eb; }
.answer-label.orange { color: #d97706; }
.answer-content { font-size: 10.5pt; line-height: 1.8; margin-top: 2px; }
.steps-box {
  border-left: 2px solid #2563eb;
  padding-left: 10px;
  margin-top: 6px;
}
.step-item { font-size: 10pt; margin-bottom: 3px; }

.math-inline { display: inline; }
.math-display { display: block; margin: 6px 0; }
.katex { font-size: 1.06em; }

@media print {
  .page { max-width: none; }
  .question-block { break-inside: avoid; }
  .subject-section { break-before: page; }
  .answer-section { break-before: page; }
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
    buf.writeln('    <div class="subtitle">AI Wrong Notebook · 试卷</div>');
    buf.writeln('    <div class="divider"></div>');
    buf.writeln('    <div class="info">共 $questionCount 道题</div>');
    buf.writeln('    <div class="info">涵盖 ${sortedSubjects.length} 个学科</div>');
    buf.writeln('    <div class="info">日期：$dateStr</div>');
    buf.writeln('    <div class="name-row">');
    buf.writeln(
        '      <span>姓&emsp;名：${HtmlRenderUtils.escapeHtml(displayName.isEmpty ? '____________' : displayName)}</span>');
    buf.writeln(
        '      <span>班&emsp;级：${HtmlRenderUtils.escapeHtml(classNameStr.isEmpty ? '____________' : classNameStr)}</span>');
    buf.writeln('    </div>');
    buf.writeln('    <div class="name-row">');
    buf.writeln('      <span>考&emsp;号：____________</span>');
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
    final buf = StringBuffer();
    buf.writeln('    <div class="question-block">');
    buf.writeln('      <div class="question-header">');
    buf.writeln('        <span class="question-index">$index.</span>');
    buf.writeln('        <span class="meta">$createDateStr</span>');
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

    // 原题图片
    if (contentOptions.includeImage) {
      if (noImage) {
        if (q.imagePath.isNotEmpty) {
          buf.writeln(
              '      <div class="question-image-placeholder">[题图省略]</div>');
        }
      } else if (imageBase64 != null) {
        buf.writeln(
            '          <img class="question-image" src="$imageBase64" alt="错题图片">');
      }
    }

    // 试卷语义：题块不输出答案，答案集中在文末参考答案区。
    // practice：留白；correction：错因 + 订正留白；answer：无附加内容。
    if (mode == WorksheetExportMode.practice) {
      final blankHeight = HtmlRenderUtils.practiceBlankHeight(questionText);
      buf.writeln(
          '      <div class="blank-area" style="height:${blankHeight}px"></div>');
    } else if (mode == WorksheetExportMode.correction) {
      final analysis = q.analysisResult;
      if (analysis != null &&
          contentOptions.includeMistakeReason &&
          analysis.mistakeReason.isNotEmpty) {
        buf.writeln(
            '      <div class="analysis-row"><span class="analysis-label">错因</span>：${HtmlRenderUtils.mixedTextToHtml(analysis.mistakeReason)}</div>');
      }
      final blankHeight = HtmlRenderUtils.practiceBlankHeight(questionText);
      buf.writeln(
          '      <div class="blank-area" style="height:${blankHeight}px"></div>');
    }

    buf.writeln('    </div>');
    return buf.toString();
  }

  /// 文末「参考答案」区：遍历所有题目，输出答案 + 解析 + 错因 + 知识点。
  /// 这是试卷模板的核心 — 题目与答案分离。
  @override
  String? generateFooter({
    required List<QuestionRecord> questions,
    required List<ReviewLog>? reviewLogs,
  }) {
    if (questions.isEmpty) return null;
    final buf = StringBuffer();
    buf.writeln('  <div class="answer-section">');
    buf.writeln('    <h2>参 考 答 案</h2>');

    for (var i = 0; i < questions.length; i++) {
      final q = questions[i];
      final analysis = q.analysisResult;
      buf.writeln('    <div class="answer-block">');
      buf.writeln('      <div class="question-header">');
      buf.writeln('        <span class="answer-index">${i + 1}.</span>');
      buf.writeln(
          '        <span class="answer-subject">${HtmlRenderUtils.escapeHtml(q.subject.label)}</span>');
      buf.writeln('      </div>');

      if (analysis == null) {
        buf.writeln(
            '      <div class="answer-content" style="color:#9ca3af">该题尚未生成解析。</div>');
      } else {
        if (analysis.finalAnswer.isNotEmpty) {
          buf.writeln(
              '      <div class="answer-content"><span class="answer-label green">答案</span>：${HtmlRenderUtils.mixedTextToHtml(analysis.finalAnswer)}</div>');
        }
        if (analysis.steps.isNotEmpty) {
          buf.writeln('      <div class="steps-box">');
          buf.writeln(
              '        <div class="answer-label blue" style="margin-bottom:4px">解析</div>');
          for (var s = 0; s < analysis.steps.length; s++) {
            buf.writeln(
                '        <div class="step-item">${s + 1}. ${HtmlRenderUtils.mixedTextToHtml(analysis.steps[s])}</div>');
          }
          buf.writeln('      </div>');
        }
        if (analysis.mistakeReason.isNotEmpty) {
          buf.writeln(
              '      <div class="answer-content"><span class="answer-label orange">错因</span>：${HtmlRenderUtils.mixedTextToHtml(analysis.mistakeReason)}</div>');
        }
        final kps = [...analysis.knowledgePoints, ...analysis.aiTags]
            .take(5)
            .join('  ·  ');
        if (kps.isNotEmpty) {
          buf.writeln(
              '      <div class="answer-content"><span class="answer-label purple">知识点</span>：${HtmlRenderUtils.mixedTextToHtml(kps)}</div>');
        }
      }

      buf.writeln('    </div>');
    }

    buf.writeln('  </div>');
    return buf.toString();
  }
}
