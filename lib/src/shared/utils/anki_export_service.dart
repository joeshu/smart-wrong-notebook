import 'dart:io';

import 'package:image/image.dart' as image;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/shared/utils/latex_normalizer.dart';

import 'export_content_options.dart';

/// 生成 Anki 导入用的 Tab 分隔文本（正面\t背面）。
///
/// 简化实现：不直接生成 .apkg（需要 sqlite3 + anki 协议太复杂），
/// 只生成 Tab 分隔的 .txt + 题图目录。
///
/// 使用流程：
/// 1. 调用 [generateAnkiImportText] 生成 txt 内容（同时把题图复制到
///    `<应用文档目录>/exports/anki_images/`）。
/// 2. 调用 [shareAnkiExport] 把 txt + 题图一起分享出去。
/// 3. 在 Anki 桌面端选择「文件 → 导入」，选择该 txt，分隔符选 Tab，
///    勾选「字段允许 HTML」。把题图复制到 collection.media 文件夹。
class AnkiExportService {
  /// 题图在 exports 目录下的子目录名。
  static const imageDirName = 'anki_images';

  /// 生成 Anki 导入文本，并把题图复制到 `<exports>/anki_images/`。
  ///
  /// [imageBaseDir] 为题图在 Anki media 文件夹下的相对前缀（如
  /// `wrong_notebook`），留空则图片直接放在 media 根目录。
  /// [knowledgeTreePaths] 为每题的知识点树路径列表（如 `['数学 > 代数 > 二次方程']`），
  /// 与 [contentOptions.includeKnowledgeTree] 联动，非空且开关打开时输出到背面。
  Future<String> generateAnkiImportText({
    required List<QuestionRecord> questions,
    required ExportContentOptions contentOptions,
    String? imageBaseDir,
    Map<String, List<String>>? knowledgeTreePaths,
  }) async {
    final exportDir = await _ensureExportDir();
    final imageDir = Directory('${exportDir.path}/$imageDirName');
    // 每次导出都重置图片目录，避免残留上次的题图。
    if (imageDir.existsSync()) {
      await imageDir.delete(recursive: true);
    }
    await imageDir.create(recursive: true);

    final buffer = StringBuffer();
    // 字段名头：正面\t背面\t学科\t知识点\t错因
    buffer.writeln('正面\t背面\t学科\t知识点\t错因');

    for (final q in questions) {
      final front = _buildFront(q, contentOptions, imageBaseDir, imageDir);
      final back = _buildBack(q, contentOptions, knowledgeTreePaths);
      final subject = _escapeField(q.subject.label);
      final analysis = q.analysisResult;
      final kps = [...?analysis?.knowledgePoints, ...?analysis?.aiTags]
          .where((s) => s.isNotEmpty)
          .join('、');
      final mistakeReason = _escapeField(analysis?.mistakeReason ?? '');
      buffer.writeln('$front\t$back\t$subject\t$kps\t$mistakeReason');
    }

    return buffer.toString();
  }

  /// 把 [content] 写入 .txt 文件，连同 `anki_images/` 下的题图一起分享。
  Future<void> shareAnkiExport(String content, String fileName) async {
    final exportDir = await _ensureExportDir();
    final txtFile = File('${exportDir.path}/$fileName');
    await txtFile.writeAsString(content, flush: true);

    final files = <XFile>[XFile(txtFile.path)];
    final imageDir = Directory('${exportDir.path}/$imageDirName');
    if (imageDir.existsSync()) {
      for (final entity in imageDir.listSync()) {
        if (entity is File) {
          files.add(XFile(entity.path));
        }
      }
    }
    await Share.shareXFiles(files);
  }

  // ─────────────────────────────────────────────────────────────────────
  // 字段构造
  // ─────────────────────────────────────────────────────────────────────

  String _buildFront(
    QuestionRecord q,
    ExportContentOptions contentOptions,
    String? imageBaseDir,
    Directory imageDir,
  ) {
    final parts = <String>[];
    final questionText = q.normalizedQuestionText.isNotEmpty
        ? q.normalizedQuestionText
        : q.extractedQuestionText;
    if (questionText.isNotEmpty) {
      parts.add(_escapeField(questionText));
    }
    if (contentOptions.includeImage && q.imagePath.isNotEmpty) {
      final imageFilename = _copyImage(q, imageDir);
      if (imageFilename != null) {
        final prefix = (imageBaseDir ?? '').trim();
        final src = prefix.isEmpty ? imageFilename : '$prefix/$imageFilename';
        parts.add('<img src="$src">');
      }
    }
    return parts.join('<br>');
  }

  String _buildBack(
    QuestionRecord q,
    ExportContentOptions contentOptions,
    Map<String, List<String>>? knowledgeTreePaths,
  ) {
    final analysis = q.analysisResult;
    // Phase 11-3：知识点树路径（与 includeKnowledgeTree 联动）。
    if (analysis == null) {
      final parts = <String>[];
      if (contentOptions.includeOcrText &&
          q.extractedQuestionText.isNotEmpty &&
          q.extractedQuestionText != q.normalizedQuestionText) {
        parts.add('<b>OCR 原文：</b>${_escapeField(q.extractedQuestionText)}');
      }
      if (contentOptions.includeKnowledgeTree) {
        final treePaths = knowledgeTreePaths?[q.id];
        if (treePaths != null && treePaths.isNotEmpty) {
          parts.add(
              '<b>知识点路径：</b>${_escapeField(treePaths.join('；'))}');
        }
      }
      return parts.join('<br><br>');
    }
    final parts = <String>[];
    if (contentOptions.includeCorrectAnswer &&
        analysis.finalAnswer.isNotEmpty) {
      parts.add('<b>正确答案：</b>${_escapeField(analysis.finalAnswer)}');
    }
    if (contentOptions.includeSolutionSteps && analysis.steps.isNotEmpty) {
      final stepsHtml = analysis.steps
          .asMap()
          .entries
          .map((e) => '${e.key + 1}. ${_escapeField(e.value)}')
          .join('<br>');
      parts.add('<b>解题步骤：</b><br>$stepsHtml');
    }
    if (contentOptions.includeKnowledgePoints) {
      final kps = [...analysis.knowledgePoints, ...analysis.aiTags]
          .where((s) => s.isNotEmpty)
          .toList();
      if (kps.isNotEmpty) {
        parts.add('<b>知识点：</b>${_escapeField(kps.join('、'))}');
      }
    }
    if (contentOptions.includeMistakeReason &&
        analysis.mistakeReason.isNotEmpty) {
      parts.add('<b>错因：</b>${_escapeField(analysis.mistakeReason)}');
    }
    if (contentOptions.includeStudyAdvice && analysis.studyAdvice.isNotEmpty) {
      parts.add('<b>学习建议：</b>${_escapeField(analysis.studyAdvice)}');
    }
    // Phase 11-4：OCR 识别原文（与正面校对文本对照）。
    if (contentOptions.includeOcrText &&
        q.extractedQuestionText.isNotEmpty &&
        q.extractedQuestionText != q.normalizedQuestionText) {
      parts.add('<b>OCR 原文：</b>${_escapeField(q.extractedQuestionText)}');
    }
    // Phase 11-3：知识点树路径（完整面包屑，如 `数学 > 代数 > 二次方程`）。
    if (contentOptions.includeKnowledgeTree) {
      final treePaths = knowledgeTreePaths?[q.id];
      if (treePaths != null && treePaths.isNotEmpty) {
        parts.add(
            '<b>知识点路径：</b>${_escapeField(treePaths.join('；'))}');
      }
    }
    return parts.join('<br><br>');
  }

  // ─────────────────────────────────────────────────────────────────────
  // 图片与转义
  // ─────────────────────────────────────────────────────────────────────

  /// 把题图压缩后写入 [imageDir]，返回新文件名（如 `image_abc123.jpg`）。
  ///
  /// Phase 11-3：原实现直接 copySync，大图会撑爆 Anki media 目录。
  /// 现复用 image 包做缩放（maxWidth 1200）+ JPEG 重编码（quality 80），
  /// 与 [HtmlExportService._encodeImageIsolate] 保持同一压缩参数。
  /// PNG 透明图保留为 PNG（level 6），其余统一转 JPEG。
  /// 解码失败时回退直接复制原文件，保证不阻塞导出。
  String? _copyImage(QuestionRecord q, Directory imageDir) {
    try {
      final source = File(q.imagePath);
      if (!source.existsSync()) return null;
      final sourceExt = _imageExtension(q.imagePath);
      final targetName = 'image_${_sanitizeId(q.id)}.$sourceExt';
      final target = File('${imageDir.path}/$targetName');

      // 尝试压缩：解码 → 缩放 → 重编码。失败则回退直接复制。
      try {
        final bytes = source.readAsBytesSync();
        final decoded = image.decodeImage(bytes);
        if (decoded != null) {
          image.Image scaled = decoded;
          if (decoded.width > 1200) {
            scaled = image.copyResize(decoded, width: 1200);
          }
          if (sourceExt == 'png') {
            target.writeAsBytesSync(image.encodePng(scaled, level: 6));
          } else {
            target.writeAsBytesSync(image.encodeJpg(scaled, quality: 80));
          }
          return targetName;
        }
      } catch (_) {
        // 解码失败，回退直接复制原文件。
      }
      source.copySync(target.path);
      return targetName;
    } catch (_) {
      return null;
    }
  }

  /// 转义字段值：HTML 特殊字符 + Tab/换行（避免破坏 TSV 结构）。
  ///
  /// 入口先归一化字面量 `\n`（反斜杠+n 两字符，AI 输出残留）为真正换行，
  /// 再统一替换为 `<br>`，避免选项 ABCD 前出现字面量 `\n` 文本。
  String _escapeField(String input) {
    return LatexNormalizer.normalizeLiteralNewlines(input)
        .replaceAll('&', '&amp;')
        .replaceAll('<', '&lt;')
        .replaceAll('>', '&gt;')
        .replaceAll('\t', ' ')
        .replaceAll('\r', '')
        .replaceAll('\n', '<br>');
  }

  /// 取图片扩展名，默认 jpg。
  String _imageExtension(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0 || dot == path.length - 1) return 'jpg';
    final ext = path.substring(dot + 1).toLowerCase();
    const supported = <String>{'jpg', 'jpeg', 'png', 'gif', 'svg', 'webp'};
    return supported.contains(ext) ? ext : 'jpg';
  }

  /// 把 question id 中的特殊字符替换为下划线，确保文件名安全。
  String _sanitizeId(String id) {
    return id.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
  }

  Future<Directory> _ensureExportDir() async {
    final dir = await getApplicationDocumentsDirectory();
    final exportDir = Directory('${dir.path}/exports');
    if (!exportDir.existsSync()) {
      await exportDir.create(recursive: true);
    }
    return exportDir;
  }
}
