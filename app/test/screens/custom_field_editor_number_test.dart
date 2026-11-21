import 'package:compendium_app/l10n/app_localizations.dart';
import 'package:compendium_app/src/screens/dance_editor/custom_field_editor.dart';
import 'package:compendium_app/src/widgets/lingo_text_editing_controller.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets(
    'a non-number in a number field is rejected in the app language',
    (tester) async {
      final formKey = GlobalKey<FormState>();
      final controller = LingoTextEditingController(
        text: 'abc',
        dialect: Dialect.leadsFollows,
      );
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ja'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: Form(
              key: formKey,
              child: CustomFieldEditor(
                def: CustomFieldDef(
                  id: 'f-num',
                  key: 'tempo',
                  label: 'Tempo',
                  type: CustomFieldType.number,
                ),
                dialect: Dialect.leadsFollows,
                textController: controller,
                currentValue: null,
                onTextChanged: () {},
                onValueChanged: (_) {},
              ),
            ),
          ),
        ),
      );

      expect(formKey.currentState!.validate(), isFalse);
      await tester.pump();

      final ja = await AppLocalizations.delegate.load(const Locale('ja'));
      expect(
        find.text(ja.collectionBatchCustomFieldNumberInvalid),
        findsOneWidget,
      );
      expect(find.text('Enter a number'), findsNothing);
    },
  );
}
