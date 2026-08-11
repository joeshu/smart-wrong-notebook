import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';

/// PDF 转图片服务。把指定 PDF 的每页渲染为 PNG 文件，输出文件路径列表。
///
/// 复用 printing 包的 [Printing.raster]：传入 PDF 字节流即可，每页得到
/// [PdfRaster]，再调用 [PdfRaster.toPng] 得到 PNG 字节，写入临时文件。
/// 后续调用方（如 [CaptureService.pickPdfFromGallery]）会把临时文件
/// 经由 [ImageStorageService] 持久化到应用目录，因此这里不需要保证
/// 文件长期有效，临时目录已足够。
class PdfToImagesService {
  /// 把 [pdfPath] 指定的 PDF 转为图片文件列表。
  ///
  /// [maxPages] 限制最多渲染多少页（默认 50，避免超大 PDF 拖垮内存）。
  /// [dpi] 渲染 DPI（默认 150，适合 OCR）。
  /// 返回每页对应的临时 PNG 文件路径列表（按页码顺序，跳过渲染失败的页）。
  ///
  /// 抛出 [FileSystemException] 当文件不存在或为空；其它渲染错误由
  /// 调用方处理。
  Future<List<String>> convertPdfToImages(
    String pdfPath, {
    int maxPages = 50,
    double dpi = 150,
  }) async {
    final file = File(pdfPath);
    if (!await file.exists()) {
      throw FileSystemException('PDF file not found', pdfPath);
    }
    final Uint8List bytes = await file.readAsBytes();
    if (bytes.isEmpty) {
      throw const FileSystemException('PDF file is empty');
    }

    final tempDir = await getTemporaryDirectory();
    final stamp = DateTime.now().microsecondsSinceEpoch;
    final results = <String>[];
    var count = 0;
    await for (final raster in Printing.raster(bytes, dpi: dpi)) {
      if (count >= maxPages) break;
      try {
        final pngBytes = await raster.toPng();
        final path = '${tempDir.path}/pdf_${stamp}_page_${count + 1}.png';
        await File(path).writeAsBytes(pngBytes, flush: true);
        results.add(path);
        count++;
      } catch (e) {
        // 单页渲染失败不阻塞整本试卷导入；调用方按返回的页数处理。
        debugPrint('[PdfToImagesService] Failed to rasterize page '
            '${count + 1}: $e');
      }
    }
    return results;
  }
}
