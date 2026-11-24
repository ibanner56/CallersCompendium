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
  tunes: l10n.exportLabelTunes,
  hook: l10n.exportLabelHook,
  sources: l10n.exportLabelSources,
  beats: l10n.exportBeatsLabel,
  bars: l10n.danceFigureBars,
  namedPhrases: l10n.exportNamedPhrases,
  namedPhraseSeparator: l10n.exportNamedPhraseSeparator,
  labelSeparator: l10n.exportLabelSeparator,
  pageOf: l10n.exportPageOfPages,
  // The dance detail screen's own credit and tune-detail lines, so a card
  // reads as the screen does.
  authorsWithYear: l10n.danceAuthorsWithYear,
  composedYear: l10n.danceComposedYear,
  interpretedBy: l10n.danceInterpretedBy,
  interpretedByWithYear: l10n.danceInterpretedByWithYear,
  interpretedYear: l10n.danceInterpretedYear,
  meter: l10n.danceMeterValue,
  musicalKey: l10n.danceMusicalKeyValue,
  barnes: l10n.danceBarnesValue,
);

ProgramExportLabels programExportLabels(AppLocalizations l10n) =>
    ProgramExportLabels(
      band: l10n.exportLabelBand,
      caller: l10n.exportLabelCaller,
      level: l10n.exportLabelLevel,
      notes: l10n.exportLabelNotes,
      alt: l10n.exportLabelAlt,
      guest: l10n.exportLabelGuest,
      unknownDance: l10n.exportUnknownDanceLabel,
      minutes: l10n.exportMinutesLabel,
      venue: l10n.exportLabelVenue,
      time: l10n.exportLabelTime,
      schedule: l10n.exportLabelSchedule,
      price: l10n.exportLabelPrice,
      sponsor: l10n.exportLabelSponsor,
      figures: l10n.exportLabelFigures,
      alternate: l10n.exportIncludeFiguresAlternate,
      by: l10n.exportSlotAuthorSuffix,
      labelSeparator: l10n.exportLabelSeparator,
      pageOf: l10n.exportPageOfPages,
      lesson: l10n.exportLabelLesson,
      timeRange: l10n.exportTimeRange,
      endsAt: l10n.exportEndsAt,
      nextDay: l10n.exportNextDay,
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
      legendCollisionBeats: l10n.exportMatrixLegendCollisionBeats,
      legendCollisionPhrase: l10n.exportMatrixLegendCollision,
      omittedCaption: l10n.exportMatrixOmittedCaption,
      pageOf: l10n.exportPageOfPages,
    );
