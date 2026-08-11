import 'dart:io';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

/// 统一系统分享入口：校验文件、捕获 iPad 锚点错误，并把分享结果反馈给用户。
class AppShareService {
  const AppShareService._();

  static Future<ShareResult?> shareFile(
    BuildContext context,
    String path, {
    bool showFeedback = true,
  }) async {
    if (!context.mounted) return null;
    final file = File(path);
    if (!await file.exists()) {
      _feedback(context, '分享失败：文件不存在或已被清理');
      return null;
    }
    if (!context.mounted) return null;
    final renderObject = context.findRenderObject();
    final box = renderObject is RenderBox && renderObject.hasSize
        ? renderObject
        : null;
    final origin = box == null
        ? null
        : box.localToGlobal(Offset.zero) & box.size;
    try {
      final result = await Future.any<ShareResult?>(<Future<ShareResult?>>[
        Share.shareXFiles(
          [XFile(file.path)],
          sharePositionOrigin: origin,
        ),
        Future<ShareResult?>.delayed(
          const Duration(seconds: 30),
          () => null,
        ),
      ]);
      if (showFeedback && context.mounted) {
        final message = result == null
            ? '分享面板响应超时，文件仍保存在导出历史中'
            : switch (result.status) {
                ShareResultStatus.success => '分享面板已完成',
                ShareResultStatus.dismissed => '已取消分享，文件仍保存在导出历史中',
                ShareResultStatus.unavailable => '当前设备暂不支持系统分享，文件已保存在导出历史中',
              };
        _feedback(context, message);
      }
      return result;
    } catch (error) {
      if (context.mounted) {
        _feedback(context, '分享失败，文件已保存在导出历史中');
      }
      return null;
    }
  }

  static void _feedback(BuildContext context, String message) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
