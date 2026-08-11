import 'package:smart_wrong_notebook/src/app/theme/app_visual_style.dart';
import 'package:smart_wrong_notebook/src/shared/utils/weekly_report_aggregator.dart';

/// 生成学情周报 HTML 文档。
///
/// 返回完全自包含的 HTML 字符串（内联 CSS、内联 SVG 图表、不依赖外部资源），
/// 可直接写入文件后用 WebView 渲染或转 PDF。结构与 [HtmlExportService]
/// 错题报告不同，因此不复用其模板路径。
///
/// [studentName] 用于封面姓名栏；为空时显示下划线占位。
/// [watermark] 非空时叠加固定位置半透明水印。
String generateWeeklyReportHtmlSync(
  WeeklyReportData data, {
  String? studentName,
  String? watermark,
  AppVisualStyle visualStyle = AppVisualStyle.academic,
}) {
  final buf = StringBuffer();
  buf.writeln('<!DOCTYPE html>');
  buf.writeln('<html lang="zh-CN">');
  buf.writeln('<head>');
  buf.writeln('<meta charset="UTF-8">');
  buf.writeln(
      '<meta name="viewport" content="width=device-width, initial-scale=1.0">');
  buf.writeln('<title>本周学情报告</title>');
  buf.writeln('<style>');
  buf.writeln(_buildCss());
  buf.writeln(_buildVisualStyleCss(visualStyle));
  buf.writeln('</style>');
  buf.writeln('</head>');
  buf.writeln('<body>');
  if (watermark != null && watermark.isNotEmpty) {
    buf.writeln(
        '  <div class="watermark">${_escapeHtml(watermark)}</div>');
  }
  buf.writeln('<div class="page">');

  // 封面
  buf.write(_buildCover(data, studentName));
  // 概览卡片
  buf.write(_buildOverviewCards(data));
  // 错因分类 Top3（横向条形图）
  buf.write(_buildMistakeBars(data));
  // 薄弱知识点 Top5
  buf.write(_buildWeakPoints(data));
  // 学科分布（饼图）
  buf.write(_buildSubjectPie(data));
  // 7 天复习趋势
  buf.write(_buildDailyTrend(data));

  buf.writeln('</div>');
  buf.writeln('</body>');
  buf.writeln('</html>');
  return buf.toString();
}

/// 异步入口（保持与调用方 Future 签名一致；内部为同步实现）。
Future<String> generateWeeklyReportHtml(
  WeeklyReportData data, {
  String? studentName,
  String? watermark,
  AppVisualStyle visualStyle = AppVisualStyle.academic,
}) async {
  return generateWeeklyReportHtmlSync(
    data,
    studentName: studentName,
    watermark: watermark,
    visualStyle: visualStyle,
  );
}

// ─────────────────────────────────────────────────────────────────────────
// CSS
// ─────────────────────────────────────────────────────────────────────────

String _buildVisualStyleCss(AppVisualStyle style) {
  final (:accent, :accentSoft, :background, :surface, :border, :radius) =
      switch (style) {
    AppVisualStyle.academic => (
        accent: '#4056C7',
        accentSoft: '#EEF0FF',
        background: '#F6F7FC',
        surface: '#FFFFFF',
        border: '#DDE1F2',
        radius: '14px',
      ),
    AppVisualStyle.paper => (
        accent: '#8A5A35',
        accentSoft: '#F1E5D6',
        background: '#F7F1E6',
        surface: '#FFFDF8',
        border: '#DCC9B3',
        radius: '6px',
      ),
    AppVisualStyle.aurora => (
        accent: '#6547D4',
        accentSoft: '#EEE9FF',
        background: '#F6F3FF',
        surface: '#FFFFFF',
        border: '#DAD0FF',
        radius: '20px',
      ),
    AppVisualStyle.forest => (
        accent: '#25735A',
        accentSoft: '#E1F0E8',
        background: '#F1F7F3',
        surface: '#FCFFFD',
        border: '#C8DED2',
        radius: '12px',
      ),
  };
  return '''
:root {
  --bg: $background;
  --surface: $surface;
  --border: $border;
  --accent: $accent;
  --accent-soft: $accentSoft;
  --work-radius: $radius;
}
.stat-card { border-radius: var(--work-radius); }
.cover h1::after {
  content: " · ${style.label}";
  font-size: 11pt;
  font-weight: 500;
  color: var(--text-muted);
}
''';
}

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

/* ── 封面 ── */
.cover {
  text-align: center;
  padding-top: 24mm;
  page-break-after: always;
}
.cover h1 {
  font-size: 30pt;
  font-weight: 700;
  color: var(--accent);
  margin: 0 0 8px;
}
.cover .subtitle {
  font-size: 14pt;
  color: var(--text-muted);
  margin-bottom: 28px;
}
.cover .info-row {
  display: flex;
  justify-content: center;
  flex-wrap: wrap;
  gap: 24px;
  margin-bottom: 28px;
  font-size: 13pt;
  color: var(--text);
}
.cover .info-row .info-item { white-space: nowrap; }
.cover .info-row .info-label {
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
  grid-template-columns: repeat(5, 1fr);
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

/* ── 错因分类 Top3 横向条形图 ── */
.bar-row {
  display: flex;
  align-items: center;
  gap: 10px;
  margin-bottom: 8px;
  font-size: 12pt;
}
.bar-row .bar-label {
  width: 96px;
  text-align: right;
  color: var(--text);
}
.bar-row .bar-track {
  flex: 1;
  height: 14px;
  background: var(--track);
  border-radius: 7px;
  overflow: hidden;
}
.bar-row .bar-fill {
  height: 100%;
  border-radius: 7px;
  background: var(--accent);
}
.bar-row .bar-count {
  width: 48px;
  color: var(--text-muted);
}
.empty-hint {
  color: var(--text-muted);
  font-size: 11pt;
  font-style: italic;
  padding: 8px 0;
}

/* ── 薄弱知识点列表 ── */
.kp-list {
  list-style: none;
  padding: 0;
  margin: 0;
}
.kp-list li {
  display: flex;
  align-items: center;
  gap: 10px;
  padding: 8px 12px;
  margin-bottom: 6px;
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: 8px;
  font-size: 12pt;
}
.kp-list .kp-rank {
  width: 24px;
  height: 24px;
  border-radius: 50%;
  background: var(--accent);
  color: #fff;
  display: inline-flex;
  align-items: center;
  justify-content: center;
  font-size: 11pt;
  font-weight: 700;
  flex-shrink: 0;
}
.kp-list .kp-text { flex: 1; }
.kp-list .kp-count {
  color: var(--text-muted);
  font-size: 11pt;
}

/* ── 学科分布饼图（纯 CSS conic-gradient） ── */
.pie-wrap {
  display: flex;
  align-items: center;
  gap: 24px;
  flex-wrap: wrap;
}
.pie {
  width: 160px;
  height: 160px;
  border-radius: 50%;
  flex-shrink: 0;
  position: relative;
}
.pie::after {
  content: '';
  position: absolute;
  top: 50%;
  left: 50%;
  width: 70px;
  height: 70px;
  background: var(--surface);
  border-radius: 50%;
  transform: translate(-50%, -50%);
}
.pie-empty {
  width: 160px;
  height: 160px;
  border-radius: 50%;
  background: var(--track);
  flex-shrink: 0;
  display: flex;
  align-items: center;
  justify-content: center;
  color: var(--text-muted);
  font-size: 11pt;
}
.pie-legend {
  flex: 1;
  min-width: 200px;
}
.pie-legend .legend-row {
  display: flex;
  align-items: center;
  gap: 8px;
  margin-bottom: 6px;
  font-size: 12pt;
}
.pie-legend .legend-swatch {
  width: 14px;
  height: 14px;
  border-radius: 3px;
  flex-shrink: 0;
}
.pie-legend .legend-label { flex: 1; }
.pie-legend .legend-count { color: var(--text-muted); }

/* ── 7 天复习趋势折线图（SVG） ── */
.trend-svg {
  width: 100%;
  max-width: 580px;
  display: block;
  margin: 0 auto;
}
.trend-svg text { fill: var(--text-muted); }
.trend-svg .grid-line { stroke: var(--border); stroke-width: 1; }
.trend-svg .trend-area { fill: rgba(99,102,241,0.12); }
.trend-svg .trend-line {
  fill: none;
  stroke: var(--accent);
  stroke-width: 2;
}
.trend-svg .trend-dot { fill: var(--accent); }

@media print {
  .page { max-width: none; }
  .section { break-inside: avoid; }
}
''';
}

// ─────────────────────────────────────────────────────────────────────────
// 各 Section 生成
// ─────────────────────────────────────────────────────────────────────────

String _buildCover(WeeklyReportData data, String? studentName) {
  final buf = StringBuffer();
  buf.writeln('  <section class="cover">');
  buf.writeln('    <h1>本周学情报告</h1>');
  buf.writeln('    <div class="subtitle">Weekly Learning Report</div>');
  buf.writeln('    <div class="info-row">');
  final nameDisplay = (studentName == null || studentName.isEmpty)
      ? '____________'
      : studentName;
  buf.writeln(
      '      <span class="info-item"><span class="info-label">姓&emsp;名：</span>${_escapeHtml(nameDisplay)}</span>');
  buf.writeln(
      '      <span class="info-item"><span class="info-label">周&emsp;期：</span>${_formatDate(data.weekStart)} 至 ${_formatDate(data.weekEnd)}</span>');
  buf.writeln('    </div>');
  buf.writeln('  </section>');
  return buf.toString();
}

String _buildOverviewCards(WeeklyReportData data) {
  final buf = StringBuffer();
  buf.writeln('  <section class="section">');
  buf.writeln('    <h2>本周概览</h2>');
  buf.writeln('    <div class="stats-grid">');
  buf.writeln('      <div class="stat-card">');
  buf.writeln('        <div class="stat-value">${data.newQuestionsCount}</div>');
  buf.writeln('        <div class="stat-label">新增题数</div>');
  buf.writeln('      </div>');
  buf.writeln('      <div class="stat-card">');
  buf.writeln('        <div class="stat-value">${data.reviewedCount}</div>');
  buf.writeln('        <div class="stat-label">完成复习</div>');
  buf.writeln('      </div>');
  buf.writeln('      <div class="stat-card">');
  buf.writeln('        <div class="stat-value">${data.masteredCount}</div>');
  buf.writeln('        <div class="stat-label">新掌握</div>');
  buf.writeln('      </div>');
  buf.writeln('      <div class="stat-card">');
  buf.writeln(
      '        <div class="stat-value">${(data.masteryRate * 100).round()}%</div>');
  buf.writeln('        <div class="stat-label">掌握率</div>');
  buf.writeln('      </div>');
  buf.writeln('      <div class="stat-card">');
  buf.writeln('        <div class="stat-value">${data.streakDays}</div>');
  buf.writeln('        <div class="stat-label">连续天数</div>');
  buf.writeln('      </div>');
  buf.writeln('    </div>');
  buf.writeln('  </section>');
  return buf.toString();
}

String _buildMistakeBars(WeeklyReportData data) {
  final buf = StringBuffer();
  buf.writeln('  <section class="section">');
  buf.writeln('    <h2>错因分类 Top 3</h2>');
  final list = data.topMistakeCategories;
  if (list.isEmpty) {
    buf.writeln('    <div class="empty-hint">本周新增题暂无错因分类数据</div>');
  } else {
    final maxCount = list.fold<int>(0, (a, e) => e.count > a ? e.count : a);
    for (final entry in list) {
      final pct = maxCount == 0 ? 0 : (entry.count / maxCount * 100).round();
      buf.writeln('    <div class="bar-row">');
      buf.writeln(
          '      <span class="bar-label">${_escapeHtml(entry.label)}</span>');
      buf.writeln('      <span class="bar-track">');
      buf.writeln(
          '        <span class="bar-fill" style="width:$pct%"></span>');
      buf.writeln('      </span>');
      buf.writeln('      <span class="bar-count">${entry.count}</span>');
      buf.writeln('    </div>');
    }
  }
  buf.writeln('  </section>');
  return buf.toString();
}

String _buildWeakPoints(WeeklyReportData data) {
  final buf = StringBuffer();
  buf.writeln('  <section class="section">');
  buf.writeln('    <h2>薄弱知识点 Top 5</h2>');
  final list = data.weakKnowledgePoints;
  if (list.isEmpty) {
    buf.writeln('    <div class="empty-hint">本周新增题暂无知识点数据</div>');
  } else {
    buf.writeln('    <ul class="kp-list">');
    for (var i = 0; i < list.length; i++) {
      final entry = list[i];
      buf.writeln('      <li>');
      buf.writeln('        <span class="kp-rank">${i + 1}</span>');
      buf.writeln(
          '        <span class="kp-text">${_escapeHtml(entry.label)}</span>');
      buf.writeln('        <span class="kp-count">${entry.count} 次</span>');
      buf.writeln('      </li>');
    }
    buf.writeln('    </ul>');
  }
  buf.writeln('  </section>');
  return buf.toString();
}

String _buildSubjectPie(WeeklyReportData data) {
  final buf = StringBuffer();
  buf.writeln('  <section class="section">');
  buf.writeln('    <h2>学科分布</h2>');
  final entries = data.newQuestionsBySubject.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  final total = entries.fold<int>(0, (a, e) => a + e.value);
  if (total == 0) {
    buf.writeln(
        '    <div class="empty-hint">本周未新增错题，暂无学科分布数据</div>');
  } else {
    // 用 conic-gradient 拼接饼图。
    final colors = _subjectPalette();
    final stops = <String>[];
    var acc = 0.0;
    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      final startPct = acc / total * 100;
      acc += e.value;
      final endPct = acc / total * 100;
      final color = colors[i % colors.length];
      stops.add('$color ${startPct.toStringAsFixed(2)}% ${endPct.toStringAsFixed(2)}%');
    }
    final gradient = stops.join(', ');
    buf.writeln('    <div class="pie-wrap">');
    buf.writeln(
        '      <div class="pie" style="background: conic-gradient($gradient);"></div>');
    buf.writeln('      <div class="pie-legend">');
    for (var i = 0; i < entries.length; i++) {
      final e = entries[i];
      final color = colors[i % colors.length];
      final pct = (e.value / total * 100).round();
      buf.writeln('        <div class="legend-row">');
      buf.writeln(
          '          <span class="legend-swatch" style="background:$color"></span>');
      buf.writeln(
          '          <span class="legend-label">${_escapeHtml(e.key.label)}</span>');
      buf.writeln(
          '          <span class="legend-count">${e.value} 题 · $pct%</span>');
      buf.writeln('        </div>');
    }
    buf.writeln('      </div>');
    buf.writeln('    </div>');
  }
  buf.writeln('  </section>');
  return buf.toString();
}

String _buildDailyTrend(WeeklyReportData data) {
  final buf = StringBuffer();
  buf.writeln('  <section class="section">');
  buf.writeln('    <h2>本周复习趋势</h2>');
  buf.write(_buildTrendSvg(data.dailyReviewCounts, data.weekStart));
  buf.writeln('  </section>');
  return buf.toString();
}

/// 生成 7 天复习趋势 SVG 折线图。
String _buildTrendSvg(List<int> dailyCounts, DateTime weekStart) {
  const w = 580.0;
  const h = 220.0;
  const pad = 40.0;
  const chartW = w - pad * 2;
  const chartH = h - pad * 2;
  final days = dailyCounts.length;
  final maxCount =
      dailyCounts.fold<int>(0, (a, b) => a > b ? a : b).clamp(1, 999999);

  final buf = StringBuffer();
  buf.writeln(
      '<svg class="trend-svg" viewBox="0 0 $w $h" xmlns="http://www.w3.org/2000/svg">');

  // 网格线
  for (var i = 0; i <= 4; i++) {
    final gy = pad + (chartH / 4) * i;
    buf.writeln(
        '<line class="grid-line" x1="$pad" y1="${gy.toStringAsFixed(1)}" x2="${(w - pad).toStringAsFixed(1)}" y2="${gy.toStringAsFixed(1)}"/>');
    final value = (maxCount * (4 - i) / 4).round();
    buf.writeln(
        '<text x="${(pad - 6).toStringAsFixed(1)}" y="${(gy + 4).toStringAsFixed(1)}" text-anchor="end" font-size="10">$value</text>');
  }

  // 数据点
  final points = <String>[];
  for (var i = 0; i < days; i++) {
    final x = pad + (chartW / (days - 1)) * i;
    final y = pad + chartH - (dailyCounts[i] / maxCount) * chartH;
    points.add('${x.toStringAsFixed(1)},${y.toStringAsFixed(1)}');
  }

  if (dailyCounts.every((c) => c == 0)) {
    buf.writeln(
        '<text x="${(w / 2).toStringAsFixed(1)}" y="${(h / 2).toStringAsFixed(1)}" text-anchor="middle" font-size="12">本周暂无复习记录</text>');
  } else {
    // 区域填充
    final lastX = pad + chartW;
    final baseY = pad + chartH;
    buf.writeln(
        '<polygon class="trend-area" points="$pad,${baseY.toStringAsFixed(1)} ${points.join(' ')} $lastX,${baseY.toStringAsFixed(1)}"/>');
    // 折线
    buf.writeln(
        '<polyline class="trend-line" points="${points.join(' ')}"/>');
    // 数据点
    for (var i = 0; i < days; i++) {
      final x = pad + (chartW / (days - 1)) * i;
      final y = pad + chartH - (dailyCounts[i] / maxCount) * chartH;
      if (dailyCounts[i] > 0) {
        buf.writeln(
            '<circle class="trend-dot" cx="${x.toStringAsFixed(1)}" cy="${y.toStringAsFixed(1)}" r="3.5"/>');
      }
    }
  }

  // X 轴标签：周一 ~ 周日
  const weekLabels = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
  for (var i = 0; i < days; i++) {
    final x = pad + (chartW / (days - 1)) * i;
    final label = weekLabels[i];
    buf.writeln(
        '<text x="${x.toStringAsFixed(1)}" y="${(h - pad + 16).toStringAsFixed(1)}" text-anchor="middle" font-size="10">${_escapeHtml(label)}</text>');
    final day = weekStart.add(Duration(days: i));
    final dayStr = '${day.month.toString().padLeft(2, '0')}/${day.day.toString().padLeft(2, '0')}';
    buf.writeln(
        '<text x="${x.toStringAsFixed(1)}" y="${(h - pad + 30).toStringAsFixed(1)}" text-anchor="middle" font-size="9">$dayStr</text>');
  }

  buf.writeln('</svg>');
  return buf.toString();
}

// ─────────────────────────────────────────────────────────────────────────
// 工具
// ─────────────────────────────────────────────────────────────────────────

String _escapeHtml(String input) {
  return input
      .replaceAll('&', '&amp;')
      .replaceAll('<', '&lt;')
      .replaceAll('>', '&gt;')
      .replaceAll('"', '&quot;')
      .replaceAll("'", '&#39;');
}

String _formatDate(DateTime dt) {
  final y = dt.year.toString();
  final m = dt.month.toString().padLeft(2, '0');
  final d = dt.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

/// 学科配色板（避免依赖 [Subject.color]，便于在 HTML/CSS 中以统一调色板呈现）。
List<String> _subjectPalette() {
  return const <String>[
    '#6366F1', // indigo
    '#16A34A', // green
    '#D97706', // amber
    '#EA580C', // orange
    '#7C3AED', // violet
    '#0EA5E9', // sky
    '#DC2626', // red
    '#14B8A6', // teal
    '#9333EA', // purple
    '#65A30D', // lime
    '#64748B', // slate
  ];
}
