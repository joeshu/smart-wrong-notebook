import 'package:smart_wrong_notebook/src/domain/models/content_status.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/review_log.dart';
import 'package:smart_wrong_notebook/src/shared/utils/export_content_options.dart';
import 'package:smart_wrong_notebook/src/shared/utils/export_template.dart';
import 'package:smart_wrong_notebook/src/shared/utils/html_render_utils.dart';
import 'package:smart_wrong_notebook/src/shared/utils/worksheet_export_mode.dart';

/// 错题卡模板：单题一卡、紧凑排列，适合裁剪贴到错题本。
///
/// 设计要点：
/// - 每题独立成一个 `.card-block`，**不分页**（与复习卡的区别），
///   紧凑排列，方便打印后裁剪贴到错题本。
/// - 走非分组分支（与复习卡一致）— 服务层根据 [type] 跳过学科分组。
/// - 卡片内：题头（#index + 学科 + 掌握度 badge）+ 题干 + 题图 +
///   模式相关内容（practice→留白 / answer→答案解析 / correction→错因+订正留白）。
/// - 不生成封面、目录与尾页（服务层根据 [type] 跳过）。
/// - 尊重 [ExportContentOptions] 字段开关。
class ErrorCardTemplate implements ExportTemplate {
  @override
  ExportTemplateType get type => ExportTemplateType.errorCard;

  @override
  String get displayName => '错题卡';

  @override
  String get description => '单题一卡、紧凑排列，适合裁剪贴到错题本';

  @override
  String generateCss(PdfLayoutOptions? layoutOptions) {
    final margin = layoutOptions?.cssMarginBox ?? '14mm 14mm 14mm 14mm';
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
  font-size: 10.5pt;
  line-height: 1.6;
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

/* ── 错题卡：每题一卡，紧凑排列，不分页 ─────────────────────── */
.card-block {
  border: 1px solid #e5e7eb;
  border-left: 4px solid #6366F1;
  border-radius: 6px;
  padding: 8px 12px;
  margin-bottom: 10px;
  break-inside: avoid;
  background: #ffffff;
}
.card-tag {
  display: flex;
  justify-content: space-between;
  align-items: center;
  margin-bottom: 6px;
  font-size: 9pt;
  color: #9ca3af;
}
.card-tag .card-no {
  font-size: 11pt;
  font-weight: 700;
  color: #6366F1;
}
.card-tag .card-subject {
  font-size: 10pt;
  color: #555;
  font-weight: 600;
}
.card-tag .badge {
  display: inline-block;
  font-size: 8pt;
  padding: 1px 6px;
  border-radius: 999px;
  font-weight: 500;
  margin-left: 4px;
}
.badge-new { background: #fee2e2; color: #dc2626; }
.badge-reviewing { background: #fef3c7; color: #d97706; }
.badge-mastered { background: #dcfce7; color: #16a34a; }
.badge-status { background: #f3f4f6; color: #6b7280; }

.question-text {
  font-size: 11pt;
  line-height: 1.7;
  color: #1f2937;
  margin-bottom: 4px;
}
.card-image {
  max-width: 100%;
  max-height: 160px;
  object-fit: contain;
  border-radius: 4px;
  margin-top: 4px;
  display: block;
}
.image-placeholder {
  color: #9ca3af;
  font-size: 9.5pt;
  font-style: italic;
  margin-top: 4px;
}

/* 答题留白 */
.blank-area {
  border: 1px dashed #c7c3ff;
  border-radius: 4px;
  background: #fafaff;
  margin-top: 6px;
}

/* 答案/解析区 */
.analysis-row { font-size: 10pt; margin-top: 3px; }
.analysis-label { font-weight: 600; }
.analysis-label.green { color: #16a34a; }
.analysis-label.purple { color: #7c3aed; }
.analysis-label.orange { color: #d97706; }
.analysis-label.blue { color: #6366F1; }
.steps-box {
  border-left: 2px solid #6366F1;
  padding-left: 8px;
  margin-top: 4px;
}
.step-item { font-size: 9.5pt; margin-bottom: 2px; }

.math-inline { display: inline; }
.math-display { display: block; margin: 4px 0; }
.katex { font-size: 1.04em; }

@media print {
  .page { max-width: none; }
  .card-block { break-inside: avoid; }
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
    // 错题卡不需要封面，服务层根据 [type] 跳过封面渲染。
    return '';
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
    final questionText = q.normalizedQuestionText.isNotEmpty
        ? q.normalizedQuestionText
        : q.extractedQuestionText;
    final mastery = HtmlRenderUtils.masteryLabel(q.masteryLevel);

    final buf = StringBuffer();
    buf.writeln('    <div class="card-block">');

    // 题头：题号 + 学科 + 掌握度 badge
    buf.writeln('      <div class="card-tag">');
    buf.writeln('        <div>');
    buf.writeln('          <span class="card-no">#$index</span>');
    buf.writeln(
        '          <span class="card-subject">${HtmlRenderUtils.escapeHtml(q.subject.label)}</span>');
    buf.writeln(
        '          <span class="badge ${HtmlRenderUtils.masteryBadgeClass(q.masteryLevel)}">${HtmlRenderUtils.escapeHtml(mastery)}</span>');
    if (q.contentStatus != ContentStatus.ready) {
      buf.writeln(
          '          <span class="badge badge-status">${HtmlRenderUtils.statusLabel(q.contentStatus)}</span>');
    }
    buf.writeln('        </div>');
    if (q.isFavorite) {
      buf.writeln('        <span style="color:#d97706">★</span>');
    }
    buf.writeln('      </div>');

    // 题干
    if (questionText.isNotEmpty) {
      buf.writeln(
          '      <div class="question-text">${HtmlRenderUtils.mixedTextToHtml(questionText)}</div>');
    }

    // 题图
    if (contentOptions.includeImage) {
      if (noImage) {
        if (q.imagePath.isNotEmpty) {
          buf.writeln('        <div class="image-placeholder">[题图省略]</div>');
        }
      } else if (imageBase64 != null) {
        buf.writeln(
            '        <img class="card-image" src="$imageBase64" alt="错题图片">');
      }
    }

    // 模式相关内容
    if (mode == WorksheetExportMode.practice) {
      final blankHeight = HtmlRenderUtils.practiceBlankHeight(questionText);
      buf.writeln(
          '      <div class="blank-area" style="height:${blankHeight}px"></div>');
    } else {
      _writeAnalysisBlock(buf, q, mode, contentOptions);
    }

    buf.writeln('    </div>');
    return buf.toString();
  }

  void _writeAnalysisBlock(
    StringBuffer buf,
    QuestionRecord q,
    WorksheetExportMode mode,
    ExportContentOptions contentOptions,
  ) {
    final analysis = q.analysisResult;
    if (analysis == null) return;

    if (mode == WorksheetExportMode.answer) {
      if (contentOptions.includeCorrectAnswer &&
          analysis.finalAnswer.isNotEmpty) {
        buf.writeln(
            '      <div class="analysis-row"><span class="analysis-label green">答案</span>：${HtmlRenderUtils.mixedTextToHtml(analysis.finalAnswer)}</div>');
      }
      if (contentOptions.includeSolutionSteps && analysis.steps.isNotEmpty) {
        buf.writeln('      <div class="steps-box">');
        for (var i = 0; i < analysis.steps.length; i++) {
          buf.writeln(
              '        <div class="step-item">${i + 1}. ${HtmlRenderUtils.mixedTextToHtml(analysis.steps[i])}</div>');
        }
        buf.writeln('      </div>');
      }
      if (contentOptions.includeMistakeReason &&
          analysis.mistakeReason.isNotEmpty) {
        buf.writeln(
            '      <div class="analysis-row"><span class="analysis-label orange">错因</span>：${HtmlRenderUtils.mixedTextToHtml(analysis.mistakeReason)}</div>');
      }
      if (contentOptions.includeKnowledgePoints) {
        final kps = [...analysis.knowledgePoints, ...analysis.aiTags]
            .take(5)
            .join('  ·  ');
        if (kps.isNotEmpty) {
          buf.writeln(
              '      <div class="analysis-row"><span class="analysis-label purple">知识点</span>：${HtmlRenderUtils.mixedTextToHtml(kps)}</div>');
        }
      }
    } else if (mode == WorksheetExportMode.correction) {
      if (contentOptions.includeMistakeReason &&
          analysis.mistakeReason.isNotEmpty) {
        buf.writeln(
            '      <div class="analysis-row"><span class="analysis-label orange">错因</span>：${HtmlRenderUtils.mixedTextToHtml(analysis.mistakeReason)}</div>');
      }
      final blankHeight = HtmlRenderUtils.practiceBlankHeight(q.normalizedQuestionText);
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
