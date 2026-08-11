import 'dart:convert';
import 'dart:ui';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_region.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';

/// Isolated, recoverable review state for an unconfirmed worksheet page.
class WorksheetReviewDraftRepository {
  static const _prefix = 'worksheet_review_draft_v1_';

  Future<List<QuestionRegion>?> load(String sourcePageId) async {
    final raw = (await SharedPreferences.getInstance()).getString('$_prefix$sourcePageId');
    if (raw == null || raw.isEmpty) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return null;
      final regions = <QuestionRegion>[];
      for (final item in decoded) {
        try {
          if (item is Map) regions.add(_decode(Map<String, dynamic>.from(item)));
        } catch (_) {
          // A damaged candidate must not discard the other review progress.
        }
      }
      return regions;
    } catch (_) {
      await clear(sourcePageId);
      return null;
    }
  }

  Future<void> save(String sourcePageId, List<QuestionRegion> regions) async {
    await (await SharedPreferences.getInstance()).setString(
      '$_prefix$sourcePageId', jsonEncode(regions.map(_encode).toList()),
    );
  }

  Future<void> clear(String sourcePageId) async =>
      (await SharedPreferences.getInstance()).remove('$_prefix$sourcePageId');

  Map<String, Object?> _encode(QuestionRegion region) => <String, Object?>{
    'id': region.id, 'rect': <double>[region.normalizedRect.left, region.normalizedRect.top, region.normalizedRect.width, region.normalizedRect.height],
    'number': region.detectedNumber, 'text': region.recognizedText, 'original': region.originalRecognizedText,
    'stem': region.questionStem, 'formulas': region.formulas, 'tables': region.tables, 'options': region.options,
    'blocks': region.documentBlocks.map(_encodeBlock).toList(),
    'format': region.contentFormatHint, 'types': region.recognizedBlockTypes, 'subject': region.subject?.index,
    'questionType': region.questionType, 'ai': region.analyzeWithAi, 'review': region.reviewStatus.index,
    'confidence': region.confidence, 'source': region.source.index, 'diagramNote': region.diagramNote,
    'studentAnswer': region.studentAnswer, 'aiNormalizedText': region.aiNormalizedText,
    'confirmedFields': region.confirmedFields.toList(growable: false),
    if (region.parentRegionId != null) 'parentRegionId': region.parentRegionId,
    if (region.readingOrder != null) 'readingOrder': region.readingOrder,
    'columnIndex': region.columnIndex,
    if (region.assemblyRiskCodes.isNotEmpty)
      'assemblyRiskCodes': region.assemblyRiskCodes.map((code) => code.index).toList(),
  };

  Map<String, Object?> _encodeBlock(DocumentBlock block) => <String, Object?>{
    'type': block.type.index,
    'content': block.content,
    if (block.id != null) 'id': block.id,
    if (block.polygon.isNotEmpty)
      'polygon': block.polygon.map((point) => <double>[point.dx, point.dy]).toList(),
    'authorRole': block.authorRole.index,
    if (block.inkColor != null) 'inkColor': block.inkColor,
    'confidence': block.confidence,
    if (block.riskCodes.isNotEmpty)
      'riskCodes': block.riskCodes.map((code) => code.index).toList(),
    if (block.sourceCropRef != null) 'sourceCropRef': block.sourceCropRef,
    if (block.parentBlockId != null) 'parentBlockId': block.parentBlockId,
    'contentFormat': block.contentFormat.index,
    'recognitionEngine': block.recognitionEngine.index,
    'recognitionStatus': block.recognitionStatus.index,
  };

  QuestionRegion _decode(Map<String, dynamic> json) {
    final rect = _decodeRect(json['rect']);
    final documentBlocks = <DocumentBlock>[];
    for (final item in (json['blocks'] as List?) ?? const <Object>[]) {
      final block = Map<String, dynamic>.from(item as Map);
      final type = _enumValue(DocumentBlockType.values, block['type']);
      final content = block['content'];
      if (type != null && content is String) {
        documentBlocks.add(DocumentBlock(
          type: type,
          content: content,
          id: block['id'] as String?,
          polygon: _decodePolygon(block['polygon']),
          authorRole: _enumValue(DocumentAuthorRole.values, block['authorRole']) ??
              DocumentAuthorRole.unknown,
          inkColor: block['inkColor'] as String?,
          confidence: _confidence(block['confidence']),
          riskCodes: ((block['riskCodes'] as List?) ?? const <Object>[])
              .map((value) => _enumValue(DocumentBlockRiskCode.values, value))
              .whereType<DocumentBlockRiskCode>()
              .toSet(),
          sourceCropRef: block['sourceCropRef'] as String?,
          parentBlockId: block['parentBlockId'] as String?,
          contentFormat: _enumValue(DocumentContentFormat.values, block['contentFormat']) ??
              DocumentContentFormat.plainText,
          recognitionEngine: _enumValue(DocumentRecognitionEngine.values, block['recognitionEngine']) ??
              DocumentRecognitionEngine.unknown,
          recognitionStatus: _enumValue(DocumentRecognitionStatus.values, block['recognitionStatus']) ??
              DocumentRecognitionStatus.recognized,
        ));
      }
    }
    return QuestionRegion(
      id: json['id'] as String, normalizedRect: Rect.fromLTWH(rect[0], rect[1], rect[2], rect[3]),
      detectedNumber: json['number'] as String?, recognizedText: json['text'] as String?, originalRecognizedText: json['original'] as String?, questionStem: json['stem'] as String?,
      formulas: ((json['formulas'] as List?) ?? const <Object>[]).map((item) => '$item').toList(), tables: ((json['tables'] as List?) ?? const <Object>[]).map((item) => '$item').toList(),
      options: ((json['options'] as List?) ?? const <Object>[]).map((item) => '$item').toList(), documentBlocks: documentBlocks,
      contentFormatHint: json['format'] as String?, recognizedBlockTypes: ((json['types'] as List?) ?? const <Object>[]).map((item) => '$item').toList(),
      subject: _enumValue(Subject.values, json['subject']), questionType: json['questionType'] as String?,
      analyzeWithAi: json['ai'] as bool? ?? true, reviewStatus: _enumValue(QuestionRegionReviewStatus.values, json['review']) ?? QuestionRegionReviewStatus.accepted,
      confidence: _confidence(json['confidence']), source: _enumValue(QuestionRegionSource.values, json['source']) ?? QuestionRegionSource.manual,
      diagramNote: json['diagramNote'] as String?, studentAnswer: json['studentAnswer'] as String?, aiNormalizedText: json['aiNormalizedText'] as String?,
      confirmedFields: ((json['confirmedFields'] as List?) ?? const <Object>[]).map((item) => '$item').toSet(),
      parentRegionId: json['parentRegionId'] as String?,
      readingOrder: json['readingOrder'] as int?,
      columnIndex: json['columnIndex'] as int? ?? 0,
      assemblyRiskCodes: ((json['assemblyRiskCodes'] as List?) ?? const <Object>[])
          .map((value) => _enumValue(QuestionAssemblyRiskCode.values, value))
          .whereType<QuestionAssemblyRiskCode>()
          .toSet(),
    );
  }

  List<double> _decodeRect(Object? value) {
    if (value is! List || value.length != 4) throw const FormatException('invalid rect');
    final rect = value.map((item) => (item as num).toDouble()).toList();
    if (rect.any((item) => !item.isFinite) || rect[2] <= 0 || rect[3] <= 0 || rect[0] < 0 || rect[1] < 0 || rect[0] + rect[2] > 1 || rect[1] + rect[3] > 1) {
      throw const FormatException('rect outside normalized bounds');
    }
    return rect;
  }

  List<Offset> _decodePolygon(Object? value) {
    if (value == null) return const <Offset>[];
    if (value is! List) return const <Offset>[];
    final points = <Offset>[];
    for (final item in value) {
      if (item is! List || item.length != 2) return const <Offset>[];
      final x = (item[0] as num?)?.toDouble();
      final y = (item[1] as num?)?.toDouble();
      if (x == null || y == null || !x.isFinite || !y.isFinite ||
          x < 0 || x > 1 || y < 0 || y > 1) return const <Offset>[];
      points.add(Offset(x, y));
    }
    return points;
  }

  T? _enumValue<T>(List<T> values, Object? value) =>
      value is int && value >= 0 && value < values.length ? values[value] : null;

  double _confidence(Object? value) {
    final confidence = (value as num?)?.toDouble() ?? 1;
    return confidence.isFinite ? confidence.clamp(0, 1).toDouble() : 1;
  }
}
