import 'package:flutter_test/flutter_test.dart';
import 'package:smart_wrong_notebook/src/shared/utils/latex_normalizer.dart';

void main() {
  group('LatexNormalizer.normalize', () {
    test('把 \\(x\\) 转换为 \$x\$', () {
      expect(LatexNormalizer.normalize(r'\(x\)'), r'$x$');
    });

    test('把 \\[x\\] 转换为 \$\$x\$\$', () {
      expect(LatexNormalizer.normalize(r'\[x\]'), r'$$x$$');
    });

    test('去除 \\( ... \\) 命令前后多余空白', () {
      expect(LatexNormalizer.normalize(r'\( x \)'), r'$x$');
      expect(LatexNormalizer.normalize(r'\(  x^2  \)'), r'$x^2$');
    });

    test('去除 \\[ ... \\] 命令前后多余空白', () {
      expect(LatexNormalizer.normalize(r'\[ x \]'), r'$$x$$');
      expect(LatexNormalizer.normalize(r'\[  a+b  \]'), r'$$a+b$$');
    });

    test('同时转换行内和块级定界符', () {
      final input = r'前缀 \(a\) 中间 \[b\] 后缀';
      final result = LatexNormalizer.normalize(input);
      expect(result, contains(r'$a$'));
      expect(result, contains(r'$$b$$'));
      // 前后缀文本保留不变。
      expect(result, startsWith('前缀 '));
      expect(result, endsWith(' 后缀'));
    });

    test('嵌套定界符：begin/end 环境标记保持不变', () {
      // begin/end 不在 normalize 的转换范围内，应保留原样。
      const input = r'\begin{equation}x^2 + y^2 = z^2\end{equation}';
      expect(LatexNormalizer.normalize(input), input);
    });

    test('嵌套定界符：\\(...\\) 内部包含 \\[...\\] 时先转换外层再尝试内层', () {
      // 外层 \( ... \) 优先被替换为 $ ... $，内层 \[ ... \] 仍可被第二条规则转换。
      // 这是 normalize 当前的顺序行为，避免外层被错误吞掉。
      final result = LatexNormalizer.normalize(r'\(\[x\]\)');
      expect(result, contains(r'$'));
      // 外层定界符已被替换为 $...$。
      expect(result, isNot(contains(r'\(')));
      expect(result, isNot(contains(r'\)')));
    });

    test('空字符串返回空字符串', () {
      expect(LatexNormalizer.normalize(''), '');
    });

    test('纯文本（无 LaTeX 定界符）保持不变', () {
      const input = '今天天气真好';
      expect(LatexNormalizer.normalize(input), input);
    });

    test('无配对定界符的孤立 \\( 不被替换', () {
      const input = r'只有 \( 没有闭合';
      expect(LatexNormalizer.normalize(input), input);
    });
  });

  group('LatexNormalizer.hasFormula', () {
    test('\$x\$ 被识别为公式', () {
      expect(LatexNormalizer.hasFormula(r'$x$'), isTrue);
    });

    test('\$\$x\$\$ 被识别为公式', () {
      expect(LatexNormalizer.hasFormula(r'$$x$$'), isTrue);
    });

    test('\\frac{1}{2} 被识别为公式', () {
      expect(LatexNormalizer.hasFormula(r'\frac{1}{2}'), isTrue);
    });

    test('数学符号 ∑ 被识别为公式', () {
      expect(LatexNormalizer.hasFormula('∑ x'), isTrue);
    });

    test('其它数学符号同样被识别', () {
      expect(LatexNormalizer.hasFormula('√2'), isTrue);
      expect(LatexNormalizer.hasFormula('a ≠ b'), isTrue);
      expect(LatexNormalizer.hasFormula('x ≤ 3'), isTrue);
      expect(LatexNormalizer.hasFormula('α + β'), isTrue);
      expect(LatexNormalizer.hasFormula('x → ∞'), isTrue);
    });

    test('纯文本不被识别为公式', () {
      expect(LatexNormalizer.hasFormula('今天天气真好'), isFalse);
      expect(LatexNormalizer.hasFormula('hello world'), isFalse);
      expect(LatexNormalizer.hasFormula('1 + 1 = 2'), isFalse);
    });

    test('空字符串不被识别为公式', () {
      expect(LatexNormalizer.hasFormula(''), isFalse);
    });

    test('\\begin{equation} 被识别为公式', () {
      expect(LatexNormalizer.hasFormula(r'\begin{equation}'), isTrue);
    });
  });
}
