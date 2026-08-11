import 'package:smart_wrong_notebook/src/domain/models/mistake_category.dart';
import 'package:smart_wrong_notebook/src/shared/utils/html_render_utils.dart';
import 'package:smart_wrong_notebook/src/shared/utils/mistake_trend_aggregator.dart';

/// 生成错因趋势热力图 HTML 文档。
///
/// 返回完全自包含的 HTML 字符串（内联 CSS、HTML table 热力图、不依赖外部资源），
/// 可直接写入文件后用 WebView 渲染或转 PDF。A4 横向排版便于展示 30 列日期。
///
/// [studentName] 用于顶部姓名栏；为空时显示下划线占位。
String generateMistakeTrendHtmlSync(
  MistakeTrendData data, {
  String? studentName,
}) {
  final buf = StringBuffer();
  buf.writeln('<!DOCTYPE html>');
  buf.writeln('<html lang="zh-CN">');
  buf.writeln('<head>');
  buf.writeln('<meta charset="UTF-8">');
  buf.writeln(
      '<meta name="viewport" content="width=device-width, initial-scale=1.0">');
  buf.writeln('<title>错因趋势热力图</title>');
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
  // 热力图主体
  buf.write(_buildHeatmapSection(data));
  // 错因分类图例
  buf.write(_buildLegendSection(data));
  // 简要说明
  buf.write(_buildNoteSection());

  buf.writeln('</div>');
  buf.writeln('</body>');
  buf.writeln('</html>');
  return buf.toString();
}

/// 异步入口（保持与调用方 Future 签名一致；内部为同步实现）。
Future<String> generateMistakeTrendHtml(
  MistakeTrendData data, {
  String? studentName,
}) async {
  return generateMistakeTrendHtmlSync(
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
  size: A4 landscape;
  margin: 12mm 12mm 16mm 12mm;
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
  line-height: 1.6;
  color: var(--text);
  margin: 0;
  padding: 0;
  background: var(--bg);
}
.page { max-width: 277mm; margin: 0 auto; }

/* ── 顶部标题区 ── */
.header {
  text-align: center;
  padding: 4mm 0 6mm;
  border-bottom: 2px solid var(--accent);
  margin-bottom: 6mm;
}
.header h1 {
  font-size: 24pt;
  font-weight: 700;
  color: var(--accent);
  margin: 0 0 4px;
}
.header .meta {
  font-size: 11pt;
  color: var(--text-muted);
  margin-top: 4px;
}
.header .meta .sep { margin: 0 10px; color: var(--border); }
.header .student-name {
  display: inline-block;
  margin-left: 10px;
  color: var(--text);
  font-weight: 600;
}

/* ── 概览卡片 ── */
.section {
  margin-top: 6mm;
  page-break-inside: avoid;
}
.section h2 {
  font-size: 14pt;
  font-weight: 700;
  color: var(--accent);
  margin: 0 0 8px;
  padding-bottom: 4px;
  border-bottom: 1px solid var(--border);
}
.stats-grid {
  display: grid;
  grid-template-columns: repeat(4, 1fr);
  gap: 8px;
  margin-bottom: 4px;
}
.stat-card {
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: 8px;
  padding: 10px 8px;
  text-align: center;
  box-shadow: var(--shadow);
}
.stat-card .stat-value {
  font-size: 18pt;
  font-weight: 700;
  color: var(--accent);
  line-height: 1.1;
}
.stat-card .stat-label {
  font-size: 9pt;
  color: var(--text-muted);
  margin-top: 2px;
}

/* ── 热力图主体 ── */
.heatmap-wrap {
  overflow-x: auto;
}
table.heatmap {
  border-collapse: separate;
  border-spacing: 2px;
  width: 100%;
  table-layout: fixed;
}
table.heatmap th,
table.heatmap td {
  border: 1px solid var(--border);
  padding: 0;
  text-align: center;
  vertical-align: middle;
  font-size: 8pt;
}
table.heatmap th.corner {
  width: 84px;
  background: var(--surface);
  font-weight: 600;
  color: var(--text-muted);
}
table.heatmap th.day-head {
  width: 22px;
  height: 24px;
  background: var(--surface);
  color: var(--text-muted);
  font-size: 7pt;
  font-weight: 500;
}
table.heatmap td.cat-label {
  width: 84px;
  background: var(--surface);
  text-align: left;
  padding: 4px 6px;
  font-size: 9pt;
  font-weight: 600;
  color: var(--text);
  white-space: nowrap;
  overflow: hidden;
  text-overflow: ellipsis;
}
table.heatmap td.cat-label .swatch {
  display: inline-block;
  width: 10px;
  height: 10px;
  border-radius: 2px;
  margin-right: 6px;
  vertical-align: middle;
}
table.heatmap td.cell {
  width: 22px;
  height: 22px;
  background: rgba(99, 102, 241, 0.04);
  color: var(--text-muted);
  font-size: 7pt;
}
table.heatmap td.cell.has-count {
  color: var(--text);
  font-weight: 600;
}
table.heatmap td.total-cell {
  width: 22px;
  height: 22px;
  background: var(--accent-soft);
  color: var(--accent);
  font-size: 7pt;
  font-weight: 700;
}
table.heatmap th.total-head {
  width: 22px;
  background: var(--accent-soft);
  color: var(--accent);
  font-size: 7pt;
}
.empty-hint {
  color: var(--text-muted);
  font-size: 11pt;
  font-style: italic;
  padding: 8px 0;
}

/* ── 错因分类图例 ── */
.legend-grid {
  display: grid;
  grid-template-columns: repeat(3, 1fr);
  gap: 8px;
}
.legend-item {
  background: var(--surface);
  border: 1px solid var(--border);
  border-radius: 8px;
  padding: 8px 10px;
  display: flex;
  align-items: center;
  gap: 8px;
  font-size: 10pt;
}
.legend-item .swatch {
  width: 14px;
  height: 14px;
  border-radius: 3px;
  flex-shrink: 0;
}
.legend-item .legend-label { flex: 1; }
.legend-item .legend-count { color: var(--text-muted); font-size: 9pt; }
.legend-item .legend-pct {
  color: var(--accent);
  font-size: 9pt;
  font-weight: 600;
  margin-left: 4px;
}

/* ── 简要说明 ── */
.note {
  margin-top: 6mm;
  padding: 8px 12px;
  background: var(--surface);
  border-left: 3px solid var(--accent);
  border-radius: 4px;
  font-size: 10pt;
  color: var(--text-muted);
  line-height: 1.7;
}
.note strong { color: var(--text); }

@media print {
  .page { max-width: none; }
  .section { break-inside: avoid; }
  .heatmap-wrap { overflow: visible; }
}
''';
}

// ─────────────────────────────────────────────────────────────────────────
// 各 Section 生成
// ─────────────────────────────────────────────────────────────────────────

String _buildHeader(MistakeTrendData data, String? studentName) {
  final buf = StringBuffer();
  buf.writeln('  <header class="header">');
  buf.writeln('    <h1>错因趋势热力图</h1>');
  final generatedStr = _formatDateTime(data.generatedAt);
  final rangeStr =
      '${_formatDate(data.startDate)} 至 ${_formatDate(data.endDate)}';
  buf.writeln('    <div class="meta">');
  buf.write('      <span>生成时间：${_escapeHtml(generatedStr)}</span>');
  buf.write('      <span class="sep">|</span>');
  buf.write('      <span>统计范围：${_escapeHtml(rangeStr)}</span>');
  if (studentName != null && studentName.isNotEmpty) {
    buf.write(
        '      <span class="sep">|</span><span>姓名：<span class="student-name">${_escapeHtml(studentName)}</span></span>');
  }
  buf.writeln('    </div>');
  buf.writeln('  </header>');
  return buf.toString();
}

String _buildOverviewCards(MistakeTrendData data) {
  final buf = StringBuffer();
  buf.writeln('  <section class="section">');
  buf.writeln('    <h2>概览</h2>');
  buf.writeln('    <div class="stats-grid">');
  // 总题数
  buf.writeln('      <div class="stat-card">');
  buf.writeln(
      '        <div class="stat-value">${data.grandTotal}</div>');
  buf.writeln('        <div class="stat-label">总题数</div>');
  buf.writeln('      </div>');
  // 活跃错因分类数
  buf.writeln('      <div class="stat-card">');
  buf.writeln(
      '        <div class="stat-value">${data.categories.length}</div>');
  buf.writeln('        <div class="stat-label">活跃错因分类数</div>');
  buf.writeln('      </div>');
  // 最热错因
  final hottest = _hottestCategory(data);
  final hottestLabel = hottest == null
      ? '—'
      : '${_escapeHtml(hottest.$1.label)} (${hottest.$2})';
  buf.writeln('      <div class="stat-card">');
  buf.writeln(
      '        <div class="stat-value" style="font-size:13pt;">$hottestLabel</div>');
  buf.writeln('        <div class="stat-label">最热错因</div>');
  buf.writeln('      </div>');
  // 日均题数
  final dailyAvg = data.dates.isEmpty
      ? 0.0
      : data.grandTotal / data.dates.length;
  buf.writeln('      <div class="stat-card">');
  buf.writeln(
      '        <div class="stat-value">${dailyAvg.toStringAsFixed(1)}</div>');
  buf.writeln('        <div class="stat-label">日均题数</div>');
  buf.writeln('      </div>');
  buf.writeln('    </div>');
  buf.writeln('  </section>');
  return buf.toString();
}

(MistakeCategory, int)? _hottestCategory(MistakeTrendData data) {
  if (data.categories.isEmpty) return null;
  var bestIdx = 0;
  var bestCount = data.categoryTotals[0];
  for (var i = 1; i < data.categories.length; i++) {
    if (data.categoryTotals[i] > bestCount) {
      bestCount = data.categoryTotals[i];
      bestIdx = i;
    }
  }
  if (bestCount == 0) return null;
  return (data.categories[bestIdx], bestCount);
}

String _buildHeatmapSection(MistakeTrendData data) {
  final buf = StringBuffer();
  buf.writeln('  <section class="section">');
  buf.writeln('    <h2>错因 × 日期 热力图</h2>');
  if (data.categories.isEmpty || data.grandTotal == 0) {
    buf.writeln(
        '    <div class="empty-hint">最近 ${data.dates.length} 天暂无错因分类数据</div>');
    buf.writeln('  </section>');
    return buf.toString();
  }
  buf.writeln('    <div class="heatmap-wrap">');
  buf.writeln('      <table class="heatmap">');

  // 表头：第一列空 + 30 个日期 + 总数列
  final maxCount = _maxCellCount(data);
  buf.writeln('        <thead><tr>');
  buf.writeln('          <th class="corner">错因 \\ 日期</th>');
  for (var i = 0; i < data.dates.length; i++) {
    // 每 5 天显示一次（i=0,5,10,...,25），其余空白。
    final showLabel = i % 5 == 0;
    final label = showLabel ? _formatShortDate(data.dates[i]) : '';
    buf.writeln('          <th class="day-head">$label</th>');
  }
  buf.writeln('          <th class="total-head">合计</th>');
  buf.writeln('        </tr></thead>');

  // 表体：每个分类一行
  buf.writeln('        <tbody>');
  for (var c = 0; c < data.categories.length; c++) {
    final cat = data.categories[c];
    final color = _mistakeCategoryHex(cat);
    buf.writeln('          <tr>');
    buf.writeln(
        '            <td class="cat-label"><span class="swatch" style="background:$color"></span>${_escapeHtml(cat.label)}</td>');
    for (var d = 0; d < data.dates.length; d++) {
      final count = data.matrix[d][c];
      final opacity = _cellOpacity(count, maxCount);
      final bg = 'rgba(99, 102, 241, $opacity)';
      final dateStr = _formatDate(data.dates[d]);
      final title = '$dateStr: $count 题';
      final cls = count > 0 ? 'cell has-count' : 'cell';
      final value = count > 0 ? '$count' : '';
      buf.writeln(
          '            <td class="$cls" title="${_escapeHtml(title)}" style="background:$bg">$value</td>');
    }
    buf.writeln(
        '            <td class="total-cell">${data.categoryTotals[c]}</td>');
    buf.writeln('          </tr>');
  }
  // 表尾汇总行：每天总数
  buf.writeln('          <tr>');
  buf.writeln('            <td class="cat-label">每日合计</td>');
  for (var d = 0; d < data.dates.length; d++) {
    final total = data.dailyTotals[d];
    final opacity = _cellOpacity(total, maxCount);
    final bg = 'rgba(99, 102, 241, $opacity)';
    final dateStr = _formatDate(data.dates[d]);
    final title = '$dateStr: $total 题';
    final cls = total > 0 ? 'cell has-count' : 'cell';
    final value = total > 0 ? '$total' : '';
    buf.writeln(
        '            <td class="$cls" title="${_escapeHtml(title)}" style="background:$bg">$value</td>');
  }
  buf.writeln(
      '            <td class="total-cell">${data.grandTotal}</td>');
  buf.writeln('          </tr>');
  buf.writeln('        </tbody>');

  buf.writeln('      </table>');
  buf.writeln('    </div>');
  buf.writeln('  </section>');
  return buf.toString();
}

String _buildLegendSection(MistakeTrendData data) {
  final buf = StringBuffer();
  buf.writeln('  <section class="section">');
  buf.writeln('    <h2>错因分类图例</h2>');
  if (data.categories.isEmpty) {
    buf.writeln(
        '    <div class="empty-hint">最近 ${data.dates.length} 天暂无错因分类数据</div>');
    buf.writeln('  </section>');
    return buf.toString();
  }
  buf.writeln('    <div class="legend-grid">');
  for (var i = 0; i < data.categories.length; i++) {
    final cat = data.categories[i];
    final count = data.categoryTotals[i];
    final pct = data.grandTotal == 0
        ? 0
        : (count * 100 / data.grandTotal).round();
    final color = _mistakeCategoryHex(cat);
    buf.writeln('      <div class="legend-item">');
    buf.writeln(
        '        <span class="swatch" style="background:$color"></span>');
    buf.writeln(
        '        <span class="legend-label">${_escapeHtml(cat.label)}</span>');
    buf.writeln(
        '        <span class="legend-count">${count} 题</span>');
    buf.writeln('        <span class="legend-pct">$pct%</span>');
    buf.writeln('      </div>');
  }
  buf.writeln('    </div>');
  buf.writeln('  </section>');
  return buf.toString();
}

String _buildNoteSection() {
  final buf = StringBuffer();
  buf.writeln('  <section class="note">');
  buf.writeln(
      '    <strong>说明：</strong>颜色越深表示当天该错因的题目数量越多；行表示错因分类，列表示日期。');
  buf.writeln(
      '悬停单元格可查看具体日期与题数。每个分类的色块仅用于区分错因类型，热力图色阶统一为靛蓝色（与「最热错因」无关）。');
  buf.writeln('  </section>');
  return buf.toString();
}

// ─────────────────────────────────────────────────────────────────────────
// 工具
// ─────────────────────────────────────────────────────────────────────────

String _escapeHtml(String input) => HtmlRenderUtils.escapeHtml(input);

String _formatDate(DateTime dt) {
  final y = dt.year.toString();
  final m = dt.month.toString().padLeft(2, '0');
  final d = dt.day.toString().padLeft(2, '0');
  return '$y-$m-$d';
}

String _formatShortDate(DateTime dt) {
  final m = dt.month.toString().padLeft(2, '0');
  final d = dt.day.toString().padLeft(2, '0');
  return '$m-$d';
}

String _formatDateTime(DateTime dt) {
  final y = dt.year.toString();
  final m = dt.month.toString().padLeft(2, '0');
  final d = dt.day.toString().padLeft(2, '0');
  final hh = dt.hour.toString().padLeft(2, '0');
  final mm = dt.minute.toString().padLeft(2, '0');
  return '$y-$m-$d $hh:$mm';
}

/// 计算矩阵中的最大值（用于色阶归一化）。
int _maxCellCount(MistakeTrendData data) {
  var maxCount = 0;
  for (var d = 0; d < data.dates.length; d++) {
    if (data.dailyTotals[d] > maxCount) {
      maxCount = data.dailyTotals[d];
    }
    for (var c = 0; c < data.categories.length; c++) {
      if (data.matrix[d][c] > maxCount) {
        maxCount = data.matrix[d][c];
      }
    }
  }
  return maxCount;
}

/// 计算单元格不透明度：count == 0 → 0.04；否则 0.15 + count/maxCount*0.85（上限 1.0）。
double _cellOpacity(int count, int maxCount) {
  if (count == 0) return 0.04;
  if (maxCount <= 0) return 0.04;
  final raw = 0.15 + (count / maxCount) * 0.85;
  if (raw > 1.0) return 1.0;
  if (raw < 0.04) return 0.04;
  return raw;
}

/// 错因分类固定配色（与 home_screen.dart 的 _mistakeCategoryColor 一致意图；
/// 在 HTML 报告中使用更易区分的 6 色调色板）。
String _mistakeCategoryHex(MistakeCategory category) {
  switch (category) {
    case MistakeCategory.concept:
      return '#6366F1'; // indigo
    case MistakeCategory.comprehension:
      return '#0EA5E9'; // sky
    case MistakeCategory.calculation:
      return '#F59E0B'; // amber
    case MistakeCategory.strategy:
      return '#EC4899'; // pink
    case MistakeCategory.format:
      return '#10B981'; // emerald
    case MistakeCategory.careless:
      return '#EF4444'; // red
  }
}
