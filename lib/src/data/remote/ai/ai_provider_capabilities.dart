import 'package:smart_wrong_notebook/src/domain/models/ai_provider_config.dart';

enum AiStructuredOutputMode {
  jsonSchema,
  jsonObject,
  jsonMimeType,
  promptOnly,
}

class AiProviderCapabilities {
  const AiProviderCapabilities({required this.structuredOutputMode});

  final AiStructuredOutputMode structuredOutputMode;

  bool get sendsResponseFormat =>
      structuredOutputMode == AiStructuredOutputMode.jsonSchema ||
      structuredOutputMode == AiStructuredOutputMode.jsonObject;

  static AiProviderCapabilities resolve(AiProviderConfig config) {
    final baseUrl = config.baseUrl.toLowerCase();
    final model = config.model.toLowerCase();

    if (model.contains('gemini') && !baseUrl.contains('openrouter')) {
      return const AiProviderCapabilities(
        structuredOutputMode: AiStructuredOutputMode.jsonMimeType,
      );
    }
    if (baseUrl.contains('api.openai.com') ||
        baseUrl.contains('openrouter') ||
        model.contains('gpt') ||
        model.contains('4o')) {
      // json_object preserves the existing optional visualAssumptions and
      // diagramData extensions. Full json_schema activation is deferred until
      // those polymorphic geometry objects have a lossless schema.
      return const AiProviderCapabilities(
        structuredOutputMode: AiStructuredOutputMode.jsonObject,
      );
    }
    return const AiProviderCapabilities(
      structuredOutputMode: AiStructuredOutputMode.promptOnly,
    );
  }
}
