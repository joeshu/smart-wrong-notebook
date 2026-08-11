import 'dart:convert';
import 'dart:io';

import 'package:smart_wrong_notebook/src/domain/services/recognition_accuracy_metrics.dart';

/// Generates a local, privacy-safe recognition report from human annotations.
/// Pending manifests deliberately produce `pending` instead of numeric scores.
void main(List<String> arguments) {
  final manifestPath = arguments.isEmpty
      ? 'test/fixtures/accuracy_manifest.json'
      : arguments.first;
  final outputPath = arguments.length < 2 ? null : arguments[1];
  final manifestFile = File(manifestPath);
  if (!manifestFile.existsSync()) {
    stderr.writeln('Manifest not found: $manifestPath');
    exitCode = 2;
    return;
  }
  final decoded = jsonDecode(manifestFile.readAsStringSync());
  if (decoded is! Map<String, dynamic>) {
    stderr.writeln('Manifest root must be a JSON object');
    exitCode = 2;
    return;
  }
  final report = RecognitionAccuracyMetrics.evaluateManifest(decoded);
  final validationErrors = RecognitionAccuracyMetrics.validateManifest(decoded);
  final markdown = report.toMarkdown();
  if (outputPath == null) {
    stdout.write(markdown);
  } else {
    File(outputPath).writeAsStringSync(markdown, flush: true);
    stdout.writeln('Recognition report written to $outputPath');
  }
  if (validationErrors.isNotEmpty) exitCode = 1;
}
