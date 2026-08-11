import 'dart:io';
import 'dart:ui';

import 'package:dio/dio.dart';
import 'package:smart_wrong_notebook/src/domain/models/layout_provider_config.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_region.dart';
import 'package:smart_wrong_notebook/src/domain/services/document_layout_service.dart';

/// Adapter for NAS Docker, MinerU gateways, or any endpoint implementing the
/// documented POST /v1/layout/question-regions multipart JSON contract.
class CustomHttpDocumentLayoutService implements DocumentLayoutService {
  CustomHttpDocumentLayoutService(this.config);
  final LayoutProviderConfig config;

  @override
  Future<LayoutDetectionResult> detectQuestionRegions({required String imagePath, String? pageRanges, LayoutStageCallback? onStage}) async {
    // Phase 10-2：自定义 HTTP 服务通常单次请求返回结果；单步阶段。
    // 自定义 HTTP 服务接口契约未定义 pageRanges；显式忽略以匹配接口契约。
    onStage?.call(current: 0, total: 1, label: '调用版面服务');
    if (config.baseUrl.trim().isEmpty) throw StateError('请先配置版面服务地址');
    final dio = Dio(BaseOptions(
      baseUrl: config.baseUrl.replaceFirst(RegExp(r'/$'), ''),
      connectTimeout: const Duration(seconds: 30),
      receiveTimeout: const Duration(seconds: 120),
      headers: config.apiKey.isEmpty ? null : {'Authorization': 'Bearer ${config.apiKey}'},
    ));
    final response = await dio.post('/v1/layout/question-regions', data: FormData.fromMap({
      'file': await MultipartFile.fromFile(imagePath, filename: File(imagePath).uri.pathSegments.last),
    }));
    final json = response.data is String ? null : response.data as Map<String, dynamic>?;
    if (json == null) throw StateError('版面服务未返回 JSON');
    final regions = <QuestionRegion>[];
    for (var i = 0; i < ((json['regions'] as List?) ?? const []).length; i++) {
      final item = (json['regions'] as List)[i] as Map;
      double? number(dynamic v) => v is num ? v.toDouble() : double.tryParse('$v');
      final x = number(item['x']); final y = number(item['y']);
      final w = number(item['width']); final h = number(item['height']);
      if (x == null || y == null || w == null || h == null) continue;
      final left = x.clamp(0.0, 1.0).toDouble(); final top = y.clamp(0.0, 1.0).toDouble();
      final width = w.clamp(0.0, 1 - left).toDouble(); final height = h.clamp(0.0, 1 - top).toDouble();
      if (width < .10 || height < .06) continue;
      regions.add(QuestionRegion(
        id: 'remote-$i-${DateTime.now().microsecondsSinceEpoch}',
        normalizedRect: Rect.fromLTWH(left, top, width, height),
        detectedNumber: item['number']?.toString(),
        confidence: (number(item['confidence']) ?? .5).clamp(0.0, 1.0).toDouble(),
        source: QuestionRegionSource.layoutModel,
      ));
    }
    if (regions.isEmpty) throw StateError('版面服务未返回有效题框');
    return LayoutDetectionResult(
      regions: regions,
      providerLabel: json['provider']?.toString() ?? '自定义版面服务',
      warning: json['warning']?.toString(),
    );
  }
}
