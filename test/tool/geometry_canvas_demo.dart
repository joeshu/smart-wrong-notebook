// ignore_for_file: avoid_print, prefer_const_constructors, deprecated_member_use
import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Demo: AI 返回结构化几何描述 → Canvas 绘制
/// 运行: flutter run -t test/tool/geometry_canvas_demo.dart
void main() {
  runApp(const GeometryCanvasDemoApp());
}

class GeometryCanvasDemoApp extends StatelessWidget {
  const GeometryCanvasDemoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '几何 Canvas 绘制 Demo',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
      home: const GeometryDemoPage(),
    );
  }
}

class GeometryDemoPage extends StatefulWidget {
  const GeometryDemoPage({super.key});

  @override
  State<GeometryDemoPage> createState() => _GeometryDemoPageState();
}

class _GeometryDemoPageState extends State<GeometryDemoPage> {
  int _currentIndex = 0;
  bool _showAuxiliary = true;

  @override
  Widget build(BuildContext context) {
    final samples = _buildSamples();
    final sample = samples[_currentIndex];

    return Scaffold(
      appBar: AppBar(
        title: const Text('几何 Canvas 绘制'),
        actions: [
          IconButton(
            icon: Icon(_showAuxiliary ? Icons.visibility : Icons.visibility_off),
            tooltip: '辅助线',
            onPressed: () => setState(() => _showAuxiliary = !_showAuxiliary),
          ),
        ],
      ),
      body: Column(
        children: [
          // 题目文字
          Padding(
            padding: const EdgeInsets.all(16),
            child: Text(
              sample.question,
              style: const TextStyle(fontSize: 15, height: 1.5),
            ),
          ),
          // Canvas 绘图区
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: AspectRatio(
              aspectRatio: 1.4,
              child: CustomPaint(
                painter: GeometryPainter(
                  diagram: sample.diagram,
                  showAuxiliary: _showAuxiliary,
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
          // 选项
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(
              children: sample.options.map((opt) {
                return Container(
                  width: double.infinity,
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(opt, style: const TextStyle(fontSize: 14)),
                );
              }).toList(),
            ),
          ),
          const Spacer(),
          // 切换样例
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                FilledButton.tonal(
                  onPressed: _currentIndex > 0
                      ? () => setState(() => _currentIndex--)
                      : null,
                  child: const Text('上一题'),
                ),
                const SizedBox(width: 16),
                Text('${_currentIndex + 1} / ${samples.length}'),
                const SizedBox(width: 16),
                FilledButton.tonal(
                  onPressed: _currentIndex < samples.length - 1
                      ? () => setState(() => _currentIndex++)
                      : null,
                  child: const Text('下一题'),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<_ExerciseSample> _buildSamples() {
    return [
      // 样例 1: 三角形内角和
      _ExerciseSample(
        question: '如图，在△ABC中，∠A = 50°，∠B = 65°，求∠C的度数。',
        options: ['A. 55°', 'B. 60°', 'C. 65°', 'D. 70°'],
        diagram: GeometryDiagram(
          elements: [
            PolygonElement(
              points: [Offset(0.5, 0.1), Offset(0.15, 0.85), Offset(0.85, 0.85)],
              labels: [
                LabelInfo('A', Offset(0.5, 0.05)),
                LabelInfo('B', Offset(0.08, 0.9)),
                LabelInfo('C', Offset(0.92, 0.9)),
              ],
            ),
            AngleArcElement(
              vertex: Offset(0.5, 0.1),
              startAngle: 55,
              sweepAngle: 70,
              radius: 0.08,
              label: '50°',
            ),
            AngleArcElement(
              vertex: Offset(0.15, 0.85),
              startAngle: -80,
              sweepAngle: 60,
              radius: 0.07,
              label: '65°',
            ),
            TextElement(text: '?', position: Offset(0.82, 0.78), color: Colors.green),
          ],
          auxiliaryLines: [
            // 延长 BC 到 D，作外角辅助线
            LineElement(
              start: Offset(0.85, 0.85),
              end: Offset(1.0, 0.85),
              style: LineStyle.dashed,
              color: Colors.orange,
            ),
            TextElement(text: 'D', position: Offset(1.02, 0.85), color: Colors.orange),
          ],
        ),
      ),
      // 样例 2: 半圆面积
      _ExerciseSample(
        question: '如图，半圆的直径 AB = 10 cm，求阴影部分（半圆）的面积。',
        options: ['A. 25π/2 cm²', 'B. 25π cm²', 'C. 50π cm²', 'D. 10π cm²'],
        diagram: GeometryDiagram(
          elements: [
            ArcElement(
              center: Offset(0.5, 0.65),
              radius: 0.3,
              startAngle: 180,
              sweepAngle: 180,
              filled: true,
              fillColor: Colors.blue.withValues(alpha: 0.15),
            ),
            LineElement(
              start: Offset(0.2, 0.65),
              end: Offset(0.8, 0.65),
            ),
            PointElement(position: Offset(0.2, 0.65), label: 'A'),
            PointElement(position: Offset(0.8, 0.65), label: 'B'),
            TextElement(
              text: '10 cm',
              position: Offset(0.5, 0.72),
              color: Colors.red,
            ),
            TextElement(
              text: '阴影',
              position: Offset(0.5, 0.48),
              color: Colors.blue,
            ),
          ],
          auxiliaryLines: [
            // 半径辅助线
            LineElement(
              start: Offset(0.5, 0.65),
              end: Offset(0.5, 0.35),
              style: LineStyle.dashed,
              color: Colors.orange,
            ),
            TextElement(text: 'r=5', position: Offset(0.53, 0.48), color: Colors.orange),
            PointElement(position: Offset(0.5, 0.65), label: 'O', color: Colors.orange),
          ],
        ),
      ),
      // 样例 3: 圆锥体积
      _ExerciseSample(
        question: '如图，圆锥的底面半径 r = 3 cm，高 h = 4 cm，求圆锥的体积。',
        options: ['A. 12π cm³', 'B. 36π cm³', 'C. 9π cm³', 'D. 48π cm³'],
        diagram: GeometryDiagram(
          elements: [
            // 底面椭圆
            EllipseElement(
              center: Offset(0.5, 0.8),
              radiusX: 0.25,
              radiusY: 0.08,
            ),
            // 侧面线
            LineElement(start: Offset(0.5, 0.15), end: Offset(0.25, 0.8)),
            LineElement(start: Offset(0.5, 0.15), end: Offset(0.75, 0.8)),
            // 顶点
            PointElement(position: Offset(0.5, 0.15), label: ''),
            // 高
            LineElement(
              start: Offset(0.5, 0.15),
              end: Offset(0.5, 0.8),
              style: LineStyle.dashed,
              color: Colors.red,
            ),
            // 半径
            LineElement(
              start: Offset(0.5, 0.8),
              end: Offset(0.75, 0.8),
              color: Colors.green,
            ),
            // 直角标记
            RightAngleElement(vertex: Offset(0.5, 0.8), size: 0.03),
            // 标注
            TextElement(text: 'h=4', position: Offset(0.4, 0.5), color: Colors.red),
            TextElement(text: 'r=3', position: Offset(0.63, 0.87), color: Colors.green),
          ],
          auxiliaryLines: [],
        ),
      ),
      // 样例 4: 等腰三角形
      _ExerciseSample(
        question: '如图，等腰三角形 ABC 中，AB = AC，∠A = 40°，求∠B。',
        options: ['A. 60°', 'B. 70°', 'C. 80°', 'D. 40°'],
        diagram: GeometryDiagram(
          elements: [
            PolygonElement(
              points: [Offset(0.5, 0.1), Offset(0.2, 0.85), Offset(0.8, 0.85)],
              labels: [
                LabelInfo('A', Offset(0.5, 0.04)),
                LabelInfo('B', Offset(0.13, 0.9)),
                LabelInfo('C', Offset(0.87, 0.9)),
              ],
            ),
            // 等边标记
            TickMarkElement(start: Offset(0.5, 0.1), end: Offset(0.2, 0.85), ticks: 1),
            TickMarkElement(start: Offset(0.5, 0.1), end: Offset(0.8, 0.85), ticks: 1),
            // 角度
            AngleArcElement(
              vertex: Offset(0.5, 0.1),
              startAngle: 55,
              sweepAngle: 70,
              radius: 0.07,
              label: '40°',
            ),
            TextElement(text: '?', position: Offset(0.26, 0.72), color: Colors.green),
          ],
          auxiliaryLines: [
            // 作底边中线（也是高）
            LineElement(
              start: Offset(0.5, 0.1),
              end: Offset(0.5, 0.85),
              style: LineStyle.dashed,
              color: Colors.orange,
            ),
            PointElement(position: Offset(0.5, 0.85), label: 'D', color: Colors.orange),
            RightAngleElement(vertex: Offset(0.5, 0.85), size: 0.025),
          ],
        ),
      ),
      // 样例 5: 梯形 + 半圆
      _ExerciseSample(
        question: '如图，梯形 ABCD 的上底 AD = 6，下底 BC = 10，高 = 4。以 AD 为直径画半圆，求阴影部分面积。',
        options: ['A. 32 + 9π/2', 'B. 32 + 4.5π', 'C. 32 - 9π/2', 'D. 40 + 9π/2'],
        diagram: GeometryDiagram(
          elements: [
            // 梯形
            PolygonElement(
              points: [
                Offset(0.35, 0.3),  // A
                Offset(0.65, 0.3),  // D
                Offset(0.8, 0.8),   // C
                Offset(0.2, 0.8),   // B
              ],
              labels: [
                LabelInfo('A', Offset(0.3, 0.25)),
                LabelInfo('D', Offset(0.7, 0.25)),
                LabelInfo('C', Offset(0.85, 0.83)),
                LabelInfo('B', Offset(0.13, 0.83)),
              ],
              fillColor: Colors.grey.withValues(alpha: 0.1),
            ),
            // 半圆（在上底上方）
            ArcElement(
              center: Offset(0.5, 0.3),
              radius: 0.15,
              startAngle: 180,
              sweepAngle: 180,
              filled: true,
              fillColor: Colors.blue.withValues(alpha: 0.2),
            ),
            // 标注
            TextElement(text: 'AD=6', position: Offset(0.5, 0.35), color: Colors.red),
            TextElement(text: 'BC=10', position: Offset(0.5, 0.87), color: Colors.red),
            TextElement(text: '阴影', position: Offset(0.5, 0.18), color: Colors.blue),
          ],
          auxiliaryLines: [
            // 高
            LineElement(
              start: Offset(0.5, 0.3),
              end: Offset(0.5, 0.8),
              style: LineStyle.dashed,
              color: Colors.orange,
            ),
            TextElement(text: 'h=4', position: Offset(0.53, 0.55), color: Colors.orange),
          ],
        ),
      ),
    ];
  }
}

// ============================================================
// 数据模型：AI 返回的结构化几何描述
// ============================================================

class GeometryDiagram {
  final List<GeometryElement> elements;
  final List<GeometryElement> auxiliaryLines;

  const GeometryDiagram({
    required this.elements,
    this.auxiliaryLines = const [],
  });
}

abstract class GeometryElement {}

enum LineStyle { solid, dashed, dotted }

class LineElement extends GeometryElement {
  final Offset start;
  final Offset end;
  final LineStyle style;
  final Color color;
  final double width;

  LineElement({
    required this.start,
    required this.end,
    this.style = LineStyle.solid,
    this.color = const Color(0xFF333333),
    this.width = 2.0,
  });
}

class PolygonElement extends GeometryElement {
  final List<Offset> points;
  final List<LabelInfo> labels;
  final Color? fillColor;

  PolygonElement({
    required this.points,
    this.labels = const [],
    this.fillColor,
  });
}

class ArcElement extends GeometryElement {
  final Offset center;
  final double radius;
  final double startAngle;
  final double sweepAngle;
  final bool filled;
  final Color fillColor;

  ArcElement({
    required this.center,
    required this.radius,
    required this.startAngle,
    required this.sweepAngle,
    this.filled = false,
    this.fillColor = Colors.transparent,
  });
}

class EllipseElement extends GeometryElement {
  final Offset center;
  final double radiusX;
  final double radiusY;

  EllipseElement({
    required this.center,
    required this.radiusX,
    required this.radiusY,
  });
}

class PointElement extends GeometryElement {
  final Offset position;
  final String label;
  final Color color;

  PointElement({
    required this.position,
    this.label = '',
    this.color = const Color(0xFF1A73E8),
  });
}

class TextElement extends GeometryElement {
  final String text;
  final Offset position;
  final Color color;
  final double fontSize;

  TextElement({
    required this.text,
    required this.position,
    this.color = const Color(0xFF333333),
    this.fontSize = 12,
  });
}

class AngleArcElement extends GeometryElement {
  final Offset vertex;
  final double startAngle;
  final double sweepAngle;
  final double radius;
  final String label;

  AngleArcElement({
    required this.vertex,
    required this.startAngle,
    required this.sweepAngle,
    required this.radius,
    this.label = '',
  });
}

class RightAngleElement extends GeometryElement {
  final Offset vertex;
  final double size;

  RightAngleElement({required this.vertex, this.size = 0.03});
}

class TickMarkElement extends GeometryElement {
  final Offset start;
  final Offset end;
  final int ticks;

  TickMarkElement({required this.start, required this.end, this.ticks = 1});
}

class LabelInfo {
  final String text;
  final Offset position;

  const LabelInfo(this.text, this.position);
}

// ============================================================
// CustomPainter：根据结构化数据绘制几何图形
// ============================================================

class GeometryPainter extends CustomPainter {
  final GeometryDiagram diagram;
  final bool showAuxiliary;

  GeometryPainter({required this.diagram, this.showAuxiliary = true});

  @override
  void paint(Canvas canvas, Size size) {
    // 绘制主图形
    for (final element in diagram.elements) {
      _drawElement(canvas, size, element);
    }
    // 绘制辅助线
    if (showAuxiliary) {
      for (final element in diagram.auxiliaryLines) {
        _drawElement(canvas, size, element);
      }
    }
  }

  void _drawElement(Canvas canvas, Size size, GeometryElement element) {
    if (element is LineElement) {
      _drawLine(canvas, size, element);
    } else if (element is PolygonElement) {
      _drawPolygon(canvas, size, element);
    } else if (element is ArcElement) {
      _drawArc(canvas, size, element);
    } else if (element is EllipseElement) {
      _drawEllipse(canvas, size, element);
    } else if (element is PointElement) {
      _drawPoint(canvas, size, element);
    } else if (element is TextElement) {
      _drawText(canvas, size, element);
    } else if (element is AngleArcElement) {
      _drawAngleArc(canvas, size, element);
    } else if (element is RightAngleElement) {
      _drawRightAngle(canvas, size, element);
    } else if (element is TickMarkElement) {
      _drawTickMark(canvas, size, element);
    }
  }

  void _drawLine(Canvas canvas, Size size, LineElement line) {
    final paint = Paint()
      ..color = line.color
      ..strokeWidth = line.width
      ..style = PaintingStyle.stroke;

    final p1 = _toPixel(line.start, size);
    final p2 = _toPixel(line.end, size);

    if (line.style == LineStyle.dashed) {
      _drawDashedLine(canvas, p1, p2, paint);
    } else {
      canvas.drawLine(p1, p2, paint);
    }
  }

  void _drawDashedLine(Canvas canvas, Offset p1, Offset p2, Paint paint) {
    const dashLength = 6.0;
    const gapLength = 4.0;
    final dx = p2.dx - p1.dx;
    final dy = p2.dy - p1.dy;
    final distance = math.sqrt(dx * dx + dy * dy);
    final unitX = dx / distance;
    final unitY = dy / distance;

    var drawn = 0.0;
    while (drawn < distance) {
      final start = Offset(p1.dx + unitX * drawn, p1.dy + unitY * drawn);
      final end = Offset(
        p1.dx + unitX * math.min(drawn + dashLength, distance),
        p1.dy + unitY * math.min(drawn + dashLength, distance),
      );
      canvas.drawLine(start, end, paint);
      drawn += dashLength + gapLength;
    }
  }

  void _drawPolygon(Canvas canvas, Size size, PolygonElement polygon) {
    final path = Path();
    final pixels = polygon.points.map((p) => _toPixel(p, size)).toList();

    if (pixels.isEmpty) return;
    path.moveTo(pixels[0].dx, pixels[0].dy);
    for (var i = 1; i < pixels.length; i++) {
      path.lineTo(pixels[i].dx, pixels[i].dy);
    }
    path.close();

    if (polygon.fillColor != null) {
      canvas.drawPath(
        path,
        Paint()
          ..color = polygon.fillColor!
          ..style = PaintingStyle.fill,
      );
    }

    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFF333333)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );

    // 绘制顶点标注
    for (final label in polygon.labels) {
      _drawLabel(canvas, size, label.text, label.position, const Color(0xFF1A73E8));
    }
  }

  void _drawArc(Canvas canvas, Size size, ArcElement arc) {
    final center = _toPixel(arc.center, size);
    final r = arc.radius * math.min(size.width, size.height);
    final rect = Rect.fromCircle(center: center, radius: r);
    final startRad = arc.startAngle * math.pi / 180;
    final sweepRad = arc.sweepAngle * math.pi / 180;

    if (arc.filled) {
      canvas.drawArc(
        rect,
        startRad,
        sweepRad,
        false,
        Paint()
          ..color = arc.fillColor
          ..style = PaintingStyle.fill,
      );
    }

    canvas.drawArc(
      rect,
      startRad,
      sweepRad,
      false,
      Paint()
        ..color = const Color(0xFF1565C0)
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke,
    );
  }

  void _drawEllipse(Canvas canvas, Size size, EllipseElement ellipse) {
    final center = _toPixel(ellipse.center, size);
    final rx = ellipse.radiusX * size.width;
    final ry = ellipse.radiusY * size.height;
    final rect = Rect.fromCenter(center: center, width: rx * 2, height: ry * 2);

    canvas.drawOval(
      rect,
      Paint()
        ..color = const Color(0xFF333333)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke,
    );
  }

  void _drawPoint(Canvas canvas, Size size, PointElement point) {
    final p = _toPixel(point.position, size);
    canvas.drawCircle(
      p,
      3,
      Paint()..color = point.color,
    );
    if (point.label.isNotEmpty) {
      _drawLabel(canvas, size, point.label, point.position, point.color);
    }
  }

  void _drawText(Canvas canvas, Size size, TextElement text) {
    final p = _toPixel(text.position, size);
    final textPainter = TextPainter(
      text: TextSpan(
        text: text.text,
        style: TextStyle(
          color: text.color,
          fontSize: text.fontSize,
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(
      canvas,
      Offset(p.dx - textPainter.width / 2, p.dy - textPainter.height / 2),
    );
  }

  void _drawAngleArc(Canvas canvas, Size size, AngleArcElement angle) {
    final center = _toPixel(angle.vertex, size);
    final r = angle.radius * math.min(size.width, size.height);
    final rect = Rect.fromCircle(center: center, radius: r);
    final startRad = angle.startAngle * math.pi / 180;
    final sweepRad = angle.sweepAngle * math.pi / 180;

    canvas.drawArc(
      rect,
      startRad,
      sweepRad,
      false,
      Paint()
        ..color = const Color(0xFFE63946)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke,
    );

    if (angle.label.isNotEmpty) {
      final midAngle = startRad + sweepRad / 2;
      final labelR = r + 12;
      final labelPos = Offset(
        center.dx + labelR * math.cos(midAngle),
        center.dy + labelR * math.sin(midAngle),
      );
      final textPainter = TextPainter(
        text: TextSpan(
          text: angle.label,
          style: const TextStyle(
            color: Color(0xFFE63946),
            fontSize: 11,
            fontWeight: FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      textPainter.paint(
        canvas,
        Offset(labelPos.dx - textPainter.width / 2, labelPos.dy - textPainter.height / 2),
      );
    }
  }

  void _drawRightAngle(Canvas canvas, Size size, RightAngleElement ra) {
    final p = _toPixel(ra.vertex, size);
    final s = ra.size * math.min(size.width, size.height);

    final path = Path()
      ..moveTo(p.dx - s, p.dy)
      ..lineTo(p.dx - s, p.dy - s)
      ..lineTo(p.dx, p.dy - s);

    canvas.drawPath(
      path,
      Paint()
        ..color = const Color(0xFFE63946)
        ..strokeWidth = 1.5
        ..style = PaintingStyle.stroke,
    );
  }

  void _drawTickMark(Canvas canvas, Size size, TickMarkElement tick) {
    final p1 = _toPixel(tick.start, size);
    final p2 = _toPixel(tick.end, size);
    final midX = (p1.dx + p2.dx) / 2;
    final midY = (p1.dy + p2.dy) / 2;

    final dx = p2.dx - p1.dx;
    final dy = p2.dy - p1.dy;
    final len = math.sqrt(dx * dx + dy * dy);
    final perpX = -dy / len * 6;
    final perpY = dx / len * 6;

    final paint = Paint()
      ..color = const Color(0xFF2D6A4F)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;

    for (var i = 0; i < tick.ticks; i++) {
      final offset = (i - (tick.ticks - 1) / 2) * 4;
      final cx = midX + dx / len * offset;
      final cy = midY + dy / len * offset;
      canvas.drawLine(
        Offset(cx + perpX, cy + perpY),
        Offset(cx - perpX, cy - perpY),
        paint,
      );
    }
  }

  void _drawLabel(Canvas canvas, Size size, String text, Offset position, Color color) {
    final p = _toPixel(position, size);
    final textPainter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: color,
          fontSize: 14,
          fontWeight: FontWeight.bold,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    textPainter.paint(
      canvas,
      Offset(p.dx - textPainter.width / 2, p.dy - textPainter.height / 2),
    );
  }

  Offset _toPixel(Offset normalized, Size size) {
    return Offset(normalized.dx * size.width, normalized.dy * size.height);
  }

  @override
  bool shouldRepaint(covariant GeometryPainter oldDelegate) {
    return oldDelegate.showAuxiliary != showAuxiliary ||
        oldDelegate.diagram != diagram;
  }
}

// ============================================================
// 练习题样例数据
// ============================================================

class _ExerciseSample {
  final String question;
  final List<String> options;
  final GeometryDiagram diagram;

  const _ExerciseSample({
    required this.question,
    required this.options,
    required this.diagram,
  });
}
