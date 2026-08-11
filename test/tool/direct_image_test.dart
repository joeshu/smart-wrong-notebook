// ignore_for_file: avoid_print

import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

/// Direct image-to-model experiment:
/// Send the semicircle image directly to gpt-5.4 and gpt-5.5
/// WITHOUT any Phase 1 text extraction, to see if the two-phase
/// approach is causing gpt-5.4's calculation error.
void main() {
  final apiKey = Platform.environment['AI_TEST_API_KEY'] ??
      Platform.environment['AI_API_KEY'];
  const baseUrl = 'https://www.vbcode.io/v1';

  final models = ['gpt-5.4', 'gpt-5.5'];

  for (final model in models) {
    test('direct image to $model - semicircle area',
        timeout: const Timeout(Duration(minutes: 3)), () async {
      if (apiKey == null || apiKey.isEmpty) {
        markTestSkipped('Set AI_TEST_API_KEY or AI_API_KEY to run this test.');
        return;
      }

      final imageFile = File('test/fixtures/semicircle.png');
      expect(imageFile.existsSync(), isTrue,
          reason: 'test/fixtures/semicircle.png must exist');

      final imageBytes = await imageFile.readAsBytes();
      final base64Image = base64Encode(imageBytes);

      final dio = Dio(BaseOptions(
        baseUrl: baseUrl,
        headers: {
          'Authorization': 'Bearer $apiKey',
          'Content-Type': 'application/json',
        },
        connectTimeout: const Duration(seconds: 30),
        receiveTimeout: const Duration(seconds: 120),
      ));

      final response = await dio.post(
        '/chat/completions',
        data: {
          'model': model,
          'messages': [
            {
              'role': 'user',
              'content': [
                {
                  'type': 'text',
                  'text': '请看这张图片，求图中标注"半圆"的半圆面积。请给出详细的计算步骤和最终答案。',
                },
                {
                  'type': 'image_url',
                  'image_url': {
                    'url': 'data:image/png;base64,$base64Image',
                  },
                },
              ],
            },
          ],
          'max_tokens': 2000,
        },
      );

      final data = response.data is String
          ? jsonDecode(response.data as String)
          : response.data;

      final content = data['choices'][0]['message']['content'] as String;

      print('=== $model direct image result ===');
      print(content);
      print('=== end $model ===\n');
    });
  }
}
