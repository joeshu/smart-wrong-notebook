import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:smart_wrong_notebook/src/domain/models/specialized_analysis.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_colors.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_ui.dart';
import 'package:smart_wrong_notebook/src/shared/widgets/math_content_view.dart';

class SpecializedAnalysisSection extends StatelessWidget {
  const SpecializedAnalysisSection({
    required this.analysis,
    super.key,
  });

  final SpecializedAnalysis analysis;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      key: Key('specialized-analysis-${analysis.profile.name}'),
      padding: EdgeInsets.zero,
      borderColor: _accent.withValues(alpha: .45),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Container(
            padding: const EdgeInsets.all(AppSpace.lg),
            decoration: BoxDecoration(
              color: _accent.withValues(alpha: .10),
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(AppRadius.medium - 1),
              ),
            ),
            child: Row(
              children: <Widget>[
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    color: _accent.withValues(alpha: .14),
                    borderRadius: BorderRadius.circular(AppRadius.small),
                  ),
                  child: Icon(_icon, color: _accent, size: 21),
                ),
                const SizedBox(width: AppSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        analysis.profile.label,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _subtitle,
                        style: TextStyle(
                          fontSize: 12,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                AppTag(
                  label: analysis.isModelProvided ? '专用解析' : '智能整理',
                  textColor: _accent,
                  backgroundColor: _accent.withValues(alpha: .10),
                  fontSize: 11,
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(AppSpace.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                if (analysis.givens.isNotEmpty)
                  _TextListBlock(title: '已知条件', values: analysis.givens),
                if (analysis.goal.trim().isNotEmpty) ...<Widget>[
                  if (analysis.givens.isNotEmpty)
                    const SizedBox(height: AppSpace.md),
                  _MathBlock(title: _goalTitle, value: analysis.goal),
                ],
                if (analysis.profile == AnalysisProfile.geometry) ...<Widget>[
                  if (analysis.entities.isNotEmpty) ...<Widget>[
                    const SizedBox(height: AppSpace.md),
                    _TagBlock(title: '图形对象', values: analysis.entities),
                  ],
                  if (analysis.relations.isNotEmpty) ...<Widget>[
                    const SizedBox(height: AppSpace.md),
                    _TagBlock(title: '几何关系', values: analysis.relations),
                  ],
                ],
                if (analysis.constraints.isNotEmpty) ...<Widget>[
                  const SizedBox(height: AppSpace.md),
                  _TextListBlock(title: '约束与定义域', values: analysis.constraints),
                ],
                if (analysis.reasoningSteps.isNotEmpty) ...<Widget>[
                  const SizedBox(height: AppSpace.lg),
                  Text(_stepsTitle,
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                  const SizedBox(height: AppSpace.sm),
                  for (final step in analysis.reasoningSteps)
                    _ReasoningStepTile(
                      step: step,
                      requiresBasis: analysis.profile == AnalysisProfile.geometry ||
                          analysis.profile == AnalysisProfile.proofArgument,
                      accent: _accent,
                    ),
                ],
                if (_isEquation) ...<Widget>[
                  const SizedBox(height: AppSpace.md),
                  _VerificationBlock(values: analysis.verification),
                ],
                if (analysis.risks.isNotEmpty) ...<Widget>[
                  const SizedBox(height: AppSpace.md),
                  _RiskBlock(values: analysis.risks),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool get _isEquation =>
      analysis.profile == AnalysisProfile.algebraEquation ||
      analysis.profile == AnalysisProfile.equationSystem;

  Color get _accent => switch (analysis.profile) {
        AnalysisProfile.algebraEquation || AnalysisProfile.equationSystem =>
          AppColors.accentTeal,
        AnalysisProfile.geometry => AppColors.accentPurple,
        AnalysisProfile.proofArgument => AppColors.accentAmber,
        AnalysisProfile.generic => AppColors.primary,
      };

  IconData get _icon => switch (analysis.profile) {
        AnalysisProfile.algebraEquation || AnalysisProfile.equationSystem =>
          CupertinoIcons.function,
        AnalysisProfile.geometry => CupertinoIcons.triangle,
        AnalysisProfile.proofArgument => CupertinoIcons.checkmark_shield,
        AnalysisProfile.generic => CupertinoIcons.sparkles,
      };

  String get _subtitle => switch (analysis.profile) {
        AnalysisProfile.algebraEquation => '未知量 · 等价变形 · 代回验证',
        AnalysisProfile.equationSystem => '约束关系 · 消元过程 · 联立验证',
        AnalysisProfile.geometry => '图形对象 · 几何关系 · 定理链',
        AnalysisProfile.proofArgument => '前提 · 结论 · 依据与证明缺口',
        AnalysisProfile.generic => '结构化解题过程',
      };

  String get _goalTitle => switch (analysis.profile) {
        AnalysisProfile.proofArgument => '待证结论',
        AnalysisProfile.geometry => '求解目标',
        _ => '目标',
      };

  String get _stepsTitle => switch (analysis.profile) {
        AnalysisProfile.proofArgument => '证明链',
        AnalysisProfile.geometry => '定理与推导',
        _ => '等价变形过程',
      };
}

class _MathBlock extends StatelessWidget {
  const _MathBlock({required this.title, required this.value});
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: AppSpace.xs),
          MathContentView(value),
        ],
      );
}

class _TextListBlock extends StatelessWidget {
  const _TextListBlock({required this.title, required this.values});
  final String title;
  final List<String> values;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: AppSpace.xs),
          for (final value in values)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpace.xs),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Padding(
                    padding: EdgeInsets.only(top: 7),
                    child: CircleAvatar(radius: 2),
                  ),
                  const SizedBox(width: AppSpace.sm),
                  Expanded(child: MathContentView(value)),
                ],
              ),
            ),
        ],
      );
}

class _TagBlock extends StatelessWidget {
  const _TagBlock({required this.title, required this.values});
  final String title;
  final List<String> values;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
          const SizedBox(height: AppSpace.xs),
          Wrap(
            spacing: AppSpace.xs,
            runSpacing: AppSpace.xs,
            children: values.map((value) => AppTag(label: value)).toList(),
          ),
        ],
      );
}

class _ReasoningStepTile extends StatelessWidget {
  const _ReasoningStepTile({
    required this.step,
    required this.requiresBasis,
    required this.accent,
  });
  final SpecializedReasoningStep step;
  final bool requiresBasis;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final missingBasis = requiresBasis && step.basis.trim().isEmpty;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpace.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: .12),
              shape: BoxShape.circle,
            ),
            child: Text('${step.index}',
                style: TextStyle(color: accent, fontWeight: FontWeight.w800)),
          ),
          const SizedBox(width: AppSpace.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                MathContentView(step.statement),
                const SizedBox(height: 3),
                Text(
                  missingBasis
                      ? '依据待补充'
                      : step.basis.trim().isEmpty
                          ? '等价变形'
                          : '依据：${step.basis}',
                  style: TextStyle(
                    color: missingBasis
                        ? AppColors.warning
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 11,
                    fontWeight: missingBasis ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _VerificationBlock extends StatelessWidget {
  const _VerificationBlock({required this.values});
  final List<String> values;

  @override
  Widget build(BuildContext context) {
    final verified = values.isNotEmpty;
    final color = verified ? AppColors.success : AppColors.warning;
    return Container(
      key: const Key('specialized-equation-verification'),
      padding: const EdgeInsets.all(AppSpace.md),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(AppRadius.small),
        border: Border.all(color: color.withValues(alpha: .35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                verified
                    ? CupertinoIcons.checkmark_circle_fill
                    : CupertinoIcons.exclamationmark_triangle_fill,
                size: 17,
                color: color,
              ),
              const SizedBox(width: AppSpace.xs),
              Text(verified ? '代回验证' : '尚未完成代回验证',
                  style: TextStyle(color: color, fontWeight: FontWeight.w800)),
            ],
          ),
          if (verified) ...<Widget>[
            const SizedBox(height: AppSpace.sm),
            for (final value in values) MathContentView(value),
          ],
        ],
      ),
    );
  }
}

class _RiskBlock extends StatelessWidget {
  const _RiskBlock({required this.values});
  final List<String> values;

  @override
  Widget build(BuildContext context) => Container(
        key: const Key('specialized-risk-block'),
        padding: const EdgeInsets.all(AppSpace.md),
        decoration: BoxDecoration(
          color: AppColors.warning.withValues(alpha: .08),
          borderRadius: BorderRadius.circular(AppRadius.small),
          border: Border.all(color: AppColors.warning.withValues(alpha: .35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Row(
              children: <Widget>[
                Icon(CupertinoIcons.exclamationmark_triangle,
                    size: 17, color: AppColors.warning),
                SizedBox(width: AppSpace.xs),
                Text('需要核对',
                    style: TextStyle(
                        color: AppColors.warning, fontWeight: FontWeight.w800)),
              ],
            ),
            const SizedBox(height: AppSpace.xs),
            for (final value in values)
              Text('• $value', style: const TextStyle(height: 1.45)),
          ],
        ),
      );
}
