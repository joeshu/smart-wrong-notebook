enum LayoutProviderType { currentVision, customHttp, manualOnly }

class LayoutProviderConfig {
  const LayoutProviderConfig({
    required this.type,
    this.baseUrl = '',
    this.apiKey = '',
    this.secondaryApiKey = '',
  });

  final LayoutProviderType type;
  final String baseUrl;
  final String apiKey;
  final String secondaryApiKey;

  bool get isReady => type == LayoutProviderType.manualOnly ||
      type == LayoutProviderType.currentVision ||
      (type == LayoutProviderType.customHttp && baseUrl.isNotEmpty);
}
