import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:smart_wrong_notebook/src/app/theme/app_visual_style.dart';
import 'package:smart_wrong_notebook/src/app/onboarding_notifier.dart';
import 'package:smart_wrong_notebook/src/core/constants/app_strings.dart';
import 'package:smart_wrong_notebook/src/features/home/presentation/home_screen.dart';
import 'package:smart_wrong_notebook/src/features/notebook/presentation/notebook_screen.dart';
import 'package:smart_wrong_notebook/src/features/notebook/presentation/question_detail_screen.dart';
import 'package:smart_wrong_notebook/src/features/notebook/presentation/worksheet_workbench_screen.dart';
import 'package:smart_wrong_notebook/src/features/notebook/presentation/worksheet_preview_screen.dart';
import 'package:smart_wrong_notebook/src/features/onboarding/presentation/onboarding_screen.dart';
import 'package:smart_wrong_notebook/src/features/review/presentation/review_history_screen.dart';
import 'package:smart_wrong_notebook/src/features/review/presentation/review_screen.dart';
import 'package:smart_wrong_notebook/src/features/settings/presentation/settings_screen.dart';
import 'package:smart_wrong_notebook/src/features/settings/presentation/provider_config_screen.dart';
import 'package:smart_wrong_notebook/src/features/settings/presentation/model_strategy_center_screen.dart';
import 'package:smart_wrong_notebook/src/features/settings/presentation/layout_provider_config_screen.dart';
import 'package:smart_wrong_notebook/src/features/settings/presentation/subject_management_screen.dart';
import 'package:smart_wrong_notebook/src/features/settings/presentation/prompt_settings_screen.dart';
import 'package:smart_wrong_notebook/src/features/settings/presentation/data_management_screen.dart';
import 'package:smart_wrong_notebook/src/features/settings/presentation/learning_settings_screen.dart';
import 'package:smart_wrong_notebook/src/features/settings/presentation/about_screen.dart';
import 'package:smart_wrong_notebook/src/features/settings/presentation/export_workbench_screen.dart';
import 'package:smart_wrong_notebook/src/features/settings/presentation/weekly_report_screen.dart';
import 'package:smart_wrong_notebook/src/features/settings/presentation/subject_radar_screen.dart';
import 'package:smart_wrong_notebook/src/features/settings/presentation/mistake_trend_screen.dart';
import 'package:smart_wrong_notebook/src/features/goals/presentation/goals_screen.dart';
import 'package:smart_wrong_notebook/src/features/knowledge_tree/presentation/knowledge_point_detail_screen.dart';
import 'package:smart_wrong_notebook/src/features/knowledge_tree/presentation/knowledge_tree_management_screen.dart';
import 'package:smart_wrong_notebook/src/features/knowledge_tree/presentation/knowledge_tree_screen.dart';
import 'package:smart_wrong_notebook/src/features/capture/presentation/add_screen.dart';
import 'package:smart_wrong_notebook/src/features/capture/presentation/capture_entry_launcher.dart';
import 'package:smart_wrong_notebook/src/features/capture/presentation/image_crop_screen.dart';
import 'package:smart_wrong_notebook/src/features/capture/presentation/question_correction_screen.dart';
import 'package:smart_wrong_notebook/src/features/worksheet_import/presentation/worksheet_import_screen.dart';
import 'package:smart_wrong_notebook/src/features/worksheet_import/presentation/worksheet_region_editor_screen.dart';
import 'package:smart_wrong_notebook/src/features/worksheet_import/presentation/worksheet_review_summary_screen.dart';
import 'package:smart_wrong_notebook/src/features/ocr/presentation/question_save_confirmation_screen.dart';
import 'package:smart_wrong_notebook/src/features/ocr/presentation/recognition_confirmation_screen.dart';
import 'package:smart_wrong_notebook/src/features/ocr/presentation/question_split_confirmation_screen.dart';
import 'package:smart_wrong_notebook/src/features/analysis/presentation/analysis_loading_screen.dart';
import 'package:smart_wrong_notebook/src/features/analysis/presentation/analysis_result_screen.dart';
import 'package:smart_wrong_notebook/src/features/analysis/presentation/exercise_practice_screen.dart';
import 'package:smart_wrong_notebook/src/data/repositories/settings_repository.dart';

GoRouter buildRouter(SettingsRepository settingsRepo,
    {required OnboardingNotifier onboardingNotifier}) {
  return GoRouter(
    initialLocation: '/',
    refreshListenable: onboardingNotifier,
    redirect: (BuildContext context, GoRouterState state) {
      final onboardingDone = onboardingNotifier.done;
      final inOnboarding = state.matchedLocation == '/onboarding';
      // 读取 settings 出错时不强制跳转，避免把用户卡在 onboarding 死循环里。
      if (onboardingNotifier.error != null) return null;
      if (!onboardingDone && !inOnboarding) {
        return '/onboarding';
      }
      if (onboardingDone && inOnboarding) {
        return '/';
      }
      return null;
    },
    routes: <RouteBase>[
      GoRoute(
          path: '/onboarding',
          pageBuilder: (_, __) => _buildPage(const OnboardingScreen())),
      // Compatibility entry points remain deep-linkable but are not primary tabs.
      GoRoute(
          path: '/add',
          pageBuilder: (_, __) => _buildPage(const AddScreen())),
      GoRoute(
          path: '/export',
          pageBuilder: (_, __) => _buildPage(const ExportWorkbenchScreen())),
      StatefulShellRoute.indexedStack(
        builder: (BuildContext context, GoRouterState state,
            StatefulNavigationShell navigationShell) {
          return ScaffoldWithNavBar(navigationShell: navigationShell);
        },
        branches: <StatefulShellBranch>[
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(path: '/', builder: (_, __) => const HomeScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                  path: '/notebook',
                  builder: (_, __) => const NotebookScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                  path: '/review', builder: (_, __) => const ReviewScreen()),
            ],
          ),
          StatefulShellBranch(
            routes: <RouteBase>[
              GoRoute(
                path: '/settings',
                builder: (_, __) => const SettingsScreen(),
                routes: <RouteBase>[
                  GoRoute(
                    path: 'provider',
                    builder: (_, __) => const ModelStrategyCenterScreen(),
                    routes: <RouteBase>[
                      GoRoute(
                        path: 'edit',
                        builder: (_, __) => const ProviderConfigScreen(),
                      ),
                    ],
                  ),
                  GoRoute(
                      path: 'subjects',
                      builder: (_, __) => const SubjectManagementScreen()),
                  GoRoute(
                      path: 'prompts',
                      builder: (_, __) => const PromptSettingsScreen()),
                  GoRoute(
                      path: 'layout',
                      builder: (_, __) => const LayoutProviderConfigScreen()),
                  GoRoute(
                    path: 'data',
                    builder: (_, __) => const DataManagementScreen()),
                  GoRoute(
                    path: 'knowledge-tree',
                    builder: (_, __) => const KnowledgeTreeScreen(),
                  ),
                  GoRoute(
                    path: 'export-workbench',
                    builder: (context, state) {
                      final raw = state.uri.queryParameters['ids'];
                      final ids = raw == null || raw.isEmpty
                          ? const <String>[]
                          : raw
                              .split(',')
                              .map((s) => s.trim())
                              .where((s) => s.isNotEmpty)
                              .toList(growable: false);
                      return ExportWorkbenchScreen(
                        initialQuestionIds: ids,
                        showBackButton: true,
                      );
                    },
                  ),
                  GoRoute(
                    path: 'weekly-report',
                    builder: (_, __) => const WeeklyReportScreen(),
                  ),
                  GoRoute(
                    path: 'subject-radar',
                    builder: (_, __) => const SubjectRadarScreen(),
                  ),
                  GoRoute(
                    path: 'mistake-trend',
                    builder: (_, __) => const MistakeTrendScreen(),
                  ),
                  GoRoute(
                    path: 'learning',
                    builder: (_, __) => const LearningSettingsScreen(),
                  ),
                  GoRoute(
                    path: 'about',
                    builder: (_, __) => const AboutScreen(),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
      GoRoute(
          path: '/capture/crop',
          pageBuilder: (_, __) => _buildPage(const ImageCropScreen())),
      GoRoute(
          path: '/worksheet/import',
          pageBuilder: (_, __) => _buildPage(const WorksheetImportScreen())),
      GoRoute(
          path: '/worksheet/review-summary',
          pageBuilder: (_, __) => _buildPage(const WorksheetReviewSummaryScreen())),
      GoRoute(
          path: '/worksheet/regions',
          pageBuilder: (_, __) => _buildPage(const WorksheetRegionEditorScreen())),
      GoRoute(
          path: '/capture/correction',
          pageBuilder: (_, __) => _buildPage(const QuestionCorrectionScreen())),
      GoRoute(
          path: '/capture/recognition-confirmation',
          pageBuilder: (_, __) =>
              _buildPage(const RecognitionConfirmationScreen())),
      GoRoute(
          path: '/capture/save-confirmation',
          pageBuilder: (_, __) =>
              _buildPage(const QuestionSaveConfirmationScreen())),
      GoRoute(
          path: '/capture/split-confirmation',
          pageBuilder: (_, __) =>
              _buildPage(const QuestionSplitConfirmationScreen())),
      GoRoute(
          path: '/analysis/loading',
          pageBuilder: (_, __) => _buildPage(const AnalysisLoadingScreen())),
      GoRoute(
          path: '/analysis/result',
          pageBuilder: (_, __) => _buildPage(const AnalysisResultScreen())),
      GoRoute(
          path: '/exercise/practice',
          pageBuilder: (_, __) => _buildPage(const ExercisePracticeScreen())),
      GoRoute(
          path: '/worksheet',
          pageBuilder: (_, __) => _buildPage(const WorksheetWorkbenchScreen())),
      GoRoute(
          path: '/worksheet/preview',
          pageBuilder: (_, __) =>
              _buildPage(const WorksheetPreviewScreen())),
      GoRoute(
          path: '/notebook/question/:id',
          pageBuilder: (_, __) => _buildPage(const QuestionDetailScreen())),
      GoRoute(
          path: '/review/history',
          pageBuilder: (_, __) => _buildPage(const ReviewHistoryScreen())),
      GoRoute(
          path: '/goals',
          pageBuilder: (_, __) => _buildPage(const GoalsScreen())),
      GoRoute(
        path: '/knowledge-tree/detail/:id',
        pageBuilder: (context, state) => _buildPage(
          KnowledgePointDetailScreen(
            knowledgePointId: state.pathParameters['id']!,
          ),
        ),
      ),
      GoRoute(
        path: '/knowledge-tree/manage',
        pageBuilder: (_, __) =>
            _buildPage(const KnowledgeTreeManagementScreen()),
      ),
    ],
  );
}

Page<void> _buildPage(Widget child) => MaterialPage<void>(child: child);

class ScaffoldWithNavBar extends StatelessWidget {
  const ScaffoldWithNavBar({required this.navigationShell, super.key});

  final StatefulNavigationShell navigationShell;

  @override
  Widget build(BuildContext context) {
    final visual = AppVisualTokens.of(context);
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final decoration = switch (visual.style) {
      AppVisualStyle.academic => BoxDecoration(
          color: scheme.surface,
          border: Border(top: BorderSide(color: scheme.outlineVariant)),
        ),
      AppVisualStyle.paper => BoxDecoration(
          color: scheme.surface,
          border: Border(
            top: BorderSide(
              color: scheme.primary.withValues(alpha: isDark ? .34 : .20),
            ),
          ),
        ),
      AppVisualStyle.aurora => BoxDecoration(
          gradient: LinearGradient(
            colors: <Color>[
              scheme.surface,
              scheme.primaryContainer.withValues(alpha: isDark ? .24 : .36),
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          boxShadow: <BoxShadow>[
            BoxShadow(
              color: scheme.primary.withValues(alpha: isDark ? .12 : .10),
              blurRadius: 18,
              offset: const Offset(0, -4),
            ),
          ],
        ),
      AppVisualStyle.forest => BoxDecoration(
          color: scheme.surface,
          border: Border(
            top: BorderSide(
              color: scheme.secondary.withValues(alpha: isDark ? .28 : .18),
            ),
          ),
        ),
    };

    return Scaffold(
      body: navigationShell,
      floatingActionButton: FloatingActionButton(
        tooltip: AppStrings.homeCapture,
        onPressed: () => CaptureEntryLauncher.show(context),
        child: const Icon(CupertinoIcons.camera),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      bottomNavigationBar: AnimatedContainer(
        duration: const Duration(milliseconds: 260),
        decoration: decoration,
        child: NavigationBar(
          backgroundColor: Colors.transparent,
          selectedIndex: navigationShell.currentIndex,
          onDestinationSelected: (int index) => navigationShell.goBranch(index),
          destinations: const <NavigationDestination>[
            NavigationDestination(
              icon: Icon(CupertinoIcons.house),
              selectedIcon: Icon(CupertinoIcons.house_fill),
              label: AppStrings.homeTab,
            ),
            NavigationDestination(
              icon: Icon(CupertinoIcons.book),
              selectedIcon: Icon(CupertinoIcons.book_fill),
              label: AppStrings.notebookTab,
            ),
            NavigationDestination(
              icon: Icon(CupertinoIcons.arrow_2_circlepath),
              label: AppStrings.reviewTab,
            ),
            NavigationDestination(
              icon: Icon(CupertinoIcons.gear),
              selectedIcon: Icon(CupertinoIcons.gear_solid),
              label: AppStrings.settingsTab,
            ),
          ],
        ),
      ),
    );
  }
}
