import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/editor/free_text_composer_controller.dart';

void main() {
  // updatePendingLine reads the scheduler phase.
  TestWidgetsFlutterBinding.ensureInitialized();

  test('an editor being replaced does not disconnect its replacement', () {
    final controller = FreeTextComposerController();
    addTearDown(controller.dispose);
    var oldSubmits = 0;
    var newSubmits = 0;
    bool oldSubmit() {
      oldSubmits++;
      return true;
    }

    bool newSubmit() {
      newSubmits++;
      return true;
    }

    // Flutter builds the replacement editor before it disposes the old one.
    controller.attach(oldSubmit);
    controller.attach(newSubmit);
    controller.detach(oldSubmit);
    controller.updatePendingLine(true);

    controller.submitPendingLine();
    expect(newSubmits, 1);
    expect(oldSubmits, 0);
  });

  test('the attached editor detaching clears the pending line', () {
    final controller = FreeTextComposerController();
    addTearDown(controller.dispose);
    bool submit() => false;

    controller.attach(submit);
    controller.updatePendingLine(true);
    expect(controller.hasPendingLine, isTrue);

    controller.detach(submit);
    expect(controller.hasPendingLine, isFalse);
    expect(controller.submitPendingLine(), isTrue);
  });
}
