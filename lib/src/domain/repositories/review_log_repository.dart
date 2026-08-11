import 'package:smart_wrong_notebook/src/domain/models/review_log.dart';

abstract class ReviewLogRepository {
  Future<void> insert(ReviewLog log);
  Future<List<ReviewLog>> getByQuestionId(String questionId);
  Future<List<ReviewLog>> listAll();
  Future<void> clear();
  Future<void> deleteByIds(Set<String> ids);

  /// 响应式订阅全量复习记录，默认回退到一次性 Future 拉取。
  Stream<List<ReviewLog>> watchAll() async* {
    yield await listAll();
  }
}

class InMemoryReviewLogRepository implements ReviewLogRepository {
  final List<ReviewLog> _items = [];

  @override
  Future<void> insert(ReviewLog log) async => _items.add(log);

  @override
  Future<List<ReviewLog>> getByQuestionId(String questionId) async =>
      _items.where((l) => l.questionRecordId == questionId).toList();

  @override
  Future<List<ReviewLog>> listAll() async => List.unmodifiable(_items);

  @override
  Future<void> clear() async => _items.clear();

  @override
  Future<void> deleteByIds(Set<String> ids) async =>
      _items.removeWhere((item) => ids.contains(item.id));

  @override
  Stream<List<ReviewLog>> watchAll() async* {
    yield await listAll();
  }
}
