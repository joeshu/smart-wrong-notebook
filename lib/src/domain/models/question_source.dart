/// Persists a user-defined question source without a schema migration.
/// Values live in the existing durable tags column and are hidden from normal
/// tag presentation. Commas are normalized because the current Drift adapter
/// serializes tags as a comma-separated string.
class QuestionSourceCodec {
  const QuestionSourceCodec._();

  static const _prefix = '__system_source:';

  static String? read(Iterable<String> tags) {
    for (final tag in tags) {
      if (tag.startsWith(_prefix)) {
        final value = tag.substring(_prefix.length).trim();
        return value.isEmpty ? null : value;
      }
    }
    return null;
  }

  static List<String> write(Iterable<String> tags, String? source) {
    final result = tags.where((tag) => !tag.startsWith(_prefix)).toList();
    final normalized =
        source == null ? null : source.trim().replaceAll(',', '，');
    if (normalized != null && normalized.isNotEmpty) {
      result.add('$_prefix$normalized');
    }
    return result;
  }
}
