/// 学习目标与打卡系统数据模型。
///
/// `GoalCheckin` 记录某一天的完成题数与打卡状态；
/// `GoalSettings` 保存用户设置（每日目标题数、是否自动打卡、是否开启提醒）。
class GoalCheckin {
  GoalCheckin({
    required this.id,
    required this.date,
    required this.completedCount,
    required this.manualCheckin,
    required this.createdAt,
  });

  /// 记录唯一 ID（uuid v4）。
  final String id;

  /// 当天 00:00（本地时间），作为按日唯一键。
  final DateTime date;

  /// 当日完成的题数（录入 + 复习累计）。
  final int completedCount;

  /// 是否由用户手动打卡；false 表示自动打卡或尚未打卡。
  final bool manualCheckin;

  /// 记录创建时间。
  final DateTime createdAt;

  GoalCheckin copyWith({
    String? id,
    DateTime? date,
    int? completedCount,
    bool? manualCheckin,
    DateTime? createdAt,
  }) {
    return GoalCheckin(
      id: id ?? this.id,
      date: date ?? this.date,
      completedCount: completedCount ?? this.completedCount,
      manualCheckin: manualCheckin ?? this.manualCheckin,
      createdAt: createdAt ?? this.createdAt,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'id': id,
      'date': date.toIso8601String(),
      'completedCount': completedCount,
      'manualCheckin': manualCheckin,
      'createdAt': createdAt.toIso8601String(),
    };
  }

  factory GoalCheckin.fromJson(Map<String, dynamic> json) {
    return GoalCheckin(
      id: json['id'] as String,
      date: DateTime.parse(json['date'] as String),
      completedCount: (json['completedCount'] as num).toInt(),
      manualCheckin: json['manualCheckin'] as bool? ?? false,
      createdAt: DateTime.parse(json['createdAt'] as String),
    );
  }
}

class GoalSettings {
  const GoalSettings({
    this.dailyTarget = 10,
    this.autoCheckin = true,
    this.reminderEnabled = false,
  });

  /// 每日学习目标题数，默认 10。
  final int dailyTarget;

  /// 完成目标后是否自动打卡，默认 true。
  final bool autoCheckin;

  /// 是否开启学习提醒，默认 false。
  final bool reminderEnabled;

  GoalSettings copyWith({
    int? dailyTarget,
    bool? autoCheckin,
    bool? reminderEnabled,
  }) {
    return GoalSettings(
      dailyTarget: dailyTarget ?? this.dailyTarget,
      autoCheckin: autoCheckin ?? this.autoCheckin,
      reminderEnabled: reminderEnabled ?? this.reminderEnabled,
    );
  }

  Map<String, dynamic> toJson() {
    return <String, dynamic>{
      'dailyTarget': dailyTarget,
      'autoCheckin': autoCheckin,
      'reminderEnabled': reminderEnabled,
    };
  }

  factory GoalSettings.fromJson(Map<String, dynamic> json) {
    return GoalSettings(
      dailyTarget: (json['dailyTarget'] as num?)?.toInt() ?? 10,
      autoCheckin: json['autoCheckin'] as bool? ?? true,
      reminderEnabled: json['reminderEnabled'] as bool? ?? false,
    );
  }
}
