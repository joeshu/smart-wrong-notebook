import 'dart:io';

import 'package:smart_wrong_notebook/src/data/files/image_fingerprint.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';

/// 错题去重检测结果：表示一道已有题与候选题的相似程度。
class DuplicateMatch {
  const DuplicateMatch({
    required this.existingQuestion,
    required this.textSimilarity,
    required this.imageSimilarity,
    required this.overallScore,
  });

  /// 命中的已有题目。
  final QuestionRecord existingQuestion;

  /// 文本相似度，0.0-1.0。
  final double textSimilarity;

  /// 图片相似度，0.0-1.0。
  /// 精确 SHA-256 命中时为 1.0，否则使用感知哈希计算近似度。
  final double? imageSimilarity;

  /// 加权得分：textSimilarity * 0.7 + imageSimilarity * 0.3。
  /// 若 [imageSimilarity] 为 null，则退化为 [textSimilarity]。
  final double overallScore;

  @override
  String toString() =>
      'DuplicateMatch(id=${existingQuestion.id}, text=$textSimilarity, '
      'image=$imageSimilarity, overall=$overallScore)';
}

/// 错题去重检测器。
///
/// 在保存草稿前对候选题与已有题做相似度比对：
/// - 文本：归一化（去标点 / 小写 / 全角半角统一 / 多空格压缩）后用
///   字符 3-gram + Jaccard 系数；若两段文本都 < 5 字符则用归一化编辑距离。
/// - 图片：复用 [ImageFingerprintCodec] 的 SHA-256 指纹，仅在两边都有
///   imagePath 时尝试比对，命中时 imageSimilarity = 1.0。
class DuplicateDetector {
  const DuplicateDetector();

  /// 检测候选题与已有题列表中的相似项。
  ///
  /// - [candidate] 当前正在确认保存的题目。
  /// - [existing] 已存在的题目列表。
  /// - [threshold] 返回的总体相似度下限，默认 0.6。
  ///
  /// 返回结果按 [DuplicateMatch.overallScore] 降序排列，最多 10 条。
  Future<List<DuplicateMatch>> detectDuplicates(
    QuestionRecord candidate,
    List<QuestionRecord> existing, {
    double threshold = 0.6,
  }) async {
    final matches = <DuplicateMatch>[];

    // 候选题图片指纹的惰性缓存：仅在有需要时计算一次。
    String? candidateFingerprint;
    var candidateFingerprintResolved = false;

    for (final item in existing) {
      // 跳过候选题自身（id 相同）。
      if (item.id == candidate.id) continue;

      final textSim = _maxTextSimilarity(candidate, item);

      // 仅当两边都有 imagePath、且图片命中后总分有可能达到阈值时，
      // 才尝试比对图片指纹；避免为注定无法达标的对计算 SHA-256。
      double? imageSim;
      final bestPossibleOverall = textSim * 0.7 + 0.3;
      final bothHaveImage =
          candidate.imagePath.isNotEmpty && item.imagePath.isNotEmpty;
      if (bothHaveImage &&
          (bestPossibleOverall >= threshold || textSim <= 0)) {
        if (!candidateFingerprintResolved) {
          candidateFingerprint = await _resolveFingerprint(candidate);
          candidateFingerprintResolved = true;
        }
        final existingFingerprint = await _resolveFingerprint(item);
        if (candidateFingerprint != null &&
            existingFingerprint != null &&
            candidateFingerprint == existingFingerprint) {
          imageSim = 1.0;
        } else {
          final candidatePerceptual =
              await _resolvePerceptualFingerprint(candidate);
          final existingPerceptual =
              await _resolvePerceptualFingerprint(item);
          if (candidatePerceptual != null && existingPerceptual != null) {
            imageSim = ImageFingerprintCodec.perceptualSimilarity(
              candidatePerceptual,
              existingPerceptual,
            );
          }
        }
      }

      final overall = _computeOverall(textSim, imageSim);
      if (overall >= threshold) {
        matches.add(DuplicateMatch(
          existingQuestion: item,
          textSimilarity: textSim,
          imageSimilarity: imageSim,
          overallScore: overall,
        ));
      }
    }

    matches.sort((a, b) => b.overallScore.compareTo(a.overallScore));
    if (matches.length > 10) {
      return matches.sublist(0, 10);
    }
    return matches;
  }

  /// 计算候选题与已有题在三个文本字段上的最大相似度。
  double _maxTextSimilarity(QuestionRecord candidate, QuestionRecord existing) {
    final correctedSim = _textSimilarity(
      candidate.correctedText,
      existing.correctedText,
    );
    final normalizedSim = _textSimilarity(
      candidate.normalizedQuestionText,
      existing.normalizedQuestionText,
    );
    final extractedSim = _textSimilarity(
      candidate.extractedQuestionText,
      existing.extractedQuestionText,
    );
    var max = correctedSim;
    if (normalizedSim > max) max = normalizedSim;
    if (extractedSim > max) max = extractedSim;
    return max;
  }

  /// 文本相似度：归一化 + 字符 3-gram Jaccard；短文本回退到归一化编辑距离。
  double _textSimilarity(String a, String b) {
    final na = _normalizeText(a);
    final nb = _normalizeText(b);
    if (na.isEmpty && nb.isEmpty) return 1.0;
    if (na.isEmpty || nb.isEmpty) return 0.0;

    if (na.length < 5 && nb.length < 5) {
      return _normalizedLevenshtein(na, nb);
    }
    return _ngramJaccard(na, nb, 3);
  }

  /// 文本归一化：小写、全角转半角、去标点、压缩空白。
  String _normalizeText(String input) {
    if (input.isEmpty) return '';
    final buffer = StringBuffer();
    for (final char in input.runes) {
      var c = char;
      // 全角空格 -> 半角空格
      if (c == 0x3000) {
        c = 0x20;
      } else if (c >= 0xFF01 && c <= 0xFF5E) {
        // 全角 ASCII (！～) -> 半角 ASCII
        c = c - 0xFEE0;
      }
      // ASCII 大写转小写
      if (c >= 0x41 && c <= 0x5A) {
        c = c + 0x20;
      }
      // 跳过标点
      if (_isPunctuation(c)) continue;
      buffer.writeCharCode(c);
    }
    return buffer.toString().replaceAll(RegExp(r'\s+'), ' ').trim();
  }

  bool _isPunctuation(int c) {
    // ASCII 标点区间
    if (c >= 0x21 && c <= 0x2F) return true;
    if (c >= 0x3A && c <= 0x40) return true;
    if (c >= 0x5B && c <= 0x60) return true;
    if (c >= 0x7B && c <= 0x7E) return true;
    // 常见 CJK 标点
    switch (c) {
      case 0x3001: // 、
      case 0x3002: // 。
      case 0x3008: // 〈
      case 0x3009: // 〉
      case 0x300A: // 《
      case 0x300B: // 》
      case 0x300C: // 「
      case 0x300D: // 」
      case 0x300E: // 『
      case 0x300F: // 』
      case 0x3010: // 【
      case 0x3011: // 】
      case 0x3014: // 〔
      case 0x3015: // 〕
      case 0x2018: // '
      case 0x2019: // '
      case 0x201C: // "
      case 0x201D: // "
      case 0x2026: // …
      case 0x2014: // —
        return true;
    }
    return false;
  }

  /// 字符 n-gram Jaccard 系数。
  double _ngramJaccard(String a, String b, int n) {
    if (a.length < n && b.length < n) {
      return a == b ? 1.0 : 0.0;
    }
    final setA = <String>{};
    for (int i = 0; i <= a.length - n; i++) {
      setA.add(a.substring(i, i + n));
    }
    final setB = <String>{};
    for (int i = 0; i <= b.length - n; i++) {
      setB.add(b.substring(i, i + n));
    }
    if (setA.isEmpty && setB.isEmpty) {
      return a == b ? 1.0 : 0.0;
    }
    final intersection = setA.intersection(setB).length;
    final union = setA.union(setB).length;
    return union == 0 ? 0.0 : intersection / union;
  }

  /// 归一化编辑距离相似度：1 - distance / maxLen。
  double _normalizedLevenshtein(String a, String b) {
    if (a == b) return 1.0;
    if (a.isEmpty || b.isEmpty) return 0.0;
    final distance = _levenshtein(a, b);
    final maxLen = a.length > b.length ? a.length : b.length;
    return maxLen == 0 ? 1.0 : 1.0 - distance / maxLen;
  }

  int _levenshtein(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;

    final aRunes = a.runes.toList(growable: false);
    final bRunes = b.runes.toList(growable: false);
    final m = aRunes.length;
    final n = bRunes.length;

    // 用两行数组滚动计算，节省内存。
    var prev = List<int>.generate(n + 1, (j) => j);
    var curr = List<int>.filled(n + 1, 0);

    for (var i = 1; i <= m; i++) {
      curr[0] = i;
      for (var j = 1; j <= n; j++) {
        final cost = aRunes[i - 1] == bRunes[j - 1] ? 0 : 1;
        final del = prev[j] + 1;
        final ins = curr[j - 1] + 1;
        final sub = prev[j - 1] + cost;
        curr[j] = del < ins ? (del < sub ? del : sub) : (ins < sub ? ins : sub);
      }
      final tmp = prev;
      prev = curr;
      curr = tmp;
    }
    return prev[n];
  }

  /// 加权总体相似度。
  double _computeOverall(double textSim, double? imageSim) {
    if (imageSim == null) return textSim;
    if (textSim <= 0) return imageSim;
    return textSim * 0.7 + imageSim * 0.3;
  }

  /// 解析题目的图片指纹：先从 tags 读取，缺失则即时从文件计算。
  Future<String?> _resolveFingerprint(QuestionRecord record) async {
    final fromTags = ImageFingerprintCodec.read(record.tags);
    if (fromTags != null && fromTags.isNotEmpty) return fromTags;

    final path = record.imagePath;
    if (path.isEmpty) return null;
    final file = File(path);
    if (!file.existsSync()) return null;
    try {
      return await ImageFingerprintCodec.fromFile(file);
    } catch (_) {
      return null;
    }
  }

  Future<String?> _resolvePerceptualFingerprint(
    QuestionRecord record,
  ) async {
    final fromTags = ImageFingerprintCodec.readPerceptual(record.tags);
    if (fromTags != null && fromTags.isNotEmpty) return fromTags;
    final path = record.imagePath;
    if (path.isEmpty) return null;
    final file = File(path);
    if (!file.existsSync()) return null;
    try {
      return await ImageFingerprintCodec.perceptualFromFile(file);
    } catch (_) {
      return null;
    }
  }
}

/// 顶层便捷实例，方便调用方直接使用。
const DuplicateDetector duplicateDetector = DuplicateDetector();
