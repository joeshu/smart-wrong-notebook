import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_wrong_notebook/src/app/providers.dart';
import 'package:smart_wrong_notebook/src/data/repositories/question_repository.dart';
import 'package:smart_wrong_notebook/src/domain/models/question_record.dart';
import 'package:smart_wrong_notebook/src/domain/models/subject.dart';

void main() {
  test('endSession clears current question provider', () {
    final container = ProviderContainer(overrides: [
      questionRepositoryProvider.overrideWithValue(InMemoryQuestionRepository()),
    ]);
    addTearDown(container.dispose);

    final record = QuestionRecord.draft(
      id: 'probe',
      imagePath: '/tmp/probe.jpg',
      subject: Subject.math,
      recognizedText: 'probe',
    );
    final session = container.read(captureSessionProvider.notifier);
    session.selectImage(record.imagePath);
    session.setCurrentQuestion(record);
    print('PROBE1 current=${container.read(currentQuestionProvider)?.id} '
        'phase=${container.read(captureSessionProvider).phase}');

    session.endSession();
    print('PROBE2 current=${container.read(currentQuestionProvider)} '
        'phase=${container.read(captureSessionProvider).phase} '
        'isTerminal=${container.read(captureSessionProvider).isTerminal}');

    expect(container.read(currentQuestionProvider), isNull);
  });
}
