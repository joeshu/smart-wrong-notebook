import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/shared/utils/export_content_options.dart';
import 'package:smart_wrong_notebook/src/shared/utils/html_export_service.dart';
import 'package:smart_wrong_notebook/src/shared/utils/pdf_export_service.dart';
import 'package:smart_wrong_notebook/src/shared/utils/worksheet_export_mode.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// 导出前的 HTML 预览页：用 WebView 渲染最终报告，并提供分享 HTML / 导出 PDF。
///
/// 预览页生成 HTML 时会写入 [HtmlExportCache]，后续点击"导出 PDF"时
/// [PdfExportService] 会优先命中缓存，避免同一份 HTML 被生成两次。
class HtmlPreviewScreen extends StatefulWidget {
  const HtmlPreviewScreen({
    super.key,
    required this.questions,
    this.title = '错题本整理报告',
    this.mode,
    this.studentInfo,
  });

  final List<QuestionRecord> questions;
  final String title;
  final WorksheetExportMode? mode;
  final ExportStudentInfo? studentInfo;

  @override
  State<HtmlPreviewScreen> createState() => _HtmlPreviewScreenState();
}

class _HtmlPreviewScreenState extends State<HtmlPreviewScreen> {
  WebViewController? _controller;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      // 传入 contentOptions 启用缓存：预览页生成的 HTML 会写入 HtmlExportCache，
      // 之后用户点"导出 PDF"时 PdfExportService 直接命中缓存，不再重新生成。
      final result = await HtmlExportService.generateHtml(
        widget.questions,
        title: widget.title,
        mode: widget.mode,
        studentInfo: widget.studentInfo,
        contentOptions: ExportContentOptions.all,
      );
      _controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..loadFile(result.filePath);
      if (!mounted) return;
      setState(() => _loading = false);
      if (result.failureHint.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('预览已生成（${result.failureHint}）')),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '$e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('导出预览'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(CupertinoIcons.share),
            tooltip: '分享 HTML',
            onPressed: _loading || _error != null
                ? null
                : () => HtmlExportService.shareHtml(
                      context,
                      widget.questions,
                      title: widget.title,
                      mode: widget.mode,
                      studentInfo: widget.studentInfo,
                      contentOptions: ExportContentOptions.all,
                    ),
          ),
          IconButton(
            icon: const Icon(CupertinoIcons.doc),
            tooltip: '导出 PDF',
            onPressed: _loading || _error != null
                ? null
                : () async {
                    await PdfExportService.sharePdf(
                      context,
                      widget.questions,
                      title: widget.title,
                      mode: widget.mode,
                      studentInfo: widget.studentInfo,
                    );
                    // Phase 11-6：导出后提供「返回调整」快捷入口，
                    // 保留预览页栈，用户可选择继续预览或返回筛选页修改。
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: const Text('PDF 导出完成'),
                        duration: const Duration(seconds: 4),
                        action: SnackBarAction(
                          label: '返回调整',
                          onPressed: () => Navigator.of(context).maybePop(),
                        ),
                      ),
                    );
                  },
          ),
          // Phase 11-6：跳转导出工作台，预填当前预览的题目 ID
          PopupMenuButton<String>(
            icon: const Icon(CupertinoIcons.ellipsis),
            tooltip: '导出为其他格式',
            enabled: !_loading && _error == null && widget.questions.isNotEmpty,
            onSelected: (value) {
              if (value == 'workbench') {
                final ids = widget.questions.map((q) => q.id).join(',');
                context.push('/settings/export-workbench?ids=$ids');
              }
            },
            itemBuilder: (ctx) => const <PopupMenuEntry<String>>[
              PopupMenuItem<String>(
                value: 'workbench',
                child: Row(children: <Widget>[
                  Icon(CupertinoIcons.square_grid_2x2, size: 18),
                  SizedBox(width: 8),
                  Text('导出为其他格式'),
                ]),
              ),
            ],
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('预览生成失败：$_error',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.red)),
        ),
      );
    }
    if (_controller == null) {
      return const Center(child: Text('无法初始化预览'));
    }
    return WebViewWidget(controller: _controller!);
  }
}
