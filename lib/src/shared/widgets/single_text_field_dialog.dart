import 'package:flutter/material.dart';

/// 弹出一个单 [TextField] 对话框，收集用户输入。
///
/// 内部创建 [TextEditingController]，[showDialog] 关闭后通过 `finally` 自动
/// dispose，避免调用方手写模板代码。用户点击确认按钮（或单行模式下按 Enter
/// 提交）时返回 trim 后的文本；用户取消（点击取消按钮、点击屏障或按返回键）
/// 时返回 null。
///
/// 用于替换重复的"创建 controller → showDialog → AlertDialog → 取消/保存
/// 按钮 → await repo.update → invalidate → pop"模板。多字段表单或需要自定义
/// 内容预览（如 `_editLearningContext`、`_splitAt`）的对话框不适用，请直接
/// 使用 [showDialog]。
Future<String?> showSingleTextFieldDialog({
  required BuildContext context,
  required String title,
  String initialText = '',
  String? hintText,
  String? labelText,
  int? maxLines,
  int? minLines,
  int? maxLength,
  bool autofocus = false,
  bool obscureText = false,
  bool barrierDismissible = true,
  String confirmText = '保存',
  String cancelText = '取消',
}) async {
  final controller = TextEditingController(text: initialText);
  try {
    return await showDialog<String>(
      context: context,
      barrierDismissible: barrierDismissible,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: controller,
          autofocus: autofocus,
          obscureText: obscureText,
          // obscureText 模式下 Flutter 强制 maxLines = 1，这里显式处理避免报错。
          maxLines: obscureText ? 1 : maxLines,
          minLines: obscureText ? null : minLines,
          maxLength: maxLength,
          decoration: InputDecoration(
            hintText: hintText,
            labelText: labelText,
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (value) => Navigator.pop(ctx, value.trim()),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(cancelText),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: Text(confirmText),
          ),
        ],
      ),
    );
  } finally {
    controller.dispose();
  }
}
