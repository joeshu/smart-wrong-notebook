import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_wrong_notebook/src/domain/services/recognition_accuracy_metrics.dart';

void main() {
  test('current unannotated manifest reports pending for every accuracy metric', () {
    final manifest = jsonDecode(
      File('test/fixtures/accuracy_manifest.json').readAsStringSync(),
    ) as Map<String, dynamic>;

    final report = RecognitionAccuracyMetrics.evaluateManifest(manifest);

    expect(report.isPending, isTrue);
    expect(report.annotationStatus, 'pending_human_annotation');
    expect(report.metrics.keys, containsAll(RecognitionAccuracyMetrics.metricNames));
    expect(report.metrics.values.every((metric) => metric.value == null), isTrue);
    expect(report.metrics.values.every((metric) => metric.status == 'pending'), isTrue);
    expect(report.caseCount, 10);
    expect(report.manualCaseCount, 7);
    expect(report.automatedCaseCount, 3);
    expect(report.strata, isNotEmpty);
    expect(report.strata.keys, contains('printed|pending|pending'));
    final markdown = report.toMarkdown();
    expect(markdown, contains('# 识别质量验收报告'));
    expect(markdown, contains('pending'));
    expect(markdown, isNot(contains('0.00%')));
  });

  test('completed measurements calculate rates without using confidence', () {
    final report = RecognitionAccuracyMetrics.evaluateManifest(<String, dynamic>{
      'manifestVersion': 2,
      'annotationStatus': 'completed',
      'cases': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'a',
          'category': 'printed',
          'validation': 'automated_contract',
          'expected': <String, dynamic>{},
          'captureMode': 'printed',
          'engine': 'test',
          'engineVersion': '1',
        },
        <String, dynamic>{
          'id': 'b',
          'category': 'handwritten',
          'validation': 'automated_contract',
          'expected': <String, dynamic>{},
          'captureMode': 'handwritten',
          'engine': 'test',
          'engineVersion': '1',
        },
      ],
      'measurements': <Map<String, dynamic>>[
        <String, dynamic>{
          'boxIoU': .9,
          'ocrCharacterAccuracy': .8,
          'formulaCompleteness': 1.0,
          'tableStructureAccuracy': .7,
          'userModified': true,
          'duplicateAiCall': false,
          'saveComplete': true,
          'recovered': true,
          'confidence': .1,
          'caseId': 'a',
          'captureMode': 'printed',
          'engine': 'test',
          'engineVersion': '1',
        },
        <String, dynamic>{
          'boxIoU': .7,
          'ocrCharacterAccuracy': 1.0,
          'formulaCompleteness': .5,
          'tableStructureAccuracy': .9,
          'userModified': false,
          'duplicateAiCall': true,
          'saveComplete': true,
          'recovered': false,
          'confidence': .99,
          'caseId': 'b',
          'captureMode': 'handwritten',
          'engine': 'test',
          'engineVersion': '1',
        },
      ],
    });

    expect(report.isPending, isFalse);
    expect(report.metrics['boxIoU']!.value, closeTo(.8, .0001));
    expect(report.metrics['ocrCharacterAccuracy']!.value, closeTo(.9, .0001));
    expect(report.metrics['userModificationRate']!.value, .5);
    expect(report.metrics['duplicateAiCallRate']!.value, .5);
    expect(report.metrics['saveCompletenessRate']!.value, 1);
    expect(report.metrics['recoveryRate']!.value, .5);
    expect(report.strata.keys, containsAll(<String>['printed|test|1', 'handwritten|test|1']));
    expect(report.caseCount, 2);
    expect(report.toMarkdown(), contains('80.00%'));
  });

  test('manifest validation rejects duplicate ids and missing expected objects', () {
    final errors = RecognitionAccuracyMetrics.validateManifest(<String, dynamic>{
      'manifestVersion': 1,
      'cases': <Map<String, dynamic>>[
        <String, dynamic>{'id': 'same', 'category': 'x', 'validation': 'manual_required'},
        <String, dynamic>{'id': 'same', 'category': '', 'validation': 'manual_required'},
      ],
    });

    expect(errors, contains('cases[1] has a missing or duplicate id'));
    expect(errors, contains('cases[1].category must be non-empty'));
    expect(errors, contains('cases[0].expected must be an object'));
  });

  test('completed manifest requires one bounded measurement per case', () {
    final errors = RecognitionAccuracyMetrics.validateManifest(<String, dynamic>{
      'manifestVersion': 2,
      'annotationStatus': 'completed',
      'cases': <Map<String, dynamic>>[
        <String, dynamic>{
          'id': 'a',
          'category': 'printed',
          'validation': 'manual_required',
          'expected': <String, dynamic>{},
          'captureMode': 'printed',
          'engine': 'x',
          'engineVersion': '1',
        },
      ],
      'measurements': <Map<String, dynamic>>[
        <String, dynamic>{'caseId': 'unknown'},
      ],
    });

    expect(errors, contains('measurements[0].caseId must uniquely reference a case'));
    expect(errors, contains('measurements[0].boxIoU must be between 0 and 1'));
    expect(errors, contains('measurements must have exactly one row per case'));
  });

  test('pure geometry and structured recognition helpers are bounded', () {
    expect(
      RecognitionAccuracyMetrics.intersectionOverUnion(0, 0, 1, 1, .5, .5, 1.5, 1.5),
      closeTo(1 / 7, .0001),
    );
    expect(RecognitionAccuracyMetrics.characterAccuracy('abc', 'adc'), closeTo(2 / 3, .0001));
    expect(
      RecognitionAccuracyMetrics.formulaCompleteness(
        boundaryPreserved: true,
        pairedMarkersPreserved: false,
        keySymbolsPreserved: true,
      ),
      closeTo(2 / 3, .0001),
    );
    expect(
      RecognitionAccuracyMetrics.tableStructureAccuracy(
        expectedRows: 2,
        expectedColumns: 3,
        actualRows: 2,
        actualColumns: 2,
      ),
      closeTo(5 / 6, .0001),
    );
  });
}
