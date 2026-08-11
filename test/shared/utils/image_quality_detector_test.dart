import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as image;
import 'package:smart_wrong_notebook/src/shared/utils/image_quality_detector.dart';

void main() {
  test('quality detector retains all simultaneous issues', () async {
    final directory = await Directory.systemTemp.createTemp('quality-test-');
    addTearDown(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });
    final file = File('${directory.path}/dark-small.png');
    final source = image.Image(width: 320, height: 240);
    image.fill(source, color: image.ColorRgb8(0, 0, 0));
    await file.writeAsBytes(image.encodePng(source));

    final result = await detectImageQuality(file.path);

    expect(result.isAcceptable, isFalse);
    expect(result.primaryIssue, result.issues.first);
    expect(
      result.issues,
      containsAll(<ImageQualityIssue>[
        ImageQualityIssue.blurry,
        ImageQualityIssue.tooDark,
        ImageQualityIssue.lowResolution,
      ]),
    );
  });

  test('edge content and central occlusion are blocking capture issues',
      () async {
    final directory = await Directory.systemTemp.createTemp('quality-block-');
    addTearDown(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });
    final file = File('${directory.path}/blocked.png');
    final source = image.Image(width: 1000, height: 1000);
    image.fill(source, color: image.ColorRgb8(220, 220, 220));
    image.fillRect(source,
        x1: 0,
        y1: 0,
        x2: 999,
        y2: 45,
        color: image.ColorRgb8(20, 20, 20));
    image.fillRect(source,
        x1: 0,
        y1: 955,
        x2: 999,
        y2: 999,
        color: image.ColorRgb8(20, 20, 20));
    image.fillRect(source,
        x1: 300,
        y1: 300,
        x2: 700,
        y2: 700,
        color: image.ColorRgb8(5, 5, 5));
    await file.writeAsBytes(image.encodePng(source));

    final result = await detectImageQuality(file.path);

    expect(result.issues, contains(ImageQualityIssue.contentCutOff));
    expect(result.issues, contains(ImageQualityIssue.occluded));
    expect(result.hasBlockingIssue, isTrue);
    expect(result.issueScores[ImageQualityIssue.occluded], greaterThan(0));
  });

  test('local white hotspot is reported separately from global brightness', () async {
    final directory = await Directory.systemTemp.createTemp('quality-glare-');
    addTearDown(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });
    final file = File('${directory.path}/glare.png');
    final source = image.Image(width: 1000, height: 1000);
    image.fill(source, color: image.ColorRgb8(185, 185, 185));
    image.fillRect(source,
        x1: 360,
        y1: 360,
        x2: 600,
        y2: 600,
        color: image.ColorRgb8(255, 255, 255));
    await file.writeAsBytes(image.encodePng(source));

    final result = await detectImageQuality(file.path);

    expect(result.issues, contains(ImageQualityIssue.glare));
    expect(result.issues, isNot(contains(ImageQualityIssue.tooBright)));
  });
}
