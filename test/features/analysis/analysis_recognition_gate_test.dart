import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/data/remote/ai/ai_analysis_service.dart';
import 'package:smart_wrong_notebook/src/data/repositories/question_repository.dart';
import 'package:smart_wrong_notebook/src/data/repositories/settings_repository.dart';
import 'package:smart_wrong_notebook/src/domain/models/ai_provider_config.dart';
import 'package:smart_wrong_notebook/src/domain/models/analysis_result.dart';
import 'package:smart_wrong_notebook/src/domain/models/content_status.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';
import 'package:smart_wrong_notebook/src/domain/services/recognition_confirmation_policy.dart';
import 'package:smart_wrong_notebook/src/features/analysis/presentation/analysis_loading_screen.dart';

class _Settings implements SettingsRepository {
  @override
  Future<AiProviderConfig?> getAiProviderConfig() async => const AiProviderConfig(
    id: 'test', displayName: 'Test', baseUrl: 'https://test', model: 'model', apiKey: 'key');
  @override
  Future<String?> getString(String key) async => null;
  @override
  Future<void> saveAiProviderConfig(AiProviderConfig config) async {}
  @override
  Future<void> setString(String key, String value) async {}
  @override
  Future<bool> isQuickCaptureEnabled() async => false;
  @override
  Future<void> setQuickCaptureEnabled(bool enabled) async {}
}

void main() {
  testWidgets('new capture stops at recognition gate before AI solving', (tester) async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    final settings = _Settings();
    final service = TestAiAnalysisService(
      settingsRepository: settings,
      extractionResult: const AiQuestionExtractionResult(
        extractedQuestionText: 'OCR 原文',
        normalizedQuestionText: '规范化题干',
        subject: Subject.math,
      ),
      analysisResultValue: const AnalysisResult(
        subject: Subject.math,
        finalAnswer: '不应调用',
        steps: <String>[],
        aiTags: <String>[],
        knowledgePoints: <String>[],
        mistakeReason: '',
        studyAdvice: '',
      ),
    );
    final repository = InMemoryQuestionRepository();
    final container = ProviderContainer(overrides: [
      settingsRepositoryProvider.overrideWithValue(settings),
      aiAnalysisServiceProvider.overrideWithValue(service),
      questionRepositoryProvider.overrideWithValue(repository),
    ]);
    addTearDown(container.dispose);
    container.read(currentQuestionProvider.notifier).state = QuestionRecord.draft(
      id: 'gate-1', imagePath: '/tmp/missing.jpg', subject: Subject.math, recognizedText: '',
    ).copyWith(tags: const <String>[RecognitionConfirmationPolicy.requiredTag]);
    final router = GoRouter(
      initialLocation: '/analysis/loading',
      routes: <GoRoute>[
        GoRoute(path: '/analysis/loading', builder: (_, __) => const AnalysisLoadingScreen()),
        GoRoute(path: '/capture/recognition-confirmation', builder: (_, __) => const Scaffold(body: Text('RECOGNITION_GATE'))),
      ],
    );
    await tester.pumpWidget(UncontrolledProviderScope(
      container: container,
      child: MaterialApp.router(routerConfig: router),
    ));
    await tester.pumpAndSettle();
    expect(find.text('RECOGNITION_GATE'), findsOneWidget);
    expect(service.extractionCallCount, 1);
    expect(service.analysisCallCount, 0);
    expect(container.read(currentQuestionProvider)?.contentStatus, ContentStatus.needsConfirmation);
    expect((await repository.getById('gate-1'))?.normalizedQuestionText, '规范化题干');
  });
}
