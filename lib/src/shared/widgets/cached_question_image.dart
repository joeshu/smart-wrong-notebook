import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart' show compute;
import 'package:flutter/material.dart';
import 'package:image/image.dart' as image;

/// 带内存缓存的本地图片 widget。
///
/// - 首次加载时在后台 isolate 把原图解码并缩放到 [maxWidth]（默认 1400px），
///   重新编码为 JPEG/PNG，避免列表/详情页加载 4K 原图导致内存峰值与卡顿。
/// - 缩放后的字节数据按文件路径+mtime 做 LRU 内存缓存，二次进入秒开。
/// - [highRes=true] 时跳过缩放，用于需要看原图细节的 InteractiveViewer 场景。
/// - 失败时按 [ImageLoadFailure] 区分附件缺失/路径失效/解码失败/异常，
///   并在 [onReselect] 提供时显示「重新选图」入口。
class CachedQuestionImage extends StatefulWidget {
  const CachedQuestionImage(
    this.path, {
    super.key,
    this.fit = BoxFit.contain,
    this.maxWidth = 1400,
    this.highRes = false,
    this.borderRadius,
    this.errorMessage,
    this.onReselect,
    this.filename,
  });

  final String path;
  final BoxFit fit;
  final int maxWidth;

  /// 是否加载原图（不缩放）。用于 InteractiveViewer 等需要细节的场景。
  final bool highRes;

  /// 可选圆角，包装在 ClipRRect 里。
  final BorderRadius? borderRadius;

  /// 自定义错误信息（覆盖默认的失败原因文案）。
  final String? errorMessage;

  /// 失败时显示「重新选图」入口；为空则不显示按钮。
  /// 用于详情页/工作台等需要让用户重新绑定原图的场景。
  final VoidCallback? onReselect;

  /// 可选的原图文件名，失败时一并展示，方便用户定位问题附件。
  final String? filename;
  @override
  State<CachedQuestionImage> createState() => _CachedQuestionImageState();

  /// 简易 LRU 缓存：path → 缩略图字节。最多保留 40 张。
  static final _BoundedMap<String, Uint8List> _cache =
      _BoundedMap<String, Uint8List>(maxSize: 40);
}

class _CachedQuestionImageState extends State<CachedQuestionImage> {
  Uint8List? _bytes;
  bool _loading = true;
  ImageLoadFailure? _failure;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(covariant CachedQuestionImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path ||
        oldWidget.maxWidth != widget.maxWidth ||
        oldWidget.highRes != widget.highRes) {
      _load();
    }
  }

  Future<void> _load() async {
    final path = widget.path;
    // 空路径或文件不存在时直接进入错误态，避免在测试/无图场景下仍 spawn
    // isolate 去读不存在的文件，导致 pumpAndSettle 等待 isolate 超时。
    if (path.isEmpty) {
      if (mounted) {
        setState(() {
          _bytes = null;
          _loading = false;
          _failure = ImageLoadFailure.emptyPath;
        });
      }
      return;
    }
    final cacheKey = '${widget.highRes ? 'hr' : 'th'}:$path';
    final cached = CachedQuestionImage._cache[cacheKey];
    if (cached != null) {
      if (mounted) {
        setState(() {
          _bytes = cached;
          _loading = false;
          _failure = null;
        });
      }
      return;
    }
    final file = File(path);
    if (!file.existsSync()) {
      if (mounted) {
        setState(() {
          _bytes = null;
          _loading = false;
          _failure = ImageLoadFailure.notFound;
        });
      }
      return;
    }
    if (mounted) setState(() => _loading = true);
    try {
      final result = await compute(
        _decodeAndScale,
        _ScaleRequest(path, widget.maxWidth, widget.highRes),
      );
      if (result != null) {
        CachedQuestionImage._cache[cacheKey] = result;
      }
      if (mounted) {
        setState(() {
          _bytes = result;
          _loading = false;
          _failure = result == null ? ImageLoadFailure.decodeFailed : null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _failure = ImageLoadFailure.exception;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    Widget content;
    if (_loading) {
      content = const Center(child: CircularProgressIndicator(strokeWidth: 2));
    } else if (_bytes != null) {
      content = Image.memory(_bytes!, fit: widget.fit);
    } else {
      content = _ImageFailureCard(
        failure: _failure ?? ImageLoadFailure.emptyPath,
        errorMessage: widget.errorMessage,
        onReselect: widget.onReselect,
        filename: widget.filename,
      );
    }
    if (widget.borderRadius != null) {
      return ClipRRect(borderRadius: widget.borderRadius!, child: content);
    }
    return content;
  }
}

/// 图片加载失败的原因分类。
///
/// 详情页/工作台/放大态共用同一套文案与图标，避免每个调用方各自硬编码。
enum ImageLoadFailure {
  /// 路径为空：从未保存原图。
  emptyPath,

  /// 路径失效：原图文件已被移动或删除。
  notFound,

  /// 解码失败：文件存在但无法解析（损坏或格式不支持）。
  decodeFailed,

  /// 其他异常（isolate 抛出）。
  exception;

  String get label {
    switch (this) {
      case ImageLoadFailure.emptyPath:
        return '附件缺失：未保存原图，仅保留识别文本与 AI 分析';
      case ImageLoadFailure.notFound:
        return '路径失效：原图已被移动或删除，可重新选图绑定';
      case ImageLoadFailure.decodeFailed:
        return '解码失败：原图损坏或格式不支持，建议重新拍摄或选图';
      case ImageLoadFailure.exception:
        return '加载异常：请重试或检查原图文件';
    }
  }

  IconData get icon {
    switch (this) {
      case ImageLoadFailure.emptyPath:
        return CupertinoIcons.photo;
      case ImageLoadFailure.notFound:
        return CupertinoIcons.link;
      case ImageLoadFailure.decodeFailed:
        return CupertinoIcons.photo;
      case ImageLoadFailure.exception:
        return CupertinoIcons.exclamationmark_circle;
    }
  }

  Color get color => const Color(0xFFDC2626);
}

/// 统一的图片失败卡片：图标 + 文案 + 可选文件名 + 可选「重新选图」入口。
///
/// 列表缩略图、详情页图框、放大态错误页都复用此组件，保证附件相关错误
/// 的视觉与措辞一致。
class _ImageFailureCard extends StatelessWidget {
  const _ImageFailureCard({
    required this.failure,
    required this.errorMessage,
    required this.onReselect,
    required this.filename,
  });

  final ImageLoadFailure failure;
  final String? errorMessage;
  final VoidCallback? onReselect;
  final String? filename;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final text = errorMessage ?? failure.label;
    final backgroundColor =
        isDark ? const Color(0xFF1F1414) : const Color(0xFFFEF2F2);

    return LayoutBuilder(
      builder: (context, constraints) {
        final compactHeight =
            constraints.maxHeight.isFinite && constraints.maxHeight < 96;
        final compactWidth =
            constraints.maxWidth.isFinite && constraints.maxWidth < 120;
        if (compactHeight || compactWidth) {
          final icon = Icon(failure.icon, size: 22, color: failure.color);
          return Semantics(
            label: text,
            button: onReselect != null,
            child: Tooltip(
              message: text,
              child: Material(
                color: backgroundColor,
                child: InkWell(
                  onTap: onReselect,
                  child: Center(child: icon),
                ),
              ),
            ),
          );
        }

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          color: backgroundColor,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(failure.icon, size: 28, color: failure.color),
              const SizedBox(height: 6),
              Text(
                text,
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: failure.color),
              ),
              if (filename != null && filename!.isNotEmpty) ...<Widget>[
                const SizedBox(height: 4),
                Text(
                  '文件：$filename',
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 10,
                    color: isDark
                        ? const Color(0xFFA1A1AA)
                        : const Color(0xFF6B7280),
                  ),
                ),
              ],
              if (onReselect != null) ...<Widget>[
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: onReselect,
                  icon:
                      const Icon(CupertinoIcons.photo_on_rectangle, size: 14),
                  label:
                      const Text('重新选图', style: TextStyle(fontSize: 11)),
                  style: TextButton.styleFrom(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                    minimumSize: const Size(0, 24),
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _ScaleRequest {
  const _ScaleRequest(this.path, this.maxWidth, this.highRes);
  final String path;
  final int maxWidth;
  final bool highRes;
}

/// 在后台 isolate 执行：解码图片，缩放，重新编码返回字节。
Uint8List? _decodeAndScale(_ScaleRequest req) {
  final file = image.decodeImage(File(req.path).readAsBytesSync());
  if (file == null) return null;
  if (req.highRes || file.width <= req.maxWidth) {
    final ext = req.path.split('.').last.toLowerCase();
    if (ext == 'png') {
      return Uint8List.fromList(image.encodePng(file, level: 6));
    }
    return Uint8List.fromList(image.encodeJpg(file, quality: 85));
  }
  final scaled = image.copyResize(file, width: req.maxWidth);
  final ext = req.path.split('.').last.toLowerCase();
  if (ext == 'png') {
    return Uint8List.fromList(image.encodePng(scaled, level: 6));
  }
  return Uint8List.fromList(image.encodeJpg(scaled, quality: 85));
}

/// 简单的有界 Map：插入时若超过 maxSize，移除最早插入的 key。
class _BoundedMap<K, V> {
  _BoundedMap({required this.maxSize});
  final int maxSize;
  final Map<K, V> _map = {};

  V? operator [](K key) {
    final v = _map.remove(key);
    if (v != null) _map[key] = v;
    return v;
  }

  operator []=(K key, V value) {
    _map.remove(key);
    _map[key] = value;
    while (_map.length > maxSize) {
      _map.remove(_map.keys.first);
    }
  }
}
