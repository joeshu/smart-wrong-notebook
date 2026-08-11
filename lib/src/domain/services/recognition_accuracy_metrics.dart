/// Pure, dependency-free metrics for the recognition accuracy fixture manifest.
///
/// This deliberately does not turn model confidence into accuracy.  Until the
/// manifest is human annotated, [evaluateManifest] returns pending metrics.
class RecognitionMetricValue {
  const RecognitionMetricValue.pending(this.reason)
      : status = 'pending',
        value = null;

  const RecognitionMetricValue.ready(this.value)
      : status = 'ready',
        reason = null;

  final String status;
  final double? value;
  final String? reason;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'status': status,
        'value': value,
        if (reason != null) 'reason': reason,
      };
}

class RecognitionAccuracyReport {
  const RecognitionAccuracyReport({
    required this.annotationStatus,
    required this.metrics,
    required this.errors,
    this.strata = const <String, Map<String, RecognitionMetricValue>>{},
    this.caseCount = 0,
    this.manualCaseCount = 0,
    this.automatedCaseCount = 0,
  });

  final String annotationStatus;
  final Map<String, RecognitionMetricValue> metrics;
  final List<String> errors;
  final Map<String, Map<String, RecognitionMetricValue>> strata;
  final int caseCount;
  final int manualCaseCount;
  final int automatedCaseCount;

  bool get isPending => metrics.values.any((metric) => metric.status == 'pending');

  Map<String, dynamic> toJson() => <String, dynamic>{
        'annotationStatus': annotationStatus,
        'metrics': metrics.map(
          (key, value) => MapEntry<String, dynamic>(key, value.toJson()),
        ),
        'errors': errors,
        'coverage': <String, int>{
          'cases': caseCount,
          'manual': manualCaseCount,
          'automated': automatedCaseCount,
        },
        'strata': strata.map(
          (key, value) => MapEntry<String, dynamic>(
            key,
            value.map((name, metric) => MapEntry<String, dynamic>(name, metric.toJson())),
          ),
        ),
      };

  String toMarkdown() {
    String value(RecognitionMetricValue metric) => metric.value == null
        ? 'pending — ${metric.reason ?? 'no measurement'}'
        : '${(metric.value! * 100).toStringAsFixed(2)}%';
    final buffer = StringBuffer()
      ..writeln('# 识别质量验收报告')
      ..writeln()
      ..writeln('- 标注状态：`$annotationStatus`')
      ..writeln('- 样例覆盖：$caseCount（人工 $manualCaseCount，自动契约 $automatedCaseCount）')
      ..writeln()
      ..writeln('| 指标 | 结果 |')
      ..writeln('|---|---|');
    for (final entry in metrics.entries) {
      buffer.writeln('| `${entry.key}` | ${value(entry.value)} |');
    }
    if (strata.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('## 分组')
        ..writeln();
      for (final entry in strata.entries) {
        buffer.writeln('- `${entry.key}`：${entry.value.values.every((item) => item.value == null) ? 'pending' : 'ready'}');
      }
    }
    if (errors.isNotEmpty) {
      buffer
        ..writeln()
        ..writeln('## 待办')
        ..writeln();
      for (final error in errors) {
        buffer.writeln('- $error');
      }
    }
    return buffer.toString();
  }
}

/// Computes only metrics backed by explicit human annotations and observations.
///
/// The v1 manifest has no observations and is intentionally pending. A future
/// manifest can provide `annotationStatus: completed` and a top-level
/// `measurements` list with the fields documented in [evaluateManifest].
class RecognitionAccuracyMetrics {
  static const metricNames = <String>[
    'boxIoU',
    'ocrCharacterAccuracy',
    'formulaCompleteness',
    'tableStructureAccuracy',
    'userModificationRate',
    'duplicateAiCallRate',
    'saveCompletenessRate',
    'recoveryRate',
  ];

  static RecognitionAccuracyReport evaluateManifest(
    Map<String, dynamic> manifest,
  ) {
    final errors = validateManifest(manifest);
    final rawAnnotationStatus = manifest['annotationStatus'];
    final annotationStatus =
        rawAnnotationStatus is String ? rawAnnotationStatus : 'missing';
    final rawMeasurements = manifest['measurements'];
    if (errors.isNotEmpty) {
      return _pending(manifest, annotationStatus, errors);
    }
    if (annotationStatus != 'completed' || rawMeasurements is! List<dynamic>) {
      return _pending(
        manifest,
        annotationStatus,
        <String>[
          if (annotationStatus != 'completed')
            'human annotation is not completed',
          if (rawMeasurements is! List<dynamic>)
            'measurements are not present',
        ],
      );
    }

    final measurements = rawMeasurements.whereType<Map<String, dynamic>>().toList();
    if (measurements.isEmpty) {
      return _pending(
        manifest,
        annotationStatus,
        <String>['measurements are empty'],
      );
    }
    return RecognitionAccuracyReport(
      annotationStatus: annotationStatus,
      metrics: <String, RecognitionMetricValue>{
        'boxIoU': _mean(measurements, 'boxIoU'),
        'ocrCharacterAccuracy': _mean(measurements, 'ocrCharacterAccuracy'),
        'formulaCompleteness': _mean(measurements, 'formulaCompleteness'),
        'tableStructureAccuracy': _mean(measurements, 'tableStructureAccuracy'),
        'userModificationRate': _rate(measurements, 'userModified'),
        'duplicateAiCallRate': _rate(measurements, 'duplicateAiCall'),
        'saveCompletenessRate': _rate(measurements, 'saveComplete'),
        'recoveryRate': _rate(measurements, 'recovered'),
      },
      errors: const <String>[],
      strata: _stratify(measurements),
      caseCount: (manifest['cases'] as List<dynamic>).length,
      manualCaseCount: _caseCount(manifest, 'manual_required'),
      automatedCaseCount: _caseCount(manifest, 'automated_contract'),
    );
  }

  static List<String> validateManifest(Map<String, dynamic> manifest) {
    final errors = <String>[];
    if (manifest['manifestVersion'] is! int || (manifest['manifestVersion'] as int) <= 0) {
      errors.add('manifestVersion must be a positive integer');
    }
    final annotationStatus = manifest['annotationStatus'];
    if (annotationStatus is! String ||
        !<String>['pending_human_annotation', 'completed'].contains(annotationStatus)) {
      errors.add('annotationStatus must be pending_human_annotation or completed');
    }
    final cases = manifest['cases'];
    if (cases is! List<dynamic>) return <String>['cases must be a list'];
    final ids = <String>{};
    for (var index = 0; index < cases.length; index++) {
      final item = cases[index];
      if (item is! Map<String, dynamic>) {
        errors.add('cases[$index] must be an object');
        continue;
      }
      final id = item['id'];
      if (id is! String || id.isEmpty || !ids.add(id)) {
        errors.add('cases[$index] has a missing or duplicate id');
      }
      if (item['category'] is! String || (item['category'] as String).isEmpty) {
        errors.add('cases[$index].category must be non-empty');
      }
      if (!<String>['manual_required', 'automated_contract'].contains(item['validation'])) {
        errors.add('cases[$index].validation must be manual_required or automated_contract');
      }
      if (item['expected'] is! Map<String, dynamic>) {
        errors.add('cases[$index].expected must be an object');
      }
      if (item['validation'] == 'manual_required' &&
          (item['notes'] is! String || (item['notes'] as String).trim().isEmpty)) {
        errors.add('cases[$index].notes must describe the human annotation source');
      }
      for (final field in <String>['captureMode', 'engine', 'engineVersion']) {
        if (item[field] is! String || (item[field] as String).isEmpty) {
          errors.add('cases[$index].$field must be non-empty');
        }
      }
      final imagePath = item['imagePath'];
      if (imagePath != null && (imagePath is! String || !imagePath.startsWith('test/fixtures/accuracy/'))) {
        errors.add('cases[$index].imagePath must use the accuracy fixture directory');
      }
    }
    final rawMeasurements = manifest['measurements'];
    if (rawMeasurements is List<dynamic>) {
      final caseById = <String, Map<String, dynamic>>{
        for (final item in cases.whereType<Map<String, dynamic>>() )
          if (item['id'] is String) item['id'] as String: item,
      };
      final caseIds = caseById.keys.toSet();
      final measuredIds = <String>{};
      for (var index = 0; index < rawMeasurements.length; index++) {
        final row = rawMeasurements[index];
        if (row is! Map<String, dynamic>) {
          errors.add('measurements[$index] must be an object');
          continue;
        }
        final caseId = row['caseId'];
        if (caseId is! String || !caseIds.contains(caseId) || !measuredIds.add(caseId)) {
          errors.add('measurements[$index].caseId must uniquely reference a case');
        }
        final expectedCase = caseById[caseId];
        if (expectedCase != null) {
          for (final field in <String>['captureMode', 'engine', 'engineVersion']) {
            if (row[field] != expectedCase[field]) {
              errors.add('measurements[$index].$field must match case $caseId');
            }
          }
        }
        for (final field in <String>['boxIoU', 'ocrCharacterAccuracy', 'formulaCompleteness', 'tableStructureAccuracy']) {
          final value = row[field];
          if (value is! num || value < 0 || value > 1) {
            errors.add('measurements[$index].$field must be between 0 and 1');
          }
        }
        for (final field in <String>['userModified', 'duplicateAiCall', 'saveComplete', 'recovered']) {
          if (row[field] is! bool) errors.add('measurements[$index].$field must be boolean');
        }
        for (final field in <String>['captureMode', 'engine', 'engineVersion']) {
          if (row[field] is! String || (row[field] as String).isEmpty) {
            errors.add('measurements[$index].$field must be non-empty');
          }
        }
      }
      if (measuredIds.length != caseIds.length) errors.add('measurements must have exactly one row per case');
    } else if (rawMeasurements != null) {
      errors.add('measurements must be a list');
    }
    return errors;
  }

  static double? intersectionOverUnion(
    double left,
    double top,
    double right,
    double bottom,
    double otherLeft,
    double otherTop,
    double otherRight,
    double otherBottom,
  ) {
    final intersectionWidth = (right < otherRight ? right : otherRight) -
        (left > otherLeft ? left : otherLeft);
    final intersectionHeight = (bottom < otherBottom ? bottom : otherBottom) -
        (top > otherTop ? top : otherTop);
    if (intersectionWidth <= 0 || intersectionHeight <= 0) return 0;
    final intersection = intersectionWidth * intersectionHeight;
    final area = (right - left) * (bottom - top);
    final otherArea = (otherRight - otherLeft) * (otherBottom - otherTop);
    final union = area + otherArea - intersection;
    return union <= 0 ? 0 : intersection / union;
  }

  static double characterAccuracy(String expected, String actual) {
    if (expected.isEmpty) return actual.isEmpty ? 1 : 0;
    final distance = _levenshtein(expected, actual);
    return (1 - distance / expected.length).clamp(0, 1).toDouble();
  }

  static double formulaCompleteness({
    required bool boundaryPreserved,
    required bool pairedMarkersPreserved,
    required bool keySymbolsPreserved,
  }) =>
      [boundaryPreserved, pairedMarkersPreserved, keySymbolsPreserved]
          .where((value) => value)
          .length /
      3;

  static double tableStructureAccuracy({
    required int expectedRows,
    required int expectedColumns,
    required int actualRows,
    required int actualColumns,
  }) {
    if (expectedRows <= 0 || expectedColumns <= 0) return 0;
    final rowScore = 1 - (expectedRows - actualRows).abs() / expectedRows;
    final columnScore = 1 - (expectedColumns - actualColumns).abs() / expectedColumns;
    return ((rowScore + columnScore) / 2).clamp(0, 1).toDouble();
  }

  static RecognitionAccuracyReport _pending(
    Map<String, dynamic> manifest,
    String status,
    List<String> reasons,
  ) =>
      RecognitionAccuracyReport(
        annotationStatus: status,
        metrics: <String, RecognitionMetricValue>{
          for (final name in metricNames)
            name: RecognitionMetricValue.pending(reasons.join('; ')),
        },
        errors: reasons,
        strata: _pendingStrata(manifest, reasons),
        caseCount: _cases(manifest).length,
        manualCaseCount: _caseCount(manifest, 'manual_required'),
        automatedCaseCount: _caseCount(manifest, 'automated_contract'),
      );

  static int _caseCount(Map<String, dynamic> manifest, String validation) =>
      _cases(manifest)
          .whereType<Map<String, dynamic>>()
          .where((item) => item['validation'] == validation)
          .length;

  static Map<String, Map<String, RecognitionMetricValue>> _pendingStrata(
    Map<String, dynamic> manifest,
    List<String> reasons,
  ) {
    final keys = _cases(manifest)
        .whereType<Map<String, dynamic>>()
        .map((item) =>
            '${item['captureMode']}|${item['engine']}|${item['engineVersion']}')
        .toSet();
    return <String, Map<String, RecognitionMetricValue>>{
      for (final key in keys)
        key: <String, RecognitionMetricValue>{
          for (final name in metricNames)
            name: RecognitionMetricValue.pending(reasons.join('; ')),
        },
    };
  }

  static List<dynamic> _cases(Map<String, dynamic> manifest) {
    final value = manifest['cases'];
    return value is List<dynamic> ? value : const <dynamic>[];
  }

  static RecognitionMetricValue _mean(List<Map<String, dynamic>> rows, String key) {
    final values = rows.map((row) => row[key]).whereType<num>().toList();
    if (values.isEmpty) return const RecognitionMetricValue.pending('no measurements');
    return RecognitionMetricValue.ready(
      values.map((value) => value.toDouble()).reduce((a, b) => a + b) / values.length,
    );
  }

  static RecognitionMetricValue _rate(List<Map<String, dynamic>> rows, String key) {
    final values = rows.map((row) => row[key]).whereType<bool>().toList();
    if (values.isEmpty) return const RecognitionMetricValue.pending('no measurements');
    return RecognitionMetricValue.ready(
      values.where((value) => value).length / values.length,
    );
  }

  static Map<String, Map<String, RecognitionMetricValue>> _stratify(
    List<Map<String, dynamic>> rows,
  ) {
    final grouped = <String, List<Map<String, dynamic>>>{};
    for (final row in rows) {
      final key = '${row['captureMode']}|${row['engine']}|${row['engineVersion']}';
      grouped.putIfAbsent(key, () => <Map<String, dynamic>>[]).add(row);
    }
    return grouped.map(
      (key, group) => MapEntry<String, Map<String, RecognitionMetricValue>>(
        key,
        <String, RecognitionMetricValue>{
          'boxIoU': _mean(group, 'boxIoU'),
          'ocrCharacterAccuracy': _mean(group, 'ocrCharacterAccuracy'),
          'formulaCompleteness': _mean(group, 'formulaCompleteness'),
          'tableStructureAccuracy': _mean(group, 'tableStructureAccuracy'),
          'userModificationRate': _rate(group, 'userModified'),
          'duplicateAiCallRate': _rate(group, 'duplicateAiCall'),
          'saveCompletenessRate': _rate(group, 'saveComplete'),
          'recoveryRate': _rate(group, 'recovered'),
        },
      ),
    );
  }

  static int _levenshtein(String a, String b) {
    var previous = List<int>.generate(b.length + 1, (index) => index);
    for (var i = 0; i < a.length; i++) {
      final current = List<int>.filled(b.length + 1, 0)..[0] = i + 1;
      for (var j = 0; j < b.length; j++) {
        current[j + 1] = [
          current[j] + 1,
          previous[j + 1] + 1,
          previous[j] + (a[i] == b[j] ? 0 : 1),
        ].reduce((x, y) => x < y ? x : y);
      }
      previous = current;
    }
    return previous[b.length];
  }
}
