import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_wrong_notebook/src/domain/models/goal_checkin.dart';
import 'package:smart_wrong_notebook/src/domain/repositories/goal_checkin_repository.dart';

/// 基于 `SharedPreferences` 的 [GoalCheckinRepository] 实现。
///
/// 打卡列表以 JSON 数组形式存储在 key `goal_checkins_v1` 下；`upsert`
/// 按 `date`（当天 00:00）去重并替换同日记录。`watchAll` 用一个内部
/// `StreamController` 在每次 mutation 后推送当前列表（SharedPrefs 无原生
/// watch 能力）。
class SharedPrefsGoalCheckinRepository implements GoalCheckinRepository {
  static const String _key = 'goal_checkins_v1';

  SharedPreferences? _prefs;
  final StreamController<List<GoalCheckin>> _controller =
      StreamController<List<GoalCheckin>>.broadcast();

  Future<SharedPreferences> get _preferences async {
    _prefs ??= await SharedPreferences.getInstance();
    return _prefs!;
  }

  Future<List<GoalCheckin>> _loadAll() async {
    final prefs = await _preferences;
    final raw = prefs.getString(_key);
    if (raw == null || raw.isEmpty) return <GoalCheckin>[];
    try {
      final list = jsonDecode(raw) as List;
      return list
          .map((e) => GoalCheckin.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return <GoalCheckin>[];
    }
  }

  Future<void> _saveAll(List<GoalCheckin> checkins) async {
    final prefs = await _preferences;
    final raw = jsonEncode(
        checkins.map((c) => c.toJson()).toList());
    await prefs.setString(_key, raw);
  }

  @override
  Future<List<GoalCheckin>> listAll() => _loadAll();

  @override
  Future<GoalCheckin?> getByDate(DateTime date) async {
    final normalized = _normalizeDay(date);
    final all = await _loadAll();
    for (final item in all) {
      if (_normalizeDay(item.date) == normalized) return item;
    }
    return null;
  }

  @override
  Future<void> upsert(GoalCheckin checkin) async {
    final all = await _loadAll();
    final normalized = _normalizeDay(checkin.date);
    // 按 date 去重：移除同日其它记录（无论 id 是否相同）。
    final filtered =
        all.where((c) => _normalizeDay(c.date) != normalized).toList();
    filtered.add(checkin);
    await _saveAll(filtered);
    _emit(filtered);
  }

  @override
  Future<void> deleteById(String id) async {
    final all = await _loadAll();
    final filtered = all.where((c) => c.id != id).toList();
    await _saveAll(filtered);
    _emit(filtered);
  }

  @override
  Future<void> clear() async {
    final prefs = await _preferences;
    await prefs.remove(_key);
    _emit(<GoalCheckin>[]);
  }

  @override
  Stream<List<GoalCheckin>> watchAll() {
    final controller = _controller;
    // 立即推送一份当前快照，再继续监听后续变化。
    Future<void>.microtask(() async {
      final snapshot = await _loadAll();
      if (!controller.isClosed) {
        controller.add(_sorted(snapshot));
      }
    });
    return controller.stream;
  }

  void _emit(List<GoalCheckin> checkins) {
    if (!_controller.isClosed) {
      _controller.add(_sorted(checkins));
    }
  }

  List<GoalCheckin> _sorted(List<GoalCheckin> checkins) {
    final list = List<GoalCheckin>.of(checkins)
      ..sort((a, b) => a.date.compareTo(b.date));
    return List<GoalCheckin>.unmodifiable(list);
  }

  DateTime _normalizeDay(DateTime date) {
    return DateTime(date.year, date.month, date.day);
  }

  /// 释放内部 StreamController。
  void dispose() {
    _controller.close();
  }
}
