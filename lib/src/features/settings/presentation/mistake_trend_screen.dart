import 'dart:io';
import 'package:smart_wrong_notebook/src/shared/ui/app_colors.dart';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_native_html_to_pdf/flutter_native_html_to_pdf.dart'
    as html2pdf;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:smart_wrong_notebook/src/shared/utils/mistake_trend_aggregator.dart';
import 'package:smart_wrong_notebook/src/shared/utils/mistake_trend_html.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// 错因趋势热力图预览页：聚合最近 30 天数据 → 生成 HTML → WebView 渲染。
///
/// 顶部 AppBar 提供「导出 PDF」与「分享」操作：
/// - 导出 PDF：移动端用 `flutter_native_html_to_pdf` 渲染；桌面端降级为
///   系统浏览器打开 HTML（用户可在浏览器中打印为 PDF）。
/// - 分享：所有平台用 `share_plus` 分享 HTML 文件。
class MistakeTrendScreen extends ConsumerStatefulWidget {
  const MistakeTrendScreen({super.key, this.studentName});

  /// 顶部姓名栏；为空时不显示。
  final String? studentName;

  @override
  ConsumerState<MistakeTrendScreen> createState() =>
      _MistakeTrendScreenState();
}

class _MistakeTrendScreenState extends ConsumerState<MistakeTrendScreen> {
  WebViewController? _controller;
  bool _loading = true;
  String? _error;
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
      final data = await aggregateMistakeTrend(ref);
      final html = generateMistakeTrendHtmlSync(
        data,
        studentName: widget.studentName,
      );
      // 写入临时文件，用 loadFile 加载（与 HtmlPreviewScreen 保持一致）。
      final dir = await getTemporaryDirectory();
      final file = File('${dir.path}/mistake_trend_preview.html');
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
    if (_htmlContent.isEmpty) return;
    if (_isDesktop) {
      await _exportPdfDesktop();
      return;
    }
    await _exportPdfMobile();
  }

  /// 移动端：用 flutter_native_html_to_pdf 把 HTML 转 PDF，再调起系统分享。
  Future<void> _exportPdfMobile() async {
    if (!mounted) return;
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
      final name = _formatPdfName();
      final converter = html2pdf.HtmlToPdfConverter();
      final file = await converter.convertHtmlToPdf(
        html: _htmlContent,
        targetDirectory: exportDir.path,
        targetName: name,
        pageSize: html2pdf.PdfPageSize.a4,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      final box = context.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) return;
      final origin = box.localToGlobal(Offset.zero) & box.size;
      await Share.shareXFiles(
        [XFile(file.path)],
        sharePositionOrigin: origin,
      );
    } catch (e) {
      if (!mounted) return;
      Navigator.of(context).pop();
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
          content: Text('已在浏览器打开热力图，可在浏览器中选择「打印 → 另存为 PDF」'),
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
    final path = _htmlFilePath;
    if (path == null) return;
    try {
      final box = context.findRenderObject() as RenderBox?;
      final origin = box == null || !box.hasSize
          ? null
          : box.localToGlobal(Offset.zero) & box.size;
      await Share.shareXFiles(
        [XFile(path)],
        sharePositionOrigin: origin,
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('分享失败: $e')),
      );
    }
  }

  /// PDF 文件名：错因趋势热力图_YYYYMMDD_HHmm.pdf
  String _formatPdfName() {
    final now = DateTime.now();
    final y = now.year.toString();
    final m = now.month.toString().padLeft(2, '0');
    final d = now.day.toString().padLeft(2, '0');
    final hh = now.hour.toString().padLeft(2, '0');
    final mm = now.minute.toString().padLeft(2, '0');
    return '错因趋势热力图_${y}${m}${d}_$hh$mm';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('错因趋势热力图'),
        leading: IconButton(
          icon: const Icon(CupertinoIcons.chevron_left),
          onPressed: () => Navigator.of(context).pop(),
        ),
        actions: <Widget>[
          IconButton(
            icon: const Icon(CupertinoIcons.share),
            tooltip: '分享',
            onPressed: _loading || _error != null ? null : _onShare,
          ),
          IconButton(
            icon: const Icon(CupertinoIcons.doc),
            tooltip: '导出 PDF',
            onPressed: _loading || _error != null ? null : _onExportPdf,
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
            Text('正在生成错因趋势热力图…'),
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
