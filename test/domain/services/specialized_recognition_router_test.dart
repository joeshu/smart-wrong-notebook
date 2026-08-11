import 'package:flutter_test/flutter_test.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_region.dart';
import 'package:smart_wrong_notebook/src/domain/services/specialized_recognition_router.dart';

void main() {
  const router = SpecializedRecognitionRouter();

  test('provider semantic label wins over missing textual delimiters', () {
    expect(
      router.classify(providerLabel: 'interline_equation', content: 'x²+y²=r²'),
      DocumentBlockType.formula,
    );
    expect(
      router.classify(providerLabel: 'table', content: '姓名 分数'),
      DocumentBlockType.table,
    );
  });

  test('handwriting is routed to specialist recognition', () {
    final type = router.classify(providerLabel: 'handwritten_text', content: '解：x=2');
    expect(type, DocumentBlockType.handwriting);
    expect(
      router.engineFor(type, precisionProvider: false),
      DocumentRecognitionEngine.handwritingOcr,
    );
  });

  test('diagram with no text preserves source evidence instead of fake OCR text', () {
    final type = router.classify(providerLabel: 'figure', content: '');
    expect(type, DocumentBlockType.diagram);
    expect(router.formatFor(type), DocumentContentFormat.imageReference);
    expect(router.statusFor(type, ''), DocumentRecognitionStatus.sourcePreserved);
    expect(
      router.engineFor(type, precisionProvider: false),
      DocumentRecognitionEngine.sourceImage,
    );
  });

  test('content heuristics remain a fallback for providers without labels', () {
    expect(
      router.classify(providerLabel: '', content: r'$a^2+b^2=c^2$'),
      DocumentBlockType.formula,
    );
    expect(
      router.classify(providerLabel: '', content: '| A | B |\n|---|---|'),
      DocumentBlockType.table,
    );
  });
}
