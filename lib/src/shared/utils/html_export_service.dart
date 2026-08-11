import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb, compute;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:image/image.dart' as image;
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/review_log.dart';
import 'package:smart_wrong_notebook/src/shared/utils/export_content_options.dart';
import 'package:smart_wrong_notebook/src/shared/utils/export_file_writer.dart';
import 'package:smart_wrong_notebook/src/shared/utils/export_template.dart';
import 'package:smart_wrong_notebook/src/shared/utils/html_render_utils.dart';
import 'package:smart_wrong_notebook/src/shared/utils/templates/export_template_factory.dart';
import 'package:smart_wrong_notebook/src/shared/utils/worksheet_export_mode.dart';

/// 封面上学生信息栏数据。
class ExportStudentInfo {
  const ExportStudentInfo({
    this.name,
    this.className,
    this.date,
    this.anonymize = false,
    this.watermark,
  });

  final String? name;
  final String? className;

  /// 已格式化的日期字符串，为空时使用导出当前时间。
  final String? date;

  /// 脱敏导出：将姓名替换为 "X 同学"，日期仅保留到天（隐藏时分）。
  final bool anonymize;

  /// 水印文本，支持占位符 "{学生名}" 与 "{日期}"；为空表示不渲染水印。
  final String? watermark;

  /// 脱敏导出时返回 'X 同学'，否则返回 [name]（可能为 null）。
  String? get displayName => anonymize ? 'X 同学' : name;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ExportStudentInfo &&
          name == other.name &&
          className == other.className &&
          date == other.date &&
          anonymize == other.anonymize &&
          watermark == other.watermark;

  @override
  int get hashCode => Object.hash(name, className, date, anonymize, watermark);
}

/// HTML 导出结果：包含文件路径与统计信息。
class HtmlExportResult {
  const HtmlExportResult({
    required this.filePath,
    required this.totalQuestions,
    required this.failedImages,
    required this.htmlSizeBytes,
  });

  /// 生成的 HTML 文件绝对路径。
  final String filePath;

  /// 题目总数。
  final int totalQuestions;

  /// 处理失败的题图数量。
  final int failedImages;

  /// HTML 文件大小（字节）。
  final int htmlSizeBytes;

  /// 失败题图数 > 0 时返回给用户的提示文案，否则返回空串。
  String get failureHint =>
      failedImages > 0 ? '$failedImages 张题图处理失败' : '';
}

/// HTML 导出缓存：避免预览页与 PDF 导出重复生成同一份 HTML。
///
/// 缓存键：(questions 引用, mode, contentOptions, title, studentInfo,
/// lowResolution, noImage, layoutOptions, templateType)。任一不同则视为不命中。
/// 简单的引用/值相等判断，适合「预览 → 导出 PDF」这种短时间内的复用场景。
class HtmlExportCache {
  static String? _cachedHtml;
  static List<QuestionRecord>? _cachedQuestions;
  static WorksheetExportMode? _cachedMode;
  static ExportContentOptions? _cachedOptions;
  static String? _cachedTitle;
  static ExportStudentInfo? _cachedStudentInfo;
  static bool? _cachedLowResolution;
  static bool? _cachedNoImage;
  static PdfLayoutOptions? _cachedLayoutOptions;
  static ExportTemplateType? _cachedTemplateType;

  HtmlExportCache._();

  /// 命中返回缓存的 HTML 字符串，否则返回 null。
  static String? get({
    required List<QuestionRecord> questions,
    WorksheetExportMode? mode,
    ExportContentOptions? options,
    String title = '错题本整理报告',
    ExportStudentInfo? studentInfo,
    bool lowResolution = false,
    bool noImage = false,
    PdfLayoutOptions? layoutOptions,
    ExportTemplateType templateType = ExportTemplateType.mistakeReport,
  }) {
    if (_cachedHtml != null &&
        identical(_cachedQuestions, questions) &&
        _cachedMode == mode &&
        _cachedOptions == options &&
        _cachedTitle == title &&
        _cachedStudentInfo == studentInfo &&
        _cachedLowResolution == lowResolution &&
        _cachedNoImage == noImage &&
        _cachedLayoutOptions == layoutOptions &&
        _cachedTemplateType == templateType) {
      return _cachedHtml;
    }
    return null;
  }

  /// 写入缓存。后续相同键的 [get] 调用会直接返回 [html]。
  static void set(
    String html, {
    required List<QuestionRecord> questions,
    WorksheetExportMode? mode,
    ExportContentOptions? options,
    String title = '错题本整理报告',
    ExportStudentInfo? studentInfo,
    bool lowResolution = false,
    bool noImage = false,
    PdfLayoutOptions? layoutOptions,
    ExportTemplateType templateType = ExportTemplateType.mistakeReport,
  }) {
    _cachedHtml = html;
    _cachedQuestions = questions;
    _cachedMode = mode;
    _cachedOptions = options;
    _cachedTitle = title;
    _cachedStudentInfo = studentInfo;
    _cachedLowResolution = lowResolution;
    _cachedNoImage = noImage;
    _cachedLayoutOptions = layoutOptions;
    _cachedTemplateType = templateType;
  }

  /// 清空缓存。
  static void clear() {
    _cachedHtml = null;
    _cachedQuestions = null;
    _cachedMode = null;
    _cachedOptions = null;
    _cachedTitle = null;
    _cachedStudentInfo = null;
    _cachedLowResolution = null;
    _cachedNoImage = null;
    _cachedLayoutOptions = null;
    _cachedTemplateType = null;
  }
}

/// 生成完全自包含的 HTML 错题报告。
///
/// 特点：
/// - 内联 KaTeX 的 CSS/JS/字体（woff2），不需要网络。
/// - 题目文本、答案、解析中的 LaTeX 会被 KaTeX 渲染，支持 `$$`、`$`、
///   `\(...\)`、`\[...\]` 以及 `\begin{env}...\end{env}` 环境。
/// - 错题原图（如果存在）会被缩放压缩后以 base64 内嵌，几何图形可直接查看。
/// - 大题量（>50 题或预估 HTML >10MB）走分章节流式写入路径，避免单 StringBuffer
///   持有完整 HTML 字符串与图片 base64 Map 同时驻留内存的峰值。
/// - 通过 [templateType] 选择导出模板（错题报告 / 学习报告 / 复习卡），
///   模板负责 CSS / 封面 / 题目块 / 尾页的生成；本服务负责图片预处理、KaTeX
///   内联、流式写入、文件管理、缓存等通用逻辑。
class HtmlExportService {
  static String? _cachedKatexCss;
  static String? _cachedKatexJs;

  /// exports 目录按总大小清理的阈值（200MB）。
  static const int maxTotalExportsBytes = 200 * 1024 * 1024;

  /// exports 目录文件数二次保护上限。
  static const int maxKeptExports = 50;

  /// 图片分批处理每批数量。
  static const int _imageBatchSize = 8;

  /// 大题量阈值：超过则启用流式写入。
  static const int _streamingQuestionThreshold = 50;

  /// 流式写入触发阈值：预估 HTML 字节数。
  static const int _streamingSizeThreshold = 10 * 1024 * 1024;

  /// 是否为桌面平台（Windows / macOS / Linux），用于 PDF 降级判断。
  static bool get isDesktopPlatform =>
      !kIsWeb &&
      (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  /// 是否为「紧凑非分组」模板：复习卡 / 错题卡。
  ///
  /// 这类模板不按学科分组渲染、不生成封面/目录/页眉页脚，
  /// 每题独立成块（复习卡分页、错题卡紧凑排列）。
  static bool _isCompactLayout(ExportTemplate template) =>
      template.type == ExportTemplateType.reviewCard ||
      template.type == ExportTemplateType.errorCard;

  /// 生成 HTML 字符串（可用于直接写入文件或转 PDF）。
  ///
  /// [onProgress] 在预处理图片时回调，用于显示进度。
  /// [lowResolution] 为 true 时图片压缩到 maxWidth 800px、JPEG quality 60，
  /// 适合大题量场景减小 HTML 体积。
  /// [noImage] 为 true 时跳过所有图片处理，HTML 中以"[题图省略]"占位。
  /// [contentOptions] 提供时启用缓存：命中则直接返回缓存，未命中则生成后缓存。
  /// [watermark] 非空时在 HTML 上叠加固定位置水印（支持 "{学生名}" "{日期}" 占位符）。
  /// [layoutOptions] 非空时覆盖默认 A4 + 22mm 16mm 边距 + 11pt 字号，
  /// 同时控制封面/目录/页眉/页脚是否生成。
  /// [templateType] 选择导出模板，默认 [ExportTemplateType.mistakeReport]
  /// 保持向后兼容。
  /// [reviewLogs] 用于学习报告模板尾页的复习趋势图，可为空。
  static Future<String> generateHtmlString(
    List<QuestionRecord> questions, {
    String title = '错题本整理报告',
    WorksheetExportMode? mode,
    ExportStudentInfo? studentInfo,
    void Function(int done, int total)? onProgress,
    bool lowResolution = false,
    bool noImage = false,
    ExportContentOptions? contentOptions,
    String? watermark,
    PdfLayoutOptions? layoutOptions,
    ExportTemplateType templateType = ExportTemplateType.mistakeReport,
    List<ReviewLog>? reviewLogs,
  }) async {
    final result = await _generateHtmlStringInternal(
      questions,
      title: title,
      mode: mode,
      studentInfo: studentInfo,
      onProgress: onProgress,
      lowResolution: lowResolution,
      noImage: noImage,
      contentOptions: contentOptions,
      watermark: watermark,
      layoutOptions: layoutOptions,
      templateType: templateType,
      reviewLogs: reviewLogs,
    );
    return result.html;
  }

  /// 内部实现：返回 HTML 字符串及失败题图数。
  static Future<({String html, int failedImages})> _generateHtmlStringInternal(
    List<QuestionRecord> questions, {
    String title = '错题本整理报告',
    WorksheetExportMode? mode,
    ExportStudentInfo? studentInfo,
    void Function(int done, int total)? onProgress,
    bool lowResolution = false,
    bool noImage = false,
    ExportContentOptions? contentOptions,
    String? watermark,
    PdfLayoutOptions? layoutOptions,
    ExportTemplateType templateType = ExportTemplateType.mistakeReport,
    List<ReviewLog>? reviewLogs,
  }) async {
    // 缓存命中检查
    if (contentOptions != null) {
      final cached = HtmlExportCache.get(
        questions: questions,
        mode: mode,
        options: contentOptions,
        title: title,
        studentInfo: studentInfo,
        lowResolution: lowResolution,
        noImage: noImage,
        layoutOptions: layoutOptions,
        templateType: templateType,
      );
      if (cached != null) {
        return (html: cached, failedImages: 0);
      }
    }

    final katexCss = await _loadKatexCss();
    final katexJs = await _loadKatexJs();

    final template = ExportTemplateFactory.create(templateType);

    // 脱敏导出：隐藏创建时间的时分秒，仅保留到天。
    final anonymize = studentInfo?.anonymize ?? false;
    final dateStr = studentInfo?.date ??
        DateFormat(anonymize ? 'yyyy-MM-dd' : 'yyyy-MM-dd HH:mm')
            .format(DateTime.now());
    final resolvedWatermark = _resolveWatermark(watermark, studentInfo, dateStr);

    // 预处理所有图片（分批压缩编码，避免一次启动过多 isolate）。
    final imageResult = await _preloadImages(
      questions,
      onProgress,
      lowResolution: lowResolution,
      noImage: noImage,
    );

    final useStreaming = _shouldUseStreaming(questions);

    String html;
    if (useStreaming) {
      // 大题量流式写入：先写文件头到临时文件，按章节 flush，最后写文件尾。
      html = await _generateHtmlStreaming(
        questions: questions,
        title: title,
        mode: mode,
        studentInfo: studentInfo,
        dateStr: dateStr,
        katexCss: katexCss,
        katexJs: katexJs,
        imageUris: imageResult.uris,
        noImage: noImage,
        watermark: resolvedWatermark,
        layoutOptions: layoutOptions,
        template: template,
        contentOptions: contentOptions ?? const ExportContentOptions(),
        reviewLogs: reviewLogs,
      );
    } else {
      // 小题量：保持原 StringBuffer 路径（性能更好）。
      final buffer = StringBuffer();
      _writeHtmlToSink(
        buffer,
        questions: questions,
        title: title,
        mode: mode,
        studentInfo: studentInfo,
        dateStr: dateStr,
        katexCss: katexCss,
        katexJs: katexJs,
        imageUris: imageResult.uris,
        noImage: noImage,
        watermark: resolvedWatermark,
        layoutOptions: layoutOptions,
        template: template,
        contentOptions: contentOptions ?? const ExportContentOptions(),
        reviewLogs: reviewLogs,
      );
      html = buffer.toString();
    }

    // 写入缓存
    if (contentOptions != null) {
      HtmlExportCache.set(
        html,
        questions: questions,
        mode: mode,
        options: contentOptions,
        title: title,
        studentInfo: studentInfo,
        lowResolution: lowResolution,
        noImage: noImage,
        layoutOptions: layoutOptions,
        templateType: templateType,
      );
    }

    return (html: html, failedImages: imageResult.failed);
  }

  /// 生成 HTML 文件并返回结果（含统计信息）。
  static Future<HtmlExportResult> generateHtml(
    List<QuestionRecord> questions, {
    String title = '错题本整理报告',
    WorksheetExportMode? mode,
    ExportStudentInfo? studentInfo,
    void Function(int done, int total)? onProgress,
    bool lowResolution = false,
    bool noImage = false,
    ExportContentOptions? contentOptions,
    String? watermark,
    PdfLayoutOptions? layoutOptions,
    ExportTemplateType templateType = ExportTemplateType.mistakeReport,
    List<ReviewLog>? reviewLogs,
  }) async {
    final result = await _generateHtmlStringInternal(
      questions,
      title: title,
      mode: mode,
      studentInfo: studentInfo,
      onProgress: onProgress,
      lowResolution: lowResolution,
      noImage: noImage,
      contentOptions: contentOptions,
      watermark: watermark,
      layoutOptions: layoutOptions,
      templateType: templateType,
      reviewLogs: reviewLogs,
    );
    final dir = await getApplicationDocumentsDirectory();
    final exportDir = Directory('${dir.path}/exports');
    if (!exportDir.existsSync()) {
      await exportDir.create(recursive: true);
    }
    final filename =
        buildExportFileName(questions, mode: mode, studentInfo: studentInfo);
    final file = await ExportFileWriter.uniqueTarget(exportDir, filename);
    await ExportFileWriter.writeTextAtomic(file, result.html);
    await cleanupExports(exportDir);
    return HtmlExportResult(
      filePath: file.path,
      totalQuestions: questions.length,
      failedImages: result.failedImages,
      htmlSizeBytes: await file.length(),
    );
  }

  /// 调起系统分享 HTML 文件，并在生成期间显示进度。
  static Future<void> shareHtml(
    BuildContext context,
    List<QuestionRecord> questions, {
    String title = '错题本整理报告',
    WorksheetExportMode? mode,
    ExportStudentInfo? studentInfo,
    ExportContentOptions? contentOptions,
    String? watermark,
    PdfLayoutOptions? layoutOptions,
    ExportTemplateType templateType = ExportTemplateType.mistakeReport,
    List<ReviewLog>? reviewLogs,
  }) async {
    final progress = ValueNotifier<double>(0);
    if (!context.mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const CircularProgressIndicator(),
              const SizedBox(height: 12),
              ValueListenableBuilder<double>(
                valueListenable: progress,
                builder: (_, v, __) {
                  if (v <= 0) {
                    return const Text('正在准备导出…');
                  }
                  // 图片预处理到 100% 后，generateHtml 还要写文件 +
                  // 调起系统分享（几秒），这期间进度保持 1.0。
                  // 切换文案避免用户误以为卡死。
                  if (v >= 1.0) {
                    return const Text('正在生成 HTML…');
                  }
                  return Text('正在处理图片 ${(v * 100).round()}%');
                },
              ),
            ],
          ),
        ),
      ),
    );
    try {
      final result = await generateHtml(
        questions,
        title: title,
        mode: mode,
        studentInfo: studentInfo,
        onProgress: (done, total) {
          progress.value = total == 0 ? 1 : done / total;
        },
        contentOptions: contentOptions,
        watermark: watermark,
        layoutOptions: layoutOptions,
        templateType: templateType,
        reviewLogs: reviewLogs,
      );
      if (!context.mounted) return;
      Navigator.of(context).pop();
      if (result.failureHint.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出完成（${result.failureHint}）')),
        );
      }
      final box = context.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return;
      final origin = box.localToGlobal(Offset.zero) & box.size;
      await Share.shareXFiles(
        [XFile(result.filePath)],
        sharePositionOrigin: origin,
      );
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出 HTML 失败: $e')),
        );
      }
    }
  }

  /// 清理 exports 目录：按总大小（>200MB 删最旧）+ 文件数上限（>50 删最旧）。
  static Future<void> cleanupExports(Directory exportDir) async {
    try {
      if (!exportDir.existsSync()) return;
      final entries = exportDir.listSync().whereType<File>().toList();
      final stats = <_FileStat>[];
      for (final f in entries) {
        try {
          final s = f.statSync();
          stats.add(_FileStat(f, s.modified, s.size));
        } catch (_) {
          // 单个文件 stat 失败跳过，不影响其他文件清理。
        }
      }
      // 按修改时间倒序（最新在前）。
      stats.sort((a, b) => b.modified.compareTo(a.modified));

      var totalBytes = 0;
      for (final s in stats) {
        totalBytes += s.size;
      }

      // 从最旧开始删，直到同时满足大小与数量上限。
      var remainingCount = stats.length;
      for (var i = stats.length - 1; i >= 0; i--) {
        if (totalBytes <= maxTotalExportsBytes &&
            remainingCount <= maxKeptExports) {
          break;
        }
        final s = stats[i];
        try {
          await s.file.delete();
          totalBytes -= s.size;
          remainingCount--;
        } catch (_) {
          // 单个删除失败不影响其他文件清理。
        }
      }
    } catch (_) {
      // 清理失败不影响导出。
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 流式写入路径（大题量）
  // ─────────────────────────────────────────────────────────────────────────

  /// 判断是否启用流式写入：题目数 > 50 或预估 HTML > 10MB。
  static bool _shouldUseStreaming(List<QuestionRecord> questions) {
    if (questions.length > _streamingQuestionThreshold) return true;
    // 预估：题目文本 ~3KB/题 + 题图压缩后 ~400KB/张（base64 后约 530KB）。
    final imageCount =
        questions.where((q) => q.imagePath.isNotEmpty).length;
    final estimatedBytes =
        questions.length * 3 * 1024 + imageCount * 530 * 1024;
    return estimatedBytes > _streamingSizeThreshold;
  }

  /// 大题量流式写入：用 [IOSink]（实现 [StringSink]）逐章节 flush 到临时文件，
  /// 完成后读回 HTML 字符串返回。读回虽有一次 IO，但避免 StringBuffer 在生成
  /// 期间同时持有完整 HTML（5MB+）与图片 base64 Map（数十 MB）的内存峰值。
  static Future<String> _generateHtmlStreaming({
    required List<QuestionRecord> questions,
    required String title,
    required WorksheetExportMode? mode,
    required ExportStudentInfo? studentInfo,
    required String dateStr,
    required String katexCss,
    required String katexJs,
    required Map<String, String?> imageUris,
    required bool noImage,
    required String? watermark,
    required ExportTemplate template,
    required ExportContentOptions contentOptions,
    required List<ReviewLog>? reviewLogs,
    PdfLayoutOptions? layoutOptions,
  }) async {
    final dir = await getApplicationDocumentsDirectory();
    final exportDir = Directory('${dir.path}/exports');
    if (!exportDir.existsSync()) {
      await exportDir.create(recursive: true);
    }
    final tempFile = File(
        '${exportDir.path}/.tmp_streaming_${DateTime.now().millisecondsSinceEpoch}.html');
    final sink = tempFile.openWrite();
    try {
      // 写文件头（DOCTYPE/CSS/字体/封面/目录）。
      _writeHtmlHeadToSink(
        sink,
        questions: questions,
        title: title,
        studentInfo: studentInfo,
        dateStr: dateStr,
        katexCss: katexCss,
        watermark: watermark,
        layoutOptions: layoutOptions,
        template: template,
      );
      await sink.flush();

      // 写正文：按模板风格渲染各题。
      // - 错题报告/学习报告/试卷：按学科分组。
      // - 复习卡/错题卡：每题独立成块，不按学科分组。
      if (_isCompactLayout(template)) {
        for (var i = 0; i < questions.length; i++) {
          final q = questions[i];
          final imageUri = imageUris[q.id];
          sink.write(template.generateQuestionBlock(
            question: q,
            index: i + 1,
            mode: mode ?? WorksheetExportMode.answer,
            contentOptions: contentOptions,
            imageBase64: imageUri,
            watermark: watermark,
            noImage: noImage,
          ));
          await sink.flush();
        }
      } else {
        final grouped = HtmlRenderUtils.groupBySubject(questions);
        final sortedSubjects = HtmlRenderUtils.sortedSubjects(grouped);
        int globalIndex = 0;
        for (final subject in sortedSubjects) {
          final list = grouped[subject]!;
          final color = HtmlRenderUtils.subjectColorHex(subject);
          sink.writeln('  <div class="subject-section">');
          // Phase 11-6：学科分组用 <details> 包裹，默认展开（open），
          // 点击学科标题可收起/展开该学科题目，便于长报告浏览。
          sink.writeln('    <details open>');
          sink.writeln('      <summary class="subject-header">');
          sink.writeln(
              '        <div class="subject-bar" style="background:$color"></div>');
          sink.writeln(
              '        <div class="subject-title">${HtmlRenderUtils.escapeHtml(subject.label)}（${list.length} 题）</div>');
          sink.writeln('      </summary>');

          for (final q in list) {
            globalIndex++;
            final imageUri = imageUris[q.id];
            sink.write(template.generateQuestionBlock(
              question: q,
              index: globalIndex,
              mode: mode ?? WorksheetExportMode.answer,
              contentOptions: contentOptions,
              imageBase64: imageUri,
              watermark: watermark,
              noImage: noImage,
            ));
          }

          sink.writeln('    </details>');
          sink.writeln('  </div>');
          await sink.flush();
        }
      }

      // 尾页（学习报告会生成 SVG 图表，其它模板返回 null）。
      final footer = template.generateFooter(
        questions: questions,
        reviewLogs: reviewLogs,
      );
      if (footer != null && footer.isNotEmpty) {
        sink.write(footer);
      }

      // 写文件尾（page 闭合 + KaTeX JS + render 脚本）。
      sink.writeln('</div>');
      sink.writeln('<script>');
      sink.writeln(katexJs);
      sink.writeln(HtmlRenderUtils.renderMathJs());
      sink.writeln('</script>');
      sink.writeln('</body>');
      sink.writeln('</html>');

      await sink.flush();
      await sink.close();

      // 读回 HTML 字符串供 PDF 转换或缓存使用。
      return tempFile.readAsString();
    } catch (_) {
      // 出错时也尝试关闭 sink，避免文件句柄泄漏。
      try {
        await sink.close();
      } catch (_) {
        // 忽略关闭失败。
      }
      rethrow;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // HTML 写入：StringSink 兼容 StringBuffer（内存）与 IOSink（流式）
  // ─────────────────────────────────────────────────────────────────────────

  /// 把完整 HTML 写入 [sink]，小题量场景下 [sink] 是 [StringBuffer]。
  static void _writeHtmlToSink(
    StringSink sink, {
    required List<QuestionRecord> questions,
    required String title,
    required WorksheetExportMode? mode,
    required ExportStudentInfo? studentInfo,
    required String dateStr,
    required String katexCss,
    required String katexJs,
    required Map<String, String?> imageUris,
    required bool noImage,
    required String? watermark,
    required ExportTemplate template,
    required ExportContentOptions contentOptions,
    required List<ReviewLog>? reviewLogs,
    PdfLayoutOptions? layoutOptions,
  }) {
    _writeHtmlHeadToSink(
      sink,
      questions: questions,
      title: title,
      studentInfo: studentInfo,
      dateStr: dateStr,
      katexCss: katexCss,
      watermark: watermark,
      layoutOptions: layoutOptions,
      template: template,
    );

    // 正文：按模板风格渲染各题。
    if (_isCompactLayout(template)) {
      for (var i = 0; i < questions.length; i++) {
        final q = questions[i];
        final imageUri = imageUris[q.id];
        sink.write(template.generateQuestionBlock(
          question: q,
          index: i + 1,
          mode: mode ?? WorksheetExportMode.answer,
          contentOptions: contentOptions,
          imageBase64: imageUri,
          watermark: watermark,
          noImage: noImage,
        ));
      }
    } else {
      final grouped = HtmlRenderUtils.groupBySubject(questions);
      final sortedSubjects = HtmlRenderUtils.sortedSubjects(grouped);
      int globalIndex = 0;
      for (final subject in sortedSubjects) {
        final list = grouped[subject]!;
        final color = HtmlRenderUtils.subjectColorHex(subject);
        sink.writeln('  <div class="subject-section">');
        // Phase 11-6：学科分组用 <details> 包裹，默认展开（open）。
        sink.writeln('    <details open>');
        sink.writeln('      <summary class="subject-header">');
        sink.writeln(
            '        <div class="subject-bar" style="background:$color"></div>');
        sink.writeln(
            '        <div class="subject-title">${HtmlRenderUtils.escapeHtml(subject.label)}（${list.length} 题）</div>');
        sink.writeln('      </summary>');

        for (final q in list) {
          globalIndex++;
          final imageUri = imageUris[q.id];
          sink.write(template.generateQuestionBlock(
            question: q,
            index: globalIndex,
            mode: mode ?? WorksheetExportMode.answer,
            contentOptions: contentOptions,
            imageBase64: imageUri,
            watermark: watermark,
            noImage: noImage,
          ));
        }

        sink.writeln('    </details>');
        sink.writeln('  </div>');
      }
    }

    // 尾页（学习报告会生成 SVG 图表，其它模板返回 null）。
    final footer = template.generateFooter(
      questions: questions,
      reviewLogs: reviewLogs,
    );
    if (footer != null && footer.isNotEmpty) {
      sink.write(footer);
    }

    sink.writeln('</div>');
    sink.writeln('<script>');
    sink.writeln(katexJs);
    sink.writeln(HtmlRenderUtils.renderMathJs());
    sink.writeln('</script>');
    sink.writeln('</body>');
    sink.writeln('</html>');
  }

  /// 写 HTML 文件头：DOCTYPE、head、CSS、body 开始、封面、目录。
  /// 流式路径下此部分先 flush 一次。
  /// [layoutOptions] 非空时按 includeCover/includeToc/includeHeader/includeFooter
  /// 控制对应区块；模板负责具体的 CSS / 封面 HTML 生成。
  static void _writeHtmlHeadToSink(
    StringSink sink, {
    required List<QuestionRecord> questions,
    required String title,
    required ExportStudentInfo? studentInfo,
    required String dateStr,
    required String katexCss,
    required String? watermark,
    required ExportTemplate template,
    PdfLayoutOptions? layoutOptions,
  }) {
    final layout = layoutOptions ?? const PdfLayoutOptions();
    sink.writeln('<!DOCTYPE html>');
    sink.writeln('<html lang="zh-CN">');
    sink.writeln('<head>');
    sink.writeln('<meta charset="UTF-8">');
    sink.writeln(
        '<meta name="viewport" content="width=device-width, initial-scale=1.0">');
    sink.writeln('<title>${HtmlRenderUtils.escapeHtml(title)}</title>');
    sink.writeln('<style>');
    sink.writeln(template.generateCss(layout));
    sink.writeln(katexCss);
    sink.writeln('</style>');
    sink.writeln('</head>');
    sink.writeln('<body>');
    // 水印：非空时叠加固定位置半透明文字，覆盖整页且不影响交互。
    if (watermark != null && watermark.isNotEmpty) {
      sink.writeln(
          '  <div class="watermark">${HtmlRenderUtils.escapeHtml(watermark)}</div>');
    }
    // 打印时的页眉页脚（fixed 元素，支持的平台会在每页重复）。
    // 复习卡 / 错题卡模板不生成页眉页脚（紧凑布局，fixed 元素会干扰视觉）。
    final showHeader = layout.includeHeader &&
        !_isCompactLayout(template);
    final showFooter = layout.includeFooter &&
        !_isCompactLayout(template);
    if (showHeader) {
      sink.writeln('  <div class="print-header">${HtmlRenderUtils.escapeHtml(title)}</div>');
    }
    if (showFooter) {
      sink.writeln(
          '  <div class="print-footer">第 1 页 / 共 1 页</div>');
    }
    sink.writeln('<div class="page">');

    // 封面与目录：复习卡 / 错题卡模板不生成（紧凑布局，无封面无目录）。
    // 学习报告 / 错题报告 / 试卷模板受 layout.includeCover / includeToc 控制。
    final showCover = layout.includeCover;
    final showToc = layout.includeToc &&
        !_isCompactLayout(template);
    if (showCover) {
      sink.write(template.generateCover(
        title: title,
        studentName: studentInfo?.displayName,
        className: studentInfo?.className,
        date: DateTime.now(),
        questionCount: questions.length,
        questions: questions,
        anonymize: studentInfo?.anonymize ?? false,
        formattedDate: dateStr,
      ));
    }

    if (showToc) {
      final grouped = HtmlRenderUtils.groupBySubject(questions);
      final sortedSubjects = HtmlRenderUtils.sortedSubjects(grouped);
      sink.writeln('  <div class="toc">');
      sink.writeln('    <h2>目&emsp;录</h2>');
      // Phase 11-6：目录用 <details> 折叠，默认展开（open），
      // 点击学科名可收起/展开对应分组的题目列表。
      sink.writeln('    <details class="toc-group" open>');
      sink.writeln('      <summary>按学科分组（${sortedSubjects.length} 个学科）</summary>');
      for (final subject in sortedSubjects) {
        final list = grouped[subject]!;
        sink.writeln('      <div class="toc-item">');
        sink.writeln('        <span>${HtmlRenderUtils.escapeHtml(subject.label)}</span>');
        sink.writeln('        <span class="count">${list.length} 题</span>');
        sink.writeln('      </div>');
      }
      sink.writeln('    </details>');
      sink.writeln('    <div class="legend">');
      sink.writeln(
          '      掌握程度：● 待学习&emsp;● 复习中&emsp;● 已掌握');
      sink.writeln('    </div>');
      sink.writeln('  </div>');
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 图片预处理（分批压缩）
  // ─────────────────────────────────────────────────────────────────────────

  /// 预处理题目图片：分批压缩编码，每批 [_imageBatchSize] 张并行 isolate。
  /// [lowResolution] 为 true 时降低 maxWidth 与 JPEG quality。
  /// [noImage] 为 true 时直接返回空 map，不读图。
  /// 返回 (uris, failed)：uris[q.id] 为 data URI 或 null（处理失败），
  /// failed 为失败题图总数。
  static Future<({Map<String, String?> uris, int failed})> _preloadImages(
    List<QuestionRecord> questions,
    void Function(int done, int total)? onProgress, {
    bool lowResolution = false,
    bool noImage = false,
  }) async {
    if (noImage) {
      // 无图模式：跳过所有图片处理。
      if (onProgress != null) onProgress(0, 0);
      return (uris: const <String, String?>{}, failed: 0);
    }
    final entries = questions.where((q) => q.imagePath.isNotEmpty).toList();
    final total = entries.length;
    if (total == 0) {
      if (onProgress != null) onProgress(0, 0);
      return (uris: const <String, String?>{}, failed: 0);
    }
    final uris = <String, String?>{};
    var done = 0;
    var failed = 0;
    // 分批处理：每批 _imageBatchSize 张，限制同时启动的 isolate 数量。
    for (var i = 0; i < entries.length; i += _imageBatchSize) {
      final batch = entries.skip(i).take(_imageBatchSize).toList();
      final results = await Future.wait(batch.map((q) async {
        final uri =
            await _encodeImage(q.imagePath, lowResolution: lowResolution);
        return MapEntry(q.id, uri);
      }));
      for (final e in results) {
        uris[e.key] = e.value;
        if (e.value == null) failed++;
        done++;
      }
      if (onProgress != null) onProgress(done, total);
    }
    return (uris: uris, failed: failed);
  }

  /// 读取图片文件，缩放到最大宽度并重新编码，返回 data URI。
  /// 解码/缩放/编码在后台 isolate 执行，避免大图阻塞 UI。
  /// PNG 保留 PNG 编码（保留透明），其余转 JPEG。
  /// [lowResolution] 为 true 时 maxWidth 降到 800px、JPEG quality 60。
  /// 返回 null 表示解码失败（调用方应记录为失败题图）。
  static Future<String?> _encodeImage(
    String path, {
    bool lowResolution = false,
  }) async {
    if (path.isEmpty) return null;
    final file = File(path);
    if (!await file.exists()) return null;
    try {
      final raw = await file.readAsBytes();
      if (raw.isEmpty) return null;
      final result = await compute(
        _encodeImageIsolate,
        _EncodeRequest(raw, path, lowResolution: lowResolution),
      );
      if (result == null) {
        // 无法解码，回退原文件 base64。
        final ext = path.split('.').last.toLowerCase();
        final mime = ext == 'png' ? 'image/png' : 'image/jpeg';
        return 'data:$mime;base64,${base64Encode(raw)}';
      }
      return result;
    } catch (_) {
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // KaTeX 资源内联
  // ─────────────────────────────────────────────────────────────────────────

  static Future<String> _loadKatexCss() async {
    if (_cachedKatexCss != null) return _cachedKatexCss!;
    var css = await rootBundle.loadString('assets/katex/katex.min.css');
    css = await _inlineAllFontFaces(css);
    _cachedKatexCss = css;
    return css;
  }

  static Future<String> _loadKatexJs() async {
    _cachedKatexJs ??=
        await rootBundle.loadString('assets/katex/katex.min.js');
    return _cachedKatexJs!;
  }

  static Future<String> _inlineAllFontFaces(String css) async {
    // 1. 内联 woff2 字体为 base64。
    final woff2Re =
        RegExp(r'''url\(['"]?fonts/([A-Za-z0-9_\-]+\.woff2)['"]?\)''');
    final filenames = woff2Re.allMatches(css).map((m) => m.group(1)!).toSet();
    for (final filename in filenames) {
      try {
        final data = await rootBundle.load('assets/katex/fonts/$filename');
        final base64 = base64Encode(data.buffer.asUint8List());
        final uri = "data:font/woff2;base64,$base64";
        css = css.replaceAllMapped(
          RegExp(
              r'''url\(['"]?fonts/''' + RegExp.escape(filename) + r'''['"]?\)'''),
          (_) => "url('$uri')",
        );
      } catch (_) {
        // 如果某个字体未打包，保留原链接，浏览器会继续尝试加载。
      }
    }
    // 2. 删除 woff/ttf fallback，避免离线 404（woff2 已足够现代浏览器使用）。
    css = css.replaceAll(
      RegExp(r''',\s*url\(fonts/[^)]+\.woff\)\s*format\("woff"\)'''),
      '',
    );
    css = css.replaceAll(
      RegExp(r''',\s*url\(fonts/[^)]+\.ttf\)\s*format\("truetype"\)'''),
      '',
    );
    return css;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 文件名与水印工具
  // ─────────────────────────────────────────────────────────────────────────

  /// 构造默认导出文件名：`{学生名或"错题本"}_{模式}_{学科范围}_{题量}题_{yyyyMMdd_HHmm}.{extension}`。
  ///
  /// 脱敏导出时学生名用 "X 同学" 代替；文件名中的非法字符会被替换为下划线。
  static String buildExportFileName(
    List<QuestionRecord> questions, {
    WorksheetExportMode? mode,
    ExportStudentInfo? studentInfo,
    String extension = 'html',
  }) {
    final namePart =
        _sanitizeFileNamePart(studentInfo?.displayName ?? '错题本');
    final modePart = _sanitizeFileNamePart(_modeLabel(mode));
    final subjectPart = _sanitizeFileNamePart(_subjectScopeLabel(questions));
    final countPart = '${questions.length}题';
    final timePart = DateFormat('yyyyMMdd_HHmmss_SSS').format(DateTime.now());
    return '${namePart}_${modePart}_${subjectPart}_${countPart}_$timePart.$extension';
  }

  /// 工作表模式对应的中文标签（用于文件名）。
  static String _modeLabel(WorksheetExportMode? mode) {
    if (mode == null) return '默认';
    return switch (mode) {
      WorksheetExportMode.practice => '练习卷',
      WorksheetExportMode.answer => '答案卷',
      WorksheetExportMode.correction => '订正卷',
    };
  }

  /// 学科范围标签：单学科返回学科名，多学科返回"多学科"，空题库返回"空"。
  static String _subjectScopeLabel(List<QuestionRecord> questions) {
    final subjects = questions.map((q) => q.subject).toSet();
    if (subjects.isEmpty) return '空';
    if (subjects.length == 1) return subjects.first.label;
    return '多学科';
  }

  /// 替换文件名中的非法字符为下划线。
  static String _sanitizeFileNamePart(String part) {
    return part.replaceAll(RegExp(r'[\\/:*?"<>|\s]'), '_');
  }

  /// 解析水印模板：将 "{学生名}" "{日期}" 占位符替换为实际值。
  /// 返回 null 表示不渲染水印（watermark 为 null 或空串）。
  static String? _resolveWatermark(
    String? watermark,
    ExportStudentInfo? studentInfo,
    String dateStr,
  ) {
    if (watermark == null || watermark.isEmpty) return null;
    final name = studentInfo?.displayName ?? '错题本';
    return watermark
        .replaceAll('{学生名}', name)
        .replaceAll('{日期}', dateStr);
  }
}

class _EncodeRequest {
  const _EncodeRequest(this.bytes, this.path, {this.lowResolution = false});
  final Uint8List bytes;
  final String path;
  final bool lowResolution;
}

/// 文件 + 修改时间 + 大小，用于 cleanupExports 排序。
class _FileStat {
  const _FileStat(this.file, this.modified, this.size);
  final File file;
  final DateTime modified;
  final int size;
}

/// 在后台 isolate 执行图片解码、缩放、重编码，返回 data URI 字符串。
/// 返回 null 表示解码失败（调用方回退原文件 base64）。
/// [req.lowResolution] 为 true 时 maxWidth 降到 800px、JPEG quality 60。
String? _encodeImageIsolate(_EncodeRequest req) {
  final decoded = image.decodeImage(req.bytes);
  if (decoded == null) return null;
  final maxWidth = req.lowResolution ? 800 : 1200;
  image.Image scaled = decoded;
  if (decoded.width > maxWidth) {
    scaled = image.copyResize(decoded, width: maxWidth);
  }
  final ext = req.path.split('.').last.toLowerCase();
  if (ext == 'png') {
    final encoded = image.encodePng(scaled, level: 6);
    return 'data:image/png;base64,${base64Encode(encoded)}';
  }
  final quality = req.lowResolution ? 60 : 80;
  final encoded = image.encodeJpg(scaled, quality: quality);
  return 'data:image/jpeg;base64,${base64Encode(encoded)}';
}
