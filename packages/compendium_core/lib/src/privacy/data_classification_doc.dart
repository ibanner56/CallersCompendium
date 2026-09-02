/// Renders the data-classification catalogue as markdown.
///
/// Kept in `lib/` — but deliberately **not** exported from
/// `compendium_core.dart` — so that the generator tool
/// (`tool/generate_data_classification_doc.dart`) and the test that checks the
/// committed doc is current (`test/privacy/data_classification_doc_test.dart`)
/// render through exactly the same code. A generator and a checker that render
/// separately can agree with each other and both be wrong.
library;

import 'data_classification.dart';
import 'field_registry.dart';
import 'settings_registry.dart';

/// Opening marker of the generated block in `docs/dev/data-classification.md`.
const String docBeginMarker = '<!-- BEGIN GENERATED: field-catalogue -->';

/// Closing marker of the generated block.
const String docEndMarker = '<!-- END GENERATED: field-catalogue -->';

/// The human-readable name of an egress class, without markdown emphasis.
/// Shared by the summary line and [_egressLabel] so the two cannot drift.
String _egressName(EgressClass egress) => switch (egress) {
  EgressClass.shareable => 'shareable',
  EgressClass.deviceLocal => 'device-local',
  EgressClass.deviceScoped => 'device-scoped',
  EgressClass.derived => 'derived',
  EgressClass.protocolIdentifier => 'protocol-identifier',
  EgressClass.accessControlData => 'access-control-data',
};

/// The table-cell rendering: [_egressName], emphasised for the classes that
/// must not reach project infrastructure so they stand out when skimming.
String _egressLabel(EgressClass egress) => switch (egress) {
  EgressClass.deviceLocal ||
  EgressClass.protocolIdentifier ||
  EgressClass.accessControlData => '**${_egressName(egress)}**',
  _ => _egressName(egress),
};

String _subjectLabel(DataSubject subject) => switch (subject) {
  DataSubject.none => '—',
  DataSubject.appUser => 'app user',
  DataSubject.thirdParty => 'third party',
};

/// Escapes the markdown table cell separator so a note containing `|` cannot
/// silently break the table's column alignment.
String _cell(String value) => value.replaceAll('|', r'\|');

/// Renders the catalogue tables and summary, without the surrounding markers.
String renderFieldCatalogue() {
  final buffer = StringBuffer()
    ..writeln('_Generated from `lib/src/privacy/field_registry.dart` and')
    ..writeln(
      '`lib/src/privacy/settings_registry.dart`. Do not edit this block',
    )
    ..writeln('by hand — run:_')
    ..writeln()
    ..writeln('```sh')
    ..writeln(
      'fvm dart run '
      'packages/compendium_core/tool/generate_data_classification_doc.dart',
    )
    ..writeln('```')
    ..writeln()
    ..writeln('### Database columns')
    ..writeln()
    ..write(_renderTable(fieldClassifications, 'Table', 'Column'))
    ..writeln()
    ..writeln('### Settings keys')
    ..writeln()
    ..writeln(
      'Declared in `app/lib`; classified here so the catalogue has one source '
      'of truth. `settings.value_json` is `deviceLocal` at the column level so '
      'a blanket sync cannot happen by accident — these entries decide what '
      'actually travels.',
    )
    ..writeln()
    ..write(_renderSettingsTable(settingsClassifications))
    ..writeln()
    ..writeln('### Settings key prefixes')
    ..writeln()
    ..writeln(
      'Some settings-table keys are built at runtime from a per-entity '
      'suffix rather than declared as an exact key (`editor_draft:<id>`), so '
      'they cannot appear in the table above. Each prefix below classifies '
      'every key it matches; `classifySettingsKey` resolves the longest '
      'matching prefix.',
    )
    ..writeln()
    ..write(
      _renderSettingsTable(
        settingsPrefixClassifications,
        keyHeader: 'Key prefix',
      ),
    );

  return buffer.toString().trimRight();
}

String _summary(Map<String, DataClassification> entries, String noun) {
  final byEgress = <EgressClass, int>{};
  for (final entry in entries.values) {
    byEgress[entry.egress] = (byEgress[entry.egress] ?? 0) + 1;
  }
  final personal = entries.values.where((c) => c.term.isPersonalData).length;
  final parts = <String>[
    for (final egress in EgressClass.values)
      if ((byEgress[egress] ?? 0) > 0)
        '${byEgress[egress]} ${_egressName(egress)}',
  ];
  return '**${entries.length} $noun**: ${parts.join(', ')}. '
      '$personal personal data by category.';
}

String _renderTable(
  Map<String, DataClassification> entries,
  String firstHeader,
  String secondHeader,
) {
  final keys = entries.keys.toList()..sort();
  final buffer = StringBuffer()
    ..writeln(_summary(entries, 'columns'))
    ..writeln()
    ..writeln(
      '| $firstHeader | $secondHeader | Category | Path | Subject | Egress '
      '| Why |',
    )
    ..writeln('| --- | --- | --- | --- | --- | --- | --- |');

  for (final key in keys) {
    final classification = entries[key]!;
    final parts = key.split('.');
    buffer.writeln(
      '| `${parts.first}` '
      '| `${parts.sublist(1).join('.')}` '
      '| `${classification.term.uri}` '
      '| ${classification.term.displayPath} '
      '| ${_subjectLabel(classification.subject)} '
      '| ${_egressLabel(classification.egress)} '
      '| ${_cell(classification.note ?? '')} |',
    );
  }
  return buffer.toString();
}

String _renderSettingsTable(
  Map<String, DataClassification> entries, {
  String keyHeader = 'Key',
}) {
  final keys = entries.keys.toList()..sort();
  final buffer = StringBuffer()
    ..writeln(
      _summary(
        entries,
        keyHeader == 'Key' ? 'settings keys' : 'settings key prefixes',
      ),
    )
    ..writeln()
    ..writeln('| $keyHeader | Category | Subject | Egress | Why |')
    ..writeln('| --- | --- | --- | --- | --- |');

  for (final key in keys) {
    final classification = entries[key]!;
    buffer.writeln(
      '| `$key` '
      '| `${classification.term.uri}` '
      '| ${_subjectLabel(classification.subject)} '
      '| ${_egressLabel(classification.egress)} '
      '| ${_cell(classification.note ?? '')} |',
    );
  }
  return buffer.toString();
}

/// Replaces the generated block inside [document] with a freshly rendered
/// catalogue, leaving the hand-written prose around it untouched.
///
/// Throws [FormatException] when the markers are missing or out of order, so a
/// mangled document fails loudly rather than being silently rewritten.
String withRegeneratedCatalogue(String document) {
  final begin = document.indexOf(docBeginMarker);
  final end = document.indexOf(docEndMarker);

  if (begin < 0 || end < 0 || end < begin) {
    throw FormatException(
      'Expected "$docBeginMarker" followed by "$docEndMarker" in the document.',
    );
  }

  final head = document.substring(0, begin + docBeginMarker.length);
  final tail = document.substring(end);
  return '$head\n\n${renderFieldCatalogue()}\n\n$tail';
}
