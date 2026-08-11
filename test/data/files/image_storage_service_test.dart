import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_wrong_notebook/src/data/files/image_storage_service.dart';

void main() {
  test('deleteImage removes the managed image and its preprocessed sibling',
      () async {
    final directory = await Directory.systemTemp.createTemp('image-cleanup-');
    addTearDown(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });
    final original = File('${directory.path}/question.png');
    final preprocessed = File('${directory.path}/question_preprocessed.jpg');
    await original.writeAsBytes(<int>[1, 2, 3]);
    await preprocessed.writeAsBytes(<int>[4, 5, 6]);

    await ImageStorageService().deleteImage(original.path);

    expect(await original.exists(), isFalse);
    expect(await preprocessed.exists(), isFalse);
  });

  test('capture preprocessing is launched without blocking draft creation', () {
    final source = File('lib/src/data/services/capture_service.dart')
        .readAsStringSync();

    expect(source, contains('unawaited(_generatePreprocessedImage(savedPath))'));
    expect(
      source,
      isNot(contains('await _generatePreprocessedImage(savedPath)')),
    );
  });
}
