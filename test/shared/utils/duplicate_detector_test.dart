import 'package:flutter_test/flutter_test.dart';
import 'package:smart_wrong_notebook/src/data/files/image_fingerprint.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';
import 'package:smart_wrong_notebook/src/shared/utils/duplicate_detector.dart';

QuestionRecord _record(String id, String hash) => QuestionRecord.draft(
      id: id,
      imagePath: '/managed/$id.jpg',
      subject: Subject.math,
      recognizedText: '',
    ).copyWith(
      tags: ImageFingerprintCodec.writePerceptual(const <String>[], hash),
    );

void main() {
  test('near-identical perceptual images match without recognized text',
      () async {
    final matches = await const DuplicateDetector().detectDuplicates(
      _record('candidate', '0000000000000000'),
      <QuestionRecord>[_record('existing', '0000000000000001')],
      threshold: .9,
    );

    expect(matches, hasLength(1));
    expect(matches.single.imageSimilarity, closeTo(63 / 64, .0001));
    expect(matches.single.overallScore, closeTo(63 / 64, .0001));
  });
}
