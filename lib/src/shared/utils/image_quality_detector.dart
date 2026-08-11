import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show compute;
import 'package:image/image.dart' as image;

/// 图片质量检测结果。
class ImageQualityResult {
  const ImageQualityResult({
    required this.isAcceptable,
    required this.sharpnessScore,
    required this.brightnessScore,
    required this.minDimensionPixels,
    required this.primaryIssue,
    this.issues = const <ImageQualityIssue>[],
    this.issueScores = const <ImageQualityIssue, double>{},
  });

  /// 总体是否可接受（无任何质量问题）。
  final bool isAcceptable;

  /// 锐度分数（0-1），由拉普拉斯方差归一化得到；越接近 1 越清晰。
  final double sharpnessScore;

  /// 亮度分数（0-1），由平均亮度归一化得到；0.3-0.7 为正常范围。
  final double brightnessScore;

  /// 图片最短边的像素数。
  final int minDimensionPixels;

  /// 主要质量问题（若有）。多个问题同时存在时取最严重的一个。
  final ImageQualityIssue? primaryIssue;

  /// 全部检测到的问题，按严重度从高到低排列。
  /// [primaryIssue] 为兼容旧调用，等同于本列表第一项。
  final List<ImageQualityIssue> issues;

  /// 各问题的置信/严重程度（0-1）。启发式结果只用于采集提示，不作为事实标签。
  final Map<ImageQualityIssue, double> issueScores;

  /// 遮挡或内容截断会使题目证据不可恢复，应先重拍而不是直接识别。
  bool get hasBlockingIssue => issues.any(
        (issue) => issue == ImageQualityIssue.occluded ||
            issue == ImageQualityIssue.contentCutOff,
      );
}

/// 图片质量问题的种类。
enum ImageQualityIssue {
  blurry,
  tooDark,
  tooBright,
  lowResolution,
  glare,
  unevenShadow,
  perspectiveDistortion,
  possiblePageCurvature,
  occluded,
  contentCutOff,
  possiblePersonalInfo,
}

/// 图片质量检测的阈值常量。
///
/// 这些阈值基于拍题场景的经验值，可按需调整。
class ImageQualityThresholds {
  const ImageQualityThresholds._();

  /// 拉普拉斯方差低于此值判定为模糊。
  static const double blurryVariance = 100.0;

  /// 用于将拉普拉斯方差映射到 0-1 分数的归一化上限。
  static const double sharpnessNormalization = 1000.0;

  /// 亮度低于此值判定为过暗。
  static const double tooDarkBrightness = 0.2;

  /// 亮度高于此值判定为过亮。
  static const double tooBrightBrightness = 0.85;

  /// 最短边低于此像素值判定为低分辨率。
  static const int lowResolutionPixels = 800;

  /// 检测时分析图像的最长边像素上限，避免大图在 isolate 中耗时过久。
  static const int maxAnalysisDimension = 768;

  static const double glarePixelRatio = .018;
  static const double shadowGridRange = .28;
  static const double edgeInkRatio = .075;
  static const double occlusionDarkRatio = .13;
}

/// 检测图片质量。
///
/// 在后台 isolate 中执行：解码图片，计算拉普拉斯方差（模糊）、平均亮度
/// （明暗）、最短边像素数（分辨率），返回 [ImageQualityResult]。
///
/// 如果文件不存在或解码失败，抛出 [StateError]。
Future<ImageQualityResult> detectImageQuality(String imagePath) {
  return compute(_detectImageQualityIsolate, imagePath);
}

ImageQualityResult _detectImageQualityIsolate(String imagePath) {
  final file = File(imagePath);
  if (!file.existsSync()) {
    throw StateError('图片文件不存在: $imagePath');
  }
  final decoded = image.decodeImage(file.readAsBytesSync());
  if (decoded == null) {
    throw StateError('无法解码图片: $imagePath');
  }

  final originalWidth = decoded.width;
  final originalHeight = decoded.height;
  final minDim = math.min(originalWidth, originalHeight);

  // 缩放到最长边 <= maxAnalysisDimension 用于分析（保留宽高比），避免
  // 4K 原图在 isolate 里跑拉普拉斯卷积耗时过久。
  image.Image working = decoded;
  final longestSide = math.max(originalWidth, originalHeight).toDouble();
  if (longestSide > ImageQualityThresholds.maxAnalysisDimension) {
    final scale = ImageQualityThresholds.maxAnalysisDimension / longestSide;
    final newWidth =
        (originalWidth * scale).round().clamp(1, originalWidth).toInt();
    final newHeight =
        (originalHeight * scale).round().clamp(1, originalHeight).toInt();
    working = image.copyResize(decoded, width: newWidth, height: newHeight);
  }

  final w = working.width;
  final h = working.height;

  // 计算灰度图（BT.601 luma）。
  final gray = List<double>.filled(w * h, 0.0);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final p = working.getPixel(x, y);
      gray[y * w + x] = 0.299 * p.r.toDouble() +
          0.587 * p.g.toDouble() +
          0.114 * p.b.toDouble();
    }
  }

  // 平均亮度归一化到 0-1。
  var sum = 0.0;
  for (final v in gray) {
    sum += v;
  }
  final meanBrightness = gray.isNotEmpty ? sum / gray.length : 0.0;
  final brightnessScore = (meanBrightness / 255.0).clamp(0.0, 1.0);

  // 拉普拉斯卷积：kernel = [0,1,0; 1,-4,1; 0,1,0]，仅在 [1, w-2] x [1, h-2]
  // 范围内计算（忽略边缘 1 像素）。同时累计一阶矩与二阶矩用于方差。
  var lapSum = 0.0;
  var lapSumSq = 0.0;
  var lapCount = 0;
  for (var y = 1; y < h - 1; y++) {
    for (var x = 1; x < w - 1; x++) {
      final center = gray[y * w + x];
      final up = gray[(y - 1) * w + x];
      final down = gray[(y + 1) * w + x];
      final left = gray[y * w + (x - 1)];
      final right = gray[y * w + (x + 1)];
      final lap = -4.0 * center + up + down + left + right;
      lapSum += lap;
      lapSumSq += lap * lap;
      lapCount++;
    }
  }
  final lapMean = lapCount > 0 ? lapSum / lapCount : 0.0;
  final lapVariance = lapCount > 0
      ? (lapSumSq / lapCount) - (lapMean * lapMean)
      : 0.0;

  final sharpnessScore =
      (lapVariance / ImageQualityThresholds.sharpnessNormalization)
          .clamp(0.0, 1.0);

  final issues = _detectIssues(
    lapVariance: lapVariance,
    brightness: brightnessScore,
    minDim: minDim,
    gray: gray,
    width: w,
    height: h,
    working: working,
  );
  final primaryIssue = issues.isEmpty ? null : issues.first;

  return ImageQualityResult(
    isAcceptable: primaryIssue == null,
    sharpnessScore: sharpnessScore,
    brightnessScore: brightnessScore,
    minDimensionPixels: minDim,
    primaryIssue: primaryIssue,
    issues: issues,
    issueScores: Map<ImageQualityIssue, double>.unmodifiable(
      _lastIssueScores,
    ),
  );
}

// isolate 内同步计算后立即复制进结果，避免对外暴露可变集合。
Map<ImageQualityIssue, double> _lastIssueScores =
    <ImageQualityIssue, double>{};

List<ImageQualityIssue> _detectIssues({
  required double lapVariance,
  required double brightness,
  required int minDim,
  required List<double> gray,
  required int width,
  required int height,
  required image.Image working,
}) {
  // 各问题的严重度（0-1，越大越严重）。
  final Map<ImageQualityIssue, double> severities = <ImageQualityIssue, double>{};

  if (lapVariance < ImageQualityThresholds.blurryVariance) {
    severities[ImageQualityIssue.blurry] =
        ((ImageQualityThresholds.blurryVariance - lapVariance) /
                ImageQualityThresholds.blurryVariance)
            .clamp(0.0, 1.0);
  }

  if (brightness < ImageQualityThresholds.tooDarkBrightness) {
    severities[ImageQualityIssue.tooDark] =
        ((ImageQualityThresholds.tooDarkBrightness - brightness) /
                ImageQualityThresholds.tooDarkBrightness)
            .clamp(0.0, 1.0);
  }

  if (brightness > ImageQualityThresholds.tooBrightBrightness) {
    severities[ImageQualityIssue.tooBright] =
        ((brightness - ImageQualityThresholds.tooBrightBrightness) /
                (1.0 - ImageQualityThresholds.tooBrightBrightness))
            .clamp(0.0, 1.0);
  }

  if (minDim < ImageQualityThresholds.lowResolutionPixels) {
    severities[ImageQualityIssue.lowResolution] =
        ((ImageQualityThresholds.lowResolutionPixels - minDim) /
                ImageQualityThresholds.lowResolutionPixels)
            .clamp(0.0, 1.0);
  }

  if (width >= 24 && height >= 24) {
    final scene = _detectSceneIssues(gray, width, height, working);
    for (final entry in scene.entries) {
      final previous = severities[entry.key] ?? 0;
      if (entry.value > previous) severities[entry.key] = entry.value;
    }
  }

  final entries = severities.entries.toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  _lastIssueScores = Map<ImageQualityIssue, double>.fromEntries(entries);
  return List<ImageQualityIssue>.unmodifiable(
    entries.map((entry) => entry.key),
  );
}

Map<ImageQualityIssue, double> _detectSceneIssues(
  List<double> gray,
  int width,
  int height,
  image.Image working,
) {
  final result = <ImageQualityIssue, double>{};
  final cellMeans = <double>[];
  const grid = 4;
  for (var gy = 0; gy < grid; gy++) {
    for (var gx = 0; gx < grid; gx++) {
      var sum = 0.0;
      var count = 0;
      final y0 = gy * height ~/ grid;
      final y1 = (gy + 1) * height ~/ grid;
      final x0 = gx * width ~/ grid;
      final x1 = (gx + 1) * width ~/ grid;
      for (var y = y0; y < y1; y += 2) {
        for (var x = x0; x < x1; x += 2) {
          final value = gray[y * width + x];
          if (value > 18 && value < 242) {
            sum += value;
            count++;
          }
        }
      }
      if (count > 0) cellMeans.add(sum / count / 255.0);
    }
  }
  if (cellMeans.length >= 8) {
    final range = cellMeans.reduce(math.max) - cellMeans.reduce(math.min);
    if (range > ImageQualityThresholds.shadowGridRange) {
      result[ImageQualityIssue.unevenShadow] =
          ((range - .28) / .45).clamp(0.0, 1.0);
    }
  }

  var glare = 0;
  var darkCenter = 0;
  var centerCount = 0;
  for (var y = 0; y < height; y += 2) {
    for (var x = 0; x < width; x += 2) {
      final p = working.getPixel(x, y);
      final maxChannel = math.max(
        p.r.toDouble(),
        math.max(p.g.toDouble(), p.b.toDouble()),
      );
      final minChannel = math.min(
        p.r.toDouble(),
        math.min(p.g.toDouble(), p.b.toDouble()),
      );
      if (maxChannel > 248 && maxChannel - minChannel < 9) glare++;
      if (x > width * .18 && x < width * .82 &&
          y > height * .18 && y < height * .82) {
        centerCount++;
        if (gray[y * width + x] < 32) darkCenter++;
      }
    }
  }
  final sampled = ((width + 1) ~/ 2) * ((height + 1) ~/ 2);
  final glareRatio = sampled == 0 ? 0.0 : glare / sampled;
  if (glareRatio > ImageQualityThresholds.glarePixelRatio && glareRatio < .42) {
    result[ImageQualityIssue.glare] =
        ((glareRatio - .018) / .12).clamp(0.0, 1.0);
  }
  final darkRatio = centerCount == 0 ? 0.0 : darkCenter / centerCount;
  if (darkRatio > ImageQualityThresholds.occlusionDarkRatio) {
    result[ImageQualityIssue.occluded] =
        ((darkRatio - .13) / .35).clamp(0.0, 1.0);
  }

  final edge = math.max(3, math.min(width, height) ~/ 40);
  var edgeInk = 0;
  var edgeCount = 0;
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      if (x >= edge &&
          x < width - edge &&
          y >= edge &&
          y < height - edge) {
        continue;
      }
      edgeCount++;
      if (gray[y * width + x] < 105) edgeInk++;
    }
  }
  final edgeInkRatio = edgeCount == 0 ? 0.0 : edgeInk / edgeCount;
  if (edgeInkRatio > ImageQualityThresholds.edgeInkRatio) {
    result[ImageQualityIssue.contentCutOff] =
        ((edgeInkRatio - .075) / .22).clamp(0.0, 1.0);
  }

  // 估算每个扫描行中亮纸区域的左右边界。线性漂移代表梯形透视，非线性
  // 波动代表书页弯曲。只有足够多行能找到双边界时才报告，避免把满幅白底误判。
  final left = <double>[];
  final right = <double>[];
  for (var y = 0; y < height; y += math.max(2, height ~/ 80)) {
    var l = -1;
    var r = -1;
    for (var x = 0; x < width; x++) {
      if (gray[y * width + x] > 165) {
        l = x;
        break;
      }
    }
    for (var x = width - 1; x >= 0; x--) {
      if (gray[y * width + x] > 165) {
        r = x;
        break;
      }
    }
    if (l > 1 && r > l && r < width - 2) {
      left.add(l / width);
      right.add(r / width);
    }
  }
  if (left.length >= 12) {
    final third = math.max(1, left.length ~/ 3);
    double avg(List<double> values) =>
        values.reduce((a, b) => a + b) / values.length;
    final topWidth = avg(right.sublist(0, third)) - avg(left.sublist(0, third));
    final bottomWidth = avg(right.sublist(left.length - third)) -
        avg(left.sublist(left.length - third));
    final widthDelta = (topWidth - bottomWidth).abs();
    if (widthDelta > .09) {
      result[ImageQualityIssue.perspectiveDistortion] =
          ((widthDelta - .09) / .3).clamp(0.0, 1.0);
    }
    final mid = left.length ~/ 2;
    final expectedLeft = (left.first + left.last) / 2;
    final expectedRight = (right.first + right.last) / 2;
    final bend = math.max((left[mid] - expectedLeft).abs(),
        (right[mid] - expectedRight).abs());
    if (bend > .035) {
      result[ImageQualityIssue.possiblePageCurvature] =
          ((bend - .035) / .16).clamp(0.0, 1.0);
    }
  }

  // 页眉密集内容只触发隐私复核，不推断具体姓名、学校或身份。
  var headerInk = 0;
  var headerCount = 0;
  final headerEnd = math.max(1, (height * .16).round());
  for (var y = 0; y < headerEnd; y += 2) {
    for (var x = width ~/ 5; x < width * 4 ~/ 5; x += 2) {
      headerCount++;
      final v = gray[y * width + x];
      if (v > 35 && v < 150) headerInk++;
    }
  }
  final headerInkRatio = headerCount == 0 ? 0.0 : headerInk / headerCount;
  if (headerInkRatio > .055 && headerInkRatio < .32) {
    result[ImageQualityIssue.possiblePersonalInfo] =
        ((headerInkRatio - .055) / .16).clamp(0.0, 1.0);
  }
  return result;
}
