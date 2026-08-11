/// 题号识别器：支持多种题号格式，统一返回阿拉伯数字字符串。
///
/// 支持格式：
/// - `1.` `1、` `1:：` `1）` `1)` `（1）` `(1)` `1．`  (阿拉伯数字 + 分隔符)
/// - `第1题` `第 1 题` `第1章` (中文"第"前缀 + 阿拉伯数字 + 章节后缀)
/// - `题1` `题 1` ("题"前缀)
/// - `Q1` `Question 1` `q1` (英文前缀)
/// - `一、` `二、` `三、` `十、` `二十、` `三十、` (中文数字，转换为阿拉伯数字)
/// - `I.` `II.` `III.` `IV.` (罗马数字，转换为阿拉伯数字)
class QuestionNumberDetector {
  const QuestionNumberDetector._();

  static const QuestionNumberDetector instance = QuestionNumberDetector._();

  /// 主匹配正则：覆盖阿拉伯数字 + 中文/英文前缀
  ///
  /// 分组顺序（extractNumber 按此顺序判断）：
  /// 1. 阿拉伯数字 + 分隔符（含 `第1题` 这种"第+数字+章节后缀"形式）
  /// 2. `（1）` `(1)` 括号包裹的阿拉伯数字
  /// 3. `题1` "题"前缀 + 数字
  /// 4. `Q1` `Question 1` 英文前缀 + 数字
  /// 5. `第` 字面量（用于"第一题"分支）
  /// 6. 中文数字（用于"第一题"分支）
  /// 7. 中文数字（用于"一、"分支，支持多位"二十"）
  /// 8. 罗马数字
  static final RegExp questionStart = RegExp(
    r'^\s*(?:'
    r'(?:第\s*)?(\d{1,3})\s*(?:题|章|节|部分|[\.．、:：]|[（）()])'
    r'|[（(]\s*(\d{1,3})\s*[）)]'
    r'|(?:题\s*)(\d{1,3})\b'
    r'|(?:Q|Question|q|question)\s*(\d{1,3})\b'
    r'|(第)\s*([一二三四五六七八九十百]+)\s*(?:题|章|节|部分)?'
    r'|([一二三四五六七八九十百]+)\s*[、\.．]'
    r'|([IVXLCDM]+)\s*[\.．]'
    r')',
  );

  /// 从匹配结果中提取统一格式的题号（阿拉伯数字字符串）
  /// 匹配失败返回 null
  String? extractNumber(String text) {
    final match = questionStart.firstMatch(text);
    if (match == null) return null;
    // 按分组顺序判断格式
    if (match.group(1) != null) return match.group(1); // 阿拉伯数字 + 分隔符
    if (match.group(2) != null) return match.group(2); // （1）
    if (match.group(3) != null) return match.group(3); // 题1
    if (match.group(4) != null) return match.group(4); // Q1
    if (match.group(6) != null) return _chineseToArabic(match.group(6)!); // 第X题
    if (match.group(7) != null) return _chineseToArabic(match.group(7)!); // 一、
    if (match.group(8) != null) return _romanToArabic(match.group(8)!); // I.
    return null;
  }

  /// 判断文本是否以题号开头
  bool hasQuestionNumber(String text) => questionStart.hasMatch(text);

  /// 中文数字转阿拉伯数字（支持 1-100）
  static String _chineseToArabic(String chinese) {
    const digits = <String, int>{
      '一': 1, '二': 2, '三': 3, '四': 4, '五': 5,
      '六': 6, '七': 7, '八': 8, '九': 9, '零': 0,
    };
    const tens = <String, int>{'十': 10, '百': 100};

    if (chinese == '十') return '10';

    int result = 0;
    int current = 0;
    for (final char in chinese.runes) {
      final c = String.fromCharCode(char);
      if (digits.containsKey(c)) {
        current = digits[c]!;
      } else if (tens.containsKey(c)) {
        if (current == 0) current = 1;
        result += current * tens[c]!;
        current = 0;
      }
    }
    result += current;
    return result.toString();
  }

  /// 罗马数字转阿拉伯数字（支持 1-3999）
  static String _romanToArabic(String roman) {
    const values = <String, int>{
      'I': 1, 'V': 5, 'X': 10, 'L': 50,
      'C': 100, 'D': 500, 'M': 1000,
    };
    int result = 0;
    int prev = 0;
    for (final c in roman.split('').reversed) {
      final v = values[c.toUpperCase()] ?? 0;
      if (v < prev) {
        result -= v;
      } else {
        result += v;
      }
      prev = v;
    }
    return result.toString();
  }
}
