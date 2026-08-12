import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/data/repositories/question_repository.dart';
import 'package:smart_wrong_notebook/src/data/repositories/settings_repository.dart';
import 'package:smart_wrong_notebook/src/data/services/capture_service.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';
import 'package:smart_wrong_notebook/src/features/capture/presentation/capture_entry_sheet.dart';
import 'package:smart_wrong_notebook/src/features/notebook/presentation/worksheet_workbench_screen.dart';

class _SpyCaptureService extends CaptureService {
  _SpyCaptureService() : super();

  int cameraCalls = 0;
  int galleryCalls = 0;

  @override
  Future<CaptureResult> pickFromCamera() async {
    cameraCalls++;
    return CaptureResult.cancel();
  }

  @override
  Future<CaptureResult> pickFromGallery() async {
    galleryCalls++;
    return CaptureResult.cancel();
  }
}

void main() {
  testWidgets('worksheet workbench renders its empty-state action', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        questionRepositoryProvider.overrideWithValue(
          InMemoryQuestionRepository(),
        ),
      ],
      child: const MaterialApp(home: WorksheetWorkbenchScreen()),
    ));
    await tester.pumpAndSettle();

    expect(find.text('还没有可组卷的错题'), findsOneWidget);
    expect(find.text('去添加错题'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('add-question sheet renders its supported entry actions',
      (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [
        questionRepositoryProvider.overrideWithValue(
          InMemoryQuestionRepository(),
        ),
        settingsRepositoryProvider.overrideWithValue(
          InMemorySettingsRepository(),
        ),
      ],
      child: MaterialApp(
        theme: ThemeData.dark(useMaterial3: true),
        home: const Scaffold(body: CaptureEntrySheet()),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('录入错题'), findsOneWidget);
    expect(find.text('拍照'), findsOneWidget);
    expect(find.text('相册'), findsOneWidget);
    expect(find.text('复制粘贴录入'), findsOneWidget);
    expect(find.text('识别选项'), findsOneWidget);
    expect(find.textContaining('PaddleOCR'), findsNothing);
    expect(find.textContaining('MinerU'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('active capture blocks replacement capture at the behavior boundary',
      (tester) async {
    final capture = _SpyCaptureService();
    final container = ProviderContainer(overrides: [
      questionRepositoryProvider.overrideWithValue(
        InMemoryQuestionRepository(),
      ),
      settingsRepositoryProvider.overrideWithValue(
        InMemorySettingsRepository(),
      ),
      captureServiceProvider.overrideWithValue(capture),
    ]);
    addTearDown(container.dispose);

    final record = QuestionRecord.draft(
      id: 'active-capture',
      imagePath: '/tmp/active-capture.jpg',
      subject: Subject.math,
      recognizedText: '待处理题目',
    );
    final session = container.read(captureSessionProvider.notifier);
    session.selectImage(record.imagePath);
    session.setCurrentQuestion(record);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: Scaffold(body: CaptureEntrySheet()),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('继续当前录题'), findsOneWidget);
    await tester.ensureVisible(find.text('拍照'));
    await tester.tap(find.text('拍照'));
    await tester.pump();

    expect(capture.cameraCalls, 0);
    expect(capture.galleryCalls, 0);
    expect(
      find.text('当前已有录入任务正在处理中，请先继续或取消后再录入。'),
      findsOneWidget,
    );
    expect(container.read(currentQuestionProvider), same(record));
    expect(container.read(captureSessionProvider).imagePath, record.imagePath);
  });

  testWidgets('active capture can be discarded from the entry sheet',
      (tester) async {
    final container = ProviderContainer(overrides: [
      questionRepositoryProvider.overrideWithValue(
        InMemoryQuestionRepository(),
      ),
      settingsRepositoryProvider.overrideWithValue(
        InMemorySettingsRepository(),
      ),
      captureServiceProvider.overrideWithValue(_SpyCaptureService()),
    ]);
    addTearDown(container.dispose);

    final record = QuestionRecord.draft(
      id: 'discard-me',
      imagePath: '/tmp/discard-me.jpg',
      subject: Subject.math,
      recognizedText: '待处理题目',
    );
    final session = container.read(captureSessionProvider.notifier);
    session.selectImage(record.imagePath);
    session.setCurrentQuestion(record);
    await container
        .read(questionRepositoryProvider)
        .saveDraft(record);

    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: const MaterialApp(
        home: Scaffold(body: CaptureEntrySheet()),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('继续当前录题'), findsOneWidget);
    await tester.ensureVisible(find.text('放弃当前任务'));
    await tester.tap(find.text('放弃当前任务'));
    await tester.pumpAndSettle();

    // 确认弹窗
    expect(find.text('放弃当前录入任务？'), findsOneWidget);
    await tester.tap(find.text('放弃并删除'));
    await tester.pumpAndSettle();

    debugPrint('[DISCARD] after tap: current=${container.read(currentQuestionProvider)} '
        'phase=${container.read(captureSessionProvider).phase}');
    expect(container.read(currentQuestionProvider), isNull);
    expect(container.read(captureSessionProvider).isTerminal, isTrue);
    expect(find.text('继续当前录题'), findsNothing);
    // 放弃后拍照入口重新可用（不再被拦截）
    await tester.tap(find.text('拍照'));
    await tester.pump();
    expect(find.text('当前已有录入任务正在处理中，请先继续或取消后再录入。'),
        findsNothing);
  });
}
