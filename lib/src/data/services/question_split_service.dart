import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:smart_wrong_notebook/src/data/remote/ai/ai_analysis_service.dart';
import 'package:smart_wrong_notebook/src/domain/models/ai_provider_config.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_split_result.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';
import 'package:smart_wrong_notebook/src/shared/utils/composite_worksheet_detector.dart';

class QuestionSplitService {
  const QuestionSplitService({this.aiAnalysisService});

  final AiAnalysisService? aiAnalysisService;

  Future<QuestionSplitResult> split(String text, {Subject? subject}) async {
    if (aiAnalysisService != null) {
      return aiAnalysisService!.splitQuestionCandidates(
        text: text,
        subjectName: subject?.name,
      );
    }
    return _splitLocally(text, subject: subject);
  }

  /// 方案5：本地正则切分 + AI 兜底语义分割。
  ///
  /// 1. 先调 [_splitLocally]（正则 + 段落切分）
  /// 2. 如果切出 0 段或 1 段，且输入文本长度 > 200 字，调用 AI 模型做语义分割
  /// 3. AI 返回切分点列表，转换为 [QuestionSplitCandidate] 列表
  /// 4. 如果 AI 也失败或仍只切出 1 段，fallback 返回整段为 1 题
  Future<QuestionSplitResult> splitWithAiFallback(String text,
      {Subject? subject}) async {
    final local = _splitLocally(text, subject: subject);
    final textLength = local.sourceText.length;
    final needsAiFallback =
        local.candidates.length <= 1 && textLength > 200;
    if (!needsAiFallback) {
      return local;
    }

    final aiResult = await _splitByAi(local.sourceText, subject: subject);
    // AI 切出 >=2 段才采用；否则 fallback 到本地结果（整段为 1 题）
    if (aiResult != null && aiResult.candidates.length >= 2) {
      return aiResult;
    }
    return local;
  }

  /// 调用 AI 模型对长文本做语义分割；失败时返回 null。
  Future<QuestionSplitResult?> _splitByAi(String text,
      {Subject? subject}) async {
    final service = aiAnalysisService;
    if (service == null) return null;
    try {
      final config = await service.settingsRepository.getAiProviderConfig();
      if (config == null ||
          config.baseUrl.isEmpty ||
          config.apiKey.isEmpty ||
          config.model.isEmpty) {
        return null;
      }
      final segments =
          await _requestAiSplit(config: config, text: text, subject: subject);
      if (segments == null || segments.isEmpty) return null;
      return QuestionSplitResult(
        sourceText: text,
        candidates:
            _buildCandidates(segments, QuestionSplitStrategy.fallback),
        strategy: QuestionSplitStrategy.fallback,
      );
    } catch (_) {
      // AI 分割任何异常都视为失败，交由上层 fallback
      return null;
    }
  }

  /// 通过 OpenAI 兼容的 chat completions 接口请求 AI 切分文本。
  Future<List<String>?> _requestAiSplit({
    required AiProviderConfig config,
    required String text,
    Subject? subject,
  }) async {
    final baseUrl = config.baseUrl.endsWith('/')
        ? config.baseUrl.substring(0, config.baseUrl.length - 1)
        : config.baseUrl;
    final dio = Dio(BaseOptions(
      baseUrl: baseUrl,
      headers: <String, String>{
        'Content-Type': 'application/json',
        if (config.apiKey.isNotEmpty)
          'Authorization': 'Bearer ${config.apiKey}',
      },
      connectTimeout: const Duration(seconds: 60),
      receiveTimeout: const Duration(seconds: 120),
    ));
    const systemPrompt = '你是一个题目分割助手。给定一段可能包含多道题目的文本，'
        '请识别每道独立题目的边界，按出现顺序返回 JSON：'
        '{"questions": ["题目1", "题目2", ...]}。只返回 JSON，不要额外解释。';
    final subjectHint = subject != null ? '（学科：${subject.label}）' : '';
    final userPrompt = '请将以下文本$subjectHint分割成独立题目，保留每道题的完整题干与子问，'
        '返回 JSON：{"questions": [...]}。\n\n文本：\n$text';
    try {
      final response = await dio.post<dynamic>(
        '/chat/completions',
        data: <String, dynamic>{
          'model': config.model,
          'messages': <Map<String, String>>[
            <String, String>{'role': 'system', 'content': systemPrompt},
            <String, String>{'role': 'user', 'content': userPrompt},
          ],
          'temperature': 0.2,
          'max_tokens': 2000,
        },
      );
      dynamic data = response.data;
      if (data is String) {
        data = jsonDecode(data);
      }
      final content = (data as Map<String, dynamic>)['choices'][0]['message']
          ['content'] as String;
      return _parseAiSplitResponse(content);
    } catch (_) {
      return null;
    }
  }

  /// 从 AI 返回的文本中解析 {"questions": [...]} JSON。
  List<String>? _parseAiSplitResponse(String content) {
    try {
      final trimmed = content.trim();
      final start = trimmed.indexOf('{');
      final end = trimmed.lastIndexOf('}');
      if (start < 0 || end <= start) return null;
      final jsonStr = trimmed.substring(start, end + 1);
      final decoded = jsonDecode(jsonStr) as Map<String, dynamic>;
      final rawQuestions = decoded['questions'];
      if (rawQuestions is! List) return null;
      final segments = <String>[];
      for (final item in rawQuestions) {
        if (item is String) {
          final trimmedItem = item.trim();
          if (trimmedItem.isNotEmpty) segments.add(trimmedItem);
        }
      }
      return segments;
    } catch (_) {
      return null;
    }
  }

  QuestionSplitResult _splitLocally(String text, {Subject? subject}) {
    final normalized = text.replaceAll('\r\n', '\n').trim();
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
        candidates: _buildCandidates(
            <String>[normalized], QuestionSplitStrategy.fallback),
        strategy: QuestionSplitStrategy.fallback,
      );
    }

    if (_isCompositeQuestionWithSubparts(normalized, subject: subject)) {
      return QuestionSplitResult(
        sourceText: normalized,
        candidates: _buildCandidates(
            <String>[normalized], QuestionSplitStrategy.fallback),
        strategy: QuestionSplitStrategy.fallback,
      );
    }

    final numberedSegments = _splitByNumberedQuestions(normalized);
    if (numberedSegments.length >= 2) {
      return QuestionSplitResult(
        sourceText: normalized,
        candidates:
            _buildCandidates(numberedSegments, QuestionSplitStrategy.numbered),
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
        candidates: _buildCandidates(
            paragraphSegments, QuestionSplitStrategy.paragraph),
        strategy: QuestionSplitStrategy.paragraph,
      );
    }

    return QuestionSplitResult(
      sourceText: normalized,
      candidates: _buildCandidates(
          <String>[normalized], QuestionSplitStrategy.fallback),
      strategy: QuestionSplitStrategy.fallback,
    );
  }

  List<QuestionSplitCandidate> _buildCandidates(
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
    final hasGenericStem = <String>[
      '如图',
      '根据下列',
      '结合材料',
      '已知',
      '条件',
      '回答下列问题',
      '完成下列问题',
    ].any(lower.contains);
    final hasMathPhysicsStem = <String>[
      '电路',
      '装置',
      '实验',
      '函数图像',
      '坐标系',
      '正方形',
      '矩形',
      '三角形',
      '圆',
    ].any(lower.contains);
    final hasChemistryStem = <String>[
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
    ].any(lower.contains);
    final hasChemistryContext = <String>[
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
    ].any(lower.contains);
    if (subject == Subject.chemistry) {
      return hasGenericStem || hasChemistryStem || hasChemistryContext;
    }
    if (subject == Subject.math || subject == Subject.physics) {
      return hasGenericStem || hasMathPhysicsStem;
    }
    return hasGenericStem || hasMathPhysicsStem || hasChemistryStem;
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
}
