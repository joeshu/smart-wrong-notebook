import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:smart_wrong_notebook/src/data/repositories/question_repository.dart';
import 'package:smart_wrong_notebook/src/domain/services/review_schedule_service.dart';
// 两个 timezone 子包共用 `tz` 前缀（flutter_local_notifications 推荐
// 写法）：data/latest_all 暴露 initializeTimeZones，timezone 暴露
// local / getLocation / TZDateTime / UTC 等。这样 tz.local 才可用。
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

/// 错题本复习提醒通知服务。
///
/// 提供两类能力：
/// - 即时提醒：[checkAndNotify] 检查到期错题并立即推送（保留旧行为）。
/// - 定时提醒：[scheduleDailyReminder] 在每天指定时刻（本地时区）触发
///   复习提醒，App 被系统挂起后仍能由操作系统唤醒。
///
/// Phase 9-3 扩展：新增 [scheduleDailyReminder] / [cancelScheduledReminder]
/// 两个方法，内部使用 [FlutterLocalNotificationsPlugin.zonedSchedule]
/// + [DateTimeComponents.time] 实现每日重复。
class NotificationService {
  NotificationService({required QuestionRepository questionRepository})
      : _questionRepository = questionRepository;

  final QuestionRepository _questionRepository;
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  bool _notificationsAllowed = true;
  bool _timeZoneInitialized = false;

  /// 定时复习提醒使用的通知 ID（与即时通知 ID 0 区分）。
  static const int scheduledReminderId = 1;

  Future<bool> init() async {
    if (_initialized) return _notificationsAllowed;

    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings();
    const settings = InitializationSettings(android: android, iOS: ios);
    await _plugin.initialize(settings);

    final androidPlugin = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    final androidAllowed = await androidPlugin?.requestNotificationsPermission();
    final iosPlugin = _plugin.resolvePlatformSpecificImplementation<
        IOSFlutterLocalNotificationsPlugin>();
    final iosAllowed = await iosPlugin?.requestPermissions(
      alert: true,
      badge: true,
      sound: true,
    );
    _notificationsAllowed = androidAllowed ?? iosAllowed ?? true;
    _initialized = true;
    return _notificationsAllowed;
  }

  /// 初始化 timezone 数据并设置本地时区。
  ///
  /// timezone 包默认 `tz.local` 为 UTC，需要显式调用
  /// [tz.setLocalLocation] 设置才能正确按本地时区调度。由于项目未引入
  /// flutter_native_timezone，这里通过 [DateTime.timeZoneOffset] 推算
  /// 偏移量并匹配最接近的 IANA 时区名。失败时回退到 UTC（用户感知为
  /// 提醒时间与本地有偏移）。
  Future<void> _ensureTimeZoneInitialized() async {
    if (_timeZoneInitialized) return;
    tz.initializeTimeZones();
    // 通过当前 UTC 偏移查找匹配时区。Asia/Shanghai (UTC+8) 是最常见的
    // 国内场景，作为偏移匹配失败时的兜底默认值。
    final offset = DateTime.now().timeZoneOffset;
    final candidateZones = <String>[
      'Asia/Shanghai',
      'Asia/Hong_Kong',
      'Asia/Tokyo',
      'Asia/Seoul',
      'Asia/Singapore',
      'UTC',
    ];
    tz.Location? matched;
    for (final name in candidateZones) {
      try {
        final loc = tz.getLocation(name);
        final now = tz.TZDateTime.now(loc);
        if (now.timeZoneOffset.inMinutes == offset.inMinutes) {
          matched = loc;
          break;
        }
      } catch (_) {
        // 该时区名无效，跳过。
      }
    }
    tz.setLocalLocation(matched ?? tz.UTC);
    _timeZoneInitialized = true;
  }

  /// Sends an immediate reminder only when questions are actually due.
  /// Timed background scheduling is intentionally handled separately: local
  /// notifications cannot re-check the database after iOS suspends the app.
  Future<bool> checkAndNotify() async {
    final allowed = await init();
    if (!allowed) return false;
    final all = await _questionRepository.listAll();
    const scheduler = ReviewScheduleService();
    final dueCount = all.where(scheduler.isDue).length;

    if (dueCount > 0) {
      await _plugin.show(
        0,
        '错题本复习提醒',
        '你有 $dueCount 道错题待复习，快来巩固吧！',
        const NotificationDetails(
          android: AndroidNotificationDetails(
            'review_reminder',
            '复习提醒',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          ),
          iOS: DarwinNotificationDetails(),
        ),
      );
      return true;
    }
    return false;
  }

  /// Phase 9-3：调度每日定时复习提醒。
  ///
  /// [hour] / [minute] 为本地时区的目标时刻（24 小时制）。
  /// 若该时刻已过今天，则从明天开始触发；之后每天重复。
  /// 返回 true 表示调度成功。
  ///
  /// 注意：iOS 在 App 完全退出后可能不触发，需系统后台保活；
  /// Android 用 [AndroidScheduleMode.inexactAllowWhileIdle] 兼顾电量。
  Future<bool> scheduleDailyReminder({
    required int hour,
    required int minute,
  }) async {
    final allowed = await init();
    if (!allowed) return false;
    await _ensureTimeZoneInitialized();
    await cancelScheduledReminder();

    final now = tz.TZDateTime.now(tz.local);
    var scheduled = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );
    // 若今天的提醒时刻已过，则推迟到明天。
    if (scheduled.isBefore(now)) {
      scheduled = scheduled.add(const Duration(days: 1));
    }

    await _plugin.zonedSchedule(
      scheduledReminderId,
      '错题本复习提醒',
      '到时间复习错题了，打开 App 看看今天的待办吧！',
      scheduled,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'review_reminder_scheduled',
          '定时复习提醒',
          importance: Importance.defaultImportance,
          priority: Priority.defaultPriority,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      // iOS 要求显式声明日期解释方式：absoluteTime 表示按调度时刻的
      // 绝对时间触发，不受设备时区变化影响（与 Android 行为对齐）。
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      matchDateTimeComponents: DateTimeComponents.time,
    );
    return true;
  }

  /// Phase 9-3：取消定时复习提醒（不影响即时通知 ID 0）。
  Future<void> cancelScheduledReminder() async {
    await _plugin.cancel(scheduledReminderId);
  }

  Future<void> cancelAll() async {
    await _plugin.cancelAll();
  }
}
