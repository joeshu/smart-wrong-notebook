// ignore_for_file: prefer_const_constructors
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_wrong_notebook/src/shared/widgets/confidence_badge.dart';

void main() {
  Future<void> pumpBadge(
    WidgetTester tester, {
    double? confidence,
    bool compact = false,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ConfidenceBadge(
            confidence: confidence,
            compact: compact,
          ),
        ),
      ),
    );
  }

  testWidgets('null confidence shows 未记录置信度 label without percentage',
      (tester) async {
    await pumpBadge(tester, confidence: null);
    expect(find.text('未记录置信度'), findsOneWidget);
    expect(find.textContaining('%'), findsNothing);
  });

  testWidgets('confidence >= 0.85 shows 识别可靠 with green tone', (tester) async {
    await pumpBadge(tester, confidence: 0.9);
    expect(find.textContaining('识别可靠'), findsOneWidget);
    expect(find.textContaining('90%'), findsOneWidget);
  });

  testWidgets('confidence exactly 0.85 still counts as reliable', (tester) async {
    await pumpBadge(tester, confidence: 0.85);
    expect(find.textContaining('识别可靠'), findsOneWidget);
    expect(find.textContaining('85%'), findsOneWidget);
  });

  testWidgets('confidence >= 0.7 shows 识别较可靠', (tester) async {
    await pumpBadge(tester, confidence: 0.75);
    expect(find.textContaining('识别较可靠'), findsOneWidget);
    expect(find.textContaining('75%'), findsOneWidget);
  });

  testWidgets('confidence exactly 0.7 still counts as 识别较可靠', (tester) async {
    await pumpBadge(tester, confidence: 0.7);
    expect(find.textContaining('识别较可靠'), findsOneWidget);
    expect(find.textContaining('70%'), findsOneWidget);
  });

  testWidgets('confidence >= 0.5 shows 建议校对', (tester) async {
    await pumpBadge(tester, confidence: 0.55);
    expect(find.textContaining('建议校对'), findsOneWidget);
    expect(find.textContaining('55%'), findsOneWidget);
  });

  testWidgets('confidence exactly 0.5 still counts as 建议校对', (tester) async {
    await pumpBadge(tester, confidence: 0.5);
    expect(find.textContaining('建议校对'), findsOneWidget);
    expect(find.textContaining('50%'), findsOneWidget);
  });

  testWidgets('confidence < 0.5 shows 建议重新识别', (tester) async {
    await pumpBadge(tester, confidence: 0.3);
    expect(find.textContaining('建议重新识别'), findsOneWidget);
    expect(find.textContaining('30%'), findsOneWidget);
  });

  testWidgets('confidence 0 shows 建议重新识别 with 0%', (tester) async {
    await pumpBadge(tester, confidence: 0.0);
    expect(find.textContaining('建议重新识别'), findsOneWidget);
    expect(find.textContaining('0%'), findsOneWidget);
  });

  testWidgets('compact mode renders without icon (only text)', (tester) async {
    await pumpBadge(tester, confidence: 0.9, compact: true);
    expect(find.textContaining('识别可靠'), findsOneWidget);
    // Compact mode should not render the leading Icon widget
    expect(find.byType(Icon), findsNothing);
  });

  testWidgets('non-compact mode renders leading icon', (tester) async {
    await pumpBadge(tester, confidence: 0.9, compact: false);
    expect(find.byType(Icon), findsOneWidget);
  });

  testWidgets('compact mode null confidence shows label only', (tester) async {
    await pumpBadge(tester, confidence: null, compact: true);
    expect(find.text('未记录置信度'), findsOneWidget);
    expect(find.byType(Icon), findsNothing);
  });

  testWidgets('percentage is rounded to nearest integer', (tester) async {
    await pumpBadge(tester, confidence: 0.856);
    // 0.856 * 100 = 85.6 → rounds to 86
    expect(find.textContaining('86%'), findsOneWidget);
  });

  testWidgets('green color used for reliable confidence', (tester) async {
    await pumpBadge(tester, confidence: 0.95);
    final container = tester.widget<Container>(find.byType(Container).first);
    final decoration = container.decoration as BoxDecoration;
    // Color 0xFF10B981 with alpha 0.12
    expect(decoration.color, const Color(0xFF10B981).withValues(alpha: 0.12));
  });

  testWidgets('blue color used for moderately reliable confidence',
      (tester) async {
    await pumpBadge(tester, confidence: 0.75);
    final container = tester.widget<Container>(find.byType(Container).first);
    final decoration = container.decoration as BoxDecoration;
    expect(decoration.color, const Color(0xFF3B82F6).withValues(alpha: 0.12));
  });

  testWidgets('orange color used for review-suggested confidence',
      (tester) async {
    await pumpBadge(tester, confidence: 0.55);
    final container = tester.widget<Container>(find.byType(Container).first);
    final decoration = container.decoration as BoxDecoration;
    expect(decoration.color, const Color(0xFFF59E0B).withValues(alpha: 0.12));
  });

  testWidgets('red color used for low confidence', (tester) async {
    await pumpBadge(tester, confidence: 0.2);
    final container = tester.widget<Container>(find.byType(Container).first);
    final decoration = container.decoration as BoxDecoration;
    expect(decoration.color, const Color(0xFFEF4444).withValues(alpha: 0.12));
  });

  testWidgets('gray color used for null confidence', (tester) async {
    await pumpBadge(tester, confidence: null);
    final container = tester.widget<Container>(find.byType(Container).first);
    final decoration = container.decoration as BoxDecoration;
    expect(decoration.color, const Color(0xFF94A3B8).withValues(alpha: 0.12));
  });
}
