import 'dart:async';

import 'package:smart_wrong_notebook/src/domain/models/goal_checkin.dart';
import 'package:smart_wrong_notebook/src/domain/repositories/goal_checkin_repository.dart';

/// 内存版 [GoalCheckinRepository]，主要供单元测试与开发期使用。
///
/// 内部按 `id` 存入 `Map<String, GoalCheckin>`；`watchAll` 通过
/// `StreamController<List<GoalCheckin>>.broadcast()` 在每次 mutation 后
/// 推送一份按 `date` 升序排序后的快照。
class InMemoryGoalCheckinRepository implements GoalCheckinRepository {
  final Map<String, GoalCheckin> _items = <String, GoalCheckin>{};
  final StreamController<List<GoalCheckin>> _controller =
      StreamController<List<GoalCheckin>>.broadcast();

  @override
  Future<List<GoalCheckin>> listAll() async {
    return List<GoalCheckin>.unmodifiable(_items.values.toList());
  }

  @override
  Future<GoalCheckin?> getByDate(DateTime date) async {
    final normalized = _normalizeDay(date);
    for (final item in _items.values) {
      if (_normalizeDay(item.date) == normalized) return item;
    }
    return null;
  }

  @override
  Future<void> upsert(GoalCheckin checkin) async {
    // 按 date 唯一：若已有同日记录则替换其 id 对应条目。
    final normalized = _normalizeDay(checkin.date);
    String? existingId;
    for (final entry in _items.entries) {
      if (_normalizeDay(entry.value.date) == normalized) {
        existingId = entry.key;
        break;
      }
    }
    if (existingId != null && existingId != checkin.id) {
      _items.remove(existingId);
    }
    _items[checkin.id] = checkin;
    _emit();
  }

  @override
  Future<void> deleteById(String id) async {
    _items.remove(id);
    _emit();
  }

  @override
  Future<void> clear() async {
    _items.clear();
    _emit();
  }

  @override
  Stream<List<GoalCheckin>> watchAll() {
    // 立即推送一份当前快照，再继续监听后续变化。
    final controller = _controller;
    Future<void>.microtask(() => controller.add(_sortedSnapshot()));
    return controller.stream;
  }

  void _emit() {
    if (!_controller.isClosed) {
      _controller.add(_sortedSnapshot());
    }
  }

  List<GoalCheckin> _sortedSnapshot() {
    final list = _items.values.toList()
      ..sort((a, b) => a.date.compareTo(b.date));
    return List<GoalCheckin>.unmodifiable(list);
  }

  DateTime _normalizeDay(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  /// 释放内部 StreamController（测试结束时可调用）。
  void dispose() {
    _controller.close();
  }
}
