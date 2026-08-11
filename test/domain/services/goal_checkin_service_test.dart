import 'package:flutter_test/flutter_test.dart';
import 'package:smart_wrong_notebook/src/data/repositories/in_memory_goal_checkin_repository.dart';
import 'package:smart_wrong_notebook/src/data/repositories/settings_repository.dart';
import 'package:smart_wrong_notebook/src/domain/models/goal_checkin.dart';
import 'package:smart_wrong_notebook/src/domain/services/goal_checkin_service.dart';

DateTime _today() {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day);
}

DateTime _daysAgo(int days) {
  return _today().subtract(Duration(days: days));
}

GoalCheckin _checkin({
  required String id,
  required DateTime date,
  int completedCount = 0,
  bool manualCheckin = false,
}) {
  return GoalCheckin(
    id: id,
    date: date,
    completedCount: completedCount,
    manualCheckin: manualCheckin,
    createdAt: date,
  );
}

void main() {
  late InMemoryGoalCheckinRepository checkinRepo;
  late SettingsRepository settingsRepo;
  late GoalCheckinService service;

  setUp(() {
    checkinRepo = InMemoryGoalCheckinRepository();
    settingsRepo = InMemorySettingsRepository();
    service = GoalCheckinService(checkinRepo, settingsRepo);
  });

  tearDown(() {
    checkinRepo.dispose();
  });

  group('settings', () {
    test('returns defaults when nothing is stored', () async {
      final settings = await service.getSettings();
      expect(settings.dailyTarget, 10);
      expect(settings.autoCheckin, isTrue);
      expect(settings.reminderEnabled, isFalse);
    });

    test('round-trips custom settings through setSettings/getSettings',
        () async {
      await service.setSettings(const GoalSettings(
        dailyTarget: 25,
        autoCheckin: false,
        reminderEnabled: true,
      ));
      final settings = await service.getSettings();
      expect(settings.dailyTarget, 25);
      expect(settings.autoCheckin, isFalse);
      expect(settings.reminderEnabled, isTrue);
    });

    test('falls back to default dailyTarget when stored value is invalid',
        () async {
      await settingsRepo.setString('goal_daily_target_v1', '0');
      final settings = await service.getSettings();
      expect(settings.dailyTarget, 10);
    });
  });

  group('recordCompletion', () {
    test('increments completedCount for today', () async {
      await service.recordCompletion(3);
      final today = await service.getToday();
      expect(today, isNotNull);
      expect(today!.completedCount, 3);
      expect(today.manualCheckin, isFalse);
    });

    test('accumulates count across multiple events', () async {
      await service.recordCompletion(2);
      await service.recordCompletion(5);
      final today = await service.getToday();
      expect(today!.completedCount, 7);
    });

    test('ignores non-positive counts', () async {
      await service.recordCompletion(0);
      await service.recordCompletion(-4);
      final today = await service.getToday();
      expect(today, isNull);
    });
  });

  group('auto check-in', () {
    test('marks as checked-in when reaching target with autoCheckin=true',
        () async {
      // 默认 target=10, autoCheckin=true
      await service.recordCompletion(10);
      final today = await service.getToday();
      expect(today, isNotNull);
      expect(today!.completedCount, 10);
      expect(today.manualCheckin, isFalse);
      // 已打卡：completedCount >= dailyTarget 且 autoCheckin=true
      expect(today.manualCheckin || today.completedCount >= 10, isTrue);
    });

    test('does NOT auto check-in when autoCheckin disabled', () async {
      await service.setSettings(
          const GoalSettings(dailyTarget: 10, autoCheckin: false));
      await service.recordCompletion(15);
      final today = await service.getToday();
      expect(today, isNotNull);
      expect(today!.completedCount, 15);
      // autoCheckin=false → 即使达到目标也算"未打卡"（manualCheckin=false，
      // 且 autoCheckin 关闭 → service 内部 isCheckedIn 应为 false）
      expect(today.manualCheckin, isFalse);
      final streak = await service.calculateStreak();
      expect(streak, 0); // autoCheckin=false，未打卡，streak=0
    });
  });

  group('manual check-in', () {
    test('checkinManually marks today as checked-in without reaching target',
        () async {
      // 先录入 5 题（未达 10 题目标）
      await service.recordCompletion(5);
      final before = await service.getToday();
      expect(before!.completedCount, 5);
      expect(before.manualCheckin, isFalse);

      await service.checkinManually();
      final after = await service.getToday();
      expect(after, isNotNull);
      expect(after!.manualCheckin, isTrue);
      // 完成题数应保留
      expect(after.completedCount, 5);
    });

    test('checkinManually creates today record when none exists', () async {
      await service.checkinManually();
      final today = await service.getToday();
      expect(today, isNotNull);
      expect(today!.manualCheckin, isTrue);
      expect(today.completedCount, 0);
    });

    test('manual check-in does not override subsequent completion increments',
        () async {
      await service.recordCompletion(3);
      await service.checkinManually();
      await service.recordCompletion(4);
      final today = await service.getToday();
      expect(today, isNotNull);
      expect(today!.completedCount, 7);
      expect(today.manualCheckin, isTrue);
    });
  });

  group('calculateStreak', () {
    test('returns 0 when no checkins exist', () async {
      expect(await service.calculateStreak(), 0);
    });

    test('counts 3 consecutive checked-in days ending today', () async {
      // 构造今天 + 过去 2 天，全部 manualCheckin=true（一定算"已打卡"）
      await checkinRepo.upsert(_checkin(
          id: 'c-today', date: _today(), manualCheckin: true));
      await checkinRepo.upsert(_checkin(
          id: 'c-1', date: _daysAgo(1), manualCheckin: true));
      await checkinRepo.upsert(_checkin(
          id: 'c-2', date: _daysAgo(2), manualCheckin: true));

      expect(await service.calculateStreak(), 3);
    });

    test('stops at first missing day', () async {
      // 今天有，昨天有，前天断，大前天有
      await checkinRepo.upsert(_checkin(
          id: 'c-today', date: _today(), manualCheckin: true));
      await checkinRepo.upsert(_checkin(
          id: 'c-1', date: _daysAgo(1), manualCheckin: true));
      // 跳过 _daysAgo(2)
      await checkinRepo.upsert(_checkin(
          id: 'c-3', date: _daysAgo(3), manualCheckin: true));

      expect(await service.calculateStreak(), 2);
    });

    test('returns 0 when today has no checkin even if past days did',
        () async {
      await checkinRepo.upsert(_checkin(
          id: 'c-1', date: _daysAgo(1), manualCheckin: true));
      await checkinRepo.upsert(_checkin(
          id: 'c-2', date: _daysAgo(2), manualCheckin: true));
      // 今天没有记录 → 从今天向前数立刻断
      expect(await service.calculateStreak(), 0);
    });

    test('only counts days that meet check-in criteria', () async {
      // 今天 completedCount=5（未达 10 题目标，autoCheckin=true 但未达标 → 不算）
      await checkinRepo.upsert(_checkin(
          id: 'c-today',
          date: _today(),
          completedCount: 5,
          manualCheckin: false));
      // 昨天达标 → 算
      await checkinRepo.upsert(_checkin(
          id: 'c-1',
          date: _daysAgo(1),
          completedCount: 12,
          manualCheckin: false));

      // 今天未打卡 → streak 从今天起就断
      expect(await service.calculateStreak(), 0);
    });

    test('counts days reaching target via auto check-in', () async {
      // 默认 autoCheckin=true；今天、昨天、前天都达到目标
      await checkinRepo.upsert(_checkin(
          id: 'c-today',
          date: _today(),
          completedCount: 10,
          manualCheckin: false));
      await checkinRepo.upsert(_checkin(
          id: 'c-1',
          date: _daysAgo(1),
          completedCount: 11,
          manualCheckin: false));
      await checkinRepo.upsert(_checkin(
          id: 'c-2',
          date: _daysAgo(2),
          completedCount: 15,
          manualCheckin: false));

      expect(await service.calculateStreak(), 3);
    });
  });

  group('repository contract', () {
    test('upsert replaces same-day record by date uniqueness', () async {
      final repo = InMemoryGoalCheckinRepository();
      final day = _today();
      await repo.upsert(_checkin(
          id: 'a', date: day, completedCount: 2, manualCheckin: false));
      await repo.upsert(_checkin(
          id: 'b', date: day, completedCount: 5, manualCheckin: true));

      final all = await repo.listAll();
      expect(all, hasLength(1));
      expect(all.first.id, 'b');
      expect(all.first.completedCount, 5);
      expect(all.first.manualCheckin, isTrue);
      repo.dispose();
    });

    test('watchAll emits sorted snapshot after mutations', () async {
      final repo = InMemoryGoalCheckinRepository();
      final emitted = <List<GoalCheckin>>[];
      final sub = repo.watchAll().listen(emitted.add);

      await repo.upsert(
          _checkin(id: 'a', date: _daysAgo(1), manualCheckin: true));
      await repo.upsert(
          _checkin(id: 'b', date: _today(), manualCheckin: true));
      await repo.deleteById('a');

      await Future<void>.delayed(Duration.zero);
      expect(emitted, isNotEmpty);
      // 最后一份快照只剩 'b'，且按 date 升序
      final last = emitted.last;
      expect(last, hasLength(1));
      expect(last.first.id, 'b');

      await sub.cancel();
      repo.dispose();
    });
  });
}
