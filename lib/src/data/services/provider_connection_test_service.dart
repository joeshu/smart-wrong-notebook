import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:smart_wrong_notebook/src/domain/models/ai_provider_config.dart';
import 'package:smart_wrong_notebook/src/domain/models/layout_provider_config.dart';

class ConnectionTestResult {
  const ConnectionTestResult({
    required this.service,
    required this.ok,
    required this.title,
    required this.detail,
    required this.elapsed,
  });
  final String service;
  final bool ok;
  final String title;
  final String detail;
  final Duration elapsed;
}

/// Low-impact credential checks. These never upload worksheet images or create
/// analysis jobs; a full import remains the final end-to-end verification.
class ProviderConnectionTestService {
  static const _paddleJobs = 'https://paddleocr.aistudio-app.com/api/v2/ocr/jobs';
  static const _mineruBase = 'https://mineru.net/api/v4';

  Future<ConnectionTestResult> testPaddle(String token) async {
    if (token.trim().isEmpty) return _missingToken('PaddleOCR AI Studio');
    final watch = Stopwatch()..start();
    final dio = _dio(token);
    try {
      // A 1x1 PNG is submitted only to validate the actual PP-StructureV3
      // request contract; it contains no user worksheet data.
      const png = 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVQIHWP4z8DwHwAFgAI/ScL8+QAAAABJRU5ErkJggg==';
      final response = await dio.post<dynamic>(_paddleJobs, data: FormData.fromMap(<String, dynamic>{
        'file': MultipartFile.fromBytes(base64Decode(png), filename: 'connection-test.png'),
        'model': 'PP-StructureV3',
        'optionalPayload': jsonEncode(const <String, bool>{'useDocOrientationClassify': false, 'useDocUnwarping': false}),
      }));
      watch.stop();
      final data = response.data is Map ? (response.data as Map)['data'] : null;
      final jobId = data is Map ? data['jobId']?.toString() : null;
      if (response.statusCode != null && response.statusCode! >= 200 && response.statusCode! < 300 && jobId != null && jobId.isNotEmpty) {
        return ConnectionTestResult(service: 'PaddleOCR AI Studio', ok: true, title: '连接成功 · PP-StructureV3 可用', detail: 'Token 已验证，已成功提交无用户数据的最小测试任务。', elapsed: watch.elapsed);
      }
      return _responseFailure('PaddleOCR AI Studio', response.statusCode ?? 0, watch.elapsed);
    } on DioException catch (error) {
      watch.stop();
      return _networkFailure('PaddleOCR AI Studio', error, watch.elapsed);
    } finally { dio.close(); }
  }

  Future<ConnectionTestResult> testMineru(String token) async {
    if (token.trim().isEmpty) return _missingToken('MinerU VLM');
    final watch = Stopwatch()..start();
    final dio = _dio(token);
    try {
      // Creates a disposable upload URL but deliberately never uploads a file.
      final response = await dio.post<dynamic>('$_mineruBase/file-urls/batch', data: <String, dynamic>{
        'files': <Map<String, String>>[<String, String>{'name': 'connection-test.png', 'data_id': 'connection-test-${DateTime.now().microsecondsSinceEpoch}'}],
        'model_version': 'vlm', 'language': 'ch', 'enable_formula': true, 'enable_table': true,
      });
      watch.stop();
      final root = response.data is Map ? Map<String, dynamic>.from(response.data as Map) : null;
      final data = root?['data'];
      final batchId = data is Map ? data['batch_id']?.toString() : null;
      if (response.statusCode != null && response.statusCode! >= 200 && response.statusCode! < 300 && root?['code'] == 0 && batchId != null && batchId.isNotEmpty) {
        return ConnectionTestResult(service: 'MinerU VLM', ok: true, title: '连接成功 · VLM 可用', detail: 'Token 已验证，已成功创建最小测试上传任务（未上传用户试卷）。', elapsed: watch.elapsed);
      }
      return _responseFailure('MinerU VLM', response.statusCode ?? 0, watch.elapsed);
    } on DioException catch (error) {
      watch.stop();
      return _networkFailure('MinerU VLM', error, watch.elapsed);
    } finally { dio.close(); }
  }

  Future<ConnectionTestResult> testAi(AiProviderConfig? config) async {
    if (config == null || config.baseUrl.trim().isEmpty || config.apiKey.trim().isEmpty || config.model.trim().isEmpty) {
      return const ConnectionTestResult(service: 'AI 分析模型', ok: false, title: '未配置', detail: '请先填写 AI 服务地址、模型和 API Key。', elapsed: Duration.zero);
    }
    final base = config.baseUrl.trim().replaceFirst(RegExp(r'/+$'), '');
    final endpoint = base.endsWith('/v1') ? '$base/chat/completions' : '$base/v1/chat/completions';
    final watch = Stopwatch()..start();
    final dio = _dio(config.apiKey);
    try {
      final response = await dio.post<dynamic>(endpoint, data: <String, dynamic>{
        'model': config.model,
        'messages': <Map<String, String>>[<String, String>{'role': 'user', 'content': 'Reply only: OK'}],
        'max_tokens': 2,
        'temperature': 0,
      });
      watch.stop();
      final choices = response.data is Map ? (response.data as Map)['choices'] : null;
      if (response.statusCode != null && response.statusCode! >= 200 && response.statusCode! < 300 && choices is List && choices.isNotEmpty) {
        return ConnectionTestResult(service: 'AI 分析模型 · ${config.model}', ok: true, title: '连接成功 · 模型可用', detail: '已完成最小文本请求，题目解析将调用该模型。', elapsed: watch.elapsed);
      }
      return _responseFailure('AI 分析模型 · ${config.model}', response.statusCode ?? 0, watch.elapsed);
    } on DioException catch (error) {
      watch.stop();
      return _networkFailure('AI 分析模型 · ${config.model}', error, watch.elapsed);
    } finally { dio.close(); }
  }

  Dio _dio(String token) => Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 12), receiveTimeout: const Duration(seconds: 25),
    validateStatus: (status) => status != null && status < 500,
    headers: <String, String>{'Authorization': 'Bearer ${token.trim()}'},
  ));

  ConnectionTestResult _missingToken(String service) => ConnectionTestResult(service: service, ok: false, title: '未填写 Token', detail: '请填写 Token 后重新测试。', elapsed: Duration.zero);
  ConnectionTestResult _responseFailure(String service, int status, Duration elapsed) {
    final auth = status == 401 || status == 403;
    return ConnectionTestResult(service: service, ok: false, title: auth ? '授权失败 · HTTP $status' : '请求失败 · HTTP $status', detail: auth ? 'Token 无效、过期或没有该服务权限，请重新保存后再试。' : '服务已响应，但测试任务未被接受。请检查服务状态、模型/接口权限或稍后重试。', elapsed: elapsed);
  }
  ConnectionTestResult _networkFailure(String service, DioException error, Duration elapsed) => ConnectionTestResult(service: service, ok: false, title: '连接失败', detail: error.type == DioExceptionType.connectionTimeout || error.type == DioExceptionType.receiveTimeout ? '请求超时，请检查网络或服务状态。' : '网络不可达：${error.message ?? '请求失败'}', elapsed: elapsed);

}
