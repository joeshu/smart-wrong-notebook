import 'package:flutter_test/flutter_test.dart';
import 'package:smart_wrong_notebook/src/domain/models/content_status.dart';
import 'package:smart_wrong_notebook/src/domain/models/mastery_level.dart';
import 'package:smart_wrong_notebook/src/domain/models/mistake_category.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';
import 'package:smart_wrong_notebook/src/shared/utils/mistake_trend_aggregator.dart';

/// 构造测试题目。`mistakeCategory` 为 null 时不写入 `__system_mistake_category:` tag，
/// 用于验证「无错因分类的题目不计入」。
QuestionRecord _question(
  String id, {
  required DateTime createdAt,
  MistakeCategory? mistakeCategory,
}) {
  return QuestionRecord(
    id: id,
    imagePath: '',
    subject: Subject.math,
    extractedQuestionText: '题目 $id',
    normalizedQuestionText: '题目 $id',
    contentFormat: QuestionContentFormat.plain,
    tags: mistakeCategory == null
        ? const <String>[]
        : <String>['__system_mistake_category:${mistakeCategory.name}'],
    createdAt: createdAt,
    updatedAt: createdAt,
    lastReviewedAt: null,
    reviewCount: 0,
    isFavorite: false,
    contentStatus: ContentStatus.ready,
    masteryLevel: MasteryLevel.newQuestion,
    analysisResult: null,
  );
}

void main() {
  // 固定「现在」便于断言日期窗口。2026-07-20 10:30:00。
  final now = DateTime(2026, 7, 20, 10, 30, 0);
  // startDate = 2026-06-21 00:00（30 天前），endDate = 2026-07-20 23:59:59。
  final startDate = DateTime(2026, 6, 21);
  final today = DateTime(2026, 7, 20);

  group('aggregateMistakeTrendFromQuestions', () {
    test('空题库 → 空矩阵、所有 totals 为 0', () {
      final data = aggregateMistakeTrendFromQuestions(
        const <QuestionRecord>[],
        days: 30,
        now: now,
      );

      expect(data.dates, hasLength(30));
      expect(data.categories, isEmpty);
      expect(data.matrix, hasLength(30));
      for (final row in data.matrix) {
        expect(row, isEmpty);
      }
      expect(data.dailyTotals, hasLength(30));
      expect(data.dailyTotals.every((v) => v == 0), isTrue);
      expect(data.categoryTotals, isEmpty);
      expect(data.grandTotal, 0);
      expect(data.startDate, startDate);
      expect(data.endDate, DateTime(2026, 7, 20, 23, 59, 59));
    });

    test('单题（createdAt=今天，mistakeCategory=concept）→ '
        'matrix 最后一行 concept 列 = 1', () {
      final data = aggregateMistakeTrendFromQuestions(
        <QuestionRecord>[
          _question(
            'q-1',
            createdAt: today,
            mistakeCategory: MistakeCategory.concept,
          ),
        ],
        days: 30,
        now: now,
      );

      // concept 是 enum 中第一个，按 index 升序应该出现在 categories[0]。
      expect(data.categories, [MistakeCategory.concept]);
      // 最后一行（dayIndex = 29，即今天）的 concept 列 = 1。
      expect(data.matrix.last, [1]);
      // 其余 29 行全为 0。
      for (var i = 0; i < 29; i++) {
        expect(data.matrix[i], [0]);
      }
      expect(data.dailyTotals.last, 1);
      expect(data.dailyTotals.sublist(0, 29).every((v) => v == 0), isTrue);
      expect(data.categoryTotals, [1]);
      expect(data.grandTotal, 1);
    });

    test('跨多天的题目分布正确', () {
      // 第 0 天（2026-06-21）：2 道 concept
      // 第 10 天（2026-07-01）：1 道 calculation
      // 第 29 天（2026-07-20）：3 道 careless + 1 道 concept
      final data = aggregateMistakeTrendFromQuestions(
        <QuestionRecord>[
          _question('a-1',
              createdAt: startDate, mistakeCategory: MistakeCategory.concept),
          _question('a-2',
              createdAt: startDate, mistakeCategory: MistakeCategory.concept),
          _question('b-1',
              createdAt: startDate.add(const Duration(days: 10)),
              mistakeCategory: MistakeCategory.calculation),
          _question('c-1',
              createdAt: today, mistakeCategory: MistakeCategory.careless),
          _question('c-2',
              createdAt: today, mistakeCategory: MistakeCategory.careless),
          _question('c-3',
              createdAt: today, mistakeCategory: MistakeCategory.careless),
          _question('c-4',
              createdAt: today, mistakeCategory: MistakeCategory.concept),
        ],
        days: 30,
        now: now,
      );

      // 出现过的分类按 index 升序：
      // concept(0), calculation(2), careless(5)。
      expect(data.categories, [
        MistakeCategory.concept,
        MistakeCategory.calculation,
        MistakeCategory.careless,
      ]);

      // 第 0 天：concept=2，其余=0
      expect(data.matrix[0], [2, 0, 0]);
      // 第 10 天：calculation=1，其余=0
      expect(data.matrix[10], [0, 1, 0]);
      // 第 29 天：concept=1, calculation=0, careless=3
      expect(data.matrix[29], [1, 0, 3]);
      // 第 5 天（中间未出题）：全 0
      expect(data.matrix[5], [0, 0, 0]);

      expect(data.dailyTotals[0], 2);
      expect(data.dailyTotals[10], 1);
      expect(data.dailyTotals[29], 4);
      expect(data.dailyTotals[5], 0);

      // categoryTotals 按 categories 顺序：concept=3, calculation=1, careless=3
      expect(data.categoryTotals, [3, 1, 3]);
      expect(data.grandTotal, 7);
    });

    test('超出 30 天的题目不计入', () {
      // 31 天前（窗口外）
      final tooOld = startDate.subtract(const Duration(days: 1));
      // 边界：刚好 30 天前（startDate 当天，应该计入）
      final boundaryStart = startDate;
      // 边界：今天（应该计入）
      final boundaryEnd = today;
      // 明天（窗口外）
      final tomorrow = today.add(const Duration(days: 1));

      final data = aggregateMistakeTrendFromQuestions(
        <QuestionRecord>[
          _question('old-1',
              createdAt: tooOld, mistakeCategory: MistakeCategory.concept),
          _question('start-1',
              createdAt: boundaryStart,
              mistakeCategory: MistakeCategory.concept),
          _question('end-1',
              createdAt: boundaryEnd,
              mistakeCategory: MistakeCategory.concept),
          _question('future-1',
              createdAt: tomorrow,
              mistakeCategory: MistakeCategory.concept),
        ],
        days: 30,
        now: now,
      );

      // 仅 start-1 与 end-1 计入。
      expect(data.grandTotal, 2);
      expect(data.categories, [MistakeCategory.concept]);
      // 第 0 天 = startDate：1 题
      expect(data.matrix[0], [1]);
      // 第 29 天 = today：1 题
      expect(data.matrix[29], [1]);
      expect(data.dailyTotals[0], 1);
      expect(data.dailyTotals[29], 1);
      expect(data.categoryTotals, [2]);
    });

    test('mistakeCategory 为 null 的题目不计入', () {
      // 同一天：一道有 concept tag，一道没有 mistakeCategory tag。
      final data = aggregateMistakeTrendFromQuestions(
        <QuestionRecord>[
          _question('with-cat',
              createdAt: today, mistakeCategory: MistakeCategory.concept),
          _question('no-cat', createdAt: today), // mistakeCategory = null
        ],
        days: 30,
        now: now,
      );

      // 只有 with-cat 计入。
      expect(data.grandTotal, 1);
      expect(data.categories, [MistakeCategory.concept]);
      expect(data.matrix[29], [1]);
      expect(data.categoryTotals, [1]);
      expect(data.dailyTotals[29], 1);
    });

    test('带时分秒的 createdAt 仍归到当天（按日期部分匹配）', () {
      // 今天 14:30:00，应归到 today（dayIndex=29）。
      final withTime = DateTime(2026, 7, 20, 14, 30, 0);
      final data = aggregateMistakeTrendFromQuestions(
        <QuestionRecord>[
          _question('q-time',
              createdAt: withTime, mistakeCategory: MistakeCategory.concept),
        ],
        days: 30,
        now: now,
      );

      expect(data.matrix[29], [1]);
      expect(data.dailyTotals[29], 1);
      expect(data.grandTotal, 1);
    });

    test('categories 按 MistakeCategory.index 升序排列', () {
      // 故意按乱序传入：careless(5), concept(0), strategy(3), comprehension(1)。
      final data = aggregateMistakeTrendFromQuestions(
        <QuestionRecord>[
          _question('q-1',
              createdAt: today, mistakeCategory: MistakeCategory.careless),
          _question('q-2',
              createdAt: today, mistakeCategory: MistakeCategory.concept),
          _question('q-3',
              createdAt: today, mistakeCategory: MistakeCategory.strategy),
          _question('q-4',
              createdAt: today,
              mistakeCategory: MistakeCategory.comprehension),
        ],
        days: 30,
        now: now,
      );

      expect(data.categories, [
        MistakeCategory.concept, // index 0
        MistakeCategory.comprehension, // index 1
        MistakeCategory.strategy, // index 3
        MistakeCategory.careless, // index 5
      ]);
      // 每个分类各 1 题。
      expect(data.categoryTotals, [1, 1, 1, 1]);
      expect(data.grandTotal, 4);
    });

    test('dates 列表按时间升序，每元素为当天 00:00', () {
      final data = aggregateMistakeTrendFromQuestions(
        const <QuestionRecord>[],
        days: 30,
        now: now,
      );

      expect(data.dates.first, startDate);
      expect(data.dates.last, today);
      // 每个 DateTime 都应该是 00:00:00。
      for (final d in data.dates) {
        expect(d.hour, 0);
        expect(d.minute, 0);
        expect(d.second, 0);
      }
      // 升序检查。
      for (var i = 1; i < data.dates.length; i++) {
        expect(data.dates[i].isAfter(data.dates[i - 1]), isTrue);
      }
    });

    test('days 参数可配置（短窗口）', () {
      // 用 7 天窗口验证参数生效。
      final shortNow = DateTime(2026, 7, 20, 10, 0, 0);
      final data = aggregateMistakeTrendFromQuestions(
        <QuestionRecord>[
          _question('q-1',
              createdAt: shortNow, mistakeCategory: MistakeCategory.concept),
        ],
        days: 7,
        now: shortNow,
      );

      expect(data.dates, hasLength(7));
      expect(data.matrix, hasLength(7));
      expect(data.dailyTotals, hasLength(7));
      // startDate 应为 6 天前。
      expect(data.startDate, DateTime(2026, 7, 14));
      // 题目在第 6 天（最后一行）。
      expect(data.matrix.last, [1]);
      expect(data.grandTotal, 1);
    });
  });
}
