import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_wrong_notebook/src/data/services/pdf_to_images_service.dart';

/// [PdfToImagesService] 的轻量测试。
///
/// 真正的 rasterize 链路依赖 printing 包的 native 插件，单元测试环境
/// （CI、无模拟器）下不可用。这里只覆盖两个在调用 [Printing.raster]
/// 之前就会抛错的分支：
/// - PDF 文件不存在 → [FileSystemException]
/// - PDF 文件为空 → [FileSystemException]
/// 任意一个分支命中后，服务都不会再访问 `path_provider` 或
/// `Printing.raster`，因此不需要 mock 平台通道。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late PdfToImagesService service;
  late Directory tempDir;

  setUp(() {
    service = PdfToImagesService();
    tempDir = Directory.systemTemp.createTempSync('pdf_to_images_test_');
  });

  tearDown(() {
    if (tempDir.existsSync()) {
      tempDir.deleteSync(recursive: true);
    }
  });

  group('convertPdfToImages 错误分支', () {
    test('文件不存在时抛 FileSystemException', () async {
      final missingPath = '${tempDir.path}/missing_${DateTime.now().microsecondsSinceEpoch}.pdf';
      expect(
        service.convertPdfToImages(missingPath),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('文件为空时抛 FileSystemException', () async {
      final emptyPath = '${tempDir.path}/empty.pdf';
      await File(emptyPath).writeAsBytes(const <int>[], flush: true);
      expect(
        service.convertPdfToImages(emptyPath),
        throwsA(isA<FileSystemException>()),
      );
    });

    test('maxPages 参数为正整数时不影响错误分支（仍走文件存在检查）', () async {
      final missingPath = '${tempDir.path}/missing_maxpages.pdf';
      // 文件不存在时，maxPages 不应改变行为；调用应当先抛 FileSystemException
      expect(
        service.convertPdfToImages(missingPath, maxPages: 5),
        throwsA(isA<FileSystemException>()),
      );
    });
  });
}
