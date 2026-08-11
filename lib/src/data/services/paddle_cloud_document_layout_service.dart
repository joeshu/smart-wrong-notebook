import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:smart_wrong_notebook/src/domain/models/layout_provider_config.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_region.dart';
import 'package:smart_wrong_notebook/src/domain/services/document_layout_service.dart';
import 'package:smart_wrong_notebook/src/domain/services/specialized_recognition_router.dart';
import 'package:smart_wrong_notebook/src/shared/utils/question_number_detector.dart';

/// Adapter for PaddleOCR AI Studio's asynchronous PP-StructureV3 API.
/// The API key is supplied through [LayoutProviderConfig] and is stored only
/// in flutter_secure_storage by LayoutProviderRepository.
class PaddleCloudDocumentLayoutService implements DocumentLayoutService {
  PaddleCloudDocumentLayoutService(this.config);
  final LayoutProviderConfig config;

  static const _jobUrl = 'https://paddleocr.aistudio-app.com/api/v2/ocr/jobs';
  static const _specializedRouter = SpecializedRecognitionRouter();

  @override
  Future<LayoutDetectionResult> detectQuestionRegions({
    required String imagePath,
    String? pageRanges,
    LayoutStageCallback? onStage,
  }) async {
    // Phase 10-2：4 个阶段——提交任务 / 排队解析中 / 下载结果 / 提取题框。
    // total 写死 4，current 从 0 开始；失败路径不回调"完成"阶段。
    const totalStages = 4;
    if (config.apiKey.trim().isEmpty) {
      throw StateError('请先在“试卷版面识别”中填写 PaddleOCR AI Studio Token');
    }
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 90),
      // Authorization 规范为大写 Bearer（RFC 7235 大小写不敏感，但统一更规范）。
      headers: <String, String>{'Authorization': 'Bearer ${config.apiKey.trim()}'},
    ));
    try {
      onStage?.call(current: 0, total: totalStages, label: '提交任务');
      // P6a: pageRanges 作为顶层 multipart 字段下发（仅在调用方提供时附加）。
      final formData = <String, dynamic>{
        'file': await MultipartFile.fromFile(imagePath, filename: File(imagePath).uri.pathSegments.last),
        'model': 'PP-StructureV3',
        'optionalPayload': jsonEncode(const <String, bool>{
          'useDocOrientationClassify': false,
          'useDocUnwarping': false,
          'useChartRecognition': false,
        }),
      };
      if (pageRanges != null && pageRanges.isNotEmpty) {
        formData['pageRanges'] = pageRanges;
      }

      // P3: 提交任务带指数退避重试（1s/2s/4s，最多 3 次）。
      // 业务码 10010（队列已满）的检查必须放在 action 内部，才能触发 _retry 退避；
      // 其它非零业务码不可重试，直接抛 StateError 穿透 _retry 上报给调用方。
      final submit = await _retry<Response<dynamic>>(
        '提交任务',
        () async {
          final response = await dio.post<dynamic>(_jobUrl, data: FormData.fromMap(formData));
          final root = _map(response.data);
          final code = _int(root?['code']);
          if (root != null && code != null && code != 0) {
            final msg = root['msg']?.toString() ?? '';
            if (code == 10010) {
              throw _RetryableBusinessError(code, msg);
            }
            throw StateError(classifyError(businessCode: code, rawMessage: msg));
          }
          return response;
        },
      );
      final submittedRoot = _map(submit.data);
      final submittedData = _map(submittedRoot?['data']);
      final jobId = submittedData?['jobId']?.toString();
      if (jobId == null || jobId.isEmpty) throw StateError('PaddleOCR 未返回任务编号');

      onStage?.call(current: 1, total: totalStages, label: '排队解析中');
      // P1 + P4: 显式区分 4 态轮询；前 5 次 2s、第 6 次起 5s，最多 36 次。
      Map<String, dynamic>? job;
      // 记录上次上报的子进度文案，避免重复触发 setState。
      String? lastReportedDetail;
      var lastState = '';
      for (var attempt = 0; attempt < _maxPollAttempts; attempt++) {
        await Future<void>.delayed(Duration(seconds: attempt < _fastPollThreshold ? 2 : 5));
        final response = await dio.get<dynamic>('$_jobUrl/$jobId');
        job = _map(response.data)?['data'] is Map ? _map(_map(response.data)!['data']) : null;
        final state = job?['state']?.toString();
        if (state == 'done') break;
        if (state == 'failed') {
          throw StateError('PaddleOCR 识别失败：${job?['errorMsg'] ?? '未知错误'}');
        }
        // 状态切换时上报；running 时把 extractProgress 拼成 detail
        // 节流：只在 detail 文案变化时才回调。
        if (state != null && state != lastState) {
          lastState = state;
          if (state == 'running') {
            final progress = _map(job?['extractProgress']);
            final extracted = progress?['extractedPages']?.toString();
            final total = progress?['totalPages']?.toString();
            final detail = (extracted != null && total != null)
                ? '$extracted/$total 页'
                : (extracted != null ? '$extracted 页' : null);
            if (detail != null && detail != lastReportedDetail) {
              lastReportedDetail = detail;
              onStage?.call(
                current: 1,
                total: totalStages,
                label: '排队解析中',
                detail: detail,
              );
            }
          }
        }
      }
      if (job?['state'] != 'done') throw StateError('PaddleOCR 识别超时，请稍后重试');

      onStage?.call(current: 2, total: totalStages, label: '下载结果');
      // P6b: 优先 jsonUrl；为空时退回 markdownUrl 构造整页文本块兜底。
      final resultUrlMap = _map(job?['resultUrl']);
      final jsonUrl = resultUrlMap?['jsonUrl']?.toString();
      final markdownUrl = resultUrlMap?['markdownUrl']?.toString();
      final List<QuestionRegion> regions;
      if (jsonUrl != null && jsonUrl.isNotEmpty) {
        final result = await _retry<Response<String>>(
          '下载结果',
          () => dio.get<String>(jsonUrl, options: Options(responseType: ResponseType.plain)),
        );
        onStage?.call(current: 3, total: totalStages, label: '提取题框');
        regions = _extractRegions(result.data ?? '');
      } else if (markdownUrl != null && markdownUrl.isNotEmpty) {
        final result = await _retry<Response<String>>(
          '下载 Markdown 结果',
          () => dio.get<String>(markdownUrl, options: Options(responseType: ResponseType.plain)),
        );
        onStage?.call(current: 3, total: totalStages, label: '提取题框');
        regions = _regionsFromMarkdown(result.data ?? '');
      } else {
        throw StateError('PaddleOCR 未返回结果地址');
      }
      if (regions.isEmpty) throw StateError('PaddleOCR 未识别到可用题框；请改为手动框选');
      return LayoutDetectionResult(regions: regions, providerLabel: 'PaddleOCR PP-StructureV3', warning: '候选题框请在裁切前逐一确认。');
    } on DioException catch (error) {
      // P2: 把网络/HTTP 错误翻译成用户可读文案；保留原始响应体作为 rawMessage。
      final httpStatus = error.response?.statusCode;
      final rawBody = error.response?.data?.toString() ?? error.message ?? '网络请求失败';
      final businessCode = _extractBusinessCode(error.response?.data);
      throw StateError(classifyError(httpStatus: httpStatus, businessCode: businessCode, rawMessage: rawBody));
    } on _RetryableBusinessError catch (error) {
      // 重试耗尽后，把队列已满错误翻译成中文文案。
      throw StateError(classifyError(businessCode: error.code, rawMessage: error.message));
    } finally {
      dio.close();
    }
  }

  // P4: 前 5 次快速轮询（2s），第 6 次起 5s，最多 36 次（5×2 + 31×5 = 165s）。
  static const _fastPollThreshold = 5;
  static const _maxPollAttempts = 36;

  // P3: 对网络敏感操作（提交任务 / 下载结果）做指数退避重试。
  // 轮询查询（GET /jobs/{jobId}）不重试，因为已经在轮询循环里。
  Future<T> _retry<T>(String opLabel, Future<T> Function() action, {int maxRetries = 3}) async {
    var attempt = 0;
    var delay = const Duration(seconds: 1);
    while (true) {
      try {
        return await action();
      } on DioException catch (e) {
        attempt++;
        if (attempt >= maxRetries || !isRetryable(e)) rethrow;
        debugPrint('[PaddleOCR] $opLabel 第 $attempt 次重试（${e.type}/${e.response?.statusCode}），${delay.inSeconds}s 后再试');
        await Future<void>.delayed(delay);
        delay *= 2;
      } on _RetryableBusinessError catch (e) {
        attempt++;
        if (attempt >= maxRetries) rethrow;
        debugPrint('[PaddleOCR] $opLabel 第 $attempt 次重试（业务码 ${e.code}），${delay.inSeconds}s 后再试');
        await Future<void>.delayed(delay);
        delay *= 2;
      }
    }
  }

  @visibleForTesting
  bool isRetryable(DioException e) {
    if (e.type == DioExceptionType.connectionTimeout ||
        e.type == DioExceptionType.receiveTimeout ||
        e.type == DioExceptionType.connectionError) {
      return true;
    }
    final status = e.response?.statusCode ?? 0;
    return status == 502 || status == 503 || status == 504;
  }

  // P2: HTTP 状态码 + 业务 code → 用户可读中文文案。优先业务 code，其次 HTTP 状态。
  @visibleForTesting
  String classifyError({int? httpStatus, int? businessCode, String? rawMessage}) {
    if (businessCode != null) {
      switch (businessCode) {
        case 10010: return '任务队列已满，请稍后重试';
        case 11002: return '任务结果已过期，请重新提交';
        case 12001: return '已达单日 3000 页配额，请次日再试';
        case 12002: return '请求频率过高，请稍后重试';
      }
    }
    switch (httpStatus) {
      case 401: return 'Token 无效或已过期，请重新填写 AI Studio 访问令牌';
      case 403: return 'Token 无权限或已达到单日 3000 页配额，请次日再试或到 AI Studio 申请配额';
      case 413: return '文件过大（>50MB），请压缩后再上传';
      case 422: return '请求参数错误：${rawMessage ?? ''}';
      case 429: return '请求频率过高，请稍后重试';
      case 500:
      case 502:
      case 504: return 'PaddleOCR 服务暂时不可用，请稍后重试或切换到 MinerU';
      case 503: return '服务繁忙，请稍后重试';
    }
    return 'PaddleOCR 服务请求失败：${rawMessage ?? '未知错误'}';
  }

  int? _extractBusinessCode(dynamic data) {
    final map = _map(data);
    if (map == null) return null;
    return _int(map['code']);
  }

  int? _int(dynamic value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  // P6b 兜底：把 markdown 当成单个整页文本块，让 _fallbackBlockRegions 仍能产出候选框。
  List<QuestionRegion> _regionsFromMarkdown(String markdown) {
    final text = markdown.trim();
    if (text.isEmpty) return const <QuestionRegion>[];
    return _fallbackBlockRegions(<_PaddleBlock>[_PaddleBlock(const Rect.fromLTWH(0, 0, 1, 1), text, 'markdown')]);
  }

  @visibleForTesting
  List<QuestionRegion> extractRegionsForTesting(String jsonl) => _extractRegions(jsonl);

  /// 提取文本中所有 `$$...$$` 和 `$...$` 包裹的 LaTeX 公式片段。
  /// 排除 `\$` 转义的情况。返回的字符串保留定界符，便于下游区分行内/块级公式。
  List<String> _extractFormulas(String text) {
    final formulas = <String>[];
    // 先匹配 $$...$$（display），再匹配 $...$（inline）；用 (?<!\\) 排除 \$。
    final regex = RegExp(
      r'(?<!\\)\$\$([\s\S]*?)(?<!\\)\$\$|(?<!\\)\$([\s\S]*?)(?<!\\)\$',
    );
    for (final match in regex.allMatches(text)) {
      formulas.add(match.group(0)!);
    }
    return formulas;
  }

  List<QuestionRegion> _extractRegions(String jsonl) {
    final blocks = <_PaddleBlock>[];
    for (final line in const LineSplitter().convert(jsonl)) {
      try {
        _collectBlocks(jsonDecode(line), blocks, null);
      } catch (_) {
        // Skip malformed JSONL rows; other result rows remain usable.
      }
    }
    final unique = <String, _PaddleBlock>{};
    for (final block in blocks) {
      final rect = block.rect;
      if (rect.width >= .10 && rect.height >= .025) {
        unique['${rect.left.toStringAsFixed(3)},${rect.top.toStringAsFixed(3)},${rect.right.toStringAsFixed(3)},${rect.bottom.toStringAsFixed(3)}'] = block;
      }
    }
    final ordered = unique.values.toList()
      ..sort((a, b) {
        final row = (a.rect.top - b.rect.top).abs() < .015
            ? a.rect.left.compareTo(b.rect.left)
            : a.rect.top.compareTo(b.rect.top);
        return row;
      });
    final starts = <int>[];
    for (var index = 0; index < ordered.length; index++) {
      if (QuestionNumberDetector.instance.hasQuestionNumber(ordered[index].text)) starts.add(index);
    }
    if (starts.isEmpty) return _fallbackBlockRegions(ordered);

    final regions = <QuestionRegion>[];
    for (var group = 0; group < starts.length; group++) {
      final from = starts[group];
      final to = group + 1 < starts.length ? starts[group + 1] : ordered.length;
      final questionBlocks = ordered.sublist(from, to);
      final rect = questionBlocks.map((block) => block.rect).reduce((a, b) => a.expandToInclude(b));
      final text = questionBlocks.map((block) => block.text.trim()).where((text) => text.isNotEmpty).join('\n');
      if (rect.width < .10 || rect.height < .06) continue;
      final structuredBlocks = questionBlocks.map(_documentBlock).toList();
      regions.add(QuestionRegion(
        id: 'paddle-question-$group',
        normalizedRect: rect,
        detectedNumber: QuestionNumberDetector.instance.extractNumber(ordered[from].text),
        recognizedText: text.isEmpty ? null : text,
        formulas: _structuredContent(structuredBlocks, DocumentBlockType.formula),
        tables: _structuredContent(structuredBlocks, DocumentBlockType.table),
        documentBlocks: structuredBlocks,
        contentFormatHint: structuredBlocks.any((block) => block.type == DocumentBlockType.formula)
            ? 'latexMixed'
            : 'plain',
        recognizedBlockTypes: _classifyBlocks(text, structuredBlocks),
        confidence: .76,
        source: QuestionRegionSource.layoutModel,
      ));
    }
    return regions.isEmpty ? _fallbackBlockRegions(ordered) : regions;
  }

  DocumentBlock _documentBlock(_PaddleBlock block, {double confidence = .76}) {
    final type = _specializedRouter.classify(
      providerLabel: block.label,
      content: block.text,
    );
    return DocumentBlock(
      type: type,
      content: block.text.trim(),
      polygon: _rectPolygon(block.rect),
      authorRole: DocumentAuthorRole.unknown,
      confidence: confidence,
      riskCodes: _blockRisks(type, block.text, confidence),
      sourceCropRef: _cropRef(block.rect),
      contentFormat: _specializedRouter.formatFor(type),
      recognitionEngine: _specializedRouter.engineFor(type, precisionProvider: false),
      recognitionStatus: _specializedRouter.statusFor(type, block.text),
    );
  }

  List<Offset> _rectPolygon(Rect rect) => <Offset>[
    rect.topLeft,
    rect.topRight,
    rect.bottomRight,
    rect.bottomLeft,
  ];

  String _cropRef(Rect rect) => 'crop://page?left=${rect.left.toStringAsFixed(4)}'
      '&top=${rect.top.toStringAsFixed(4)}&right=${rect.right.toStringAsFixed(4)}'
      '&bottom=${rect.bottom.toStringAsFixed(4)}';

  Set<DocumentBlockRiskCode> _blockRisks(
    DocumentBlockType type,
    String text,
    double confidence,
  ) {
    final risks = <DocumentBlockRiskCode>{DocumentBlockRiskCode.roleUncertain};
    if (confidence < .6) risks.add(DocumentBlockRiskCode.lowConfidence);
    if (type == DocumentBlockType.formula && r'$'.allMatches(text).length.isOdd) {
      risks.add(DocumentBlockRiskCode.formulaIncomplete);
    }
    if (type == DocumentBlockType.table &&
        text.split('\n').where((line) => line.contains('|')).length < 2) {
      risks.add(DocumentBlockRiskCode.tableStructureInvalid);
    }
    return risks;
  }

  List<QuestionRegion> _fallbackBlockRegions(List<_PaddleBlock> blocks) => blocks
      .where((block) => block.rect.width >= .10 && block.rect.height >= .06)
      .take(30)
      .toList()
      .asMap()
      .entries
      .map((entry) {
        final block = _documentBlock(entry.value, confidence: .55);
        return QuestionRegion(
            id: 'paddle-block-${entry.key}',
            normalizedRect: entry.value.rect,
            recognizedText: entry.value.text.isEmpty ? null : entry.value.text,
            formulas: _structuredContent(<DocumentBlock>[block], DocumentBlockType.formula),
            tables: _structuredContent(<DocumentBlock>[block], DocumentBlockType.table),
            documentBlocks: <DocumentBlock>[block],
            contentFormatHint: block.type == DocumentBlockType.formula ? 'latexMixed' : 'plain',
            recognizedBlockTypes: _classifyBlocks(entry.value.text, <DocumentBlock>[block]),
            confidence: .55,
            source: QuestionRegionSource.layoutModel,
          );
      })
      .toList();

  List<String> _structuredContent(List<DocumentBlock> blocks, DocumentBlockType type) {
    final semantic = blocks
        .where((block) => block.type == type && block.content.trim().isNotEmpty)
        .map((block) => block.content.trim());
    if (type != DocumentBlockType.formula) return semantic.toSet().toList();
    return <String>{..._extractFormulas(blocks.map((block) => block.content).join('\n')), ...semantic}.toList();
  }

  List<String> _classifyBlocks(String text, List<DocumentBlock> blocks) {
    final types = _classifyText(text).toSet();
    const labels = <DocumentBlockType, String>{
      DocumentBlockType.handwriting: '手写',
      DocumentBlockType.formula: '公式',
      DocumentBlockType.table: '表格',
      DocumentBlockType.diagram: '图形',
      DocumentBlockType.image: '图片',
      DocumentBlockType.answerMark: '批改标记',
    };
    for (final block in blocks) {
      final label = labels[block.type];
      if (label != null) types.add(label);
    }
    return types.toList();
  }

  List<String> _classifyText(String text) {
    final types = <String>['文字'];
    if (text.contains(r'$') || text.contains(r'\\') || RegExp(r'[∑√∫≠≤≥]').hasMatch(text)) types.add('公式');
    if (text.contains('|') && text.split('\n').where((line) => line.contains('|')).length >= 2) types.add('表格');
    if (RegExp(r'(?:^|\n)\s*[A-DＡ-Ｄ][\.．、]').hasMatch(text)) types.add('选项');
    return types;
  }

  void _collectBlocks(dynamic value, List<_PaddleBlock> out, Size? inheritedSize) {
    if (value is Map) {
      final map = Map<String, dynamic>.from(value);
      final pageSize = _size(map) ?? inheritedSize;
      final label = (map['label'] ?? map['block_label'] ?? map['type'] ?? '').toString().toLowerCase();
      final box = _box(map['bbox'] ?? map['box'] ?? map['coordinate'] ?? map['poly']);
      final text = (map['text'] ?? map['content'] ?? map['text_content'] ?? '').toString().trim();
      final preservableVisual = _specializedRouter.classify(
        providerLabel: label,
        content: text,
      ) != DocumentBlockType.unknown;
      if (box != null && (text.isNotEmpty || preservableVisual) &&
          !label.contains('header') && !label.contains('footer')) {
        final raw = pageSize == null ? box : Rect.fromLTWH(box.left / pageSize.width, box.top / pageSize.height, box.width / pageSize.width, box.height / pageSize.height);
        final rect = Rect.fromLTRB(raw.left.clamp(0, 1).toDouble(), raw.top.clamp(0, 1).toDouble(), raw.right.clamp(0, 1).toDouble(), raw.bottom.clamp(0, 1).toDouble());
        if (!rect.isEmpty) out.add(_PaddleBlock(rect, text, label));
      }
      for (final child in map.values) {
        _collectBlocks(child, out, pageSize);
      }
    } else if (value is List) {
      for (final child in value) {
        _collectBlocks(child, out, inheritedSize);
      }
    }
  }

  Map<String, dynamic>? _map(dynamic value) => value is Map ? Map<String, dynamic>.from(value) : null;
  Size? _size(Map<String, dynamic> map) { final width = _number(map['pageWidth'] ?? map['width']); final height = _number(map['pageHeight'] ?? map['height']); return width != null && height != null && width > 1 && height > 1 ? Size(width, height) : null; }
  double? _number(dynamic value) => value is num ? value.toDouble() : double.tryParse('$value');
  Rect? _box(dynamic value) { if (value is! List || value.isEmpty) return null; final n = value.map(_number).toList(); if (n.length >= 4 && n.take(4).every((x) => x != null)) return Rect.fromLTRB(n[0]!, n[1]!, n[2]!, n[3]!); if (value.first is List) { final points = value.whereType<List>().map((p) => p.length >= 2 ? Offset(_number(p[0]) ?? 0, _number(p[1]) ?? 0) : null).whereType<Offset>().toList(); if (points.isNotEmpty) return Rect.fromPoints(Offset(points.map((p) => p.dx).reduce((a,b) => a < b ? a : b), points.map((p) => p.dy).reduce((a,b) => a < b ? a : b)), Offset(points.map((p) => p.dx).reduce((a,b) => a > b ? a : b), points.map((p) => p.dy).reduce((a,b) => a > b ? a : b))); } return null; }
}

class _PaddleBlock {
  const _PaddleBlock(this.rect, this.text, this.label);
  final Rect rect;
  final String text;
  final String label;
}

/// P3: 业务码 10010（队列已满）视为可重试错误，让 _retry 退避后重试提交。
class _RetryableBusinessError implements Exception {
  const _RetryableBusinessError(this.code, this.message);
  final int code;
  final String message;
  @override
  String toString() => '业务码 $code: $message';
}
