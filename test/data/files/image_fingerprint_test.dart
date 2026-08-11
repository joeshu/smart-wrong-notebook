import 'package:flutter_test/flutter_test.dart';
import 'package:smart_wrong_notebook/src/data/files/image_fingerprint.dart';

void main() {
  test('perceptual tags coexist with exact SHA tags', () {
    final tags = ImageFingerprintCodec.writePerceptual(
      ImageFingerprintCodec.write(const <String>['user-tag'], 'exact'),
      '0123456789abcdef',
    );

    expect(ImageFingerprintCodec.read(tags), 'exact');
    expect(
      ImageFingerprintCodec.readPerceptual(tags),
      '0123456789abcdef',
    );
    expect(tags, contains('user-tag'));
  });

  test('perceptual similarity reflects hamming distance', () {
    expect(
      ImageFingerprintCodec.perceptualSimilarity(
        '0000000000000000',
        '0000000000000000',
      ),
      1,
    );
    expect(
      ImageFingerprintCodec.perceptualSimilarity(
        '0000000000000000',
        '0000000000000001',
      ),
      closeTo(63 / 64, 0.0001),
    );
  });
}
