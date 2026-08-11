import 'dart:math' as math;

import 'package:smart_wrong_notebook/src/domain/models/mastery_level.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/review_log.dart';
import 'package:smart_wrong_notebook/src/shared/utils/export_content_options.dart';
import 'package:smart_wrong_notebook/src/shared/utils/export_template.dart';
import 'package:smart_wrong_notebook/src/shared/utils/html_render_utils.dart';
import 'package:smart_wrong_notebook/src/shared/utils/worksheet_export_mode.dart';

/// 学习报告模板：卡片式布局，封面含统计概览，尾页含 SVG 图表。
///
/// - CSS 更现代简洁，每题一张卡片（带阴影、圆角、轻边框）。
/// - 封面统计概览：总题数、学科数、掌握度分布、本月复习次数。
/// - 尾页 SVG 图表：学科分布柱状图、掌握度饼图、近 30 天复习趋势折线图。
/// - 单题块尊重 [ExportContentOptions] 字段开关。
/// - 不按学科分组（与错题报告不同），扁平列出所有题目。
class StudyReportTemplate implements ExportTemplate {
  @override
  ExportTemplateType get type => ExportTemplateType.studyReport;

  @override
  String get displayName => '学习报告';

  @override
  String get description => '卡片式布局、含统计概览与 SVG 图表的学习总结';

  @override
  String generateCss(PdfLayoutOptions? layoutOptions) {
    final margin =
        layoutOptions?.cssMarginBox ?? '18mm 16mm 20mm 16mm';
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
  background: #fafafa;
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

/* ── 封面：统计概览 ─────────────────────────────────────────── */
.cover {
  text-align: center;
  padding-top: 30mm;
  page-break-after: always;
}
.cover h1 {
  font-size: 28pt;
  font-weight: 700;
  color: #6366F1;
  margin-bottom: 8px;
}
.cover .subtitle { font-size: 13pt; color: #888; margin-bottom: 28px; }
.cover .info-row {
  display: flex;
  justify-content: center;
  gap: 24px;
  margin-bottom: 28px;
  font-size: 11pt;
  color: #555;
}
.stats-grid {
  display: grid;
  grid-template-columns: repeat(4, 1fr);
  gap: 12px;
  max-width: 160mm;
  margin: 0 auto 28px;
}
.stat-card {
  background: #fff;
  border: 1px solid #e5e7eb;
  border-radius: 10px;
  padding: 14px 10px;
  text-align: center;
  box-shadow: 0 1px 3px rgba(0,0,0,0.04);
}
.stat-card .stat-value {
  font-size: 24pt;
  font-weight: 700;
  color: #6366F1;
  line-height: 1.1;
}
.stat-card .stat-label {
  font-size: 9.5pt;
  color: #6b7280;
  margin-top: 4px;
}
.cover h3 {
  font-size: 13pt;
  font-weight: 600;
  color: #374151;
  margin: 18px 0 8px;
  text-align: left;
  max-width: 160mm;
  margin-left: auto;
  margin-right: auto;
}
.mini-bars {
  max-width: 160mm;
  margin: 0 auto 8px;
}
.mini-bar-row {
  display: flex;
  align-items: center;
  gap: 8px;
  margin-bottom: 4px;
  font-size: 10.5pt;
}
.mini-bar-row .mini-label { width: 60px; text-align: right; color: #555; }
.mini-bar-row .mini-track {
  flex: 1;
  height: 10px;
  background: #f3f4f6;
  border-radius: 5px;
  overflow: hidden;
}
.mini-bar-row .mini-fill { height: 100%; border-radius: 5px; }
.mini-bar-row .mini-count { width: 40px; color: #6b7280; }
.mastery-legend {
  font-size: 10pt;
  color: #6b7280;
  max-width: 160mm;
  margin: 0 auto;
  text-align: left;
}
.mastery-legend span { margin-right: 14px; }

/* ── 题目卡片 ─────────────────────────────────────────── */
.question-card {
  background: #fff;
  border: 1px solid #e5e7eb;
  border-radius: 10px;
  padding: 14px 16px;
  margin-bottom: 14px;
  break-inside: avoid;
  box-shadow: 0 1px 3px rgba(0,0,0,0.05);
}
.card-header {
  display: flex;
  align-items: center;
  flex-wrap: wrap;
  gap: 8px;
  margin-bottom: 8px;
  padding-bottom: 8px;
  border-bottom: 1px solid #f3f4f6;
}
.card-index {
  font-size: 13pt;
  font-weight: 700;
  color: #6366F1;
}
.card-subject {
  font-size: 10.5pt;
  font-weight: 600;
  padding: 2px 10px;
  border-radius: 999px;
  color: #fff;
}
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
.meta { font-size: 9pt; color: #9ca3af; }
.card-body {
  background: #f5f3ff;
  border-radius: 6px;
  padding: 10px 12px;
  margin: 8px 0;
  font-size: 11pt;
  line-height: 1.8;
}
.card-image {
  max-width: 100%;
  max-height: 240px;
  object-fit: contain;
  border-radius: 6px;
  margin-top: 8px;
  display: block;
}
.card-image-placeholder {
  color: #9ca3af;
  font-size: 10pt;
  font-style: italic;
  margin-top: 8px;
}
.card-meta { font-size: 10.5pt; margin-top: 6px; }
.card-meta-row { margin-top: 4px; }
.card-meta-label { font-weight: 600; }
.card-meta-label.green { color: #16a34a; }
.card-meta-label.purple { color: #7c3aed; }
.card-meta-label.orange { color: #d97706; }
.card-meta-label.blue { color: #6366F1; }
.steps-box {
  border-left: 2px solid #6366F1;
  padding-left: 10px;
  margin-top: 6px;
}
.step-item { font-size: 10pt; margin-bottom: 3px; }
.math-inline { display: inline; }
.math-display { display: block; margin: 6px 0; }
.katex { font-size: 1.06em; }

/* ── 尾页 SVG 图表 ─────────────────────────────────────────── */
.stats-footer {
  page-break-before: always;
  padding-top: 10mm;
}
.stats-footer h2 {
  font-size: 20pt;
  font-weight: 700;
  color: #6366F1;
  margin-bottom: 16px;
  text-align: center;
}
.chart-grid {
  display: grid;
  grid-template-columns: 1fr 1fr;
  gap: 16px;
  margin-bottom: 16px;
}
.chart-block {
  background: #fff;
  border: 1px solid #e5e7eb;
  border-radius: 10px;
  padding: 14px;
}
.chart-block h3 {
  font-size: 12pt;
  font-weight: 600;
  color: #374151;
  margin-bottom: 8px;
  text-align: center;
}
.chart-full {
  background: #fff;
  border: 1px solid #e5e7eb;
  border-radius: 10px;
  padding: 14px;
}
.chart-full h3 {
  font-size: 12pt;
  font-weight: 600;
  color: #374151;
  margin-bottom: 8px;
  text-align: center;
}
.legend-row {
  display: flex;
  flex-wrap: wrap;
  gap: 10px;
  justify-content: center;
  margin-top: 6px;
  font-size: 9.5pt;
  color: #6b7280;
}
.legend-row .legend-item { display: inline-flex; align-items: center; gap: 4px; }
.legend-row .legend-swatch {
  display: inline-block;
  width: 10px;
  height: 10px;
  border-radius: 2px;
}

@media print {
  .page { max-width: none; }
  .question-card { break-inside: avoid; }
  .stats-footer { break-before: page; }
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
    final dateStr = formattedDate ?? _formatDate(date, anonymize);
    final grouped = HtmlRenderUtils.groupBySubject(questions);
    final sortedSubjects = HtmlRenderUtils.sortedSubjects(grouped);
    final subjectCount = sortedSubjects.length;

    // 掌握度分布
    final masteryCounts = <MasteryLevel, int>{
      MasteryLevel.newQuestion: 0,
      MasteryLevel.reviewing: 0,
      MasteryLevel.mastered: 0,
    };
    for (final q in questions) {
      masteryCounts[q.masteryLevel] = (masteryCounts[q.masteryLevel] ?? 0) + 1;
    }

    // 本月复习次数：lastReviewedAt 落在本月的题目 reviewCount 总和近似。
    final now = date;
    var monthlyReviews = 0;
    for (final q in questions) {
      final last = q.lastReviewedAt;
      if (last != null &&
          last.year == now.year &&
          last.month == now.month) {
        monthlyReviews += q.reviewCount;
      }
    }
    // 没有本月复习记录时退化为总复习次数（避免封面 0 误导）。
    if (monthlyReviews == 0) {
      monthlyReviews = questions.fold(0, (a, q) => a + q.reviewCount);
    }

    final maxSubjectCount = sortedSubjects.fold<int>(0,
        (a, s) => grouped[s]!.length > a ? grouped[s]!.length : a);

    final buf = StringBuffer();
    buf.writeln('  <div class="cover">');
    buf.writeln('    <h1>${HtmlRenderUtils.escapeHtml(title)}</h1>');
    buf.writeln('    <div class="subtitle">学习报告 · Learning Report</div>');
    buf.writeln('    <div class="info-row">');
    buf.writeln(
        '      <span>姓&emsp;名：${HtmlRenderUtils.escapeHtml(studentName?.isEmpty ?? true ? '____________' : studentName!)}</span>');
    buf.writeln(
        '      <span>班&emsp;级：${HtmlRenderUtils.escapeHtml(className?.isEmpty ?? true ? '____________' : className!)}</span>');
    buf.writeln('      <span>日&emsp;期：$dateStr</span>');
    buf.writeln('    </div>');

    // 统计卡片
    buf.writeln('    <div class="stats-grid">');
    buf.writeln('      <div class="stat-card">');
    buf.writeln('        <div class="stat-value">$questionCount</div>');
    buf.writeln('        <div class="stat-label">总题数</div>');
    buf.writeln('      </div>');
    buf.writeln('      <div class="stat-card">');
    buf.writeln('        <div class="stat-value">$subjectCount</div>');
    buf.writeln('        <div class="stat-label">学科数</div>');
    buf.writeln('      </div>');
    buf.writeln('      <div class="stat-card">');
    buf.writeln(
        '        <div class="stat-value">${masteryCounts[MasteryLevel.mastered] ?? 0}</div>');
    buf.writeln('        <div class="stat-label">已掌握</div>');
    buf.writeln('      </div>');
    buf.writeln('      <div class="stat-card">');
    buf.writeln('        <div class="stat-value">$monthlyReviews</div>');
    buf.writeln('        <div class="stat-label">本月复习</div>');
    buf.writeln('      </div>');
    buf.writeln('    </div>');

    // 学科分布迷你条
    buf.writeln('    <h3>学科分布</h3>');
    buf.writeln('    <div class="mini-bars">');
    for (final s in sortedSubjects) {
      final count = grouped[s]!.length;
      final pct =
          maxSubjectCount == 0 ? 0 : (count / maxSubjectCount * 100).round();
      final color = HtmlRenderUtils.subjectColorHex(s);
      buf.writeln('      <div class="mini-bar-row">');
      buf.writeln(
          '        <span class="mini-label">${HtmlRenderUtils.escapeHtml(s.label)}</span>');
      buf.writeln('        <span class="mini-track">');
      buf.writeln(
          '          <span class="mini-fill" style="width:$pct%;background:$color"></span>');
      buf.writeln('        </span>');
      buf.writeln('        <span class="mini-count">$count</span>');
      buf.writeln('      </div>');
    }
    buf.writeln('    </div>');

    // 掌握度图例
    buf.writeln('    <div class="mastery-legend">');
    buf.writeln(
        '      <span>● 待学习 ${masteryCounts[MasteryLevel.newQuestion] ?? 0}</span>');
    buf.writeln(
        '      <span>● 复习中 ${masteryCounts[MasteryLevel.reviewing] ?? 0}</span>');
    buf.writeln(
        '      <span>● 已掌握 ${masteryCounts[MasteryLevel.mastered] ?? 0}</span>');
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
    final buf = StringBuffer();
    final subjectColor = HtmlRenderUtils.subjectColorHex(q.subject);

    buf.writeln('    <div class="question-card">');
    buf.writeln('      <div class="card-header">');
    buf.writeln('        <span class="card-index">#$index</span>');
    buf.writeln(
        '        <span class="card-subject" style="background:$subjectColor">${HtmlRenderUtils.escapeHtml(q.subject.label)}</span>');
    buf.writeln(
        '        <span class="badge ${HtmlRenderUtils.masteryBadgeClass(q.masteryLevel)}">${HtmlRenderUtils.masteryLabel(q.masteryLevel)}</span>');
    if (contentOptions.includeFavoriteMark && q.isFavorite) {
      buf.writeln('        <span style="color:#d97706">★</span>');
    }
    if (contentOptions.includeReviewCount && q.reviewCount > 0) {
      buf.writeln('        <span class="meta">已复习 ${q.reviewCount} 次</span>');
    }
    if (contentOptions.includeDates) {
      buf.writeln(
          '        <span class="meta" style="margin-left:auto">${HtmlRenderUtils.shortDate(q.createdAt)}</span>');
    }
    buf.writeln('      </div>');

    // 题干
    final questionText = q.normalizedQuestionText.isNotEmpty
        ? q.normalizedQuestionText
        : q.extractedQuestionText;
    if (questionText.isNotEmpty) {
      buf.writeln('      <div class="card-body">');
      buf.write(HtmlRenderUtils.mixedTextToHtml(questionText));
      buf.writeln('      </div>');
    }

    // 题图
    if (contentOptions.includeImage) {
      if (noImage) {
        if (q.imagePath.isNotEmpty) {
          buf.writeln(
              '      <div class="card-image-placeholder">[题图省略]</div>');
        }
      } else if (imageBase64 != null) {
        buf.writeln(
            '      <img class="card-image" src="$imageBase64" alt="错题图片">');
      }
    }

    // 解析（学习报告总是展示完整解析，忽略 mode 中的 practice/correction 留白）
    final analysis = q.analysisResult;
    if (analysis != null) {
      buf.writeln('      <div class="card-meta">');
      if (contentOptions.includeKnowledgePoints) {
        final kps = [...analysis.knowledgePoints, ...analysis.aiTags]
            .take(5)
            .join('  ·  ');
        if (kps.isNotEmpty) {
          buf.writeln(
              '        <div class="card-meta-row"><span class="card-meta-label purple">知识点</span>：${HtmlRenderUtils.mixedTextToHtml(kps)}</div>');
        }
      }
      if (contentOptions.includeMistakeReason &&
          analysis.mistakeReason.isNotEmpty) {
        buf.writeln(
            '        <div class="card-meta-row"><span class="card-meta-label">错因分析</span>：${HtmlRenderUtils.mixedTextToHtml(analysis.mistakeReason)}</div>');
      }
      if (contentOptions.includeCorrectAnswer &&
          analysis.finalAnswer.isNotEmpty) {
        buf.writeln(
            '        <div class="card-meta-row"><span class="card-meta-label green">正确答案</span>：${HtmlRenderUtils.mixedTextToHtml(analysis.finalAnswer)}</div>');
      }
      if (contentOptions.includeSolutionSteps &&
          analysis.steps.isNotEmpty) {
        buf.writeln('        <div class="steps-box">');
        buf.writeln(
            '          <div class="card-meta-label blue" style="margin-bottom:4px">解题步骤</div>');
        for (var i = 0; i < analysis.steps.length; i++) {
          buf.writeln(
              '          <div class="step-item">${i + 1}. ${HtmlRenderUtils.mixedTextToHtml(analysis.steps[i])}</div>');
        }
        buf.writeln('        </div>');
      }
      if (contentOptions.includeStudyAdvice &&
          analysis.studyAdvice.isNotEmpty) {
        buf.writeln(
            '        <div class="card-meta-row"><span class="card-meta-label orange">学习建议</span>：${HtmlRenderUtils.mixedTextToHtml(analysis.studyAdvice)}</div>');
      }
      buf.writeln('      </div>');
    }

    buf.writeln('    </div>');
    return buf.toString();
  }

  @override
  String? generateFooter({
    required List<QuestionRecord> questions,
    required List<ReviewLog>? reviewLogs,
  }) {
    if (questions.isEmpty) return null;
    final buf = StringBuffer();
    buf.writeln('  <div class="stats-footer">');
    buf.writeln('    <h2>学习数据分析</h2>');

    buf.writeln('    <div class="chart-grid">');
    // 学科分布柱状图
    buf.writeln('      <div class="chart-block">');
    buf.writeln('        <h3>学科分布</h3>');
    buf.write(_subjectDistributionSvg(questions));
    buf.writeln('      </div>');
    // 掌握度饼图
    buf.writeln('      <div class="chart-block">');
    buf.writeln('        <h3>掌握度分布</h3>');
    buf.write(_masteryPieSvg(questions));
    buf.writeln('      </div>');
    buf.writeln('    </div>');

    // 30 天复习趋势
    buf.writeln('    <div class="chart-full">');
    buf.writeln('      <h3>近 30 天复习趋势</h3>');
    buf.write(_reviewTrendSvg(reviewLogs ?? const <ReviewLog>[]));
    buf.writeln('    </div>');

    buf.writeln('  </div>');
    return buf.toString();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SVG 图表生成
  // ─────────────────────────────────────────────────────────────────────────

  /// 学科分布柱状图（水平条形图，SVG rect）。
  String _subjectDistributionSvg(List<QuestionRecord> questions) {
    final grouped = HtmlRenderUtils.groupBySubject(questions);
    final sortedSubjects = HtmlRenderUtils.sortedSubjects(grouped);
    final maxCount = sortedSubjects.fold<int>(0,
        (a, s) => grouped[s]!.length > a ? grouped[s]!.length : a);
    const barHeight = 18.0;
    const gap = 6.0;
    const labelWidth = 60.0;
    const valueWidth = 40.0;
    const chartW = 360.0;
    const barAreaW = chartW - labelWidth - valueWidth;
    final totalH =
        sortedSubjects.length * (barHeight + gap) + 20.0;

    final buf = StringBuffer();
    buf.writeln(
        '<svg viewBox="0 0 $chartW $totalH" xmlns="http://www.w3.org/2000/svg" style="width:100%;max-width:${chartW}px;">');
    var y = 10.0;
    for (final s in sortedSubjects) {
      final count = grouped[s]!.length;
      final w = maxCount == 0 ? 0.0 : (count / maxCount) * barAreaW;
      final color = HtmlRenderUtils.subjectColorHex(s);
      buf.writeln(
          '<text x="${labelWidth - 6}" y="${y + barHeight / 2 + 4}" text-anchor="end" font-size="11" fill="#555">${HtmlRenderUtils.escapeHtml(s.label)}</text>');
      buf.writeln(
          '<rect x="$labelWidth" y="$y" width="$w" height="$barHeight" fill="$color" rx="3"/>');
      buf.writeln(
          '<text x="${labelWidth + w + 6}" y="${y + barHeight / 2 + 4}" font-size="11" fill="#6b7280">$count</text>');
      y += barHeight + gap;
    }
    buf.writeln('</svg>');
    return buf.toString();
  }

  /// 掌握度分布饼图（SVG path / circle）。
  String _masteryPieSvg(List<QuestionRecord> questions) {
    final counts = <MasteryLevel, int>{
      MasteryLevel.newQuestion: 0,
      MasteryLevel.reviewing: 0,
      MasteryLevel.mastered: 0,
    };
    for (final q in questions) {
      counts[q.masteryLevel] = (counts[q.masteryLevel] ?? 0) + 1;
    }
    final total = counts.values.fold(0, (a, b) => a + b);
    const cx = 90.0, cy = 90.0, r = 70.0;

    final buf = StringBuffer();
    buf.writeln(
        '<svg viewBox="0 0 180 200" xmlns="http://www.w3.org/2000/svg" style="width:180px;height:200px;display:block;margin:0 auto;">');
    if (total == 0) {
      buf.writeln(
          '<circle cx="$cx" cy="$cy" r="$r" fill="#f3f4f6"/>');
      buf.writeln(
          '<text x="$cx" y="${cy + 4}" text-anchor="middle" font-size="11" fill="#999">无数据</text>');
    } else {
      var startAngle = -math.pi / 2;
      final levels = [
        MasteryLevel.newQuestion,
        MasteryLevel.reviewing,
        MasteryLevel.mastered,
      ];
      for (final level in levels) {
        final count = counts[level] ?? 0;
        if (count == 0) continue;
        final angle = (count / total) * 2 * math.pi;
        final endAngle = startAngle + angle;
        final color = _masteryColorHex(level);
        if (count == total) {
          buf.writeln(
              '<circle cx="$cx" cy="$cy" r="$r" fill="$color"/>');
        } else {
          final x1 = cx + r * math.cos(startAngle);
          final y1 = cy + r * math.sin(startAngle);
          final x2 = cx + r * math.cos(endAngle);
          final y2 = cy + r * math.sin(endAngle);
          final largeArc = angle > math.pi ? 1 : 0;
          buf.writeln(
              '<path d="M $cx $cy L ${x1.toStringAsFixed(2)} ${y1.toStringAsFixed(2)} A $r $r 0 $largeArc 1 ${x2.toStringAsFixed(2)} ${y2.toStringAsFixed(2)} Z" fill="$color"/>');
        }
        startAngle = endAngle;
      }
      // 中心环（视觉上更像 donut）
      buf.writeln(
          '<circle cx="$cx" cy="$cy" r="${r * 0.55}" fill="#fafafa"/>');
      buf.writeln(
          '<text x="$cx" y="${cy - 4}" text-anchor="middle" font-size="20" font-weight="700" fill="#6366F1">$total</text>');
      buf.writeln(
          '<text x="$cx" y="${cy + 14}" text-anchor="middle" font-size="9" fill="#6b7280">总题数</text>');
    }
    buf.writeln('</svg>');
    // 图例
    buf.writeln('<div class="legend-row">');
    buf.writeln(
        '  <span class="legend-item"><span class="legend-swatch" style="background:${_masteryColorHex(MasteryLevel.newQuestion)}"></span>待学习 ${counts[MasteryLevel.newQuestion]}</span>');
    buf.writeln(
        '  <span class="legend-item"><span class="legend-swatch" style="background:${_masteryColorHex(MasteryLevel.reviewing)}"></span>复习中 ${counts[MasteryLevel.reviewing]}</span>');
    buf.writeln(
        '  <span class="legend-item"><span class="legend-swatch" style="background:${_masteryColorHex(MasteryLevel.mastered)}"></span>已掌握 ${counts[MasteryLevel.mastered]}</span>');
    buf.writeln('</div>');
    return buf.toString();
  }

  /// 近 30 天复习趋势折线图（SVG polyline）。
  String _reviewTrendSvg(List<ReviewLog> reviewLogs) {
    const days = 30;
    final now = DateTime.now();
    final dailyCounts = List<int>.filled(days, 0);
    for (final log in reviewLogs) {
      final diff = now.difference(log.reviewedAt).inDays;
      if (diff >= 0 && diff < days) {
        dailyCounts[days - 1 - diff]++;
      }
    }
    final maxCount = dailyCounts.fold<int>(0, (a, b) => a > b ? a : b);
    const w = 600.0, h = 220.0, pad = 40.0;
    const chartW = w - pad * 2;
    const chartH = h - pad * 2;

    final buf = StringBuffer();
    buf.writeln(
        '<svg viewBox="0 0 $w $h" xmlns="http://www.w3.org/2000/svg" style="width:100%;max-width:${w}px;">');
    // 网格线
    for (var i = 0; i <= 4; i++) {
      final gy = pad + (chartH / 4) * i;
      buf.writeln(
          '<line x1="$pad" y1="$gy" x2="${w - pad}" y2="$gy" stroke="#eee" stroke-width="1"/>');
      final value = (maxCount * (4 - i) / 4).round();
      buf.writeln(
          '<text x="${pad - 6}" y="${gy + 4}" text-anchor="end" font-size="10" fill="#999">$value</text>');
    }
    // X 轴标签（每 5 天一个）
    for (var i = 0; i < days; i += 5) {
      final x = pad + (chartW / (days - 1)) * i;
      final dayAgo = days - 1 - i;
      final label = dayAgo == 0 ? '今天' : '$dayAgo天前';
      buf.writeln(
          '<text x="$x" y="${h - pad + 14}" text-anchor="middle" font-size="10" fill="#999">${HtmlRenderUtils.escapeHtml(label)}</text>');
    }

    if (maxCount > 0) {
      // 区域填充
      final areaPoints = <String>[];
      for (var i = 0; i < days; i++) {
        final x = pad + (chartW / (days - 1)) * i;
        final y = pad + chartH - (dailyCounts[i] / maxCount) * chartH;
        areaPoints.add('${x.toStringAsFixed(1)},${y.toStringAsFixed(1)}');
      }
      const lastX = pad + chartW;
      const baseY = pad + chartH;
      buf.writeln(
          '<polygon points="$pad,$baseY ${areaPoints.join(' ')} $lastX,$baseY" fill="rgba(99,102,241,0.12)"/>');
      // 折线
      buf.writeln(
          '<polyline points="${areaPoints.join(' ')}" fill="none" stroke="#6366F1" stroke-width="2"/>');
      // 数据点
      for (var i = 0; i < days; i++) {
        final x = pad + (chartW / (days - 1)) * i;
        final y = pad + chartH - (dailyCounts[i] / maxCount) * chartH;
        if (dailyCounts[i] > 0) {
          buf.writeln(
              '<circle cx="${x.toStringAsFixed(1)}" cy="${y.toStringAsFixed(1)}" r="2.5" fill="#6366F1"/>');
        }
      }
    } else {
      buf.writeln(
          '<text x="${w / 2}" y="${h / 2}" text-anchor="middle" font-size="12" fill="#999">暂无复习记录</text>');
    }
    buf.writeln('</svg>');
    return buf.toString();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 工具
  // ─────────────────────────────────────────────────────────────────────────

  String _formatDate(DateTime dt, bool anonymize) {
    final y = dt.year.toString();
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    if (anonymize) return '$y-$m-$d';
    final hh = dt.hour.toString().padLeft(2, '0');
    final mm = dt.minute.toString().padLeft(2, '0');
    return '$y-$m-$d $hh:$mm';
  }

  String _masteryColorHex(MasteryLevel level) => switch (level) {
        MasteryLevel.newQuestion => '#dc2626',
        MasteryLevel.reviewing => '#d97706',
        MasteryLevel.mastered => '#16a34a',
      };
}
