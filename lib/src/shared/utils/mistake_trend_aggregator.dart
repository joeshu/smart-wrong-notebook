import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/domain/models/mistake_category.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';

/// 错因趋势热力图聚合数据。
///
/// 聚合最近 [days] 天（默认 30 天）每天每错因分类的题数，
/// 供 [generateMistakeTrendHtmlSync] 渲染 HTML 热力图报告使用。
class MistakeTrendData {
  const MistakeTrendData({
    required this.generatedAt,
    required this.startDate,
    required this.endDate,
    required this.categories,
    required this.dates,
    required this.matrix,
    required this.dailyTotals,
    required this.categoryTotals,
    required this.grandTotal,
  });

  /// 报告生成时间。
  final DateTime generatedAt;

  /// 起始日期（30 天前的 00:00）。
  final DateTime startDate;

  /// 结束日期（今天的 23:59:59）。
  final DateTime endDate;

  /// 出现过的错因分类（按 [MistakeCategory.index] 升序）。
  final List<MistakeCategory> categories;

  /// 30 天的日期列表（按时间升序，每天 00:00）。
  final List<DateTime> dates;

  /// 二维矩阵：`matrix[dayIndex][categoryIndex] = 该天该分类的题数`。
  final List<List<int>> matrix;

  /// 每天总题数（与 [dates] 等长）。
  final List<int> dailyTotals;

  /// 每个分类总题数（与 [categories] 等长）。
  final List<int> categoryTotals;

  /// 全部题数。
  final int grandTotal;
}

/// 聚合错因趋势数据。
///
/// 调用方需要在 WidgetRef 上下文中使用，例如：
/// ```dart
/// final data = await aggregateMistakeTrend(ref);
/// ```
Future<MistakeTrendData> aggregateMistakeTrend(
  WidgetRef ref, {
  int days = 30,
}) async {
  // 用 Future.wait 并发拉取（与 weekly_report_aggregator 保持一致的模式；
  // 当前仅有一个 provider，后续扩展可追加并行流）。
  final results = await Future.wait<dynamic>([
    ref.read(questionListProvider.future),
  ]);
  final List<QuestionRecord> questions = results[0] as List<QuestionRecord>;
  return aggregateMistakeTrendFromQuestions(questions, days: days);
}

/// 纯函数实现，便于单元测试直接复用。
@visibleForTesting
MistakeTrendData aggregateMistakeTrendFromQuestions(
  List<QuestionRecord> questions, {
  int days = 30,
  DateTime? now,
}) {
  final current = now ?? DateTime.now();
  // startDate = 当前时间减去 (days-1) 天，再取日期部分（年月日 00:00）。
  final startDate =
      DateTime(current.year, current.month, current.day).subtract(
    Duration(days: days - 1),
  );
  // endDate = 今天的 23:59:59。
  final endDate = DateTime(current.year, current.month, current.day, 23, 59, 59);

  // 30 天日期列表，每天 00:00。
  final dates = List<DateTime>.generate(
    days,
    (i) => startDate.add(Duration(days: i)),
  );

  // 第一遍扫描：找出在窗口内出现过的所有分类。
  final seenCategories = <MistakeCategory>{};
  for (final q in questions) {
    final cat = q.mistakeCategory;
    if (cat == null) continue;
    final created = DateTime(
      q.createdAt.year,
      q.createdAt.month,
      q.createdAt.day,
    );
    if (created.isBefore(startDate) || created.isAfter(endDate)) continue;
    seenCategories.add(cat);
  }
  // 按 MistakeCategory.index 升序排列（enum 声明顺序即 index 顺序）。
  final categories = seenCategories.toList()
    ..sort((a, b) => a.index.compareTo(b.index));
  final categoryIndex = <MistakeCategory, int>{
    for (var i = 0; i < categories.length; i++) categories[i]: i,
  };

  // 初始化矩阵全 0。
  final matrix = List<List<int>>.generate(
    days,
    (_) => List<int>.filled(categories.length, 0),
  );
  final dailyTotals = List<int>.filled(days, 0);
  final categoryTotals = List<int>.filled(categories.length, 0);

  var grandTotal = 0;
  for (final q in questions) {
    final cat = q.mistakeCategory;
    if (cat == null) continue;
    final catIdx = categoryIndex[cat];
    if (catIdx == null) continue;
    final created = DateTime(
      q.createdAt.year,
      q.createdAt.month,
      q.createdAt.day,
    );
    if (created.isBefore(startDate) || created.isAfter(endDate)) continue;
    final dayDiff = created.difference(startDate).inDays;
    if (dayDiff < 0 || dayDiff >= days) continue;
    matrix[dayDiff][catIdx]++;
    dailyTotals[dayDiff]++;
    categoryTotals[catIdx]++;
    grandTotal++;
  }

  return MistakeTrendData(
    generatedAt: current,
    startDate: startDate,
    endDate: endDate,
    categories: categories,
    dates: dates,
    matrix: matrix,
    dailyTotals: dailyTotals,
    categoryTotals: categoryTotals,
    grandTotal: grandTotal,
  );
}
