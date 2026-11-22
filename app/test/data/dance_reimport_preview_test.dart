import 'package:compendium_app/src/data/dance_reimport.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'the re-import preview leaves out the credit years a re-import keeps',
    () {
      final now = DateTime.utc(2026, 1, 1);
      final incoming = Dance(
        id: 'd1',
        title: 'Incoming',
        form: DanceForm.ecd,
        composedOn: PartialDate(1651),
        interpretedOn: PartialDate(1916),
        createdAt: now,
        updatedAt: now,
      );

      final preview = reimportPreviewData(incoming).dance;

      expect(preview.composedOn, isNull);
      expect(preview.interpretedOn, isNull);
      // Fields a re-import may take are still previewed.
      expect(preview.title, 'Incoming');
      expect(preview.form, DanceForm.ecd);
    },
  );
}
