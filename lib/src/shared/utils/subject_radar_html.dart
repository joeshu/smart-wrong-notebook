import 'dart:math' as math;

import 'package:smart_wrong_notebook/src/shared/utils/html_render_utils.dart';
import 'package:smart_wrong_notebook/src/shared/utils/subject_radar_aggregator.dart';

/// 生成学科能力雷达图 HTML 文档。
///
/// 返回完全自包含的 HTML 字符串（内联 CSS、内联 SVG 雷达图、不依赖外部资源），
/// 可直接写入文件后用 WebView 渲染或转 PDF。结构与 [generateWeeklyReportHtmlSync]
/// 相似但聚焦于学科能力维度，不复用其模板路径。
///
/// [studentName] 用于封面姓名栏；为空时显示下划线占位。
String generateSubjectRadarHtmlSync(
  SubjectRadarData data, {
  String? studentName,
}) {
  final buf = StringBuffer();
  buf.writeln('<!DOCTYPE html>');
  buf.writeln('<html lang="zh-CN">');
  buf.writeln('<head>');
  buf.writeln('<meta charset="UTF-8">');
  buf.writeln(
      '<meta name="viewport" content="width=device-width, initial-scale=1.0">');
  buf.writeln('<title>学科能力雷达图</title>');
  buf.writeln('<style>');
  buf.writeln(_buildCss());
  buf.writeln('</style>');
  buf.writeln('</head>');
  buf.writeln('<body>');
  buf.writeln('<div class="page">');

  // 顶部标题区
  buf.write(_buildHeader(data, studentName));
  // 概览卡片
  buf.write(_buildOverviewCards(data));
  // 雷达图 SVG
  buf.write(_buildRadarSection(data));
  // 学科得分明细表
  buf.write(_buildScoreTable(data));
  // 简要说明
  buf.write(_buildFormulaNote());

  buf.writeln('</div>');
  buf.writeln('</body>');
  buf.writeln('</html>');
  return buf.toString();
}

/// 异步入口（保持与调用方 Future 签名一致；内部为同步实现）。
Future<String> generateSubjectRadarHtml(
  SubjectRadarData data, {
  String? studentName,
}) async {
  return generateSubjectRadarHtmlSync(
    data,
    studentName: studentName,
  );
}

// ─────────────────────────────────────────────────────────────────────────
// CSS
// ─────────────────────────────────────────────────────────────────────────

String _buildCss() {
  return '''
@page {
  size: A4 portrait;
  margin: 18mm 16mm 20mm 16mm;
  @bottom-center {
    content: "第 " counter(page) " 页 / 共 " counter(pages) " 页";
    font-size: 9pt;
    color: #999;
  }
}
* { box-sizing: border-box; }
:root {
  --bg: #fafafa;
  --surface: #ffffff;
  --text: #1f2937;
  --text-muted: #6b7280;
  --border: #e5e7eb;
  --accent: #6366F1;
  --accent-soft: #f5f3ff;
  --track: #f3f4f6;
  --shadow: 0 1px 3px rgba(0,0,0,0.05);
}
@media (prefers-color-scheme: dark) {
  :root {
    --bg: #0f172a;
    --surface: #1e293b;
    --text: #e2e8f0;
    --text-muted: #94a3b8;
    --border: #334155;
    --accent: #818cf8;
    --accent-soft: #1e1b4b;
    --track: #334155;
    --shadow: 0 1px 3px rgba(0,0,0,0.4);
  }
}
body {
  font-family: -apple-system, 'PingFang SC', 'Microsoft YaHei', 'Hiragino Sans GB', sans-serif;
  font-size: 14pt;
  line-height: 1.7;
  color: var(--text);
  margin: 0;
  padding: 0;
  background: var(--bg);
}
.page { max-width: 190mm; margin: 0 auto; }

/* ── 顶部标题区 ── */
.header {
  text-align: center;
  padding: 8mm 0 4mm;
  border-bottom: 2px solid var(--accent);
  margin-bottom: 12px;
}
.header h1 {
  font-size: 26pt;
  font-weight: 700;
  color: var(--accent);
  margin: 0 0 6px;
}
.header .subtitle {
  font-size: 12pt;
  color: var(--text-muted);
  margin-bottom: 8px;
}
.header .info-row {
  display: flex;
  justify-content: center;
  flex-wrap: wrap;
  gap: 24px;
  font-size: 12pt;
  color: var(--text);
}
.header .info-row .info-label {
  color: var(--text-muted);
  margin-right: 6px;
}

/* ── 概览卡片 ── */
.section {
  margin-top: 18px;
  page-break-inside: avoid;
}
.section h2 {
  font-size: 18pt;
  font-weight: 700;
  color: var(--accent);
  margin: 0 0 12px;
  padding-bottom: 6px;
  border-bottom: 2px solid var(--accent);
}
.stats-grid {
  display: grid;
  grid-template-columns: repeat(4, 1fr);
  gap: 10px;
  margin-bottom: 8px;
}
.stat-card {
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: 10px;
  padding: 14px 8px;
  text-align: center;
  box-shadow: var(--shadow);
}
.stat-card .stat-value {
  font-size: 22pt;
  font-weight: 700;
  color: var(--accent);
  line-height: 1.1;
}
.stat-card .stat-label {
  font-size: 10pt;
  color: var(--text-muted);
  margin-top: 4px;
}

/* ── 雷达图 SVG ── */
.radar-wrap {
  display: flex;
  justify-content: center;
  align-items: center;
  padding: 8px 0;
}
.radar-svg {
  width: 100%;
  max-width: 500px;
  display: block;
  margin: 0 auto;
}
.radar-svg text { fill: var(--text); }
.radar-svg .grid-polygon {
  fill: none;
  stroke: var(--border);
  stroke-width: 1;
}
.radar-svg .grid-polygon.outer {
  stroke: var(--text-muted);
  stroke-width: 1.2;
}
.radar-svg .axis-line {
  stroke: var(--border);
  stroke-width: 1;
}
.radar-svg .axis-label {
  font-size: 13px;
  font-weight: 600;
  fill: var(--text);
}
.radar-svg .score-label {
  font-size: 11px;
  fill: var(--text-muted);
}
.radar-svg .data-polygon {
  fill: rgba(99,102,241,0.25);
  stroke: #6366F1;
  stroke-width: 2;
  stroke-linejoin: round;
}
.radar-svg .data-dot {
  fill: #6366F1;
}
@media (prefers-color-scheme: dark) {
  .radar-svg .data-polygon {
    fill: rgba(129,140,248,0.30);
    stroke: #818cf8;
  }
  .radar-svg .data-dot { fill: #818cf8; }
}
.radar-empty {
  text-align: center;
  color: var(--text-muted);
  font-size: 12pt;
  font-style: italic;
  padding: 40px 12px;
  border: 1px dashed var(--border);
  border-radius: 8px;
}

/* ── 得分明细表 ── */
.score-table {
  width: 100%;
  border-collapse: collapse;
  font-size: 12pt;
  margin-top: 6px;
}
.score-table th,
.score-table td {
  border: 1px solid var(--border);
  padding: 8px 10px;
  text-align: center;
}
.score-table th {
  background: var(--accent-soft);
  color: var(--accent);
  font-weight: 700;
}
.score-table td.subject-cell {
  text-align: left;
  font-weight: 600;
}
.score-table td.score-cell {
  font-weight: 700;
  color: var(--accent);
}
.score-table tr:nth-child(even) td {
  background: var(--surface);
}

/* ── 公式说明 ── */
.formula-note {
  margin-top: 16px;
  padding: 10px 14px;
  background: var(--accent-soft);
  border-left: 4px solid var(--accent);
  border-radius: 4px;
  font-size: 11pt;
  color: var(--text);
}
.formula-note .formula {
  font-family: 'Menlo', 'Consolas', monospace;
  color: var(--accent);
  font-weight: 600;
}

@media print {
  .page { max-width: none; }
  .section { break-inside: avoid; }
}
''';
}

// ─────────────────────────────────────────────────────────────────────────
// 各 Section 生成
// ─────────────────────────────────────────────────────────────────────────

String _buildHeader(SubjectRadarData data, String? studentName) {
  final buf = StringBuffer();
  buf.writeln('  <header class="header">');
  buf.writeln('    <h1>学科能力雷达图</h1>');
  buf.writeln('    <div class="subtitle">Subject Ability Radar</div>');
  buf.writeln('    <div class="info-row">');
  final nameDisplay = (studentName == null || studentName.isEmpty)
      ? '____________'
      : studentName;
  buf.writeln(
      '      <span><span class="info-label">姓&emsp;名：</span>${HtmlRenderUtils.escapeHtml(nameDisplay)}</span>');
  buf.writeln(
      '      <span><span class="info-label">生成时间：</span>${_formatDateTime(data.generatedAt)}</span>');
  buf.writeln('    </div>');
  buf.writeln('  </header>');
  return buf.toString();
}

String _buildOverviewCards(SubjectRadarData data) {
  final buf = StringBuffer();
  buf.writeln('  <section class="section">');
  buf.writeln('    <h2>概览</h2>');
  buf.writeln('    <div class="stats-grid">');
  buf.writeln('      <div class="stat-card">');
  buf.writeln('        <div class="stat-value">${data.totalQuestions}</div>');
  buf.writeln('        <div class="stat-label">总题数</div>');
  buf.writeln('      </div>');
  buf.writeln('      <div class="stat-card">');
  buf.writeln('        <div class="stat-value">${data.totalMastered}</div>');
  buf.writeln('        <div class="stat-label">已掌握</div>');
  buf.writeln('      </div>');
  buf.writeln('      <div class="stat-card">');
  buf.writeln('        <div class="stat-value">${data.totalReviewing}</div>');
  buf.writeln('        <div class="stat-label">学习中</div>');
  buf.writeln('      </div>');
  buf.writeln('      <div class="stat-card">');
  buf.writeln('        <div class="stat-value">${data.totalNew}</div>');
  buf.writeln('        <div class="stat-label">待学习</div>');
  buf.writeln('      </div>');
  buf.writeln('    </div>');
  buf.writeln('  </section>');
  return buf.toString();
}

String _buildRadarSection(SubjectRadarData data) {
  final buf = StringBuffer();
  buf.writeln('  <section class="section">');
  buf.writeln('    <h2>能力雷达图</h2>');
  if (data.scores.isEmpty) {
    buf.writeln(
        '    <div class="radar-empty">暂无题目数据，无法生成雷达图</div>');
  } else if (data.scores.length < 3) {
    buf.writeln(
        '    <div class="radar-empty">至少需要 3 个学科才能绘制雷达图，当前仅有 ${data.scores.length} 个</div>');
  } else {
    buf.write(_buildRadarSvg(data.scores));
  }
  buf.writeln('  </section>');
  return buf.toString();
}

/// 生成雷达图 SVG。viewport 500x500，中心 (250, 250)，半径 200。
String _buildRadarSvg(List<SubjectScore> scores) {
  const cx = 250.0;
  const cy = 250.0;
  const r = 200.0;
  final n = scores.length;

  // 各学科在圆周上的角度（从正上方开始顺时针）。
  final angles = List<double>.generate(n, (i) {
    return -math.pi / 2 + i * 2 * math.pi / n;
  });

  // 计算指定半径与顶点索引的坐标。
  double pointX(int i, double radius) =>
      cx + radius * math.cos(angles[i]);
  double pointY(int i, double radius) =>
      cy + radius * math.sin(angles[i]);

  String polygonPoints(double scale) {
    final pts = <String>[];
    for (var i = 0; i < n; i++) {
      pts.add('${pointX(i, r * scale).toStringAsFixed(2)},'
          '${pointY(i, r * scale).toStringAsFixed(2)}');
    }
    return pts.join(' ');
  }

  final buf = StringBuffer();
  buf.writeln(
      '<svg class="radar-svg" viewBox="0 0 500 500" xmlns="http://www.w3.org/2000/svg">');

  // 同心多边形网格：25% / 50% / 75% / 100%
  const gridLevels = [0.25, 0.5, 0.75, 1.0];
  for (final level in gridLevels) {
    final cls = level == 1.0 ? 'grid-polygon outer' : 'grid-polygon';
    buf.writeln(
        '<polygon class="$cls" points="${polygonPoints(level)}"/>');
  }

  // 从中心向各学科轴的射线
  for (var i = 0; i < n; i++) {
    buf.writeln(
        '<line class="axis-line" x1="${cx.toStringAsFixed(2)}" y1="${cy.toStringAsFixed(2)}" '
        'x2="${pointX(i, r).toStringAsFixed(2)}" y2="${pointY(i, r).toStringAsFixed(2)}"/>');
  }

  // 数据多边形顶点
  final dataPoints = <String>[];
  for (var i = 0; i < n; i++) {
    final score = scores[i].abilityScore.clamp(0.0, 100.0);
    final radius = r * (score / 100);
    dataPoints.add('${pointX(i, radius).toStringAsFixed(2)},'
        '${pointY(i, radius).toStringAsFixed(2)}');
  }

  // 数据多边形
  buf.writeln(
      '<polygon class="data-polygon" points="${dataPoints.join(' ')}"/>');

  // 每个顶点的数据点 + 得分标签 + 学科标签
  for (var i = 0; i < n; i++) {
    final score = scores[i].abilityScore.clamp(0.0, 100.0);
    final radius = r * (score / 100);
    final dx = pointX(i, radius);
    final dy = pointY(i, radius);
    buf.writeln(
        '<circle class="data-dot" cx="${dx.toStringAsFixed(2)}" cy="${dy.toStringAsFixed(2)}" r="4"/>');

    // 得分标签放在数据点内侧
    final scoreLabelR = radius - 12;
    if (scoreLabelR > 0) {
      final sx = pointX(i, scoreLabelR);
      final sy = pointY(i, scoreLabelR);
      buf.writeln(
          '<text class="score-label" x="${sx.toStringAsFixed(2)}" y="${sy.toStringAsFixed(2)}" '
          'text-anchor="middle" dominant-baseline="middle">${score.toStringAsFixed(0)}</text>');
    }
  }

  // 学科标签：放在轴端外侧，根据象限调整 text-anchor / dominant-baseline
  const labelR = 218.0;
  for (var i = 0; i < n; i++) {
    final lx = pointX(i, labelR);
    final ly = pointY(i, labelR);
    final angle = angles[i];
    // cos(angle) > 0.2 -> 右侧 anchor=start；< -0.2 -> 左侧 anchor=end；中间 middle
    String anchor;
    if (math.cos(angle) > 0.2) {
      anchor = 'start';
    } else if (math.cos(angle) < -0.2) {
      anchor = 'end';
    } else {
      anchor = 'middle';
    }
    String baseline;
    if (math.sin(angle) < -0.5) {
      baseline = 'auto'; // 顶部，文字在轴端上方
    } else if (math.sin(angle) > 0.5) {
      baseline = 'hanging'; // 底部，文字在轴端下方
    } else {
      baseline = 'middle';
    }
    final label = HtmlRenderUtils.escapeHtml(scores[i].subject.label);
    buf.writeln(
        '<text class="axis-label" x="${lx.toStringAsFixed(2)}" y="${ly.toStringAsFixed(2)}" '
        'text-anchor="$anchor" dominant-baseline="$baseline">$label</text>');
  }

  buf.writeln('</svg>');
  return buf.toString();
}

String _buildScoreTable(SubjectRadarData data) {
  final buf = StringBuffer();
  buf.writeln('  <section class="section">');
  buf.writeln('    <h2>学科得分明细</h2>');
  if (data.scores.isEmpty) {
    buf.writeln(
        '    <div class="radar-empty">暂无题目数据</div>');
  } else {
    buf.writeln('    <table class="score-table">');
    buf.writeln('      <thead>');
    buf.writeln('        <tr>');
    buf.writeln('          <th>学科</th>');
    buf.writeln('          <th>题数</th>');
    buf.writeln('          <th>已掌握</th>');
    buf.writeln('          <th>学习中</th>');
    buf.writeln('          <th>待学习</th>');
    buf.writeln('          <th>能力得分</th>');
    buf.writeln('        </tr>');
    buf.writeln('      </thead>');
    buf.writeln('      <tbody>');
    for (final s in data.scores) {
      buf.writeln('        <tr>');
      buf.writeln(
          '          <td class="subject-cell">${HtmlRenderUtils.escapeHtml(s.subject.label)}</td>');
      buf.writeln('          <td>${s.total}</td>');
      buf.writeln('          <td>${s.mastered}</td>');
      buf.writeln('          <td>${s.reviewing}</td>');
      buf.writeln('          <td>${s.newQuestions}</td>');
      buf.writeln(
          '          <td class="score-cell">${s.abilityScore.toStringAsFixed(1)}</td>');
      buf.writeln('        </tr>');
    }
    buf.writeln('      </tbody>');
    buf.writeln('    </table>');
  }
  buf.writeln('  </section>');
  return buf.toString();
}

String _buildFormulaNote() {
  final buf = StringBuffer();
  buf.writeln('  <div class="formula-note">');
  buf.writeln(
      '    <span>能力得分 = </span>'
      '<span class="formula">(已掌握 × 1.0 + 学习中 × 0.5) / 总题数 × 100</span>');
  buf.writeln(
      '    <div style="margin-top:4px;color:var(--text-muted);font-size:10pt;">'
      '已掌握权重 1.0，学习中权重 0.5，待学习权重 0；得分范围 0 ~ 100，得分越高表示该学科整体掌握程度越好。'
      '</div>');
  buf.writeln('  </div>');
  return buf.toString();
}

// ─────────────────────────────────────────────────────────────────────────
// 工具
// ─────────────────────────────────────────────────────────────────────────

String _formatDateTime(DateTime dt) {
  final y = dt.year.toString();
  final m = dt.month.toString().padLeft(2, '0');
  final d = dt.day.toString().padLeft(2, '0');
  final h = dt.hour.toString().padLeft(2, '0');
  final min = dt.minute.toString().padLeft(2, '0');
  return '$y-$m-$d $h:$min';
}
