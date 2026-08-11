import 'package:smart_wrong_notebook/src/data/repositories/settings_repository.dart';
import 'package:smart_wrong_notebook/src/domain/models/goal_checkin.dart';
import 'package:smart_wrong_notebook/src/domain/repositories/goal_checkin_repository.dart';
import 'package:uuid/uuid.dart';

/// 学习目标与打卡业务服务。
///
/// 协调 [GoalCheckinRepository]（打卡记录）与 [SettingsRepository]（用户
/// 设置）：
/// - 读写 [GoalSettings]（每日目标、自动打卡、提醒开关）。
/// - 处理 `recordCompletion` 事件：自增当日 `completedCount`，若达成目标
///   且 `autoCheckin=true` 则视为自动打卡。
/// - `checkinManually` 将当日记录标记为手动打卡。
/// - `calculateStreak` 从今天向前数连续打卡天数。
class GoalCheckinService {
  GoalCheckinService(this._checkinRepo, this._settingsRepo);

  final GoalCheckinRepository _checkinRepo;
  final SettingsRepository _settingsRepo;

  static const String _keyDailyTarget = 'goal_daily_target_v1';
  static const String _keyAutoCheckin = 'goal_auto_checkin_v1';
  static const String _keyReminder = 'goal_reminder_enabled_v1';

  /// 读取学习目标设置。未设置时返回默认值（target=10, autoCheckin=true,
  /// reminder=false）。
  Future<GoalSettings> getSettings() async {
    final dailyTargetStr = await _settingsRepo.getString(_keyDailyTarget);
    final autoCheckinStr = await _settingsRepo.getString(_keyAutoCheckin);
    final reminderStr = await _settingsRepo.getString(_keyReminder);

    var dailyTarget = int.tryParse(dailyTargetStr ?? '') ?? 10;
    if (dailyTarget <= 0) dailyTarget = 10;
    // autoCheckin 默认 true：仅当显式存储为 "false" 时才关闭。
    final autoCheckin = autoCheckinStr != 'false';
    // reminder 默认 false：仅当显式存储为 "true" 时才开启。
    final reminder = reminderStr == 'true';

    return GoalSettings(
      dailyTarget: dailyTarget,
      autoCheckin: autoCheckin,
      reminderEnabled: reminder,
    );
  }

  /// 持久化学习目标设置。
  Future<void> setSettings(GoalSettings settings) async {
    await _settingsRepo.setString(
        _keyDailyTarget, settings.dailyTarget.toString());
    await _settingsRepo.setString(
        _keyAutoCheckin, settings.autoCheckin ? 'true' : 'false');
    await _settingsRepo.setString(
        _keyReminder, settings.reminderEnabled ? 'true' : 'false');
  }

  /// 返回今日打卡记录（如有）。
  Future<GoalCheckin?> getToday() async {
    return _checkinRepo.getByDate(_today());
  }

  /// 记录一次题目录入/复习完成事件：自增今日 `completedCount`；若达成
  /// 目标且 `autoCheckin=true`，则记录会被视为自动打卡（`manualCheckin`
  /// 保持 `false`）。
  ///
  /// 若今日记录此前已被手动打卡（`manualCheckin=true`），后续的完成事件
  /// 只会累加 `completedCount`，不会撤销手动打卡标记。
  Future<void> recordCompletion(int count) async {
    if (count <= 0) return;
    final now = DateTime.now();
    final today = _normalize(now);

    final existing = await _checkinRepo.getByDate(today);
    final newCount = (existing?.completedCount ?? 0) + count;
    // 保留既有的 manualCheckin；新记录默认 false（即自动打卡或尚未打卡）。
    final manualCheckin = existing?.manualCheckin ?? false;

    final checkin = GoalCheckin(
      id: existing?.id ?? const Uuid().v4(),
      date: today,
      completedCount: newCount,
      manualCheckin: manualCheckin,
      createdAt: existing?.createdAt ?? now,
    );
    await _checkinRepo.upsert(checkin);
  }

  /// 手动打卡：将今日记录标记为 `manualCheckin=true`。若今日尚无记录，
  /// 则创建一条 `completedCount=0` 的手动打卡记录。
  Future<void> checkinManually() async {
    final now = DateTime.now();
    final today = _normalize(now);

    final existing = await _checkinRepo.getByDate(today);
    final checkin = GoalCheckin(
      id: existing?.id ?? const Uuid().v4(),
      date: today,
      completedCount: existing?.completedCount ?? 0,
      manualCheckin: true,
      createdAt: existing?.createdAt ?? now,
    );
    await _checkinRepo.upsert(checkin);
  }

  /// 计算连续打卡天数：从今天向前数，连续"已打卡"的天数。
  ///
  /// "已打卡"定义：当日的 [GoalCheckin] 记录存在，且满足
  /// `manualCheckin=true` 或（`completedCount >= dailyTarget` 且
  /// `autoCheckin=true`）。
  Future<int> calculateStreak() async {
    final settings = await getSettings();
    final all = await _checkinRepo.listAll();

    final Set<String> checkedInDays = <String>{};
    for (final c in all) {
      if (_isCheckedIn(c, settings)) {
        checkedInDays.add(_dayKey(c.date));
      }
    }

    var day = _today();
    var streak = 0;
    while (checkedInDays.contains(_dayKey(day))) {
      streak++;
      day = day.subtract(const Duration(days: 1));
    }
    return streak;
  }

  /// 返回全部打卡记录（按日期升序），供 UI 渲染日历使用。
  Future<List<GoalCheckin>> listAllSorted() async {
    final all = await _checkinRepo.listAll();
    final list = List<GoalCheckin>.of(all)
      ..sort((a, b) => a.date.compareTo(b.date));
    return list;
  }

  /// 判断单条记录是否算"已打卡"。
  bool _isCheckedIn(GoalCheckin c, GoalSettings settings) {
    if (c.manualCheckin) return true;
    return settings.autoCheckin && c.completedCount >= settings.dailyTarget;
  }

  DateTime _today() => _normalize(DateTime.now());

  DateTime _normalize(DateTime dt) {
    return DateTime(dt.year, dt.month, dt.day);
  }

  String _dayKey(DateTime d) => '${d.year}-${d.month}-${d.day}';
}
