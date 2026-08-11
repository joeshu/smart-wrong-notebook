import 'package:smart_wrong_notebook/src/data/remote/ai/ai_provider_capabilities.dart';
import 'package:smart_wrong_notebook/src/data/remote/ai/ai_prompt_builder.dart';
import 'package:smart_wrong_notebook/src/domain/models/ai_provider_config.dart';

/// Pure construction of provider-independent chat request payloads.
///
/// Authentication and network transport deliberately remain in
/// [AiAnalysisService]. This component only mirrors the existing payload
/// contract so it can be tested without Flutter, Dio, or credentials.
class AiRequestBuilder {
  const AiRequestBuilder();

  static const AiPromptBuilder _promptBuilder = AiPromptBuilder();

  Map<String, dynamic> buildChatPayload({
    required AiProviderConfig config,
    required List<Map<String, dynamic>> messages,
    required int maxTokens,
    required double temperature,
  }) {
    final payload = <String, dynamic>{
      'model': config.model,
      'messages': messages,
      'temperature': temperature,
      'max_tokens': maxTokens,
    };
    final mode = AiProviderCapabilities.resolve(config).structuredOutputMode;
    // Keep the exact response_format payload owned by the existing prompt
    // builder. The extraction must not silently drop the JSON schema body.
    final responseFormat = _promptBuilder.responseFormat(mode);
    if (responseFormat != null) payload['response_format'] = responseFormat;
    return payload;
  }
}
