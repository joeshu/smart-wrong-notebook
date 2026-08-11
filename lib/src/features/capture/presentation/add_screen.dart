import 'package:flutter/material.dart';
import 'package:smart_wrong_notebook/src/core/constants/app_strings.dart';
import 'package:smart_wrong_notebook/src/features/capture/presentation/capture_entry_sheet.dart';

/// 「添加」Tab 根页面。
///
/// Phase 5：作为底部导航 6 入口之一，复用 [CaptureEntrySheet] 的录入能力，
/// 隐藏 sheet 场景的关闭按钮。
class AddScreen extends StatelessWidget {
  const AddScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.addTab)),
      body: const CaptureEntrySheet(showCloseButton: false),
    );
  }
}
