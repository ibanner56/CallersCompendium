import 'package:compendium_core/compendium_core.dart';

import '../../l10n/app_localizations.dart';

/// Where a dance came from, as its provenance line names it.
String provenanceSourceLabel(AppLocalizations l10n, ProvenanceSource source) =>
    switch (source) {
      ProvenanceSource.callersbox => "The Caller's Box",
      ProvenanceSource.contradb => 'ContraDB',
      ProvenanceSource.callersCompanion => "Caller's Companion",
      ProvenanceSource.manual => l10n.danceProvenanceSourceManual,
      ProvenanceSource.json => l10n.danceProvenanceSourceJson,
      ProvenanceSource.publishedCollection => l10n.publishedCollectionsTitle,
    };
