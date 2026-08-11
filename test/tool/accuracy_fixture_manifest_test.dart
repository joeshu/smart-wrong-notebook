import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:smart_wrong_notebook/src/domain/services/recognition_accuracy_metrics.dart';

void main() {
  late Map<String, dynamic> manifest;
  late List<dynamic> cases;

  setUpAll(() {
    final file = File('test/fixtures/accuracy_manifest.json');
    expect(file.existsSync(), isTrue);
    manifest = jsonDecode(file.readAsStringSync()) as Map<String, dynamic>;
    cases = manifest['cases'] as List<dynamic>;
  });

  test('manifest is explicit, versioned, and covers required categories', () {
    expect(manifest['manifestVersion'], 2);
    expect(manifest['annotationStatus'], 'pending_human_annotation');
    final categories = cases
        .map((item) => (item as Map<String, dynamic>)['category'])
        .toSet();
    expect(
      categories,
      containsAll(<String>[
        'blurred',
        'tilted',
        'handwritten',
        'formula',
        'table',
        'multi_question',
        'blank_or_invalid',
        'incomplete_ocr',
        'ai_failure',
        'duplicate_save',
      ]),
    );
  });

  test('manifest passes the same validation used by the metrics executor', () {
    expect(
      RecognitionAccuracyMetrics.validateManifest(manifest),
      isEmpty,
    );
  });

  test('each case has stable id, category, expected annotation and validation mode', () {
    final ids = <String>{};
    for (final raw in cases) {
      final item = raw as Map<String, dynamic>;
      final id = item['id'] as String?;
      expect(id, isNotNull);
      expect(ids.add(id!), isTrue, reason: 'duplicate fixture id: $id');
      expect((item['category'] as String?)?.isNotEmpty, isTrue);
      expect((item['pageType'] as String?)?.isNotEmpty, isTrue);
      expect((item['schoolStage'] as String?)?.isNotEmpty, isTrue);
      expect(item['contentTags'], isA<List<dynamic>>());
      expect(item['authorRoles'], isA<List<dynamic>>());
      expect(item['expected'], isA<Map<String, dynamic>>());
      expect(
        <String>['manual_required', 'automated_contract'],
        contains(item['validation']),
      );

      final expected = item['expected'] as Map<String, dynamic>;
      expect(expected.keys, containsAll(<String>[
        'questionCount',
        'text',
        'regions',
        'formulaCount',
        'tableShape',
      ]));
      if (item['validation'] == 'manual_required') {
        expect(item['notes'], isA<String>());
      }
    }
  });

  test('image-backed cases use repository fixture paths and may remain pending', () {
    for (final raw in cases) {
      final item = raw as Map<String, dynamic>;
      final imagePath = item['imagePath'] as String?;
      if (imagePath == null) continue;
      expect(imagePath, startsWith('test/fixtures/accuracy/'));
      expect(imagePath.toLowerCase(), endsWith('.png'));
      // The manifest is committed before private/de-identified images arrive.
      // Missing files are reported as pending, not treated as model accuracy.
      if (!File(imagePath).existsSync()) {
        expect(manifest['annotationStatus'], 'pending_human_annotation');
      }
    }
  });

  test('automated failure/repeat cases are explicitly separated from image accuracy', () {
    final automated = cases
        .where((item) => (item as Map<String, dynamic>)['validation'] == 'automated_contract')
        .map((item) => (item as Map<String, dynamic>)['category'])
        .toSet();
    expect(automated, containsAll(<String>['blank_or_invalid', 'ai_failure', 'duplicate_save']));
  });
}
