import 'package:compendium_app/src/editor/draft_save_health.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(() {
    DraftSaveHealth.resetSessionForTest();
  });

  test('claims the first log once per session, across editors', () {
    final dance = DraftSaveHealth();
    final program = DraftSaveHealth();
    expect(dance.claimFirstLog(), isTrue);
    expect(dance.claimFirstLog(), isFalse);
    expect(program.claimFirstLog(), isFalse);
  });

  test('failed follows the latest write and reports changes', () {
    final health = DraftSaveHealth();
    expect(health.recordSuccess(), isFalse);
    expect(health.recordFailure(), isTrue);
    expect(health.recordFailure(), isFalse);
    expect(health.failed, isTrue);
    expect(health.recordSuccess(), isTrue);
    expect(health.failed, isFalse);
  });
}
