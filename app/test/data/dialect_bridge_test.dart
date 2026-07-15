import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/data/active_dialect_scope.dart';
import 'package:compendium_app/src/data/dialect_library_controller.dart';
import 'package:compendium_app/src/data/dialect_library_scope.dart';

import '../support/test_repositories.dart';

/// A consumer that reads the active dialect through [ActiveDialectScope] — the
/// same path every screen in the app uses. It must reflect whatever the
/// [DialectLibraryController] resolves as active, live.
class _DialectConsumer extends StatelessWidget {
  const _DialectConsumer();

  @override
  Widget build(BuildContext context) {
    return Text(
      ActiveDialectScope.of(context).name,
      textDirection: TextDirection.ltr,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'controller active dialect flows through ActiveDialectScope to consumers',
    (tester) async {
      final repos = openTestRepositories();
      await repos.ensureMigrated();

      final controller = DialectLibraryController(repos.settings);
      await controller.load();

      // Wire the bridge exactly like main.dart: the controller drives the
      // notifier that ActiveDialectScope consumers read.
      final notifier = ValueNotifier<Dialect>(controller.active);
      void sync() => notifier.value = controller.active;
      controller.addListener(sync);
      addTearDown(() {
        controller.removeListener(sync);
        controller.dispose();
        notifier.dispose();
      });

      await tester.pumpWidget(
        DialectLibraryScope(
          controller: controller,
          child: ActiveDialectScope(
            notifier: notifier,
            child: const _DialectConsumer(),
          ),
        ),
      );

      // Defaults to the app default before anything is chosen.
      expect(find.text(Dialect.larksRobins.name), findsOneWidget);

      // Activating another preset propagates to the consumer.
      await controller.setActive(Dialect.leadsFollows.name);
      await tester.pump();
      expect(find.text(Dialect.leadsFollows.name), findsOneWidget);

      // Activating a custom dialect propagates too.
      await controller.upsert(Dialect(name: 'Mine'));
      await controller.setActive('Mine');
      await tester.pump();
      expect(find.text('Mine'), findsOneWidget);

      // Deleting the active custom falls back to the default.
      await controller.delete('Mine');
      await tester.pump();
      expect(find.text(Dialect.larksRobins.name), findsOneWidget);
    },
  );
}
