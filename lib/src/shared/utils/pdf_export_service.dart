import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_native_html_to_pdf/flutter_native_html_to_pdf.dart' as html2pdf;
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:smart_wrong_notebook/src/domain/models/content_status.dart';
import 'package:smart_wrong_notebook/src/domain/models/mastery_level.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/shared/utils/export_file_writer.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';

import 'export_content_options.dart';
import 'html_export_service.dart';
import 'pdf_layout_options.dart';
import 'worksheet_export_mode.dart';

/// 把自包含 HTML 错题报告转成 PDF 并分享。
///
/// 移动端利用原生 WebView 渲染（`flutter_native_html_to_pdf`），
/// 公式（KaTeX）和几何图片都能高保真输出；
/// 桌面端（Windows/macOS/Linux）`flutter_native_html_to_pdf` 不支持，
/// 改用 `pdf` 包直接从 [QuestionRecord] 列表原生生成 PDF（不依赖 WebView），
/// 并通过 `printing` 包调起系统打印对话框（含「另存为 PDF」）。
///
/// [PdfLayoutOptions] 同时驱动桌面端原生 PDF 的纸张/方向/边距/字号与
/// 移动端 HTML 报告的 `@page` CSS。复用 [HtmlExportCache]：若
/// [HtmlPreviewScreen] 已生成过同一份 HTML，直接命中缓存。
class PdfExportService {
  /// 生成 PDF 文件并返回。
  ///
  /// 桌面平台返回原生生成的 PDF 文件（pdf 包）；
  /// 移动平台返回 WebView 渲染的 PDF 文件。
  static Future<File> generatePdf(
    List<QuestionRecord> questions, {
    String title = '错题本整理报告',
    WorksheetExportMode? mode,
    ExportStudentInfo? studentInfo,
    void Function(int done, int total)? onProgress,
    String? watermark,
    PdfLayoutOptions? layoutOptions,
    ExportContentOptions contentOptions = const ExportContentOptions(),
  }) async {
    final layout = layoutOptions ?? PdfLayoutOptions.defaults;

    if (HtmlExportService.isDesktopPlatform) {
      // 桌面端：pdf 包原生生成 PDF（不依赖 WebView）。
      return _generatePdfNative(
        questions,
        title: title,
        mode: mode,
        studentInfo: studentInfo,
        onProgress: onProgress,
        layout: layout,
      );
    }

    // 移动端和 HTML 使用同一份内容选项，避免 PDF 与 HTML 内容不一致。
    String html;
    final cached = HtmlExportCache.get(
      questions: questions,
      mode: mode,
      options: contentOptions,
      title: title,
      studentInfo: studentInfo,
      layoutOptions: layout,
    );
    if (cached != null) {
      html = cached;
    } else {
      // 传 contentOptions 让 generateHtmlString 在生成后写入缓存，
      // 后续若再次导出同一份内容可直接命中。
      html = await HtmlExportService.generateHtmlString(
        questions,
        title: title,
        mode: mode,
        studentInfo: studentInfo,
        onProgress: onProgress,
        contentOptions: contentOptions,
        watermark: watermark,
        layoutOptions: layout,
      );
    }

    final dir = await getApplicationDocumentsDirectory();
    final exportDir = Directory('${dir.path}/exports');
    if (!exportDir.existsSync()) {
      await exportDir.create(recursive: true);
    }
    final filename = HtmlExportService.buildExportFileName(questions,
        mode: mode, studentInfo: studentInfo, extension: 'pdf');

    final converter = html2pdf.HtmlToPdfConverter();
    // convertHtmlToPdf 会自动添加 .pdf 后缀，这里只传不带后缀的 name。
    final targetName = filename.replaceAll(RegExp(r'\.pdf$'), '');
    final file = await converter.convertHtmlToPdf(
      html: html,
      targetDirectory: exportDir.path,
      targetName: targetName,
      pageSize: html2pdf.PdfPageSize.a4,
    );
    await HtmlExportService.cleanupExports(exportDir);
    return file;
  }

  /// 调起系统分享 PDF 文件，并在生成期间显示进度。
  ///
  /// 桌面端用 `printing` 包的 [Printing.layoutPdf] 调起系统打印对话框，
  /// 用户可在对话框中选择「另存为 PDF」。失败时降级为 [Share.shareXFiles]
  /// 或浏览器打开 HTML。
  static Future<void> sharePdf(
    BuildContext context,
    List<QuestionRecord> questions, {
    String title = '错题本整理报告',
    WorksheetExportMode? mode,
    ExportStudentInfo? studentInfo,
    String? watermark,
    PdfLayoutOptions? layoutOptions,
  }) async {
    if (HtmlExportService.isDesktopPlatform) {
      await _sharePdfDesktop(context, questions,
          title: title,
          mode: mode,
          studentInfo: studentInfo,
          watermark: watermark,
          layoutOptions: layoutOptions);
      return;
    }
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
                  // 图片预处理到 100% 后，generatePdf 还要调用
                  // convertHtmlToPdf 渲染 PDF（WebView，耗时数秒到十几秒），
                  // 这期间进度保持 1.0。切换文案避免用户误以为卡死。
                  if (v >= 1.0) {
                    return const Text('正在生成 PDF…');
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
      final file = await generatePdf(
        questions,
        title: title,
        mode: mode,
        studentInfo: studentInfo,
        onProgress: (done, total) {
          progress.value = total == 0 ? 1 : done / total;
        },
        watermark: watermark,
        layoutOptions: layoutOptions,
      );
      if (!context.mounted) return;
      Navigator.of(context).pop();
      final box = context.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return;
      final origin = box.localToGlobal(Offset.zero) & box.size;
      await Share.shareXFiles(
        [XFile(file.path)],
        sharePositionOrigin: origin,
      );
    } catch (e) {
      if (context.mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出 PDF 失败: $e')),
        );
      }
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 桌面端：pdf 包原生生成 PDF
  // ─────────────────────────────────────────────────────────────────────────

  /// 桌面端用 `pdf` 包从 [questions] 直接生成 PDF 文件。
  ///
  /// 不依赖 WebView：题目文本/图片用 pdf widgets 排版，LaTeX 公式以源码
  /// 形式渲染（保留 `$...$` / `$$...$$` 定界符，便于打印后人工识别）。
  /// 适合 Windows / macOS / Linux 桌面环境。
  static Future<File> _generatePdfNative(
    List<QuestionRecord> questions, {
    required String title,
    WorksheetExportMode? mode,
    ExportStudentInfo? studentInfo,
    void Function(int done, int total)? onProgress,
    required PdfLayoutOptions layout,
  }) async {
    // 加载中文字体：优先 PdfGoogleFonts 下载 Noto Sans SC，失败回退 Helvetica。
    final baseFont = await _loadCjkFont();
    final boldFont = await _loadCjkFont(bold: true);

    final pageFormat = _resolvePageFormat(layout);
    final theme = pw.ThemeData.withFont(base: baseFont, bold: boldFont);

    final doc = pw.Document(theme: theme);

    // 脱敏导出：隐藏创建时间的时分秒，仅保留到天。
    final dateStr = studentInfo?.date ??
        '${DateTime.now().year}-${DateTime.now().month.toString().padLeft(2, '0')}-'
                '${DateTime.now().day.toString().padLeft(2, '0')}';

    // 按学科分组排序（与 HTML 路径一致）。
    final grouped = <Subject, List<QuestionRecord>>{};
    for (final q in questions) {
      grouped.putIfAbsent(q.subject, () => []).add(q);
    }
    final sortedSubjects = grouped.keys.toList()
      ..sort((a, b) => a.label.compareTo(b.label));

    // 预处理图片：读字节并解码，便于嵌入 PDF。
    final imageBytesMap = <String, Uint8List>{};
    if (mode != WorksheetExportMode.practice) {
      final withImages =
          questions.where((q) => q.imagePath.isNotEmpty).toList();
      var done = 0;
      for (final q in withImages) {
        try {
          final f = File(q.imagePath);
          if (await f.exists()) {
            imageBytesMap[q.id] = await f.readAsBytes();
          }
        } catch (_) {
          // 单张图读取失败不阻塞导出，留空在排版时跳过。
        }
        done++;
        if (onProgress != null) onProgress(done, withImages.length);
      }
    } else {
      if (onProgress != null) onProgress(0, 0);
    }

    // 字号：根据 layout.fontSize 计算各元素字号（pt）。
    final basePt = layout.baseFontSizePt;
    final scale = basePt / 11.0;
    final titleFont = (26 * scale);
    final h2Font = (20 * scale);
    final subjectTitleFont = (18 * scale);
    final coverInfoFont = (12 * scale);
    final questionIndexFont = (13 * scale);
    final bodyFont = (11 * scale);
    final metaFont = (9 * scale);

    // ── 封面页 ──
    if (layout.includeCover) {
      doc.addPage(
        pw.Page(
          pageFormat: pageFormat,
          theme: theme,
          margin: _resolveMargin(layout),
          build: (ctx) => pw.Center(
            child: pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.center,
              crossAxisAlignment: pw.CrossAxisAlignment.center,
              children: <pw.Widget>[
                pw.Text(title,
                    style: pw.TextStyle(
                        fontSize: titleFont,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColor.fromInt(0xFF6366F1))),
                pw.SizedBox(height: 12),
                pw.Text('AI Wrong Notebook',
                    style: pw.TextStyle(
                        fontSize: 13 * scale,
                        color: PdfColor.fromInt(0xFF888888))),
                pw.SizedBox(height: 24),
                pw.Container(
                    width: 200,
                    height: 1,
                    color: PdfColor.fromInt(0xFFDDDDDD)),
                pw.SizedBox(height: 24),
                pw.Text('共 ${questions.length} 道错题',
                    style: pw.TextStyle(
                        fontSize: coverInfoFont,
                        color: PdfColor.fromInt(0xFF555555))),
                pw.SizedBox(height: 6),
                pw.Text('导出时间：$dateStr',
                    style: pw.TextStyle(
                        fontSize: coverInfoFont,
                        color: PdfColor.fromInt(0xFF555555))),
                pw.SizedBox(height: 6),
                pw.Text('涵盖 ${sortedSubjects.length} 个学科',
                    style: pw.TextStyle(
                        fontSize: coverInfoFont,
                        color: PdfColor.fromInt(0xFF555555))),
                pw.SizedBox(height: 36),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.center,
                  children: <pw.Widget>[
                    pw.Text('姓\u2003\u2003名：',
                        style: pw.TextStyle(fontSize: coverInfoFont)),
                    pw.Text(studentInfo?.displayName ?? '____________',
                        style: pw.TextStyle(fontSize: coverInfoFont)),
                    pw.SizedBox(width: 40),
                    pw.Text('班\u2003\u2003级：',
                        style: pw.TextStyle(fontSize: coverInfoFont)),
                    pw.Text(studentInfo?.className ?? '____________',
                        style: pw.TextStyle(fontSize: coverInfoFont)),
                  ],
                ),
                pw.SizedBox(height: 18),
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.center,
                  children: <pw.Widget>[
                    pw.Text('日\u2003\u2003期：',
                        style: pw.TextStyle(fontSize: coverInfoFont)),
                    pw.Text(dateStr,
                        style: pw.TextStyle(fontSize: coverInfoFont)),
                    pw.SizedBox(width: 40),
                    pw.Text('得\u2003\u2003分：',
                        style: pw.TextStyle(fontSize: coverInfoFont)),
                    pw.Text('____________',
                        style: pw.TextStyle(fontSize: coverInfoFont)),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    }

    // ── 目录页 ──
    if (layout.includeToc) {
      doc.addPage(
        pw.Page(
          pageFormat: pageFormat,
          theme: theme,
          margin: _resolveMargin(layout),
          build: (ctx) => pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: <pw.Widget>[
              pw.Text('目\u2003\u2003录',
                  style: pw.TextStyle(
                      fontSize: h2Font, fontWeight: pw.FontWeight.bold)),
              pw.SizedBox(height: 20),
              for (final subject in sortedSubjects) ...<pw.Widget>[
                pw.Padding(
                  padding: const pw.EdgeInsets.only(bottom: 6),
                  child: pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: <pw.Widget>[
                      pw.Text(subject.label,
                          style: pw.TextStyle(fontSize: coverInfoFont)),
                      pw.Text('${grouped[subject]!.length} 题',
                          style: pw.TextStyle(
                              fontSize: 10.5 * scale,
                              color: PdfColor.fromInt(0xFF888888))),
                    ],
                  ),
                ),
              ],
              pw.SizedBox(height: 18),
              pw.Text(
                  '掌握程度：● 待学习\u2003\u2003● 复习中\u2003\u2003● 已掌握',
                  style: pw.TextStyle(
                      fontSize: 10 * scale,
                      color: PdfColor.fromInt(0xFF888888))),
            ],
          ),
        ),
      );
    }

    // ── 题目页（MultiPage 自动分页） ──
    doc.addPage(
      pw.MultiPage(
        pageFormat: pageFormat,
        theme: theme,
        margin: _resolveMargin(layout),
        header: layout.includeHeader
            ? (ctx) => pw.Container(
                  alignment: pw.Alignment.center,
                  padding: const pw.EdgeInsets.only(bottom: 4),
                  decoration: const pw.BoxDecoration(
                    border: pw.Border(
                      bottom: pw.BorderSide(
                          color: PdfColor.fromInt(0xFFEEEEEE), width: 0.5),
                    ),
                  ),
                  child: pw.Text(title,
                      style: pw.TextStyle(
                          fontSize: metaFont,
                          color: PdfColor.fromInt(0xFF999999))),
                )
            : null,
        footer: layout.includeFooter
            ? (ctx) {
                final pageStr = PdfLayoutOptions.resolveFooter(
                  layout.footerText,
                  ctx.pageNumber,
                  ctx.pagesCount,
                  dateStr,
                  studentInfo?.displayName,
                );
                return pw.Container(
                  alignment: pw.Alignment.center,
                  child: pw.Text(pageStr,
                      style: pw.TextStyle(
                          fontSize: metaFont,
                          color: PdfColor.fromInt(0xFF999999))),
                );
              }
            : null,
        build: (ctx) {
          final widgets = <pw.Widget>[];
          int globalIndex = 0;
          for (final subject in sortedSubjects) {
            final list = grouped[subject]!;
            // 学科标题
            widgets.add(
              pw.Padding(
                padding: const pw.EdgeInsets.only(top: 8, bottom: 12),
                child: pw.Row(
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: <pw.Widget>[
                    pw.Container(
                        width: 4,
                        height: 22,
                        color: _subjectPdfColor(subject)),
                    pw.SizedBox(width: 8),
                    pw.Text(
                        '${subject.label}（${list.length} 题）',
                        style: pw.TextStyle(
                            fontSize: subjectTitleFont,
                            fontWeight: pw.FontWeight.bold)),
                  ],
                ),
              ),
            );
            // 题目块
            for (final q in list) {
              globalIndex++;
              widgets.add(
                _buildQuestionBlock(
                  index: globalIndex,
                  q: q,
                  mode: mode,
                  imageBytes: imageBytesMap[q.id],
                  bodyFont: bodyFont,
                  questionIndexFont: questionIndexFont,
                  metaFont: metaFont,
                ),
              );
            }
          }
          return widgets;
        },
      ),
    );

    // 写文件。
    final dir = await getApplicationDocumentsDirectory();
    final exportDir = Directory('${dir.path}/exports');
    if (!exportDir.existsSync()) {
      await exportDir.create(recursive: true);
    }
    final filename = HtmlExportService.buildExportFileName(questions,
        mode: mode, studentInfo: studentInfo, extension: 'pdf');
    final file = await ExportFileWriter.uniqueTarget(exportDir, filename);
    await ExportFileWriter.writeBytesAtomic(file, await doc.save());
    await HtmlExportService.cleanupExports(exportDir);
    return file;
  }

  /// 构造单个题目块（PdfWidget 树）。
  static pw.Widget _buildQuestionBlock({
    required int index,
    required QuestionRecord q,
    required WorksheetExportMode? mode,
    required Uint8List? imageBytes,
    required double bodyFont,
    required double questionIndexFont,
    required double metaFont,
  }) {
    final createDateStr =
        '${q.createdAt.month.toString().padLeft(2, '0')}/${q.createdAt.day.toString().padLeft(2, '0')}';
    final mastery = _masteryLabel(q.masteryLevel);

    final children = <pw.Widget>[];

    // 题头：#编号 + 掌握程度 badge + 复习次数 + 日期
    children.add(
      pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          pw.Text('#$index',
              style: pw.TextStyle(
                  fontSize: questionIndexFont,
                  fontWeight: pw.FontWeight.bold,
                  color: PdfColor.fromInt(0xFF6366F1))),
          pw.SizedBox(width: 6),
          if (q.isFavorite) ...<pw.Widget>[
            pw.Text('★',
                style: pw.TextStyle(
                    fontSize: questionIndexFont,
                    color: PdfColor.fromInt(0xFFD97706))),
            pw.SizedBox(width: 4),
          ],
          pw.Container(
            padding: const pw.EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: pw.BoxDecoration(
              color: _masteryBadgeBg(q.masteryLevel),
              borderRadius: pw.BorderRadius.circular(8),
            ),
            child: pw.Text(mastery,
                style: pw.TextStyle(
                    fontSize: metaFont,
                    color: _masteryBadgeFg(q.masteryLevel))),
          ),
          if (q.contentStatus != ContentStatus.ready) ...<pw.Widget>[
            pw.SizedBox(width: 4),
            pw.Text('(${_statusLabel(q.contentStatus)})',
                style: pw.TextStyle(
                    fontSize: metaFont,
                    color: PdfColor.fromInt(0xFF6B7280))),
          ],
          pw.Spacer(),
          if (q.reviewCount > 0)
            pw.Text('已复习 ${q.reviewCount} 次',
                style: pw.TextStyle(
                    fontSize: metaFont,
                    color: PdfColor.fromInt(0xFF9CA3AF))),
          pw.SizedBox(width: 8),
          pw.Text(createDateStr,
              style: pw.TextStyle(
                  fontSize: metaFont,
                  color: PdfColor.fromInt(0xFF9CA3AF))),
        ],
      ),
    );

    // 题干文本（保留 LaTeX 源码定界符）。
    final questionText = q.normalizedQuestionText.isNotEmpty
        ? q.normalizedQuestionText
        : q.extractedQuestionText;
    if (questionText.isNotEmpty) {
      children.add(
        pw.Container(
          width: double.infinity,
          margin: const pw.EdgeInsets.only(top: 6, bottom: 6),
          padding: const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: pw.BoxDecoration(
            color: PdfColor.fromInt(0xFFF5F3FF),
            borderRadius: pw.BorderRadius.circular(4),
          ),
          child: pw.Text(questionText,
              style: pw.TextStyle(
                  fontSize: bodyFont,
                  lineSpacing: 1.5,
                  color: PdfColor.fromInt(0xFF1F2937))),
        ),
      );
    }

    // 题图。
    if (imageBytes != null) {
      try {
        children.add(
          pw.Padding(
            padding: const pw.EdgeInsets.only(top: 6, bottom: 6),
            child: pw.Image(
              pw.MemoryImage(imageBytes),
              width: 320,
              height: 240,
              fit: pw.BoxFit.contain,
            ),
          ),
        );
      } catch (_) {
        // 图片解码失败忽略，不阻塞导出。
      }
    }

    // 答题模式：留白；否则输出分析块。
    if (mode == WorksheetExportMode.practice) {
      children.add(
        pw.Container(
          width: double.infinity,
          height: 80,
          margin: const pw.EdgeInsets.only(top: 6),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(
                color: PdfColor.fromInt(0xFFC7C3FF),
                width: 0.5,
                style: pw.BorderStyle.dashed),
            color: PdfColor.fromInt(0xFFFAFAFF),
            borderRadius: pw.BorderRadius.circular(4),
          ),
        ),
      );
    } else {
      final analysisWidgets = _buildAnalysisWidgets(
        q: q,
        mode: mode,
        bodyFont: bodyFont,
        metaFont: metaFont,
      );
      children.addAll(analysisWidgets);
    }

    return pw.Container(
      margin: const pw.EdgeInsets.only(bottom: 12),
      padding: const pw.EdgeInsets.only(bottom: 10),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(
              color: PdfColor.fromInt(0xFFE5E7EB), width: 0.5),
        ),
      ),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: children,
      ),
    );
  }

  /// 构造题目分析块 widgets（知识点 / 错因 / 答案 / 步骤 / 建议）。
  static List<pw.Widget> _buildAnalysisWidgets({
    required QuestionRecord q,
    required WorksheetExportMode? mode,
    required double bodyFont,
    required double metaFont,
  }) {
    final analysis = q.analysisResult;
    if (analysis == null) return const <pw.Widget>[];

    final widgets = <pw.Widget>[];
    final labelStyle = pw.TextStyle(
        fontSize: metaFont, fontWeight: pw.FontWeight.bold);
    final bodyStyle = pw.TextStyle(
        fontSize: metaFont, color: PdfColor.fromInt(0xFF1F2937));

    if (mode == null || mode == WorksheetExportMode.answer) {
      final kps = [...analysis.knowledgePoints, ...analysis.aiTags]
          .take(5)
          .join('  ·  ');
      if (kps.isNotEmpty) {
        widgets.add(_analysisRow('知识点', kps, labelStyle, bodyStyle,
            labelColor: PdfColor.fromInt(0xFF7C3AED)));
      }
      if (analysis.mistakeReason.isNotEmpty) {
        widgets.add(_analysisRow(
            '错因分析', analysis.mistakeReason, labelStyle, bodyStyle));
      }
      if (analysis.finalAnswer.isNotEmpty) {
        widgets.add(_analysisRow('正确答案', analysis.finalAnswer, labelStyle,
            bodyStyle,
            labelColor: PdfColor.fromInt(0xFF16A34A)));
      }
      if (analysis.steps.isNotEmpty) {
        final stepWidgets = <pw.Widget>[];
        for (var i = 0; i < analysis.steps.length; i++) {
          stepWidgets.add(
            pw.Padding(
              padding: const pw.EdgeInsets.only(bottom: 2),
              child: pw.Text(
                '${i + 1}. ${analysis.steps[i]}',
                style: pw.TextStyle(
                    fontSize: metaFont,
                    color: PdfColor.fromInt(0xFF1F2937)),
              ),
            ),
          );
        }
        widgets.add(
          pw.Container(
            width: double.infinity,
            margin: const pw.EdgeInsets.only(top: 4),
            padding: const pw.EdgeInsets.only(left: 8),
            decoration: const pw.BoxDecoration(
              border: pw.Border(
                left: pw.BorderSide(
                    color: PdfColor.fromInt(0xFF6366F1), width: 1.5),
              ),
            ),
            child: pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: <pw.Widget>[
                pw.Text('解题步骤',
                    style: pw.TextStyle(
                        fontSize: metaFont,
                        fontWeight: pw.FontWeight.bold,
                        color: PdfColor.fromInt(0xFF6366F1))),
                pw.SizedBox(height: 4),
                ...stepWidgets,
              ],
            ),
          ),
        );
      }
      if (analysis.studyAdvice.isNotEmpty) {
        widgets.add(_analysisRow('学习建议', analysis.studyAdvice, labelStyle,
            bodyStyle,
            labelColor: PdfColor.fromInt(0xFFD97706)));
      }
    } else if (mode == WorksheetExportMode.correction) {
      if (analysis.mistakeReason.isNotEmpty) {
        widgets.add(_analysisRow(
            '错因分析', analysis.mistakeReason, labelStyle, bodyStyle));
      }
      if (analysis.studyAdvice.isNotEmpty) {
        widgets.add(_analysisRow('订正提示', analysis.studyAdvice, labelStyle,
            bodyStyle,
            labelColor: PdfColor.fromInt(0xFFD97706)));
      }
      widgets.add(
        pw.Container(
          width: double.infinity,
          height: 80,
          margin: const pw.EdgeInsets.only(top: 6),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(
                color: PdfColor.fromInt(0xFFC7C3FF),
                width: 0.5,
                style: pw.BorderStyle.dashed),
            color: PdfColor.fromInt(0xFFFAFAFF),
            borderRadius: pw.BorderRadius.circular(4),
          ),
        ),
      );
    }
    return widgets;
  }

  static pw.Widget _analysisRow(
    String label,
    String content,
    pw.TextStyle labelStyle,
    pw.TextStyle bodyStyle, {
    PdfColor? labelColor,
  }) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(top: 3),
      child: pw.Row(
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: <pw.Widget>[
          pw.Text('$label：',
              style: pw.TextStyle(
                  fontSize: labelStyle.fontSize,
                  fontWeight: pw.FontWeight.bold,
                  color: labelColor ?? PdfColor.fromInt(0xFF1F2937))),
          pw.Expanded(
            child: pw.Text(content, style: bodyStyle),
          ),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 桌面端：分享 / 打印入口
  // ─────────────────────────────────────────────────────────────────────────

  /// 桌面端：原生生成 PDF 后调起系统打印对话框（含「另存为 PDF」）。
  /// 打印失败时降级为系统分享，再失败回退浏览器打开 HTML。
  static Future<void> _sharePdfDesktop(
    BuildContext context,
    List<QuestionRecord> questions, {
    required String title,
    WorksheetExportMode? mode,
    ExportStudentInfo? studentInfo,
    String? watermark,
    PdfLayoutOptions? layoutOptions,
  }) async {
    final layout = layoutOptions ?? PdfLayoutOptions.defaults;
    File? pdfFile;
    File? htmlFile;
    try {
      // 优先：pdf 包原生生成 PDF。
      pdfFile = await generatePdf(
        questions,
        title: title,
        mode: mode,
        studentInfo: studentInfo,
        watermark: watermark,
        layoutOptions: layout,
      );
    } catch (e) {
      // pdf 包生成失败时降级为 HTML 路径。
      pdfFile = null;
      debugPrint('[PdfExportService] 原生 PDF 生成失败，降级 HTML: $e');
    }

    try {
      if (pdfFile != null) {
        // 用系统打印对话框预览（含「另存为 PDF」）。
        final bytes = await pdfFile.readAsBytes();
        final printed = await Printing.layoutPdf(
          name: pdfFile.uri.pathSegments.isEmpty
              ? title
              : pdfFile.uri.pathSegments.last,
          onLayout: (_) => bytes,
          format: _resolvePageFormat(layout),
        );
        if (!printed) {
          // 用户取消或打印系统不可用，降级为系统分享 PDF 文件。
          if (!await _shareDesktopFile(pdfFile)) {
            // 分享也失败，回退浏览器打开 HTML。
            htmlFile = await _generateDesktopHtmlFallback(
              questions,
              title: title,
              mode: mode,
              studentInfo: studentInfo,
              watermark: watermark,
              layout: layout,
            );
            await _openInDesktopBrowser(htmlFile);
          }
        }
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('已调起系统打印对话框，可在对话框中选择「另存为 PDF」'),
          ),
        );
        return;
      }
    } catch (e) {
      debugPrint('[PdfExportService] 打印对话框失败: $e');
    }

    // 完全降级：HTML + 浏览器。
    try {
      htmlFile = await _generateDesktopHtmlFallback(
        questions,
        title: title,
        mode: mode,
        studentInfo: studentInfo,
        watermark: watermark,
        layout: layout,
      );
      if (!await _shareDesktopFile(htmlFile)) {
        await _openInDesktopBrowser(htmlFile);
      }
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('桌面端原生 PDF 不可用，已用浏览器打开 HTML，可在浏览器中打印为 PDF'),
        ),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('导出失败: $e')),
        );
      }
    }
  }

  /// 桌面端 HTML 降级路径：生成带 layoutOptions 的 HTML 文件。
  static Future<File> _generateDesktopHtmlFallback(
    List<QuestionRecord> questions, {
    required String title,
    WorksheetExportMode? mode,
    ExportStudentInfo? studentInfo,
    String? watermark,
    required PdfLayoutOptions layout,
  }) async {
    final result = await HtmlExportService.generateHtml(
      questions,
      title: title,
      mode: mode,
      studentInfo: studentInfo,
      contentOptions: ExportContentOptions.all,
      watermark: watermark,
      layoutOptions: layout,
    );
    return File(result.filePath);
  }

  /// 桌面端调起系统分享单个文件。返回是否成功（false 表示需要回退浏览器）。
  static Future<bool> _shareDesktopFile(File file) async {
    try {
      await Share.shareXFiles([XFile(file.path)]);
      return true;
    } catch (_) {
      // share_plus 在某些桌面环境（无 DBus/分享面板）会抛错，回退浏览器。
      return false;
    }
  }

  /// 用系统默认浏览器/应用打开本地文件。
  static Future<void> _openInDesktopBrowser(File file) async {
    final path = file.path;
    if (Platform.isMacOS) {
      await Process.run('open', [path]);
    } else if (Platform.isWindows) {
      await Process.run('cmd', ['/c', 'start', '', path]);
    } else {
      // Linux 及其它桌面环境。
      await Process.run('xdg-open', [path]);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 字体与排版辅助
  // ─────────────────────────────────────────────────────────────────────────

  /// 加载中文字体：优先 `PdfGoogleFonts.notoSansSCRegular()`（首次下载并缓存），
  /// 离线/失败时回退 `Font.helvetica()`（中文字符将渲染为方框，但 PDF 仍可生成）。
  static Future<pw.Font> _loadCjkFont({bool bold = false}) async {
    try {
      if (bold) {
        return await PdfGoogleFonts.notoSansSCBold();
      }
      return await PdfGoogleFonts.notoSansSCRegular();
    } catch (_) {
      // 离线或网络不可用时回退 Helvetica。
      return pw.Font.helvetica();
    }
  }

  /// 把 [PdfLayoutOptions] 映射为 `pdf` 包的 [PdfPageFormat]。
  /// orientation 已通过 width/height 交换处理。
  static PdfPageFormat _resolvePageFormat(PdfLayoutOptions layout) {
    final (tbMm, lrMm) = layout.cssMargin;
    final tb = tbMm * PdfPageFormat.mm;
    final lr = lrMm * PdfPageFormat.mm;
    PdfPageFormat base;
    switch (layout.pageSize) {
      case PdfPageSize.a4:
        base = PdfPageFormat.a4;
      case PdfPageSize.a5:
        base = PdfPageFormat.a5;
      case PdfPageSize.letter:
        base = PdfPageFormat.letter;
      case PdfPageSize.b5:
        // pdf 包没有内置 B5，手工指定 176x250mm。
        base = PdfPageFormat(176 * PdfPageFormat.mm, 250 * PdfPageFormat.mm);
    }
    final oriented = layout.orientation == PdfOrientation.landscape
        ? base.landscape
        : base.portrait;
    // 用 layout 的边距覆盖默认 marginAll，保持与 CSS @page margin 一致。
    return oriented.copyWith(
      marginTop: tb,
      marginBottom: tb,
      marginLeft: lr,
      marginRight: lr,
    );
  }

  /// MultiPage / Page 的 margin 参数（与 _resolvePageFormat 边距保持一致）。
  static pw.EdgeInsets _resolveMargin(PdfLayoutOptions layout) {
    final (tbMm, lrMm) = layout.cssMargin;
    return pw.EdgeInsets.fromLTRB(
      lrMm * PdfPageFormat.mm,
      tbMm * PdfPageFormat.mm,
      lrMm * PdfPageFormat.mm,
      tbMm * PdfPageFormat.mm,
    );
  }

  static PdfColor _subjectPdfColor(Subject subject) {
    final c = subject.color;
    return PdfColor.fromInt(
      0xFF000000 |
          ((c.r * 255).round() << 16) |
          ((c.g * 255).round() << 8) |
          (c.b * 255).round(),
    );
  }

  static PdfColor _masteryBadgeBg(MasteryLevel level) {
    switch (level) {
      case MasteryLevel.newQuestion:
        return PdfColor.fromInt(0xFFFEE2E2);
      case MasteryLevel.reviewing:
        return PdfColor.fromInt(0xFFFEF3C7);
      case MasteryLevel.mastered:
        return PdfColor.fromInt(0xFFDCFCE7);
    }
  }

  static PdfColor _masteryBadgeFg(MasteryLevel level) {
    switch (level) {
      case MasteryLevel.newQuestion:
        return PdfColor.fromInt(0xFFDC2626);
      case MasteryLevel.reviewing:
        return PdfColor.fromInt(0xFFD97706);
      case MasteryLevel.mastered:
        return PdfColor.fromInt(0xFF16A34A);
    }
  }

  static String _masteryLabel(MasteryLevel level) => switch (level) {
        MasteryLevel.newQuestion => '待学习',
        MasteryLevel.reviewing => '复习中',
        MasteryLevel.mastered => '已掌握',
      };

  static String _statusLabel(ContentStatus status) => switch (status) {
        ContentStatus.processing => '处理中',
        ContentStatus.analyzing => '分析中',
        ContentStatus.needsConfirmation => '待人工确认',
        ContentStatus.ready => '已完成',
        ContentStatus.failed => '识别失败',
        ContentStatus.analysisFailed => '分析失败',
      };
}
