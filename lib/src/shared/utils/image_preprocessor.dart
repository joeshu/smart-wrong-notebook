import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show compute, debugPrint;
import 'package:image/image.dart' as image;

/// OCR / AI 分析前的图片预处理请求，用于在 isolate 间传递参数。
class _PreprocessRequest {
  const _PreprocessRequest(
    this.bytes,
    this.enableDeskew,
    this.enableBinarize,
  );

  final Uint8List bytes;
  final bool enableDeskew;
  final bool enableBinarize;
}

/// OCR / AI 分析前的图片预处理管线入口。
///
/// 在内部通过 [compute] 派发到后台 isolate 执行，避免阻塞 UI 线程。
/// 管线步骤：
/// 1. 用 `image` 包的 `decodeImage` 解码源字节
/// 2. （可选）轻度锐化（unsharp mask）+ 基于梯度方向直方图的旋转纠偏
/// 3. 灰度化
/// 4. （可选）Otsu 自适应阈值二值化，去除阴影与光照不均
/// 5. 3x3 中值滤波降噪，去除二值化后残留的孤立噪点
/// 6. 对比度拉伸，把像素值范围拉到 0-255
/// 7. 重新编码为 JPEG quality 90
///
/// 任一步骤抛错或 isolate 启动失败时，回退返回原始字节，调用方仍可
/// 继续走原 OCR / AI 流程。
Future<Uint8List> preprocessForOcr(
  Uint8List sourceBytes, {
  bool enableDeskew = true,
  bool enableBinarize = true,
}) async {
  if (sourceBytes.isEmpty) return sourceBytes;
  try {
    return await compute(
      _preprocessForOcrInIsolate,
      _PreprocessRequest(sourceBytes, enableDeskew, enableBinarize),
    );
  } catch (e, st) {
    // isolate 启动失败或序列化失败时回退原始字节，避免阻塞主流程
    debugPrint('[ImagePreprocessor] isolate fallback: $e\n$st');
    return sourceBytes;
  }
}

/// Isolate 入口：实际执行预处理管线。
Uint8List _preprocessForOcrInIsolate(_PreprocessRequest req) {
  try {
    final decoded = image.decodeImage(req.bytes);
    if (decoded == null) return req.bytes;
    image.Image img = decoded;

    // 2. 纠偏（轻度锐化 + 旋转矫正）
    if (req.enableDeskew) {
      img = _unsharpMask(img);
      img = _deskew(img);
    }

    // 3. 灰度化
    image.Image gray = image.grayscale(img);

    // 4. 二值化（Otsu 自适应阈值）
    if (req.enableBinarize) {
      gray = _otsuBinarize(gray);
    }

    // 5. 中值滤波降噪（3x3），去除二值化后残留的孤立噪点
    gray = _medianFilter3x3(gray);

    // 6. 对比度拉伸
    gray = _contrastStretch(gray);

    // 7. 重新编码 JPEG quality 90
    final encoded = image.encodeJpg(gray, quality: 90);
    return Uint8List.fromList(encoded);
  } catch (_) {
    return req.bytes;
  }
}

/// 轻度锐化（unsharp mask）。
///
/// 使用经典 3x3 锐化卷积核，提升文字边缘清晰度，便于后续 OCR。
image.Image _unsharpMask(image.Image src) {
  // 锐化核：中心 5，四邻 -1
  const filter = <double>[
    0, -1, 0,
    -1, 5, -1,
    0, -1, 0,
  ];
  return image.convolution(src, filter: filter, div: 1, offset: 0);
}

/// 简单旋转纠偏。
///
/// 算法：对降采样的灰度图做 Sobel 梯度，统计梯度方向在 [-45°, 45°] 区间
/// 的直方图，取峰值方向作为文档主方向，旋转该角度使主方向水平。
/// 最大旋转 ±10°，避免误判造成大幅旋转。
image.Image _deskew(image.Image src) {
  // 降采样以加速：最长边缩到 400 以内
  const maxDim = 400;
  final longestSide =
      src.width > src.height ? src.width : src.height;
  final scale = longestSide > maxDim ? maxDim / longestSide : 1.0;
  final small = scale < 1.0
      ? image.copyResize(src, width: (src.width * scale).round())
      : src;

  final gray = image.grayscale(small);
  final w = gray.width;
  final h = gray.height;
  if (w < 5 || h < 5) return src;

  // 角度直方图：[-45, 45] 共 90 个 bin，每 bin 1°
  const angleBins = 90;
  final hist = List<int>.filled(angleBins, 0);

  const gradientThreshold = 50.0; // 弱梯度视为噪声
  for (var y = 1; y < h - 1; y++) {
    for (var x = 1; x < w - 1; x++) {
      final p00 = gray.getPixel(x - 1, y - 1).r;
      final p01 = gray.getPixel(x, y - 1).r;
      final p02 = gray.getPixel(x + 1, y - 1).r;
      final p10 = gray.getPixel(x - 1, y).r;
      final p12 = gray.getPixel(x + 1, y).r;
      final p20 = gray.getPixel(x - 1, y + 1).r;
      final p21 = gray.getPixel(x, y + 1).r;
      final p22 = gray.getPixel(x + 1, y + 1).r;

      // Sobel Gx / Gy
      final gx = -p00 + p02 - 2 * p10 + 2 * p12 - p20 + p22;
      final gy = -p00 - 2 * p01 - p02 + p20 + 2 * p21 + p22;
      final mag = math.sqrt(gx * gx + gy * gy);
      if (mag < gradientThreshold) continue;

      var angle = math.atan2(gy, gx) * 180.0 / math.pi;
      // 文档主方向每隔 90° 等价，把角度归一到 [-45, 45]
      while (angle > 45) {
        angle -= 90;
      }
      while (angle < -45) {
        angle += 90;
      }
      final bin = (angle + 45).round();
      if (bin >= 0 && bin < angleBins) hist[bin]++;
    }
  }

  // 找直方图峰值，作为纠偏角度
  var maxBin = 0;
  var maxCount = 0;
  for (var i = 0; i < angleBins; i++) {
    if (hist[i] > maxCount) {
      maxCount = hist[i];
      maxBin = i;
    }
  }
  // 峰值计数太低说明没有明显方向，不旋转
  if (maxCount < 20) return src;

  final skewAngle = (maxBin - 45).toDouble();
  // 角度过小不旋转，避免无意义插值损失
  if (skewAngle.abs() < 0.5) return src;
  // 限制最大旋转角度，防止误判
  final clamped = skewAngle.clamp(-10.0, 10.0).toDouble();
  return image.copyRotate(src, angle: -clamped);
}

/// 3x3 中值滤波，去除孤立噪点（盐椒噪声）。
image.Image _medianFilter3x3(image.Image src) {
  final w = src.width;
  final h = src.height;
  if (w < 3 || h < 3) return src;
  final out = image.Image.from(src);

  final vals = List<num>.filled(9, 0);
  for (var y = 1; y < h - 1; y++) {
    for (var x = 1; x < w - 1; x++) {
      var k = 0;
      for (var dy = -1; dy <= 1; dy++) {
        for (var dx = -1; dx <= 1; dx++) {
          vals[k++] = src.getPixel(x + dx, y + dy).r;
        }
      }
      vals.sort();
      final m = vals[4].round().clamp(0, 255);
      out.setPixelR(x, y, m);
    }
  }
  return out;
}

/// Otsu 自适应阈值二值化。
///
/// 通过最大化类间方差自动选取全局阈值，把灰度图转成黑白图，
/// 去除阴影和光照不均。
image.Image _otsuBinarize(image.Image src) {
  final w = src.width;
  final h = src.height;
  final total = w * h;

  final hist = List<int>.filled(256, 0);
  for (final pixel in src) {
    final v = pixel.r.round().clamp(0, 255);
    hist[v]++;
  }

  var sum = 0;
  for (var i = 0; i < 256; i++) {
    sum += i * hist[i];
  }

  var sumB = 0;
  var wB = 0;
  var maxVar = 0.0;
  var threshold = 127;
  for (var t = 0; t < 256; t++) {
    wB += hist[t];
    if (wB == 0) continue;
    final wF = total - wB;
    if (wF == 0) break;
    sumB += t * hist[t];
    final mB = sumB / wB;
    final mF = (sum - sumB) / wF;
    final between = wB * wF * (mB - mF) * (mB - mF);
    if (between > maxVar) {
      maxVar = between;
      threshold = t;
    }
  }

  final out = image.Image(width: w, height: h, numChannels: src.numChannels);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final v = src.getPixel(x, y).r.round();
      final outV = v <= threshold ? 0 : 255;
      out.setPixelR(x, y, outV);
    }
  }
  return out;
}

/// 对比度拉伸：把像素值范围线性映射到 [0, 255]。
image.Image _contrastStretch(image.Image src) {
  var minV = 255;
  var maxV = 0;
  for (final pixel in src) {
    final v = pixel.r.round();
    if (v < minV) minV = v;
    if (v > maxV) maxV = v;
  }
  if (maxV <= minV) return src;
  final range = maxV - minV;

  final out = image.Image.from(src);
  for (var y = 0; y < src.height; y++) {
    for (var x = 0; x < src.width; x++) {
      final v = src.getPixel(x, y).r;
      final stretched =
          (((v - minV) * 255) / range).round().clamp(0, 255);
      out.setPixelR(x, y, stretched);
    }
  }
  return out;
}
