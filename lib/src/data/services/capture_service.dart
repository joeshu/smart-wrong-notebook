import 'dart:async';
import 'dart:io';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:image_picker/image_picker.dart';
import 'package:smart_wrong_notebook/src/data/files/image_storage_service.dart';
import 'package:smart_wrong_notebook/src/data/files/image_fingerprint.dart';
import 'package:smart_wrong_notebook/src/data/services/pdf_to_images_service.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';
import 'package:smart_wrong_notebook/src/shared/utils/image_preprocessor.dart';
import 'package:uuid/uuid.dart';

class CaptureResult {
  final QuestionRecord? record;
  final String? errorMessage;
  final bool isCancelled;

  CaptureResult.success(this.record)
      : errorMessage = null,
        isCancelled = false;

  CaptureResult.cancel()
      : record = null,
        errorMessage = null,
        isCancelled = true;

  CaptureResult.error(this.errorMessage)
      : record = null,
        isCancelled = false;
}

class CaptureService {
  CaptureService({ImageStorageService? storage})
      : _storage = storage ?? ImageStorageService();

  final ImageStorageService _storage;
  final ImagePicker _picker = ImagePicker();
  final PdfToImagesService _pdfService = PdfToImagesService();
  final Set<String> _discardedImagePaths = <String>{};

  /// Removes a managed capture and prevents an in-flight preprocessing task
  /// from recreating its derived image after cancellation.
  Future<void> discardManagedImage(String imagePath) async {
    _discardedImagePaths.add(imagePath);
    await _storage.deleteImage(imagePath);
  }

  Future<CaptureResult> pickFromCamera() async {
    try {
      debugPrint('[CaptureService] Opening camera...');
      final XFile? file = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 2560,
        maxHeight: 2560,
        imageQuality: 85,
      );
      debugPrint('[CaptureService] Camera result: ${file?.path ?? "cancelled"}');

      if (file == null) {
        return CaptureResult.cancel();
      }

      final record = await _saveToDraft(file);
      debugPrint('[CaptureService] Image saved: ${record.imagePath}');
      return CaptureResult.success(record);
    } catch (e) {
      debugPrint('[CaptureService] Camera error: $e');
      return CaptureResult.error(e.toString());
    }
  }

  Future<CaptureResult> pickFromGallery() async {
    try {
      debugPrint('[CaptureService] Opening gallery...');
      final XFile? file = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 2560,
        maxHeight: 2560,
        imageQuality: 85,
      );
      debugPrint('[CaptureService] Gallery result: ${file?.path ?? "cancelled"}');

      if (file == null) {
        return CaptureResult.cancel();
      }

      final record = await _saveToDraft(file);
      debugPrint('[CaptureService] Image saved: ${record.imagePath}');
      return CaptureResult.success(record);
    } catch (e) {
      debugPrint('[CaptureService] Gallery error: $e');
      return CaptureResult.error(e.toString());
    }
  }

  Future<List<QuestionRecord>> pickMultipleFromGallery() async {
    try {
      debugPrint('[CaptureService] Opening gallery for worksheet pages...');
      final files = await _picker.pickMultiImage(
        maxWidth: 2560,
        maxHeight: 2560,
        imageQuality: 85,
      );
      if (files.isEmpty) return const <QuestionRecord>[];

      final records = <QuestionRecord>[];
      for (final file in files) {
        records.add(await _saveToDraft(file));
      }
      debugPrint('[CaptureService] Saved ${records.length} worksheet pages');
      return records;
    } catch (e) {
      debugPrint('[CaptureService] Worksheet gallery error: $e');
      rethrow;
    }
  }

  /// 选择 PDF 文件并把每页转为图片草稿。
  ///
  /// 调用 [PdfToImagesService.convertPdfToImages] 把 PDF 渲染成临时 PNG，
  /// 再复用 [_saveToDraft] 把每页图片持久化到应用目录并生成 [QuestionRecord]，
  /// 流程与 [pickMultipleFromGallery] 一致：调用方拿到 records 后即可走
  /// `WorksheetImportSession` 多页切题流程。
  ///
  /// [maxPages] 限制最多渲染多少页，避免超大 PDF 拖垮内存（默认 50）。
  /// 返回空列表表示用户取消选择；其它错误抛出。
  Future<List<QuestionRecord>> pickPdfFromGallery({
    int maxPages = 50,
  }) async {
    try {
      debugPrint('[CaptureService] Opening file picker for PDF...');
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: const <String>['pdf'],
        withData: false,
      );
      if (result == null || result.files.isEmpty) {
        return const <QuestionRecord>[];
      }
      final pdfPath = result.files.first.path;
      if (pdfPath == null) {
        return const <QuestionRecord>[];
      }

      final imagePaths = await _pdfService.convertPdfToImages(
        pdfPath,
        maxPages: maxPages,
      );
      if (imagePaths.isEmpty) {
        return const <QuestionRecord>[];
      }

      final records = <QuestionRecord>[];
      for (final path in imagePaths) {
        try {
          records.add(await _saveToDraft(XFile(path)));
        } finally {
          // PDF pages are renderer-owned temporary files. _saveToDraft has
          // already copied them into managed storage, so retain no duplicate.
          final renderedPage = File(path);
          if (await renderedPage.exists()) await renderedPage.delete();
        }
      }
      debugPrint('[CaptureService] PDF imported ${records.length} pages');
      return records;
    } catch (e) {
      debugPrint('[CaptureService] PDF import error: $e');
      rethrow;
    }
  }

  Future<QuestionRecord> _saveToDraft(XFile file) async {
    // 1. 保存原图：UI 展示（CachedQuestionImage）与回退 OCR 都读这个路径。
    final savedPath = await _storage.saveImage(File(file.path));
    // 2. 生成预处理图（去噪 / 纠偏 / 二值化），保存到
    //    `<savedPath 去扩展名>_preprocessed.jpg`。AI / OCR 链路按命名约定
    //    优先读这个文件；失败时静默回退，AI 仍读 savedPath。
    // Do not hold the capture UI while CPU-heavy OCR preprocessing runs. The
    // analysis path already falls back to the original until this file exists.
    unawaited(_generatePreprocessedImage(savedPath));
    final savedFile = File(savedPath);
    final fingerprint = await ImageFingerprintCodec.fromFile(savedFile);
    final perceptual =
        await ImageFingerprintCodec.perceptualFromFile(savedFile);
    final tags = ImageFingerprintCodec.writePerceptual(
      ImageFingerprintCodec.write(const <String>[], fingerprint),
      perceptual,
    );
    return QuestionRecord.draft(
      id: const Uuid().v4(),
      imagePath: savedPath,
      subject: Subject.math,
      recognizedText: '',
    ).copyWith(tags: tags);
  }

  /// 在后台 isolate 对原图跑预处理管线，把结果写到
  /// `<savedPath 去扩展名>_preprocessed.jpg`。
  ///
  /// 命名约定：给定 `imagePath = xxx.jpg`，预处理图位于
  /// `xxx_preprocessed.jpg`。AI / OCR 链路据此查找预处理版本，
  /// 文件不存在时回退到 `imagePath` 原图。
  ///
  /// 任一步骤失败时静默跳过，调用方继续使用原图。
  Future<void> _generatePreprocessedImage(String originalPath) async {
    if (originalPath.isEmpty || _discardedImagePaths.contains(originalPath)) {
      return;
    }
    final original = File(originalPath);
    if (!original.existsSync()) return;
    try {
      final sourceBytes = await original.readAsBytes();
      if (sourceBytes.isEmpty) return;
      final processed = await preprocessForOcr(sourceBytes);
      if (processed.isEmpty || identical(processed, sourceBytes)) return;
      final outPath = _preprocessedPath(originalPath);
      if (_discardedImagePaths.contains(originalPath) ||
          !await original.exists()) {
        return;
      }
      final temporary = File('$outPath.tmp');
      await temporary.writeAsBytes(processed, flush: true);
      if (_discardedImagePaths.contains(originalPath) ||
          !await original.exists()) {
        if (await temporary.exists()) await temporary.delete();
        return;
      }
      await temporary.rename(outPath);
      debugPrint('[CaptureService] Preprocessed image saved: $outPath');
    } catch (e) {
      debugPrint('[CaptureService] Preprocess failed, fallback to original: $e');
    }
  }

  String _preprocessedPath(String original) {
    final dot = original.lastIndexOf('.');
    if (dot < 0) return '${original}_preprocessed.jpg';
    return '${original.substring(0, dot)}_preprocessed.jpg';
  }
}
