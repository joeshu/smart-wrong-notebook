import 'package:smart_wrong_notebook/src/domain/models/question_region.dart';
import 'package:smart_wrong_notebook/src/shared/utils/latex_normalizer.dart';

/// Converts provider layout labels into a stable, provider-independent block
/// contract. Provider labels are preferred; content heuristics are only a
/// fallback when an API omits semantic block metadata.
class SpecializedRecognitionRouter {
  const SpecializedRecognitionRouter();

  DocumentBlockType classify({required String providerLabel, required String content}) {
    final label = providerLabel.trim().toLowerCase();
    if (_containsAny(label, const <String>['handwriting', 'handwritten', 'handwrite'])) {
      return DocumentBlockType.handwriting;
    }
    if (_containsAny(label, const <String>['formula', 'equation', 'interline_equation'])) {
      return DocumentBlockType.formula;
    }
    if (_containsAny(label, const <String>['table', 'spreadsheet'])) return DocumentBlockType.table;
    if (_containsAny(label, const <String>['chart', 'diagram', 'figure'])) return DocumentBlockType.diagram;
    if (_containsAny(label, const <String>['image', 'picture'])) return DocumentBlockType.image;
    if (_containsAny(label, const <String>['answer_mark', 'seal', 'stamp'])) return DocumentBlockType.answerMark;
    if (content.contains('|') && content.split('\n').where((line) => line.contains('|')).length >= 2) {
      return DocumentBlockType.table;
    }
    if (LatexNormalizer.hasFormula(content)) return DocumentBlockType.formula;
    return content.trim().isEmpty ? DocumentBlockType.unknown : DocumentBlockType.text;
  }

  DocumentRecognitionEngine engineFor(DocumentBlockType type, {required bool precisionProvider}) {
    switch (type) {
      case DocumentBlockType.text:
        return precisionProvider ? DocumentRecognitionEngine.visionLayout : DocumentRecognitionEngine.printedOcr;
      case DocumentBlockType.handwriting:
        return precisionProvider ? DocumentRecognitionEngine.visionLayout : DocumentRecognitionEngine.handwritingOcr;
      case DocumentBlockType.formula:
        return precisionProvider ? DocumentRecognitionEngine.visionLayout : DocumentRecognitionEngine.formulaRecognizer;
      case DocumentBlockType.table:
        return precisionProvider ? DocumentRecognitionEngine.visionLayout : DocumentRecognitionEngine.tableRecognizer;
      case DocumentBlockType.diagram:
      case DocumentBlockType.image:
      case DocumentBlockType.answerMark:
      case DocumentBlockType.unknown:
        return DocumentRecognitionEngine.sourceImage;
    }
  }

  DocumentRecognitionStatus statusFor(DocumentBlockType type, String content) {
    if (type == DocumentBlockType.diagram || type == DocumentBlockType.image ||
        type == DocumentBlockType.answerMark || type == DocumentBlockType.unknown) {
      return DocumentRecognitionStatus.sourcePreserved;
    }
    if (type == DocumentBlockType.handwriting && content.trim().isEmpty) {
      return DocumentRecognitionStatus.needsSpecialist;
    }
    return content.trim().isEmpty
        ? DocumentRecognitionStatus.needsSpecialist
        : DocumentRecognitionStatus.recognized;
  }

  DocumentContentFormat formatFor(DocumentBlockType type) {
    switch (type) {
      case DocumentBlockType.formula:
        return DocumentContentFormat.latex;
      case DocumentBlockType.table:
        return DocumentContentFormat.tableGrid;
      case DocumentBlockType.diagram:
      case DocumentBlockType.image:
      case DocumentBlockType.answerMark:
      case DocumentBlockType.unknown:
        return DocumentContentFormat.imageReference;
      case DocumentBlockType.text:
      case DocumentBlockType.handwriting:
        return DocumentContentFormat.plainText;
    }
  }

  bool _containsAny(String value, List<String> needles) => needles.any(value.contains);
}
