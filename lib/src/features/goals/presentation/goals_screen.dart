import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/data/repositories/shared_prefs_goal_checkin_repository.dart';
import 'package:smart_wrong_notebook/src/domain/models/goal_checkin.dart';
import 'package:smart_wrong_notebook/src/domain/services/goal_checkin_service.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_colors.dart';
import 'package:smart_wrong_notebook/src/shared/ui/app_ui.dart';

/// 学习目标与打卡详情页。
///
/// 顶部展示今日目标进度卡片，中部为目标设置，底部为最近 30 天打卡日历。
class GoalsScreen extends ConsumerStatefulWidget {
  const GoalsScreen({super.key});

  @override
  ConsumerState<GoalsScreen> createState() => _GoalsScreenState();
}

class _GoalsScreenState extends ConsumerState<GoalsScreen> {
  late final SharedPrefsGoalCheckinRepository _repository;
  late final GoalCheckinService _service;

  GoalSettings _settings = const GoalSettings();
  GoalCheckin? _today;
  int _streak = 0;
  List<GoalCheckin> _recentCheckins = const <GoalCheckin>[];
  bool _loading = true;

  final TextEditingController _targetController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _repository = SharedPrefsGoalCheckinRepository();
    _service = GoalCheckinService(
      _repository,
      ref.read(settingsRepositoryProvider),
    );
    _loadAll();
  }

  @override
  void dispose() {
    _targetController.dispose();
    _repository.dispose();
    super.dispose();
  }

  Future<void> _loadAll() async {
    final settings = await _service.getSettings();
    final today = await _service.getToday();
    final streak = await _service.calculateStreak();
    final all = await _service.listAllSorted();
    if (!mounted) return;
    setState(() {
      _settings = settings;
      _today = today;
      _streak = streak;
      _recentCheckins = all;
      _targetController.text = settings.dailyTarget.toString();
      _loading = false;
    });
  }

  Future<void> _onCheckin() async {
    await _service.checkinManually();
    await _loadAll();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已手动打卡')),
    );
  }

  Future<void> _onAutoCheckinChanged(bool value) async {
    final newSettings = _settings.copyWith(autoCheckin: value);
    await _service.setSettings(newSettings);
    setState(() {
      _settings = newSettings;
    });
  }

  Future<void> _onReminderChanged(bool value) async {
    final newSettings = _settings.copyWith(reminderEnabled: value);
    await _service.setSettings(newSettings);
    setState(() {
      _settings = newSettings;
    });
  }

  Future<void> _onTargetSubmitted() async {
    final parsed = int.tryParse(_targetController.text.trim());
    if (parsed == null || parsed <= 0) {
      _targetController.text = _settings.dailyTarget.toString();
      return;
    }
    final newSettings = _settings.copyWith(dailyTarget: parsed);
    await _service.setSettings(newSettings);
    setState(() {
      _settings = newSettings;
    });
    await _loadAll();
  }

  bool _isTodayCheckedIn() {
    final today = _today;
    if (today == null) return false;
    if (today.manualCheckin) return true;
    return _settings.autoCheckin &&
        today.completedCount >= _settings.dailyTarget;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('学习目标'),
        leading: IconButton(
          icon: const Icon(CupertinoIcons.chevron_left),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: _loading
          ? const AppLoadingState()
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                  AppSpace.lg, AppSpace.md, AppSpace.lg, AppSpace.xl),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  _TodayProgressCard(
                    settings: _settings,
                    today: _today,
                    streak: _streak,
                    checkedIn: _isTodayCheckedIn(),
                    onCheckin: _onCheckin,
                  ),
                  const SizedBox(height: AppSpace.xl),
                  const AppSectionTitle('目标设置'),
                  const SizedBox(height: AppSpace.md),
                  _SettingsCard(
                    settings: _settings,
                    targetController: _targetController,
                    onTargetSubmitted: _onTargetSubmitted,
                    onAutoCheckinChanged: _onAutoCheckinChanged,
                    onReminderChanged: _onReminderChanged,
                  ),
                  const SizedBox(height: AppSpace.xl),
                  const AppSectionTitle('最近 30 天打卡'),
                  const SizedBox(height: AppSpace.md),
                  _CheckinCalendar(
                    settings: _settings,
                    checkins: _recentCheckins,
                  ),
                ],
              ),
            ),
    );
  }
}

class _TodayProgressCard extends StatelessWidget {
  const _TodayProgressCard({
    required this.settings,
    required this.today,
    required this.streak,
    required this.checkedIn,
    required this.onCheckin,
  });

  final GoalSettings settings;
  final GoalCheckin? today;
  final int streak;
  final bool checkedIn;
  final Future<void> Function() onCheckin;

  @override
  Widget build(BuildContext context) {
    final completed = today?.completedCount ?? 0;
    final target = settings.dailyTarget;
    final progress = target > 0 ? (completed / target).clamp(0.0, 1.0) : 0.0;
    final colorScheme = Theme.of(context).colorScheme;

    return AppCard(
      backgroundColor: checkedIn
          ? AppColors.semanticContainer(AppColors.success,
              isDark: Theme.of(context).brightness == Brightness.dark)
          : AppColors.semanticContainer(AppColors.primary,
              isDark: Theme.of(context).brightness == Brightness.dark),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Icon(
                checkedIn
                    ? CupertinoIcons.checkmark_seal_fill
                    : CupertinoIcons.flag_fill,
                size: 18,
                color: checkedIn ? AppColors.success : AppColors.primary,
              ),
              const SizedBox(width: AppSpace.sm),
              Text(
                '今日学习目标',
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              const Spacer(),
              if (streak > 0)
                Row(
                  children: <Widget>[
                    Icon(CupertinoIcons.flame_fill,
                        size: 16, color: AppColors.warning),
                    const SizedBox(width: 4),
                    Text(
                      '连续 $streak 天',
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.onSurfaceVariant,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: <Widget>[
              Text(
                '$completed',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: colorScheme.onSurface,
                ),
              ),
              Text(
                ' / $target 题',
                style: TextStyle(
                  fontSize: 14,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(width: AppSpace.sm),
              if (checkedIn)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpace.sm, vertical: 2),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(AppRadius.small),
                  ),
                  child: Text(
                    '已打卡',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.success,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpace.md),
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.small),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 8,
              backgroundColor: colorScheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(
                checkedIn ? AppColors.success : AppColors.primary,
              ),
            ),
          ),
          const SizedBox(height: AppSpace.lg),
          Row(
            children: <Widget>[
              Expanded(
                child: FilledButton.icon(
                  onPressed: checkedIn ? null : () => onCheckin(),
                  icon: const Icon(CupertinoIcons.checkmark_circle, size: 18),
                  label: const Text('打卡'),
                  style: FilledButton.styleFrom(
                    backgroundColor:
                        checkedIn ? null : AppColors.success,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: AppSpace.md),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.settings,
    required this.targetController,
    required this.onTargetSubmitted,
    required this.onAutoCheckinChanged,
    required this.onReminderChanged,
  });

  final GoalSettings settings;
  final TextEditingController targetController;
  final Future<void> Function() onTargetSubmitted;
  final Future<void> Function(bool) onAutoCheckinChanged;
  final Future<void> Function(bool) onReminderChanged;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return AppCard(
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '每日目标题数',
                  style: TextStyle(fontSize: 14, color: colorScheme.onSurface),
                ),
              ),
              SizedBox(
                width: 72,
                child: TextField(
                  controller: targetController,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.right,
                  decoration: const InputDecoration(
                    isDense: true,
                    suffixText: '题',
                    border: InputBorder.none,
                  ),
                  onEditingComplete: onTargetSubmitted,
                  onSubmitted: (_) => onTargetSubmitted(),
                ),
              ),
            ],
          ),
          Divider(
            height: 1,
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        '完成目标自动打卡',
                        style: TextStyle(
                            fontSize: 14, color: colorScheme.onSurface),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '达成每日目标后自动记录打卡',
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: settings.autoCheckin,
                  onChanged: onAutoCheckinChanged,
                ),
              ],
            ),
          ),
          Divider(
            height: 1,
            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpace.sm),
            child: Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    '学习提醒',
                    style: TextStyle(
                        fontSize: 14, color: colorScheme.onSurface),
                  ),
                ),
                Switch(
                  value: settings.reminderEnabled,
                  onChanged: onReminderChanged,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CheckinCalendar extends StatelessWidget {
  const _CheckinCalendar({
    required this.settings,
    required this.checkins,
  });

  final GoalSettings settings;
  final List<GoalCheckin> checkins;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    // 构造最近 30 天（含今天）的日期列表，按时间倒序（最新在左）。
    final days = List<DateTime>.generate(30, (i) {
      return today.subtract(Duration(days: 29 - i));
    });

    final Map<String, GoalCheckin> byDay = <String, GoalCheckin>{};
    for (final c in checkins) {
      final key =
          '${c.date.year}-${c.date.month}-${c.date.day}';
      byDay[key] = c;
    }

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 7,
              mainAxisSpacing: AppSpace.sm,
              crossAxisSpacing: AppSpace.sm,
            ),
            itemCount: days.length,
            itemBuilder: (BuildContext context, int index) {
              final day = days[index];
              final key = '${day.year}-${day.month}-${day.day}';
              final checkin = byDay[key];
              final isCheckedIn = checkin != null &&
                  (checkin.manualCheckin ||
                      (settings.autoCheckin &&
                          checkin.completedCount >= settings.dailyTarget));
              final isToday = day == today;

              return Tooltip(
                message: _formatDate(day) +
                    (checkin == null
                        ? ''
                        : ' · ${checkin.completedCount} 题${checkin.manualCheckin ? ' · 手动' : ''}'),
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isCheckedIn
                        ? AppColors.success
                        : colorScheme.surfaceContainerHighest,
                    border: isToday
                        ? Border.all(color: AppColors.primary, width: 2)
                        : null,
                  ),
                  alignment: Alignment.center,
                  child: isCheckedIn
                      ? const Icon(CupertinoIcons.check_mark,
                          size: 14, color: Colors.white)
                      : Text(
                          '${day.day}',
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                ),
              );
            },
          ),
          const SizedBox(height: AppSpace.md),
          Row(
            children: <Widget>[
              _LegendDot(
                color: AppColors.success,
                label: '已打卡',
                textColor: colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpace.lg),
              _LegendDot(
                color: colorScheme.surfaceContainerHighest,
                label: '未打卡',
                textColor: colorScheme.onSurfaceVariant,
              ),
              const Spacer(),
              Text(
                '共 ${checkins.where((c) => c.manualCheckin || (settings.autoCheckin && c.completedCount >= settings.dailyTarget)).length} 天打卡',
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime d) {
    return '${d.month}-${d.day}';
  }
}

class _LegendDot extends StatelessWidget {
  const _LegendDot({
    required this.color,
    required this.label,
    required this.textColor,
  });

  final Color color;
  final String label;
  final Color textColor;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color),
        ),
        const SizedBox(width: AppSpace.xs),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: textColor),
        ),
      ],
    );
  }
}
