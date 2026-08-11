import 'dart:io';
import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_colors.dart';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_native_html_to_pdf/flutter_native_html_to_pdf.dart'
    as html2pdf;
import 'package:path_provider/path_provider.dart';
import 'package:smart_wrong_notebook/src/shared/utils/app_share_service.dart';
import 'package:smart_wrong_notebook/src/shared/utils/weekly_report_aggregator.dart';
import 'package:smart_wrong_notebook/src/shared/utils/weekly_report_html.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// 学情周报预览页：聚合本周数据 → 生成 HTML → WebView 渲染。
///
/// 顶部 AppBar 提供「导出 PDF」与「分享」操作：
/// - 导出 PDF：移动端用 `flutter_native_html_to_pdf` 渲染；桌面端降级为
///   系统浏览器打开 HTML（用户可在浏览器中打印为 PDF）。
/// - 分享：所有平台用 `share_plus` 分享 HTML 文件。
class WeeklyReportScreen extends ConsumerStatefulWidget {
  const WeeklyReportScreen({super.key, this.studentName, this.watermark});

  /// 封面学生姓名；为空时显示下划线占位。
  final String? studentName;

  /// 可选水印文本，叠加在每页固定位置。
  final String? watermark;

  @override
  ConsumerState<WeeklyReportScreen> createState() =>
      _WeeklyReportScreenState();
}

class _WeeklyReportScreenState extends ConsumerState<WeeklyReportScreen> {
  WebViewController? _controller;
  bool _loading = true;
  String? _error;
  bool _sharing = false;
  String? _htmlFilePath;
  String _htmlContent = '';

  @override
  void initState() {
    super.initState();
    // 在首帧后触发聚合，确保 ref 可用。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _init();
    });
  }

  Future<void> _init() async {
    try {
      final data = await aggregateWeeklyReport(ref);
      final html = generateWeeklyReportHtmlSync(
        data,
        studentName: widget.studentName,
        watermark: widget.watermark,
        visualStyle: ref.read(appVisualStyleProvider),
      );
      // 写入临时文件，用 loadFile 加载（与 HtmlPreviewScreen 保持一致）。
      final dir = await getTemporaryDirectory();
      final file = File(
          '${dir.path}/weekly_report_${DateTime.now().millisecondsSinceEpoch}.html');
      await file.writeAsString(html, flush: true);
      _htmlContent = html;
      _htmlFilePath = file.path;
      _controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..loadFile(file.path);
      if (!mounted) return;
      setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = '$e';
        });
      }
    }
  }

  /// 是否为桌面平台（与 PdfExportService.isDesktopPlatform 判断一致）。
  bool get _isDesktop =>
      !kIsWeb && (Platform.isWindows || Platform.isMacOS || Platform.isLinux);

  Future<void> _onExportPdf() async {
    if (_sharing || _htmlContent.isEmpty) return;
    setState(() => _sharing = true);
    try {
      if (_isDesktop) {
        await _exportPdfDesktop();
        return;
      }
      await _exportPdfMobile();
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  /// 移动端：用 flutter_native_html_to_pdf 把 HTML 转 PDF，再调起系统分享。
  Future<void> _exportPdfMobile() async {
    if (!mounted) return;
    var progressDialogOpen = true;
    void closeProgressDialog() {
      if (!progressDialogOpen || !mounted) return;
      progressDialogOpen = false;
      Navigator.of(context).pop();
    }
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const PopScope(
        canPop: false,
        child: AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              CircularProgressIndicator(),
              SizedBox(height: 12),
              Text('正在生成 PDF…'),
            ],
          ),
        ),
      ),
    );
    try {
      final dir = await getApplicationDocumentsDirectory();
      final exportDir = Directory('${dir.path}/exports');
      if (!exportDir.existsSync()) {
        await exportDir.create(recursive: true);
      }
      final name =
          'weekly_report_${DateTime.now().millisecondsSinceEpoch}';
      final converter = html2pdf.HtmlToPdfConverter();
      final file = await converter.convertHtmlToPdf(
        html: _htmlContent,
        targetDirectory: exportDir.path,
        targetName: name,
        pageSize: html2pdf.PdfPageSize.a4,
      );
      if (!mounted) return;
      closeProgressDialog();
      await AppShareService.shareFile(
        context,
        file.path,
      );
    } catch (e) {
      if (!mounted) return;
      closeProgressDialog();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导出 PDF 失败: $e')),
      );
    }
  }

  /// 桌面端：flutter_native_html_to_pdf 不可用，写 HTML 文件并调起系统浏览器
  /// 打开，用户可在浏览器中 Ctrl+P 打印为 PDF。失败时降级为分享 HTML 文件。
  Future<void> _exportPdfDesktop() async {
    final path = _htmlFilePath;
    if (path == null) return;
    try {
      await _openInDesktopBrowser(File(path));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已在浏览器打开周报，可在浏览器中选择「打印 → 另存为 PDF」'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('导出失败: $e')),
      );
    }
  }

  /// 用系统默认浏览器打开本地 HTML 文件。
  Future<void> _openInDesktopBrowser(File file) async {
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

  Future<void> _onShare() async {
    if (_sharing) return;
    final path = _htmlFilePath;
    if (path == null) return;
    setState(() => _sharing = true);
    try {
      await AppShareService.shareFile(
        context,
        path,
      );
    } finally {
      if (mounted) setState(() => _sharing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('本周学情报告'),
        leading: IconButton(
          icon: const Icon(CupertinoIcons.chevron_left),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: <Widget>[
          IconButton(
            icon: const Icon(CupertinoIcons.share),
            tooltip: '分享',
            onPressed: _loading || _error != null || _sharing ? null : _onShare,
          ),
          IconButton(
            icon: const Icon(CupertinoIcons.doc),
            tooltip: '导出 PDF',
            onPressed: _loading || _error != null || _sharing ? null : _onExportPdf,
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text('正在生成本周学情…'),
          ],
        ),
      );
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Icon(CupertinoIcons.exclamationmark_circle,
                  size: 48, color: AppColors.danger),
              const SizedBox(height: 12),
              Text(
                '生成失败：$_error',
                textAlign: TextAlign.center,
                style: const TextStyle(color: AppColors.danger),
              ),
              const SizedBox(height: 16),
              OutlinedButton(
                onPressed: () {
                  setState(() {
                    _loading = true;
                    _error = null;
                  });
                  _init();
                },
                child: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }
    if (_controller == null) {
      return const Center(child: Text('无法初始化预览'));
    }
    return WebViewWidget(controller: _controller!);
  }
}
