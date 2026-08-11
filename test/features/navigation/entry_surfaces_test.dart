import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/data/repositories/question_repository.dart';
import 'package:smart_wrong_notebook/src/features/capture/presentation/capture_entry_sheet.dart';
import 'package:smart_wrong_notebook/src/features/notebook/presentation/worksheet_workbench_screen.dart';

void main() {
  final override = questionRepositoryProvider.overrideWithValue(
    InMemoryQuestionRepository(),
  );

  testWidgets('worksheet workbench renders its empty-state action', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [override],
      child: const MaterialApp(home: WorksheetWorkbenchScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('还没有可组卷的错题'), findsOneWidget);
    expect(find.text('去添加错题'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('add-question sheet renders on a dark surface', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [override],
      child: MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: const Scaffold(body: CaptureEntrySheet()),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('录入错题'), findsOneWidget);
    expect(find.text('拍照'), findsOneWidget);
    expect(find.text('相册'), findsOneWidget);
    expect(find.text('试卷批量导入'), findsOneWidget);
    expect(find.text('连续拍摄试卷'), findsOneWidget);
    expect(find.text('PDF 试卷导入'), findsOneWidget);
    expect(find.text('识别选项'), findsOneWidget);
    expect(find.textContaining('PaddleOCR'), findsNothing);
    expect(find.textContaining('MinerU'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  test('capture entry wires session before the compatibility mirror', () {
    final source = File(
      'lib/src/features/capture/presentation/capture_entry_sheet.dart',
    ).readAsStringSync();
    final select = source.indexOf('session.selectImage(record.imagePath)');
    final mirror = source.indexOf('session.setCurrentQuestion(record)');

    expect(source, contains("src/app/providers.dart"));
    expect(select, greaterThanOrEqualTo(0));
    expect(mirror, greaterThan(select));
    expect(source, isNot(contains('currentQuestionProvider.notifier).state = result.record')));
    expect(source, contains("router.go('/analysis/loading')"));
    expect(source, contains("router.go('/capture/crop')"));
    expect(source, contains('capture.pickMultipleFromGallery()'));
    expect(source, contains('capture.pickPdfFromGallery()'));
    expect(source, contains('pickFromCamera()'));
    expect(source, contains(r'已拍摄 ${pages.length} 页'));
    expect(source, contains("router.go('/worksheet/import')"));
    expect(source, contains("config == null || config.baseUrl.isEmpty"));
    final saveDraft = source.indexOf(
      'questionRepositoryProvider).saveDraft(record)',
    );
    final configCheck = source.indexOf(
      'settingsRepositoryProvider).getAiProviderConfig()',
      saveDraft,
    );
    expect(saveDraft, greaterThan(mirror));
    expect(configCheck, greaterThan(saveDraft));
    expect(source, contains('继续当前录题'));
  });

  test('capture entry protects an active session from being overwritten', () {
    final source = File(
      'lib/src/features/capture/presentation/capture_entry_sheet.dart',
    ).readAsStringSync();

    expect(source, contains('var sessionState = ref.read(captureSessionProvider)'));
    expect(
      source,
      contains('if (sessionState.imagePath != null && !sessionState.isTerminal)'),
    );
    expect(source, contains('当前已有录入任务正在处理中'));
    expect(
      source.indexOf(
        'if (sessionState.imagePath != null && !sessionState.isTerminal)',
      ),
      lessThan(source.indexOf('session.selectImage(record.imagePath)')),
    );
  });

  test('capture entry only pops the sheet surface before routing', () {
    final source = File(
      'lib/src/features/capture/presentation/capture_entry_sheet.dart',
    ).readAsStringSync();
    final closeGuard = source.indexOf('if (widget.showCloseButton)');
    final pop = source.indexOf('Navigator.pop(context)', closeGuard);

    expect(closeGuard, greaterThanOrEqualTo(0));
    expect(pop, greaterThan(closeGuard));
    expect(source.indexOf("router.go('/analysis/loading')"), greaterThan(pop));
    expect(source.indexOf("router.go('/capture/crop')"), greaterThan(pop));
  });

  test('capture analysis screens advance the session state at their boundaries', () {
    final correction = File(
      'lib/src/features/capture/presentation/question_correction_screen.dart',
    ).readAsStringSync();
    final crop = File(
      'lib/src/features/capture/presentation/image_crop_screen.dart',
    ).readAsStringSync();
    final loading = File(
      'lib/src/features/analysis/presentation/analysis_loading_screen.dart',
    ).readAsStringSync();

    expect(correction, contains('session.beginRecognition()'));
    expect(correction, contains("context.go('/analysis/loading')"));
    expect(crop, contains('session.beginCropping()'));
    expect(crop, contains('session.beginRecognition()'));
    expect(crop, contains('if (croppedFile == null)'));
    expect(crop, contains('session.cancel()'));
    expect(crop, contains('questionRepositoryProvider).delete(current.id)'));
    expect(crop, contains('discardManagedImage(current.imagePath)'));
    expect(
      crop.indexOf('if (croppedFile == null)'),
      lessThan(crop.indexOf('session.beginRecognition()')),
    );
    expect(loading, contains('_advanceCaptureSessionToAnalysis();'));
    expect(loading, contains('_markCaptureConfirmation();'));
    expect(loading, contains('_completeCaptureSession(persisted.contentStatus);'));
    expect(loading, contains('_markRetryableCaptureSession(friendlyError'));
    expect(loading, contains('_cancelCaptureSession();'));
    expect(loading, contains('_analysisToken++;'));
  });

  test('analysis loading invalidates stale work after timeout and blocks duplicate retry', () {
    final source = File(
      'lib/src/features/analysis/presentation/analysis_loading_screen.dart',
    ).readAsStringSync();

    expect(source, contains('int _analysisToken = 0;'));
    expect(source, contains('if (_analysisRunning) return;'));
    expect(source, contains('token != _analysisToken'));
    expect(source, contains('contentStatus: ContentStatus.analysisFailed'));
    expect(source, contains('原图和已校对题干已保留'));
    expect(source, contains('final timeoutToken = ++_analysisToken;'));
    expect(source, contains('if (mounted && token == _analysisToken)'));
    expect(source, contains('Future<void> _retryCurrentStage()'));
    expect(source, contains('_resumeStepFor(checkpoint)'));
    expect(source, contains("label: Text('从“\${_steps[_step]}”继续')"));
    expect(source, contains("!working.tags.contains(_boundaryCheckedTag)"));
    expect(source, contains("'__system_question_boundary_checked'"));
    expect(
      source.indexOf('working = working.copyWith(splitResult: splitResult)'),
      lessThan(source.indexOf(
        'questionRepositoryProvider).saveDraft(working)',
        source.indexOf('working = working.copyWith(splitResult: splitResult)'),
      )),
    );
  });

  test('analysis loading separates leaving, retrying, and replacing a capture', () {
    final source = File(
      'lib/src/features/analysis/presentation/analysis_loading_screen.dart',
    ).readAsStringSync();

    expect(source, contains('void _leaveAnalysis(String route)'));
    expect(source, contains("onPressed: () => _leaveAnalysis('/capture/correction')"));
    expect(source, contains('void _replaceCaptureWithNewPhoto()'));
    expect(source, contains('ref.read(captureSessionProvider.notifier).endSession();'));
    expect(source, contains('onPressed: _replaceCaptureWithNewPhoto'));
    expect(source, contains('保留当前图片和识别文本'));
  });
}
