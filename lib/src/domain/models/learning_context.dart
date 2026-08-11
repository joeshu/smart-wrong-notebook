/// Learning context stored as reserved tags so existing Drift databases and
/// JSON backups remain compatible without a destructive schema migration.
/// Values are hidden from ordinary tag presentation by [QuestionRecord].
enum QuestionDifficulty { foundation, advanced, challenge, custom }

enum AttemptStatus { notAttempted, wrongAttempt, incomplete, unknown }

/// Phase 13-3：FSRS 卡片状态。
///
/// 与 [MasteryLevel] 并存：MasteryLevel 仍用于 UI 展示，FsrsState 用于
/// 调度算法内部状态。映射关系：
/// - newQuestion → New
/// - reviewing → Learning 或 Review（由 fsrsState 字段决定）
/// - mastered → Review（FSRS 无永久掌握态）
enum FsrsState { newCard, learning, review, relearning }

class LearningContextCodec {
  const LearningContextCodec._();

  static const _stagePrefix = '__system_learning_stage:';
  static const _difficultyPrefix = '__system_difficulty:';
  static const _attemptPrefix = '__system_attempt_status:';
  static const _studentWorkPrefix = '__system_student_work:';

  // Phase 13-3：FSRS 状态用 5 个保留 tag 编码，避免 drift schema 迁移。
  static const _fsrsStabilityPrefix = '__system_fsrs_s:';
  static const _fsrsDifficultyPrefix = '__system_fsrs_d:';
  static const _fsrsStatePrefix = '__system_fsrs_state:';
  static const _fsrsRepsPrefix = '__system_fsrs_reps:';
  static const _fsrsLapsesPrefix = '__system_fsrs_lapses:';
  static const _fsrsLastReviewPrefix = '__system_fsrs_last_review:';

  static String? learningStage(Iterable<String> tags) =>
      _readText(tags, _stagePrefix);

  static QuestionDifficulty? difficulty(Iterable<String> tags) =>
      _readEnum(tags, _difficultyPrefix, QuestionDifficulty.values);

  static AttemptStatus? attemptStatus(Iterable<String> tags) =>
      _readEnum(tags, _attemptPrefix, AttemptStatus.values);

  static String? studentWork(Iterable<String> tags) =>
      _readText(tags, _studentWorkPrefix);

  /// Phase 13-3：读取 FSRS 稳定性（天）。无记录返回 null。
  static double? fsrsStability(Iterable<String> tags) =>
      _readDouble(tags, _fsrsStabilityPrefix);

  /// Phase 13-3：读取 FSRS 难度（1-10）。无记录返回 null。
  static double? fsrsDifficulty(Iterable<String> tags) =>
      _readDouble(tags, _fsrsDifficultyPrefix);

  static FsrsState? fsrsState(Iterable<String> tags) =>
      _readEnum(tags, _fsrsStatePrefix, FsrsState.values);

  static int? fsrsReps(Iterable<String> tags) => _readInt(tags, _fsrsRepsPrefix);

  static int? fsrsLapses(Iterable<String> tags) =>
      _readInt(tags, _fsrsLapsesPrefix);

  static DateTime? fsrsLastReview(Iterable<String> tags) {
    final value = _readText(tags, _fsrsLastReviewPrefix);
    if (value == null) return null;
    return DateTime.tryParse(value);
  }

  static List<String> write({
    required Iterable<String> tags,
    String? learningStage,
    QuestionDifficulty? difficulty,
    AttemptStatus? attemptStatus,
    String? studentWork,
  }) {
    final prefixes = [_stagePrefix, _difficultyPrefix, _attemptPrefix, _studentWorkPrefix];
    final result = tags.where((tag) => !prefixes.any(tag.startsWith)).toList();
    _appendText(result, _stagePrefix, learningStage);
    if (difficulty != null) result.add('$_difficultyPrefix${difficulty.name}');
    if (attemptStatus != null) result.add('$_attemptPrefix${attemptStatus.name}');
    _appendText(result, _studentWorkPrefix, studentWork);
    return result;
  }

  /// Phase 13-3：写入 FSRS 状态。null 字段会清除对应 tag。
  static List<String> writeFsrs({
    required Iterable<String> tags,
    required double stability,
    required double difficulty,
    required FsrsState state,
    required int reps,
    required int lapses,
    required DateTime lastReview,
  }) {
    final prefixes = [
      _fsrsStabilityPrefix,
      _fsrsDifficultyPrefix,
      _fsrsStatePrefix,
      _fsrsRepsPrefix,
      _fsrsLapsesPrefix,
      _fsrsLastReviewPrefix,
    ];
    final result = tags.where((tag) => !prefixes.any(tag.startsWith)).toList();
    result.add('$_fsrsStabilityPrefix${_formatDouble(stability)}');
    result.add('$_fsrsDifficultyPrefix${_formatDouble(difficulty)}');
    result.add('$_fsrsStatePrefix${state.name}');
    result.add('$_fsrsRepsPrefix$reps');
    result.add('$_fsrsLapsesPrefix$lapses');
    result.add('$_fsrsLastReviewPrefix${lastReview.toIso8601String()}');
    return result;
  }

  /// Phase 13-3：清除所有 FSRS tag（reset 时调用）。
  static List<String> clearFsrs(Iterable<String> tags) {
    final prefixes = [
      _fsrsStabilityPrefix,
      _fsrsDifficultyPrefix,
      _fsrsStatePrefix,
      _fsrsRepsPrefix,
      _fsrsLapsesPrefix,
      _fsrsLastReviewPrefix,
    ];
    return tags.where((tag) => !prefixes.any(tag.startsWith)).toList();
  }

  static bool isReservedTag(String tag) => tag.startsWith(_stagePrefix) ||
      tag.startsWith(_difficultyPrefix) ||
      tag.startsWith(_attemptPrefix) ||
      tag.startsWith(_studentWorkPrefix) ||
      tag.startsWith(_fsrsStabilityPrefix) ||
      tag.startsWith(_fsrsDifficultyPrefix) ||
      tag.startsWith(_fsrsStatePrefix) ||
      tag.startsWith(_fsrsRepsPrefix) ||
      tag.startsWith(_fsrsLapsesPrefix) ||
      tag.startsWith(_fsrsLastReviewPrefix);

  static String? _readText(Iterable<String> tags, String prefix) {
    for (final tag in tags) {
      if (tag.startsWith(prefix)) {
        final value = tag.substring(prefix.length).trim();
        return value.isEmpty ? null : value;
      }
    }
    return null;
  }

  static T? _readEnum<T extends Enum>(Iterable<String> tags, String prefix, List<T> values) {
    final value = _readText(tags, prefix);
    if (value == null) return null;
    for (final item in values) {
      if (item.name == value) return item;
    }
    return null;
  }

  static double? _readDouble(Iterable<String> tags, String prefix) {
    final value = _readText(tags, prefix);
    if (value == null) return null;
    return double.tryParse(value);
  }

  static int? _readInt(Iterable<String> tags, String prefix) {
    final value = _readText(tags, prefix);
    if (value == null) return null;
    return int.tryParse(value);
  }

  static String _formatDouble(double value) {
    // 保留 4 位小数，去掉尾部 0，避免 tag 过长。
    var s = value.toStringAsFixed(4);
    while (s.endsWith('0')) {
      s = s.substring(0, s.length - 1);
    }
    if (s.endsWith('.')) s = s.substring(0, s.length - 1);
    return s;
  }

  static void _appendText(List<String> tags, String prefix, String? value) {
    final normalized = value?.trim().replaceAll(',', '，');
    if (normalized != null && normalized.isNotEmpty) tags.add('$prefix$normalized');
  }
}
