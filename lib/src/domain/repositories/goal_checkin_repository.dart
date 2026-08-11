import 'package:smart_wrong_notebook/src/domain/models/goal_checkin.dart';

/// 学习目标打卡记录仓库接口。
///
/// 按 `date`（当天 00:00）唯一保存 [GoalCheckin]；具体实现可选择内存、
/// SharedPrefs 或 Drift 等。
abstract class GoalCheckinRepository {
  /// 返回全部打卡记录（未指定顺序，调用方自行排序）。
  Future<List<GoalCheckin>> listAll();

  /// 按日期查询打卡记录。`date` 应为当天 00:00（本地时间）。
  Future<GoalCheckin?> getByDate(DateTime date);

  /// 插入或更新一条打卡记录（按 `date` 唯一去重）。
  Future<void> upsert(GoalCheckin checkin);

  /// 按 ID 删除一条打卡记录。
  Future<void> deleteById(String id);

  /// 清空全部打卡记录。
  Future<void> clear();

  /// 响应式订阅全部打卡记录，每次 mutation 后推送新快照。
  Stream<List<GoalCheckin>> watchAll();
}
