import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/review_log.dart';
import 'package:smart_wrong_notebook/src/shared/utils/export_content_options.dart';
import 'package:smart_wrong_notebook/src/shared/utils/export_template.dart';
import 'package:smart_wrong_notebook/src/shared/utils/html_render_utils.dart';
import 'package:smart_wrong_notebook/src/shared/utils/worksheet_export_mode.dart';

/// 复习卡模板：每题一页正面 + 一页背面，适合双面打印做闪卡。
///
/// - 每题生成两个 `.card-page` 元素：奇数（nth-child(odd)）为正面、偶数为背面。
/// - 正面：题图 + 题干（大字号、居中）。
/// - 背面：正确答案 + 解题步骤。
/// - CSS 用 `page-break-after: always` 强制每题分页，正面背面交替可双面打印。
/// - 不生成封面、目录与尾页（服务层根据 [type] 跳过）。
/// - 尊重 [ExportContentOptions] 字段开关。
class ReviewCardTemplate implements ExportTemplate {
  @override
  ExportTemplateType get type => ExportTemplateType.reviewCard;

  @override
  String get displayName => '复习卡';

  @override
  String get description => '每题一页正面 + 一页背面，适合双面打印做闪卡';

  @override
  String generateCss(PdfLayoutOptions? layoutOptions) {
    final margin =
        layoutOptions?.cssMarginBox ?? '14mm 14mm 14mm 14mm';
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

/* ── 闪卡页面：每页一张卡，强制分页 ─────────────────────────────────────── */
.card-page {
  page-break-after: always;
  break-after: page;
  min-height: 240mm;
  display: flex;
  flex-direction: column;
  padding: 6mm 4mm;
  position: relative;
}
.card-page:last-child {
  page-break-after: auto;
  break-after: auto;
}
/* 正面背面交替：nth-child(odd) 为正面，nth-child(even) 为背面。*/
.card-page:nth-child(odd) {
  background: #ffffff;
  border-left: 6px solid #6366F1;
}
.card-page:nth-child(even) {
  background: #fafaff;
  border-left: 6px solid #16a34a;
}

.card-tag {
  font-size: 9pt;
  color: #9ca3af;
  margin-bottom: 8px;
  display: flex;
  justify-content: space-between;
  align-items: center;
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
.card-tag .card-side {
  font-size: 8.5pt;
  color: #999;
  padding: 1px 8px;
  border: 1px solid #e5e7eb;
  border-radius: 999px;
}

/* 正面：题图 + 题干，居中大字号 */
.card-front-body {
  flex: 1;
  display: flex;
  flex-direction: column;
  justify-content: center;
  align-items: center;
  text-align: center;
  padding: 12mm 8mm;
}
.card-front-body .question-text {
  font-size: 18pt;
  font-weight: 600;
  line-height: 1.7;
  color: #1f2937;
  margin-bottom: 14px;
  max-width: 160mm;
}
.card-front-body .card-image {
  max-width: 100%;
  max-height: 120mm;
  object-fit: contain;
  border-radius: 8px;
  border: 1px solid #e5e7eb;
}
.card-front-body .image-placeholder {
  color: #9ca3af;
  font-size: 11pt;
  font-style: italic;
  margin-top: 8px;
}

/* 背面：正确答案 + 解题步骤 */
.card-back-body {
  flex: 1;
  display: flex;
  flex-direction: column;
  justify-content: flex-start;
  padding: 12mm 8mm;
}
.card-back-body .back-section { margin-bottom: 14px; }
.card-back-body .back-label {
  font-size: 10pt;
  font-weight: 700;
  color: #16a34a;
  margin-bottom: 4px;
  letter-spacing: 1px;
}
.card-back-body .back-content {
  font-size: 14pt;
  color: #1f2937;
  line-height: 1.8;
}
.card-back-body .back-content.small {
  font-size: 11pt;
  color: #374151;
}
.card-back-body .step-list { padding-left: 0; list-style: none; }
.card-back-body .step-item {
  font-size: 11pt;
  color: #374151;
  margin-bottom: 4px;
  padding-left: 18px;
  position: relative;
}
.card-back-body .step-item::before {
  content: "→";
  position: absolute;
  left: 0;
  color: #6366F1;
  font-weight: 700;
}

.math-inline { display: inline; }
.math-display { display: block; margin: 6px 0; }
.katex { font-size: 1.06em; }
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
    // 复习卡不需要封面，服务层根据 [type] 跳过封面渲染。
    // 此处返回空串以保持接口契约。
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

    final buf = StringBuffer();

    // ── 正面：题图 + 题干 ───────────────────────────────────────
    buf.writeln('    <div class="card-page card-front">');
    buf.writeln('      <div class="card-tag">');
    buf.writeln('        <span class="card-no">#$index</span>');
    buf.writeln(
        '        <span class="card-subject">${HtmlRenderUtils.escapeHtml(q.subject.label)}</span>');
    buf.writeln('        <span class="card-side">正面 · 题目</span>');
    buf.writeln('      </div>');
    buf.writeln('      <div class="card-front-body">');
    if (questionText.isNotEmpty) {
      buf.writeln(
          '        <div class="question-text">${HtmlRenderUtils.mixedTextToHtml(questionText)}</div>');
    }
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
    buf.writeln('      </div>');
    buf.writeln('    </div>');

    // ── 背面：正确答案 + 解题步骤 ───────────────────────────────
    buf.writeln('    <div class="card-page card-back">');
    buf.writeln('      <div class="card-tag">');
    buf.writeln('        <span class="card-no">#$index</span>');
    buf.writeln(
        '        <span class="card-subject">${HtmlRenderUtils.escapeHtml(q.subject.label)}</span>');
    buf.writeln('        <span class="card-side">背面 · 答案</span>');
    buf.writeln('      </div>');
    buf.writeln('      <div class="card-back-body">');
    final analysis = q.analysisResult;
    if (analysis != null) {
      if (contentOptions.includeCorrectAnswer &&
          analysis.finalAnswer.isNotEmpty) {
        buf.writeln('        <div class="back-section">');
        buf.writeln('          <div class="back-label">正确答案</div>');
        buf.writeln(
            '          <div class="back-content">${HtmlRenderUtils.mixedTextToHtml(analysis.finalAnswer)}</div>');
        buf.writeln('        </div>');
      }
      if (contentOptions.includeSolutionSteps &&
          analysis.steps.isNotEmpty) {
        buf.writeln('        <div class="back-section">');
        buf.writeln('          <div class="back-label">解题步骤</div>');
        buf.writeln('          <div class="back-content small">');
        buf.writeln('            <div class="step-list">');
        for (var i = 0; i < analysis.steps.length; i++) {
          buf.writeln(
              '              <div class="step-item">${i + 1}. ${HtmlRenderUtils.mixedTextToHtml(analysis.steps[i])}</div>');
        }
        buf.writeln('            </div>');
        buf.writeln('          </div>');
        buf.writeln('        </div>');
      }
      if (contentOptions.includeMistakeReason &&
          analysis.mistakeReason.isNotEmpty) {
        buf.writeln('        <div class="back-section">');
        buf.writeln('          <div class="back-label" style="color:#d97706">错因</div>');
        buf.writeln(
            '          <div class="back-content small">${HtmlRenderUtils.mixedTextToHtml(analysis.mistakeReason)}</div>');
        buf.writeln('        </div>');
      }
      if (contentOptions.includeKnowledgePoints) {
        final kps = [...analysis.knowledgePoints, ...analysis.aiTags]
            .take(5)
            .join(' · ');
        if (kps.isNotEmpty) {
          buf.writeln('        <div class="back-section">');
          buf.writeln(
              '          <div class="back-label" style="color:#7c3aed">知识点</div>');
          buf.writeln(
              '          <div class="back-content small">${HtmlRenderUtils.mixedTextToHtml(kps)}</div>');
          buf.writeln('        </div>');
        }
      }
    } else {
      buf.writeln('        <div class="back-section">');
      buf.writeln('          <div class="back-label">暂无解析</div>');
      buf.writeln(
          '          <div class="back-content small">该题尚未生成解析，请先在错题本中触发 AI 分析。</div>');
      buf.writeln('        </div>');
    }
    buf.writeln('      </div>');
    buf.writeln('    </div>');
    return buf.toString();
  }

  @override
  String? generateFooter({
    required List<QuestionRecord> questions,
    required List<ReviewLog>? reviewLogs,
  }) {
    return null;
  }
}
