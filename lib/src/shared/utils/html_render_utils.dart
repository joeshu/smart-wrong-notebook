import 'package:intl/intl.dart';
import 'package:smart_wrong_notebook/src/domain/models/content_status.dart';
import 'package:smart_wrong_notebook/src/domain/models/mastery_level.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';
import 'package:smart_wrong_notebook/src/shared/utils/latex_normalizer.dart';

/// HTML 报告渲染工具：被 [HtmlExportService] 与各 [ExportTemplate] 共享。
///
/// 抽出到独立文件避免循环依赖（templates → utils ← service）。
class HtmlRenderUtils {
  HtmlRenderUtils._();

  /// 转义 HTML 特殊字符（& < > " '）。
  static String escapeHtml(String input) {
    return input
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('"', '&quot;')
        .replaceAll("'", '&#39;');
  }

  /// 学科主题色（来自 [Subject.color]）转 `#rrggbb` 字符串。
  static String subjectColorHex(Subject subject) {
    final c = subject.color;
    final r = (c.r * 255).round().toRadixString(16).padLeft(2, '0');
    final g = (c.g * 255).round().toRadixString(16).padLeft(2, '0');
    final b = (c.b * 255).round().toRadixString(16).padLeft(2, '0');
    return '#$r$g$b';
  }

  /// 掌握程度中文标签。
  static String masteryLabel(MasteryLevel level) => switch (level) {
        MasteryLevel.newQuestion => '待学习',
        MasteryLevel.reviewing => '复习中',
        MasteryLevel.mastered => '已掌握',
      };

  /// 掌握程度对应的 CSS badge class。
  static String masteryBadgeClass(MasteryLevel level) => switch (level) {
        MasteryLevel.newQuestion => 'badge-new',
        MasteryLevel.reviewing => 'badge-reviewing',
        MasteryLevel.mastered => 'badge-mastered',
      };

  /// 题目内容状态中文标签。
  static String statusLabel(ContentStatus status) => switch (status) {
        ContentStatus.processing => '处理中',
        ContentStatus.analyzing => '分析中',
        ContentStatus.needsConfirmation => '待人工确认',
        ContentStatus.ready => '已完成',
        ContentStatus.failed => '识别失败',
        ContentStatus.analysisFailed => '分析失败',
      };

  /// 练习卷/订正卷答题留白高度，按题干长度自适应。
  static int practiceBlankHeight(String questionText) {
    if (questionText.isEmpty) return 80;
    final lines = (questionText.length / 40).ceil();
    final height = (lines + 3) * 28;
    return height.clamp(60, 220).toInt();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 文字 + LaTeX 混合转 HTML
  // ─────────────────────────────────────────────────────────────────────────

  /// 把包含 LaTeX 分隔符的文本转成 HTML：数学部分用 `<span class="math-...">`
  /// 包裹供 KaTeX 渲染，其余部分转义并保留换行。
  ///
  /// 入口先调用 [LatexNormalizer.normalizeLiteralNewlines] 把字面量 `\n`
  /// （反斜杠+n 两字符，AI 输出残留）转为真正换行符，避免选项 ABCD 前
  /// 出现字面量 `\n` 文本。覆盖 HTML/PDF/3 模板导出。
  static String mixedTextToHtml(String input) {
    final normalized = normalizeDelimiters(
        LatexNormalizer.normalizeLiteralNewlines(input));
    final spans = splitMathSpans(normalized);
    final buffer = StringBuffer();
    for (final span in spans) {
      if (span.isMath) {
        final cls = span.display ? 'math-display' : 'math-inline';
        buffer.write('<span class="$cls">${escapeHtml(span.text)}</span>');
      } else {
        final text = span.text
            .replaceAll('&', '&amp;')
            .replaceAll('<', '&lt;')
            .replaceAll('>', '&gt;')
            .replaceAll('\n', '<br>');
        buffer.write(text);
      }
    }
    return buffer.toString();
  }

  /// 把 `\(...\)`, `\[...\]` 归一化为 `$...$` 与 `$$...$$`。
  static String normalizeDelimiters(String v) {
    return v
        .replaceAllMapped(
          RegExp(r'\\\['),
          (_) => r'$$',
        )
        .replaceAllMapped(
          RegExp(r'\\\]'),
          (_) => r'$$',
        )
        .replaceAllMapped(
          RegExp(r'\\\('),
          (_) => r'$',
        )
        .replaceAllMapped(
          RegExp(r'\\\)'),
          (_) => r'$',
        );
  }

  /// 切分文本为数学 / 文本 span 序列：识别 `$$...$$` 与 `\begin{env}...\end{env}`
  /// 这两种 display 数学块，以及 `$...$` inline 数学。
  static List<MathSpan> splitMathSpans(String v) {
    final spans = <MathSpan>[];
    final displayOrEnv = RegExp(
      r'\$\$([\s\S]*?)\$\$|\\begin\{([A-Za-z]+\*?)\}([\s\S]*?)\\end\{\2\}',
    );
    var cursor = 0;
    for (final m in displayOrEnv.allMatches(v)) {
      if (m.start > cursor) {
        spans.addAll(splitInlineMath(v.substring(cursor, m.start)));
      }
      final math = m.group(1) ?? m.group(3)!;
      spans.add(MathSpan(math.trim(), isMath: true, display: true));
      cursor = m.end;
    }
    if (cursor < v.length) {
      spans.addAll(splitInlineMath(v.substring(cursor)));
    }
    return spans.where((s) => s.text.isNotEmpty).toList();
  }

  /// 切分 inline 数学 `$...$`，其余视作普通文本。
  static List<MathSpan> splitInlineMath(String v) {
    final spans = <MathSpan>[];
    final inlineRe = RegExp(r'\$([^\$]+)\$');
    var cursor = 0;
    for (final m in inlineRe.allMatches(v)) {
      if (m.start > cursor) {
        spans.add(MathSpan(v.substring(cursor, m.start), isMath: false));
      }
      spans.add(MathSpan(m.group(1)!.trim(), isMath: true));
      cursor = m.end;
    }
    if (cursor < v.length) {
      spans.add(MathSpan(v.substring(cursor), isMath: false));
    }
    return spans.where((s) => s.text.isNotEmpty).toList();
  }

  /// KaTeX 渲染脚本：遍历 `.math-inline` / `.math-display` 调用 `katex.render`。
  static String renderMathJs() {
    return '''
document.addEventListener('DOMContentLoaded', function() {
  function render(el, display) {
    try {
      katex.render(el.textContent, el, {
        throwOnError: false,
        strict: false,
        trust: true,
        displayMode: display
      });
    } catch(e) {}
  }
  document.querySelectorAll('.math-inline').forEach(function(el) { render(el, false); });
  document.querySelectorAll('.math-display').forEach(function(el) { render(el, true); });
});
''';
  }

  /// 题目创建时间的 MM/DD 短日期格式。
  static String shortDate(DateTime dt) => DateFormat('MM/dd').format(dt);

  /// 按学科分组并按学科名排序。
  static Map<Subject, List<QuestionRecord>> groupBySubject(
    List<QuestionRecord> questions,
  ) {
    final grouped = <Subject, List<QuestionRecord>>{};
    for (final q in questions) {
      grouped.putIfAbsent(q.subject, () => []).add(q);
    }
    return grouped;
  }

  /// 学科列表按 label 排序。
  static List<Subject> sortedSubjects(Map<Subject, List<QuestionRecord>> grouped) {
    final list = grouped.keys.toList()..sort((a, b) => a.label.compareTo(b.label));
    return list;
  }
}

/// 一段被切分出来的文本 / 数学 span。
class MathSpan {
  const MathSpan(this.text, {this.isMath = false, this.display = false});
  final String text;
  final bool isMath;
  final bool display;
}
