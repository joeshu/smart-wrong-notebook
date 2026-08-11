// ignore_for_file: avoid_print
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';

/// Experiment: single-pass analysis without Phase 1 locking.
/// Tests whether gpt-5.5 can produce consistent visualAssumptions + steps
/// in a single call without any pre-extracted hypotheses.
///
/// Usage:
///   dart run test/tool/single_pass_experiment.dart gpt-5.5
///   dart run test/tool/single_pass_experiment.dart gpt-5.4
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
  print('Model: $model');
  print('Mode: single-pass (no Phase 1 locking)\n');

  final dio = Dio(BaseOptions(
    baseUrl: baseUrl,
    headers: {
      'Authorization': 'Bearer $apiKey',
      'Content-Type': 'application/json',
    },
    connectTimeout: const Duration(seconds: 60),
    receiveTimeout: const Duration(minutes: 5),
  ));

  // This prompt mirrors the production analysis prompt but WITHOUT any
  // locked hypotheses injection. The model must read the image, extract
  // structured info, AND solve — all in one pass.
  const prompt = '''请仔细观察图片，完成以下任务：

1. 提取图中的题目信息（题干、标注含义、几何关系）
2. 解题并给出详细步骤和最终答案

请严格按以下 JSON 格式输出（不要输出其他内容）：

```json
{
  "reconstructedQuestionText": "从图片中还原的完整题干",
  "visualAssumptions": {
    "targetObject": "求解目标对象",
    "targetQuestion": "求什么（面积/周长/角度等）",
    "measurements": [
      {"label": "图中标注", "meaning": "该标注的几何含义", "confidence": "high/medium/low"}
    ],
    "solutionBasis": ["解题依据的几何关系列表"],
    "uncertainItems": ["无法确定的信息"]
  },
  "steps": ["解题步骤1", "步骤2", "..."],
  "finalAnswer": "最终答案",
  "finalAnswerDerivation": "答案推导的简要说明"
}
```

要求：
- 直接观察图片，自由理解图形含义
- steps 中引用的数字必须与 measurements 中的含义一致
- 如果发现某个标注有多种可能含义，选择最合理的一种并在 confidence 中标注''';

  try {
    final response = await dio.post(
      '/chat/completions',
      data: {
        'model': model,
        'messages': [
          {
            'role': 'system',
            'content': '你是数学解题专家。请直接观察图片并解题，输出结构化 JSON。',
          },
          {
            'role': 'user',
            'content': [
              {'type': 'text', 'text': prompt},
              {
                'type': 'image_url',
                'image_url': {'url': 'data:image/png;base64,$base64Image'},
              },
            ],
          },
        ],
        'max_tokens': 3000,
      },
    );

    final data = response.data is String
        ? jsonDecode(response.data as String)
        : response.data;

    final content = data['choices'][0]['message']['content'] as String;

    print('=== $model single-pass result ===');
    print(content);
    print('\n=== end $model ===');

    // Try to parse and check consistency
    final jsonMatch = RegExp(r'\{[\s\S]*\}').firstMatch(content);
    if (jsonMatch != null) {
      try {
        final parsed = jsonDecode(jsonMatch.group(0)!) as Map<String, dynamic>;
        final answer = parsed['finalAnswer'] ?? '';
        final steps = parsed['steps'] as List<dynamic>? ?? [];
        final measurements = (parsed['visualAssumptions']
                as Map<String, dynamic>?)?['measurements'] as List<dynamic>? ??
            [];

        print('\n=== Consistency Check ===');
        print('Final answer: $answer');
        print('Number of steps: ${steps.length}');
        print('Measurements:');
        for (final m in measurements) {
          print('  - ${m['label']} → ${m['meaning']} (${m['confidence']})');
        }

        // Check if answer matches expected 29π/2
        final answerStr = answer.toString().toLowerCase();
        final isCorrect =
            answerStr.contains('29') && answerStr.contains('pi') ||
                answerStr.contains('29π') ||
                answerStr.contains('29\\pi') ||
                answerStr.contains('14.5π');
        print('\nAnswer contains 29π/2: $isCorrect');
      } catch (e) {
        print('\nFailed to parse JSON for consistency check: $e');
      }
    }
  } on DioException catch (e) {
    print('DioException: ${e.type} - ${e.message}');
    if (e.response != null) {
      print('Response: ${e.response?.data}');
    }
    exit(1);
  }
}
