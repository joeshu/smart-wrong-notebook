enum MistakeCategory {
  concept,
  comprehension,
  calculation,
  strategy,
  format,
  careless,
}

extension MistakeCategoryLabel on MistakeCategory {
  String get label => switch (this) {
        MistakeCategory.concept => '概念不清',
        MistakeCategory.comprehension => '审题偏差',
        MistakeCategory.calculation => '计算失误',
        MistakeCategory.strategy => '方法选择',
        MistakeCategory.format => '单位/格式',
        MistakeCategory.careless => '粗心遗漏',
      };
}

/// Stores structured mistake categories in the existing durable [tags] field.
/// The system marker is hidden from normal user tags and avoids a database
/// schema migration for this MVP; it can be migrated to a dedicated column.
class MistakeCategoryCodec {
  const MistakeCategoryCodec._();

  static const _prefix = '__system_mistake_category:';

  static MistakeCategory? read(Iterable<String> tags) {
    for (final marker in tags) {
      if (!marker.startsWith(_prefix)) continue;
      final value = marker.substring(_prefix.length);
      for (final category in MistakeCategory.values) {
        if (category.name == value) return category;
      }
    }
    return null;
  }

  static List<String> write(
    Iterable<String> tags,
    MistakeCategory? category,
  ) {
    final result = tags.where((tag) => !tag.startsWith(_prefix)).toList();
    if (category != null) result.add('$_prefix${category.name}');
    return result;
  }
}
