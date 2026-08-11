import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_wrong_notebook/src/app/theme/app_visual_style.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/domain/models/ai_model_strategy.dart';
import 'package:smart_wrong_notebook/src/domain/models/ai_provider_config.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_colors.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_layout.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_ui.dart';

class ModelStrategyCenterScreen extends ConsumerStatefulWidget {
  const ModelStrategyCenterScreen({super.key});

  @override
  ConsumerState<ModelStrategyCenterScreen> createState() =>
      _ModelStrategyCenterScreenState();
}

class _ModelStrategyCenterScreenState
    extends ConsumerState<ModelStrategyCenterScreen> {
  AiModelStrategy? _strategy;
  AiProviderConfig? _provider;
  Object? _error;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  Future<void> _load() async {
    try {
      final settings = ref.read(settingsRepositoryProvider);
      final results = await Future.wait<dynamic>(<Future<dynamic>>[
        AiModelStrategyStore(settings).load(),
        settings.getAiProviderConfig(),
      ]);
      if (!mounted) return;
      setState(() {
        _strategy = results[0] as AiModelStrategy;
        _provider = results[1] as AiProviderConfig?;
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = error);
    }
  }

  Future<void> _select(AiStrategyPreset preset) async {
    if (_saving || preset == _strategy?.preset) return;
    if (preset == AiStrategyPreset.privacy && !_isPrivateProvider(_provider)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请先在高级设置中配置本地或私有服务，再启用隐私优先'),
        ),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      final updated = await AiModelStrategyStore(
        ref.read(settingsRepositoryProvider),
      ).selectPreset(preset);
      if (!mounted) return;
      setState(() => _strategy = updated);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已切换为「${preset.label}」策略')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('保存模型策略失败：$error')),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  bool _isPrivateProvider(AiProviderConfig? provider) {
    if (provider?.isPrivate == true) return true;
    final raw = provider?.baseUrl.trim().toLowerCase() ?? '';
    if (raw.isEmpty) return false;
    final uri = Uri.tryParse(raw);
    final host = uri?.host ?? '';
    return host == 'localhost' ||
        host == '127.0.0.1' ||
        host == '::1' ||
        host.startsWith('192.168.') ||
        host.startsWith('10.');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('模型策略中心'),
        leading: IconButton(
          icon: const Icon(CupertinoIcons.chevron_left),
          onPressed: () => context.go('/settings'),
        ),
      ),
      body: AppPage(
        maxWidth: AppContentWidth.wide,
        child: _buildBody(context),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            const Icon(CupertinoIcons.exclamationmark_triangle,
                size: 42, color: AppColors.warning),
            const SizedBox(height: AppSpace.md),
            const Text('模型策略加载失败'),
            const SizedBox(height: AppSpace.sm),
            OutlinedButton(onPressed: _load, child: const Text('重新加载')),
          ],
        ),
      );
    }
    final strategy = _strategy;
    if (strategy == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return ListView(
      key: const Key('model-strategy-center-list'),
      children: <Widget>[
        _buildHero(context, strategy),
        const SizedBox(height: AppSpace.xl),
        const AppSectionTitle('选择工作策略'),
        const SizedBox(height: AppSpace.xs),
        Text(
          '普通用户只需选择目标，系统会决定何时快速完成、何时复核或降级。',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
        ),
        const SizedBox(height: AppSpace.md),
        LayoutBuilder(builder: (context, constraints) {
          final columns = constraints.maxWidth >= AppBreakpoints.expanded ? 2 : 1;
          final width = columns == 2
              ? (constraints.maxWidth - AppSpace.md) / 2
              : constraints.maxWidth;
          return Wrap(
            spacing: AppSpace.md,
            runSpacing: AppSpace.md,
            children: AiStrategyPreset.values
                .map((preset) => SizedBox(
                      width: width,
                      child: _StrategyCard(
                        preset: preset,
                        selected: strategy.preset == preset,
                        enabled: preset != AiStrategyPreset.privacy ||
                            _isPrivateProvider(_provider),
                        saving: _saving,
                        onTap: () => _select(preset),
                      ),
                    ))
                .toList(growable: false),
          );
        }),
        const SizedBox(height: AppSpace.xl),
        const AppSectionTitle('当前提供商'),
        const SizedBox(height: AppSpace.sm),
        _buildProviderCard(context),
        const SizedBox(height: AppSpace.xl),
        const AppSectionTitle('任务路由预览'),
        const SizedBox(height: AppSpace.sm),
        _buildRoutes(context, strategy),
        const SizedBox(height: AppSpace.xxl),
      ],
    );
  }

  Widget _buildHero(BuildContext context, AiModelStrategy strategy) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      key: const Key('model-strategy-hero'),
      padding: const EdgeInsets.all(AppSpace.xl),
      decoration: BoxDecoration(
        gradient: AppVisualTokens.of(context).heroGradient,
        borderRadius: BorderRadius.circular(
          AppVisualTokens.of(context).cardRadius,
        ),
      ),
      child: Row(
        children: <Widget>[
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: .16),
              borderRadius: BorderRadius.circular(AppRadius.medium),
            ),
            child: const Icon(CupertinoIcons.sparkles,
                color: Colors.white, size: 26),
          ),
          const SizedBox(width: AppSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  '当前：${strategy.preset.label}',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: AppSpace.xs),
                Text(
                  strategy.preset.summary,
                  style: TextStyle(
                    color: scheme.onPrimary.withValues(alpha: .88),
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProviderCard(BuildContext context) {
    final provider = _provider;
    final ready = provider != null &&
        provider.baseUrl.isNotEmpty &&
        provider.model.isNotEmpty &&
        provider.apiKey.isNotEmpty;
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      padding: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(AppSpace.lg),
        child: Column(
          children: <Widget>[
            Row(
              children: <Widget>[
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: ready
                        ? AppColors.success.withValues(alpha: .12)
                        : AppColors.warning.withValues(alpha: .12),
                    borderRadius: BorderRadius.circular(AppRadius.small),
                  ),
                  child: Icon(
                    ready
                        ? CupertinoIcons.checkmark_shield
                        : CupertinoIcons.exclamationmark_triangle,
                    color: ready ? AppColors.success : AppColors.warning,
                  ),
                ),
                const SizedBox(width: AppSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(provider?.displayName ?? '尚未配置提供商',
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(
                        provider == null
                            ? '配置服务后才能执行 AI 分析'
                            : '${provider.serviceType.label} · ${provider.model}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: scheme.onSurfaceVariant,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                FilledButton.tonal(
                  key: const Key('manage-ai-provider-button'),
                  onPressed: () => context.go('/settings/provider/edit'),
                  child: Text(provider == null ? '去配置' : '高级设置'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoutes(BuildContext context, AiModelStrategy strategy) {
    final scheme = Theme.of(context).colorScheme;
    return AppCard(
      child: Column(
        children: <Widget>[
          for (var index = 0; index < strategy.routes.length; index++) ...<Widget>[
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: AppSpace.lg, vertical: AppSpace.md),
              child: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(strategy.routes[index].task.label,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  Text(
                    strategy.routes[index].primaryModel.isEmpty
                        ? '待配置'
                        : strategy.routes[index].primaryModel,
                    style: TextStyle(
                      color: strategy.routes[index].primaryModel.isEmpty
                          ? AppColors.warning
                          : scheme.onSurfaceVariant,
                      fontSize: 12,
                    ),
                  ),
                  const SizedBox(width: AppSpace.sm),
                  Icon(CupertinoIcons.chevron_right,
                      size: 14, color: scheme.outline),
                ],
              ),
            ),
            if (index < strategy.routes.length - 1)
              Divider(height: 1, color: scheme.outlineVariant),
          ],
        ],
      ),
    );
  }
}

class _StrategyCard extends StatelessWidget {
  const _StrategyCard({
    required this.preset,
    required this.selected,
    required this.enabled,
    required this.saving,
    required this.onTap,
  });

  final AiStrategyPreset preset;
  final bool selected;
  final bool enabled;
  final bool saving;
  final VoidCallback onTap;

  IconData get _icon => switch (preset) {
        AiStrategyPreset.balanced => CupertinoIcons.slider_horizontal_3,
        AiStrategyPreset.accuracy => CupertinoIcons.checkmark_shield_fill,
        AiStrategyPreset.economy => CupertinoIcons.leaf_arrow_circlepath,
        AiStrategyPreset.privacy => CupertinoIcons.lock_shield_fill,
      };

  String get _metrics => switch (preset) {
        AiStrategyPreset.balanced => '速度 中 · 准确性 高 · 费用 中',
        AiStrategyPreset.accuracy => '速度 较慢 · 准确性 最高 · 费用 较高',
        AiStrategyPreset.economy => '速度 快 · 准确性 标准 · 费用 低',
        AiStrategyPreset.privacy => '远程受限 · 数据保护最高',
      };

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? scheme.primary : scheme.onSurfaceVariant;
    return Semantics(
      selected: selected,
      button: true,
      label: '${preset.label}模型策略',
      child: Material(
        color: selected ? scheme.primaryContainer : scheme.surface,
        borderRadius: BorderRadius.circular(AppRadius.medium),
        child: InkWell(
          key: Key('model-strategy-${preset.name}'),
          onTap: saving ? null : onTap,
          borderRadius: BorderRadius.circular(AppRadius.medium),
          child: Container(
            padding: const EdgeInsets.all(AppSpace.lg),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(AppRadius.medium),
              border: Border.all(
                color: selected ? scheme.primary : scheme.outlineVariant,
                width: selected ? 1.5 : 1,
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Icon(_icon, color: enabled ? color : scheme.outline, size: 24),
                const SizedBox(width: AppSpace.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              preset.label,
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: enabled ? null : scheme.outline,
                              ),
                            ),
                          ),
                          if (selected)
                            Icon(CupertinoIcons.checkmark_circle_fill,
                                color: scheme.primary, size: 20),
                        ],
                      ),
                      const SizedBox(height: AppSpace.xs),
                      Text(
                        preset.summary,
                        style: TextStyle(
                          color: enabled
                              ? scheme.onSurfaceVariant
                              : scheme.outline,
                          height: 1.35,
                        ),
                      ),
                      const SizedBox(height: AppSpace.sm),
                      Text(
                        enabled ? _metrics : '需要先配置本地或私有提供商',
                        style: TextStyle(
                          color: enabled ? color : AppColors.warning,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
