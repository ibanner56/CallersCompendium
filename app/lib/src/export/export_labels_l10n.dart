import 'package:compendium_core/compendium_core.dart';

import '../../l10n/app_localizations.dart';

/// Resolves the app's [AppLocalizations] into the plain-Dart export label value
/// objects the renderers/PDF builders consume, so exported documents (plain
/// text and PDF) follow the UI language (localization decision #529).
///
/// The renderers live in (or below) the Flutter-free `compendium_core` package
/// and cannot call `AppLocalizations` themselves; the app resolves these at the
/// call site and injects them — the same contract used for facet display
/// strings (formation/level/status).
DanceExportLabels danceExportLabels(AppLocalizations l10n) => DanceExportLabels(
  formation: l10n.exportLabelFormation,
  level: l10n.exportLabelLevel,
  mixer: l10n.exportLabelMixer,
  status: l10n.exportLabelStatus,
  phrase: l10n.exportLabelPhrase,
  figures: l10n.exportLabelFigures,
  callingNotes: l10n.exportLabelCallingNotes,
  walkthrough: l10n.exportLabelWalkthrough,
  beats: l10n.exportBeatsLabel,
);

ProgramExportLabels programExportLabels(AppLocalizations l10n) =>
    ProgramExportLabels(
      band: l10n.exportLabelBand,
      caller: l10n.exportLabelCaller,
      level: l10n.exportLabelLevel,
      notes: l10n.exportLabelNotes,
      alt: l10n.exportLabelAlt,
      guest: l10n.exportLabelGuest,
      performed: l10n.exportLabelPerformed,
      unknownDance: l10n.exportUnknownDanceLabel,
      minutes: l10n.exportMinutesLabel,
      venue: l10n.exportLabelVenue,
      time: l10n.exportLabelTime,
      schedule: l10n.exportLabelSchedule,
      price: l10n.exportLabelPrice,
      sponsor: l10n.exportLabelSponsor,
      figures: l10n.exportLabelFigures,
      alternate: l10n.exportIncludeFiguresAlternate,
    );

ProgramMatrixExportLabels programMatrixExportLabels(AppLocalizations l10n) =>
    ProgramMatrixExportLabels(
      defaultTitle: l10n.exportMatrixDefaultTitle,
      danceColumn: l10n.exportMatrixDanceColumn,
      formationColumn: l10n.exportMatrixFormationColumn,
      emptyState: l10n.exportMatrixEmptyState,
      legendDebut: l10n.exportMatrixLegendDebut,
      legendFirst: l10n.exportMatrixLegendFirst,
      legendPresent: l10n.exportMatrixLegendPresent,
      legendCollision: l10n.exportMatrixLegendCollision,
      omittedCaption: l10n.exportMatrixOmittedCaption,
    );
