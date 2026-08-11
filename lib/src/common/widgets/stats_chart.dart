import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:smart_wrong_notebook/src/domain/models/mastery_level.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_colors.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_components.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_ui.dart';

class StatsBarChart extends StatelessWidget {
  const StatsBarChart({
    super.key,
    required this.total,
    required this.mastered,
    required this.reviewing,
    required this.newQ,
  });

  final int total;
  final int mastered;
  final int reviewing;
  final int newQ;

  static const _colors = {
    MasteryLevel.mastered: Color(0xFF16A34A),
    MasteryLevel.reviewing: Color(0xFFD97706),
    MasteryLevel.newQuestion: Color(0xFF6B7280),
  };

  static const _labels = {
    MasteryLevel.mastered: '已掌握',
    MasteryLevel.reviewing: '复习中',
    MasteryLevel.newQuestion: '新增',
  };

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final maxY =
        [mastered, reviewing, newQ].reduce((a, b) => a > b ? a : b).toDouble();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        SizedBox(
          height: 160,
          child: BarChart(
            BarChartData(
              alignment: BarChartAlignment.spaceAround,
              maxY: maxY < 1 ? 5 : maxY * 1.3,
              barTouchData: BarTouchData(
                enabled: total > 0,
                touchTooltipData: BarTouchTooltipData(
                  getTooltipColor: (_) => const Color(0xFF1E293B),
                  tooltipRoundedRadius: 6,
                  getTooltipItem: (group, groupIndex, rod, rodIndex) {
                    final level = MasteryLevel.values[group.x.toInt()];
                    return BarTooltipItem(
                      '${_labels[level]}\n${rod.toY.toInt()} 题',
                      const TextStyle(color: Colors.white, fontSize: 12),
                    );
                  },
                ),
              ),
              titlesData: FlTitlesData(
                show: true,
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    getTitlesWidget: (value, meta) {
                      final level = MasteryLevel.values[value.toInt()];
                      return Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Text(
                          _labels[level]!,
                          style: TextStyle(
                            fontSize: 11,
                            color: colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      );
                    },
                    reservedSize: 32,
                  ),
                ),
                leftTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                topTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                rightTitles:
                    const AxisTitles(sideTitles: SideTitles(showTitles: false)),
              ),
              gridData: const FlGridData(show: false),
              borderData: FlBorderData(show: false),
              barGroups: <BarChartGroupData>[
                BarChartGroupData(
                  x: MasteryLevel.newQuestion.index,
                  barRods: [
                    BarChartRodData(
                      toY: newQ.toDouble(),
                      color: _colors[MasteryLevel.newQuestion],
                      width: 28,
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(6)),
                    ),
                  ],
                ),
                BarChartGroupData(
                  x: MasteryLevel.reviewing.index,
                  barRods: [
                    BarChartRodData(
                      toY: reviewing.toDouble(),
                      color: _colors[MasteryLevel.reviewing],
                      width: 28,
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(6)),
                    ),
                  ],
                ),
                BarChartGroupData(
                  x: MasteryLevel.mastered.index,
                  barRods: [
                    BarChartRodData(
                      toY: mastered.toDouble(),
                      color: _colors[MasteryLevel.mastered],
                      width: 28,
                      borderRadius:
                          const BorderRadius.vertical(top: Radius.circular(6)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: <Widget>[
            _LegendDot(
                color: _colors[MasteryLevel.newQuestion]!, label: '新增 ($newQ)'),
            const SizedBox(width: 16),
            _LegendDot(
                color: _colors[MasteryLevel.reviewing]!,
                label: '复习中 ($reviewing)'),
            const SizedBox(width: 16),
            _LegendDot(
                color: _colors[MasteryLevel.mastered]!,
                label: '已掌握 ($mastered)'),
          ],
        ),
      ],
    );
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({required this.color, required this.label});

  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
              color: color, borderRadius: BorderRadius.circular(5)),
        ),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }
}

class StatsGrid extends StatelessWidget {
  const StatsGrid({
    super.key,
    required this.total,
    required this.todayNew,
    required this.pending,
    required this.mastered,
  });

  final int total;
  final int todayNew;
  final int pending;
  final int mastered;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Row(
          children: <Widget>[
            Expanded(
              child: AppStatCard(
                label: '题库总量',
                value: '$total',
                icon: CupertinoIcons.book,
                accentColor: AppColors.primary,
              ),
            ),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: AppStatCard(
                label: '今日新增',
                value: '$todayNew',
                icon: CupertinoIcons.plus_app,
                accentColor: AppColors.info,
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpace.md),
        Row(
          children: <Widget>[
            Expanded(
              child: AppStatCard(
                label: '已掌握',
                value: '$mastered',
                icon: CupertinoIcons.checkmark_seal_fill,
                accentColor: AppColors.success,
              ),
            ),
            const SizedBox(width: AppSpace.md),
            Expanded(
              child: AppStatCard(
                label: '待复习',
                value: '$pending',
                icon: CupertinoIcons.clock,
                accentColor: AppColors.warning,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
