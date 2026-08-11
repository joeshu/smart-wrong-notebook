/// AI 服务类型（Phase 12-3）。
///
/// 用于区分不同的上游协议约定，影响请求头/响应解析的微调。
/// `custom` 表示通用 OpenAI 兼容协议（baseURL 自填）。
enum AiServiceType {
  openai,
  anthropic,
  custom;

  String get label => switch (this) {
        AiServiceType.openai => 'OpenAI 兼容',
        AiServiceType.anthropic => 'Anthropic',
        AiServiceType.custom => '自定义',
      };

  String get hint => switch (this) {
        AiServiceType.openai => '标准 OpenAI / 国内中转 / OneAPI 等 OpenAI 兼容接口',
        AiServiceType.anthropic => 'Anthropic Claude 官方 API',
        AiServiceType.custom => '自定义协议（按 OpenAI 兼容兜底）',
      };

  /// 序列化用的小写 name。
  String get serializedName => name;

  static AiServiceType fromSerializedName(String? value) {
    switch (value) {
      case 'anthropic':
        return AiServiceType.anthropic;
      case 'custom':
        return AiServiceType.custom;
      case 'openai':
      default:
        return AiServiceType.openai;
    }
  }
}

class AiProviderConfig {
  const AiProviderConfig({
    required this.id,
    required this.displayName,
    required this.baseUrl,
    required this.model,
    required this.apiKey,
    this.maxConcurrency = 2,
    this.timeoutSeconds = 60,
    this.serviceType = AiServiceType.openai,
    this.isPrivate = false,
  });

  final String id;
  final String displayName;
  final String baseUrl;
  final String model;
  final String apiKey;

  /// 多题并发分析的最大并发度。0 或负数视为默认 2。
  final int maxConcurrency;

  /// 单次 AI 请求超时秒数（Phase 12-3）。0 或负数视为默认 60。
  final int timeoutSeconds;

  /// AI 服务类型（Phase 12-3），决定请求适配器分支。
  final AiServiceType serviceType;
  /// 用户明确确认该服务为本地部署或私有服务。
  final bool isPrivate;

  /// 返回有效并发度（兜底默认 2）。
  int get effectiveMaxConcurrency => maxConcurrency > 0 ? maxConcurrency : 2;

  /// 返回有效超时秒数（兜底默认 60）。
  int get effectiveTimeoutSeconds => timeoutSeconds > 0 ? timeoutSeconds : 60;

  /// 返回有效 [Duration] 超时。
  Duration get effectiveTimeout =>
      Duration(seconds: effectiveTimeoutSeconds);

  AiProviderConfig copyWith({
    String? id,
    String? displayName,
    String? baseUrl,
    String? model,
    String? apiKey,
    int? maxConcurrency,
    int? timeoutSeconds,
    AiServiceType? serviceType,
    bool? isPrivate,
  }) =>
      AiProviderConfig(
        id: id ?? this.id,
        displayName: displayName ?? this.displayName,
        baseUrl: baseUrl ?? this.baseUrl,
        model: model ?? this.model,
        apiKey: apiKey ?? this.apiKey,
        maxConcurrency: maxConcurrency ?? this.maxConcurrency,
        timeoutSeconds: timeoutSeconds ?? this.timeoutSeconds,
        serviceType: serviceType ?? this.serviceType,
        isPrivate: isPrivate ?? this.isPrivate,
      );
}
