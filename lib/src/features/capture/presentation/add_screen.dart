import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_wrong_notebook/src/core/constants/app_strings.dart';
import 'package:smart_wrong_notebook/src/features/capture/presentation/capture_entry_sheet.dart';

/// 「添加」页。
///
/// 复用 [CaptureEntrySheet] 的录入能力，隐藏 sheet 场景的关闭按钮与拖拽条；
/// 由 AppBar 提供明确的返回入口。
class AddScreen extends StatelessWidget {
  const AddScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(AppStrings.addTab),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
          tooltip: '返回',
          onPressed: () {
            if (context.canPop()) {
              context.pop();
              return;
            }
            context.go('/');
          },
        ),
      ),
      body: const CaptureEntrySheet(showCloseButton: false),
    );
  }
}
