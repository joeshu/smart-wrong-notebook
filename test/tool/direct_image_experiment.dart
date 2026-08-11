// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

/// Direct image-to-model experiment (standalone script).
/// Usage:
///   dart run test/tool/direct_image_experiment.dart gpt-5.5
///   dart run test/tool/direct_image_experiment.dart gpt-5.4
void main(List<String> args) async {
  final model = args.isNotEmpty ? args[0] : 'gpt-5.5';
  final apiKey = Platform.environment['AI_TEST_API_KEY'] ??
      Platform.environment['AI_API_KEY'];
  if (apiKey == null || apiKey.isEmpty) {
    print(
        'ERROR: set AI_TEST_API_KEY or AI_API_KEY before running this script.');
    exit(1);
  }
  const baseUrl = 'https://www.vbcode.io/v1';
  const imagePath = '/Users/tangjun/opencode/test/1.png';

  final imageFile = File(imagePath);
  if (!imageFile.existsSync()) {
    print('ERROR: image not found at $imagePath');
    exit(1);
  }

  final imageBytes = await imageFile.readAsBytes();
  final base64Image = base64Encode(imageBytes);
  print('Image loaded: ${imageBytes.length} bytes');
  print('Sending to model: $model ...\n');

  final dio = Dio(BaseOptions(
    baseUrl: baseUrl,
    headers: {
      'Authorization': 'Bearer $apiKey',
      'Content-Type': 'application/json',
    },
    connectTimeout: const Duration(seconds: 60),
    receiveTimeout: const Duration(minutes: 5),
  ));

  try {
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
    print('=== end $model ===');
  } on DioException catch (e) {
    print('DioException: ${e.type} - ${e.message}');
    if (e.response != null) {
      print('Response: ${e.response?.data}');
    }
    exit(1);
  }
}
