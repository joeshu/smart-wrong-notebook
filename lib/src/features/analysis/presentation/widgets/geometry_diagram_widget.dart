import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';

class GeometryDiagramWidget extends StatefulWidget {
  const GeometryDiagramWidget({
    super.key,
    required this.diagramData,
    this.showAuxiliaryButton = true,
  });

  final Map<String, dynamic> diagramData;
  final bool showAuxiliaryButton;

  @override
  State<GeometryDiagramWidget> createState() => _GeometryDiagramWidgetState();
}

class _GeometryDiagramWidgetState extends State<GeometryDiagramWidget>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animController;
  late final Animation<double> _animation;
  bool _showAuxiliary = false;
  _GeometryDiagram? _diagram;

  @override
  void initState() {
    super.initState();
    _animController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _animation =
        CurvedAnimation(parent: _animController, curve: Curves.easeOut);
    _diagram = _GeometryDiagram.tryFromJson(widget.diagramData);
  }

  @override
  void didUpdateWidget(covariant GeometryDiagramWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.diagramData != oldWidget.diagramData) {
      _diagram = _GeometryDiagram.tryFromJson(widget.diagramData);
      _showAuxiliary = false;
      _animController.reset();
    }
  }

  @override
  void dispose() {
    _animController.dispose();
    super.dispose();
  }

  void _toggleAuxiliary() {
    setState(() {
      _showAuxiliary = !_showAuxiliary;
      if (_showAuxiliary) {
        if (!const bool.fromEnvironment('FLUTTER_TEST')) {
          _animController.forward(from: 0);
        }
      } else {
        _animController.reset();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final diagram = _diagram;
    if (diagram == null) return const SizedBox.shrink();

    final colorScheme = Theme.of(context).colorScheme;
    final hasAuxiliary =
        widget.showAuxiliaryButton && diagram.auxiliaryLines.isNotEmpty;

    return Column(
      children: [
        Container(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: colorScheme.outlineVariant,
            ),
          ),
          child: AspectRatio(
            aspectRatio: 1.4,
            child: AnimatedBuilder(
              animation: _animation,
              builder: (context, _) {
                return CustomPaint(
                  size: Size.infinite,
                  painter: _GeometryPainter(
                    diagram: diagram,
                    showAuxiliary: _showAuxiliary,
                    auxiliaryProgress: _animation.value,
                    colorScheme: colorScheme,
                  ),
                );
              },
            ),
          ),
        ),
        if (hasAuxiliary)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: TextButton.icon(
              onPressed: _toggleAuxiliary,
              icon: Icon(
                _showAuxiliary ? CupertinoIcons.eye_slash : CupertinoIcons.eye,
                size: 18,
              ),
              label: Text(
                _showAuxiliary ? '隐藏辅助线' : '显示辅助线',
                style: const TextStyle(fontSize: 13),
              ),
              style: TextButton.styleFrom(
                foregroundColor: colorScheme.tertiary,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
      ],
    );
  }
}

// ---- Painter ----

class _GeometryPainter extends CustomPainter {
  _GeometryPainter({
    required this.diagram,
    required this.colorScheme,
    this.showAuxiliary = false,
    this.auxiliaryProgress = 1.0,
  });

  final _GeometryDiagram diagram;
  final ColorScheme colorScheme;
  final bool showAuxiliary;
  final double auxiliaryProgress;

  @override
  void paint(Canvas canvas, Size size) {
    final padding = size.width * 0.06;
    final area = Rect.fromLTWH(
      padding,
      padding,
      size.width - padding * 2,
      size.height - padding * 2,
    );

    for (final el in diagram.elements) {
      _drawElement(canvas, area, el, 1.0);
    }
    if (showAuxiliary && auxiliaryProgress > 0) {
      for (final el in diagram.auxiliaryLines) {
        _drawElement(canvas, area, el, auxiliaryProgress);
      }
    }
  }

  Offset _px(double x, double y, Rect a) =>
      Offset(a.left + x * a.width, a.top + y * a.height);

  void _drawElement(Canvas c, Rect a, _GeoElement el, double p) {
    switch (el) {
      case _LineEl():
        _drawLine(c, a, el, p);
      case _PolygonEl():
        _drawPolygon(c, a, el, p);
      case _ArcEl():
        _drawArc(c, a, el, p);
      case _EllipseEl():
        _drawEllipse(c, a, el, p);
      case _PointEl():
        _drawPoint(c, a, el, p);
      case _TextEl():
        _drawText(c, a, el, p);
      case _AngleArcEl():
        _drawAngleArc(c, a, el, p);
      case _RightAngleEl():
        _drawRightAngle(c, a, el, p);
      case _TickMarkEl():
        _drawTickMark(c, a, el, p);
    }
  }

  void _drawLine(Canvas c, Rect a, _LineEl l, double p) {
    final color = _color(l.role);
    final paint = Paint()
      ..color = color.withValues(alpha: p)
      ..strokeWidth = l.strokeWidth
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final p1 = _px(l.x1, l.y1, a);
    final p2Full = _px(l.x2, l.y2, a);
    final p2 = Offset.lerp(p1, p2Full, p)!;
    if (l.style == 'dashed') {
      _dashed(c, p1, p2, paint);
    } else {
      c.drawLine(p1, p2, paint);
    }
  }

  void _dashed(Canvas c, Offset a, Offset b, Paint paint) {
    const dash = 6.0, gap = 4.0;
    final d = (b - a);
    final dist = d.distance;
    if (dist < 0.5) return;
    final u = d / dist;
    var drawn = 0.0;
    while (drawn < dist) {
      final s = a + u * drawn;
      final e = a + u * math.min(drawn + dash, dist);
      c.drawLine(s, e, paint);
      drawn += dash + gap;
    }
  }

  void _drawPolygon(Canvas c, Rect a, _PolygonEl poly, double p) {
    if (poly.points.isEmpty) return;
    final pts = poly.points.map((pt) => _px(pt[0], pt[1], a)).toList();
    final path = Path()..moveTo(pts[0].dx, pts[0].dy);
    for (var i = 1; i < pts.length; i++) {
      path.lineTo(pts[i].dx, pts[i].dy);
    }
    path.close();

    if (poly.filled) {
      c.drawPath(
          path, Paint()..color = _color(poly.role).withValues(alpha: 0.08 * p));
    }
    c.drawPath(
      path,
      Paint()
        ..color = colorScheme.onSurface.withValues(alpha: 0.85 * p)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke
        ..strokeJoin = StrokeJoin.round,
    );
    for (final lbl in poly.labels) {
      _label(
          c,
          a,
          lbl['text'] as String? ?? '',
          (lbl['x'] as num?)?.toDouble() ?? 0,
          (lbl['y'] as num?)?.toDouble() ?? 0,
          colorScheme.primary,
          p);
    }
  }

  void _drawArc(Canvas c, Rect a, _ArcEl arc, double p) {
    final center = _px(arc.cx, arc.cy, a);
    final r = arc.r * math.min(a.width, a.height);
    final rect = Rect.fromCircle(center: center, radius: r);
    final startRad = arc.startAngle * math.pi / 180;
    final sweepRad = arc.sweepAngle * math.pi / 180;
    if (arc.filled) {
      c.drawArc(
          rect,
          startRad,
          sweepRad * p,
          false,
          Paint()
            ..color = _color(arc.role).withValues(alpha: 0.12 * p)
            ..style = PaintingStyle.fill);
    }
    c.drawArc(
        rect,
        startRad,
        sweepRad * p,
        false,
        Paint()
          ..color = colorScheme.primary.withValues(alpha: p)
          ..strokeWidth = 2
          ..style = PaintingStyle.stroke);
  }

  void _drawEllipse(Canvas c, Rect a, _EllipseEl el, double p) {
    final center = _px(el.cx, el.cy, a);
    final rect = Rect.fromCenter(
        center: center,
        width: el.rx * a.width * 2,
        height: el.ry * a.height * 2);
    c.drawOval(
        rect,
        Paint()
          ..color = colorScheme.onSurface.withValues(alpha: 0.6 * p)
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke);
  }

  void _drawPoint(Canvas c, Rect a, _PointEl pt, double p) {
    final pos = _px(pt.x, pt.y, a);
    final color = _color(pt.role);
    c.drawCircle(pos, 3.5, Paint()..color = color.withValues(alpha: p));
    if (pt.label.isNotEmpty) {
      _label(c, a, pt.label, pt.x, pt.y - 0.04, color, p);
    }
  }

  void _drawText(Canvas c, Rect a, _TextEl t, double p) {
    final pos = _px(t.x, t.y, a);
    final tp = TextPainter(
      text: TextSpan(
        text: t.text,
        style: TextStyle(
          color: _color(t.role).withValues(alpha: p),
          fontSize: t.fontSize,
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, Offset(pos.dx - tp.width / 2, pos.dy - tp.height / 2));
  }

  void _drawAngleArc(Canvas c, Rect a, _AngleArcEl ang, double p) {
    final center = _px(ang.vx, ang.vy, a);
    final r = ang.r * math.min(a.width, a.height);
    final rect = Rect.fromCircle(center: center, radius: r);

    final computed = ang.usesExplicitAngles
        ? null
        : _computeAngleFromPolygon(ang.vx, ang.vy);
    final double startRad;
    final double sweepRad;
    if (computed != null) {
      startRad = computed.$1;
      sweepRad = computed.$2;
    } else {
      startRad = ang.startAngle * math.pi / 180;
      sweepRad = ang.sweepAngle * math.pi / 180;
    }

    const red = Color(0xFFE63946);
    c.drawArc(
        rect,
        startRad,
        sweepRad * p,
        false,
        Paint()
          ..color = red.withValues(alpha: p)
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke);
    if (ang.label.isNotEmpty && p > 0.5) {
      final mid = startRad + sweepRad / 2;
      final lp = Offset(
        center.dx + (r + 14) * math.cos(mid),
        center.dy + (r + 14) * math.sin(mid),
      );
      final tp = TextPainter(
        text: TextSpan(
          text: ang.label,
          style: TextStyle(
            color: red.withValues(alpha: (p - 0.5) * 2),
            fontSize: 12,
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(c, Offset(lp.dx - tp.width / 2, lp.dy - tp.height / 2));
    }
  }

  (double, double)? _computeAngleFromPolygon(double vx, double vy) {
    const threshold = 0.05;
    for (final el in diagram.elements) {
      if (el is! _PolygonEl || el.points.length < 3) continue;
      final pts = el.points;
      for (var i = 0; i < pts.length; i++) {
        final dx = pts[i][0] - vx;
        final dy = pts[i][1] - vy;
        if (dx * dx + dy * dy > threshold * threshold) continue;
        final prev = pts[(i - 1 + pts.length) % pts.length];
        final next = pts[(i + 1) % pts.length];
        final a1 = math.atan2(prev[1] - vy, prev[0] - vx);
        final a2 = math.atan2(next[1] - vy, next[0] - vx);
        var sweep = a2 - a1;
        if (sweep < 0) sweep += 2 * math.pi;
        if (sweep > math.pi) {
          final start = a2;
          return (start, 2 * math.pi - sweep);
        }
        return (a1, sweep);
      }
    }
    return null;
  }

  void _drawRightAngle(Canvas c, Rect a, _RightAngleEl ra, double p) {
    final pos = _px(ra.x, ra.y, a);
    final s = (ra.size ?? 0.025) * math.min(a.width, a.height);
    final path = Path()
      ..moveTo(pos.dx - s, pos.dy)
      ..lineTo(pos.dx - s, pos.dy - s)
      ..lineTo(pos.dx, pos.dy - s);
    c.drawPath(
        path,
        Paint()
          ..color = const Color(0xFFE63946).withValues(alpha: p)
          ..strokeWidth = 1.5
          ..style = PaintingStyle.stroke);
  }

  void _drawTickMark(Canvas c, Rect a, _TickMarkEl tick, double p) {
    final p1 = _px(tick.x1, tick.y1, a);
    final p2 = _px(tick.x2, tick.y2, a);
    final mid = Offset((p1.dx + p2.dx) / 2, (p1.dy + p2.dy) / 2);
    final d = p2 - p1;
    final len = d.distance;
    if (len < 1) return;
    final perp = Offset(-d.dy / len * 6, d.dx / len * 6);
    final paint = Paint()
      ..color = const Color(0xFF2D6A4F).withValues(alpha: p)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    for (var i = 0; i < tick.ticks; i++) {
      final off = (i - (tick.ticks - 1) / 2) * 4;
      final cx = mid.dx + d.dx / len * off;
      final cy = mid.dy + d.dy / len * off;
      c.drawLine(Offset(cx + perp.dx, cy + perp.dy),
          Offset(cx - perp.dx, cy - perp.dy), paint);
    }
  }

  void _label(Canvas c, Rect a, String text, double x, double y, Color color,
      double p) {
    final pos = _px(x, y, a);
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color.withValues(alpha: p),
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, Offset(pos.dx - tp.width / 2, pos.dy - tp.height / 2));
  }

  Color _color(String? role) => switch (role) {
        'known' => const Color(0xFFE63946),
        'target' || 'solve' => const Color(0xFF2D6A4F),
        'auxiliary' => colorScheme.tertiary,
        'label' => colorScheme.primary,
        'fill' => colorScheme.primary,
        _ => colorScheme.onSurface,
      };

  @override
  bool shouldRepaint(covariant _GeometryPainter old) =>
      old.showAuxiliary != showAuxiliary ||
      old.auxiliaryProgress != auxiliaryProgress ||
      old.diagram != diagram ||
      old.colorScheme != colorScheme;
}

// ---- Data Model ----

class _GeometryDiagram {
  final List<_GeoElement> elements;
  final List<_GeoElement> auxiliaryLines;

  const _GeometryDiagram(
      {required this.elements, this.auxiliaryLines = const []});

  static _GeometryDiagram? tryFromJson(Map<String, dynamic> json) {
    try {
      final rawEls = json['elements'] as List?;
      if (rawEls == null || rawEls.isEmpty) {
        debugPrint('[GeometryDiagram] elements is null or empty: ${json.keys}');
        return null;
      }
      final els = <_GeoElement>[];
      for (final item in rawEls) {
        final map = _asStringMap(item);
        if (map == null) continue;
        final el = _parseEl(map);
        if (el != null) els.add(el);
      }
      if (els.isEmpty) {
        debugPrint(
            '[GeometryDiagram] all elements failed to parse (${rawEls.length} items)');
        return null;
      }
      final rawAux = json['auxiliaryLines'] as List?;
      final aux = <_GeoElement>[];
      if (rawAux != null) {
        for (final item in rawAux) {
          final map = _asStringMap(item);
          if (map == null) continue;
          final el = _parseEl(map);
          if (el != null) aux.add(el);
        }
      }
      debugPrint(
          '[GeometryDiagram] parsed OK: ${els.length} elements, ${aux.length} aux');
      return _GeometryDiagram(elements: els, auxiliaryLines: aux);
    } catch (e, st) {
      debugPrint('[GeometryDiagram] tryFromJson error: $e\n$st');
      return null;
    }
  }

  static Map<String, dynamic>? _asStringMap(Object? value) {
    if (value is Map<String, dynamic>) return value;
    if (value is Map) return Map<String, dynamic>.from(value);
    return null;
  }

  static _GeoElement? _parseEl(Map<String, dynamic> j) {
    final type = j['type'] as String? ?? '';
    try {
      return switch (type) {
        'line' => _LineEl.fromJson(j),
        'polygon' => _PolygonEl.fromJson(j),
        'arc' => _ArcEl.fromJson(j),
        'ellipse' => _EllipseEl.fromJson(j),
        'point' => _PointEl.fromJson(j),
        'text' => _TextEl.fromJson(j),
        'angleArc' => _AngleArcEl.fromJson(j),
        'rightAngle' => _RightAngleEl.fromJson(j),
        'tickMark' => _TickMarkEl.fromJson(j),
        _ => null,
      };
    } catch (e, st) {
      debugPrint('[GeometryDiagram] _parseEl($type) error: $e\n$st');
      return null;
    }
  }
}

sealed class _GeoElement {}

class _LineEl extends _GeoElement {
  final double x1, y1, x2, y2, strokeWidth;
  final String style;
  final String? role;
  _LineEl(
      {required this.x1,
      required this.y1,
      required this.x2,
      required this.y2,
      this.style = 'solid',
      this.role,
      this.strokeWidth = 2});
  factory _LineEl.fromJson(Map<String, dynamic> j) => _LineEl(
        x1: (j['x1'] as num).toDouble(),
        y1: (j['y1'] as num).toDouble(),
        x2: (j['x2'] as num).toDouble(),
        y2: (j['y2'] as num).toDouble(),
        style: j['style'] as String? ?? 'solid',
        role: j['role'] as String?,
        strokeWidth: (j['strokeWidth'] as num?)?.toDouble() ?? 2,
      );
}

class _PolygonEl extends _GeoElement {
  final List<List<double>> points;
  final List<Map<String, dynamic>> labels;
  final bool filled;
  final String? role;
  _PolygonEl(
      {required this.points,
      this.labels = const [],
      this.filled = false,
      this.role});
  factory _PolygonEl.fromJson(Map<String, dynamic> j) {
    final pts = (j['points'] as List).map((p) {
      final l = p as List;
      return [(l[0] as num).toDouble(), (l[1] as num).toDouble()];
    }).toList();
    final lbls = (j['labels'] as List? ?? [])
        .map((l) => Map<String, dynamic>.from(l as Map))
        .toList();
    return _PolygonEl(
        points: pts,
        labels: lbls,
        filled: j['filled'] as bool? ?? false,
        role: j['role'] as String?);
  }
}

class _ArcEl extends _GeoElement {
  final double cx, cy, r, startAngle, sweepAngle;
  final bool filled;
  final String? role;
  _ArcEl(
      {required this.cx,
      required this.cy,
      required this.r,
      required this.startAngle,
      required this.sweepAngle,
      this.filled = false,
      this.role});
  factory _ArcEl.fromJson(Map<String, dynamic> j) => _ArcEl(
        cx: (j['cx'] as num).toDouble(),
        cy: (j['cy'] as num).toDouble(),
        r: (j['r'] as num).toDouble(),
        startAngle: (j['startAngle'] as num).toDouble(),
        sweepAngle: (j['sweepAngle'] as num).toDouble(),
        filled: j['filled'] as bool? ?? false,
        role: j['role'] as String?,
      );
}

class _EllipseEl extends _GeoElement {
  final double cx, cy, rx, ry;
  _EllipseEl(
      {required this.cx, required this.cy, required this.rx, required this.ry});
  factory _EllipseEl.fromJson(Map<String, dynamic> j) => _EllipseEl(
        cx: (j['cx'] as num).toDouble(),
        cy: (j['cy'] as num).toDouble(),
        rx: (j['rx'] as num).toDouble(),
        ry: (j['ry'] as num).toDouble(),
      );
}

class _PointEl extends _GeoElement {
  final double x, y;
  final String label;
  final String? role;
  _PointEl({required this.x, required this.y, this.label = '', this.role});
  factory _PointEl.fromJson(Map<String, dynamic> j) => _PointEl(
        x: (j['x'] as num).toDouble(),
        y: (j['y'] as num).toDouble(),
        label: j['label'] as String? ?? '',
        role: j['role'] as String?,
      );
}

class _TextEl extends _GeoElement {
  final String text;
  final double x, y, fontSize;
  final String? role;
  _TextEl(
      {required this.text,
      required this.x,
      required this.y,
      this.role,
      this.fontSize = 12});
  factory _TextEl.fromJson(Map<String, dynamic> j) => _TextEl(
        text: j['text'] as String? ?? '',
        x: (j['x'] as num).toDouble(),
        y: (j['y'] as num).toDouble(),
        role: j['role'] as String?,
        fontSize: (j['fontSize'] as num?)?.toDouble() ?? 12,
      );
}

class _AngleArcEl extends _GeoElement {
  final double vx, vy, startAngle, sweepAngle, r;
  final String label;
  final String? role;
  _AngleArcEl(
      {required this.vx,
      required this.vy,
      required this.startAngle,
      required this.sweepAngle,
      required this.r,
      this.label = '',
      this.role});
  bool get usesExplicitAngles => role == 'external' || role == 'explicit';
  factory _AngleArcEl.fromJson(Map<String, dynamic> j) => _AngleArcEl(
        vx: (j['vx'] as num).toDouble(),
        vy: (j['vy'] as num).toDouble(),
        startAngle: (j['startAngle'] as num).toDouble(),
        sweepAngle: (j['sweepAngle'] as num).toDouble(),
        r: (j['r'] as num).toDouble(),
        label: j['label'] as String? ?? '',
        role: j['role'] as String?,
      );
}

class _RightAngleEl extends _GeoElement {
  final double x, y;
  final double? size;
  _RightAngleEl({required this.x, required this.y, this.size});
  factory _RightAngleEl.fromJson(Map<String, dynamic> j) => _RightAngleEl(
        x: (j['x'] as num).toDouble(),
        y: (j['y'] as num).toDouble(),
        size: (j['size'] as num?)?.toDouble(),
      );
}

class _TickMarkEl extends _GeoElement {
  final double x1, y1, x2, y2;
  final int ticks;
  _TickMarkEl(
      {required this.x1,
      required this.y1,
      required this.x2,
      required this.y2,
      this.ticks = 1});
  factory _TickMarkEl.fromJson(Map<String, dynamic> j) => _TickMarkEl(
        x1: (j['x1'] as num).toDouble(),
        y1: (j['y1'] as num).toDouble(),
        x2: (j['x2'] as num).toDouble(),
        y2: (j['y2'] as num).toDouble(),
        ticks: j['ticks'] as int? ?? 1,
      );
}
