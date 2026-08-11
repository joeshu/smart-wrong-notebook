import 'dart:ui';

import 'package:smart_wrong_notebook/src/domain/models/question_region.dart';

class QuestionAssemblyResult {
  const QuestionAssemblyResult({
    required this.regions,
    required this.columnCount,
  });

  final List<QuestionRegion> regions;
  final int columnCount;
}

/// Deterministic page-level assembly. Provider order is never treated as the
/// reading order; geometry is the source of truth and uncertain inferences are
/// kept visible for confirmation.
class QuestionAssemblyService {
  const QuestionAssemblyService();

  QuestionAssemblyResult assemble(
    List<QuestionRegion> source, {
    Map<String, String?> parentOverrides = const <String, String?>{},
  }) {
    if (source.isEmpty) {
      return const QuestionAssemblyResult(regions: <QuestionRegion>[], columnCount: 0);
    }
    final twoColumns = _looksTwoColumn(source);
    final sorted = List<QuestionRegion>.from(source)..sort((a, b) {
      final ac = twoColumns ? _column(a.normalizedRect) : 0;
      final bc = twoColumns ? _column(b.normalizedRect) : 0;
      if (ac != bc) return ac.compareTo(bc);
      final vertical = a.normalizedRect.top.compareTo(b.normalizedRect.top);
      return vertical != 0 ? vertical : a.normalizedRect.left.compareTo(b.normalizedRect.left);
    });

    String? currentParent;
    var currentColumn = -1;
    final assembled = <QuestionRegion>[];
    for (var index = 0; index < sorted.length; index++) {
      final region = sorted[index];
      final column = twoColumns ? _column(region.normalizedRect) : 0;
      if (column != currentColumn) {
        currentParent = null;
        currentColumn = column;
      }
      final number = (region.detectedNumber ?? '').trim();
      final isChild = RegExp(r'^[（(]\s*\d+\s*[)）]$').hasMatch(number);
      String? parentId;
      var risks = Set<QuestionAssemblyRiskCode>.from(region.assemblyRiskCodes)
        ..removeAll(const <QuestionAssemblyRiskCode>{
          QuestionAssemblyRiskCode.readingOrderUncertain,
          QuestionAssemblyRiskCode.parentQuestionUncertain,
          QuestionAssemblyRiskCode.authorRoleUncertain,
          QuestionAssemblyRiskCode.specialistRetryRequired,
        });
      if (parentOverrides.containsKey(region.id)) {
        parentId = parentOverrides[region.id];
        risks.remove(QuestionAssemblyRiskCode.parentQuestionUncertain);
      } else if (isChild) {
        parentId = currentParent;
        if (parentId == null) risks.add(QuestionAssemblyRiskCode.parentQuestionUncertain);
      } else {
        currentParent = region.id;
      }
      if (twoColumns && _crossesGutter(region.normalizedRect)) {
        risks.add(QuestionAssemblyRiskCode.readingOrderUncertain);
      }
      if (region.documentBlocks.any((block) =>
          block.riskCodes.contains(DocumentBlockRiskCode.roleUncertain))) {
        risks.add(QuestionAssemblyRiskCode.authorRoleUncertain);
      }
      if (region.documentBlocks.any((block) =>
          block.recognitionStatus == DocumentRecognitionStatus.needsSpecialist ||
          block.recognitionStatus == DocumentRecognitionStatus.failed)) {
        risks.add(QuestionAssemblyRiskCode.specialistRetryRequired);
      }
      assembled.add(region.copyWith(
        parentRegionId: parentId,
        readingOrder: index,
        columnIndex: column,
        assemblyRiskCodes: risks,
        documentBlocks: _sortBlocks(region.documentBlocks),
      ));
    }
    return QuestionAssemblyResult(regions: assembled, columnCount: twoColumns ? 2 : 1);
  }

  DocumentBlock confirmAuthorRole(DocumentBlock block, DocumentAuthorRole role) {
    final risks = Set<DocumentBlockRiskCode>.from(block.riskCodes)
      ..remove(DocumentBlockRiskCode.roleUncertain);
    return block.copyWith(authorRole: role, riskCodes: risks);
  }

  DocumentBlock requestSpecialistRetry(DocumentBlock block) => block.copyWith(
    recognitionStatus: DocumentRecognitionStatus.needsSpecialist,
    recognitionEngine: _engineFor(block.type),
  );

  bool _looksTwoColumn(List<QuestionRegion> regions) {
    final candidates = regions.where((r) => r.normalizedRect.width < .58).toList();
    if (candidates.length < 4) return false;
    final left = candidates.where((r) => r.normalizedRect.center.dx < .46).length;
    final right = candidates.where((r) => r.normalizedRect.center.dx > .54).length;
    return left >= 2 && right >= 2;
  }

  int _column(Rect rect) => rect.center.dx < .5 ? 0 : 1;
  bool _crossesGutter(Rect rect) => rect.left < .48 && rect.right > .52;

  List<DocumentBlock> _sortBlocks(List<DocumentBlock> blocks) {
    final sorted = List<DocumentBlock>.from(blocks);
    sorted.sort((a, b) {
      if (a.polygon.isEmpty || b.polygon.isEmpty) return 0;
      final ay = a.polygon.map((p) => p.dy).reduce((x, y) => x < y ? x : y);
      final by = b.polygon.map((p) => p.dy).reduce((x, y) => x < y ? x : y);
      final row = ay.compareTo(by);
      if (row != 0) return row;
      final ax = a.polygon.map((p) => p.dx).reduce((x, y) => x < y ? x : y);
      final bx = b.polygon.map((p) => p.dx).reduce((x, y) => x < y ? x : y);
      return ax.compareTo(bx);
    });
    return sorted;
  }

  DocumentRecognitionEngine _engineFor(DocumentBlockType type) => switch (type) {
    DocumentBlockType.handwriting => DocumentRecognitionEngine.handwritingOcr,
    DocumentBlockType.formula => DocumentRecognitionEngine.formulaRecognizer,
    DocumentBlockType.table => DocumentRecognitionEngine.tableRecognizer,
    DocumentBlockType.diagram || DocumentBlockType.image => DocumentRecognitionEngine.visionLayout,
    _ => DocumentRecognitionEngine.printedOcr,
  };
}
