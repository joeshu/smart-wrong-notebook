import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'dart:math' as math;
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:smart_wrong_notebook/src/data/remote/ai/ai_analysis_response_contract.dart';
import 'package:smart_wrong_notebook/src/data/remote/ai/ai_json_decoder.dart';
import 'package:smart_wrong_notebook/src/data/remote/ai/ai_prompt_builder.dart';
import 'package:smart_wrong_notebook/src/data/remote/ai/ai_request_builder.dart';
import 'package:smart_wrong_notebook/src/data/remote/ai/ai_provider_capabilities.dart';
import 'package:smart_wrong_notebook/src/data/repositories/settings_repository.dart';
import 'package:smart_wrong_notebook/src/domain/models/ai_provider_config.dart';
import 'package:smart_wrong_notebook/src/domain/models/capture_mode.dart';
import 'package:smart_wrong_notebook/src/domain/models/analysis_result.dart';
import 'package:smart_wrong_notebook/src/domain/models/generated_exercise.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_split_result.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_region.dart';
import 'package:smart_wrong_notebook/src/domain/models/specialized_analysis.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';
import 'package:smart_wrong_notebook/src/domain/models/ai_analysis_contract.dart';
import 'package:smart_wrong_notebook/src/domain/models/ai_analysis_payload.dart';
import 'package:smart_wrong_notebook/src/domain/models/ai_analysis_patch.dart';
import 'package:smart_wrong_notebook/src/domain/models/ai_response_diagnostics.dart';
import 'package:smart_wrong_notebook/src/shared/utils/composite_worksheet_detector.dart';
import 'package:smart_wrong_notebook/src/shared/utils/latex_normalizer.dart';

export 'package:smart_wrong_notebook/src/domain/models/ai_analysis_payload.dart';

part 'ai_analysis_service_fake.dart';

enum _ExerciseDomain {
  generic,
  algebraEquation,
  equationSystem,
  functionEvaluation,
  proportionalRelation,
  planeGeometryArea,
  planeGeometryAngle,
  planeGeometryLength,
  solidGeometryVolume,
}

enum _ExerciseObject {
  generic,
  linearEquation,
  quadraticEquation,
  equationSystem,
  functionExpression,
  proportionalRelation,
  circleFamily,
  square,
  triangle,
  rightTriangle,
  coneCylinder,
}

class _Point2 {
  const _Point2(this.x, this.y);

  final double x;
  final double y;
}

class _ExteriorAngleSpec {
  const _ExteriorAngleSpec({
    required this.extensionPoint,
    required this.vertex,
    required this.basePoint,
  });

  final String extensionPoint;
  final String vertex;
  final String basePoint;
}

class _FramedSemicircleSpec {
  const _FramedSemicircleSpec({
    required this.top,
    required this.bottom,
    required this.height,
  });

  final int top;
  final int bottom;
  final int height;

  int get horizontalDiff => (bottom - top).abs();
  int get diameterSquared => horizontalDiff * horizontalDiff + height * height;
}

enum _ExerciseMethod {
  linearSolve,
  squareRoot,
  elimination,
  functionSubstitution,
  ratioRelation,
  formulaSubstitution,
  halfArea,
  largeMinusSmall,
  splitAndCombine,
  shadedArea,
  angleSum,
  pythagorean,
  equalLengthRelation,
  perpendicularBisector,
  coordinateGeometry,
}

enum _ExerciseVariant {
  rightTriangleLength,
  circleArea,
  semicircleArea,
  compositeSemicircleArea,
  annulusOrShadedArea,
  squarePerpendicularBisectorLength,
  coneVolume,
  cylinderVolume,
}

enum _TopicProfileSource { sourceQuestion, exercise }

class _ExerciseTopicProfile {
  const _ExerciseTopicProfile({
    required this.domain,
    required this.object,
    required this.methods,
    required this.hasStrongSignal,
    this.variant,
  });

  final _ExerciseDomain domain;
  final _ExerciseObject object;
  final Set<_ExerciseMethod> methods;
  final bool hasStrongSignal;
  final _ExerciseVariant? variant;
}

class AiQuestionExtractionResult {
  const AiQuestionExtractionResult({
    required this.extractedQuestionText,
    required this.normalizedQuestionText,
    this.subject,
    this.splitResult,
    this.studentAnswer,
    this.ocrConfidence,
  });

  final String extractedQuestionText;
  final String normalizedQuestionText;
  final Subject? subject;
  final QuestionSplitResult? splitResult;
  final double? ocrConfidence;

  /// 手写解答过程转录结果。
  ///
  /// 仅在录入模式为 [CaptureMode.handwritten] 或 [CaptureMode.mixed] 时由 AI
  /// 返回；[CaptureMode.printed] 模式下保持为 null，沿用"忽略手写批改"行为。
  final String? studentAnswer;
}

/// 校验题干文本中 LaTeX 结构是否平衡。
/// 返回 null 表示通过；返回 String 表示问题具体描述（仅作 debugPrint 警告，
/// 不阻塞业务流程）。
String? validateLatexStructure(String text) {
  if (text.isEmpty) return null;

  // 1. `$$...$$` 必须成对。
  final doubleDollarCount = RegExp(r'\$\$').allMatches(text).length;
  if (doubleDollarCount.isOdd) {
    return 'LaTeX 定界符不匹配：\$\$ 未成对';
  }

  // 2. 单 `$...$` 在去掉 `$$` 后必须成对。
  final textWithoutDoubleDollar = text.replaceAll(r'$$', '');
  final singleDollarCount =
      RegExp(r'\$').allMatches(textWithoutDoubleDollar).length;
  if (singleDollarCount.isOdd) {
    return 'LaTeX 定界符不匹配：\$ 未成对';
  }

  // 3. `\begin{env}` 与 `\end{env}` 配对（栈式匹配）。
  final envMatches = <_LatexEnvMatch>[];
  for (final m in RegExp(r'\\begin\{([^}]+)\}').allMatches(text)) {
    envMatches.add(_LatexEnvMatch(m.group(1)!, m.start, true));
  }
  for (final m in RegExp(r'\\end\{([^}]+)\}').allMatches(text)) {
    envMatches.add(_LatexEnvMatch(m.group(1)!, m.start, false));
  }
  envMatches.sort((a, b) => a.position.compareTo(b.position));
  final envStack = <String>[];
  for (final m in envMatches) {
    if (m.isBegin) {
      envStack.add(m.env);
    } else {
      if (envStack.isEmpty) {
        return 'LaTeX 环境不匹配：\\end{${m.env}} 缺少对应的 \\begin';
      }
      final last = envStack.removeLast();
      if (last != m.env) {
        return 'LaTeX 环境不匹配：\\begin{$last} 与 \\end{${m.env}} 不对应';
      }
    }
  }
  if (envStack.isNotEmpty) {
    return 'LaTeX 环境不匹配：\\begin{${envStack.last}} 缺少对应的 \\end';
  }

  // 4. 数学环境内的 `()[]{}` 括号匹配。
  final bracketIssue = _checkBracketsInMathEnvironments(text);
  if (bracketIssue != null) return bracketIssue;

  return null;
}

class _LatexEnvMatch {
  _LatexEnvMatch(this.env, this.position, this.isBegin);
  final String env;
  final int position;
  final bool isBegin;
}

/// 从文本中提取数学环境片段（`$...$`、`$$...$$`、`\(...\)`、`\[...\]`）。
/// 若定界符本身不平衡，返回空列表（外层已先行告警）。
List<String> _extractMathEnvironments(String text) {
  final segments = <String>[];
  // $$ ... $$
  for (final m in RegExp(r'\$\$([\s\S]*?)\$\$').allMatches(text)) {
    segments.add(m.group(1)!);
  }
  // 移除已匹配的 $$ 块，再提取单 $ 块
  final textWithoutDoubleDollar = text.replaceAll(RegExp(r'\$\$[\s\S]*?\$\$'), '');
  for (final m in RegExp(r'\$([^$]*?)\$').allMatches(textWithoutDoubleDollar)) {
    segments.add(m.group(1)!);
  }
  // \( ... \)
  for (final m in RegExp(r'\\\(([\s\S]*?)\\\)').allMatches(text)) {
    segments.add(m.group(1)!);
  }
  // \[ ... \]
  for (final m in RegExp(r'\\\[([\s\S]*?)\\\]').allMatches(text)) {
    segments.add(m.group(1)!);
  }
  return segments;
}

String? _checkBracketsInMathEnvironments(String text) {
  for (final segment in _extractMathEnvironments(text)) {
    final issue = _checkBracketBalance(segment);
    if (issue != null) return issue;
  }
  return null;
}

String? _checkBracketBalance(String text) {
  const pairs = <String, String>{')': '(', ']': '[', '}': '{'};
  final opens = pairs.values.toSet();
  final stack = <String>[];
  for (var i = 0; i < text.length; i++) {
    final c = text[i];
    if (opens.contains(c)) {
      stack.add(c);
    } else if (pairs.containsKey(c)) {
      if (stack.isEmpty) {
        return '括号不匹配：多余的右括号 "$c"';
      }
      final top = stack.removeLast();
      if (top != pairs[c]) {
        return '括号不匹配："$top" 与 "$c" 不对应';
      }
    }
  }
  if (stack.isNotEmpty) {
    return '括号不匹配：未闭合的左括号 "${stack.last}"';
  }
  return null;
}

/// 对 AI 提取出的题干文本做保守的 OCR 混淆字符纠错。
/// 仅在明确上下文里替换，避免误纠正常字母。
String correctCommonOcrErrors(String text, {required String subject}) {
  if (text.isEmpty) return text;
  final isMath = subject == Subject.math.label || subject == Subject.math.name;
  final isPhysics =
      subject == Subject.physics.label || subject == Subject.physics.name;
  if (!isMath && !isPhysics) return text;

  var result = text;
  if (isMath) {
    // 数字上下文中的 l → 1：例如 "l2" / "3l" / "l00"
    result = result.replaceAllMapped(
      RegExp(r'(?<=\d)l|l(?=\d)'),
      (_) => '1',
    );
    // 数字上下文中的 O → 0：例如 "O2" / "3O" / "O0"
    result = result.replaceAllMapped(
      RegExp(r'(?<=\d)O|O(?=\d)'),
      (_) => '0',
    );
    // 独立的 V → √：前后为非字母数字
    result = result.replaceAllMapped(
      RegExp(r'(?<![A-Za-z0-9])V(?![A-Za-z0-9])'),
      (_) => '√',
    );
    // 数字之间的 x → ×：例如 "3x4" → "3×4"，但 "x+1=3" 保留
    result = result.replaceAllMapped(
      RegExp(r'(?<=\d)x(?=\d)'),
      (_) => '×',
    );
  }
  if (isPhysics) {
    // 物理题：O 与 0 混淆纠错（数字上下文）
    result = result.replaceAllMapped(
      RegExp(r'(?<=\d)O|O(?=\d)'),
      (_) => '0',
    );
  }
  return result;
}

class AiAnalysisService {
  AiAnalysisService({required this.settingsRepository});

  final SettingsRepository settingsRepository;
  static const AiJsonDecoder _jsonDecoder = AiJsonDecoder();
  static const AiPromptBuilder _promptBuilder = AiPromptBuilder();
  static const AiRequestBuilder _requestBuilder = AiRequestBuilder();

  static const _maxRetries = 2; // 最多重试2次（总共3次请求）
  static const _baseDelayMs = 1000; // 基础延迟1秒
  // 429 缺省退避（秒），未读到 Retry-After 时使用。
  static const _defaultRetryAfterSeconds = 5;

  /// 判断是否需要重试，并返回应等待的时长（null 表示不重试）。
  /// 429 优先使用响应头 Retry-After（秒数）；其它可重试错误走指数退避。
  Duration? _retryBackoff(DioException e, int attempt) {
    final status = e.response?.statusCode;
    final is429 = status == 429;
    final isServer5xx = status != null && status >= 500 && status < 600;
    final isNetworkOrTimeout = e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.connectionError;

    final shouldRetry = is429 || isServer5xx || isNetworkOrTimeout;
    if (!shouldRetry) return null;
    if (attempt > _maxRetries) return null;

    if (is429) {
      final retryAfterSeconds = _parseRetryAfterHeader(e);
      return Duration(seconds: retryAfterSeconds);
    }
    // 指数退避：1s/2s/4s。
    final delayMs = _baseDelayMs * (1 << (attempt - 1));
    return Duration(milliseconds: delayMs);
  }

  int _parseRetryAfterHeader(DioException e) {
    final raw = e.response?.headers.value('Retry-After');
    if (raw == null || raw.isEmpty) return _defaultRetryAfterSeconds;
    final parsed = int.tryParse(raw.trim());
    if (parsed != null && parsed > 0) return parsed;
    // HTTP 日期格式不支持，回退缺省。
    return _defaultRetryAfterSeconds;
  }

  String _retryReason(DioException e) {
    final status = e.response?.statusCode;
    if (status == 429) return '429 限流';
    if (status != null && status >= 500) return 'HTTP $status';
    return e.type.name;
  }

  static const diagnosticsRawResponseEnabledKey =
      'ai_diagnostics_raw_response_enabled';
  static const diagnosticsRawRetentionDaysKey =
      'ai_diagnostics_raw_retention_days';
  static const defaultDiagnosticsRawRetentionDays = 7;

  /// 带重试的 POST 请求（指数退避；429 读 Retry-After 头）
  Future<Response<T>> _retryPost<T>(
    Dio dio,
    String path, {
    required Map<String, dynamic> data,
    int attempt = 1,
  }) async {
    try {
      return await dio.post<T>(path, data: data);
    } on DioException catch (e) {
      // 不重试 4xx（除 429、408 外），例如 401/403/404。
      final backoff = _retryBackoff(e, attempt);
      if (backoff == null) {
        rethrow;
      }
      final reason = _retryReason(e);
      debugPrint(
          '[AiAnalysisService] 请求失败($reason)，${backoff.inMilliseconds}ms 后重试 (第 $attempt 次, 共 $_maxRetries 次)...');
      await Future.delayed(backoff);
      return _retryPost(dio, path, data: data, attempt: attempt + 1);
    }
  }

  factory AiAnalysisService.fake() => _FakeAiAnalysisService();

  /// 从 Dio response 中安全提取 OpenAI 格式的 content 字段。
  /// 代理服务偶尔返回非 application/json content-type，导致 response.data 为原始 String。
  String _extractContentFromResponse(Response response) {
    dynamic data = response.data;
    if (data is String) {
      data = jsonDecode(data);
    }
    return (data as Map<String, dynamic>)['choices'][0]['message']['content']
        as String;
  }

  Dio _createClient(AiProviderConfig config) {
    // Phase 12-3：连接超时按用户配置（兜底 60s），接收超时按 4 倍连接超时
    // 兜底（避免大模型流式响应被过早掐断）。
    final connectTimeout = config.effectiveTimeout;
    final receiveTimeout = Duration(
      seconds: connectTimeout.inSeconds * 4,
    );
    return Dio(BaseOptions(
      baseUrl: config.baseUrl.endsWith('/')
          ? config.baseUrl.substring(0, config.baseUrl.length - 1)
          : config.baseUrl,
      headers: <String, String>{
        'Content-Type': 'application/json',
        if (config.apiKey.isNotEmpty)
          'Authorization': 'Bearer ${config.apiKey}',
      },
      connectTimeout: connectTimeout,
      receiveTimeout: receiveTimeout,
    ));
  }

  /// 测试 API 连接
  Future<void> testConnection(AiProviderConfig config) async {
    debugPrint('[AiAnalysisService] testConnection called');
    debugPrint('[AiAnalysisService] baseUrl: ${config.baseUrl}');
    debugPrint('[AiAnalysisService] model: ${config.model}');

    final dio = _createClient(config);
    final baseUrl = config.baseUrl.toLowerCase();

    try {
      // 只检查 HTTP 200 状态码，不检查返回内容
      if (baseUrl.contains('openrouter')) {
        debugPrint('[AiAnalysisService] Testing OpenRouter endpoint');
        await dio.post('/chat/completions', data: <String, dynamic>{
          'model': config.model,
          'messages': [
            {'role': 'user', 'content': 'Hi'},
          ],
          'max_tokens': 1,
        });
      } else if (config.model.toLowerCase().contains('gemini')) {
        debugPrint('[AiAnalysisService] Testing Gemini endpoint');
        await dio.post(
          '/v1beta/models/${config.model}:generateContent',
          data: <String, dynamic>{
            'contents': [
              {
                'parts': [
                  {'text': 'Hi'}
                ]
              },
            ],
            'generationConfig': {'maxOutputTokens': 1},
          },
        );
      } else {
        debugPrint('[AiAnalysisService] Testing default OpenAI endpoint');
        await dio.post('/chat/completions', data: <String, dynamic>{
          'model': config.model,
          'messages': [
            {'role': 'user', 'content': 'Hi'},
          ],
          'max_tokens': 1,
        });
      }

      debugPrint('[AiAnalysisService] Connection test passed (HTTP 200)');
    } on DioException catch (e) {
      debugPrint(
          '[AiAnalysisService] testConnection DioException: type=${e.type}, message=${e.message}');
      throw AiAnalysisException(_dioErrorMessage(e));
    } catch (e) {
      debugPrint('[AiAnalysisService] Exception: $e');
      throw AiAnalysisException('测试失败: $e');
    }
  }

  /// Uses the configured vision-capable model to suggest question regions on
  /// one worksheet page. The caller must still show them for user confirmation.
  Future<List<QuestionRegion>> detectWorksheetQuestionRegions(
      {required String imagePath}) async {
    final config = await _requireConfig();
    final bytes = await File(imagePath).readAsBytes();
    final content = await _requestAiContentWithImage(
      config: config,
      systemPrompt: '你是试卷版面分析器。只返回 JSON，不要 Markdown。',
      prompt: '''识别这张试卷图片中彼此独立的“大题”区域。返回格式：
{"regions":[{"number":"1","x":0.05,"y":0.08,"width":0.9,"height":0.18,"confidence":0.9}],"warning":"可选提示"}
规则：x/y/width/height 必须为 0~1 的归一化数字；每框包含题号、题干、选项及必要图形；共享材料和其子问尽量保留在同一框；不确定时降低 confidence；不要给答案或题目文字。''',
      imageBytes: bytes,
      maxTokens: 1800,
      imageDetail: 'high',
      temperature: 0.1,
    );
    return _parseWorksheetRegions(content);
  }

  List<QuestionRegion> _parseWorksheetRegions(String content) {
    final raw = _extractJsonObject(content);
    if (raw == null) throw AiAnalysisException('版面服务未返回可识别的 JSON 候选框');
    try {
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      final items = decoded['regions'] as List? ?? const <dynamic>[];
      final regions = <QuestionRegion>[];
      for (var index = 0; index < items.length; index++) {
        final item = items[index];
        if (item is! Map) continue;
        final x = _layoutNumber(item['x']);
        final y = _layoutNumber(item['y']);
        final width = _layoutNumber(item['width']);
        final height = _layoutNumber(item['height']);
        if (x == null || y == null || width == null || height == null) continue;
        final left = x.clamp(0.0, 1.0).toDouble();
        final top = y.clamp(0.0, 1.0).toDouble();
        final safeWidth = width.clamp(0.0, 1.0 - left).toDouble();
        final safeHeight = height.clamp(0.0, 1.0 - top).toDouble();
        if (safeWidth < .10 || safeHeight < .06) continue;
        regions.add(QuestionRegion(
          id: 'vision-$index-${DateTime.now().microsecondsSinceEpoch}',
          normalizedRect: Rect.fromLTWH(left, top, safeWidth, safeHeight),
          detectedNumber: item['number']?.toString(),
          confidence: (_layoutNumber(item['confidence']) ?? .5)
              .clamp(0.0, 1.0).toDouble(),
          source: QuestionRegionSource.layoutModel,
        ));
      }
      if (regions.isEmpty) throw AiAnalysisException('未识别到有效题目框，请改为手动框选');
      return regions;
    } catch (e) {
      if (e is AiAnalysisException) rethrow;
      throw AiAnalysisException('候选题框解析失败：$e');
    }
  }

  String? _extractJsonObject(String text) {
    final fenced = RegExp(r'```(?:json)?\s*([\s\S]*?)```', caseSensitive: false)
        .firstMatch(text);
    final candidate = (fenced?.group(1) ?? text).trim();
    final start = candidate.indexOf('{');
    final end = candidate.lastIndexOf('}');
    return start >= 0 && end > start ? candidate.substring(start, end + 1) : null;
  }

  double? _layoutNumber(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  /// 分析题目 - 图形题先直接读图解题，其他带图题保持先提取结构再分析。
  Future<AnalysisResult> analyzeQuestion({
    required String correctedText,
    required String subjectName,
    String? imagePath, // 可选：图片路径
    String studentAnswer = '',
  }) async {
    debugPrint('[AiAnalysisService] analyzeQuestion called');
    debugPrint(
        '[AiAnalysisService] - correctedText: ${correctedText.isNotEmpty ? "provided (${correctedText.length} chars)" : "empty"}');
    debugPrint('[AiAnalysisService] - subjectName: $subjectName');
    debugPrint('[AiAnalysisService] - imagePath: $imagePath');

    var textForAnalysis = correctedText;
    var resolvedSubject = _parseSubject(subjectName);

    if (imagePath != null && File(imagePath).existsSync()) {
      final shouldSolveImageDirectly = isGraphicalQuestion(
        correctedText,
        subjectName,
        imagePath: imagePath,
      );
      if (shouldSolveImageDirectly) {
        return analyzeExtractedQuestion(
          correctedText: correctedText,
          subjectName: resolvedSubject?.name ?? subjectName,
          imagePath: imagePath,
          studentAnswer: studentAnswer,
        );
      }

      final extraction = await extractQuestionStructure(
        subjectName: subjectName,
        imagePath: imagePath,
        textHint: correctedText,
      );
      if (extraction.normalizedQuestionText.isNotEmpty) {
        textForAnalysis = extraction.normalizedQuestionText;
      }
      resolvedSubject ??= extraction.subject;
    }

    return analyzeExtractedQuestion(
      correctedText: textForAnalysis,
      subjectName: resolvedSubject?.name ?? subjectName,
      imagePath: imagePath,
      studentAnswer: studentAnswer,
    );
  }

  Future<QuestionSplitResult> splitQuestionCandidates({
    required String text,
    String? subjectName,
    QuestionSplitResult Function(String text)? fallbackSplit,
  }) async {
    final subject = subjectName != null ? _parseSubject(subjectName) : null;
    final splitter = fallbackSplit ??
        (String t) => _defaultSplitQuestionCandidates(t, subject: subject);
    return splitter(text);
  }

  Future<AiQuestionExtractionResult> extractQuestionStructure({
    required String subjectName,
    required String imagePath,
    String textHint = '',
    CaptureMode mode = CaptureMode.printed,
  }) async {
    debugPrint('[AiAnalysisService] extractQuestionStructure called (mode=$mode)');

    final config = await _requireConfig();
    final imageBytes = await File(imagePath).readAsBytes();
    try {
      final systemPrompt = await _loadExtractionSystemPrompt(mode: mode);
      final prompt = _buildExtractionPrompt(
        subjectName: subjectName,
        textHint: textHint,
        mode: mode,
      );
      const firstMaxTokens = 1600;
      const firstImageDetail = 'auto';
      final extractionContent = await _requestAiContentWithImage(
        config: config,
        systemPrompt: systemPrompt,
        prompt: prompt,
        imageBytes: imageBytes,
        maxTokens: firstMaxTokens,
        imageDetail: firstImageDetail,
      );
      final extraction = await _parseContentWithJsonRetry(
        firstContent: extractionContent,
        parse: _parseExtractionResponse,
        retryContentFetcher: () => _requestAiContentWithImage(
          config: config,
          systemPrompt: systemPrompt,
          prompt: prompt,
          imageBytes: imageBytes,
          maxTokens: firstMaxTokens + 500,
          imageDetail: firstImageDetail,
          temperature: 0.3,
        ),
        stage: 'extraction',
      );

      // 识别为空但图非空告警：图片较大但未提取到文字，可能是图片质量差或纯图形题。
      if (imageBytes.length > 50 * 1024 &&
          extraction.extractedQuestionText.length < 5) {
        debugPrint(
            '[AiAnalysisService] 提取文本为空但图片较大(${imageBytes.length} bytes)，提示重拍');
        throw AiAnalysisException(
            '未识别到文字内容，可能图片质量差或为纯图形题，建议重拍或手动输入');
      }

      return AiQuestionExtractionResult(
        extractedQuestionText: extraction.extractedQuestionText,
        normalizedQuestionText: extraction.normalizedQuestionText,
        subject: extraction.subject,
        splitResult: extraction.splitResult,
        studentAnswer: extraction.studentAnswer,
        ocrConfidence: extraction.ocrConfidence,
      );
    } on DioException catch (e) {
      debugPrint(
          '[AiAnalysisService] extract DioException: type=${e.type}, message=${e.message}, status=${e.response?.statusCode}');
      throw AiAnalysisException(_dioErrorMessage(e));
    } catch (e) {
      debugPrint('[AiAnalysisService] extract Exception: $e');
      if (e is AiAnalysisException) rethrow;
      throw AiAnalysisException('AI 识别题目失败: $e');
    }
  }

  Future<List<CandidateAnalysisPayload>> analyzeSplitCandidates({
    required String questionId,
    required String subjectName,
    required QuestionSplitResult splitResult,
    String? imagePath,
    void Function(int completed, int total, {int failed})? onProgress,
  }) async {
    final candidates = splitResult.candidates;
    final total = candidates.length;
    var completed = 0;
    var failed = 0;
    final payloads = <CandidateAnalysisPayload>[];

    // 并发度从配置读取，便于根据模型限流调整；缺省为 2。
    final config = await settingsRepository.getAiProviderConfig();
    final concurrency = config?.effectiveMaxConcurrency ?? 2;

    debugPrint(
        '[AiAnalysisService] analyzeSplitCandidates: $total candidates, concurrency=$concurrency');

    for (var start = 0; start < candidates.length; start += concurrency) {
      final batch =
          candidates.skip(start).take(concurrency).map((candidate) async {
        try {
          final payload = await _analyzeSplitCandidateWithRetry(
            questionId: questionId,
            subjectName: subjectName,
            candidate: candidate,
            imagePath: imagePath,
          );
          completed++;
          onProgress?.call(completed, total, failed: failed);
          return payload;
        } catch (e) {
          debugPrint(
              '[AiAnalysisService] candidate ${candidate.order} failed after retry: $e');
          failed++;
          completed++;
          onProgress?.call(completed, total, failed: failed);
          return CandidateAnalysisPayload.failed(
            candidateId: candidate.id,
            order: candidate.order,
            questionText: candidate.text,
            errorMessage: friendlyAiErrorMessage(e),
          );
        }
      }).toList();

      payloads.addAll(await Future.wait(batch));
    }

    payloads.sort((a, b) => a.order.compareTo(b.order));
    return payloads;
  }

  Future<CandidateAnalysisPayload> _analyzeSplitCandidateWithRetry({
    required String questionId,
    required String subjectName,
    required QuestionSplitCandidate candidate,
    String? imagePath,
  }) async {
    Object? lastError;
    for (var attempt = 1; attempt <= 2; attempt++) {
      try {
        final candidateText = candidate.text;
        final candidateImagePath = isGraphicalQuestion(
          candidateText,
          subjectName,
          imagePath: imagePath,
        )
            ? imagePath
            : null;
        final analysis = await analyzeExtractedQuestion(
          correctedText: candidateText,
          subjectName: subjectName,
          imagePath: candidateImagePath,
        );
        final exercises = analysis is ParsedAnalysisResult
            ? extractGeneratedExercisesFromContent(
                analysis.rawContent,
                questionId: '$questionId-${candidate.order}',
                analysis: analysis,
                sourceQuestionText: candidateText,
              )
            : extractGeneratedExercises(
                analysis,
                questionId: '$questionId-${candidate.order}',
                sourceQuestionText: candidateText,
              );

        return CandidateAnalysisPayload(
          candidateId: candidate.id,
          order: candidate.order,
          questionText: candidateText,
          analysisResult: analysis,
          savedExercises: exercises,
          subject: analysis.subject,
          aiTags: analysis.aiTags,
          aiKnowledgePoints: analysis.knowledgePoints,
        );
      } catch (e) {
        lastError = e;
        debugPrint(
            '[AiAnalysisService] candidate ${candidate.order} attempt $attempt failed: $e');
      }
    }
    throw lastError ?? AiAnalysisException('解析失败');
  }

  AnalysisResult _stampAnalysisAudit(AnalysisResult analysis, String modelName) =>
      analysis.copyWith(
        schemaVersion: AiAnalysisSchema.currentVersion,
        promptVersion: AiAnalysisSchema.currentPromptVersion,
        modelName: modelName,
        isLegacyContract: false,
      );

  AnalysisResult _enrichSpecializedAnalysis(
    AnalysisResult analysis,
    String questionText,
  ) {
    const enricher = SpecializedAnalysisEnricher();
    final specialized = enricher.enrich(
      questionText: questionText,
      solutionSteps: analysis.solutionSteps.isNotEmpty
          ? analysis.solutionSteps
          : analysis.steps,
      modelAnalysis: analysis.specializedAnalysis,
    );
    return specialized == null
        ? analysis
        : analysis.copyWith(specializedAnalysis: specialized);
  }

  Future<AnalysisResult> _applyResponseDiagnosticsRetentionPolicy(
    AnalysisResult analysis,
  ) async {
    final diagnostics = analysis.responseDiagnostics;
    if (diagnostics == null) return analysis;

    final rawEnabled =
        await settingsRepository.getString(diagnosticsRawResponseEnabledKey) ==
            'true';
    if (!rawEnabled) {
      return analysis.copyWith(
        responseDiagnostics: diagnostics.withoutRawResponse(),
      );
    }

    final rawResponse = analysis is ParsedAnalysisResult
        ? analysis.rawContent
        : diagnostics.rawResponse;
    if (rawResponse == null || rawResponse.isEmpty) {
      return analysis.copyWith(
        responseDiagnostics: diagnostics.withoutRawResponse(),
      );
    }
    final retentionRaw =
        await settingsRepository.getString(diagnosticsRawRetentionDaysKey);
    final retentionDays = int.tryParse(retentionRaw ?? '') ??
        defaultDiagnosticsRawRetentionDays;
    return analysis.copyWith(
      responseDiagnostics: AiResponseDiagnostics(
        contentLength: diagnostics.contentLength,
        contentFingerprint: diagnostics.contentFingerprint,
        markdownWrapped: diagnostics.markdownWrapped,
        repairStrategy: diagnostics.repairStrategy,
        capturedAt: diagnostics.capturedAt,
        rawResponse: rawResponse,
        retentionDays: retentionDays.clamp(1, 30).toInt(),
      ),
    );
  }

  Future<AnalysisResult> _finalizeAnalysisResult(
    Future<AnalysisResult> checked,
  ) async {
    return _applyResponseDiagnosticsRetentionPolicy(await checked);
  }

  @visibleForTesting
  Future<AnalysisResult> applyResponseDiagnosticsRetentionForTest(
    AnalysisResult analysis,
  ) {
    return _applyResponseDiagnosticsRetentionPolicy(analysis);
  }

  Future<AnalysisResult> analyzeExtractedQuestion({
    required String correctedText,
    required String subjectName,
    String? imagePath,
    String studentAnswer = '',
  }) async {
    debugPrint('[AiAnalysisService] analyzeExtractedQuestion called');

    final config = await _requireConfig();
    final isGraphicalQuestion = this.isGraphicalQuestion(
      correctedText,
      subjectName,
      imagePath: imagePath,
    );
    final shouldAnalyzeImageFirst = isGraphicalQuestion ||
        _shouldAnalyzeImageFirst(
          correctedText,
          subjectName,
          imagePath: imagePath,
        );
    final prompt = _buildAnalysisPrompt(
      correctedText,
      subjectName,
      isGraphicalQuestion: shouldAnalyzeImageFirst,
      studentAnswer: studentAnswer,
      modelName: config.model,
    );
    final systemPrompt = await _loadAnalysisSystemPrompt();

    // 分流：图片分支（含高清图重试、紧凑图回退）或纯文本分支；统一在外层做
    // 一致性校验与异常分类。
    try {
      final isCompositeLanguageAnalysis =
          _isCompositeLanguageAnalysis(correctedText, subjectName);
      if (imagePath != null && File(imagePath).existsSync()) {
        final imageBytes = await File(imagePath).readAsBytes();
        final analysis = await _analyzeWithImage(
          config: config,
          systemPrompt: systemPrompt,
          prompt: prompt,
          imageBytes: imageBytes,
          isCompositeLanguageAnalysis: isCompositeLanguageAnalysis,
          shouldAnalyzeImageFirst: shouldAnalyzeImageFirst,
        );
        return _finalizeAnalysisResult(_ensureAnalysisConsistency(
          _enrichSpecializedAnalysis(
            _stampAnalysisAudit(analysis, config.model),
            correctedText,
          ),
          questionText: correctedText,
          subjectName: subjectName,
          imagePath: imagePath,
          config: config,
          imageBytes: imageBytes,
        ));
      }
      final analysis = await _analyzeTextOnly(
        config: config,
        systemPrompt: systemPrompt,
        prompt: prompt,
        isCompositeLanguageAnalysis: isCompositeLanguageAnalysis,
      );
      return _finalizeAnalysisResult(_ensureAnalysisConsistency(
        _enrichSpecializedAnalysis(
          _stampAnalysisAudit(analysis, config.model),
          correctedText,
        ),
        questionText: correctedText,
        subjectName: subjectName,
        imagePath: null,
        config: config,
      ));
    } on DioException catch (e) {
      debugPrint(
          '[AiAnalysisService] DioException: type=${e.type}, message=${e.message}, status=${e.response?.statusCode}');
      throw AiAnalysisException(_dioErrorMessage(e));
    } catch (e) {
      if (e is AiAnalysisException) rethrow;
      debugPrint('[AiAnalysisService] Exception: $e');
      if (e is FormatException) {
        throw AiAnalysisException('AI 返回内容格式异常，请重试或换一张更清晰的图片');
      }
      throw AiAnalysisException('AI 解析失败: $e');
    }
  }

  /// Repairs only selected analysis fields and preserves all other trusted
  /// values. The caller can use this for field-level retry after user review.
  Future<AnalysisResult> retryAnalysisFields({
    required AnalysisResult current,
    required Set<AiAnalysisField> fields,
    required String confirmedQuestion,
    required String subjectName,
    String studentAnswer = '',
    String? imagePath,
  }) async {
    if (fields.isEmpty) return current;
    if (!current.hasContractV2 || current.confidence == null) {
      throw AiAnalysisException('历史分析缺少 Contract V2 置信度，请先完整重新分析');
    }
    final config = await _requireConfig();
    final prompt = _promptBuilder.buildFieldRepairPrompt(
      current: current,
      fields: fields,
      confirmedQuestion: confirmedQuestion,
      studentAnswer: studentAnswer,
      modelName: config.model,
    );
    const systemPrompt = '你是 AI 错题分析字段修复器。只返回请求字段的严格 JSON 补丁。';

    Future<String> fetch({required int maxTokens}) {
      if (imagePath != null && File(imagePath).existsSync()) {
        return File(imagePath).readAsBytes().then(
              (bytes) => _requestAiContentWithImage(
                config: config,
                systemPrompt: systemPrompt,
                prompt: prompt,
                imageBytes: bytes,
                maxTokens: maxTokens,
                imageDetail: 'high',
                temperature: 0.1,
              ),
            );
      }
      return _requestAiContent(
        config: config,
        systemPrompt: systemPrompt,
        prompt: prompt,
        maxTokens: maxTokens,
        temperature: 0.1,
      );
    }

    AnalysisResult parsePatch(String content) {
      try {
        final decoded = _decodeResponseJson(content);
        final patch = AiAnalysisPatchContract.parse(
          decoded.value,
          requestedFields: fields,
          studentAnswer: studentAnswer,
        );
        final diagnostics = AiResponseDiagnostics(
          contentLength: decoded.contentLength,
          contentFingerprint: decoded.contentFingerprint,
          markdownWrapped: decoded.markdownWrapped,
          repairStrategy: decoded.repairStrategy.name,
          capturedAt: DateTime.now(),
        );
        return _stampAnalysisAudit(
          patch.applyTo(current).copyWith(responseDiagnostics: diagnostics),
          config.model,
        );
      } on _AiJsonParseException {
        rethrow;
      } on FormatException catch (error) {
        throw _AiJsonParseException(error);
      }
    }

    final content = await fetch(maxTokens: 1400);
    final repaired = await _parseContentWithJsonRetry(
      firstContent: content,
      parse: parsePatch,
      retryContentFetcher: () => fetch(maxTokens: 1800),
      stage: 'analysis(field repair)',
    );
    return _applyResponseDiagnosticsRetentionPolicy(repaired);
  }

  /// 图片分支：先按高清图（high/auto）请求，失败时若条件满足回退到紧凑图重试。
  /// 仅返回解析后的 [AnalysisResult]，一致性校验交回主方法统一处理。
  Future<AnalysisResult> _analyzeWithImage({
    required AiProviderConfig config,
    required String systemPrompt,
    required String prompt,
    required Uint8List imageBytes,
    required bool isCompositeLanguageAnalysis,
    required bool shouldAnalyzeImageFirst,
  }) async {
    final String imagePrompt;
    if (isCompositeLanguageAnalysis) {
      imagePrompt =
          '$prompt\n\n请按一整道复合题分析，不要拆成多道独立题；英语按空号逐项解析，语文按文常、字词、翻译/释义模块解析。';
    } else {
      imagePrompt = prompt;
    }

    try {
      final firstMaxTokens = isCompositeLanguageAnalysis ||
              shouldAnalyzeImageFirst
          ? 3000
          : 2000;
      final firstImageDetail = isCompositeLanguageAnalysis ||
              shouldAnalyzeImageFirst
          ? 'high'
          : 'auto';
      final content = await _requestAiContentWithImage(
        config: config,
        systemPrompt: systemPrompt,
        prompt: imagePrompt,
        imageBytes: imageBytes,
        maxTokens: firstMaxTokens,
        imageDetail: firstImageDetail,
      );
      return await _parseContentWithJsonRetry(
        firstContent: content,
        parse: _parseAnalysisResponseV2,
        retryContentFetcher: () => _requestAiContentWithImage(
          config: config,
          systemPrompt: systemPrompt,
          prompt: imagePrompt,
          imageBytes: imageBytes,
          maxTokens: firstMaxTokens + 500,
          imageDetail: firstImageDetail,
          temperature: 0.3,
        ),
        stage: 'analysis(image)',
      );
    } on DioException catch (e) {
      if (!_shouldRetryWithCompactImage(e) ||
          !isCompositeLanguageAnalysis && !shouldAnalyzeImageFirst) {
        rethrow;
      }
      debugPrint(
          '[AiAnalysisService] High detail image analysis failed, retrying compact image request: ${e.type}, status=${e.response?.statusCode}');
      const compactMaxTokens = 2200;
      const compactImageDetail = 'auto';
      final content = await _requestAiContentWithImage(
        config: config,
        systemPrompt: systemPrompt,
        prompt: prompt,
        imageBytes: imageBytes,
        maxTokens: compactMaxTokens,
        imageDetail: compactImageDetail,
      );
      return await _parseContentWithJsonRetry(
        firstContent: content,
        parse: _parseAnalysisResponseV2,
        retryContentFetcher: () => _requestAiContentWithImage(
          config: config,
          systemPrompt: systemPrompt,
          prompt: prompt,
          imageBytes: imageBytes,
          maxTokens: compactMaxTokens + 500,
          imageDetail: compactImageDetail,
          temperature: 0.3,
        ),
        stage: 'analysis(compact image)',
      );
    }
  }

  /// 纯文本分支：无图片可用时走此路径。仅返回解析后的 [AnalysisResult]，
  /// 一致性校验交回主方法统一处理。
  Future<AnalysisResult> _analyzeTextOnly({
    required AiProviderConfig config,
    required String systemPrompt,
    required String prompt,
    required bool isCompositeLanguageAnalysis,
  }) async {
    final firstMaxTokens = isCompositeLanguageAnalysis ? 3000 : 2000;
    final content = await _requestAiContent(
      config: config,
      systemPrompt: systemPrompt,
      prompt: prompt,
      maxTokens: firstMaxTokens,
    );
    return _parseContentWithJsonRetry(
      firstContent: content,
      parse: _parseAnalysisResponseV2,
      retryContentFetcher: () => _requestAiContent(
        config: config,
        systemPrompt: systemPrompt,
        prompt: prompt,
        maxTokens: firstMaxTokens + 500,
        temperature: 0.3,
      ),
      stage: 'analysis(text)',
    );
  }

  Future<AnalysisResult> _ensureAnalysisConsistency(
    AnalysisResult analysis, {
    required String questionText,
    required String subjectName,
    required String? imagePath,
    required AiProviderConfig config,
    Uint8List? imageBytes,
  }) async {
    final check = _detectAnalysisConsistencyIssue(
      analysis,
      questionText: questionText,
    );

    if (check.forceManualReview) {
      return analysis.copyWith(
        consistencyStatus: AnalysisConsistencyStatus.needsReview,
        consistencyNote: check.note,
        wasVerifierUsed: false,
      );
    }

    if (!check.isSuspicious) {
      // Visual assumption uncertainty and answer consistency are independent
      // dimensions. When local check finds no conflict, we still set the
      // appropriate status — but visual uncertainty upgrades the status to
      // needsReview without triggering the verifier (no internal conflict to
      // repair).
      final visualNeedsReview =
          analysis.visualAssumptionStatus == VisualAssumptionStatus.needsReview;
      final AnalysisConsistencyStatus status;
      final String note;
      if (visualNeedsReview) {
        status = AnalysisConsistencyStatus.needsReview;
        note = _visualAssumptionReviewNote(analysis.visualAssumptions);
      } else if (check.isUnverifiable) {
        status = AnalysisConsistencyStatus.unverifiable;
        note = check.note;
      } else {
        status = AnalysisConsistencyStatus.consistent;
        note = check.note;
      }
      return analysis.copyWith(
        consistencyStatus: status,
        consistencyNote: note,
        wasVerifierUsed: false,
      );
    }

    try {
      final prompt = _buildConsistencyVerificationPrompt(
        questionText: questionText,
        subjectName: subjectName,
        analysis: analysis,
        issueSummary: check.note,
      );
      final content = imageBytes != null && imagePath != null
          ? await _requestAiContentWithImage(
              config: config,
              systemPrompt: _consistencyVerifierSystemPrompt,
              prompt: prompt,
              imageBytes: imageBytes,
              maxTokens: 1200,
              imageDetail: 'high',
              temperature: 0.1,
            )
          : await _requestAiContent(
              config: config,
              systemPrompt: _consistencyVerifierSystemPrompt,
              prompt: prompt,
              maxTokens: 1000,
              temperature: 0.1,
            );
      final verification = _parseConsistencyVerificationResponse(content);
      return _applyConsistencyVerification(analysis, verification);
    } catch (e) {
      debugPrint('[AiAnalysisService] consistency verifier failed: $e');
      return analysis.copyWith(
        consistencyStatus: AnalysisConsistencyStatus.needsReview,
        consistencyNote: '答案与步骤可能不一致，自动复核失败，请人工核对。',
        wasVerifierUsed: true,
      );
    }
  }

  _ConsistencyCheck _detectAnalysisConsistencyIssue(
    AnalysisResult analysis, {
    String? questionText,
  }) {
    final targetMismatch = _detectGraphicalTargetMismatch(
      analysis,
      questionText: questionText,
    );
    if (targetMismatch != null) return targetMismatch;

    final formulaIssue = _detectHighRiskFormulaChainIssue(
      analysis,
      questionText: questionText,
    );
    if (formulaIssue != null) return formulaIssue;

    // Generic: detect contradictory conclusion values within the last few steps.
    final stepContradiction = _detectStepInternalContradiction(analysis);
    if (stepContradiction != null) return stepContradiction;

    final finalTokens = _extractLikelyConclusionTokens(analysis.finalAnswer);
    final derivationTokens = _extractLikelyConclusionTokens(
      analysis.finalAnswerDerivation,
    );
    final stepConclusionTokens = <String>{
      for (final step in analysis.steps.reversed.take(2))
        ..._extractLikelyConclusionTokens(step),
    };

    if (finalTokens.isEmpty ||
        derivationTokens.isEmpty && stepConclusionTokens.isEmpty) {
      return const _ConsistencyCheck(
        isSuspicious: false,
        isUnverifiable: true,
        note: '未提取到足够明确的答案结论，未自动复核。',
      );
    }

    if (stepConclusionTokens.isNotEmpty &&
        finalTokens.intersection(stepConclusionTokens).isEmpty) {
      return _ConsistencyCheck(
        isSuspicious: true,
        isUnverifiable: false,
        note:
            'finalAnswer 提取为 ${finalTokens.join(', ')}，步骤最终结论提取为 ${stepConclusionTokens.join(', ')}。',
      );
    }

    if (derivationTokens.isNotEmpty &&
        finalTokens.intersection(derivationTokens).isEmpty) {
      return _ConsistencyCheck(
        isSuspicious: true,
        isUnverifiable: false,
        note:
            'finalAnswer 提取为 ${finalTokens.join(', ')}，答案来源提取为 ${derivationTokens.join(', ')}。',
      );
    }

    if (derivationTokens.isNotEmpty &&
        stepConclusionTokens.isNotEmpty &&
        derivationTokens.intersection(stepConclusionTokens).isEmpty) {
      return _ConsistencyCheck(
        isSuspicious: true,
        isUnverifiable: false,
        note:
            '答案来源提取为 ${derivationTokens.join(', ')}，步骤最终结论提取为 ${stepConclusionTokens.join(', ')}。',
      );
    }

    return const _ConsistencyCheck(
      isSuspicious: false,
      isUnverifiable: false,
      note: '答案与步骤结论一致。',
    );
  }

  _ConsistencyCheck? _detectGraphicalTargetMismatch(
    AnalysisResult analysis, {
    String? questionText,
  }) {
    final source = questionText?.toLowerCase() ?? '';
    if (source.isEmpty) return null;

    final asksCompositeRegion = _hasCompositeAreaTargetSignal(source);
    if (!asksCompositeRegion) return null;

    final targetText = <String>[
      analysis.reconstructedQuestionText,
      analysis.visualAssumptions?.targetObject ?? '',
      analysis.visualAssumptions?.targetQuestion ?? '',
    ].join(' ').toLowerCase();
    if (targetText.isEmpty) return null;

    final targetsOnlySemicircle = _hasAnySignal(targetText, <String>[
          '求半圆面积',
          '求该半圆的面积',
          '求这个半圆的面积',
          '求阴影半圆面积',
          '半圆面积',
        ]) &&
        !_hasCompositeAreaTargetSignal(targetText);

    if (!targetsOnlySemicircle) return null;

    return const _ConsistencyCheck(
      isSuspicious: true,
      isUnverifiable: false,
      forceManualReview: true,
      note: '参考题干指向括号状/剩余区域面积，但 AI 重构目标变成只求半圆面积，需复核读图目标。',
    );
  }

  bool _hasCompositeAreaTargetSignal(String text) {
    return _hasAnySignal(text, <String>[
      '括号',
      '括号状',
      '剩余区域',
      '剩余面积',
      '剩余部分',
      '半圆外',
      '外框内',
      '外边界与半圆',
      '目标区域',
      '所示区域',
      '阴影区域',
      '阴影部分',
      '空白部分',
    ]);
  }

  _ConsistencyCheck? _detectHighRiskFormulaChainIssue(
    AnalysisResult analysis, {
    String? questionText,
  }) {
    final combined = <String>[
      questionText ?? '',
      analysis.finalAnswer,
      analysis.finalAnswerDerivation,
      ...analysis.steps,
      analysis.mistakeReason,
      ...analysis.aiTags,
      ...analysis.knowledgePoints,
    ].join(' ').toLowerCase();
    if (!_hasPlaneGeometryAreaSignal(combined) ||
        !_hasCircleAreaSignal(combined) ||
        !_hasAnySignal(combined, <String>[
          '半圆',
          '一半',
          r'\frac{1}{2}',
          '1/2',
          '阴影',
        ])) {
      return null;
    }

    final canonical = _canonicalMathText(combined);
    final has25PiHalf = _hasAnySignal(canonical, <String>[
      '25\\pi/2',
      '\\frac{25\\pi}{2}',
      '\\frac{25pi}{2}',
    ]);
    final has29PiHalf = _hasAnySignal(canonical, <String>[
      '29\\pi/2',
      '\\frac{29\\pi}{2}',
      '\\frac{29pi}{2}',
    ]);
    final finalTokens = _extractLikelyConclusionTokens(analysis.finalAnswer);
    if (has25PiHalf &&
        has29PiHalf &&
        (finalTokens.contains(r'25\pi') ||
            finalTokens.contains(r'25\pi/2') ||
            finalTokens.contains(r'29\pi/2'))) {
      return const _ConsistencyCheck(
        isSuspicious: true,
        isUnverifiable: false,
        note: '图形面积解析中同时出现 25π/2、29π/2 或 25π 等不同结论，需复核最终答案。',
      );
    }

    if (_hasAnySignal(canonical, <String>[
      '25\\pi/2*2=25\\pi',
      '25\\pi/2×2=25\\pi',
      '25\\pi/2乘2=25\\pi',
      '1/2\\pi*5^2=25\\pi',
      '1/2\\pi×5^2=25\\pi',
      '1/2*\\pi*5^2=25\\pi',
      '1/2×\\pi×5^2=25\\pi',
    ])) {
      return const _ConsistencyCheck(
        isSuspicious: true,
        isUnverifiable: false,
        note: '半圆面积公式链出现从 25π/2 跳到 25π 的矛盾，需复核最终答案。',
      );
    }

    final hasHalfCircleFormula = _hasAnySignal(canonical, <String>[
      '1/2\\pi r^2',
      '1/2\\pir^2',
      '1/2*\\pi*r^2',
      '1/2×\\pi×r^2',
      '1/2\\pi×r^2',
      '1/2\\pi*5^2',
      '1/2\\pi×5^2',
      '\\frac{1}{2}\\pi r^2',
      '\\frac{1}{2}\\pir^2',
      '\\frac{1}{2}\\pi×5^2',
      '\\frac{1}{2}\\pi*5^2',
    ]);
    final derivesHalfOf25Pi = _hasAnySignal(canonical, <String>[
      '25\\pi/2',
      '\\frac{25\\pi}{2}',
      '\\frac{25pi}{2}',
    ]);
    if (hasHalfCircleFormula &&
        derivesHalfOf25Pi &&
        finalTokens.contains(r'25\pi') &&
        !finalTokens.any((token) => token.contains('/2'))) {
      return const _ConsistencyCheck(
        isSuspicious: true,
        isUnverifiable: false,
        note: '半圆面积推导中已得到 25π/2，但 finalAnswer 是 25π，需复核最终答案。',
      );
    }

    return null;
  }

  /// Generic detection: checks if any single step contains mutually exclusive
  /// final-answer-like conclusions. Unlike [_detectHighRiskFormulaChainIssue]
  /// this is not hardcoded to specific values.
  ///
  /// Only flags cases where a step has **separate conclusion statements**
  /// (e.g. "所以面积为 10π" and later "最终答案是 29π/2") pointing to
  /// different values. Continuous formula chains like "= 25π/2 × 2 = 25π"
  /// are NOT flagged — they are valid computation chains even if the math
  /// is wrong (math correctness is the verifier's job).
  _ConsistencyCheck? _detectStepInternalContradiction(
    AnalysisResult analysis,
  ) {
    if (analysis.steps.isEmpty) return null;

    // Look for conclusion keywords that introduce final-answer-like values.
    final conclusionPattern = RegExp(
      r'(?:答案|所以|因此|故|得|最终|最后)[^=]*?(?:为|是|=)\s*([^\s,，。；]+)',
    );

    for (final step in analysis.steps.reversed.take(3)) {
      final matches = conclusionPattern.allMatches(step).toList();
      if (matches.length < 2) continue;

      // Extract numeric tokens from each conclusion fragment.
      final conclusionTokens = <Set<String>>[];
      for (final match in matches) {
        final fragment = match.group(1) ?? '';
        final tokens = _extractAnswerTokens(fragment)
            .where((t) => RegExp(r'\d|\\pi|pi').hasMatch(t))
            .toSet();
        if (tokens.isNotEmpty) conclusionTokens.add(tokens);
      }

      // If two conclusion statements in the same step point to
      // different numeric values, that's a genuine contradiction.
      if (conclusionTokens.length >= 2) {
        final last = conclusionTokens.last;
        for (var i = 0; i < conclusionTokens.length - 1; i++) {
          final earlier = conclusionTokens[i];
          if (earlier.intersection(last).isEmpty) {
            return _ConsistencyCheck(
              isSuspicious: true,
              isUnverifiable: false,
              note:
                  '步骤内部结论矛盾：同一步中先结论 ${earlier.join(', ')}，后结论 ${last.join(', ')}，需复核。',
            );
          }
        }
      }
    }

    return null;
  }

  String _canonicalMathText(String text) {
    return text
        .replaceAll(' ', '')
        .replaceAll('，', ',')
        .replaceAll('。', '')
        .replaceAll('＝', '=')
        .replaceAll('π', r'\pi')
        .replaceAll('−', '-')
        .replaceAll('·', '*')
        .replaceAll('×', '×')
        .replaceAll(r'\times', '×')
        .replaceAll(r'\cdot', '*')
        .replaceAll(r'\left', '')
        .replaceAll(r'\right', '')
        .replaceAll('{', '')
        .replaceAll('}', '')
        .toLowerCase();
  }

  Set<String> _extractLikelyConclusionTokens(String text) {
    final normalized = text
        .replaceAll(' ', '')
        .replaceAll('，', ',')
        .replaceAll('。', '')
        .replaceAll('＝', '=')
        .replaceAll('π', r'\pi')
        .replaceAll('÷', '/')
        .replaceAll('−', '-')
        .toLowerCase();
    final keywordMatch = RegExp(r'(?:答案|选|应选|所以|因此|故|得|为|是)[:：]?([^。；;，,]*)')
        .allMatches(normalized)
        .lastOrNull;
    if (keywordMatch != null) {
      final tokens = _extractAnswerTokens(keywordMatch.group(1)!);
      if (tokens.isNotEmpty) return tokens;
    }

    final equalsIndex = normalized.lastIndexOf('=');
    if (equalsIndex >= 0 && equalsIndex < normalized.length - 1) {
      final tokens =
          _extractAnswerTokens(normalized.substring(equalsIndex + 1));
      if (tokens.isNotEmpty) return tokens;
    }

    return _extractAnswerTokens(normalized);
  }

  Set<String> _extractAnswerTokens(String text) {
    final normalized = text
        .replaceAll(' ', '')
        .replaceAll('，', ',')
        .replaceAll('。', '')
        .replaceAll('＝', '=')
        .replaceAll('π', r'\pi')
        .replaceAll('÷', '/')
        .replaceAll('−', '-')
        .toLowerCase();
    final tokens = <String>{};

    for (final match
        in RegExp(r'(?<![a-z])[a-d](?![a-z])').allMatches(normalized)) {
      tokens.add(match.group(0)!.toUpperCase());
    }
    for (final match in RegExp(
            r'(?:\\frac\{[^{}]+\}\{[^{}]+\}|\d+(?:\.\d+)?(?:\\pi|pi)?(?:/\d+(?:\.\d+)?)?|(?:\\pi|pi)(?:/\d+(?:\.\d+)?)?)')
        .allMatches(normalized)) {
      final token = match.group(0)!;
      if (RegExp(r'\d|\\pi|pi').hasMatch(token)) tokens.add(token);
    }
    for (final match
        in RegExp(r'\\frac\{([^{}]+)\}\{([^{}]+)\}').allMatches(normalized)) {
      tokens.add('${match.group(1)}/${match.group(2)}');
    }
    return tokens
        .where((token) => token.length > 1 || RegExp(r'[A-D]').hasMatch(token))
        .toSet();
  }

  @visibleForTesting
  AnalysisResult parseAnalysisResponseForTest(String content) {
    return _parseAnalysisResponse(content);
  }

  @visibleForTesting
  AnalysisResult applyConsistencyVerificationForTest(
    AnalysisResult analysis,
    String verificationContent,
  ) {
    return _applyConsistencyVerification(
      analysis,
      _parseConsistencyVerificationResponse(verificationContent),
    );
  }

  /// Returns `true` if [_detectAnalysisConsistencyIssue] would mark the
  /// analysis as suspicious (i.e. would trigger the verifier in production).
  @visibleForTesting
  bool detectConsistencyIssueForTest(
    AnalysisResult analysis, {
    String? questionText,
  }) {
    return _detectAnalysisConsistencyIssue(
      analysis,
      questionText: questionText,
    ).isSuspicious;
  }

  @visibleForTesting
  bool consistencyIssueForcesManualReviewForTest(
    AnalysisResult analysis, {
    String? questionText,
  }) {
    return _detectAnalysisConsistencyIssue(
      analysis,
      questionText: questionText,
    ).forceManualReview;
  }

  String _buildConsistencyVerificationPrompt({
    required String questionText,
    required String subjectName,
    required AnalysisResult analysis,
    required String issueSummary,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('请复核以下错题解析的最终答案一致性。');
    buffer.writeln('科目：$subjectName');
    buffer.writeln('题目：$questionText');
    buffer.writeln('冲突摘要：$issueSummary');
    buffer.writeln();
    buffer.writeln('原 finalAnswer：${analysis.finalAnswer}');
    buffer.writeln('原 finalAnswerDerivation：${analysis.finalAnswerDerivation}');
    buffer.writeln('原 steps：');
    for (var i = 0; i < analysis.steps.length; i++) {
      buffer.writeln('${i + 1}. ${analysis.steps[i]}');
    }
    buffer.writeln('原 mistakeReason：${analysis.mistakeReason}');
    buffer.writeln();
    buffer.writeln('只判断 finalAnswer 是否与最终推导/步骤一致；不要重新生成举一反三。');
    buffer.writeln(
        '如果 steps 内部公式链本身错误，必须返回 correctedSteps，且 correctedSteps 不能保留原错误公式链。');
    buffer.writeln('如果不一致，只返回应该采用的最终答案、最终答案来源说明、必要的修正步骤和错因。');
    return buffer.toString();
  }

  static const _consistencyVerifierSystemPrompt =
      '''你是错题解析一致性复核器，只检查 finalAnswer 是否与 finalAnswerDerivation 和 steps 的最终结论一致。
不要把 mistakeReason 中复述的旧答案当作最终结论。
不要扩写举一反三。
只有在非常明确时才修正；如果不确定，设置 needsManualReview=true。
如果 steps 内部有错误公式链或错误结论，必须返回 correctedSteps，不能只修正 finalAnswer。
如果不能可靠修正 steps，设置 needsManualReview=true。
返回纯 JSON，不要 markdown：
{
  "isConsistent": false,
  "correctFinalAnswer": "",
  "correctedFinalAnswerDerivation": "",
  "correctedSteps": [],
  "correctedMistakeReason": "",
  "confidence": "high|medium|low",
  "needsManualReview": false,
  "reason": ""
}''';

  _ConsistencyVerification _parseConsistencyVerificationResponse(
      String content) {
    final map = _parseResponseJson(content);
    return _ConsistencyVerification(
      isConsistent: map['isConsistent'] as bool? ?? false,
      correctFinalAnswer: (map['correctFinalAnswer'] as String?)?.trim() ?? '',
      correctedFinalAnswerDerivation:
          (map['correctedFinalAnswerDerivation'] as String?)?.trim() ?? '',
      correctedSteps: List<String>.from(
        (map['correctedSteps'] as List? ?? <String>[])
            .map((item) => item.toString().trim())
            .where((item) => item.isNotEmpty),
      ),
      correctedMistakeReason:
          (map['correctedMistakeReason'] as String?)?.trim() ?? '',
      confidence: (map['confidence'] as String?)?.trim().toLowerCase() ?? 'low',
      needsManualReview: map['needsManualReview'] as bool? ?? true,
      reason: (map['reason'] as String?)?.trim() ?? '',
    );
  }

  AnalysisResult _applyConsistencyVerification(
    AnalysisResult analysis,
    _ConsistencyVerification verification,
  ) {
    if (verification.isConsistent) {
      final visualNeedsReview =
          analysis.visualAssumptionStatus == VisualAssumptionStatus.needsReview;
      return analysis.copyWith(
        consistencyStatus: visualNeedsReview
            ? AnalysisConsistencyStatus.needsReview
            : AnalysisConsistencyStatus.consistent,
        consistencyNote: visualNeedsReview
            ? _visualAssumptionReviewNote(analysis.visualAssumptions)
            : (verification.reason.isNotEmpty
                ? verification.reason
                : 'AI 已复核答案与步骤一致。'),
        wasVerifierUsed: true,
      );
    }

    final canRepair = !verification.needsManualReview &&
        (verification.confidence == 'high' ||
            verification.confidence == 'medium') &&
        verification.correctFinalAnswer.isNotEmpty;
    if (!canRepair) {
      return analysis.copyWith(
        consistencyStatus: AnalysisConsistencyStatus.needsReview,
        consistencyNote: verification.reason.isNotEmpty
            ? verification.reason
            : '答案与步骤可能不一致，请人工核对。',
        wasVerifierUsed: true,
      );
    }

    final repairedSteps = verification.correctedSteps.isNotEmpty
        ? verification.correctedSteps
            .map(_normalizeExtractedQuestionText)
            .where((step) => step.isNotEmpty)
            .toList()
        : analysis.steps;
    final repairedMistakeReason = verification.correctedMistakeReason.isNotEmpty
        ? _normalizeExtractedQuestionText(verification.correctedMistakeReason)
        : analysis.mistakeReason;
    final repaired = analysis.copyWith(
      finalAnswer:
          _normalizeExtractedQuestionText(verification.correctFinalAnswer),
      finalAnswerDerivation: _normalizeExtractedQuestionText(
        verification.correctedFinalAnswerDerivation.isNotEmpty
            ? verification.correctedFinalAnswerDerivation
            : analysis.finalAnswerDerivation,
      ),
      reconstructedQuestionText: analysis.reconstructedQuestionText,
      steps: repairedSteps,
      mistakeReason: repairedMistakeReason,
      consistencyStatus: AnalysisConsistencyStatus.repaired,
      consistencyNote:
          verification.reason.isNotEmpty ? verification.reason : 'AI 已复核并修正答案。',
      wasVerifierUsed: true,
    );
    final check = _detectAnalysisConsistencyIssue(repaired);
    if (check.isSuspicious) {
      return analysis.copyWith(
        consistencyStatus: AnalysisConsistencyStatus.needsReview,
        consistencyNote: 'AI 复核后仍无法确认最终答案，请人工核对。',
        wasVerifierUsed: true,
      );
    }
    if (repaired.visualAssumptionStatus == VisualAssumptionStatus.needsReview) {
      return repaired.copyWith(
        consistencyStatus: AnalysisConsistencyStatus.needsReview,
        consistencyNote:
            'AI 已复核并修正答案；${_visualAssumptionReviewNote(repaired.visualAssumptions)}',
        wasVerifierUsed: true,
      );
    }
    return repaired;
  }

  Future<AiProviderConfig> _requireConfig() async {
    final config = await settingsRepository.getAiProviderConfig();

    debugPrint(
        '[AiAnalysisService] config: ${config != null ? "loaded" : "null"}');
    if (config != null) {
      debugPrint('[AiAnalysisService] provider configured: model=${config.model}');
    }

    if (config == null ||
        config.baseUrl.isEmpty ||
        config.apiKey.isEmpty ||
        config.model.isEmpty) {
      debugPrint('[AiAnalysisService] No config - throwing error');
      throw AiAnalysisException('AI 未配置，请在设置中配置 API 地址、API Key 和模型');
    }

    return config;
  }

  bool _shouldRetryWithCompactImage(DioException e) {
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout ||
        e.type == DioExceptionType.connectionError) {
      return true;
    }
    final status = e.response?.statusCode;
    return status == 408 ||
        status == 429 ||
        status == 500 ||
        status == 502 ||
        status == 503 ||
        status == 504;
  }

  String _dioErrorMessage(DioException e) {
    final buffer = StringBuffer('AI 服务请求失败');
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.sendTimeout) {
      buffer.write(': 请求超时，请检查网络后重试');
    } else if (e.type == DioExceptionType.connectionError) {
      buffer.write(': 网络连接失败，请检查网络');
    } else if (e.response != null) {
      final status = e.response!.statusCode;
      final body = e.response!.data;
      if (status != null) {
        buffer.write(' (HTTP $status)');
        if (body != null && body is Map && body['error'] != null) {
          final errMsg = body['error'];
          final compatibilityMessage =
              _providerCompatibilityMessage(errMsg?.toString());
          if (compatibilityMessage != null) {
            buffer.write(': $compatibilityMessage');
            return buffer.toString();
          }
          if (errMsg is Map) {
            buffer.write(': ${errMsg['message'] ?? errMsg}');
          } else {
            buffer.write(': $errMsg');
          }
        } else if (body is String && body.isNotEmpty) {
          final compatibilityMessage = _providerCompatibilityMessage(body);
          if (compatibilityMessage != null) {
            buffer.write(': $compatibilityMessage');
            return buffer.toString();
          }
          buffer.write(
              ': ${body.length > 100 ? '${body.substring(0, 100)}...' : body}');
        }
      } else if (e.message != null) {
        final compatibilityMessage = _providerCompatibilityMessage(e.message);
        if (compatibilityMessage != null) {
          buffer.write(': $compatibilityMessage');
          return buffer.toString();
        }
        buffer.write(': ${e.message}');
      }
    } else if (e.message != null) {
      final compatibilityMessage = _providerCompatibilityMessage(e.message);
      if (compatibilityMessage != null) {
        buffer.write(': $compatibilityMessage');
        return buffer.toString();
      }
      buffer.write(': ${e.message}');
    }
    return buffer.toString();
  }

  /// 把后端协议级别的兼容错误翻译成用户可行动的提示。
  ///
  /// 例如模型不支持 `image_url` 多模态输入时，直接展示原始报错只会让
  /// 用户困惑；这里统一转成"换视觉模型或改用文字解析"的指引。
  String? _providerCompatibilityMessage(String? raw) {
    final normalized = raw?.toLowerCase() ?? '';
    if (normalized.contains('unknown variant `image_url`') ||
        normalized.contains("unknown variant 'image_url'") ||
        normalized.contains('expected `text`') ||
        normalized.contains('expected text')) {
      return '当前模型不支持图片输入，请切换到支持视觉识别的模型，或改用文字解析。';
    }
    return null;
  }

  QuestionSplitResult _defaultSplitQuestionCandidates(String text,
      {Subject? subject}) {
    final normalized = _normalizeExtractedQuestionText(
      text.replaceAll('\r\n', '\n').trim(),
    );
    if (normalized.isEmpty) {
      return const QuestionSplitResult(
        sourceText: '',
        candidates: <QuestionSplitCandidate>[],
        strategy: QuestionSplitStrategy.fallback,
      );
    }

    if (isCompositeLanguageWorksheet(normalized, subject: subject)) {
      return QuestionSplitResult(
        sourceText: normalized,
        candidates: _buildSplitCandidates(
            <String>[normalized], QuestionSplitStrategy.fallback),
        strategy: QuestionSplitStrategy.fallback,
      );
    }

    if (_isCompositeQuestionWithSubparts(normalized, subject: subject)) {
      return QuestionSplitResult(
        sourceText: normalized,
        candidates: _buildSplitCandidates(
            <String>[normalized], QuestionSplitStrategy.fallback),
        strategy: QuestionSplitStrategy.fallback,
      );
    }

    final numberedSegments = _splitByNumberedQuestions(normalized);
    if (numberedSegments.length >= 2) {
      return QuestionSplitResult(
        sourceText: normalized,
        candidates: _buildSplitCandidates(
            numberedSegments, QuestionSplitStrategy.numbered),
        strategy: QuestionSplitStrategy.numbered,
      );
    }

    final paragraphSegments = normalized
        .split(RegExp(r'\n\s*\n+'))
        .map((segment) => segment.trim())
        .where((segment) => segment.isNotEmpty)
        .toList();
    if (paragraphSegments.length >= 2) {
      return QuestionSplitResult(
        sourceText: normalized,
        candidates: _buildSplitCandidates(
            paragraphSegments, QuestionSplitStrategy.paragraph),
        strategy: QuestionSplitStrategy.paragraph,
      );
    }

    return QuestionSplitResult(
      sourceText: normalized,
      candidates: _buildSplitCandidates(
          <String>[normalized], QuestionSplitStrategy.fallback),
      strategy: QuestionSplitStrategy.fallback,
    );
  }

  String _normalizeExtractedQuestionText(String text) {
    final normalized = LatexNormalizer.normalizeLiteralNewlines(text)
        .replaceAllMapped(
          RegExp(r'begin\{(cases|aligned)\}([\s\S]*?)end\{(?:cases|aligned)\}'),
          (match) {
            final body = match.group(2)!.trim().replaceAllMapped(
                  RegExp(r'(?<=[0-9A-Za-z一-龥])\s+(?=[A-Za-z])'),
                  (_) => r' \\ ',
                );
            return '\\begin{${match.group(1)}} $body \\end{${match.group(1)}}';
          },
        )
        .replaceAllMapped(RegExp(r'\\+tri\\+angle\s*'), (_) => r'\triangle ')
        .replaceAllMapped(RegExp(r'\\?tri\\?angle\s*|\\?tri∠|tri(?=\\angle)'),
            (_) => r'\triangle ')
        .replaceAllMapped(RegExp(r'(?<!\\)angle\b'), (_) => r'\angle')
        .replaceAllMapped(RegExp(r'(?<!\\)circ\b'), (_) => r'\circ')
        .replaceAllMapped(RegExp(r'(?<!\\)pm(?=[A-Za-z0-9])'), (_) => r'\pm ')
        .replaceAllMapped(RegExp(r'(?<!\\)pm\b'), (_) => r'\pm');

    return normalized
        .replaceAll(RegExp(r'\\+tri\\+angle\s*'), r'\triangle ')
        .replaceAll(RegExp(r'tri\\+angle\s*'), r'\triangle ')
        .replaceAll(RegExp(r'(?<![A-Za-z\\])tri∠'), r'\triangle ')
        .replaceAll(RegExp(r'(?<![A-Za-z\\])tri(?=\\angle|/)'), r'\triangle ')
        .replaceAll(
          RegExp(r'(?<![A-Za-z\\])text(?=kg|m|cm|g|s|N|Pa|J|W|V|A|Ω)'),
          r'\mathrm',
        )
        .replaceAllMapped(
          RegExp(r'\\?mathrm([A-Za-zΩ]+)(\^-?\d+)?'),
          (match) => '\\mathrm{${match.group(1)}}${match.group(2) ?? ''}',
        )
        .trim();
  }

  bool _isCompositeLanguageAnalysis(String text, String subjectName) {
    final subject = _parseSubject(subjectName);
    if ((subject == Subject.english || subject == Subject.chinese) &&
        text.trim().isEmpty) {
      return true;
    }
    return isCompositeLanguageWorksheet(text, subject: subject);
  }

  bool _isCompositeQuestionWithSubparts(String text, {Subject? subject}) {
    if (subject == Subject.chinese ||
        subject == Subject.english ||
        subject == Subject.history ||
        subject == Subject.geography ||
        subject == Subject.politics) {
      return false;
    }
    final hasSubQuestions =
        RegExp(r'（\s*\d+\s*）|\(\s*\d+\s*\)').allMatches(text).length >= 2;
    if (!hasSubQuestions) return false;

    final independentQuestionCount =
        RegExp(r'(^|\n)\s*(?:第\s*\d+\s*题|\d+[\.、．)])\s*', multiLine: true)
            .allMatches(text)
            .length;
    if (independentQuestionCount >= 2) return false;

    return _hasSharedCompositeStemSignal(text, subject: subject);
  }

  bool _hasSharedCompositeStemSignal(String text, {Subject? subject}) {
    final lower = text.toLowerCase();
    final hasGenericStem = _hasAnySignal(text, <String>[
      '如图',
      '根据下列',
      '结合材料',
      '已知',
      '条件',
      '回答下列问题',
      '完成下列问题',
    ]);
    final hasMathPhysicsStem = _hasAnySignal(text, <String>[
      '电路',
      '装置',
      '实验',
      '函数图像',
      '坐标系',
      '正方形',
      '矩形',
      '三角形',
      '圆',
    ]);
    final hasChemistryStem = _hasAnySignal(text, <String>[
      '合成路线',
      '流程',
      '路线',
      '转化关系',
      '可通过如下',
      '如图',
      '条件',
      '已知',
      '写出',
      '结构简式',
      '分子式',
      '化学方程式',
      '反应类型',
    ]);
    final hasChemistryContext = _hasAnySignal(lower, <String>[
      'naoh',
      'nh2oh',
      'hcl',
      'br',
      'fecl3',
      'c6h',
      '苯',
      '酯',
      '醇',
      '醛',
      '羧酸',
      '有机',
      '官能团',
      '同分异构体',
    ]);
    if (subject == Subject.chemistry) {
      return hasGenericStem || hasChemistryStem || hasChemistryContext;
    }
    if (subject == Subject.math || subject == Subject.physics) {
      return hasGenericStem || hasMathPhysicsStem;
    }
    return hasGenericStem || hasMathPhysicsStem || hasChemistryStem;
  }

  List<QuestionSplitCandidate> _buildSplitCandidates(
      List<String> segments, QuestionSplitStrategy strategy) {
    return segments.asMap().entries.map((entry) {
      return QuestionSplitCandidate(
        id: 'candidate-${entry.key}',
        order: entry.key + 1,
        text: entry.value,
        strategy: strategy,
      );
    }).toList();
  }

  List<String> _splitByNumberedQuestions(String text) {
    final matches =
        RegExp(r'(^|\n)\s*(?:第\s*\d+\s*题|\d+[\.、．)])\s*', multiLine: true)
            .allMatches(text)
            .toList();
    if (matches.length < 2) return const <String>[];

    final segments = <String>[];
    for (var index = 0; index < matches.length; index++) {
      final current = matches[index];
      final start = current.start + (current.group(1)?.length ?? 0);
      final end =
          index + 1 < matches.length ? matches[index + 1].start : text.length;
      final segment = text.substring(start, end).trim();
      if (segment.isNotEmpty) {
        segments.add(segment);
      }
    }
    return segments;
  }

  Future<Response<T>> _postChatWithStructuredFallback<T>(
    Dio dio,
    Map<String, dynamic> data,
  ) async {
    try {
      return await _retryPost<T>(dio, '/chat/completions', data: data);
    } on DioException catch (error) {
      final status = error.response?.statusCode;
      final canFallback = data.containsKey('response_format') &&
          (status == 400 || status == 404 || status == 422);
      if (!canFallback) rethrow;
      final fallback = Map<String, dynamic>.from(data)..remove('response_format');
      debugPrint(
        '[AiAnalysisService] Provider rejected structured output; '
        'retrying with prompt-only JSON. status=$status',
      );
      return _retryPost<T>(dio, '/chat/completions', data: fallback);
    }
  }

  Map<String, dynamic> _chatRequestData({
    required AiProviderConfig config,
    required List<Map<String, dynamic>> messages,
    required int maxTokens,
    required double temperature,
  }) {
    return _requestBuilder.buildChatPayload(
      config: config,
      messages: messages,
      maxTokens: maxTokens,
      temperature: temperature,
    );
  }

  Future<String> _requestAiContent({
    required AiProviderConfig config,
    required String systemPrompt,
    required String prompt,
    int maxTokens = 2000,
    double temperature = 0.7,
  }) async {
    final dio = _createClient(config);
    final response = await _postChatWithStructuredFallback(
      dio,
      _chatRequestData(
        config: config,
        messages: <Map<String, dynamic>>[
          <String, dynamic>{'role': 'system', 'content': systemPrompt},
          <String, dynamic>{'role': 'user', 'content': prompt},
        ],
        temperature: temperature,
        maxTokens: maxTokens,
      ),
    );

    return _extractContentFromResponse(response);
  }

  bool _usesOpenAiCompatibleChat(AiProviderConfig config) {
    final baseUrl = config.baseUrl.toLowerCase();
    final model = config.model.toLowerCase();
    return baseUrl.contains('/v1') ||
        baseUrl.contains('openrouter') ||
        model.contains('gpt') ||
        model.contains('4o') ||
        model.contains('4-turbo');
  }

  Future<String> _requestAiContentWithImage({
    required AiProviderConfig config,
    required String systemPrompt,
    required String prompt,
    required Uint8List imageBytes,
    int maxTokens = 2000,
    String imageDetail = 'auto',
    double temperature = 0.7,
  }) async {
    final dio = _createClient(config);
    final base64Image = base64Encode(imageBytes);
    const mimeType = 'image/jpeg';
    final baseUrl = config.baseUrl.toLowerCase();
    final model = config.model.toLowerCase();

    if (_usesOpenAiCompatibleChat(config)) {
      final response = await _postChatWithStructuredFallback(
        dio,
        _chatRequestData(
          config: config,
          messages: <Map<String, dynamic>>[
            {'role': 'system', 'content': systemPrompt},
            {
              'role': 'user',
              'content': [
                {
                  'type': 'image_url',
                  'image_url': {
                    'url': 'data:$mimeType;base64,$base64Image',
                    'detail': imageDetail
                  },
                },
                {'type': 'text', 'text': prompt},
              ],
            },
          ],
          temperature: temperature,
          maxTokens: maxTokens,
        ),
      );
      return _extractContentFromResponse(response);
    }

    if (model.contains('gemini') && !baseUrl.contains('openrouter')) {
      final response = await dio.post(
        '/v1beta/models/${config.model}:generateContent',
        data: <String, dynamic>{
          'contents': [
            {
              'parts': [
                {'text': '$systemPrompt\n\n$prompt'},
                {
                  'inlineData': {'mimeType': mimeType, 'data': base64Image}
                },
              ],
            },
          ],
          'generationConfig': {
            'temperature': temperature,
            'maxOutputTokens': maxTokens,
            'responseMimeType': 'application/json',
          },
        },
      );
      return response.data['candidates'][0]['content']['parts'][0]['text']
          as String;
    }

    final response = await _postChatWithStructuredFallback(
      dio,
      _chatRequestData(
        config: config,
        messages: <Map<String, dynamic>>[
          {'role': 'system', 'content': systemPrompt},
          {
            'role': 'user',
            'content': [
              {
                'type': 'image_url',
                'image_url': {
                  'url': 'data:$mimeType;base64,$base64Image',
                  'detail': imageDetail
                },
              },
              {'type': 'text', 'text': prompt},
            ],
          },
        ],
        temperature: temperature,
        maxTokens: maxTokens,
      ),
    );
    return _extractContentFromResponse(response);
  }

  /// 在 [_parseResponseJson] 失败时重试一次 AI 请求。
  /// 第一次解析失败 -> 调用 [retryContentFetcher] 重新请求 AI（调用方应将
  /// max_tokens +500，temperature 降为 0.3）-> 再次解析；仍失败抛
  /// [AiAnalysisException]。
  Future<T> _parseContentWithJsonRetry<T>({
    required String firstContent,
    required T Function(String) parse,
    required Future<String> Function() retryContentFetcher,
    required String stage,
  }) async {
    try {
      return parse(firstContent);
    } on _AiJsonParseException catch (e1) {
      debugPrint(
          '[AiAnalysisService] $stage JSON 解析失败(${e1.inner})，重试 AI 请求 (max_tokens+500, temperature=0.3)...');
      try {
        final retryContent = await retryContentFetcher();
        return parse(retryContent);
      } on _AiJsonParseException catch (e2) {
        throw AiAnalysisException('解析 AI 响应失败: ${e2.inner}');
      }
    }
  }

  static const _defaultAnalysisSystemPrompt = r'''你是一个专业的错题分析助手，专门帮助学生分析和理解错题。

你的任务是：
1. 基于题目文本或图片内容进行学习分析
2. 根据题目内容判断所属科目（数学、语文、英语、物理、化学、生物、历史、地理、政治等）
3. 提供正确的解题思路和答案
4. 分析学生可能犯错误的原因
5. 提供学习建议和相关的知识点
6. 生成举一反三的练习题（选择题格式，带 A/B/C/D 选项）

重要规则：
- 优先使用用户已确认的题目文本；如果输入包含图片且文本不足，必须直接根据图片理解题目并解题
- reconstructedQuestionText 必须整理出完整题干；图形题应基于读图理解补全已知条件和求解目标
- 答案必须准确、有条理
- 生成的练习题应该难度适中、与原题相关
- finalAnswer 只能填写题目最终要求的答案，不要填写中间量；必须与 steps 最后一条最终结论一致
- finalAnswerDerivation 必须用一句话说明最终答案来源，且必须与 finalAnswer 一致；如果 steps、mistakeReason 中出现其他中间答案，不得把中间答案写入 finalAnswer
- 输出 JSON 前必须自检 finalAnswer、finalAnswerDerivation、steps、mistakeReason 是否一致；若不一致，以重新验算后的最终结论同步修正
- generatedExercises 必须围绕本题同一个知识点、同一题型、同一种核心解法生成，禁止退化成无关的简单加减法或一元一次方程
- 如果原题含有平方项、平方根、一元二次或 \(x^2=a\) 结构，练习题也必须包含平方项/开平方/正负根相关解法，不能生成 \(x+1=4\)、\(2x=8\) 这类一元一次题
- 如果原题是三角形内角/外角/等腰三角形，练习题也必须是三角形角度关系题
- 如果原题是方程组，练习题也必须是方程组题
- 练习题必须是选择题格式，包含 A/B/C/D 四个选项，其中一个是正确答案
- 答案字段填写正确选项的字母（如 "A"）
- 【几何题配图规则】如果原题属于几何类（三角形、圆、平行四边形、梯形、圆锥等），每道练习题必须附带 diagramData 字段，用结构化 JSON 描述几何图形。坐标使用归一化 0-1 范围。格式：
  {"elements":[{"type":"polygon","points":[[x,y],...],"labels":[{"text":"A","x":0.5,"y":0.05}]},{"type":"line","x1":0,"y1":0,"x2":1,"y2":1,"style":"solid|dashed","role":"known|target|label"},{"type":"text","text":"10cm","x":0.5,"y":0.7,"role":"known"},{"type":"angleArc","vx":0.5,"vy":0.1,"startAngle":55,"sweepAngle":70,"r":0.08,"label":"50°"},{"type":"rightAngle","x":0.5,"y":0.8},{"type":"tickMark","x1":0,"y1":0,"x2":0.5,"y2":0.5,"ticks":1},{"type":"arc","cx":0.5,"cy":0.5,"r":0.3,"startAngle":0,"sweepAngle":180,"filled":true},{"type":"ellipse","cx":0.5,"cy":0.8,"rx":0.3,"ry":0.08},{"type":"point","x":0.5,"y":0.5,"label":"O","role":"label"}],"auxiliaryLines":[...同格式，解题辅助线]}
  role 取值：known（已知条件红色）、target/solve（求解目标绿色）、label（标注蓝色）、auxiliary（辅助线橙色）、external（外角弧）
  三角形外角图必须画清楚延长线：例如“D 在 AB 的延长线上”时，D、A、B 必须共线且 D 在 A 的另一侧；表示外角的 angleArc 必须加 "role":"external"，并画在延长线与另一边之间，不能画成三角形内角。
  非几何题不要输出 diagramData
- aiTags 要求简短精炼（2-8个字），数量 2-4 个，如 ["压强", "力学", "公式"]
- knowledgePoints 可以详细描述，长度不限，如 ["压强公式p=f/s，压强与压力的关系", "受力面积相同时，压力越大压强越大"]
- 如果内容包含 LaTeX，必须先生成合法 JSON：所有 LaTeX 反斜杠都写成 JSON 转义形式，例如 \\frac、\\times、\\(x\\)、\\[x\\]
- 方程组或多行公式必须使用 KaTeX 兼容的 aligned 或 cases 环境，例如 \\begin{cases} x+y=5 \\\\ x-y=1 \\end{cases}，不要使用 \\newline
- 不要在 JSON 字符串内部直接换行；换行必须写成 \\n
- 【LaTeX 格式强制规范——必须严格遵守】
  1. 所有数学公式必须使用标准 LaTeX 定界符包裹：行内公式用 \(公式\)，独立公式用 \[公式\]。禁止使用方括号 [(...) 或 [...] 作为 LaTeX 定界符。
  2. LaTeX 命令必须使用完整的反斜杠前缀，禁止省略反斜杠：
     - 正确命令：\frac、\angle、\triangle、\circ、\times、\cdot、\pm、\sqrt、\pi、\rho、\alpha、\beta、\gamma、\theta、\Delta、\lambda、\mu、\sigma、\omega、\leq、\geq、\neq、\approx、\sin、\cos、\tan、\log、\ln、\mathrm、\rightarrow、\leftarrow
     - 错误写法：frac、angle、triangle、circ、times、cdot、pm、sqrt、pi、rho、alpha
     - 注意：乘号用 \times，除法用 \frac，分数用 \frac{a}{b}，圆周率用 \pi，密度用 \rho
  3. 角度/度数统一用 ^\circ，圆周率统一用 \pi
  4. 上标用 ^{n} 格式，禁止裸 ^n
  5. 物理单位用 \mathrm{}：\mathrm{kg}、\mathrm{m}、\mathrm{N}、\mathrm{Pa}、\mathrm{J}、\mathrm{W}、\mathrm{V}、\mathrm{A}、\mathrm{\Omega}
  6. generatedExercises 中的 question、options、explanation 字段同样必须遵守上述所有 LaTeX 格式规则
  7. JSON 转义规则：反斜杠双写，\ → \\，\\ → \\\\。换行用 \\n。cases 环境行分隔符 \\ → \\\\
     - 示例：\\(x^2=4\)\\n  所以 x=\\pm 2  // JSON 中 \\n = 换行，\\pi = \pi，\\pm = \pm
     - 示例：\[\\begin{cases} x+y=5 \\\\ x-y=1 \\end{cases}\]  // \\\\ 在 JSON 中表示 LaTeX 换行符 \\
返回格式以用户消息中的 Contract V2 为唯一准则，不再返回旧版 V1 顶层结构。
- standardAnswer 对应旧 finalAnswer；solutionSteps 对应旧 steps；normalizedQuestion 对应旧 reconstructedQuestionText。
- 可以保留 visualAssumptions 和 exerciseAnchor 作为兼容扩展字段。
- 没有 studentAnswer 时，mistakeCategory 必须为 null，mistakeReason 必须为空字符串。
- 只输出纯 JSON，不要包含 Markdown 代码围栏、前缀或后缀。''';

  static const _defaultExtractionSystemPrompt =
      r'''你是一个专业的教辅录入员，负责把题目图片整理成可存储、可检索的结构化文本。

你的任务是：
1. 识别图片中的完整原始题目内容，而不只是检测题目边界框
2. 逐字提取题干、选择题选项、填空内容，以及与题目有关的印刷文字
3. 识别并还原数学公式、上下标、分数、根号、方程组等为合法 LaTeX
4. 理解几何图形中的点、线、角、长度、平行/垂直/相等等视觉信息，并在题干中补充可确认的图形条件
5. 保留无法文字化的图形、表格和原图证据，不得因为文字困难就当作内容不存在
6. 忽略无关的手写批改痕迹、圈画、红叉等内容

重要规则：
- 必须以图片内容为准，不要虚构缺失内容
- 选择题必须逐项输出图片中实际存在的选项，使用 A.、B.、C.、D. 等原始标签；缺失或看不清的选项不要凭空补齐 ABCD
- 图形题即使无法完整转成文字，也要在题干中保留“见原题图片”并描述能确认的点、线、角和长度；调用方必须保留原图路径
- extractedQuestionText 保留尽量忠实的识别结果
- normalizedQuestionText 输出更适合展示、搜索和后续 AI 分析的规范文本
- 如果图片无法识别出有效题目，两个文本字段都返回空字符串
- 如果内容包含 LaTeX，必须先生成合法 JSON：所有 LaTeX 反斜杠都写成 JSON 转义形式，例如 \\frac、\\times、\\(x\\)、\\[x\\]
- 方程组或多行公式必须使用 KaTeX 兼容的 aligned 或 cases 环境，例如 \\begin{cases} x+y=5 \\\\ x-y=1 \\end{cases}，不要使用 \\newline
- 不要在 JSON 字符串内部直接换行；换行必须写成 \\n
- 【LaTeX 格式强制规范——必须严格遵守】
  1. 所有数学公式必须使用标准 LaTeX 定界符包裹：行内公式用 \(公式\)，独立公式用 \[公式\]。禁止使用方括号 [(...) 或 [...] 作为 LaTeX 定界符。
  2. LaTeX 命令必须使用完整的反斜杠前缀，禁止省略反斜杠：
     - 正确命令：\frac、\angle、\triangle、\circ、\times、\cdot、\pm、\sqrt、\pi、\rho、\alpha、\beta、\gamma、\theta、\Delta、\lambda、\mu、\sigma、\omega、\leq、\geq、\neq、\approx、\sin、\cos、\tan、\log、\ln、\mathrm、\rightarrow、\leftarrow
     - 错误写法：frac、angle、triangle、circ、times、cdot、pm、sqrt、pi、rho、alpha
     - 注意：乘号用 \times，除法用 \frac，分数用 \frac{a}{b}，圆周率用 \pi，密度用 \rho
  3. 角度/度数统一用 ^\circ，圆周率统一用 \pi
  4. 上标用 ^{n} 格式，禁止裸 ^n
  5. 物理单位用 \mathrm{}：\mathrm{kg}、\mathrm{m}、\mathrm{N}、\mathrm{Pa}、\mathrm{J}、\mathrm{W}、\mathrm{V}、\mathrm{A}、\mathrm{\Omega}
  6. JSON 转义规则：反斜杠双写，\ → \\，\\ → \\\\。换行用 \\n。cases 环境行分隔符 \\ → \\\\
     - 示例：\\(x^2=4\)\\n  所以 x=\\pm 2  // JSON 中 \\n = 换行，\\pi = \pi，\\pm = \pm
     - 示例：\[\\begin{cases} x+y=5 \\\\ x-y=1 \\end{cases}\]  // \\\\ 在 JSON 中表示 LaTeX 换行符 \\
返回格式必须严格如下（不要包含 markdown 代码块标记，使用纯 JSON）：
{
  "subject": "自动判断的科目名称",
  "extractedQuestionText": "从图片提取的原始题目文本",
  "normalizedQuestionText": "整理后的标准题目文本",
  "ocrConfidence": 0.0
}''';

  /// 手写解答模式：忠实转录图片中的手写内容，包括错误步骤。
  ///
  /// 错题本场景下，学生的手写解答过程恰恰是错因分析的核心信息，因此该模式下
  /// 不能"忽略手写批改"，而应原样转录。
  static const _handwrittenExtractionSystemPrompt =
      r'''你是一个专业的教辅录入员，负责把题目图片中的手写内容原样转录成可存储、可检索的结构化文本。

你的任务是：
1. 忠实转录图片中的手写内容，包括学生的解答过程和错误步骤
2. 不要纠正错误，原样转录；学生写错的符号、计算、单位都要保留
3. 输出适合存入题库的规范化文本，便于后续做错因分析
4. 判断题目所属科目
5. 数学公式使用 LaTeX 或 Markdown 友好的表达，保持题意完整

重要规则：
- 必须以图片内容为准，不要虚构缺失内容
- studentAnswer 字段必须包含完整的手写解答过程转录结果
- extractedQuestionText、normalizedQuestionText 仅在能辨识出印刷题干时填写，否则留空字符串
- 如果图片无法识别出有效手写内容，所有文本字段都返回空字符串
- 如果内容包含 LaTeX，必须先生成合法 JSON：所有 LaTeX 反斜杠都写成 JSON 转义形式，例如 \\frac、\\times、\\(x\\)、\\[x\\]
- 方程组或多行公式必须使用 KaTeX 兼容的 aligned 或 cases 环境，例如 \\begin{cases} x+y=5 \\\\ x-y=1 \\end{cases}，不要使用 \\newline
- 不要在 JSON 字符串内部直接换行；换行必须写成 \\n
- 【LaTeX 格式强制规范——必须严格遵守】
  1. 所有数学公式必须使用标准 LaTeX 定界符包裹：行内公式用 \(公式\)，独立公式用 \[公式\]。禁止使用方括号 [(...) 或 [...] 作为 LaTeX 定界符。
  2. LaTeX 命令必须使用完整的反斜杠前缀，禁止省略反斜杠：
     - 正确命令：\frac、\angle、\triangle、\circ、\times、\cdot、\pm、\sqrt、\pi、\rho、\alpha、\beta、\gamma、\theta、\Delta、\lambda、\mu、\sigma、\omega、\leq、\geq、\neq、\approx、\sin、\cos、\tan、\log、\ln、\mathrm、\rightarrow、\leftarrow
     - 错误写法：frac、angle、triangle、circ、times、cdot、pm、sqrt、pi、rho、alpha
     - 注意：乘号用 \times，除法用 \frac，分数用 \frac{a}{b}，圆周率用 \pi，密度用 \rho
  3. 角度/度数统一用 ^\circ，圆周率统一用 \pi
  4. 上标用 ^{n} 格式，禁止裸 ^n
  5. 物理单位用 \mathrm{}：\mathrm{kg}、\mathrm{m}、\mathrm{N}、\mathrm{Pa}、\mathrm{J}、\mathrm{W}、\mathrm{V}、\mathrm{A}、\mathrm{\Omega}
  6. JSON 转义规则：反斜杠双写，\ → \\，\\ → \\\\。换行用 \\n。cases 环境行分隔符 \\ → \\\\
返回格式必须严格如下（不要包含 markdown 代码块标记，使用纯 JSON）：
{
  "subject": "自动判断的科目名称",
  "extractedQuestionText": "可辨识的印刷题干（无则留空字符串）",
  "normalizedQuestionText": "整理后的标准题目文本（无则留空字符串）",
  "studentAnswer": "完整手写解答过程转录，原样保留错误步骤",
  "ocrConfidence": 0.0
}''';

  /// 混合模式：同时识别印刷题干和手写批注。
  static const _mixedExtractionSystemPrompt =
      r'''你是一个专业的教辅录入员，负责把题目图片整理成可存储、可检索的结构化文本。

你的任务是：
1. 同时识别图片中的印刷题干和手写批注
2. 印刷题干写入 extractedQuestionText / normalizedQuestionText
3. 手写批注原样转录到 studentAnswer，包括学生的解答过程和错误步骤；不要纠正错误
4. 判断题目所属科目
5. 数学公式使用 LaTeX 或 Markdown 友好的表达，保持题意完整

重要规则：
- 必须以图片内容为准，不要虚构缺失内容
- extractedQuestionText 保留尽量忠实的印刷题干识别结果
- normalizedQuestionText 输出更适合展示、搜索和后续 AI 分析的规范文本
- studentAnswer 必须包含完整的手写批注/解答过程，原样保留错误步骤
- 如果图片无法识别出有效内容，所有文本字段都返回空字符串
- 如果内容包含 LaTeX，必须先生成合法 JSON：所有 LaTeX 反斜杠都写成 JSON 转义形式，例如 \\frac、\\times、\\(x\\)、\\[x\\]
- 方程组或多行公式必须使用 KaTeX 兼容的 aligned 或 cases 环境，例如 \\begin{cases} x+y=5 \\\\ x-y=1 \\end{cases}，不要使用 \\newline
- 不要在 JSON 字符串内部直接换行；换行必须写成 \\n
- 【LaTeX 格式强制规范——必须严格遵守】
  1. 所有数学公式必须使用标准 LaTeX 定界符包裹：行内公式用 \(公式\)，独立公式用 \[公式\]。禁止使用方括号 [(...) 或 [...] 作为 LaTeX 定界符。
  2. LaTeX 命令必须使用完整的反斜杠前缀，禁止省略反斜杠：
     - 正确命令：\frac、\angle、\triangle、\circ、\times、\cdot、\pm、\sqrt、\pi、\rho、\alpha、\beta、\gamma、\theta、\Delta、\lambda、\mu、\sigma、\omega、\leq、\geq、\neq、\approx、\sin、\cos、\tan、\log、\ln、\mathrm、\rightarrow、\leftarrow
     - 错误写法：frac、angle、triangle、circ、times、cdot、pm、sqrt、pi、rho、alpha
     - 注意：乘号用 \times，除法用 \frac，分数用 \frac{a}{b}，圆周率用 \pi，密度用 \rho
  3. 角度/度数统一用 ^\circ，圆周率统一用 \pi
  4. 上标用 ^{n} 格式，禁止裸 ^n
  5. 物理单位用 \mathrm{}：\mathrm{kg}、\mathrm{m}、\mathrm{N}、\mathrm{Pa}、\mathrm{J}、\mathrm{W}、\mathrm{V}、\mathrm{A}、\mathrm{\Omega}
  6. JSON 转义规则：反斜杠双写，\ → \\，\\ → \\\\。换行用 \\n。cases 环境行分隔符 \\ → \\\\
返回格式必须严格如下（不要包含 markdown 代码块标记，使用纯 JSON）：
{
  "subject": "自动判断的科目名称",
  "extractedQuestionText": "从图片提取的印刷题干原始文本",
  "normalizedQuestionText": "整理后的标准题目文本",
  "studentAnswer": "完整手写批注/解答过程转录，原样保留错误步骤",
  "ocrConfidence": 0.0
}''';

  Future<String> _loadAnalysisSystemPrompt() async {
    final custom = await settingsRepository.getString('system_prompt');
    return custom?.isNotEmpty == true ? custom! : _defaultAnalysisSystemPrompt;
  }

  Future<String> _loadExtractionSystemPrompt({
    CaptureMode mode = CaptureMode.printed,
  }) async {
    final custom =
        await settingsRepository.getString('extraction_system_prompt');
    // 用户自定义了 extraction_system_prompt 时，统一沿用自定义 prompt，不再按模式分支，
    // 避免覆盖用户的刻意配置。
    if (custom?.isNotEmpty == true) return custom!;
    switch (mode) {
      case CaptureMode.handwritten:
        return _handwrittenExtractionSystemPrompt;
      case CaptureMode.mixed:
        return _mixedExtractionSystemPrompt;
      case CaptureMode.printed:
        return _defaultExtractionSystemPrompt;
    }
  }

  String _buildExtractionPrompt({
    required String subjectName,
    required String textHint,
    CaptureMode mode = CaptureMode.printed,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('请先做题目结构化提取。');
    buffer.writeln('用户当前选择的科目提示：$subjectName');
    if (textHint.isNotEmpty) {
      buffer.writeln();
      buffer.writeln('用户已有文本提示：');
      buffer.writeln(textHint);
      buffer.writeln('文本提示可能来自 OCR 或上次整理，只能作参考；图片中的图形、标注和区域关系必须以原图为准。');
    }
    buffer.writeln();
    buffer.writeln(
        '若题目包含图形/示意图，请先忠实描述原图中真实看到的图形类型、边界、标注和目标区域；看不清就写不确定，不要猜成梯形/半圆/扇形等特定题型。');
    switch (mode) {
      case CaptureMode.handwritten:
        buffer.writeln(
            '本次录入模式：手写解答。本图为手写作答，请把学生写在题上的作答内容完整转录到 studentAnswer 字段（保留原始格式，包括公式 LaTeX），包括学生的解答过程和错误步骤。不要纠正错误，原样转录。返回的 studentAnswer 字段必须包含完整手写内容；extractedQuestionText、normalizedQuestionText 留空字符串或仅记录可辨识的印刷题干。');
        buffer.writeln(
            '请输出 subject、extractedQuestionText、normalizedQuestionText、studentAnswer。方程组或多行公式请使用 aligned/cases 环境，不要使用 \\newline。');
        break;
      case CaptureMode.mixed:
        buffer.writeln(
            '本次录入模式：混合。本图同时包含印刷题干和手写作答，请把学生写在题上的作答内容完整转录到 studentAnswer 字段（保留原始格式，包括公式 LaTeX），同时识别印刷题干写入 extractedQuestionText / normalizedQuestionText。手写部分原样转录，包括错误步骤，不要纠正。');
        buffer.writeln(
            '请输出 subject、extractedQuestionText、normalizedQuestionText、studentAnswer。方程组或多行公式请使用 aligned/cases 环境，不要使用 \\newline。');
        break;
      case CaptureMode.printed:
        buffer.writeln(
            '请输出 subject、extractedQuestionText、normalizedQuestionText。方程组或多行公式请使用 aligned/cases 环境，不要使用 \\newline。');
        buffer.writeln(
            '如有学生作答痕迹（即使是手写），也请转录到 studentAnswer 字段，保留原始格式（包括公式 LaTeX）。');
        break;
    }
    return buffer.toString();
  }

  bool isGraphicalQuestion(
    String text,
    String subjectName, {
    String? imagePath,
  }) {
    if (imagePath == null || imagePath.isEmpty) return false;
    final subject = _parseSubject(subjectName);
    if (subject != Subject.math &&
        subject != Subject.physics &&
        subject != Subject.science) {
      return false;
    }

    final normalized = text.toLowerCase();
    final hasDiagramCue =
        RegExp(r'如图|下图|上图|图中|示意图|阴影|图形|图示|图所示').hasMatch(normalized);
    final hasGraphicalFeature = RegExp(
            r'面积|周长|角|度|直角|边长|半径|直径|高|底|宽|长|三角形|矩形|长方形|正方形|梯形|圆|半圆|扇形|立方体|长方体|圆柱|圆锥|cm|厘米|mm|毫米|m\b|米|°|∠|速度|相向|每小时')
        .hasMatch(text);
    return hasDiagramCue && hasGraphicalFeature;
  }

  bool _shouldAnalyzeImageFirst(
    String text,
    String subjectName, {
    String? imagePath,
  }) {
    if (imagePath == null || imagePath.isEmpty) return false;
    final subject = _parseSubject(subjectName);
    if (subject != Subject.math &&
        subject != Subject.physics &&
        subject != Subject.science) {
      return false;
    }

    final normalized = text.toLowerCase().trim();
    if (normalized.isEmpty || normalized.length < 80) return true;
    return RegExp(r'如图|下图|上图|图中|示意图|阴影|图形|图示|图所示|看图|观察图').hasMatch(normalized);
  }

  @visibleForTesting
  String buildAnalysisPromptForTest(
    String correctedText,
    String subjectName, {
    bool isGraphicalQuestion = false,
    String studentAnswer = '',
    String modelName = 'configured-model',
  }) {
    return _buildAnalysisPrompt(
      correctedText,
      subjectName,
      isGraphicalQuestion: isGraphicalQuestion,
      studentAnswer: studentAnswer,
      modelName: modelName,
    );
  }

  String _buildAnalysisPrompt(
    String correctedText,
    String subjectName, {
    bool isGraphicalQuestion = false,
    String studentAnswer = '',
    String modelName = 'configured-model',
  }) {
    final buffer = StringBuffer();
    buffer.writeln('请分析以下$subjectName科目的错题：');
    buffer.writeln();
    if (isGraphicalQuestion) {
      buffer.writeln('图片题输入说明：');
      buffer.writeln(
          '下面文本可能来自 OCR 或上一步整理，只能作为参考线索，不是已确认题干；图片中的图形、标注、区域关系和求解目标优先级最高。');
      buffer.writeln('参考文本：');
    } else {
      buffer.writeln('已确认题目文本：');
    }
    buffer.writeln(correctedText);
    buffer.writeln();
    buffer.writeln('学生作答：');
    buffer.writeln(studentAnswer.trim().isEmpty ? '（未提供）' : studentAnswer);
    buffer.writeln();
    if (isGraphicalQuestion) {
      buffer.writeln('图形/示意图题分析要求：');
      buffer.writeln('1. 第一目标是直接根据原图理解题目并完成解题，不要把人工确认作为解题前置条件。');
      buffer.writeln('2. 先读图：只依据图片确认图形结构、可见标注、边界、目标区域或求解对象；参考文本不能覆盖图片观察。');
      buffer.writeln(
          '3. 再解题：基于已读出的图形关系选择公式并计算；如果需要辅助线或构造，请说明应该连接哪些点、延长哪条线或把区域拆成哪些基础图形。');
      buffer.writeln('4. 不要因为参考文本出现面积、阴影、圆、半圆等词就硬套梯形、三角形、半圆或扇形；图形类型必须来自原图观察。');
      buffer.writeln('5. 不要为了写完整题干而强行命名外部轮廓；除非图片或题干明确说明，不要把外边框称为梯形、三角形、矩形等。');
      buffer.writeln(
          '6. 图中数字只能按可确认的标注关系使用；不能自动解释成上底、下底、高、半径或直径。无关或含义不确定的数字不要写入解题条件。');
      buffer.writeln(
          '7. reconstructedQuestionText 只重构与求解目标直接相关且能从图片确认的条件；如果目标是求某个圆/半圆/阴影区域面积，不要把无关外框条件编入题干。');
      buffer.writeln(
          '8. 只有关键标注、目标区域或半径/直径关系确实无法从图中判断，才在 mistakeReason 或 studyAdvice 中提示需要人工核对；不要因此跳过解题。');
      buffer.writeln(
          '9. 解题步骤必须基于 reconstructedQuestionText 中的可靠读图关系展开；不要在步骤中引入未确认的外部形状名称或边长含义。');
      buffer.writeln(
          '10. 必须输出 visualAssumptions 对象，用于声明读图假设和关键标注可信度；如果关键标注含义不确定，visualAssumptions.needsManualReview 必须为 true。');
      buffer.writeln(
          '11. finalAnswer、finalAnswerDerivation 和 steps 最后一条必须是同一个最终答案；如果读图假设不确定，也只能给一个“在该假设下”的最终答案，不得在 finalAnswerDerivation 中同时写互斥答案。');
      buffer.writeln();
    }
    final topicProfile =
        _buildExerciseTopicProfile(sourceQuestionText: correctedText);
    final topicAnchor = _exerciseAnchorText(topicProfile);
    if (topicAnchor.isNotEmpty) {
      buffer.writeln('举一反三锚点：$topicAnchor');
      buffer.writeln(
          'generatedExercises 必须保持 domain/object/method，不得生成 avoid 中的题型。');
      buffer.writeln(
          'generatedExercises 必须恰好 3 道选择题，difficulty 依次为 简单、同级、提高；三题必须保持同一知识点、同一题型、同一核心解法。');
      buffer.writeln(
          '难度递进只能通过换数、增加一步同方法变形或增加一个同主题条件完成，禁止通过切换题型/知识点提高难度；无法满足时返回空 generatedExercises。');
      final isGeometryDomain =
          topicProfile.domain == _ExerciseDomain.planeGeometryArea ||
              topicProfile.domain == _ExerciseDomain.planeGeometryAngle ||
              topicProfile.domain == _ExerciseDomain.planeGeometryLength ||
              topicProfile.domain == _ExerciseDomain.solidGeometryVolume;
      if (isGraphicalQuestion || isGeometryDomain) {
        buffer.writeln(
            '几何题的每道 generatedExercises 必须包含 diagramData 字段（归一化坐标），不得为 null。');
      }
      buffer.writeln();
    }
    buffer.writeln(_promptBuilder.buildV2ContractInstruction(
      modelName: modelName,
    ));
    buffer.writeln(
        '图形题可以额外返回 visualAssumptions；练习锚点可以额外返回 exerciseAnchor。'
        'visualAssumptions 中所有解题使用的标注都必须给出 evidence 和 confidence。'
        'standardAnswer、solutionSteps 最后一条必须一致；方程组或多行公式使用 aligned/cases，不要使用 \\newline。');
    return buffer.toString();
  }

  String _exerciseAnchorText(_ExerciseTopicProfile profile) {
    switch (profile.domain) {
      case _ExerciseDomain.planeGeometryArea:
        return 'domain=planeGeometryArea; object=${profile.object.name}; methods=${profile.methods.map((m) => m.name).join('/')}; variant=${profile.variant?.name ?? 'generic'}; avoid=equation/function/quadraticRoot/solidVolume/lengthOnly';
      case _ExerciseDomain.planeGeometryLength:
        return 'domain=planeGeometryLength; object=rightTriangle; methods=${profile.methods.map((m) => m.name).join('/')}; variant=rightTriangleLength; avoid=area/angle/equation/function/volume';
      case _ExerciseDomain.algebraEquation:
        if (profile.object == _ExerciseObject.quadraticEquation) {
          return 'domain=algebraEquation; object=quadraticEquation; methods=squareRoot; avoid=linearEquation/function/geometry/volume';
        }
        return 'domain=algebraEquation; object=linearEquation; methods=linearSolve; avoid=quadraticRoot/function/geometry/volume';
      case _ExerciseDomain.equationSystem:
        return 'domain=equationSystem; object=equationSystem; methods=elimination; avoid=linearEquation/quadraticRoot/function/geometry';
      case _ExerciseDomain.planeGeometryAngle:
        return 'domain=planeGeometryAngle; object=triangle; methods=angleSum; avoid=equation/function/volume';
      case _ExerciseDomain.solidGeometryVolume:
        return 'domain=solidGeometryVolume; object=coneCylinder; methods=formulaSubstitution; variant=${profile.variant?.name ?? 'generic'}; avoid=quadraticRoot/function/equationSystem/planeGeometryArea';
      case _ExerciseDomain.functionEvaluation:
        return 'domain=functionEvaluation; object=functionExpression; methods=functionSubstitution; avoid=quadraticRoot/equationSystem/geometry/volume';
      case _ExerciseDomain.proportionalRelation:
        return 'domain=proportionalRelation; object=proportionalRelation; methods=ratioRelation; avoid=equationSystem/quadraticRoot/function/geometry';
      case _ExerciseDomain.generic:
        return '';
    }
  }

  AiJsonDecodeResult _decodeResponseJson(String content) {
    try {
      final decoded = _jsonDecoder.decode(content);
      final schemaVersion = decoded.value['schemaVersion'];
      if (schemaVersion == AiAnalysisResponseContract.version &&
          decoded.markdownWrapped) {
        throw const FormatException(
          'Contract V2 响应不得包含 Markdown 代码围栏',
        );
      }
      if (schemaVersion == AiAnalysisResponseContract.version &&
          decoded.repairStrategy == AiJsonRepairStrategy.flatFieldRecovery) {
        throw const FormatException(
          'Contract V2 响应结构损坏，不允许降级为平铺字段恢复',
        );
      }
      debugPrint(
        '[AiAnalysisService] AI JSON decoded: ${decoded.diagnosticSummary}',
      );
      return decoded;
    } on AiJsonDecodingException catch (error) {
      debugPrint('[AiAnalysisService] AI JSON decode failed: ${error.inner}');
      throw _AiJsonParseException(error.inner);
    } on FormatException catch (error) {
      debugPrint('[AiAnalysisService] AI JSON contract envelope rejected: $error');
      throw _AiJsonParseException(error);
    }
  }

  Map<String, dynamic> _parseResponseJson(String content) {
    return _decodeResponseJson(content).value;
  }

  AiQuestionExtractionResult _parseExtractionResponse(String content) {
    final map = _parseResponseJson(content);
    final subject = _parseSubject((map['subject'] as String?) ?? '');
    final subjectKey = subject?.name ?? (map['subject'] as String?) ?? '';
    var extractedQuestionText = _normalizeExtractedQuestionText(
      (map['extractedQuestionText'] as String?)?.trim() ?? '',
    );
    var normalizedQuestionText = _normalizeExtractedQuestionText(
      (map['normalizedQuestionText'] as String?)?.trim() ?? '',
    );

    // 后处理校验：先做保守的 OCR 混淆字符纠错，再做 LaTeX 结构校验（仅警告）。
    if (extractedQuestionText.isNotEmpty) {
      final correctedExtracted = correctCommonOcrErrors(
        extractedQuestionText,
        subject: subjectKey,
      );
      if (correctedExtracted != extractedQuestionText) {
        debugPrint(
            '[AiAnalysisService] extractedQuestionText OCR correction applied '
            '(length=${extractedQuestionText.length})');
        extractedQuestionText = correctedExtracted;
      }
      final latexIssue = validateLatexStructure(extractedQuestionText);
      if (latexIssue != null) {
        debugPrint(
            '[AiAnalysisService] extractedQuestionText LaTeX 警告: $latexIssue');
      }
    }
    if (normalizedQuestionText.isNotEmpty) {
      final correctedNormalized = correctCommonOcrErrors(
        normalizedQuestionText,
        subject: subjectKey,
      );
      if (correctedNormalized != normalizedQuestionText) {
        debugPrint(
            '[AiAnalysisService] normalizedQuestionText OCR correction applied '
            '(length=${normalizedQuestionText.length})');
        normalizedQuestionText = correctedNormalized;
      }
      final latexIssue = validateLatexStructure(normalizedQuestionText);
      if (latexIssue != null) {
        debugPrint(
            '[AiAnalysisService] normalizedQuestionText LaTeX 警告: $latexIssue');
      }
    }

    final splitSeed = normalizedQuestionText.isNotEmpty
        ? normalizedQuestionText
        : extractedQuestionText;

    // 手写解答模式 / 混合模式下，AI 应返回 studentAnswer 字段（手写过程原样转录）。
    // printed 模式下该字段不存在，保持为 null。
    final rawStudentAnswer =
        (map['studentAnswer'] as String?)?.trim() ?? '';
    final studentAnswer = rawStudentAnswer.isEmpty
        ? null
        : _normalizeExtractedQuestionText(rawStudentAnswer);

    return AiQuestionExtractionResult(
      subject: subject,
      extractedQuestionText: extractedQuestionText,
      normalizedQuestionText: normalizedQuestionText,
      splitResult: _defaultSplitQuestionCandidates(splitSeed),
      studentAnswer: studentAnswer,
      ocrConfidence: (map['ocrConfidence'] as num?)
          ?.toDouble()
          .clamp(0.0, 1.0)
          .toDouble(),
    );
  }

  AnalysisResult _parseAnalysisResponseV2(String content) {
    try {
      return _parseAnalysisResponse(content, allowLegacy: false);
    } on _AiJsonParseException {
      rethrow;
    } on FormatException catch (error) {
      throw _AiJsonParseException(error);
    }
  }

  AnalysisResult _parseAnalysisResponse(
    String content, {
    bool allowLegacy = true,
  }) {
    final decoded = _decodeResponseJson(content);
    final map = AiAnalysisResponseContract.normalize(
      decoded.value,
      allowLegacy: allowLegacy,
    );

    Subject? subject;
    final subjectStr = map['subject'] as String?;
    if (subjectStr != null && subjectStr.isNotEmpty) {
      debugPrint('[AiAnalysisService] AI returned subject: $subjectStr');
      subject = _parseSubject(subjectStr);
      debugPrint('[AiAnalysisService] Parsed subject: $subject');
    }

    final visualAssumptions = _parseVisualAssumptions(map['visualAssumptions']);
    final contractMetadata = AnalysisResult.fromJson(map);
    final diagnostics = AiResponseDiagnostics(
      contentLength: decoded.contentLength,
      contentFingerprint: decoded.contentFingerprint,
      markdownWrapped: decoded.markdownWrapped,
      repairStrategy: decoded.repairStrategy.name,
      capturedAt: DateTime.now(),
    );

    return ParsedAnalysisResult(
      rawContent: content,
      subject: subject,
      finalAnswer: _normalizeExtractedQuestionText(
        map['finalAnswer'] as String? ?? '',
      ),
      finalAnswerDerivation: _normalizeExtractedQuestionText(
        map['finalAnswerDerivation'] as String? ?? '',
      ),
      reconstructedQuestionText: _normalizeExtractedQuestionText(
        map['reconstructedQuestionText'] as String? ?? '',
      ),
      visualAssumptions: visualAssumptions,
      visualAssumptionStatus: _visualAssumptionStatus(visualAssumptions),
      steps: List<String>.from(map['steps'] as List? ?? <String>[])
          .map(_normalizeExtractedQuestionText)
          .toList(),
      aiTags: List<String>.from(map['aiTags'] as List? ?? <String>[]),
      knowledgePoints:
          List<String>.from(map['knowledgePoints'] as List? ?? <String>[])
              .map(_normalizeExtractedQuestionText)
              .toList(),
      mistakeReason: _normalizeExtractedQuestionText(
        map['mistakeReason'] as String? ?? '',
      ),
      studyAdvice: _normalizeExtractedQuestionText(
        map['studyAdvice'] as String? ?? '',
      ),
      schemaVersion: contractMetadata.schemaVersion,
      promptVersion: contractMetadata.promptVersion,
      modelName: contractMetadata.modelName,
      confidence: contractMetadata.confidence,
      uncertainties: contractMetadata.uncertainties,
      evidence: contractMetadata.evidence,
      mistakeCategory: contractMetadata.mistakeCategory,
      originalQuestion: contractMetadata.originalQuestion,
      normalizedQuestion: contractMetadata.normalizedQuestion,
      studentAnswer: contractMetadata.studentAnswer,
      standardAnswer: contractMetadata.standardAnswer,
      solutionSteps: contractMetadata.solutionSteps,
      reviewPlan: contractMetadata.reviewPlan,
      isLegacyContract: contractMetadata.isLegacyContract,
      responseDiagnostics: diagnostics,
      specializedAnalysis: contractMetadata.specializedAnalysis,
    );
  }

  @visibleForTesting
  AiQuestionExtractionResult parseExtractionResultForTest(String content) {
    return _parseExtractionResponse(content);
  }

  List<GeneratedExercise> extractGeneratedExercisesFromContent(
    String content, {
    required String questionId,
    AnalysisResult? analysis,
    String? sourceQuestionText,
  }) {
    final map = _parseResponseJson(content);
    return _parseGeneratedExercises(
      map,
      questionId: questionId,
      analysis: analysis,
      sourceQuestionText: sourceQuestionText,
    );
  }

  List<GeneratedExercise> extractGeneratedExercises(
    AnalysisResult analysis, {
    required String questionId,
    String? sourceQuestionText,
  }) {
    return _defaultGeneratedExercises(
      questionId,
      analysis: analysis,
      sourceQuestionText: sourceQuestionText,
    );
  }

  List<GeneratedExercise> _parseGeneratedExercises(
    Map<String, dynamic> map, {
    required String questionId,
    AnalysisResult? analysis,
    String? sourceQuestionText,
  }) {
    final rawExercises = map['generatedExercises'];
    if (rawExercises is! List || rawExercises.isEmpty) {
      return _defaultGeneratedExercises(
        questionId,
        analysis: analysis,
        sourceQuestionText: sourceQuestionText,
      );
    }

    final parsedAnalysis = analysis ?? _analysisFromParsedMap(map);
    final sourceProfile = _buildExerciseTopicProfile(
      sourceQuestionText: sourceQuestionText,
      analysis: parsedAnalysis,
    );
    final now = DateTime.now();
    final parsed = <GeneratedExercise>[];

    for (var index = 0; index < rawExercises.length; index++) {
      final item = rawExercises[index];
      if (item is! Map) continue;
      final exerciseMap = Map<String, dynamic>.from(item);
      final id = (exerciseMap['id'] as String?)?.trim();
      final question = _normalizeExtractedQuestionText(
        (exerciseMap['question'] as String?)?.trim() ?? '',
      );
      if (question.isEmpty) continue;

      List<String>? options;
      final rawOptions = exerciseMap['options'];
      if (rawOptions is List) {
        final normalizedOptions = rawOptions
            .map((option) => option?.toString().trim() ?? '')
            .where((option) => option.isNotEmpty)
            .map(_normalizeExtractedQuestionText)
            .toList();
        if (normalizedOptions.isNotEmpty) {
          options = normalizedOptions;
        }
      }

      final diagramRaw = exerciseMap['diagramData'];
      final diagramParsed = _parseDiagramData(diagramRaw);

      final exercise = GeneratedExercise(
        id: id != null && id.isNotEmpty ? id : 'gen_${questionId}_${index + 1}',
        questionId: questionId,
        generationMode: ExerciseGenerationMode.practice,
        difficulty: _normalizeExerciseDifficulty(
          (exerciseMap['difficulty'] as String?)?.trim(),
        ),
        question: question,
        answer: _normalizeExtractedQuestionText(
          (exerciseMap['answer'] as String?)?.trim() ?? '',
        ),
        explanation: _normalizeExtractedQuestionText(
          (exerciseMap['explanation'] as String?)?.trim() ?? '',
        ),
        createdAt: now,
        order: index,
        options: options,
        diagramData: diagramParsed,
      );

      final acceptable =
          _isGeneratedExerciseAcceptable(exercise, sourceProfile);
      if (acceptable) {
        parsed.add(GeneratedExercise(
          id: exercise.id,
          questionId: exercise.questionId,
          generationMode: exercise.generationMode,
          difficulty: exercise.difficulty,
          question: exercise.question,
          answer: exercise.answer,
          explanation: exercise.explanation,
          createdAt: exercise.createdAt,
          order: parsed.length,
          options: exercise.options,
          diagramData: exercise.diagramData,
        ));
      }
    }

    if (sourceProfile.hasStrongSignal) {
      final defaults = _defaultGeneratedExercises(
        questionId,
        analysis: parsedAnalysis,
        sourceQuestionText: sourceQuestionText,
      );
      return _mergeGeneratedExercisesWithDefaults(
        parsed,
        defaults,
        questionId: questionId,
        now: now,
      );
    }

    final expectedCount = rawExercises.length >= 3 ? 3 : rawExercises.length;
    if (parsed.length < expectedCount) {
      return _defaultGeneratedExercises(
        questionId,
        analysis: parsedAnalysis,
        sourceQuestionText: sourceQuestionText,
      );
    }

    return _selectPracticeExerciseSet(
      parsed,
      questionId: questionId,
      now: now,
    );
  }

  List<GeneratedExercise> _mergeGeneratedExercisesWithDefaults(
    List<GeneratedExercise> accepted,
    List<GeneratedExercise> defaults, {
    required String questionId,
    required DateTime now,
  }) {
    const difficulties = <String>['简单', '同级', '提高'];
    final byDifficulty = <String, GeneratedExercise>{};

    for (final exercise in accepted) {
      byDifficulty.putIfAbsent(exercise.difficulty, () => exercise);
    }

    final merged = <GeneratedExercise>[];
    for (var index = 0; index < difficulties.length; index++) {
      final difficulty = difficulties[index];
      final fallback = defaults.firstWhere(
        (exercise) => exercise.difficulty == difficulty,
        orElse: () => defaults[index],
      );
      final selected = byDifficulty[difficulty] ?? fallback;
      final selectedIsFallback = identical(selected, fallback);
      merged.add(GeneratedExercise(
        id: selected.id.isNotEmpty
            ? selected.id
            : 'gen_${questionId}_${index + 1}',
        questionId: questionId,
        generationMode: selected.generationMode,
        difficulty: difficulty,
        question: selected.question,
        answer: selected.answer,
        explanation: selected.explanation,
        createdAt: selectedIsFallback ? fallback.createdAt : now,
        order: index,
        options: selected.options,
        diagramData: selected.diagramData,
      ));
    }
    return merged;
  }

  List<GeneratedExercise> _selectPracticeExerciseSet(
    List<GeneratedExercise> exercises, {
    required String questionId,
    required DateTime now,
  }) {
    const difficulties = <String>['简单', '同级', '提高'];
    final selected = <GeneratedExercise>[];
    final used = <String>{};

    for (final difficulty in difficulties) {
      final match = exercises
          .where((exercise) => exercise.difficulty == difficulty)
          .cast<GeneratedExercise?>()
          .firstWhere((exercise) => exercise != null, orElse: () => null);
      if (match != null) {
        selected.add(match);
        used.add(match.id);
      }
    }

    for (final exercise in exercises) {
      if (selected.length >= 3) break;
      if (used.contains(exercise.id)) continue;
      selected.add(exercise);
      used.add(exercise.id);
    }

    return selected.asMap().entries.map((entry) {
      final exercise = entry.value;
      return GeneratedExercise(
        id: exercise.id.isNotEmpty
            ? exercise.id
            : 'gen_${questionId}_${entry.key + 1}',
        questionId: questionId,
        generationMode: exercise.generationMode,
        difficulty: difficulties.length > entry.key
            ? difficulties[entry.key]
            : exercise.difficulty,
        question: exercise.question,
        answer: exercise.answer,
        explanation: exercise.explanation,
        createdAt: exercise.createdAt,
        order: entry.key,
        options: exercise.options,
        diagramData: exercise.diagramData,
      );
    }).toList();
  }

  String _normalizeExerciseDifficulty(String? difficulty) {
    final normalized = difficulty?.trim() ?? '';
    switch (normalized) {
      case '简单':
      case '基础':
      case '容易':
        return '简单';
      case '同级':
      case '中等':
      case '普通':
      case '巩固':
        return '同级';
      case '提高':
      case '提升':
      case '困难':
      case '挑战':
      case '拓展':
        return '提高';
      default:
        return normalized.isEmpty ? '同级' : normalized;
    }
  }

  Map<String, dynamic>? _parseDiagramData(Object? value) {
    if (value is! Map) return null;
    final data = Map<String, dynamic>.from(value);
    final elements = data['elements'];
    if (elements is! List || elements.isEmpty) return null;
    return data;
  }

  VisualAssumptions? _parseVisualAssumptions(Object? value) {
    if (value is Map<String, dynamic>) {
      return VisualAssumptions.fromJson(value);
    }
    if (value is Map) {
      return VisualAssumptions.fromJson(Map<String, dynamic>.from(value));
    }
    return null;
  }

  VisualAssumptionStatus _visualAssumptionStatus(
    VisualAssumptions? assumptions,
  ) {
    if (assumptions == null || !assumptions.hasContent) {
      return VisualAssumptionStatus.none;
    }
    if (assumptions.needsManualReview ||
        assumptions.uncertainItems.isNotEmpty ||
        assumptions.measurements.any((item) =>
            item.usedInSolution &&
            _isReviewLevelVisualAssumption(item.confidence))) {
      return VisualAssumptionStatus.needsReview;
    }
    return VisualAssumptionStatus.reliable;
  }

  bool _isReviewLevelVisualAssumption(String confidence) {
    final normalized = confidence.toLowerCase().trim();
    return normalized == 'low' ||
        normalized == 'medium' ||
        normalized == '中' ||
        normalized == '中等' ||
        normalized == '低';
  }

  String _visualAssumptionReviewNote(VisualAssumptions? assumptions) {
    final reason = assumptions?.reviewReason.trim() ?? '';
    if (reason.isNotEmpty) return reason;
    final uncertainItems = assumptions?.uncertainItems ?? const <String>[];
    if (uncertainItems.isNotEmpty) {
      return '图中关键标注含义需核对：${uncertainItems.join('、')}。';
    }
    return '图中关键标注含义需核对，当前解析仅作可能解法。';
  }

  AnalysisResult _analysisFromParsedMap(Map<String, dynamic> map) {
    List<String> listField(String key) {
      final value = map[key];
      if (value is! List) return const <String>[];
      return value
          .map((item) => item?.toString().trim() ?? '')
          .where((item) => item.isNotEmpty)
          .toList();
    }

    final visualAssumptions = _parseVisualAssumptions(map['visualAssumptions']);

    return AnalysisResult(
      subject: _parseSubject(map['subject']?.toString() ?? ''),
      finalAnswer: map['finalAnswer']?.toString() ?? '',
      finalAnswerDerivation: map['finalAnswerDerivation']?.toString() ?? '',
      reconstructedQuestionText:
          map['reconstructedQuestionText']?.toString() ?? '',
      visualAssumptions: visualAssumptions,
      visualAssumptionStatus: _visualAssumptionStatus(visualAssumptions),
      steps: listField('steps'),
      aiTags: listField('aiTags'),
      knowledgePoints: listField('knowledgePoints'),
      mistakeReason: map['mistakeReason']?.toString() ?? '',
      studyAdvice: map['studyAdvice']?.toString() ?? '',
    );
  }

  bool _isGeneratedExerciseAcceptable(
    GeneratedExercise exercise,
    _ExerciseTopicProfile sourceProfile,
  ) {
    if (exercise.question.trim().isEmpty ||
        exercise.answer.trim().isEmpty ||
        exercise.explanation.trim().isEmpty) {
      return false;
    }

    if (_hasGeneratedExerciseSelfInvalidation(exercise)) {
      return false;
    }

    if (_hasGeneratedExerciseAnswerConflict(exercise)) {
      return false;
    }

    final normalizedAnswer = exercise.answer.trim().toUpperCase();
    if (!RegExp(r'^[A-D]$').hasMatch(normalizedAnswer)) return false;

    final options = exercise.options;
    if (options == null || options.length != 4) return false;
    final optionLetters = options
        .map((option) =>
            option.trim().isEmpty ? '' : option.trim()[0].toUpperCase())
        .toSet();
    if (!optionLetters.containsAll(const <String>{'A', 'B', 'C', 'D'})) {
      return false;
    }

    if (_requiresExerciseDiagram(sourceProfile) &&
        exercise.diagramData == null) {
      return false;
    }
    if (_hasInvalidExteriorAngleDiagram(exercise)) {
      return false;
    }

    if (!sourceProfile.hasStrongSignal) return true;

    final exerciseText =
        '${exercise.question} ${exercise.explanation} ${options.join(' ')}';
    if (!_exerciseMatchesTopicAnchor(exerciseText, sourceProfile)) {
      return false;
    }
    if (!_exerciseMatchesSourceTarget(exerciseText, sourceProfile)) {
      return false;
    }
    if (sourceProfile.domain == _ExerciseDomain.planeGeometryArea &&
        _hasForbiddenPlaneAreaDrift(exerciseText)) {
      return false;
    }

    final exerciseProfile = _buildExerciseTopicProfile(
      sourceQuestionText: exerciseText,
      profileSource: _TopicProfileSource.exercise,
    );
    return _isExerciseProfileCompatible(sourceProfile, exerciseProfile);
  }

  bool _hasInvalidExteriorAngleDiagram(GeneratedExercise exercise) {
    final diagram = exercise.diagramData;
    if (diagram == null) return false;

    final spec = _exteriorAngleSpec(exercise.question);
    if (spec == null) {
      return false;
    }

    final labels = _diagramPointLabels(diagram);
    final vertex = labels[spec.vertex];
    final base = labels[spec.basePoint];
    final extension = labels[spec.extensionPoint];
    if (vertex == null || base == null || extension == null) return true;

    final baseRay = _Point2(base.x - vertex.x, base.y - vertex.y);
    final extensionRay =
        _Point2(extension.x - vertex.x, extension.y - vertex.y);
    final baseLength = math.sqrt(baseRay.x * baseRay.x + baseRay.y * baseRay.y);
    final extensionLength = math.sqrt(
        extensionRay.x * extensionRay.x + extensionRay.y * extensionRay.y);
    if (baseLength < 0.001 || extensionLength < 0.001) return true;

    final cross =
        (baseRay.x * extensionRay.y - baseRay.y * extensionRay.x).abs() /
            (baseLength * extensionLength);
    final dot = baseRay.x * extensionRay.x + baseRay.y * extensionRay.y;
    if (cross > 0.08 || dot >= 0) return true;

    final hasExtensionLine = _hasDiagramLineBetween(diagram, vertex, extension);
    if (!hasExtensionLine) return true;

    final hasExternalArc = _diagramElements(diagram).any((element) {
      if (element['type'] != 'angleArc') return false;
      final vx = element['vx'];
      final vy = element['vy'];
      if (vx is! num || vy is! num) return false;
      if (!_isNear(_Point2(vx.toDouble(), vy.toDouble()), vertex)) {
        return false;
      }
      final role = element['role']?.toString().toLowerCase();
      return role == 'external' || role == 'explicit';
    });
    return !hasExternalArc;
  }

  _ExteriorAngleSpec? _exteriorAngleSpec(String question) {
    final text = question
        .toLowerCase()
        .replaceAll(r'\angle', '∠')
        .replaceAll(RegExp(r'\\[()\[\]{}]'), '')
        .replaceAll(RegExp(r'[\\()\[\]{}\s]'), '');
    if (!text.contains('外角') || !text.contains('延长')) return null;

    final extensionMatch =
        RegExp(r'点?([a-z])在([a-z])([a-z])的?延长线上').firstMatch(text);
    final angleMatch = RegExp(r'∠([a-z])([a-z])([a-z])').firstMatch(text);
    if (extensionMatch == null || angleMatch == null) return null;

    final extensionPoint = angleMatch.group(1)!;
    final vertex = angleMatch.group(2)!;
    final namedExtensionPoint = extensionMatch.group(1)!;
    final segmentStart = extensionMatch.group(2)!;
    final segmentEnd = extensionMatch.group(3)!;

    if (namedExtensionPoint != extensionPoint) return null;
    if (vertex == segmentStart) {
      return _ExteriorAngleSpec(
        extensionPoint: extensionPoint,
        vertex: vertex,
        basePoint: segmentEnd,
      );
    }
    if (vertex == segmentEnd) {
      return _ExteriorAngleSpec(
        extensionPoint: extensionPoint,
        vertex: vertex,
        basePoint: segmentStart,
      );
    }
    return null;
  }

  Map<String, _Point2> _diagramPointLabels(Map<String, dynamic> diagram) {
    final labels = <String, _Point2>{};
    for (final element in _diagramElements(diagram)) {
      final type = element['type'];
      if (type == 'polygon') {
        final points = element['points'];
        final rawLabels = element['labels'];
        if (points is! List || rawLabels is! List) continue;
        for (var i = 0; i < rawLabels.length && i < points.length; i++) {
          final labelMap = rawLabels[i];
          final point = points[i];
          if (labelMap is! Map || point is! List || point.length < 2) continue;
          final label = labelMap['text']?.toString().trim().toLowerCase();
          final x = point[0];
          final y = point[1];
          if (label == null || label.isEmpty || x is! num || y is! num) {
            continue;
          }
          labels[label] = _Point2(x.toDouble(), y.toDouble());
        }
      } else if (type == 'point') {
        final label = element['label']?.toString().trim().toLowerCase();
        final x = element['x'];
        final y = element['y'];
        if (label == null || label.isEmpty || x is! num || y is! num) {
          continue;
        }
        labels[label] = _Point2(x.toDouble(), y.toDouble());
      }
    }
    return labels;
  }

  Iterable<Map<String, dynamic>> _diagramElements(
      Map<String, dynamic> diagram) {
    final elements = diagram['elements'];
    if (elements is! List) return const Iterable<Map<String, dynamic>>.empty();
    return elements.whereType<Map>().map(Map<String, dynamic>.from);
  }

  bool _hasDiagramLineBetween(
    Map<String, dynamic> diagram,
    _Point2 a,
    _Point2 b,
  ) {
    return _diagramElements(diagram).any((element) {
      if (element['type'] != 'line') return false;
      final x1 = element['x1'];
      final y1 = element['y1'];
      final x2 = element['x2'];
      final y2 = element['y2'];
      if (x1 is! num || y1 is! num || x2 is! num || y2 is! num) {
        return false;
      }
      final p1 = _Point2(x1.toDouble(), y1.toDouble());
      final p2 = _Point2(x2.toDouble(), y2.toDouble());
      return (_isNear(p1, a) && _isNear(p2, b)) ||
          (_isNear(p1, b) && _isNear(p2, a));
    });
  }

  bool _isNear(_Point2 a, _Point2 b, {double threshold = 0.04}) {
    final dx = a.x - b.x;
    final dy = a.y - b.y;
    return dx * dx + dy * dy <= threshold * threshold;
  }

  bool _exerciseMatchesSourceTarget(
    String exerciseText,
    _ExerciseTopicProfile sourceProfile,
  ) {
    if (sourceProfile.domain != _ExerciseDomain.planeGeometryArea) {
      return true;
    }

    if (sourceProfile.variant == _ExerciseVariant.compositeSemicircleArea) {
      return _hasCompositeAreaTargetSignal(exerciseText) &&
          !_targetsOnlySemicircleArea(exerciseText);
    }

    return true;
  }

  bool _targetsOnlySemicircleArea(String text) {
    final normalized = text.toLowerCase();
    final asksSemicircleArea = _hasAnySignal(normalized, <String>[
      '求半圆面积',
      '求该半圆的面积',
      '求这个半圆的面积',
      '求阴影半圆面积',
    ]);
    return asksSemicircleArea && !_hasCompositeAreaTargetSignal(normalized);
  }

  bool _hasGeneratedExerciseSelfInvalidation(GeneratedExercise exercise) {
    final text =
        '${exercise.question} ${exercise.explanation} ${exercise.options?.join(' ') ?? ''}';
    return _hasAnySignal(text, <String>[
      '选项中没有',
      '没有该值',
      '无正确选项',
      '选项设计不严谨',
      '选项有误',
      '原选项设计',
      '需重新检查',
      '需要重新检查',
      '修正后应',
      '应为修正',
      '无法从选项',
      '题目不严谨',
      '本题无解',
    ]);
  }

  bool _requiresExerciseDiagram(_ExerciseTopicProfile sourceProfile) {
    return sourceProfile.domain == _ExerciseDomain.planeGeometryArea ||
        sourceProfile.domain == _ExerciseDomain.planeGeometryAngle ||
        sourceProfile.domain == _ExerciseDomain.planeGeometryLength;
  }

  bool _hasGeneratedExerciseAnswerConflict(GeneratedExercise exercise) {
    final answer = exercise.answer.trim().toUpperCase();
    if (!RegExp(r'^[A-D]$').hasMatch(answer)) return false;
    final text = exercise.explanation.replaceAll(' ', '').toUpperCase();
    final explicitAnswerMatches = RegExp(
      r'(?:答案(?:是|为)?|正确答案(?:是|为)?|正确选项(?:是|为)?|应选|应为|选择|选)([A-D])',
    ).allMatches(text);
    for (final match in explicitAnswerMatches) {
      final stated = match.group(1);
      if (stated != null && stated != answer) return true;
    }

    final options = exercise.options;
    if (options == null || options.length != 4) return false;
    final answerIndex = answer.codeUnitAt(0) - 'A'.codeUnitAt(0);
    if (answerIndex < 0 || answerIndex >= options.length) return false;

    final selectedTokens = _mathConclusionTokens(options[answerIndex]);
    final explanationTokens = _mathConclusionTokens(exercise.explanation);
    if (selectedTokens.isEmpty || explanationTokens.isEmpty) return false;
    if (selectedTokens.intersection(explanationTokens).isNotEmpty) {
      return false;
    }

    final distractorTokens = <String>{};
    for (var i = 0; i < options.length; i++) {
      if (i == answerIndex) continue;
      distractorTokens.addAll(_mathConclusionTokens(options[i]));
    }
    return explanationTokens.intersection(distractorTokens).isNotEmpty;
  }

  Set<String> _mathConclusionTokens(String text) {
    final normalized = text
        .replaceAll('π', r'\pi')
        .replaceAll('，', ' ')
        .replaceAll('。', ' ')
        .replaceAll('；', ' ')
        .replaceAll(';', ' ')
        .replaceAll(RegExp(r'\s+'), '')
        .replaceFirst(RegExp(r'^[A-Da-d][\.、．:]'), '')
        .toLowerCase();
    final tokens = <String>{};

    for (final match in RegExp(
      r'\d+(?:\.\d+)?[-+]\d+(?:\.\d+)?(?:\\pi|pi)(?:/\d+(?:\.\d+)?)?',
    ).allMatches(normalized)) {
      final token = match.group(0);
      if (token != null) tokens.add(_normalizeMathToken(token));
    }

    for (final match in RegExp(
      r'\d+(?:\.\d+)?(?:\\pi|pi)(?:/\d+(?:\.\d+)?)?',
    ).allMatches(normalized)) {
      final token = match.group(0);
      if (token != null) tokens.add(_normalizeMathToken(token));
    }

    for (final match
        in RegExp(r'\\frac\{([^{}]+)\}\{([^{}]+)\}').allMatches(normalized)) {
      final numerator = match.group(1);
      final denominator = match.group(2);
      if (numerator != null && denominator != null) {
        tokens.add(_normalizeMathToken('$numerator/$denominator'));
      }
    }
    return tokens.where((token) => token.isNotEmpty).toSet();
  }

  String _normalizeMathToken(String token) {
    return token
        .replaceAll('π', r'\pi')
        .replaceAll('pi', r'\pi')
        .replaceAllMapped(
          RegExp(r'\\frac\{([^{}]+)\}\{([^{}]+)\}'),
          (match) => '${match.group(1)}/${match.group(2)}',
        )
        .replaceAll(RegExp(r'[\\(){}\[\]\s]'), '');
  }

  bool _hasForbiddenPlaneAreaDrift(String text) {
    final normalized = text.toLowerCase();
    return _hasAnySignal(normalized, <String>[
      '体积',
      '立体几何',
      '圆柱',
      '圆锥',
      '长方体',
      '正方体',
      '棱柱',
      '棱锥',
      'v=',
      r'\frac{1}{3}\pi',
      r'\pi r^2 h',
      'πr^2h',
      'π r^2 h',
      '函数',
      '方程组',
    ]);
  }

  bool _isExerciseProfileCompatible(
    _ExerciseTopicProfile source,
    _ExerciseTopicProfile exercise,
  ) {
    if (source.domain != exercise.domain) return false;
    if (source.object == _ExerciseObject.circleFamily) {
      if (exercise.object != _ExerciseObject.circleFamily) return false;
    } else if (source.object != _ExerciseObject.generic &&
        exercise.object != source.object) {
      return false;
    }
    if (source.methods.isNotEmpty && exercise.methods.isNotEmpty) {
      if (source.methods.intersection(exercise.methods).isEmpty) return false;
    }
    if (source.variant != null && exercise.variant != null) {
      return source.variant == exercise.variant;
    }
    return true;
  }

  bool _exerciseMatchesTopicAnchor(
    String text,
    _ExerciseTopicProfile profile,
  ) {
    final normalized = text.toLowerCase();
    switch (profile.domain) {
      case _ExerciseDomain.functionEvaluation:
        return _hasFunctionSignal(normalized) &&
            _hasAnySignal(normalized,
                <String>['求', '代入', '函数值', 'f(', 'g(', 'h(', 'f（', 'g（', 'h（']);
      case _ExerciseDomain.proportionalRelation:
        return _hasProportionalRelationSignal(normalized);
      case _ExerciseDomain.solidGeometryVolume:
        return _hasVolumeSignal(normalized);
      case _ExerciseDomain.equationSystem:
        return _hasEquationSystemSignal(normalized);
      case _ExerciseDomain.planeGeometryAngle:
        return _hasTriangleAngleSignal(normalized);
      case _ExerciseDomain.planeGeometryArea:
        if (_hasForbiddenPlaneAreaDrift(normalized)) return false;
        return _hasPlaneGeometryAreaSignal(normalized);
      case _ExerciseDomain.planeGeometryLength:
        return _hasPlaneGeometryLengthSignal(normalized, profile);
      case _ExerciseDomain.algebraEquation:
        if (profile.object == _ExerciseObject.quadraticEquation) {
          return _hasQuadraticRootSignal(normalized);
        }
        return _hasLinearEquationSignal(normalized);
      case _ExerciseDomain.generic:
        return true;
    }
  }

  _ExerciseTopicProfile _buildExerciseTopicProfile({
    String? sourceQuestionText,
    AnalysisResult? analysis,
    _TopicProfileSource profileSource = _TopicProfileSource.sourceQuestion,
  }) {
    final text = <String>[
      sourceQuestionText ?? '',
      ...?analysis?.aiTags,
      ...?analysis?.knowledgePoints,
      analysis?.finalAnswer ?? '',
      ...?analysis?.steps,
      analysis?.mistakeReason ?? '',
      analysis?.studyAdvice ?? '',
    ].join(' ').toLowerCase();

    final hasVolume = _hasVolumeSignal(text);
    final hasPlaneGeometryArea =
        !hasVolume && _hasPlaneGeometryAreaSignal(text);
    final hasFunctionEvaluation = _hasFunctionEvaluationSignal(text);
    final hasProportionalRelation = _hasProportionalRelationSignal(text);
    final hasSquarePerpendicularBisectorLength = !hasPlaneGeometryArea &&
        !hasVolume &&
        _hasSquarePerpendicularBisectorLengthSignal(text);
    final hasRightTriangleLength = !hasPlaneGeometryArea &&
        !hasVolume &&
        !hasSquarePerpendicularBisectorLength &&
        _hasRightTriangleLengthSignal(text);
    final hasEquationSystem =
        !hasProportionalRelation && _hasEquationSystemSignal(text);
    final hasTriangleAngle = !hasPlaneGeometryArea &&
        !hasRightTriangleLength &&
        _hasTriangleAngleSignal(text);
    final hasQuadraticRoot = !hasVolume &&
        !hasPlaneGeometryArea &&
        !hasFunctionEvaluation &&
        !hasProportionalRelation &&
        !hasRightTriangleLength &&
        _hasQuadraticRootSignal(text, allowBareSquareSymbol: true);
    final hasLinearEquation = !hasQuadraticRoot &&
        !hasEquationSystem &&
        !hasFunctionEvaluation &&
        !hasProportionalRelation &&
        !hasPlaneGeometryArea &&
        !hasRightTriangleLength &&
        _hasLinearEquationSignal(text);

    if (hasPlaneGeometryArea) {
      return _ExerciseTopicProfile(
        domain: _ExerciseDomain.planeGeometryArea,
        object: _hasCircleAreaSignal(text)
            ? _ExerciseObject.circleFamily
            : _ExerciseObject.generic,
        methods: _geometryAreaMethods(text),
        hasStrongSignal: true,
        variant: _circleAreaVariant(text),
      );
    }
    if (hasRightTriangleLength) {
      final methods = <_ExerciseMethod>{_ExerciseMethod.pythagorean};
      if (_hasEqualLengthSignal(text)) {
        methods.add(_ExerciseMethod.equalLengthRelation);
      }
      return _ExerciseTopicProfile(
        domain: _ExerciseDomain.planeGeometryLength,
        object: _ExerciseObject.rightTriangle,
        methods: methods,
        hasStrongSignal: true,
        variant: _ExerciseVariant.rightTriangleLength,
      );
    }
    if (hasSquarePerpendicularBisectorLength) {
      return const _ExerciseTopicProfile(
        domain: _ExerciseDomain.planeGeometryLength,
        object: _ExerciseObject.square,
        methods: <_ExerciseMethod>{
          _ExerciseMethod.equalLengthRelation,
          _ExerciseMethod.perpendicularBisector,
          _ExerciseMethod.coordinateGeometry,
        },
        hasStrongSignal: true,
        variant: _ExerciseVariant.squarePerpendicularBisectorLength,
      );
    }
    if (hasVolume) {
      return _ExerciseTopicProfile(
        domain: _ExerciseDomain.solidGeometryVolume,
        object: _ExerciseObject.coneCylinder,
        methods: const <_ExerciseMethod>{_ExerciseMethod.formulaSubstitution},
        hasStrongSignal: true,
        variant: _solidVolumeVariant(text),
      );
    }
    if (hasFunctionEvaluation) {
      return const _ExerciseTopicProfile(
        domain: _ExerciseDomain.functionEvaluation,
        object: _ExerciseObject.functionExpression,
        methods: <_ExerciseMethod>{_ExerciseMethod.functionSubstitution},
        hasStrongSignal: true,
      );
    }
    if (hasProportionalRelation) {
      return const _ExerciseTopicProfile(
        domain: _ExerciseDomain.proportionalRelation,
        object: _ExerciseObject.proportionalRelation,
        methods: <_ExerciseMethod>{_ExerciseMethod.ratioRelation},
        hasStrongSignal: true,
      );
    }
    if (hasEquationSystem) {
      return const _ExerciseTopicProfile(
        domain: _ExerciseDomain.equationSystem,
        object: _ExerciseObject.equationSystem,
        methods: <_ExerciseMethod>{_ExerciseMethod.elimination},
        hasStrongSignal: true,
      );
    }
    if (hasTriangleAngle) {
      return const _ExerciseTopicProfile(
        domain: _ExerciseDomain.planeGeometryAngle,
        object: _ExerciseObject.triangle,
        methods: <_ExerciseMethod>{_ExerciseMethod.angleSum},
        hasStrongSignal: true,
      );
    }
    if (hasQuadraticRoot) {
      return const _ExerciseTopicProfile(
        domain: _ExerciseDomain.algebraEquation,
        object: _ExerciseObject.quadraticEquation,
        methods: <_ExerciseMethod>{_ExerciseMethod.squareRoot},
        hasStrongSignal: true,
      );
    }
    if (hasLinearEquation) {
      final isStrong = profileSource == _TopicProfileSource.exercise;
      return _ExerciseTopicProfile(
        domain: _ExerciseDomain.algebraEquation,
        object: _ExerciseObject.linearEquation,
        methods: const <_ExerciseMethod>{_ExerciseMethod.linearSolve},
        hasStrongSignal: isStrong,
      );
    }
    return const _ExerciseTopicProfile(
      domain: _ExerciseDomain.generic,
      object: _ExerciseObject.generic,
      methods: <_ExerciseMethod>{},
      hasStrongSignal: false,
    );
  }

  bool _hasAnySignal(String text, Iterable<String> needles) {
    return needles.any(text.contains);
  }

  bool _hasSquareSymbol(String text) {
    return RegExp(r'(x|a|b|m|n|p|q|r|y)\s*(\^\{?2\}?|²)').hasMatch(text);
  }

  bool _hasEquationSystemSignal(String text) {
    return _hasAnySignal(
        text, <String>['方程组', '消元', 'begin{cases}', 'cases', '二元一次方程组']);
  }

  bool _hasProportionalRelationSignal(String text) {
    final hasRatioSignal = _hasAnySignal(text, <String>[
      '比例',
      '比值',
      '分式关系',
      '分数关系',
      '倍数关系',
      '成比例',
      'a:b',
      'm:n',
      'x:y',
      r'\frac',
    ]);
    if (!hasRatioSignal) return false;
    return _hasAnySignal(text, <String>[
      '和式',
      '差式',
      '和差',
      'a+b',
      'x+y',
      'm+n',
      'a-b',
      'x-y',
      'm-n',
      '求 a',
      '求a',
      '求 x',
      '求x',
      '求两个量',
      '代入法',
      '转化为',
    ]);
  }

  bool _hasTriangleAngleSignal(String text) {
    return _hasAnySignal(
            text, <String>['三角', '等腰', '内角', '外角', '角形', r'\triangle', '△']) &&
        _hasAnySignal(text, <String>['角', '度', r'\angle', '∠', r'^\circ', '°']);
  }

  bool _hasRightTriangleLengthSignal(String text) {
    if (_hasPlaneGeometryAreaSignal(text) || _hasVolumeSignal(text)) {
      return false;
    }
    final hasLengthTarget = _hasAnySignal(text, <String>[
      '线段',
      '边长',
      '长度',
      '斜边',
      '直角边',
      '求bc',
      '求 bc',
      '求 ab',
      '求ab',
      '求 ac',
      '求ac',
      '求 bd',
      '求bd',
    ]);
    if (!hasLengthTarget) return false;
    final hasRightTriangle = _hasAnySignal(text, <String>[
      '直角',
      '90°',
      r'90^\circ',
      r'90^\circ',
      '勾股',
      '斜边',
      '直角三角形',
      r'a^2+b^2=c^2',
      r'a^2 + b^2 = c^2',
    ]);
    return hasRightTriangle &&
        _hasAnySignal(
            text, <String>['三角', '角形', '△', r'\triangle', 'ab', 'bc', 'ac']);
  }

  bool _hasSquarePerpendicularBisectorLengthSignal(String text) {
    if (_hasPlaneGeometryAreaSignal(text) || _hasVolumeSignal(text)) {
      return false;
    }
    final hasLengthTarget = _hasAnySignal(text, <String>[
      '线段',
      '边长',
      '长度',
      '求df',
      '求 df',
      '求af',
      '求 af',
      '求ef',
      '求 ef',
    ]);
    if (!hasLengthTarget) return false;
    final hasSquare = _hasAnySignal(text, <String>['正方形', 'abcd']);
    final hasPerpendicularBisector =
        _hasAnySignal(text, <String>['垂直平分线', '垂直平分', '中垂线']);
    final hasEdgePoint = _hasAnySignal(text, <String>[
      '中点',
      '点f',
      '点 f',
      '边dc',
      '边 dc',
      'dc上',
      'dc 上',
    ]);
    return hasSquare && hasPerpendicularBisector && hasEdgePoint;
  }

  bool _hasPlaneGeometryLengthSignal(
    String text,
    _ExerciseTopicProfile profile,
  ) {
    switch (profile.variant) {
      case _ExerciseVariant.squarePerpendicularBisectorLength:
        return _hasSquarePerpendicularBisectorLengthSignal(text);
      case _ExerciseVariant.rightTriangleLength:
        return _hasRightTriangleLengthSignal(text);
      default:
        return _hasRightTriangleLengthSignal(text) ||
            _hasSquarePerpendicularBisectorLengthSignal(text);
    }
  }

  bool _hasEqualLengthSignal(String text) {
    return _hasAnySignal(text, <String>['等长', '相等', 'bd=bc', 'ab=ac', 'bc=bd']);
  }

  _ExerciseVariant? _circleAreaVariant(String text) {
    if (_hasCompositeSemicircleAreaSignal(text)) {
      return _ExerciseVariant.compositeSemicircleArea;
    }
    if (_hasAnySignal(
        text, <String>['圆环', '大圆', '小圆', '空白', '剩余', '减去', '挖去', '内圆', '外圆'])) {
      return _ExerciseVariant.annulusOrShadedArea;
    }
    if (_hasAnySignal(text, <String>['半圆', '一半', r'\frac{1}{2}', '1/2'])) {
      return _ExerciseVariant.semicircleArea;
    }
    if (_hasAnySignal(text, <String>['阴影'])) {
      return _ExerciseVariant.annulusOrShadedArea;
    }
    if (_hasAnySignal(text, <String>['圆', '半径', '直径', r'\pi', 'π'])) {
      return _ExerciseVariant.circleArea;
    }
    return null;
  }

  bool _hasCompositeSemicircleAreaSignal(String text) {
    final hasSemicircle = _hasAnySignal(text, <String>['半圆']);
    final hasOuterArea = _hasAnySignal(
      text,
      <String>[
        '梯形',
        '上底',
        '下底',
        '上边',
        '下边',
        '底边',
        '水平边',
        '外框',
        '外边界',
        '外框面积',
        '上方水平边',
        '下方水平边',
        '右侧竖直边',
        '右边高',
      ],
    );
    final hasDiameterDerived = _hasAnySignal(
      text,
      <String>[
        '斜边',
        '直径',
        '勾股',
        '水平差',
        '竖直差',
        '高度',
        '高为',
        '右边高',
        '竖直边高',
        '竖直高度',
      ],
    );
    final hasDifference = _hasAnySignal(
      text,
      <String>['剩余', '减去', '减小', '面积差', '外侧', '之间', '括号', '半圆外'],
    );
    return hasSemicircle && hasOuterArea && hasDiameterDerived && hasDifference;
  }

  bool _hasFramedSemicircleDiameterSignal(
    String? sourceQuestionText,
    AnalysisResult? analysis,
  ) {
    final text = <String>[
      sourceQuestionText ?? '',
      ...?analysis?.aiTags,
      ...?analysis?.knowledgePoints,
      ...?analysis?.steps,
      analysis?.mistakeReason ?? '',
      analysis?.studyAdvice ?? '',
    ].join(' ').toLowerCase();
    final hasFramedShape = _hasAnySignal(text, <String>[
      '外框',
      '上边',
      '下边',
      '上底',
      '下底',
      '右边高',
      '水平差',
      '竖直差',
      '左侧斜边',
    ]);
    final hasSemicircleDiameter = _hasAnySignal(text, <String>[
      '半圆直径',
      '半圆以左侧斜边为直径',
      '左侧斜边为半圆直径',
      '斜边为半圆直径',
    ]);
    return hasFramedShape && hasSemicircleDiameter;
  }

  _FramedSemicircleSpec? _framedSemicircleSpecFromSource(
    String? sourceQuestionText,
    AnalysisResult? analysis,
  ) {
    final text = <String>[
      sourceQuestionText ?? '',
      ...?analysis?.steps,
    ].join(' ');
    int? firstNumberAfter(Iterable<String> labels) {
      for (final label in labels) {
        final match =
            RegExp('$label(?:长)?(?:为|是|=)?\\s*(\\d+)').firstMatch(text);
        if (match != null) return int.tryParse(match.group(1)!);
      }
      return null;
    }

    final top = firstNumberAfter(const <String>['上边', '上底', '上水平边']);
    final bottom = firstNumberAfter(const <String>['下边', '下底', '下水平边', '底边']);
    final height = firstNumberAfter(const <String>['右边高', '右侧竖直边高', '高']);
    if (top == null || bottom == null || height == null) return null;
    if (top <= 0 || bottom <= 0 || height <= 0 || top == bottom) return null;
    return _FramedSemicircleSpec(top: top, bottom: bottom, height: height);
  }

  _ExerciseVariant? _solidVolumeVariant(String text) {
    if (_hasAnySignal(text, <String>['圆锥', r'\frac{1}{3}\pi'])) {
      return _ExerciseVariant.coneVolume;
    }
    if (_hasAnySignal(text, <String>['圆柱', 'πr^2h', 'π r^2 h', r'\pi r^2 h'])) {
      return _ExerciseVariant.cylinderVolume;
    }
    return null;
  }

  bool _hasPlaneGeometryAreaSignal(String text) {
    if (!_hasAnySignal(text, <String>[
      '面积',
      '阴影',
      '空白部分',
      '剩余部分',
      'cm²',
      'cm^2',
      'm²',
      'm^2',
      '平方厘米',
      '平方米'
    ])) {
      return false;
    }
    return _hasAnySignal(text, <String>[
      '圆',
      '半圆',
      '扇形',
      '圆环',
      '半径',
      '直径',
      r'\pi',
      'π',
      '三角形',
      '矩形',
      '长方形',
      '正方形',
      '梯形',
      '平行四边形',
      '底',
      '高',
      '宽',
      '长',
    ]);
  }

  bool _hasCircleAreaSignal(String text) {
    return _hasAnySignal(text, <String>[
      '圆',
      '半圆',
      '扇形',
      '圆环',
      '半径',
      '直径',
      '圆心角',
      r'\pi',
      'π',
    ]);
  }

  Set<_ExerciseMethod> _geometryAreaMethods(String text) {
    final methods = <_ExerciseMethod>{_ExerciseMethod.formulaSubstitution};
    if (_hasAnySignal(
        text, <String>['半圆', '一半', r'\frac{1}{2}', '1/2', '比例', '圆心角', '扇形'])) {
      methods.add(_ExerciseMethod.halfArea);
    }
    if (_hasAnySignal(text, <String>['阴影', '空白', '剩余', '剪去', '半圆外'])) {
      methods.add(_ExerciseMethod.shadedArea);
    }
    if (_hasAnySignal(
        text, <String>['减', '减去', '减小', '大圆', '小圆', '圆环', '空白', '半圆外'])) {
      methods.add(_ExerciseMethod.largeMinusSmall);
    }
    if (_hasAnySignal(text, <String>['组合', '拆', '拼', '补'])) {
      methods.add(_ExerciseMethod.splitAndCombine);
    }
    return methods;
  }

  bool _hasVolumeSignal(String text) {
    final hasSolidObject = _hasAnySignal(text, <String>[
      '体积',
      '立体几何',
      '圆柱',
      '圆锥',
      '长方体',
      '正方体',
      '棱柱',
      '棱锥',
      '底面半径',
      r'\frac{1}{3}\pi',
      'πr^2h',
      'π r^2 h',
      r'\pi r^2 h',
    ]);
    if (!hasSolidObject) return false;
    if (_hasPlaneGeometryAreaSignal(text) &&
        !_hasAnySignal(text, <String>['体积', '圆柱', '圆锥', '长方体', '正方体'])) {
      return false;
    }
    return true;
  }

  bool _hasFunctionSignal(String text) {
    return _hasAnySignal(text, <String>[
      'f(',
      'g(',
      'h(',
      'f（',
      'g（',
      'h（',
      r'f\left',
      r'g\left',
      r'h\left'
    ]);
  }

  bool _hasFunctionEvaluationSignal(String text) {
    return _hasAnySignal(text, <String>['函数值', '函数解析式', '代入函数', '自变量']) ||
        (_hasFunctionSignal(text) && _hasAnySignal(text, <String>['代入', '求']));
  }

  bool _hasQuadraticRootSignal(String text,
      {bool allowBareSquareSymbol = false}) {
    final hasRootLanguage = _hasAnySignal(
        text, <String>['平方根', '开平方', '一元二次', '二次方程', '正负根', r'\sqrt', r'\pm']);
    if (hasRootLanguage) return true;
    return allowBareSquareSymbol &&
        _hasSquareSymbol(text) &&
        _hasAnySignal(text, <String>['解方程', '求 x', '求x', 'x 的值', 'x的值']);
  }

  bool _hasLinearEquationSignal(String text) {
    return _hasAnySignal(text, <String>['一元一次', '移项', '解方程']);
  }

  Subject? _parseSubject(String input) {
    final lower = input.toLowerCase();

    for (final subject in Subject.values) {
      if (subject.label == input || subject.name == input) {
        return subject;
      }
    }

    if (lower.contains('物理') || lower == 'wuli' || lower == 'physics') {
      return Subject.physics;
    }
    if (lower.contains('语文') || lower == 'chinese') return Subject.chinese;
    if (lower.contains('英语') || lower.contains('english')) {
      return Subject.english;
    }
    if (lower.contains('化学') || lower == 'chemistry') return Subject.chemistry;
    if (lower.contains('生物') || lower == 'biology') return Subject.biology;
    if (lower.contains('历史') || lower == 'history') return Subject.history;
    if (lower.contains('地理') || lower == 'geography') return Subject.geography;
    if (lower.contains('政治') || lower == 'politics') return Subject.politics;
    if (lower.contains('科学') || lower == 'science') return Subject.science;
    if (lower.contains('数学') ||
        lower == 'math' ||
        lower.contains('mathematics')) {
      return Subject.math;
    }
    return null;
  }

  /// AI 判断用户答案是否正确
  Future<bool> judgeAnswer({
    required String question,
    required String userAnswer,
    required String correctAnswer,
    List<String>? options,
  }) async {
    debugPrint(
      '[AiAnalysisService] judgeAnswer called '
      '(questionLength=${question.length}, userAnswerLength=${userAnswer.length})',
    );

    final config = await settingsRepository.getAiProviderConfig();

    if (config == null ||
        config.baseUrl.isEmpty ||
        config.apiKey.isEmpty ||
        config.model.isEmpty) {
      debugPrint('[AiAnalysisService] No config - using direct compare');
      return userAnswer == correctAnswer;
    }

    final dio = _createClient(config);
    final prompt =
        _buildJudgePrompt(question, userAnswer, correctAnswer, options);

    try {
      final response =
          await _retryPost(dio, '/chat/completions', data: <String, dynamic>{
        'model': config.model,
        'messages': <Map<String, String>>[
          <String, String>{
            'role': 'system',
            'content': '你是一个判断答案是否正确的助手。请仔细分析题目和答案，给出判断结果。'
          },
          <String, String>{'role': 'user', 'content': prompt},
        ],
        'temperature': 0.1,
        'max_tokens': 50,
      });

      final content =
          response.data['choices'][0]['message']['content'] as String;
      debugPrint(
        '[AiAnalysisService] judgeAnswer response received '
        '(length=${content.length})',
      );

      // 解析 AI 判断结果
      final lower = content.toLowerCase();
      if (lower.contains('正确') && !lower.contains('不正')) {
        return true;
      } else if (lower.contains('错误') || lower.contains('不对')) {
        return false;
      }

      // 默认回退到直接比较
      return userAnswer == correctAnswer;
    } catch (e) {
      debugPrint('[AiAnalysisService] judgeAnswer error: $e');
      // 回退到直接比较
      return userAnswer == correctAnswer;
    }
  }

  String _buildJudgePrompt(String question, String userAnswer,
      String correctAnswer, List<String>? options) {
    final buffer = StringBuffer();
    buffer.writeln('请判断以下答案是否正确：');
    buffer.writeln();
    buffer.writeln('题目：$question');
    if (options != null && options.isNotEmpty) {
      buffer.writeln('选项：');
      for (final option in options) {
        buffer.writeln(option);
      }
    }
    buffer.writeln();
    buffer.writeln('正确答案：$correctAnswer');
    buffer.writeln('用户答案：$userAnswer');
    buffer.writeln();
    buffer.writeln('请只回答"正确"或"错误"，不需要其他解释。');

    return buffer.toString();
  }

  /// Phase 13-2：独立生成变式题（举一反三）。
  ///
  /// 与 [analyzeQuestion] 不同，本方法只请求 AI 生成变式题，不重新分析
  /// 整道错题。失败时回退到内置兜底题（[_defaultGeneratedExercises]），
  /// 保证调用方总能拿到 3 道可练习题。
  ///
  /// 输入 [sourceQuestionText] 是源错题文本（必须，用于 anchor 推断和
  /// 漂移检测）；[subjectName] 用于判定是否走几何题分支；[knowledgePoints]
  /// 可选，用于在 prompt 中提示 AI 限定知识点范围。
  ///
  /// 返回 3 道按"简单 / 同级 / 提高"难度排序的 [GeneratedExercise]。
  Future<List<GeneratedExercise>> generateVariants({
    required String questionId,
    required String sourceQuestionText,
    required String subjectName,
    List<String>? knowledgePoints,
  }) async {
    debugPrint('[AiAnalysisService] generateVariants called for $questionId');

    final config = await settingsRepository.getAiProviderConfig();

    // 无 AI 配置 → 直接走兜底题。
    if (config == null ||
        config.baseUrl.isEmpty ||
        config.apiKey.isEmpty ||
        config.model.isEmpty) {
      debugPrint('[AiAnalysisService] No config - using default exercises');
      return _defaultGeneratedExercises(
        questionId,
        sourceQuestionText: sourceQuestionText,
      );
    }

    final prompt = _buildVariantsPrompt(
      sourceQuestionText: sourceQuestionText,
      subjectName: subjectName,
      knowledgePoints: knowledgePoints,
    );

    try {
      final content = await _requestAiContent(
        config: config,
        systemPrompt: '你是一位资深的中学命题教师，擅长基于原题生成同知识点、'
            '同题型、同核心解法的变式练习题。请严格按 JSON 返回。',
        prompt: prompt,
        maxTokens: 2000,
        temperature: 0.7,
      );
      // 复用现有解析 + 漂移检测 + 兜底链路。
      return extractGeneratedExercisesFromContent(
        content,
        questionId: questionId,
        sourceQuestionText: sourceQuestionText,
      );
    } catch (e) {
      debugPrint('[AiAnalysisService] generateVariants error: $e');
      // 网络失败/JSON 解析失败 → 走兜底题。
      return _defaultGeneratedExercises(
        questionId,
        sourceQuestionText: sourceQuestionText,
      );
    }
  }

  /// Phase 13-2：构建变式题生成 prompt（复用 anchor + 漂移检测要求）。
  ///
  /// 与 [_buildAnalysisPrompt] 相比，本方法只问变式题，不要求 finalAnswer/
  /// visualAssumptions/reconstructedQuestionText 等字段，max_tokens 可降到
  /// 2000 左右。
  @visibleForTesting
  String buildVariantsPromptForTest({
    required String sourceQuestionText,
    required String subjectName,
    List<String>? knowledgePoints,
  }) =>
      _buildVariantsPrompt(
        sourceQuestionText: sourceQuestionText,
        subjectName: subjectName,
        knowledgePoints: knowledgePoints,
      );

  String _buildVariantsPrompt({
    required String sourceQuestionText,
    required String subjectName,
    List<String>? knowledgePoints,
  }) {
    final buffer = StringBuffer();
    buffer.writeln('请为以下$subjectName科目题目生成 3 道变式练习题（举一反三）。');
    buffer.writeln();
    buffer.writeln('源题目：');
    buffer.writeln(sourceQuestionText);
    buffer.writeln();
    if (knowledgePoints != null && knowledgePoints.isNotEmpty) {
      buffer.writeln('相关知识点：${knowledgePoints.join('、')}');
      buffer.writeln('变式题必须围绕以上知识点展开，不得切换到其他知识点。');
      buffer.writeln();
    }
    final topicProfile =
        _buildExerciseTopicProfile(sourceQuestionText: sourceQuestionText);
    final topicAnchor = _exerciseAnchorText(topicProfile);
    if (topicAnchor.isNotEmpty) {
      buffer.writeln('举一反三锚点：$topicAnchor');
      buffer.writeln(
          'generatedExercises 必须保持 domain/object/method，不得生成 avoid 中的题型。');
      buffer.writeln(
          'generatedExercises 必须恰好 3 道选择题，difficulty 依次为 简单、同级、提高；三题必须保持同一知识点、同一题型、同一核心解法。');
      buffer.writeln(
          '难度递进只能通过换数、增加一步同方法变形或增加一个同主题条件完成，禁止通过切换题型/知识点提高难度；无法满足时返回空 generatedExercises。');
      final isGeometryDomain =
          topicProfile.domain == _ExerciseDomain.planeGeometryArea ||
              topicProfile.domain == _ExerciseDomain.planeGeometryAngle ||
              topicProfile.domain == _ExerciseDomain.planeGeometryLength ||
              topicProfile.domain == _ExerciseDomain.solidGeometryVolume;
      if (isGeometryDomain) {
        buffer.writeln(
            '几何题的每道 generatedExercises 必须包含 diagramData 字段（归一化坐标），不得为 null。');
      }
      buffer.writeln();
    }
    buffer.writeln(
        '请以 JSON 返回 {"generatedExercises": [...]}，每道题含字段：id（字符串）、difficulty（"简单"/"同级"/"提高"）、question（题干，支持 LaTeX）、options（4 个选项，形如 ["A. ...", "B. ...", "C. ...", "D. ..."]）、answer（A/B/C/D 之一）、explanation（解析，支持 LaTeX）、diagramData（几何题必填，含 elements 数组）。');
    buffer.writeln('方程组或多行公式请使用 aligned/cases 环境，不要使用 \\newline。');
    return buffer.toString();
  }

  List<GeneratedExercise> _defaultCircleAreaExercises(
    String questionId,
    DateTime now,
  ) {
    return <GeneratedExercise>[
      GeneratedExercise(
        id: 'e1',
        questionId: questionId,
        generationMode: ExerciseGenerationMode.practice,
        difficulty: '简单',
        question: r'一个圆的半径为 4 cm，求这个圆的面积。',
        options: const [
          r'A. \(8\pi\) cm²',
          r'B. \(12\pi\) cm²',
          r'C. \(16\pi\) cm²',
          r'D. \(32\pi\) cm²',
        ],
        answer: 'C',
        explanation: r'圆面积公式为 \(S=\pi r^2\)，代入 \(r=4\)，得 \(S=16\pi\) cm²。',
        createdAt: now,
        order: 0,
        diagramData: _circleDiagram('4cm'),
      ),
      GeneratedExercise(
        id: 'e2',
        questionId: questionId,
        generationMode: ExerciseGenerationMode.practice,
        difficulty: '同级',
        question: r'一个圆的直径为 10 cm，求这个圆的面积。',
        options: const [
          r'A. \(10\pi\) cm²',
          r'B. \(20\pi\) cm²',
          r'C. \(25\pi\) cm²',
          r'D. \(100\pi\) cm²',
        ],
        answer: 'C',
        explanation: r'直径为 10 cm，所以半径为 5 cm，面积为 \(\pi\times5^2=25\pi\) cm²。',
        createdAt: now,
        order: 1,
        diagramData: _circleDiagram('d=10cm'),
      ),
      GeneratedExercise(
        id: 'e3',
        questionId: questionId,
        generationMode: ExerciseGenerationMode.practice,
        difficulty: '提高',
        question: r'一个圆的周长为 \(12\pi\) cm，求这个圆的面积。',
        options: const [
          r'A. \(24\pi\) cm²',
          r'B. \(36\pi\) cm²',
          r'C. \(48\pi\) cm²',
          r'D. \(144\pi\) cm²',
        ],
        answer: 'B',
        explanation: r'由 \(2\pi r=12\pi\) 得 \(r=6\)，面积为 \(\pi r^2=36\pi\) cm²。',
        createdAt: now,
        order: 2,
        diagramData: _circleDiagram('C=12π'),
      ),
    ];
  }

  List<GeneratedExercise> _defaultSemicircleAreaExercises(
    String questionId,
    DateTime now,
  ) {
    return <GeneratedExercise>[
      GeneratedExercise(
        id: 'e1',
        questionId: questionId,
        generationMode: ExerciseGenerationMode.practice,
        difficulty: '简单',
        question: r'一个半圆的半径为 4 cm，求这个半圆的面积。',
        options: const [
          r'A. \(4\pi\) cm²',
          r'B. \(8\pi\) cm²',
          r'C. \(16\pi\) cm²',
          r'D. \(32\pi\) cm²',
        ],
        answer: 'B',
        explanation: r'整圆面积为 \(16\pi\) cm²，半圆面积是一半，所以为 \(8\pi\) cm²。',
        createdAt: now,
        order: 0,
        diagramData: _semicircleDiagram('4cm'),
      ),
      GeneratedExercise(
        id: 'e2',
        questionId: questionId,
        generationMode: ExerciseGenerationMode.practice,
        difficulty: '同级',
        question: r'一个半圆的直径为 10 cm，求这个半圆的面积。',
        options: const [
          r'A. \(\frac{25\pi}{2}\) cm²',
          r'B. \(25\pi\) cm²',
          r'C. \(50\pi\) cm²',
          r'D. \(10\pi\) cm²',
        ],
        answer: 'A',
        explanation:
            r'直径为 10 cm，半径为 5 cm，半圆面积为 \(\frac{1}{2}\pi\times5^2=\frac{25\pi}{2}\) cm²。',
        createdAt: now,
        order: 1,
        diagramData: _semicircleDiagram('d=10cm'),
      ),
      GeneratedExercise(
        id: 'e3',
        questionId: questionId,
        generationMode: ExerciseGenerationMode.practice,
        difficulty: '提高',
        question: r'一个半圆的弧所在整圆周长为 \(16\pi\) cm，求这个半圆的面积。',
        options: const [
          r'A. \(16\pi\) cm²',
          r'B. \(24\pi\) cm²',
          r'C. \(32\pi\) cm²',
          r'D. \(64\pi\) cm²',
        ],
        answer: 'C',
        explanation:
            r'由 \(2\pi r=16\pi\) 得 \(r=8\)，半圆面积为 \(\frac{1}{2}\pi\times8^2=32\pi\) cm²。',
        createdAt: now,
        order: 2,
        diagramData: _semicircleDiagram('C=16π'),
      ),
    ];
  }

  List<GeneratedExercise> _defaultCompositeSemicircleAreaExercises(
    String questionId,
    DateTime now,
  ) {
    return <GeneratedExercise>[
      GeneratedExercise(
        id: 'e1',
        questionId: questionId,
        generationMode: ExerciseGenerationMode.practice,
        difficulty: '简单',
        question: r'如图，上边长为 2，下边长为 5，右边高为 4，半圆以左侧斜边为直径。求右侧外边界与半圆弧之间区域的面积。',
        options: const [
          r'A. \(14-\frac{25\pi}{8}\)',
          r'B. \(14-\frac{25\pi}{4}\)',
          r'C. \(20-\frac{25\pi}{8}\)',
          r'D. \(14-\frac{5\pi}{2}\)',
        ],
        answer: 'A',
        explanation:
            r'外边界面积为 \(\frac{2+5}{2}\times4=14\)。左侧斜边平方为 \((5-2)^2+4^2=25\)，所以半圆面积为 \(\frac{25\pi}{8}\)，目标面积为 \(14-\frac{25\pi}{8}\)。',
        createdAt: now,
        order: 0,
        diagramData: _framedSemicircleDiagram('2', '5', '4'),
      ),
      GeneratedExercise(
        id: 'e2',
        questionId: questionId,
        generationMode: ExerciseGenerationMode.practice,
        difficulty: '同级',
        question: r'如图，上边长为 3，下边长为 7，右边高为 10，半圆以左侧斜边为直径。求右侧外边界与半圆弧之间区域的面积。',
        options: const [
          r'A. \(50-29\pi\)',
          r'B. \(50-\frac{29\pi}{2}\)',
          r'C. \(40-\frac{29\pi}{2}\)',
          r'D. \(50-58\pi\)',
        ],
        answer: 'B',
        explanation:
            r'外边界面积为 \(\frac{3+7}{2}\times10=50\)。左侧斜边平方为 \((7-3)^2+10^2=116\)，半径平方为 29，半圆面积为 \(\frac{29\pi}{2}\)，目标面积为 \(50-\frac{29\pi}{2}\)。',
        createdAt: now,
        order: 1,
        diagramData: _framedSemicircleDiagram('3', '7', '10'),
      ),
      GeneratedExercise(
        id: 'e3',
        questionId: questionId,
        generationMode: ExerciseGenerationMode.practice,
        difficulty: '提高',
        question: r'如图，上边长为 4，下边长为 10，右边高为 8，半圆以左侧斜边为直径。求右侧外边界与半圆弧之间区域的面积。',
        options: const [
          r'A. \(56-50\pi\)',
          r'B. \(48-25\pi\)',
          r'C. \(56-25\pi\)',
          r'D. \(56-\frac{25\pi}{2}\)',
        ],
        answer: 'D',
        explanation:
            r'外边界面积为 \(\frac{4+10}{2}\times8=56\)。左侧斜边平方为 \((10-4)^2+8^2=100\)，半径平方为 25，半圆面积为 \(\frac{25\pi}{2}\)，目标面积为 \(56-\frac{25\pi}{2}\)。',
        createdAt: now,
        order: 2,
        diagramData: _framedSemicircleDiagram('4', '10', '8'),
      ),
    ];
  }

  List<GeneratedExercise> _defaultFramedSemicircleAreaExercises(
    String questionId,
    DateTime now,
    _FramedSemicircleSpec? sourceSpec,
  ) {
    final same = sourceSpec ??
        const _FramedSemicircleSpec(top: 3, bottom: 7, height: 10);
    final simple = _scaledFramedSemicircleSpec(same, difficulty: -1);
    final hard = _scaledFramedSemicircleSpec(same, difficulty: 1);
    return <GeneratedExercise>[
      _framedSemicircleExercise(
        id: 'e1',
        questionId: questionId,
        difficulty: '简单',
        spec: simple,
        createdAt: now,
        order: 0,
      ),
      _framedSemicircleExercise(
        id: 'e2',
        questionId: questionId,
        difficulty: '同级',
        spec: same,
        createdAt: now,
        order: 1,
      ),
      _framedSemicircleExercise(
        id: 'e3',
        questionId: questionId,
        difficulty: '提高',
        spec: hard,
        createdAt: now,
        order: 2,
      ),
    ];
  }

  _FramedSemicircleSpec _scaledFramedSemicircleSpec(
    _FramedSemicircleSpec source, {
    required int difficulty,
  }) {
    if (difficulty < 0) {
      final diff = math.max(3, source.horizontalDiff - 1);
      final height = math.max(4, source.height - 2);
      final top = math.max(2, source.top - 1);
      return _FramedSemicircleSpec(
        top: top,
        bottom: top + diff,
        height: height,
      );
    }
    final diff = source.horizontalDiff + 2;
    final height = source.height + 3;
    final top = source.top + 1;
    return _FramedSemicircleSpec(
      top: top,
      bottom: top + diff,
      height: height,
    );
  }

  GeneratedExercise _framedSemicircleExercise({
    required String id,
    required String questionId,
    required String difficulty,
    required _FramedSemicircleSpec spec,
    required DateTime createdAt,
    required int order,
  }) {
    final area = _formatPiOver8(spec.diameterSquared);
    final distractors = <String>[
      _formatPiOver8(spec.diameterSquared * 2),
      _formatPiOver8(math.max(1, spec.diameterSquared - 8)),
      '${spec.diameterSquared}π',
    ];
    return GeneratedExercise(
      id: id,
      questionId: questionId,
      generationMode: ExerciseGenerationMode.practice,
      difficulty: difficulty,
      question:
          '如图，上边长为 ${spec.top}，下边长为 ${spec.bottom}，右边高为 ${spec.height}，左侧斜边为半圆直径。求该半圆的面积。',
      options: <String>[
        'A. ${distractors[0]}',
        'B. $area',
        'C. ${distractors[1]}',
        'D. ${distractors[2]}',
      ],
      answer: 'B',
      explanation:
          '水平差为 ${spec.horizontalDiff}，高为 ${spec.height}，由勾股定理得直径平方为 ${spec.diameterSquared}，半圆面积为 $area。',
      createdAt: createdAt,
      order: order,
      diagramData: _framedSemicircleDiagram(
        spec.top.toString(),
        spec.bottom.toString(),
        spec.height.toString(),
        targetLabel: '求半圆面积',
      ),
    );
  }

  String _formatPiOver8(int numerator) {
    final divisor = _gcd(numerator, 8);
    final reducedNumerator = numerator ~/ divisor;
    final reducedDenominator = 8 ~/ divisor;
    if (reducedDenominator == 1) return '${reducedNumerator}π';
    return '${reducedNumerator}π/$reducedDenominator';
  }

  int _gcd(int a, int b) {
    var x = a.abs();
    var y = b.abs();
    while (y != 0) {
      final next = x % y;
      x = y;
      y = next;
    }
    return x == 0 ? 1 : x;
  }

  List<GeneratedExercise> _defaultAnnulusAreaExercises(
    String questionId,
    DateTime now,
  ) {
    return <GeneratedExercise>[
      GeneratedExercise(
        id: 'e1',
        questionId: questionId,
        generationMode: ExerciseGenerationMode.practice,
        difficulty: '简单',
        question: r'一个圆环的外圆半径为 5 cm，内圆半径为 3 cm，求圆环面积。',
        options: const [
          r'A. \(8\pi\) cm²',
          r'B. \(12\pi\) cm²',
          r'C. \(16\pi\) cm²',
          r'D. \(25\pi\) cm²',
        ],
        answer: 'C',
        explanation: r'圆环面积为大圆面积减小圆面积，\(25\pi-9\pi=16\pi\) cm²。',
        createdAt: now,
        order: 0,
        diagramData: _annulusDiagram('5cm', '3cm'),
      ),
      GeneratedExercise(
        id: 'e2',
        questionId: questionId,
        generationMode: ExerciseGenerationMode.practice,
        difficulty: '同级',
        question: r'一个圆形花坛半径为 6 m，中间挖去半径为 2 m 的圆形区域，剩余部分面积是多少？',
        options: const [
          r'A. \(24\pi\) m²',
          r'B. \(28\pi\) m²',
          r'C. \(32\pi\) m²',
          r'D. \(36\pi\) m²',
        ],
        answer: 'C',
        explanation: r'剩余面积为 \(36\pi-4\pi=32\pi\) m²。',
        createdAt: now,
        order: 1,
        diagramData: _annulusDiagram('6m', '2m'),
      ),
      GeneratedExercise(
        id: 'e3',
        questionId: questionId,
        generationMode: ExerciseGenerationMode.practice,
        difficulty: '提高',
        question: r'一个圆环的外圆直径为 14 cm，内圆直径为 10 cm，求圆环面积。',
        options: const [
          r'A. \(12\pi\) cm²',
          r'B. \(24\pi\) cm²',
          r'C. \(36\pi\) cm²',
          r'D. \(48\pi\) cm²',
        ],
        answer: 'B',
        explanation: r'外半径为 7 cm，内半径为 5 cm，圆环面积为 \(49\pi-25\pi=24\pi\) cm²。',
        createdAt: now,
        order: 2,
        diagramData: _annulusDiagram('d=14', 'd=10'),
      ),
    ];
  }

  List<GeneratedExercise> _defaultRightTriangleLengthExercises(
    String questionId,
    DateTime now,
  ) {
    return <GeneratedExercise>[
      GeneratedExercise(
        id: 'e1',
        questionId: questionId,
        generationMode: ExerciseGenerationMode.practice,
        difficulty: '简单',
        question: r'如图，直角三角形两条直角边分别为 6 和 8，求斜边的长度。',
        options: const ['A. 8', 'B. 9', 'C. 10', 'D. 12'],
        answer: 'C',
        explanation: r'由勾股定理，斜边 \(c=\sqrt{6^2+8^2}=10\)。',
        createdAt: now,
        order: 0,
        diagramData: _rightTriangleDiagram('6', '8', '?'),
      ),
      GeneratedExercise(
        id: 'e2',
        questionId: questionId,
        generationMode: ExerciseGenerationMode.practice,
        difficulty: '同级',
        question: r'如图，直角三角形的斜边为 13，一条直角边为 5，求另一条直角边的长度。',
        options: const ['A. 8', 'B. 10', 'C. 12', 'D. 14'],
        answer: 'C',
        explanation: r'设另一条直角边为 \(x\)，则 \(x^2+5^2=13^2\)，所以 \(x=12\)。',
        createdAt: now,
        order: 1,
        diagramData: _rightTriangleDiagram('5', '?', '13'),
      ),
      GeneratedExercise(
        id: 'e3',
        questionId: questionId,
        generationMode: ExerciseGenerationMode.practice,
        difficulty: '提高',
        question:
            r'如图，\(\angle ABC=90^\circ\)，点 \(D\) 在 \(AB\) 上，\(BD=BC\)，\(AD=7\)，\(AC=17\)，求 \(BC\) 的长度。',
        options: const ['A. 6', 'B. 8', 'C. 10', 'D. 12'],
        answer: 'B',
        explanation:
            r'设 \(BC=BD=x\)，则 \(AB=x+7\)。由勾股定理，\((x+7)^2+x^2=17^2\)，解得 \(x=8\)，所以 \(BC=8\)。',
        createdAt: now,
        order: 2,
        diagramData: _rightTriangleCompositeDiagram(),
      ),
    ];
  }

  Map<String, dynamic> _circleDiagram(String label) {
    return <String, dynamic>{
      'elements': [
        {
          'type': 'arc',
          'cx': 0.5,
          'cy': 0.5,
          'r': 0.35,
          'startAngle': 0,
          'sweepAngle': 360,
          'filled': false
        },
        {'type': 'point', 'x': 0.5, 'y': 0.5, 'label': 'O', 'role': 'label'},
        {
          'type': 'line',
          'x1': 0.5,
          'y1': 0.5,
          'x2': 0.85,
          'y2': 0.5,
          'style': 'solid',
          'role': 'known'
        },
        {'type': 'text', 'text': label, 'x': 0.68, 'y': 0.42, 'role': 'known'},
      ],
    };
  }

  Map<String, dynamic> _semicircleDiagram(String label) {
    return <String, dynamic>{
      'elements': [
        {
          'type': 'arc',
          'cx': 0.5,
          'cy': 0.6,
          'r': 0.3,
          'startAngle': 180,
          'sweepAngle': 180,
          'filled': true
        },
        {
          'type': 'line',
          'x1': 0.2,
          'y1': 0.6,
          'x2': 0.8,
          'y2': 0.6,
          'style': 'solid',
          'role': 'known'
        },
        {'type': 'text', 'text': label, 'x': 0.5, 'y': 0.68, 'role': 'known'},
        {'type': 'point', 'x': 0.5, 'y': 0.6, 'label': 'O', 'role': 'label'},
      ],
    };
  }

  Map<String, dynamic> _annulusDiagram(String outer, String inner) {
    return <String, dynamic>{
      'elements': [
        {
          'type': 'arc',
          'cx': 0.5,
          'cy': 0.5,
          'r': 0.4,
          'startAngle': 0,
          'sweepAngle': 360,
          'filled': false
        },
        {
          'type': 'arc',
          'cx': 0.5,
          'cy': 0.5,
          'r': 0.26,
          'startAngle': 0,
          'sweepAngle': 360,
          'filled': false
        },
        {
          'type': 'line',
          'x1': 0.5,
          'y1': 0.5,
          'x2': 0.9,
          'y2': 0.5,
          'style': 'solid',
          'role': 'known'
        },
        {
          'type': 'line',
          'x1': 0.5,
          'y1': 0.5,
          'x2': 0.76,
          'y2': 0.5,
          'style': 'dashed',
          'role': 'known'
        },
        {'type': 'text', 'text': outer, 'x': 0.73, 'y': 0.42, 'role': 'known'},
        {'type': 'text', 'text': inner, 'x': 0.61, 'y': 0.56, 'role': 'known'},
        {'type': 'point', 'x': 0.5, 'y': 0.5, 'label': 'O', 'role': 'label'},
      ],
    };
  }

  Map<String, dynamic> _compositeSemicircleDiagram(
    String top,
    String bottom,
    String height,
  ) {
    return _framedSemicircleDiagram(top, bottom, height);
  }

  Map<String, dynamic> _framedSemicircleDiagram(
    String top,
    String bottom,
    String height, {
    String targetLabel = '求此区域',
  }) {
    return <String, dynamic>{
      'elements': [
        {
          'type': 'polygon',
          'points': [
            [0.36, 0.16],
            [0.76, 0.16],
            [0.76, 0.86],
            [0.12, 0.86],
          ],
          'labels': [
            {'text': 'A', 'x': 0.35, 'y': 0.1},
            {'text': 'B', 'x': 0.79, 'y': 0.12},
            {'text': 'C', 'x': 0.79, 'y': 0.9},
            {'text': 'D', 'x': 0.09, 'y': 0.9},
          ],
        },
        {'type': 'text', 'text': top, 'x': 0.56, 'y': 0.1, 'role': 'known'},
        {'type': 'text', 'text': bottom, 'x': 0.44, 'y': 0.94, 'role': 'known'},
        {'type': 'text', 'text': height, 'x': 0.84, 'y': 0.5, 'role': 'known'},
        {
          'type': 'arc',
          'cx': 0.24,
          'cy': 0.51,
          'r': 0.38,
          'startAngle': -72,
          'sweepAngle': 180,
          'filled': false,
          'role': 'known',
        },
        {'type': 'text', 'text': '半圆', 'x': 0.48, 'y': 0.55, 'role': 'label'},
        {
          'type': 'text',
          'text': targetLabel,
          'x': 0.68,
          'y': 0.39,
          'role': 'target',
        },
        {'type': 'rightAngle', 'x': 0.76, 'y': 0.86},
      ],
      'auxiliaryLines': [
        {
          'type': 'line',
          'x1': 0.36,
          'y1': 0.16,
          'x2': 0.12,
          'y2': 0.86,
          'style': 'dashed',
          'role': 'auxiliary',
        },
      ],
    };
  }

  Map<String, dynamic> _rightTriangleDiagram(
    String legA,
    String legB,
    String hypotenuse,
  ) {
    return <String, dynamic>{
      'elements': [
        {
          'type': 'polygon',
          'points': [
            [0.2, 0.8],
            [0.2, 0.25],
            [0.78, 0.8],
          ],
          'labels': [
            {'text': 'A', 'x': 0.18, 'y': 0.86},
            {'text': 'B', 'x': 0.16, 'y': 0.2},
            {'text': 'C', 'x': 0.82, 'y': 0.86},
          ],
        },
        {'type': 'rightAngle', 'x': 0.2, 'y': 0.8},
        {'type': 'text', 'text': legA, 'x': 0.14, 'y': 0.52, 'role': 'known'},
        {'type': 'text', 'text': legB, 'x': 0.5, 'y': 0.86, 'role': 'known'},
        {
          'type': 'text',
          'text': hypotenuse,
          'x': 0.53,
          'y': 0.48,
          'role': 'target'
        },
      ],
    };
  }

  Map<String, dynamic> _rightTriangleCompositeDiagram() {
    return <String, dynamic>{
      'elements': [
        {
          'type': 'polygon',
          'points': [
            [0.2, 0.82],
            [0.2, 0.22],
            [0.78, 0.82],
          ],
          'labels': [
            {'text': 'A', 'x': 0.18, 'y': 0.16},
            {'text': 'B', 'x': 0.16, 'y': 0.88},
            {'text': 'C', 'x': 0.82, 'y': 0.88},
            {'text': 'D', 'x': 0.18, 'y': 0.56},
          ],
        },
        {'type': 'rightAngle', 'x': 0.2, 'y': 0.82},
        {'type': 'point', 'x': 0.2, 'y': 0.55, 'label': 'D', 'role': 'label'},
        {'type': 'text', 'text': 'AD=7', 'x': 0.1, 'y': 0.38, 'role': 'known'},
        {'type': 'text', 'text': 'BD=x', 'x': 0.1, 'y': 0.68, 'role': 'target'},
        {
          'type': 'text',
          'text': 'BC=x',
          'x': 0.49,
          'y': 0.88,
          'role': 'target'
        },
        {
          'type': 'text',
          'text': 'AC=17',
          'x': 0.55,
          'y': 0.48,
          'role': 'known'
        },
        {
          'type': 'tickMark',
          'x1': 0.2,
          'y1': 0.55,
          'x2': 0.2,
          'y2': 0.82,
          'ticks': 1
        },
        {
          'type': 'tickMark',
          'x1': 0.2,
          'y1': 0.82,
          'x2': 0.78,
          'y2': 0.82,
          'ticks': 1
        },
      ],
    };
  }

  List<GeneratedExercise> _defaultSquarePerpendicularBisectorLengthExercises(
    String questionId,
    DateTime now,
  ) {
    return <GeneratedExercise>[
      GeneratedExercise(
        id: 'e1',
        questionId: questionId,
        generationMode: ExerciseGenerationMode.practice,
        difficulty: '简单',
        question:
            r'如图，在边长为 \(4\) 的正方形 \(ABCD\) 中，点 \(E\) 是 \(BC\) 的中点，点 \(F\) 在 \(DC\) 上，且 \(F\) 在线段 \(AE\) 的垂直平分线上。求 \(DF\) 的长。',
        options: const [
          r'A. \(\frac{1}{2}\)',
          r'B. \(1\)',
          r'C. \(\frac{3}{2}\)',
          r'D. \(2\)',
        ],
        answer: 'A',
        explanation:
            r'设 \(B(0,0)\)，\(C(4,0)\)，\(D(4,4)\)，\(A(0,4)\)，则 \(E(2,0)\)，设 \(F(4,y)\)。由 \(FA=FE\)，得 \(4^2+(y-4)^2=2^2+y^2\)，解得 \(y=\frac{7}{2}\)，所以 \(DF=4-\frac{7}{2}=\frac{1}{2}\)。',
        createdAt: now,
        order: 0,
        diagramData: _squarePerpendicularBisectorDiagram('4', '求DF'),
      ),
      GeneratedExercise(
        id: 'e2',
        questionId: questionId,
        generationMode: ExerciseGenerationMode.practice,
        difficulty: '同级',
        question:
            r'如图，在边长为 \(8\) 的正方形 \(ABCD\) 中，点 \(E\) 是 \(BC\) 的中点，点 \(F\) 在 \(DC\) 上，直线 \(FH\) 垂直平分线段 \(AE\)。求 \(DF\) 的长。',
        options: const [
          r'A. \(\frac{1}{2}\)',
          r'B. \(1\)',
          r'C. \(2\)',
          r'D. \(4\)',
        ],
        answer: 'B',
        explanation:
            r'设 \(B(0,0)\)，\(C(8,0)\)，\(D(8,8)\)，\(A(0,8)\)，则 \(E(4,0)\)，设 \(F(8,y)\)。由 \(FA=FE\)，得 \(8^2+(y-8)^2=4^2+y^2\)，解得 \(y=7\)，所以 \(DF=8-7=1\)。',
        createdAt: now,
        order: 1,
        diagramData: _squarePerpendicularBisectorDiagram('8', '求DF'),
      ),
      GeneratedExercise(
        id: 'e3',
        questionId: questionId,
        generationMode: ExerciseGenerationMode.practice,
        difficulty: '提高',
        question:
            r'如图，在边长为 \(6\) 的正方形 \(ABCD\) 中，点 \(E\) 是 \(BC\) 的中点，点 \(F\) 在 \(DC\) 上，且 \(F\) 在线段 \(AE\) 的垂直平分线上。求 \(DF\) 的长。',
        options: const [
          r'A. \(\frac{1}{2}\)',
          r'B. \(\frac{2}{3}\)',
          r'C. \(\frac{3}{4}\)',
          r'D. \(\frac{5}{4}\)',
        ],
        answer: 'C',
        explanation:
            r'设 \(B(0,0)\)，\(C(6,0)\)，\(D(6,6)\)，\(A(0,6)\)，则 \(E(3,0)\)，设 \(F(6,y)\)。由 \(FA=FE\)，得 \(6^2+(y-6)^2=3^2+y^2\)，解得 \(y=\frac{21}{4}\)，所以 \(DF=6-\frac{21}{4}=\frac{3}{4}\)。',
        createdAt: now,
        order: 2,
        diagramData: _squarePerpendicularBisectorDiagram('6', '求DF'),
      ),
    ];
  }

  Map<String, dynamic> _squarePerpendicularBisectorDiagram(
    String side,
    String target,
  ) {
    return <String, dynamic>{
      'elements': [
        {
          'type': 'polygon',
          'points': [
            [0.2, 0.2],
            [0.2, 0.8],
            [0.8, 0.8],
            [0.8, 0.2],
          ],
          'labels': [
            {'text': 'A', 'x': 0.16, 'y': 0.18},
            {'text': 'B', 'x': 0.16, 'y': 0.84},
            {'text': 'C', 'x': 0.82, 'y': 0.84},
            {'text': 'D', 'x': 0.82, 'y': 0.18},
          ],
        },
        {'type': 'point', 'x': 0.5, 'y': 0.8, 'label': 'E', 'role': 'known'},
        {'type': 'point', 'x': 0.8, 'y': 0.275, 'label': 'F', 'role': 'target'},
        {
          'type': 'line',
          'x1': 0.2,
          'y1': 0.2,
          'x2': 0.5,
          'y2': 0.8,
          'style': 'solid',
          'role': 'known'
        },
        {
          'type': 'line',
          'x1': 0.35,
          'y1': 0.5,
          'x2': 0.8,
          'y2': 0.275,
          'style': 'solid',
          'role': 'known'
        },
        {'type': 'point', 'x': 0.35, 'y': 0.5, 'label': 'H', 'role': 'label'},
        {
          'type': 'text',
          'text': '边长$side',
          'x': 0.48,
          'y': 0.14,
          'role': 'known'
        },
        {
          'type': 'line',
          'x1': 0.8,
          'y1': 0.2,
          'x2': 0.8,
          'y2': 0.275,
          'style': 'solid',
          'role': 'target'
        },
        {
          'type': 'text',
          'text': target,
          'x': 0.86,
          'y': 0.24,
          'role': 'target'
        },
      ],
      'auxiliaryLines': [],
    };
  }

  List<GeneratedExercise> _defaultConeVolumeExercises(
    String questionId,
    DateTime now,
  ) {
    return <GeneratedExercise>[
      GeneratedExercise(
        id: 'e1',
        questionId: questionId,
        generationMode: ExerciseGenerationMode.practice,
        difficulty: '简单',
        question: r'圆锥底面半径为 \(r=2\)，高为 \(h=3\)，则体积 \(V\) 为',
        options: const [
          r'A. \(4\pi\)',
          r'B. \(8\pi\)',
          r'C. \(12\pi\)',
          r'D. \(6\pi\)',
        ],
        answer: 'A',
        explanation:
            r'\(V=\frac{1}{3}\pi r^2 h=\frac{1}{3}\pi \times 4 \times 3=4\pi\)',
        createdAt: now,
        order: 0,
      ),
      GeneratedExercise(
        id: 'e2',
        questionId: questionId,
        generationMode: ExerciseGenerationMode.practice,
        difficulty: '同级',
        question: r'圆锥底面半径为 \(r=3\)，高为 \(h=6\)，则体积 \(V\) 为',
        options: const [
          r'A. \(12\pi\)',
          r'B. \(18\pi\)',
          r'C. \(24\pi\)',
          r'D. \(54\pi\)',
        ],
        answer: 'B',
        explanation:
            r'\(V=\frac{1}{3}\pi r^2h=\frac{1}{3}\pi\times9\times6=18\pi\)。',
        createdAt: now,
        order: 1,
      ),
      GeneratedExercise(
        id: 'e3',
        questionId: questionId,
        generationMode: ExerciseGenerationMode.practice,
        difficulty: '提高',
        question: r'一个圆锥体积为 \(24\pi\)，底面半径为 \(r=3\)，求高 \(h\)。',
        options: const ['A. 6', 'B. 8', 'C. 10', 'D. 12'],
        answer: 'B',
        explanation:
            r'由 \(24\pi=\frac{1}{3}\pi\times9\times h=3\pi h\)，得 \(h=8\)。',
        createdAt: now,
        order: 2,
      ),
    ];
  }

  List<GeneratedExercise> _defaultCylinderVolumeExercises(
    String questionId,
    DateTime now,
  ) {
    return <GeneratedExercise>[
      GeneratedExercise(
        id: 'e1',
        questionId: questionId,
        generationMode: ExerciseGenerationMode.practice,
        difficulty: '简单',
        question: r'圆柱底面半径为 \(r=2\)，高为 \(h=5\)，则圆柱体积为',
        options: const [
          r'A. \(10\pi\)',
          r'B. \(20\pi\)',
          r'C. \(25\pi\)',
          r'D. \(40\pi\)',
        ],
        answer: 'B',
        explanation: r'圆柱体积 \(V=\pi r^2h=\pi\times4\times5=20\pi\)。',
        createdAt: now,
        order: 0,
      ),
      GeneratedExercise(
        id: 'e2',
        questionId: questionId,
        generationMode: ExerciseGenerationMode.practice,
        difficulty: '同级',
        question: r'圆柱底面直径为 6，高为 4，则圆柱体积为',
        options: const [
          r'A. \(24\pi\)',
          r'B. \(30\pi\)',
          r'C. \(36\pi\)',
          r'D. \(48\pi\)',
        ],
        answer: 'C',
        explanation: r'直径为 6，所以半径为 3，体积 \(V=\pi\times9\times4=36\pi\)。',
        createdAt: now,
        order: 1,
      ),
      GeneratedExercise(
        id: 'e3',
        questionId: questionId,
        generationMode: ExerciseGenerationMode.practice,
        difficulty: '提高',
        question: r'一个圆柱体积为 \(45\pi\)，底面半径为 3，求高。',
        options: const ['A. 3', 'B. 4', 'C. 5', 'D. 6'],
        answer: 'C',
        explanation: r'由 \(45\pi=\pi\times3^2\times h=9\pi h\)，得 \(h=5\)。',
        createdAt: now,
        order: 2,
      ),
    ];
  }

  List<GeneratedExercise> _defaultGeneratedExercises(
    String questionId, {
    AnalysisResult? analysis,
    String? sourceQuestionText,
  }) {
    final now = DateTime.now();
    final profile = _buildExerciseTopicProfile(
      sourceQuestionText: sourceQuestionText,
      analysis: analysis,
    );

    if (profile.domain == _ExerciseDomain.planeGeometryArea &&
        profile.object == _ExerciseObject.circleFamily) {
      if (profile.variant == _ExerciseVariant.compositeSemicircleArea) {
        return _defaultCompositeSemicircleAreaExercises(questionId, now);
      }
      if (profile.variant == _ExerciseVariant.semicircleArea) {
        if (_hasFramedSemicircleDiameterSignal(sourceQuestionText, analysis)) {
          return _defaultFramedSemicircleAreaExercises(
            questionId,
            now,
            _framedSemicircleSpecFromSource(sourceQuestionText, analysis),
          );
        }
        return _defaultSemicircleAreaExercises(questionId, now);
      }
      if (profile.variant == _ExerciseVariant.annulusOrShadedArea) {
        return _defaultAnnulusAreaExercises(questionId, now);
      }
      return _defaultCircleAreaExercises(questionId, now);
    }

    if (profile.domain == _ExerciseDomain.planeGeometryLength &&
        profile.object == _ExerciseObject.rightTriangle) {
      return _defaultRightTriangleLengthExercises(questionId, now);
    }

    if (profile.domain == _ExerciseDomain.planeGeometryLength &&
        profile.object == _ExerciseObject.square &&
        profile.variant == _ExerciseVariant.squarePerpendicularBisectorLength) {
      return _defaultSquarePerpendicularBisectorLengthExercises(
          questionId, now);
    }

    if (profile.domain == _ExerciseDomain.algebraEquation &&
        profile.object == _ExerciseObject.quadraticEquation) {
      return <GeneratedExercise>[
        GeneratedExercise(
          id: 'e1',
          questionId: questionId,
          generationMode: ExerciseGenerationMode.practice,
          difficulty: '简单',
          question: r'已知 \(x^2=9\)，求 \(x\) 的值。',
          options: const [
            r'A. \(x=3\)',
            r'B. \(x=-3\)',
            r'C. \(x=\pm 3\)',
            r'D. \(x=9\)',
          ],
          answer: 'C',
          explanation: r'一个数的平方等于 9，这个数可能是 3 或 -3，所以 \(x=\pm 3\)。',
          createdAt: now,
          order: 0,
        ),
        GeneratedExercise(
          id: 'e2',
          questionId: questionId,
          generationMode: ExerciseGenerationMode.practice,
          difficulty: '同级',
          question: r'已知 \(x^2+4=20\)，求 \(x\) 的值。',
          options: const [
            r'A. \(x=4\)',
            r'B. \(x=\pm 4\)',
            r'C. \(x=8\)',
            r'D. \(x=\pm 8\)',
          ],
          answer: 'B',
          explanation: r'两边同时减去 4，得 \(x^2=16\)，所以 \(x=\pm 4\)。',
          createdAt: now,
          order: 1,
        ),
        GeneratedExercise(
          id: 'e3',
          questionId: questionId,
          generationMode: ExerciseGenerationMode.practice,
          difficulty: '提高',
          question: r'已知 \((x-1)^2=25\)，求 \(x\) 的值。',
          options: const [
            r'A. \(x=6\) 或 \(x=-4\)',
            r'B. \(x=5\) 或 \(x=-5\)',
            r'C. \(x=4\) 或 \(x=-6\)',
            r'D. \(x=6\)',
          ],
          answer: 'A',
          explanation:
              r'由 \((x-1)^2=25\) 得 \(x-1=\pm 5\)，所以 \(x=6\) 或 \(x=-4\)。',
          createdAt: now,
          order: 2,
        ),
      ];
    }

    if (profile.domain == _ExerciseDomain.planeGeometryAngle &&
        profile.object == _ExerciseObject.triangle) {
      return <GeneratedExercise>[
        GeneratedExercise(
          id: 'e1',
          questionId: questionId,
          generationMode: ExerciseGenerationMode.practice,
          difficulty: '简单',
          question:
              r'在 \(\triangle ABC\) 中，若 \(\angle A=50^\circ\)，\(\angle B=60^\circ\)，则 \(\angle C\) 是多少？',
          options: const ['A. 60°', 'B. 70°', 'C. 80°', 'D. 90°'],
          answer: 'B',
          explanation:
              r'三角形内角和为 \(180^\circ\)，所以 \(\angle C=180^\circ-50^\circ-60^\circ=70^\circ\)。',
          createdAt: now,
          order: 0,
          diagramData: const <String, dynamic>{
            'elements': [
              {
                'type': 'polygon',
                'points': [
                  [0.5, 0.15],
                  [0.15, 0.85],
                  [0.85, 0.85]
                ],
                'labels': [
                  {'text': 'A', 'x': 0.5, 'y': 0.08},
                  {'text': 'B', 'x': 0.1, 'y': 0.92},
                  {'text': 'C', 'x': 0.9, 'y': 0.92}
                ]
              },
              {
                'type': 'angleArc',
                'vx': 0.5,
                'vy': 0.15,
                'startAngle': 55,
                'sweepAngle': 70,
                'r': 0.08,
                'label': '50°'
              },
              {
                'type': 'angleArc',
                'vx': 0.15,
                'vy': 0.85,
                'startAngle': -10,
                'sweepAngle': 45,
                'r': 0.08,
                'label': '60°'
              },
              {
                'type': 'angleArc',
                'vx': 0.85,
                'vy': 0.85,
                'startAngle': 135,
                'sweepAngle': 35,
                'r': 0.08,
                'label': '?'
              },
            ],
          },
        ),
        GeneratedExercise(
          id: 'e2',
          questionId: questionId,
          generationMode: ExerciseGenerationMode.practice,
          difficulty: '同级',
          question:
              r'在等腰 \(\triangle ABC\) 中，\(AB=AC\)，若 \(\angle A=36^\circ\)，则 \(\angle B\) 是多少？',
          options: const ['A. 36°', 'B. 54°', 'C. 72°', 'D. 108°'],
          answer: 'C',
          explanation:
              r'\(AB=AC\)，所以底角 \(\angle B=\angle C\)；两个底角和为 \(144^\circ\)，所以 \(\angle B=72^\circ\)。',
          createdAt: now,
          order: 1,
          diagramData: const <String, dynamic>{
            'elements': [
              {
                'type': 'polygon',
                'points': [
                  [0.5, 0.1],
                  [0.2, 0.85],
                  [0.8, 0.85]
                ],
                'labels': [
                  {'text': 'A', 'x': 0.5, 'y': 0.03},
                  {'text': 'B', 'x': 0.14, 'y': 0.92},
                  {'text': 'C', 'x': 0.86, 'y': 0.92}
                ]
              },
              {
                'type': 'tickMark',
                'x1': 0.5,
                'y1': 0.1,
                'x2': 0.2,
                'y2': 0.85,
                'ticks': 1
              },
              {
                'type': 'tickMark',
                'x1': 0.5,
                'y1': 0.1,
                'x2': 0.8,
                'y2': 0.85,
                'ticks': 1
              },
              {
                'type': 'angleArc',
                'vx': 0.5,
                'vy': 0.1,
                'startAngle': 60,
                'sweepAngle': 60,
                'r': 0.08,
                'label': '36°'
              },
            ],
          },
        ),
        GeneratedExercise(
          id: 'e3',
          questionId: questionId,
          generationMode: ExerciseGenerationMode.practice,
          difficulty: '提高',
          question:
              r'在 \(\triangle ABC\) 中，若 \(AB=AC\)，点 \(D\) 在 \(AB\) 的延长线上，且外角 \(\angle DAC=120^\circ\)，求 \(\angle B\)。',
          options: const ['A. 50°', 'B. 55°', 'C. 60°', 'D. 65°'],
          answer: 'C',
          explanation:
              r'因为 \(D\) 在 \(AB\) 的延长线上，所以 \(\angle A+\angle DAC=180^\circ\)，得 \(\angle A=60^\circ\)。又因为 \(AB=AC\)，所以 \(\angle B=\angle C\)，因此 \(\angle B=\frac{180^\circ-60^\circ}{2}=60^\circ\)。',
          createdAt: now,
          order: 2,
          diagramData: const <String, dynamic>{
            'elements': [
              {
                'type': 'polygon',
                'points': [
                  [0.5, 0.35],
                  [0.24, 0.8],
                  [0.76, 0.8]
                ],
                'labels': [
                  {'text': 'A', 'x': 0.5, 'y': 0.27},
                  {'text': 'B', 'x': 0.18, 'y': 0.86},
                  {'text': 'C', 'x': 0.82, 'y': 0.86}
                ]
              },
              {
                'type': 'line',
                'x1': 0.643,
                'y1': 0.103,
                'x2': 0.5,
                'y2': 0.35,
                'style': 'solid',
                'role': 'known'
              },
              {
                'type': 'point',
                'x': 0.643,
                'y': 0.103,
                'label': 'D',
                'role': 'label'
              },
              {
                'type': 'tickMark',
                'x1': 0.5,
                'y1': 0.35,
                'x2': 0.24,
                'y2': 0.8,
                'ticks': 1
              },
              {
                'type': 'tickMark',
                'x1': 0.5,
                'y1': 0.35,
                'x2': 0.76,
                'y2': 0.8,
                'ticks': 1
              },
              {
                'type': 'angleArc',
                'vx': 0.5,
                'vy': 0.35,
                'startAngle': -60,
                'sweepAngle': 120,
                'r': 0.09,
                'label': '120°',
                'role': 'external'
              },
              {
                'type': 'angleArc',
                'vx': 0.24,
                'vy': 0.8,
                'startAngle': -5,
                'sweepAngle': 60,
                'r': 0.08,
                'label': '?'
              },
            ],
          },
        ),
      ];
    }

    if (profile.domain == _ExerciseDomain.proportionalRelation) {
      return <GeneratedExercise>[
        GeneratedExercise(
          id: 'e1',
          questionId: questionId,
          generationMode: ExerciseGenerationMode.practice,
          difficulty: '简单',
          question: r'若 \(\frac{a}{b}=2\)，且 \(a+b=12\)，求 \(a\) 的值。',
          options: const ['A. 4', 'B. 6', 'C. 8', 'D. 10'],
          answer: 'C',
          explanation:
              r'由 \(\frac{a}{b}=2\) 得 \(a=2b\)，代入 \(a+b=12\) 得 \(3b=12\)，所以 \(b=4\)，\(a=8\)。',
          createdAt: now,
          order: 0,
        ),
        GeneratedExercise(
          id: 'e2',
          questionId: questionId,
          generationMode: ExerciseGenerationMode.practice,
          difficulty: '同级',
          question: r'若 \(m:n=3:2\)，且 \(m+n=25\)，求 \(m\) 的值。',
          options: const ['A. 10', 'B. 12', 'C. 15', 'D. 18'],
          answer: 'C',
          explanation:
              r'由 \(m:n=3:2\) 可设 \(m=3k\)，\(n=2k\)，代入 \(m+n=25\) 得 \(5k=25\)，所以 \(m=15\)。',
          createdAt: now,
          order: 1,
        ),
        GeneratedExercise(
          id: 'e3',
          questionId: questionId,
          generationMode: ExerciseGenerationMode.practice,
          difficulty: '提高',
          question: r'若 \(\frac{x}{y}=\frac{4}{3}\)，且 \(x-y=5\)，求 \(x\) 的值。',
          options: const ['A. 10', 'B. 15', 'C. 20', 'D. 25'],
          answer: 'C',
          explanation:
              r'由 \(\frac{x}{y}=\frac{4}{3}\) 可设 \(x=4k\)，\(y=3k\)，代入 \(x-y=5\) 得 \(k=5\)，所以 \(x=20\)。',
          createdAt: now,
          order: 2,
        ),
      ];
    }

    if (profile.domain == _ExerciseDomain.equationSystem) {
      return <GeneratedExercise>[
        GeneratedExercise(
          id: 'e1',
          questionId: questionId,
          generationMode: ExerciseGenerationMode.practice,
          difficulty: '简单',
          question: r'解方程组：\\begin{cases} x+y=7 \\ x-y=1 \\end{cases}，x 的值是多少？',
          options: const ['A. 2', 'B. 3', 'C. 4', 'D. 5'],
          answer: 'C',
          explanation: r'两式相加得 2x=8，所以 x=4。',
          createdAt: now,
          order: 0,
        ),
        GeneratedExercise(
          id: 'e2',
          questionId: questionId,
          generationMode: ExerciseGenerationMode.practice,
          difficulty: '同级',
          question:
              r'解方程组：\\begin{cases} 2x+y=8 \\ x+y=5 \\end{cases}，y 的值是多少？',
          options: const ['A. 1', 'B. 2', 'C. 3', 'D. 4'],
          answer: 'B',
          explanation: r'两式相减得 x=3，代入 x+y=5 得 y=2。',
          createdAt: now,
          order: 1,
        ),
        GeneratedExercise(
          id: 'e3',
          questionId: questionId,
          generationMode: ExerciseGenerationMode.practice,
          difficulty: '提高',
          question:
              r'解方程组：\\begin{cases} x+2y=11 \\ 3x-y=4 \\end{cases}，x+y 的值是多少？',
          options: const ['A. 6', 'B. 7', 'C. 8', 'D. 9'],
          answer: 'C',
          explanation: r'由 3x-y=4 得 y=3x-4，代入 x+2y=11 得 x=3，y=5，所以 x+y=8。',
          createdAt: now,
          order: 2,
        ),
      ];
    }

    if (profile.domain == _ExerciseDomain.solidGeometryVolume) {
      if (profile.variant == _ExerciseVariant.cylinderVolume) {
        return _defaultCylinderVolumeExercises(questionId, now);
      }
      return _defaultConeVolumeExercises(questionId, now);
    }

    if (profile.domain == _ExerciseDomain.functionEvaluation) {
      return <GeneratedExercise>[
        GeneratedExercise(
          id: 'e1',
          questionId: questionId,
          generationMode: ExerciseGenerationMode.practice,
          difficulty: '简单',
          question: r'已知函数 \(f(x)=2x+1\)，求 \(f(3)\) 的值。',
          options: const ['A. 5', 'B. 6', 'C. 7', 'D. 8'],
          answer: 'C',
          explanation: r'把 \(x=3\) 代入，得 \(f(3)=2\times3+1=7\)。',
          createdAt: now,
          order: 0,
        ),
        GeneratedExercise(
          id: 'e2',
          questionId: questionId,
          generationMode: ExerciseGenerationMode.practice,
          difficulty: '同级',
          question: r'已知函数 \(g(x)=x^2-2x\)，求 \(g(4)\) 的值。',
          options: const ['A. 6', 'B. 8', 'C. 10', 'D. 12'],
          answer: 'B',
          explanation: r'把 \(x=4\) 代入，得 \(g(4)=4^2-2\times4=16-8=8\)。',
          createdAt: now,
          order: 1,
        ),
        GeneratedExercise(
          id: 'e3',
          questionId: questionId,
          generationMode: ExerciseGenerationMode.practice,
          difficulty: '提高',
          question: r'已知函数 \(h(x)=-x^2+3x+2\)，求 \(h(2)\) 的值。',
          options: const ['A. 2', 'B. 4', 'C. 6', 'D. 8'],
          answer: 'B',
          explanation: r'把 \(x=2\) 代入，得 \(h(2)=-4+6+2=4\)。',
          createdAt: now,
          order: 2,
        ),
      ];
    }

    return <GeneratedExercise>[
      GeneratedExercise(
        id: 'e1',
        questionId: questionId,
        generationMode: ExerciseGenerationMode.practice,
        difficulty: '简单',
        question: 'x+1=4，求 x 的值',
        options: const ['A. 2', 'B. 3', 'C. 4', 'D. 5'],
        answer: 'B',
        explanation: '移项得 x=4-1=3',
        createdAt: now,
        order: 0,
      ),
      GeneratedExercise(
        id: 'e2',
        questionId: questionId,
        generationMode: ExerciseGenerationMode.practice,
        difficulty: '同级',
        question: '2x=8，求 x 的值',
        options: const ['A. 2', 'B. 3', 'C. 4', 'D. 6'],
        answer: 'C',
        explanation: '两边同时除以 2 得 x=4',
        createdAt: now,
        order: 1,
      ),
      GeneratedExercise(
        id: 'e3',
        questionId: questionId,
        generationMode: ExerciseGenerationMode.practice,
        difficulty: '提高',
        question: '3x+2=11，求 x 的值',
        options: const ['A. 2', 'B. 3', 'C. 4', 'D. 5'],
        answer: 'B',
        explanation: '先减 2 再除以 3: 3x=9, x=3',
        createdAt: now,
        order: 2,
      ),
    ];
  }

  AnalysisResult _fakeResult() {
    return const AnalysisResult(
      subject: Subject.math,
      finalAnswer: 'x = 3',
      steps: <String>['移项得到 x = 5 - 2', '计算得到 x = 3'],
      aiTags: <String>['一元一次方程', '移项', '方程'],
      knowledgePoints: <String>['一元一次方程的基本概念', '移项规则：将项从等式一边移到另一边时需要变号'],
      mistakeReason: '对移项规则不熟悉',
      studyAdvice: '先用简单方程练熟移项，再做文字题。',
    );
  }
}

class _ConsistencyCheck {
  const _ConsistencyCheck({
    required this.isSuspicious,
    required this.isUnverifiable,
    required this.note,
    this.forceManualReview = false,
  });

  final bool isSuspicious;
  final bool isUnverifiable;
  final String note;
  final bool forceManualReview;
}

class _ConsistencyVerification {
  const _ConsistencyVerification({
    required this.isConsistent,
    required this.correctFinalAnswer,
    required this.correctedFinalAnswerDerivation,
    required this.correctedSteps,
    required this.correctedMistakeReason,
    required this.confidence,
    required this.needsManualReview,
    required this.reason,
  });

  final bool isConsistent;
  final String correctFinalAnswer;
  final String correctedFinalAnswerDerivation;
  final List<String> correctedSteps;
  final String correctedMistakeReason;
  final String confidence;
  final bool needsManualReview;
  final String reason;
}

class TestAiAnalysisService extends AiAnalysisService {
  TestAiAnalysisService({
    required super.settingsRepository,
    required this.extractionResult,
    required this.analysisResultValue,
    this.candidateAnalysisResults,
  });

  final AiQuestionExtractionResult extractionResult;
  final AnalysisResult analysisResultValue;
  final List<AnalysisResult>? candidateAnalysisResults;
  int extractionCallCount = 0;
  int analysisCallCount = 0;
  int analysisImageCallCount = 0;
  String? lastStudentAnswer;

  @override
  Future<AiQuestionExtractionResult> extractQuestionStructure({
    required String subjectName,
    required String imagePath,
    String textHint = '',
    CaptureMode mode = CaptureMode.printed,
  }) async {
    extractionCallCount++;
    return extractionResult;
  }

  @override
  Future<AnalysisResult> analyzeExtractedQuestion({
    required String correctedText,
    required String subjectName,
    String? imagePath,
    String studentAnswer = '',
  }) async {
    analysisCallCount++;
    lastStudentAnswer = studentAnswer;
    if (imagePath != null) analysisImageCallCount++;
    if (candidateAnalysisResults != null &&
        analysisCallCount <= candidateAnalysisResults!.length) {
      return candidateAnalysisResults![analysisCallCount - 1];
    }
    return analysisResultValue;
  }
}

class AiAnalysisException implements Exception {
  AiAnalysisException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// 标记 AI 响应 JSON 解析失败（含本地修复失败）。
/// 上层 [_requestWithJsonRetry] 捕获此异常后重试一次 AI 请求。
class _AiJsonParseException implements Exception {
  _AiJsonParseException(this.inner);
  final Object inner;
  @override
  String toString() => 'AI JSON parse failed: $inner';
}

/// 把底层异常翻译成用户可读的中文文案。UI 层应优先调用本函数，而不是
/// 直接 `e.toString()`，避免暴露技术栈。
String friendlyAiErrorMessage(Object error) {
  if (error is AiAnalysisException) {
    final message = error.message;
    // 解析 AI 响应失败 -> 走"内容格式异常"语义。
    if (message.startsWith('解析 AI 响应失败')) {
      return 'AI 返回内容格式异常，请重试或换一张更清晰的图片';
    }
    // 已经是友好文案，直接返回。
    return message;
  }
  if (error is DioException) {
    final status = error.response?.statusCode;
    if (status == 401 || status == 403) {
      return 'AI 服务未授权，请检查 API Key 设置';
    }
    if (status == 429) {
      return 'AI 服务繁忙，请稍后重试';
    }
    if (status != null && status >= 500 && status < 600) {
      return 'AI 服务暂时不可用，请稍后重试';
    }
    if (error.type == DioExceptionType.connectionTimeout ||
        error.type == DioExceptionType.receiveTimeout ||
        error.type == DioExceptionType.sendTimeout) {
      return '网络较慢，建议切换网络后重试';
    }
    if (error.type == DioExceptionType.connectionError) {
      return '网络连接失败，请检查网络';
    }
    return 'AI 服务请求失败，请稍后重试';
  }
  if (error is FormatException) {
    return 'AI 返回内容不完整，请重试';
  }
  return 'AI 分析失败，请重试';
}
