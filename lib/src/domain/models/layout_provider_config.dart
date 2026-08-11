enum LayoutProviderType { currentVision, paddleCloud, mineruCloud, autoCloud, customHttp, manualOnly }

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
      (type == LayoutProviderType.paddleCloud && apiKey.isNotEmpty) ||
      (type == LayoutProviderType.mineruCloud && apiKey.isNotEmpty) ||
      (type == LayoutProviderType.autoCloud && apiKey.isNotEmpty && secondaryApiKey.isNotEmpty) ||
      (type == LayoutProviderType.customHttp && baseUrl.isNotEmpty);
}
