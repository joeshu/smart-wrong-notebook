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
    final raw = await _settings.getString(storageKey);
    if (raw != null && raw.isNotEmpty) {
      try {
        return AiModelStrategy.decode(raw);
      } catch (_) {
        // Corrupt strategy settings must not block the existing AI provider.
      }
    }
    final migrated = AiModelStrategy.fromLegacyProvider(
      await _settings.getAiProviderConfig(),
    );
    await save(migrated);
    return migrated;
  }

  Future<void> save(AiModelStrategy strategy) =>
      _settings.setString(storageKey, strategy.encode());

  Future<AiModelStrategy> selectPreset(AiStrategyPreset preset) async {
    final current = await load();
    final updated = current.copyWith(preset: preset, updatedAt: DateTime.now());
    await save(updated);
    return updated;
  }
}
