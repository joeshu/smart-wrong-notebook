import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_wrong_notebook/src/data/repositories/worksheet_review_draft_repository.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_region.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';

QuestionRegion _region({
  String id = 'r1',
  String? text,
  String? original,
  List<String> formulas = const <String>[],
  List<String> tables = const <String>[],
  List<String> options = const <String>[],
  String? diagramNote,
}) {
  return QuestionRegion(
    id: id,
    normalizedRect: const Rect.fromLTWH(0.1, 0.2, 0.5, 0.3),
    recognizedText: text,
    originalRecognizedText: original,
    formulas: formulas,
    tables: tables,
    options: options,
    diagramNote: diagramNote,
    subject: Subject.math,
  );
}

void main() {
  late WorksheetReviewDraftRepository repo;

  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    repo = WorksheetReviewDraftRepository();
  });

  group('WorksheetReviewDraftRepository 新字段 round-trip', () {
    test('内容块空间证据、角色和风险码正确保存和恢复', () async {
      final region = _region(text: '题干').copyWith(
        parentRegionId: 'major-1',
        readingOrder: 2,
        columnIndex: 1,
        assemblyRiskCodes: const <QuestionAssemblyRiskCode>{
          QuestionAssemblyRiskCode.authorRoleUncertain,
        },
        documentBlocks: const <DocumentBlock>[
          DocumentBlock(
            id: 'teacher-1',
            type: DocumentBlockType.answerMark,
            content: '×',
            polygon: <Offset>[Offset(.2, .3), Offset(.3, .3), Offset(.3, .4)],
            authorRole: DocumentAuthorRole.teacherMark,
            inkColor: 'red',
            confidence: .7,
            riskCodes: <DocumentBlockRiskCode>{DocumentBlockRiskCode.roleUncertain},
            recognitionEngine: DocumentRecognitionEngine.sourceImage,
            recognitionStatus: DocumentRecognitionStatus.sourcePreserved,
            sourceCropRef: 'crop://teacher-1',
            parentBlockId: 'r1',
            contentFormat: DocumentContentFormat.imageReference,
          ),
        ],
      );

      await repo.save('page-blocks', <QuestionRegion>[region]);
      final block = (await repo.load('page-blocks'))!.single.documentBlocks.single;
      expect(block.type, DocumentBlockType.answerMark);
      expect(block.authorRole, DocumentAuthorRole.teacherMark);
      expect(block.polygon, hasLength(3));
      expect(block.riskCodes, <DocumentBlockRiskCode>{DocumentBlockRiskCode.roleUncertain});
      expect(block.recognitionEngine, DocumentRecognitionEngine.sourceImage);
      expect(block.recognitionStatus, DocumentRecognitionStatus.sourcePreserved);
      expect(block.parentBlockId, 'r1');
      final restored = (await repo.load('page-blocks'))!.single;
      expect(restored.parentRegionId, 'major-1');
      expect(restored.readingOrder, 2);
      expect(restored.columnIndex, 1);
      expect(restored.assemblyRiskCodes,
          contains(QuestionAssemblyRiskCode.authorRoleUncertain));
    });

    test('单个损坏候选不会清除同页其他有效草稿', () async {
      await repo.save('page1', <QuestionRegion>[_region(id: 'valid', text: '保留')]);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('worksheet_review_draft_v1_page1', jsonEncode(<Object?>[
        <String, Object?>{'id': 'valid', 'rect': <double>[.1, .2, .5, .3], 'text': '保留'},
        <String, Object?>{'id': 'bad', 'rect': <Object>[.1, .2, 9, .3], 'text': '损坏'},
      ]));
      final restored = await repo.load('page1');
      expect(restored, hasLength(1));
      expect(restored!.single.id, 'valid');
    });
    test('options 与 diagramNote 正确保存和恢复', () async {
      final regions = <QuestionRegion>[
        _region(
          id: 'r1',
          text: '题干\nA. 红色\nB. 蓝色',
          original: '题干\nA. 红色\nB. 蓝色',
          options: const <String>['A. 红色', 'B. 蓝色'],
          diagramNote: '直角三角形 ABC',
        ),
        _region(id: 'r2', text: '题干', options: const <String>[]),
      ];

      await repo.save('page1', regions);
      final restored = await repo.load('page1');

      expect(restored, isNotNull);
      expect(restored!.length, 2);
      expect(restored[0].options, <String>['A. 红色', 'B. 蓝色']);
      expect(restored[0].diagramNote, '直角三角形 ABC');
      expect(restored[1].options, isEmpty);
      expect(restored[1].diagramNote, isNull);
    });

    test('老草稿（缺 options/diagramNote 键）load 时回落到默认值', () async {
      // 模拟老草稿 JSON：不带 options / diagramNote 键。
      final legacyJson = <Map<String, Object?>>[
        <String, Object?>{
          'id': 'r1',
          'rect': <double>[0.1, 0.2, 0.5, 0.3],
          'number': null,
          'text': '题干',
          'original': null,
          'stem': null,
          'formulas': <String>[],
          'tables': <String>[],
          'blocks': <Map<String, Object?>>[],
          'format': null,
          'types': <String>[],
          'subject': null,
          'questionType': null,
          'ai': true,
          'review': 0,
          'confidence': 1.0,
          'source': 0,
        },
      ];
      SharedPreferences.setMockInitialValues(<String, Object>{
        'worksheet_review_draft_v1_page1': jsonEncode(legacyJson),
      });

      final restored = await repo.load('page1');
      expect(restored, isNotNull);
      expect(restored!.single.options, isEmpty);
      expect(restored.single.diagramNote, isNull);
    });

    test('diagramNote 为空串时也能 round-trip（区分 null 与空串）', () async {
      final regions = <QuestionRegion>[
        _region(id: 'r1', text: '题干', diagramNote: ''),
      ];
      await repo.save('page1', regions);
      final restored = await repo.load('page1');
      expect(restored, isNotNull);
      // 空串保存为 ''，不是 null（用于"用户主动清空备注"语义）
      expect(restored!.single.diagramNote, '');
    });
  });
}
