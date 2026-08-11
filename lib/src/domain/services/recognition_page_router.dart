import 'package:smart_wrong_notebook/src/domain/models/question_region.dart';

/// Conservative page classifier used to choose a review/recognition route.
/// Unknown is preferred when the available layout evidence is ambiguous.
class RecognitionPageRouter {
  const RecognitionPageRouter();

  RecognitionDocument route({
    required String documentId,
    required List<QuestionRegion> regions,
    RecognitionSourceType sourceType = RecognitionSourceType.unknown,
    int pageCount = 1,
    List<String> qualityIssues = const <String>[],
  }) {
    final blocks = regions.expand((region) => region.documentBlocks).toList(growable: false);
    final roles = blocks.map((block) => block.authorRole).toSet();
    final types = blocks.map((block) => block.type).toSet();
    final text = regions.map((region) => region.recognizedText ?? '').join('\n');

    RecognitionPageType type = RecognitionPageType.unknown;
    double confidence = .35;
    if (sourceType == RecognitionSourceType.screenshot) {
      type = RecognitionPageType.screenshot;
      confidence = .95;
    } else if (roles.contains(DocumentAuthorRole.teacherMark)) {
      type = RecognitionPageType.markedWorksheet;
      confidence = .9;
    } else if (types.contains(DocumentBlockType.handwriting) &&
        !roles.contains(DocumentAuthorRole.printedPrompt)) {
      type = RecognitionPageType.handwrittenNotebook;
      confidence = .8;
    } else if (_looksLikeEssay(text)) {
      type = RecognitionPageType.essayPage;
      confidence = .75;
    } else if (_looksLikeAnswerSheet(text)) {
      type = RecognitionPageType.answerSheet;
      confidence = .75;
    } else if (regions.length >= 2) {
      type = RecognitionPageType.multiQuestionPage;
      confidence = .85;
    } else if (regions.length == 1) {
      type = RecognitionPageType.printedSingleQuestion;
      confidence = .65;
    }

    return RecognitionDocument(
      id: documentId,
      sourceType: sourceType,
      pageType: type,
      pageCount: pageCount,
      qualityIssues: qualityIssues,
      blocks: blocks,
      regions: regions,
      routingConfidence: confidence,
    );
  }

  bool _looksLikeEssay(String text) =>
      text.length >= 300 && RegExp(r'作文|题目自拟|不少于\d+字').hasMatch(text);

  bool _looksLikeAnswerSheet(String text) =>
      RegExp(r'答题卡|准考证号|选择题答题区').hasMatch(text);
}
