/// 统一 PaddleOCR/MinerU 返回的原始 LaTeX 定界符到 $...$ / $$...$$ 格式。
///
/// 处理：
/// - \(...\) → $...$
/// - \[...\] → $$...$$
/// - \begin{...}...\end{...} 保持原样
/// - 去除 LaTeX 命令前后多余空白
class LatexNormalizer {
  const LatexNormalizer._();

  static String normalize(String input) {
    if (input.isEmpty) return input;
    var result = input;
    // \( ... \) → $ ... $
    result = result.replaceAllMapped(
      RegExp(r'\\\(\s*([\s\S]*?)\s*\\\)'),
      (m) => '\$${m.group(1)}\$',
    );
    // \[ ... \] → $$ ... $$
    result = result.replaceAllMapped(
      RegExp(r'\\\[\s*([\s\S]*?)\s*\\\]'),
      (m) => '\$\$${m.group(1)}\$\$',
    );
    return result;
  }

  /// 判断文本是否包含 LaTeX 公式
  static bool hasFormula(String text) {
    if (text.contains(r'$')) return true;
    if (text.contains(r'\\')) return true;
    // 常见 LaTeX 命令前缀
    if (RegExp(
      r'\\(frac|sqrt|sum|int|begin|alpha|beta|gamma|delta|theta|pi|infty|partial|nabla|cdot|times|pm|mp|leq|geq|neq|approx|equiv|subset|supset|in|notin|forall|exists|rightarrow|leftarrow|Rightarrow|Leftarrow|mapsto)\b',
    ).hasMatch(text)) {
      return true;
    }
    // 数学符号
    if (RegExp(r'[∑√∫≠≤≥≈≡⊆⊇∈∉∀∃→←⇒⇐↦αβγδθπ∞∂∇·×±∓]').hasMatch(text)) {
      return true;
    }
    return false;
  }

  /// 把字面量 `\n`（反斜杠+n 两字符）转为真正的换行符。
  ///
  /// AI 在 JSON 字符串中常输出字面量 `\n` 表示换行（提示词要求"换行写成
  /// \\n"），但 JSON 修复逻辑为保护 LaTeX 命令会把 `\n`+字母 转义为字面量
  /// `\n`。`\nA`/`\nB`/`\nC`/`\nD`（选项字母）并非 LaTeX 命令，应转为换行。
  ///
  /// 用负向先行断言 `\\n(?![aeglLmrRstu])` 仅排除真正以 `\n` 开头的 LaTeX
  /// 命令首字母：
  /// - a: nabla
  /// - e: ne / neg / neq / nexists / newline
  /// - g: ngeq / ngtr
  /// - l: nleq / nless / nleft...
  /// - L: nLeft...
  /// - m: nmid
  /// - r: nrightarrow
  /// - R: nRightarrow
  /// - s: nsupseteq / nsq...
  /// - t: ntriangle...
  /// - u: nu
  ///
  /// 其余 `\n`+字符 视为换行。供导出服务（HTML/Anki/Markdown/CSV/JSON）
  /// 和 AI 分析统一复用，避免选项 ABCD 前出现字面量 `\n`。
  static String normalizeLiteralNewlines(String input) {
    if (input.isEmpty) return input;
    return input.replaceAllMapped(
      RegExp(r'\\n(?![aeglLmrRstu])'),
      (_) => '\n',
    );
  }
}
