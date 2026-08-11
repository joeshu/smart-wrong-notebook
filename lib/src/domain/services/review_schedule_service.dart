import 'package:smart_wrong_notebook/src/domain/models/content_status.dart';
import 'package:smart_wrong_notebook/src/domain/models/learning_context.dart';
import 'package:smart_wrong_notebook/src/domain/models/mastery_level.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';

/// 用户复习反馈档位（3 档映射到 FSRS 4 档的 Again/Hard/Good）。
///
/// - [forgot] → FSRS Again (1)：答错或完全忘记，重置稳定性、进入重学
/// - [hard] → FSRS Hard (2)：答对但吃力，稳定性小幅增长、间隔缩短
/// - [easy] → FSRS Good (3)：正常答对，稳定性按公式增长、间隔=稳定性
///
/// Phase 13-3：保留 3 档 UI 不变；如需 Easy(4) 档可在后续加按钮。
enum ReviewRating { forgot, hard, easy }

/// Phase 13-3：FSRS-4.5 简化实现（替换原固定间隔查表策略）。
///
/// **设计原则**：
/// - 保持 [apply] / [isDue] / [reset] 签名不变，6 处
///   `const ReviewScheduleService()` 调用零改动
/// - FSRS 状态用 `__system_fsrs_*:` 保留 tag 编码进 [QuestionRecord.tags]，
///   无需 drift schema 迁移
/// - 旧数据（无 fsrs tag）按 New 卡片初始化
/// - legacy mastered 题（nextReviewAt==null）保留 isDue 例外，避免旧数据
///   突然涌入队列
/// - [MasteryLevel] 与 [FsrsState] 并存：MasteryLevel 用于 UI，FsrsState
///   用于调度
///
/// **算法核心**（参考 FSRS-4.5）：
/// - stability（S）：记忆稳定性（天），随正确复习增长，答错重置
/// - difficulty（D）：1-10，初始 5.0-6.6，每次复习按 rating 调整
/// - state：New / Learning / Review / Relearning
/// - interval：Review 态 = S × ratio(rating)，Learning/Relearning = 固定短间隔
///
/// 与原固定间隔策略的关键差异：
/// - 间隔随 stability 增长而非封顶 30 天
/// - 答错后 stability 重置为 0.4×oldS（非固定 1 小时）
/// - 难度高的题稳定性增长慢（df = (10-D)/10 权重）
class ReviewScheduleService {
  const ReviewScheduleService();

  // FSRS-4.5 默认初始稳定性（按 rating 1-4 索引）。
  // 本实现 rating 1-3 对应 forgot/hard/easy，索引 0-2。
  static const List<double> _initialStability = <double>[0.4, 0.6, 2.4];

  // 难度边界。
  static const double _difficultyMin = 1.0;
  static const double _difficultyMax = 10.0;

  QuestionRecord apply(
    QuestionRecord question,
    ReviewRating rating, {
    DateTime? reviewedAt,
    bool forceMastered = false,
  }) {
    final now = reviewedAt ?? DateTime.now();
    final ratingIdx = _ratingIndex(rating); // 1-3

    // 读取当前 FSRS 状态（旧数据按 null 处理）。
    final tags = question.tags;
    final oldState = LearningContextCodec.fsrsState(tags) ?? FsrsState.newCard;
    final oldS = LearningContextCodec.fsrsStability(tags) ?? 0.0;
    final oldD = LearningContextCodec.fsrsDifficulty(tags) ??
        _initialDifficulty(ratingIdx);
    final oldReps = LearningContextCodec.fsrsReps(tags) ?? 0;
    final oldLapses = LearningContextCodec.fsrsLapses(tags) ?? 0;
    final oldLastReview = LearningContextCodec.fsrsLastReview(tags);

    late double newS;
    late double newD;
    late FsrsState newState;
    late int newReps;
    late int newLapses;
    late Duration interval;

    if (oldState == FsrsState.newCard) {
      // 第一次复习：按 rating 初始化 stability。
      newS = _initialStability[ratingIdx - 1];
      newD = _clampDifficulty(_initialDifficulty(ratingIdx));
      newState =
          ratingIdx >= 3 ? FsrsState.review : FsrsState.learning;
      newReps = 1;
      newLapses = ratingIdx == 1 ? 1 : 0;
      // 毕业到 Review：间隔 = stability × ratio；留在学习阶段：短间隔。
      interval = ratingIdx >= 3
          ? _reviewInterval(newS, ratingIdx)
          : _shortInterval(ratingIdx);
    } else if (oldState == FsrsState.learning ||
        oldState == FsrsState.relearning) {
      // 学习/重学阶段：Good/Easy 毕业，Again/Hard 留在原阶段。
      newD = _clampDifficulty(oldD + 0.1 * (ratingIdx - 3));
      newReps = oldReps + 1;
      // Learning/Relearning 阶段再次 forgot 不计为新 lapse：
      // 严格 FSRS 仅在 Review→Again（已学会后遗忘）时 lapses++。
      newLapses = oldLapses;
      if (ratingIdx >= 3) {
        // 毕业：stability 取初始值与旧值的较大者 ×1.5。
        newS = (_initialStability[ratingIdx - 1]).clamp(
            oldS * 1.5, double.maxFinite);
        if (newS < oldS * 1.5) newS = oldS * 1.5;
        newState = FsrsState.review;
        interval = _reviewInterval(newS, ratingIdx);
      } else {
        // 留在学习阶段：stability 衰减。
        newS = (oldS * 0.5).clamp(0.4, double.maxFinite);
        newState = oldState == FsrsState.relearning
            ? FsrsState.relearning
            : FsrsState.learning;
        interval = _shortInterval(ratingIdx);
      }
    } else {
      // Review 态：按 FSRS-4.5 公式演进。
      newD = _clampDifficulty(oldD + 0.1 * (ratingIdx - 3));
      newReps = oldReps + 1;
      if (ratingIdx == 1) {
        // Again：进入重学，lapses++，stability 大幅衰减。
        newState = FsrsState.relearning;
        newLapses = oldLapses + 1;
        newS = (oldS * 0.4).clamp(0.4, double.maxFinite);
        interval = _shortInterval(ratingIdx);
      } else {
        // Hard/Good/Easy：stability 按 elapsed_days 与难度权重增长。
        newState = FsrsState.review;
        newLapses = oldLapses;
        final elapsed = oldLastReview == null
            ? 0.0
            : now.difference(oldLastReview).inDays.toDouble().clamp(0.0, 365.0);
        final df = (10 - newD) / 10; // 难度因子 0.0-0.9
        double growth;
        double ratio;
        if (ratingIdx == 2) {
          // Hard
          growth = 0.2 + 0.3 * df;
          ratio = 0.6;
        } else if (ratingIdx == 3) {
          // Good
          growth = 0.4 + 0.4 * df;
          ratio = 1.0;
        } else {
          // Easy（ratingIdx == 4，当前未启用，预留）
          growth = 0.6 + 0.5 * df;
          ratio = 1.3;
        }
        // elapsed_days 影响：复习间隔越长，新 stability 增长越多（前提是答对了）。
        final elapsedBonus = oldS > 0 ? (elapsed / oldS).clamp(0.0, 2.0) : 0.0;
        newS = (oldS * (1 + growth * (1 + elapsedBonus)))
            .clamp(0.4, 36500.0);
        interval = _reviewInterval(newS, ratingIdx, ratio: ratio);
      }
    }

    // 映射回 MasteryLevel（UI 用）。
    // forceMastered=true 时强制 mastered（用于 markMastered：用户主动标记
    // 已掌握，FSRS stability 可能还低，但 UI 应立即显示 mastered）。
    final mastery = forceMastered
        ? MasteryLevel.mastered
        : _masteryFromFsrs(newState, newS, rating);

    // 写回 FSRS 状态到 tags。
    final newTags = LearningContextCodec.writeFsrs(
      tags: tags,
      stability: newS,
      difficulty: newD,
      state: newState,
      reps: newReps,
      lapses: newLapses,
      lastReview: now,
    );

    return question.copyWith(
      masteryLevel: mastery,
      reviewCount: question.reviewCount + 1,
      lastReviewedAt: now,
      nextReviewAt: now.add(interval),
      tags: newTags,
    );
  }

  QuestionRecord reset(QuestionRecord question, {DateTime? now}) {
    final at = now ?? DateTime.now();
    // 清除 FSRS 状态但保留 reviewCount（与原行为一致）。
    final clearedTags = LearningContextCodec.clearFsrs(question.tags);
    return question.copyWith(
      masteryLevel: MasteryLevel.newQuestion,
      nextReviewAt: at,
      tags: clearedTags,
    );
  }

  bool isDue(QuestionRecord question, {DateTime? now}) {
    if (question.contentStatus != ContentStatus.ready) return false;
    // Legacy "mastered" records never carried a schedule and historically
    // meant permanently complete. FSRS 下 mastered 题也有 nextReviewAt，
    // 但旧数据 nextReviewAt==null 的 mastered 题保留退出队列的例外。
    if (question.masteryLevel == MasteryLevel.mastered &&
        question.nextReviewAt == null) {
      return false;
    }
    final dueAt = question.nextReviewAt ?? question.createdAt;
    return !dueAt.isAfter(now ?? DateTime.now());
  }

  // --- FSRS-4.5 辅助方法 ---

  int _ratingIndex(ReviewRating rating) {
    switch (rating) {
      case ReviewRating.forgot:
        return 1; // Again
      case ReviewRating.hard:
        return 2; // Hard
      case ReviewRating.easy:
        return 3; // Good
    }
  }

  double _initialDifficulty(int ratingIdx) =>
      (0.3 * ratingIdx + 4.5).clamp(_difficultyMin, _difficultyMax);

  double _clampDifficulty(double d) =>
      d.clamp(_difficultyMin, _difficultyMax);

  /// Learning/Relearning 阶段的短间隔。
  /// Again = 10 分钟，Hard = 1 天。
  Duration _shortInterval(int ratingIdx) {
    if (ratingIdx == 1) {
      return const Duration(minutes: 10);
    }
    return const Duration(days: 1);
  }

  /// Review 阶段的间隔 = stability × ratio，clamp 到 1-36500 天。
  Duration _reviewInterval(double stability, int ratingIdx,
      {double ratio = 1.0}) {
    final days = (stability * ratio).round().clamp(1, 36500);
    return Duration(days: days);
  }

  /// FSRS 状态映射回 MasteryLevel（UI 展示用）。
  ///
  /// - newCard → newQuestion
  /// - learning/relearning → reviewing
  /// - review 且 stability > 21 天 → mastered（约 3 周+ 记忆稳定）
  /// - review 且 stability ≤ 21 天 → reviewing
  MasteryLevel _masteryFromFsrs(
      FsrsState state, double stability, ReviewRating rating) {
    if (state == FsrsState.newCard) return MasteryLevel.newQuestion;
    if (state == FsrsState.review && stability > 21) {
      return MasteryLevel.mastered;
    }
    return MasteryLevel.reviewing;
  }
}
