import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_wrong_notebook/src/data/files/backup_attachment_integrity.dart';

void main() {
  test('accepts matching SHA-256 attachment hash', () {
    final bytes = Uint8List.fromList(<int>[1, 2, 3, 4]);
    final hash = BackupAttachmentIntegrity.sha256Hex(bytes);

    expect(BackupAttachmentIntegrity.matches(bytes, hash), isTrue);
  });

  test('rejects altered attachment data and accepts legacy no-hash backups', () {
    final original = Uint8List.fromList(<int>[1, 2, 3, 4]);
    final altered = Uint8List.fromList(<int>[1, 2, 3, 5]);
    final hash = BackupAttachmentIntegrity.sha256Hex(original);

    expect(BackupAttachmentIntegrity.matches(altered, hash), isFalse);
    expect(BackupAttachmentIntegrity.matches(altered, null), isTrue);
  });
}
