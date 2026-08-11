import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';

class WorksheetReviewSummaryScreen extends ConsumerWidget {
  const WorksheetReviewSummaryScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(currentWorksheetReviewSummaryProvider);
    if (summary == null) return Scaffold(
      appBar: AppBar(title: const Text('本页处理结果')),
      body: const Center(child: Text('没有可显示的本页处理结果')),
    );
    final total = summary.aiCount + summary.ocrCount + summary.ignoredCount;
    return Scaffold(
      appBar: AppBar(title: const Text('本页处理完成')),
      body: SafeArea(child: ListView(padding: const EdgeInsets.all(20), children: <Widget>[
        Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(color: const Color(0xFFF0FDF4), borderRadius: BorderRadius.circular(14)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: <Widget>[
            const Row(children: <Widget>[Icon(CupertinoIcons.check_mark_circled_solid, color: Color(0xFF16A34A)), SizedBox(width: 8), Text('本页已按确认策略处理', style: TextStyle(fontWeight: FontWeight.w700))]),
            const SizedBox(height: 12),
            Text('共 $total 道候选题', style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 5),
            Text('✓ ${summary.aiCount} 题：进入普通 AI 深度分析'),
            Text('✓ ${summary.ocrCount} 题：保存为 OCR / 文档草稿'),
            if (summary.ignoredCount > 0) Text('⊘ ${summary.ignoredCount} 题：已忽略，未裁切也未保存'),
          ]),
        ),
        const SizedBox(height: 18),
        FilledButton.icon(onPressed: summary.aiCount == 0 ? null : () => context.go('/analysis/loading'), icon: const Icon(CupertinoIcons.sparkles), label: const Text('查看分析进度')),
        const SizedBox(height: 10),
        OutlinedButton.icon(onPressed: () => context.go('/worksheet/import'), icon: const Icon(CupertinoIcons.doc_text), label: const Text('查看 OCR 草稿与导入批次')),
        const SizedBox(height: 10),
        OutlinedButton.icon(onPressed: () => context.go('/worksheet/import'), icon: const Icon(CupertinoIcons.add), label: const Text('继续导入下一页')),
        const SizedBox(height: 10),
        TextButton(onPressed: () => context.go('/notebook'), child: const Text('返回错题本')),
      ])),
    );
  }
}
