import 'package:flutter_test/flutter_test.dart';
import 'package:smart_wrong_notebook/src/data/remote/ai/ai_provider_capabilities.dart';
import 'package:smart_wrong_notebook/src/domain/models/ai_provider_config.dart';

void main() {
  test('native Gemini uses JSON MIME type', () {
    final capabilities = AiProviderCapabilities.resolve(
      _config(baseUrl: 'https://generativelanguage.googleapis.com', model: 'gemini-2.0-flash'),
    );
    expect(
      capabilities.structuredOutputMode,
      AiStructuredOutputMode.jsonMimeType,
    );
  });

  test('OpenAI and OpenRouter use compatible json_object mode', () {
    expect(
      AiProviderCapabilities.resolve(
        _config(baseUrl: 'https://api.openai.com/v1', model: 'gpt-4o'),
      ).structuredOutputMode,
      AiStructuredOutputMode.jsonObject,
    );
    expect(
      AiProviderCapabilities.resolve(
        _config(baseUrl: 'https://openrouter.ai/api/v1', model: 'vendor/model'),
      ).structuredOutputMode,
      AiStructuredOutputMode.jsonObject,
    );
  });

  test('unknown compatible provider remains prompt-only', () {
    final capabilities = AiProviderCapabilities.resolve(
      _config(baseUrl: 'https://example.com/chat', model: 'vision-model'),
    );
    expect(
      capabilities.structuredOutputMode,
      AiStructuredOutputMode.promptOnly,
    );
    expect(capabilities.sendsResponseFormat, isFalse);
  });
}

AiProviderConfig _config({required String baseUrl, required String model}) =>
    AiProviderConfig(
      id: 'test',
      displayName: 'Test',
      baseUrl: baseUrl,
      model: model,
      apiKey: 'not-a-real-key',
    );
