import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smart_wrong_notebook/l10n/generated/app_localizations.dart';
import 'package:smart_wrong_notebook/src/app/onboarding_notifier.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/app/router.dart';
import 'package:smart_wrong_notebook/src/data/repositories/drift_settings_repository.dart';
import 'package:smart_wrong_notebook/src/data/repositories/drift_question_repository.dart';
import 'package:smart_wrong_notebook/src/data/repositories/drift_review_log_repository.dart';
import 'package:smart_wrong_notebook/src/data/repositories/knowledge_point_repository.dart';
import 'package:smart_wrong_notebook/src/data/repositories/question_knowledge_link_repository.dart';
import 'package:smart_wrong_notebook/src/data/repositories/shared_prefs_question_repository.dart';
import 'package:smart_wrong_notebook/src/data/repositories/shared_prefs_review_log_repository.dart';
import 'package:smart_wrong_notebook/src/data/migrations/legacy_data_migration.dart';
import 'package:smart_wrong_notebook/src/data/local/app_database.dart';
import 'package:smart_wrong_notebook/src/data/repositories/worksheet_import_repository.dart';
import 'package:smart_wrong_notebook/src/app/theme/app_theme.dart';
import 'package:smart_wrong_notebook/src/data/files/image_storage_service.dart';
import 'package:smart_wrong_notebook/src/domain/services/analysis_recovery_service.dart';
import 'package:smart_wrong_notebook/src/shared/widgets/katex_math_view.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  KatexMathView.preload();

  final db = AppDatabase();
  final settingsRepo = DriftSettingsRepository(db);
  final questionRepo = DriftQuestionRepository(db);
  final reviewLogRepo = DriftReviewLogRepository(db);
  // Phase 4 知识点迁移依赖：播种受控知识点树，把现有题目的
  // aiKnowledgePoints 自由文本映射为结构化关联。迁移幂等，失败可重试。
  final knowledgePointRepo = KnowledgePointRepository();
  final questionKnowledgeLinkRepo = QuestionKnowledgeLinkRepository();
  await LegacyDataMigration(
    settings: settingsRepo,
    questions: questionRepo,
    legacyQuestions: SharedPrefsQuestionRepository(),
    reviewLogs: reviewLogRepo,
    legacyReviewLogs: SharedPrefsReviewLogRepository(),
    knowledgePointRepo: knowledgePointRepo,
    questionKnowledgeLinkRepo: questionKnowledgeLinkRepo,
  ).migrateIfNeeded();

  // 跨进程恢复：如果 App 在 AI 分析中被系统杀掉，启动时把“分析中”
  // 草稿标记为“分析失败，可重试”，避免题目长期卡在处理中。
  const analysisRecovery = AnalysisRecoveryService();
  final existingQuestions = await questionRepo.listAll();
  for (final recovered in analysisRecovery.recoverAll(existingQuestions)) {
    final original = existingQuestions.firstWhere((item) => item.id == recovered.id);
    if (original.contentStatus != recovered.contentStatus ||
        original.lastAnalysisError != recovered.lastAnalysisError) {
      await questionRepo.saveDraft(recovered);
    }
  }

  // 跨进程恢复：App 被系统杀掉后，启动时从持久化仓库读回未完成的导入批次，
  // 避免批次状态丢失。通过 override 注入初始值，UI 即可显示"继续处理"入口。
  final worksheetImportRepo = WorksheetImportRepository();
  final restoredWorksheetImport =
      await loadWorksheetImportSession(worksheetImportRepo);

  // 在构建 router 之前先同步加载 onboarding 状态，避免启动闪烁。
  final onboardingNotifier = OnboardingNotifier(initialDone: false);
  await onboardingNotifier.loadFromSettings(settingsRepo.getString);

  final router = buildRouter(
    settingsRepo,
    onboardingNotifier: onboardingNotifier,
  );

  runApp(
    ProviderScope(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        settingsRepositoryProvider.overrideWithValue(settingsRepo),
        questionRepositoryProvider.overrideWithValue(questionRepo),
        reviewLogRepositoryProvider.overrideWithValue(reviewLogRepo),
        knowledgePointRepositoryProvider.overrideWithValue(knowledgePointRepo),
        questionKnowledgeLinkRepositoryProvider.overrideWithValue(questionKnowledgeLinkRepo),
        worksheetImportRepositoryProvider.overrideWithValue(worksheetImportRepo),
        currentWorksheetImportProvider.overrideWith((_) => restoredWorksheetImport),
        // 跨进程恢复：批量队列的"自动连续分析"开关也要随 session 一起恢复，
        // 否则用户在批量分析中被杀掉重启后会丢失"继续处理剩余题目"的入口。
        worksheetAutoAnalyzeProvider
            .overrideWith((_) => restoredWorksheetImport?.autoAnalyze ?? false),
        onboardingNotifierProvider.overrideWithValue(onboardingNotifier),
        // 注意：不要 override aiAnalysisServiceProvider，让它使用 settingsRepo
        imageStorageServiceProvider.overrideWithValue(ImageStorageService()),
      ],
      child: Consumer(
        builder: (context, ref, _) => MaterialApp.router(
          title: 'AI错题本',
          theme: buildLightTheme(
            style: ref.watch(appVisualStyleProvider),
          ),
          darkTheme: buildDarkTheme(
            style: ref.watch(appVisualStyleProvider),
          ),
          themeMode: ref.watch(themeModeProvider),
          routerConfig: router,
          debugShowCheckedModeBanner: false,
          localizationsDelegates: const <LocalizationsDelegate<dynamic>>[
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          supportedLocales: AppLocalizations.supportedLocales,
        ),
      ),
    ),
  );
}
