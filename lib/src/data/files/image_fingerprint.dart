import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:image/image.dart' as image;

/// Keeps a SHA-256 fingerprint in the existing durable tag column. The hash
/// never leaves the device; it lets later analysis reuse an exact local image
/// result without another model request.
class ImageFingerprintCodec {
  const ImageFingerprintCodec._();

  static const _prefix = '__system_image_sha256:';
  static const _perceptualPrefix = '__system_image_dhash:';

  static String? read(Iterable<String> tags) {
    for (final tag in tags) {
      if (tag.startsWith(_prefix)) return tag.substring(_prefix.length);
    }
    return null;
  }

  static List<String> write(Iterable<String> tags, String fingerprint) {
    final result = tags.where((tag) => !tag.startsWith(_prefix)).toList();
    if (fingerprint.isNotEmpty) result.add('$_prefix$fingerprint');
    return result;
  }

  static String? readPerceptual(Iterable<String> tags) {
    for (final tag in tags) {
      if (tag.startsWith(_perceptualPrefix)) {
        return tag.substring(_perceptualPrefix.length);
      }
    }
    return null;
  }

  static List<String> writePerceptual(
    Iterable<String> tags,
    String fingerprint,
  ) {
    final result =
        tags.where((tag) => !tag.startsWith(_perceptualPrefix)).toList();
    if (fingerprint.isNotEmpty) {
      result.add('$_perceptualPrefix$fingerprint');
    }
    return result;
  }

  static Future<String> fromFile(File file) async =>
      sha256.convert(await file.readAsBytes()).toString();

  /// 64-bit difference hash. It remains stable across ordinary JPEG
  /// recompression and small brightness changes, unlike SHA-256.
  static Future<String> perceptualFromFile(File file) async {
    final decoded = image.decodeImage(await file.readAsBytes());
    if (decoded == null) throw StateError('Unable to decode image fingerprint');
    final resized = image.copyResize(decoded, width: 9, height: 8);
    var hash = BigInt.zero;
    for (var y = 0; y < 8; y++) {
      for (var x = 0; x < 8; x++) {
        hash <<= 1;
        if (_luma(resized.getPixel(x, y)) >
            _luma(resized.getPixel(x + 1, y))) {
          hash |= BigInt.one;
        }
      }
    }
    return hash.toRadixString(16).padLeft(16, '0');
  }

  static double perceptualSimilarity(String a, String b) {
    if (a.length != 16 || b.length != 16) return 0;
    try {
      var differing = BigInt.parse(a, radix: 16) ^ BigInt.parse(b, radix: 16);
      var bits = 0;
      while (differing > BigInt.zero) {
        bits += (differing & BigInt.one).toInt();
        differing >>= 1;
      }
      return 1 - bits / 64;
    } catch (_) {
      return 0;
    }
  }

  static double _luma(image.Pixel pixel) =>
      .299 * pixel.r.toDouble() +
      .587 * pixel.g.toDouble() +
      .114 * pixel.b.toDouble();
}
