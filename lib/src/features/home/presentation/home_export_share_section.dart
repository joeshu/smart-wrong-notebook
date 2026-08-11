import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_ui.dart';

class HomeExportShareSection extends StatelessWidget {
  const HomeExportShareSection({required this.onExport, required this.onShare, super.key});

  final VoidCallback onExport;
  final VoidCallback onShare;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      padding: const EdgeInsets.all(AppSpace.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(children: <Widget>[
            Icon(CupertinoIcons.square_arrow_up, size: 18, color: scheme.primary),
            const SizedBox(width: AppSpace.sm),
            const Text('导出与分享', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
          ]),
          const SizedBox(height: AppSpace.xs),
          Text('整理错题、复习报告和学习资料，导出后可随时分享。',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
          const SizedBox(height: AppSpace.md),
          Row(children: <Widget>[
            Expanded(child: FilledButton.icon(
              onPressed: onExport,
              icon: const Icon(CupertinoIcons.square_arrow_up, size: 16),
              label: const Text('导出资料'),
            )),
            const SizedBox(width: AppSpace.sm),
            Expanded(child: OutlinedButton.icon(
              onPressed: onShare,
              icon: const Icon(CupertinoIcons.share, size: 16),
              label: const Text('分享与历史'),
            )),
          ]),
        ],
      ),
    );
  }
}
