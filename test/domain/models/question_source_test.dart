import 'package:flutter_test/flutter_test.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_source.dart';

void main() {
  test('writes, replaces, and clears durable question source markers', () {
    var tags = QuestionSourceCodec.write(<String>['ordinary'], '期中考试');
    expect(QuestionSourceCodec.read(tags), '期中考试');
    expect(tags, contains('__system_source:期中考试'));

    tags = QuestionSourceCodec.write(tags, '课堂作业');
    expect(QuestionSourceCodec.read(tags), '课堂作业');
    expect(tags.where((tag) => tag.startsWith('__system_source:')), hasLength(1));

    tags = QuestionSourceCodec.write(tags, '');
    expect(QuestionSourceCodec.read(tags), isNull);
    expect(tags, contains('ordinary'));
  });

  test('normalizes comma in source for current Drift tag storage', () {
    final tags = QuestionSourceCodec.write(<String>[], '月考,数学');
    expect(QuestionSourceCodec.read(tags), '月考，数学');
  });
}
