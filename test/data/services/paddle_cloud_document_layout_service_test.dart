import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_wrong_notebook/src/data/services/paddle_cloud_document_layout_service.dart';
import 'package:smart_wrong_notebook/src/domain/models/layout_provider_config.dart';

/// 仅测试 PaddleOCR 服务的纯函数：错误分类、重试判定、JSONL 解析。
/// 不发任何真实网络请求；构造服务实例仅为了拿到带 `@visibleForTesting` 的方法。
void main() {
  late PaddleCloudDocumentLayoutService service;

  setUp(() {
    service = PaddleCloudDocumentLayoutService(
      const LayoutProviderConfig(type: LayoutProviderType.paddleCloud, apiKey: 'test-token'),
    );
  });

  group('classifyError', () {
    test('HTTP 状态码翻译成中文文案', () {
      expect(
        service.classifyError(httpStatus: 401),
        'Token 无效或已过期，请重新填写 AI Studio 访问令牌',
      );
      expect(
        service.classifyError(httpStatus: 403),
        'Token 无权限或已达到单日 3000 页配额，请次日再试或到 AI Studio 申请配额',
      );
      expect(
        service.classifyError(httpStatus: 413),
        '文件过大（>50MB），请压缩后再上传',
      );
      expect(
        service.classifyError(httpStatus: 422, rawMessage: 'model 缺失'),
        '请求参数错误：model 缺失',
      );
      expect(
        service.classifyError(httpStatus: 429),
        '请求频率过高，请稍后重试',
      );
      expect(
        service.classifyError(httpStatus: 500),
        'PaddleOCR 服务暂时不可用，请稍后重试或切换到 MinerU',
      );
      expect(
        service.classifyError(httpStatus: 502),
        'PaddleOCR 服务暂时不可用，请稍后重试或切换到 MinerU',
      );
      expect(
        service.classifyError(httpStatus: 504),
        'PaddleOCR 服务暂时不可用，请稍后重试或切换到 MinerU',
      );
      expect(
        service.classifyError(httpStatus: 503),
        '服务繁忙，请稍后重试',
      );
    });

    test('业务码翻译成中文文案', () {
      expect(service.classifyError(businessCode: 10010), '任务队列已满，请稍后重试');
      expect(service.classifyError(businessCode: 11002), '任务结果已过期，请重新提交');
      expect(service.classifyError(businessCode: 12001), '已达单日 3000 页配额，请次日再试');
      expect(service.classifyError(businessCode: 12002), '请求频率过高，请稍后重试');
    });

    test('业务码优先级高于 HTTP 状态码', () {
      // 同时给 401 和 12001 时，应当走业务码分支（配额超限）。
      expect(
        service.classifyError(httpStatus: 401, businessCode: 12001),
        '已达单日 3000 页配额，请次日再试',
      );
    });

    test('未知 HTTP 状态码 fallback 到 rawMessage', () {
      expect(
        service.classifyError(httpStatus: 418, rawMessage: 'I am a teapot'),
        'PaddleOCR 服务请求失败：I am a teapot',
      );
      expect(
        service.classifyError(rawMessage: '连接重置'),
        'PaddleOCR 服务请求失败：连接重置',
      );
      // 完全没有上下文时应给出未知错误兜底。
      expect(
        service.classifyError(),
        'PaddleOCR 服务请求失败：未知错误',
      );
    });

    test('业务码未匹配到映射表时也走 HTTP/rawMessage 路径', () {
      // 10005 不在映射表里，应回退到 HTTP 422 文案。
      expect(
        service.classifyError(httpStatus: 422, businessCode: 10005, rawMessage: '参数不合法'),
        '请求参数错误：参数不合法',
      );
    });
  });

  group('isRetryable', () {
    DioException err(DioExceptionType type, {int? status}) {
      return DioException(
        type: type,
        requestOptions: RequestOptions(path: '/x'),
        response: status == null
            ? null
            : Response<dynamic>(
                statusCode: status,
                requestOptions: RequestOptions(path: '/x'),
              ),
      );
    }

    test('超时与连接错误可重试', () {
      expect(service.isRetryable(err(DioExceptionType.connectionTimeout)), isTrue);
      expect(service.isRetryable(err(DioExceptionType.receiveTimeout)), isTrue);
      expect(service.isRetryable(err(DioExceptionType.connectionError)), isTrue);
    });

    test('5xx 网关错误可重试（502/503/504）', () {
      expect(service.isRetryable(err(DioExceptionType.badResponse, status: 502)), isTrue);
      expect(service.isRetryable(err(DioExceptionType.badResponse, status: 503)), isTrue);
      expect(service.isRetryable(err(DioExceptionType.badResponse, status: 504)), isTrue);
    });

    test('4xx 客户端错误与 500 不重试', () {
      expect(service.isRetryable(err(DioExceptionType.badResponse, status: 401)), isFalse);
      expect(service.isRetryable(err(DioExceptionType.badResponse, status: 403)), isFalse);
      expect(service.isRetryable(err(DioExceptionType.badResponse, status: 413)), isFalse);
      expect(service.isRetryable(err(DioExceptionType.badResponse, status: 422)), isFalse);
      expect(service.isRetryable(err(DioExceptionType.badResponse, status: 429)), isFalse);
      // 500 是服务端错误但不在重试白名单里（仅 502/503/504）。
      expect(service.isRetryable(err(DioExceptionType.badResponse, status: 500)), isFalse);
    });

    test('其它 DioException 类型不重试', () {
      expect(service.isRetryable(err(DioExceptionType.cancel)), isFalse);
      expect(service.isRetryable(err(DioExceptionType.sendTimeout)), isFalse);
      expect(service.isRetryable(err(DioExceptionType.badCertificate)), isFalse);
      expect(service.isRetryable(err(DioExceptionType.unknown)), isFalse);
    });
  });

  group('extractRegionsForTesting', () {
    test('按题号分组生成多个候选区域', () {
      // 构造两道题，bbox 直接使用归一化坐标（不带 pageWidth/pageHeight）。
      // 题号正则匹配 "1." / "2." 前缀。用 raw 字符串避免 LaTeX `$` 触发插值。
      const jsonl = r'''
{"text":"1. 计算 3+5=","bbox":[0.1,0.05,0.9,0.15]}
{"text":"解：3+5=8","bbox":[0.1,0.16,0.9,0.22]}
{"text":"2. 化简 $x^2-1$","bbox":[0.1,0.30,0.9,0.40]}
{"text":"解：$(x-1)(x+1)$","bbox":[0.1,0.41,0.9,0.47]}
''';
      final regions = service.extractRegionsForTesting(jsonl);
      expect(regions.length, 2);
      expect(regions[0].detectedNumber, '1');
      expect(regions[1].detectedNumber, '2');
      // 第一题应当包含两行文本（题干+解答）。
      expect(regions[0].recognizedText, contains('计算 3+5='));
      expect(regions[0].recognizedText, contains('解：3+5=8'));
      // 第二题包含公式标记，应识别为 latexMixed。
      expect(regions[1].contentFormatHint, 'latexMixed');
      // 题框按从上到下排序。
      expect(regions[0].normalizedRect.top < regions[1].normalizedRect.top, isTrue);
    });

    test('题号缺失时走兜底路径，仍返回块级候选框', () {
      const jsonl = r'''
{"text":"纯文字段落没有题号前缀","bbox":[0.1,0.1,0.9,0.3]}
{"text":"另一段文字","bbox":[0.1,0.4,0.9,0.6]}
''';
      final regions = service.extractRegionsForTesting(jsonl);
      // 兜底路径直接产出块级候选框，每块至少 0.10×0.06。
      expect(regions.length, 2);
      expect(regions.every((r) => r.normalizedRect.width >= .10), isTrue);
      expect(regions.every((r) => r.normalizedRect.height >= .06), isTrue);
      expect(regions.first.detectedNumber, isNull);
    });

    test('太小的块被过滤掉', () {
      // 0.05×0.05 的块低于 0.10×0.025 阈值，应被去重阶段过滤。
      const jsonl = r'''
{"text":"小到看不见","bbox":[0.1,0.1,0.15,0.15]}
{"text":"1. 正常题目","bbox":[0.1,0.1,0.9,0.3]}
''';
      final regions = service.extractRegionsForTesting(jsonl);
      expect(regions.length, 1);
      expect(regions.first.detectedNumber, '1');
    });

    test('格式损坏的 JSONL 行被跳过，其它行仍可用', () {
      const jsonl = r'''
not a json line
{"text":"1. 第一题","bbox":[0.1,0.1,0.9,0.3]}
{"text":"also broken
''';
      final regions = service.extractRegionsForTesting(jsonl);
      expect(regions.length, 1);
      expect(regions.first.detectedNumber, '1');
    });

    test('空字符串返回空列表', () {
      expect(service.extractRegionsForTesting(''), isEmpty);
    });

    test('服务端公式标签优先于文本启发式', () {
      const jsonl = r'''
{"text":"1. 求下式的值","bbox":[0.1,0.05,0.9,0.14],"label":"text"}
{"text":"x²+y²=r²","bbox":[0.1,0.15,0.9,0.24],"label":"interline_equation"}
''';
      final block = service.extractRegionsForTesting(jsonl).single.documentBlocks.last;
      expect(block.type.name, 'formula');
      expect(block.contentFormat.name, 'latex');
      expect(block.recognitionEngine.name, 'formulaRecognizer');
    });

    test('无文字图形块仍保留裁剪证据', () {
      const jsonl = r'''
{"text":"1. 如图求角 A","bbox":[0.1,0.05,0.9,0.14],"label":"text"}
{"text":"","bbox":[0.2,0.15,0.8,0.55],"label":"figure"}
''';
      final blocks = service.extractRegionsForTesting(jsonl).single.documentBlocks;
      final diagram = blocks.singleWhere((block) => block.type.name == 'diagram');
      expect(diagram.content, isEmpty);
      expect(diagram.sourceCropRef, startsWith('crop://page?'));
      expect(diagram.recognitionStatus.name, 'sourcePreserved');
    });
  });
}
