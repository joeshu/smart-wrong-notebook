import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/core/constants/app_strings.dart';
import 'package:smart_wrong_notebook/src/data/services/notification_service.dart';
import 'package:smart_wrong_notebook/src/domain/models/learning_context.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_colors.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_ui.dart';
import 'package:smart_wrong_notebook/src/shared/widgets/post_recognition_ai_dialog.dart';

/// 学习设置页面（Phase 9-3 / Phase 10-3）。
///
/// 承载每日复习目标入口（跳 `/goals`）、复习提醒时间显示、难度偏好、
/// 知识树显示层级、识别后默认 AI 行为五项设置。难度偏好/层级/默认 AI
/// 用 SharedPreferences 持久化。
class LearningSettingsScreen extends ConsumerStatefulWidget {
  const LearningSettingsScreen({super.key});

  @override
  ConsumerState<LearningSettingsScreen> createState() =>
      _LearningSettingsScreenState();
}

class _LearningSettingsScreenState
    extends ConsumerState<LearningSettingsScreen> {
  static const _difficultyKey = 'pref_difficulty';
  static const _treeDepthKey = 'pref_knowledge_tree_depth';
  static const _postRecognitionAiKey = 'pref_post_recognition_ai';

  QuestionDifficulty? _difficulty;
  int _treeDepth = 3; // 默认知识点层
  PostRecognitionAiChoice _postRecognitionAi =
      PostRecognitionAiChoice.perQuestion; // 默认逐题选择
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadPrefs();
  }

  Future<void> _loadPrefs() async {
    final prefs = await SharedPreferences.getInstance();
    final diffStr = prefs.getString(_difficultyKey);
    final depth = prefs.getInt(_treeDepthKey) ?? 3;
    final aiStr =
        prefs.getString(_postRecognitionAiKey) ?? 'perQuestion';
    QuestionDifficulty? diff;
    if (diffStr != null) {
      for (final d in QuestionDifficulty.values) {
        if (d.name == diffStr) {
          diff = d;
          break;
        }
      }
    }
    PostRecognitionAiChoice aiChoice;
    switch (aiStr) {
      case 'none':
        aiChoice = PostRecognitionAiChoice.none;
        break;
      case 'all':
        aiChoice = PostRecognitionAiChoice.all;
        break;
      default:
        aiChoice = PostRecognitionAiChoice.perQuestion;
    }
    if (!mounted) return;
    setState(() {
      _difficulty = diff;
      _treeDepth = depth;
      _postRecognitionAi = aiChoice;
      _loading = false;
    });
  }

  Future<void> _setDifficulty(QuestionDifficulty? value) async {
    final prefs = await SharedPreferences.getInstance();
    if (value == null) {
      await prefs.remove(_difficultyKey);
    } else {
      await prefs.setString(_difficultyKey, value.name);
    }
    setState(() => _difficulty = value);
  }

  Future<void> _setTreeDepth(int value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_treeDepthKey, value);
    setState(() => _treeDepth = value);
  }

  Future<void> _setPostRecognitionAi(PostRecognitionAiChoice value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_postRecognitionAiKey, value.name);
    setState(() => _postRecognitionAi = value);
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final reminderTime = ref.watch(reviewReminderTimeProvider);
    return Scaffold(
      appBar: AppBar(title: const Text(AppStrings.settingsLearning)),
      body: _loading
          ? const AppLoadingState()
          : SingleChildScrollView(
              padding: const EdgeInsets.all(AppSpace.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  AppSectionTitle(AppStrings.settingsDailyGoal),
                  const SizedBox(height: AppSpace.md),
                  AppCard(
                    child: AppListTile(
                      icon: CupertinoIcons.flag_fill,
                      iconColor: AppColors.primary,
                      iconBackgroundColor: AppColors.primaryContainerLight,
                      title: AppStrings.settingsDailyGoal,
                      subtitle: AppStrings.settingsDailyGoalSubtitle,
                      onTap: () => context.push('/goals'),
                    ),
                  ),
                  const SizedBox(height: AppSpace.xl),

                  // Phase 9-3：定时复习提醒时间
                  AppSectionTitle(AppStrings.settingsReviewReminderTime),
                  const SizedBox(height: AppSpace.md),
                  AppCard(
                    child: AppListTile(
                      icon: CupertinoIcons.bell,
                      iconColor: AppColors.warning,
                      iconBackgroundColor: AppColors.warningContainerLight,
                      title: AppStrings.settingsReviewReminderTime,
                      subtitle: AppStrings.settingsReviewReminderTimeSubtitle,
                      trailing: Text(
                        _formatTimeOfDay(reminderTime),
                        style: TextStyle(
                          fontSize: 14,
                          color: colorScheme.onSurfaceVariant,
                          fontFeatures: const <FontFeature>[
                            FontFeature.tabularFigures(),
                          ],
                        ),
                      ),
                      onTap: () => _pickReminderTime(context, ref),
                    ),
                  ),
                  const SizedBox(height: AppSpace.xl),

                  // Phase 10-3：识别后默认是否交给 AI
                  AppSectionTitle('识别后默认行为'),
                  const SizedBox(height: AppSpace.md),
                  AppCard(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpace.lg, vertical: AppSpace.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            'PaddleOCR / MinerU / Auto 识别完成后的默认动作',
                            style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: AppSpace.sm),
                          for (final choice in PostRecognitionAiChoice.values)
                            RadioListTile<PostRecognitionAiChoice>(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              value: choice,
                              groupValue: _postRecognitionAi,
                              title: Text(_postRecognitionAiLabel(choice)),
                              subtitle: Text(
                                _postRecognitionAiDescription(choice),
                                style: const TextStyle(fontSize: 11),
                              ),
                              onChanged: (v) {
                                if (v != null) _setPostRecognitionAi(v);
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpace.xl),

                  AppSectionTitle(AppStrings.settingsDifficultyPreference),
                  const SizedBox(height: AppSpace.md),
                  AppCard(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpace.lg, vertical: AppSpace.sm),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            AppStrings.settingsDifficultyPreferenceSubtitle,
                            style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: AppSpace.sm),
                          Wrap(
                            spacing: AppSpace.sm,
                            children: <Widget>[
                              _buildDifficultyChip(null, '不指定'),
                              _buildDifficultyChip(
                                  QuestionDifficulty.foundation, '基础'),
                              _buildDifficultyChip(
                                  QuestionDifficulty.advanced, '进阶'),
                              _buildDifficultyChip(
                                  QuestionDifficulty.challenge, '挑战'),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpace.xl),
                  AppSectionTitle(AppStrings.settingsKnowledgeTreeDepth),
                  const SizedBox(height: AppSpace.md),
                  AppCard(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: AppSpace.lg, vertical: AppSpace.md),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: <Widget>[
                          Text(
                            AppStrings.settingsKnowledgeTreeDepthSubtitle,
                            style: TextStyle(
                                fontSize: 12,
                                color: colorScheme.onSurfaceVariant),
                          ),
                          const SizedBox(height: AppSpace.sm),
                          for (var i = 1; i <= 4; i++)
                            RadioListTile<int>(
                              dense: true,
                              contentPadding: EdgeInsets.zero,
                              value: i,
                              groupValue: _treeDepth,
                              title: Text(_depthLabel(i)),
                              onChanged: (v) {
                                if (v != null) _setTreeDepth(v);
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildDifficultyChip(QuestionDifficulty? value, String label) {
    final selected = _difficulty == value;
    final scheme = Theme.of(context).colorScheme;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => _setDifficulty(selected ? null : value),
      selectedColor: scheme.primaryContainer,
      labelStyle: TextStyle(
        color: selected ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
        fontSize: 13,
      ),
    );
  }

  String _depthLabel(int depth) {
    switch (depth) {
      case 1:
        return '科目层';
      case 2:
        return '模块层';
      case 3:
        return '章节 / 知识点';
      case 4:
        return '考点（最深）';
      default:
        return '层级 $depth';
    }
  }

  String _postRecognitionAiLabel(PostRecognitionAiChoice choice) {
    switch (choice) {
      case PostRecognitionAiChoice.none:
        return '仅保留识别结果';
      case PostRecognitionAiChoice.perQuestion:
        return '逐题选择（默认）';
      case PostRecognitionAiChoice.all:
        return '全部交给普通 AI';
    }
  }

  String _postRecognitionAiDescription(PostRecognitionAiChoice choice) {
    switch (choice) {
      case PostRecognitionAiChoice.none:
        return '不调用 AI，所有题框 analyzeWithAi=false';
      case PostRecognitionAiChoice.perQuestion:
        return '保留各题默认值，由用户在工作台逐题切换';
      case PostRecognitionAiChoice.all:
        return '所有题框 analyzeWithAi=true，直接进入 AI 分析';
    }
  }

  /// Phase 9-3：把 [TimeOfDay] 格式化为 `HH:MM`。
  String _formatTimeOfDay(TimeOfDay t) {
    final hh = t.hour.toString().padLeft(2, '0');
    final mm = t.minute.toString().padLeft(2, '0');
    return '$hh:$mm';
  }

  /// Phase 9-3：弹出时间选择器，写入 provider；若主开关已开启则同步重排
  /// 定时提醒。通知权限未授予时给出提示但不阻止写入（用户可后续开启）。
  Future<void> _pickReminderTime(BuildContext context, WidgetRef ref) async {
    final current = ref.read(reviewReminderTimeProvider);
    final picked = await showTimePicker(
      context: context,
      initialTime: current,
      helpText: '选择每日复习提醒时间',
      confirmText: '确定',
      cancelText: '取消',
    );
    if (picked == null) return;
    await ref.read(reviewReminderTimeProvider.notifier).setTime(picked);
    if (!context.mounted) return;
    final enabled = ref.read(reviewReminderEnabledProvider);
    if (!enabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('时间已保存。请到「设置 → 复习提醒」打开开关以启用每日推送。'),
        ),
      );
      return;
    }
    final svc = ref.read(notificationServiceProvider);
    final ok = await svc.scheduleDailyReminder(
      hour: picked.hour,
      minute: picked.minute,
    );
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok
            ? '${AppStrings.settingsReviewReminderTimeScheduled}（${_formatTimeOfDay(picked)}）'
            : AppStrings.settingsReviewReminderTimePermissionDenied),
      ),
    );
  }
}

