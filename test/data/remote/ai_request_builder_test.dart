import 'package:flutter_test/flutter_test.dart';
import 'package:smart_wrong_notebook/src/data/remote/ai/ai_request_builder.dart';
import 'package:smart_wrong_notebook/src/domain/models/ai_provider_config.dart';

void main() {
  test('builds an OpenAI-compatible chat payload without credentials', () {
    const builder = AiRequestBuilder();
    const config = AiProviderConfig(
      id: 'test-provider',
      displayName: 'Test provider',
      baseUrl: 'https://example.invalid/v1',
      model: 'gpt-test',
      apiKey: '',
    );

    final payload = builder.buildChatPayload(
      config: config,
      messages: const [
        {'role': 'system', 'content': 'system prompt'},
        {'role': 'user', 'content': 'question'},
      ],
      maxTokens: 321,
      temperature: 0.3,
    );

    expect(payload, {
      'model': 'gpt-test',
      'messages': [
        {'role': 'system', 'content': 'system prompt'},
        {'role': 'user', 'content': 'question'},
      ],
      'temperature': 0.3,
      'max_tokens': 321,
      'response_format': {'type': 'json_object'},
    });
    expect(payload.containsKey('apiKey'), isFalse);
    expect(payload.containsKey('Authorization'), isFalse);
  });

  test('omits response_format for providers that only support prompt instructions', () {
    const builder = AiRequestBuilder();
    const config = AiProviderConfig(
      id: 'test-provider',
      displayName: 'Test provider',
      baseUrl: 'https://example.invalid/custom',
      model: 'local-model',
      apiKey: '',
    );

    final payload = builder.buildChatPayload(
      config: config,
      messages: const [],
      maxTokens: 10,
      temperature: 0.7,
    );

    expect(payload, {
      'model': 'local-model',
      'messages': <Map<String, dynamic>>[],
      'temperature': 0.7,
      'max_tokens': 10,
    });
  });
}
