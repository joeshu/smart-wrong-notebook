import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:smart_wrong_notebook/src/data/files/image_storage_service.dart';

void main() {
  test('stores and cleans a 12MP image', () async {
    final image = img.Image(width: 4000, height: 3000);
    final bytes = img.encodeJpg(image, quality: 82);
    final input = File('${Directory.systemTemp.path}/rc-12mp.jpg')
      ..writeAsBytesSync(bytes);
    final service = ImageStorageService();
    try {
      final saved = await service.saveImage(input);
      expect(await File(saved).exists(), isTrue);
      await service.deleteImage(saved);
      expect(await File(saved).exists(), isFalse);
    } finally {
      if (await input.exists()) await input.delete();
    }
  });

  test('stores and cleans an eight-page image batch', () async {
    final service = ImageStorageService();
    final paths = <String>[];
    try {
      for (var index = 0; index < 8; index++) {
        final image = img.Image(width: 1600, height: 2200);
        final bytes = img.encodeJpg(image, quality: 78);
        final input = File('${Directory.systemTemp.path}/rc-page-$index.jpg')
          ..writeAsBytesSync(bytes);
        try {
          paths.add(await service.saveImage(input));
        } finally {
          if (await input.exists()) await input.delete();
        }
      }
      expect(paths, hasLength(8));
      for (final path in paths) {
        expect(await File(path).exists(), isTrue);
      }
    } finally {
      for (final path in paths) {
        await service.deleteImage(path);
      }
    }
  });
}
