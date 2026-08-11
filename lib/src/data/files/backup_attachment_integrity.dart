import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Integrity helpers for portable JSON backup attachments.
class BackupAttachmentIntegrity {
  const BackupAttachmentIntegrity._();

  static String sha256Hex(List<int> bytes) => sha256.convert(bytes).toString();

  static bool matches(Uint8List bytes, String? expectedHash) {
    if (expectedHash == null || expectedHash.isEmpty) return true;
    return sha256Hex(bytes) == expectedHash;
  }
}
