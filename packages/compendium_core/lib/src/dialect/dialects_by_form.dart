import 'package:collection/collection.dart';
import 'package:meta/meta.dart';

import '../model/dance.dart';
import '../model/enums.dart';
import 'dialect.dart';

/// The dialect each dance form is shown in.
///
/// Each dance form has its own dialect, with everything a contra dialect has
/// (ADR-006 §9.1, point 1): a dance is shown in its own form's dialect, so a
/// program that mixes forms shows each dance in its form's words (ADR-006
/// §12.2, S3). A form with no dialect of its own given reads in
/// [Dialect.larksRobins], the app default.
@immutable
final class DialectsByForm {
  DialectsByForm([Map<DanceForm, Dialect> byForm = const {}])
    : _byForm = Map.unmodifiable(byForm);

  /// The same [dialect] for every form.
  DialectsByForm.all(Dialect dialect)
    : _byForm = Map.unmodifiable({
        for (final form in DanceForm.values) form: dialect,
      });

  /// Every form in the app default, [Dialect.larksRobins].
  static final DialectsByForm defaults = DialectsByForm();

  final Map<DanceForm, Dialect> _byForm;

  /// The dialect a dance of [form] is shown in.
  Dialect forForm(DanceForm form) => _byForm[form] ?? Dialect.larksRobins;

  /// The dialect [dance] is shown in: its own form's.
  Dialect forDance(Dance dance) => forForm(dance.form);

  /// A copy with [form] shown in [dialect].
  DialectsByForm withForm(DanceForm form, Dialect dialect) =>
      DialectsByForm({..._byForm, form: dialect});

  @override
  bool operator ==(Object other) =>
      other is DialectsByForm &&
      DanceForm.values.every((f) => other.forForm(f) == forForm(f));

  @override
  int get hashCode => const ListEquality<Dialect>().hash([
    for (final form in DanceForm.values) forForm(form),
  ]);
}
