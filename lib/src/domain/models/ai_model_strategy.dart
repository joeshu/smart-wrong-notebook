import 'dart:convert';

import 'package:smart_wrong_notebook/src/data/repositories/settings_repository.dart';
import 'package:smart_wrong_notebook/src/domain/models/ai_provider_config.dart';

enum AiStrategyPreset { balanced, accuracy, economy, privacy }

extension AiStrategyPresetX on AiStrategyPreset {
  String get label => switch (this) {
        AiStrategyPreset.balanced => '均衡',
        AiStrategyPreset.accuracy => '准确优先',
        AiStrategyPreset.economy => '省钱优先',
        AiStrategyPreset.privacy => '隐私优先',
      };

  String get summary => switch (this) {
        AiStrategyPreset.balanced => '普通题快速完成，风险字段再复核',
        AiStrategyPreset.accuracy => '复杂题加强审查，优先保证答案可靠',
        AiStrategyPreset.economy => '轻量调用为主，只在失败时升级',
        AiStrategyPreset.privacy => '仅允许本地或明确标记为私有的服务',
      };
}

enum AiTaskProfile {
  documentLayout,
  generalAnalysis,
  specializedAnalysis,
  riskReview,
  exerciseGeneration,
  reportNarration,
}

extension AiTaskProfileX on AiTaskProfile {
  String get label => switch (this) {
        AiTaskProfile.documentLayout => '版面理解',
        AiTaskProfile.generalAnalysis => '普通题分析',
        AiTaskProfile.specializedAnalysis => '复杂题分析',
        AiTaskProfile.riskReview => '风险字段复核',
        AiTaskProfile.exerciseGeneration => '练习生成',
        AiTaskProfile.reportNarration => '成长报告文案',
      };
}

class AiTaskRoute {
  const AiTaskRoute({
    required this.task,
    required this.primaryProviderId,
    required this.primaryModel,
    this.fallbackModelIds = const <String>[],
    this.reviewModelId,
  });

  final AiTaskProfile task;
  final String primaryProviderId;
  final String primaryModel;
  final List<String> fallbackModelIds;
  final String? reviewModelId;

  AiTaskRoute copyWith({
    AiTaskProfile? task,
    String? primaryProviderId,
    String? primaryModel,
    List<String>? fallbackModelIds,
    String? reviewModelId,
  }) =>
      AiTaskRoute(
        task: task ?? this.task,
        primaryProviderId: primaryProviderId ?? this.primaryProviderId,
        primaryModel: primaryModel ?? this.primaryModel,
        fallbackModelIds: fallbackModelIds ?? this.fallbackModelIds,
        reviewModelId: reviewModelId ?? this.reviewModelId,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'task': task.name,
        'primaryProviderId': primaryProviderId,
        'primaryModel': primaryModel,
        'fallbackModelIds': fallbackModelIds,
        if (reviewModelId != null) 'reviewModelId': reviewModelId,
      };

  factory AiTaskRoute.fromJson(Map<String, dynamic> json) => AiTaskRoute(
        task: AiTaskProfile.values.firstWhere(
          (value) => value.name == json['task'],
          orElse: () => AiTaskProfile.generalAnalysis,
        ),
        primaryProviderId: json['primaryProviderId'] as String? ?? 'default',
        primaryModel: json['primaryModel'] as String? ?? '',
        fallbackModelIds: (json['fallbackModelIds'] as List<dynamic>? ??
                const <dynamic>[])
            .whereType<String>()
            .toList(growable: false),
        reviewModelId: json['reviewModelId'] as String?,
      );
}

class AiModelStrategy {
  const AiModelStrategy({
    required this.id,
    required this.preset,
    required this.routes,
    required this.updatedAt,
    this.schemaVersion = 1,
  });

  final int schemaVersion;
  final String id;
  final AiStrategyPreset preset;
  final List<AiTaskRoute> routes;
  final DateTime updatedAt;

  bool get riskReviewEnabled => preset == AiStrategyPreset.balanced ||
      preset == AiStrategyPreset.accuracy;
  bool get complexProblemReviewEnabled =>
      preset == AiStrategyPreset.accuracy;
  bool get fallbackOnlyOnFailure => preset == AiStrategyPreset.economy;
  bool get blocksUntrustedRemoteProviders =>
      preset == AiStrategyPreset.privacy;

  AiTaskRoute? routeFor(AiTaskProfile task) {
    for (final route in routes) {
      if (route.task == task) return route;
    }
    return null;
  }

  AiModelStrategy copyWith({
    AiStrategyPreset? preset,
    List<AiTaskRoute>? routes,
    DateTime? updatedAt,
  }) =>
      AiModelStrategy(
        id: id,
        preset: preset ?? this.preset,
        routes: routes ?? this.routes,
        updatedAt: updatedAt ?? this.updatedAt,
        schemaVersion: schemaVersion,
      );

  Map<String, dynamic> toJson() => <String, dynamic>{
        'schemaVersion': schemaVersion,
        'id': id,
        'preset': preset.name,
        'routes': routes.map((route) => route.toJson()).toList(),
        'updatedAt': updatedAt.toIso8601String(),
      };

  String encode() => jsonEncode(toJson());

  factory AiModelStrategy.fromJson(Map<String, dynamic> json) =>
      AiModelStrategy(
        schemaVersion: (json['schemaVersion'] as num?)?.toInt() ?? 1,
        id: json['id'] as String? ?? 'default-strategy',
        preset: AiStrategyPreset.values.firstWhere(
          (value) => value.name == json['preset'],
          orElse: () => AiStrategyPreset.balanced,
        ),
        routes: (json['routes'] as List<dynamic>? ?? const <dynamic>[])
            .whereType<Map<String, dynamic>>()
            .map(AiTaskRoute.fromJson)
            .toList(growable: false),
        updatedAt: DateTime.tryParse(json['updatedAt'] as String? ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );

  factory AiModelStrategy.decode(String raw) => AiModelStrategy.fromJson(
      jsonDecode(raw) as Map<String, dynamic>);

  factory AiModelStrategy.fromLegacyProvider(
    AiProviderConfig? provider, {
    AiStrategyPreset preset = AiStrategyPreset.balanced,
    DateTime? now,
  }) {
    final providerId = provider?.id ?? 'default';
    final model = provider?.model ?? '';
    return AiModelStrategy(
      id: 'default-strategy',
      preset: preset,
      updatedAt: now ?? DateTime.now(),
      routes: AiTaskProfile.values
          .map((task) => AiTaskRoute(
                task: task,
                primaryProviderId: providerId,
                primaryModel: model,
              ))
          .toList(growable: false),
    );
  }
}

class AiModelStrategyStore {
  AiModelStrategyStore(this._settings);

  static const storageKey = 'ai_model_strategy_v1';
  final SettingsRepository _settings;

  Future<AiModelStrategy> load() async {
    final provider = await _settings.getAiProviderConfig();
    final raw = await _settings.getString(storageKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        final decoded = AiModelStrategy.decode(raw);
        final reconciled = _reconcileWithProvider(decoded, provider);
        if (reconciled.encode() != decoded.encode()) {
          await save(reconciled);
        }
        return reconciled;
      } catch (_) {
        // Corrupt strategy settings must not block the existing AI provider.
      }
    }
    final migrated = _reconcileWithProvider(
      AiModelStrategy.fromLegacyProvider(provider),
      provider,
    );
    await save(migrated);
    return migrated;
  }

  /// 将当前策略与最新 AI 提供商配置对齐后持久化。
  ///
  /// 单提供商模式下，提供商变更（换模型/换服务）会同步到所有任务路由，
  /// 避免「任务路由预览」长期停留在『待配置』。
  Future<AiModelStrategy> syncWithProvider(AiProviderConfig? provider) async {
    final raw = await _settings.getString(storageKey);
    final current = raw != null && raw.isNotEmpty
        ? () {
            try {
              return AiModelStrategy.decode(raw);
            } catch (_) {
              return AiModelStrategy.fromLegacyProvider(provider);
            }
          }()
        : AiModelStrategy.fromLegacyProvider(provider);
    final synced = _reconcileWithProvider(current, provider);
    await save(synced);
    return synced;
  }

  Future<void> save(AiModelStrategy strategy) =>
      _settings.setString(storageKey, strategy.encode());

  Future<AiModelStrategy> selectPreset(AiStrategyPreset preset) async {
    final current = await load();
    final updated = current.copyWith(preset: preset, updatedAt: DateTime.now());
    await save(updated);
    return updated;
  }

  /// 把已保存的策略路由与当前提供商配置对齐。
  ///
  /// - 缺任务的路由补齐（后续新增任务类型时旧数据自动迁移）。
  /// - 单提供商模式（所有路由指向同一提供方/模型）下跟随提供商变更。
  /// - 多提供方/多模型形态只补空模型路由，不覆盖用户手工配置。
  AiModelStrategy _reconcileWithProvider(
    AiModelStrategy current,
    AiProviderConfig? provider,
  ) {
    final providerId = provider?.id ?? 'default';
    final model = provider?.model ?? '';
    final singleProviderMode = _usesSingleProviderConfiguration(current.routes);
    var changed = current.routes.length != AiTaskProfile.values.length;
    final routesByTask = <AiTaskProfile, AiTaskRoute>{
      for (final route in current.routes) route.task: route,
    };

    final nextRoutes = AiTaskProfile.values.map((task) {
      final route = routesByTask[task];
      if (route == null) {
        changed = true;
        return AiTaskRoute(
          task: task,
          primaryProviderId: providerId,
          primaryModel: model,
        );
      }

      if (provider == null) {
        return route;
      }

      if (singleProviderMode) {
        if (route.primaryProviderId != providerId ||
            route.primaryModel != model) {
          changed = true;
          return route.copyWith(
            primaryProviderId: providerId,
            primaryModel: model,
          );
        }
        return route;
      }

      // 多模型形态：仅补空模型路由。
      if (route.primaryModel.isEmpty && model.isNotEmpty) {
        changed = true;
        return route.copyWith(
          primaryProviderId: providerId,
          primaryModel: model,
        );
      }

      return route;
    }).toList(growable: false);

    if (!changed) return current;
    return current.copyWith(routes: nextRoutes, updatedAt: DateTime.now());
  }

  /// 所有路由是否都指向同一个提供方与模型（默认的单一提供商形态）。
  ///
  /// 注意：不能拿第一条路由做基准——当提供商变更后第一条还是旧模型时，
  /// 该判断会误判为“多模型形态”而拒绝同步。判据：
  /// 1. providerId 全部一致；
  /// 2. 非空模型取值不超过一种（空值表示尚未迁移，视为跟随提供商）。
  bool _usesSingleProviderConfiguration(List<AiTaskRoute> routes) {
    if (routes.isEmpty) return true;
    final providerIds = <String>{};
    final nonEmptyModels = <String>{};
    for (final route in routes) {
      providerIds.add(route.primaryProviderId);
      if (route.primaryModel.isNotEmpty) {
        nonEmptyModels.add(route.primaryModel);
      }
      if (providerIds.length > 1 || nonEmptyModels.length > 1) return false;
    }
    return true;
  }
}
