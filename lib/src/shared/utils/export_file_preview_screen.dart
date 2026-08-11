import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:printing/printing.dart';
import 'package:smart_wrong_notebook/src/shared/utils/app_share_service.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// 预览已经生成的导出文件。
/// HTML 使用 WebView，PDF 使用打印预览，其余文本格式显示可读内容。
class ExportFilePreviewScreen extends StatefulWidget {
  const ExportFilePreviewScreen({super.key, required this.file});

  final File file;

  @override
  State<ExportFilePreviewScreen> createState() => _ExportFilePreviewScreenState();
}

class _ExportFilePreviewScreenState extends State<ExportFilePreviewScreen> {
  bool _loading = true;
  String? _error;
  WebViewController? _webController;
  Uint8List? _pdfBytes;
  String? _text;

  String get _extension {
    final name = widget.file.path.toLowerCase();
    final dot = name.lastIndexOf('.');
    return dot < 0 ? '' : name.substring(dot + 1);
  }

  bool get _isHtml => _extension == 'html' || _extension == 'htm';
  bool get _isPdf => _extension == 'pdf';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      if (!await widget.file.exists()) {
        throw StateError('文件不存在');
      }
      if (_isHtml) {
        _webController = WebViewController()
          ..setJavaScriptMode(JavaScriptMode.unrestricted)
          ..loadFile(widget.file.path);
      } else if (_isPdf) {
        _pdfBytes = await widget.file.readAsBytes();
      } else {
        final bytes = await widget.file.readAsBytes();
        _text = utf8.decode(bytes, allowMalformed: true);
      }
      if (mounted) setState(() => _loading = false);
    } catch (e) {
      if (mounted) setState(() { _loading = false; _error = '$e'; });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('文件预览'),
        actions: <Widget>[
          IconButton(
            icon: const Icon(CupertinoIcons.share),
            tooltip: '分享文件',
            onPressed: _loading || _error != null
                ? null
                : () => _share(context),
          ),
        ],
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text('预览失败：$_error', textAlign: TextAlign.center),
      ));
    }
    if (_isHtml && _webController != null) {
      return WebViewWidget(controller: _webController!);
    }
    if (_isPdf && _pdfBytes != null) {
      return PdfPreview(
        build: (_) async => _pdfBytes!,
        allowPrinting: false,
        allowSharing: false,
        canChangePageFormat: false,
        canChangeOrientation: false,
        pdfFileName: widget.file.uri.pathSegments.last,
      );
    }
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: SelectableText(_text ?? '该文件没有可预览内容'),
    );
  }

  Future<void> _share(BuildContext context) async {
    // 复用系统文件分享，预览页不附带文本内容。
    await AppShareService.shareFile(context, widget.file.path);
  }
}
