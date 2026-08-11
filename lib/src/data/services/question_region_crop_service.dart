import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as image;
import 'package:smart_wrong_notebook/src/data/files/image_storage_service.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_region.dart';

/// Produces independent final question images from confirmed worksheet regions.
class QuestionRegionCropService {
  QuestionRegionCropService({ImageStorageService? storage})
      : _storage = storage ?? ImageStorageService();

  final ImageStorageService _storage;

  Future<String> cropToStoredImage({
    required String sourcePath,
    required QuestionRegion region,
  }) async {
    final bytes = await File(sourcePath).readAsBytes();
    final decoded = image.decodeImage(bytes);
    if (decoded == null) throw StateError('无法读取试卷图片');

    final rect = region.normalizedRect;
    final left = (rect.left.clamp(0.0, 1.0) * decoded.width).round();
    final top = (rect.top.clamp(0.0, 1.0) * decoded.height).round();
    final width = (rect.width.clamp(0.01, 1.0) * decoded.width).round();
    final height = (rect.height.clamp(0.01, 1.0) * decoded.height).round();
    final safeWidth = width.clamp(1, decoded.width - left).toInt();
    final safeHeight = height.clamp(1, decoded.height - top).toInt();
    if (left >= decoded.width || top >= decoded.height) {
      throw StateError('题目框超出了试卷图片范围');
    }

    final cropped = image.copyCrop(decoded,
        x: left, y: top, width: safeWidth, height: safeHeight);
    final encoded = Uint8List.fromList(image.encodeJpg(cropped, quality: 85));
    final temp = File('${Directory.systemTemp.path}/question-region-${region.id}.jpg');
    await temp.writeAsBytes(encoded, flush: true);
    return _storage.saveImage(temp);
  }
}
