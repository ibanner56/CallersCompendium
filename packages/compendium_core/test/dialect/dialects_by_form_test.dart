import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

void main() {
  test('each form reads in its own dialect', () {
    final byForm = DialectsByForm({
      DanceForm.contra: Dialect.leadsFollows,
      DanceForm.ecd: Dialect.canonical,
    });
    expect(byForm.forForm(DanceForm.contra), Dialect.leadsFollows);
    expect(byForm.forForm(DanceForm.ecd), Dialect.canonical);
    expect(
      byForm.forDance(
        Dance(
          id: 'd',
          title: 'T',
          form: DanceForm.ecd,
          createdAt: DateTime.utc(2026),
          updatedAt: DateTime.utc(2026),
        ),
      ),
      Dialect.canonical,
    );
  });

  test('a form with no dialect given reads in the app default', () {
    expect(DialectsByForm().forForm(DanceForm.square), Dialect.larksRobins);
    expect(DialectsByForm.defaults.forForm(DanceForm.ecd), Dialect.larksRobins);
  });

  test('all gives every form one dialect, and withForm changes one', () {
    final all = DialectsByForm.all(Dialect.leadsFollows);
    for (final form in DanceForm.values) {
      expect(all.forForm(form), Dialect.leadsFollows, reason: form.name);
    }
    final changed = all.withForm(DanceForm.ecd, Dialect.canonical);
    expect(changed.forForm(DanceForm.ecd), Dialect.canonical);
    expect(changed.forForm(DanceForm.contra), Dialect.leadsFollows);
    expect(all.forForm(DanceForm.ecd), Dialect.leadsFollows);
  });

  test('equality compares the dialect of every form', () {
    expect(
      DialectsByForm({DanceForm.contra: Dialect.larksRobins}),
      DialectsByForm.defaults,
    );
    expect(
      DialectsByForm({DanceForm.ecd: Dialect.leadsFollows}),
      isNot(DialectsByForm.defaults),
    );
    expect(
      DialectsByForm({DanceForm.ecd: Dialect.leadsFollows}).hashCode,
      DialectsByForm.all(
        Dialect.larksRobins,
      ).withForm(DanceForm.ecd, Dialect.leadsFollows).hashCode,
    );
  });
}
