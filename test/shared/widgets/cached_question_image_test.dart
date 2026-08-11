import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_wrong_notebook/src/shared/widgets/cached_question_image.dart';

void main() {
  testWidgets('missing image uses compact non-overflowing thumbnail fallback',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 64,
              height: 64,
              child: CachedQuestionImage('/path/that/does/not/exist.jpg'),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(Icon), findsOneWidget);
    expect(find.byType(Tooltip), findsOneWidget);
  });

  testWidgets('compact missing image keeps reselect action accessible',
      (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 64,
            height: 64,
            child: CachedQuestionImage(
              '/path/that/does/not/exist.jpg',
              onReselect: () => tapped = true,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.byType(InkWell));

    expect(tapped, isTrue);
    expect(tester.takeException(), isNull);
  });

  testWidgets('large missing image retains explanatory failure text',
      (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 320,
            height: 180,
            child: CachedQuestionImage('/path/that/does/not/exist.jpg'),
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.textContaining('路径失效'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
