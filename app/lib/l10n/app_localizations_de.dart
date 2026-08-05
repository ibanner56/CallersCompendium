// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for German (`de`).
class AppLocalizationsDe extends AppLocalizations {
  AppLocalizationsDe([String locale = 'de']) : super(locale);

  @override
  String get appTitle => 'Caller\'s Compendium';

  @override
  String get navCollection => 'Sammlung';

  @override
  String get navPrograms => 'Programme';

  @override
  String get navSettings => 'Einstellungen';

  @override
  String get navGuide => 'Leitfaden';

  @override
  String get navGuideTooltip => 'Benutzerhandbuch';

  @override
  String get navSearch => 'Suche';

  @override
  String navSearchTooltip(String hint) {
    return 'Suchen ($hint)';
  }

  @override
  String get appBootstrapPreparing => 'Sammlung wird vorbereitet';

  @override
  String get appBootstrapRebuildingIndex => 'Suchindex wird neu aufgebaut';

  @override
  String appBootstrapRebuildingIndexProgress(int percent) {
    return 'Suchindex wird neu aufgebaut… $percent%';
  }

  @override
  String get appBootstrapError => 'Sammlung konnte nicht vorbereitet werden.';

  @override
  String get migrationDowngradeMessage =>
      'Diese Daten wurden mit einer neueren Version von Caller’s Compendium erstellt – bitte aktualisiere die App.';

  @override
  String migrationSnapshotAbortedMessage(String cause) {
    return 'Caller’s Compendium wurde nicht gestartet, weil vor der Aktualisierung deiner gespeicherten Daten keine automatische Sicherung erstellt werden konnte. ${cause}Schaffe Speicherplatz (oder repariere den Sicherungsordner) und öffne die App dann erneut – oder öffne sie erneut und fahre ohne Sicherung fort.';
  }

  @override
  String get migrationSnapshotCauseDiskFull =>
      'Auf deinem Gerät ist offenbar wenig Speicherplatz frei.';

  @override
  String get migrationSnapshotCauseUnwritableBackupsDir =>
      'Der automatische Sicherungsordner konnte nicht beschrieben werden.';

  @override
  String get migrationSnapshotConsentTitle =>
      'Sicherung deiner Daten fehlgeschlagen';

  @override
  String migrationSnapshotConsentBody(String cause) {
    return 'Bevor deine gespeicherten Daten in ein neues Format aktualisiert werden, erstellt Caller’s Compendium eine automatische Sicherung, damit eine fehlgeschlagene Aktualisierung rückgängig gemacht werden kann. Diese Sicherung konnte diesmal nicht erstellt werden.$cause\n\nWenn du ohne Sicherung fortfährst und die Aktualisierung unterbrochen wird, könnten einige deiner Tänze oder Programme verloren gehen. Du kannst die App beenden, Speicherplatz schaffen (oder den Sicherungsordner reparieren) und sie erneut öffnen, um es noch einmal zu versuchen.';
  }

  @override
  String get migrationSnapshotConsentQuit => 'Beenden';

  @override
  String get migrationSnapshotConsentProceed => 'Ohne Sicherung fortfahren';

  @override
  String get confirmDeleteTitle => 'Löschen?';

  @override
  String confirmDeleteBody(String itemLabel) {
    return '„$itemLabel“ wird gelöscht. Sie können dies rückgängig machen.';
  }

  @override
  String get colorEditHexLabel => 'Hex';

  @override
  String get settingsTitle => 'Einstellungen';

  @override
  String get settingsGeneralTitle => 'Allgemein';

  @override
  String get settingsAppearanceTitle => 'Darstellung';

  @override
  String get settingsDialectTitle => 'Dialekt';

  @override
  String get settingsDefaultsTitle => 'Standardwerte';

  @override
  String get settingsUpdatesTitle => 'Updates';

  @override
  String get settingsDiagnosticsTitle => 'Diagnose';

  @override
  String get settingsAboutTitle => 'Über';

  @override
  String get commonSystemDefault => 'Systemstandard';

  @override
  String get commonComingSoon => 'Demnächst verfügbar';

  @override
  String get settingsLanguageRegionTitle => 'Sprache & Region';

  @override
  String get settingsRegionalFormatsHeader => 'Formate';

  @override
  String get settingsRegionalLanguageHeader => 'Sprache';

  @override
  String get settingsDateFormatTitle => 'Datumsformat';

  @override
  String settingsDateFormatSubtitle(String example) {
    return 'Wie die Datumsangaben von Veranstaltungen angezeigt werden. Beispiel: $example';
  }

  @override
  String get settingsDateFormatYmd => 'Jahr-Monat-Tag (2026-07-15)';

  @override
  String get settingsDateFormatDmy => 'Tag/Monat/Jahr (15/07/2026)';

  @override
  String get settingsDateFormatMdy => 'Monat/Tag/Jahr (07/15/2026)';

  @override
  String get settingsDateFormatCustom => 'Benutzerdefiniert…';

  @override
  String get settingsDateFormatCustomPatternLabel =>
      'Benutzerdefiniertes Datumsmuster';

  @override
  String get settingsDateFormatCustomPatternHint => 'MM.DD.YY';

  @override
  String get settingsDateFormatCustomLegend =>
      'Tokens: yyyy oder yy = Jahr, MM = Monat (MMM = Kurzname, MMMM = vollständiger Name), d oder dd = Tag. Trennzeichen: - / . , oder Leerzeichen.';

  @override
  String get settingsDateFormatCustomInvalid =>
      'Unbekanntes Muster – bis zur Korrektur wird die Systemvorgabe verwendet.';

  @override
  String get settingsFirstDayOfWeekTitle => 'Erster Wochentag';

  @override
  String get settingsFirstDayOfWeekSubtitle =>
      'Welcher Tag die Woche in den eigenen Datumsansichten der App beginnt, etwa im Wochenstreifen der Programmliste.';

  @override
  String get settingsFirstDayOfWeekSunday => 'Sonntag';

  @override
  String get settingsFirstDayOfWeekMonday => 'Montag';

  @override
  String get settingsFirstDayOfWeekSaturday => 'Samstag';

  @override
  String get settingsAppLanguageTitle => 'App-Sprache';

  @override
  String get settingsAppLanguageSubtitle =>
      'Wählen Sie die Sprache der App-Oberfläche.';

  @override
  String get settingsAboutHelpHeader => 'Hilfe';

  @override
  String get settingsAboutUserGuideTitle => 'Benutzerhandbuch';

  @override
  String get settingsAboutUserGuideSubtitle =>
      'Lesen Sie die integrierten Anleitungen – Erste Schritte, Dialekte, Importe und mehr. Funktioniert offline.';

  @override
  String get settingsAboutLicenseHeader => 'Lizenz';

  @override
  String get settingsAboutLicenseBody =>
      'Caller\'s Compendium ist freie Software, lizenziert unter der GNU Affero General Public License, Version 3 (AGPL-3.0). Sie dürfen es unter dieser Lizenz frei verwenden, studieren, teilen und modifizieren. Da die AGPL es vorschreibt, wird der vollständige entsprechende Quellcode jedem angeboten, der die App verwendet.';

  @override
  String get settingsAboutViewSourceTitle => 'Quellcode auf GitHub ansehen';

  @override
  String get settingsAboutFontsHeader => 'Schriftarten';

  @override
  String get settingsAboutFontsBody =>
      'Diese App bündelt die folgenden Schriftarten unter der SIL Open Font License 1.1. Ihre vollständigen Lizenztexte sind unter „Lizenzen ansehen“ unten verfügbar.';

  @override
  String get settingsAboutFontFrauncesSubtitle =>
      'SIL Open Font License 1.1 · © The Fraunces Project Authors — Display & Überschriften';

  @override
  String get settingsAboutFontAtkinsonSubtitle =>
      'SIL Open Font License 1.1 · © Braille Institute of America, Inc. — Fließtext, UI & Perform';

  @override
  String get settingsAboutFontRobotoSubtitle =>
      'SIL Open Font License 1.1 · © The Roboto Project Authors — Fallback';

  @override
  String get settingsAboutThemesHeader => 'Designs';

  @override
  String get settingsAboutThemesBody =>
      'Einige optionale Farbdesigns sind von beliebten Code-Editor-Paletten inspiriert – One Dark, Dracula, Nord, Tokyo Night, Gruvbox und Catppuccin darunter – neu abgeleitet und kontrastoptimiert für diese App. Designnamen dienen nur zur Nennung der jeweiligen Inspiration.';

  @override
  String get settingsAboutDanceDataHeader => 'Tanzdaten';

  @override
  String get settingsAboutDanceDataBody =>
      'Tanzdaten stützen sich auf The Caller’s Box (Chris Page & Michael Dyck), deren Sammlung unter der Creative Commons Attribution-NonCommercial-Lizenz (CC BY-NC) veröffentlicht ist – mit Dankbarkeit.';

  @override
  String get settingsAboutLicensesHeader => 'Lizenzen';

  @override
  String get settingsAboutViewLicensesTitle => 'Lizenzen ansehen';

  @override
  String get settingsAboutViewLicensesSubtitle =>
      'Vollständige Open-Source-Lizenztexte, einschließlich der gebündelten Schriftarten.';

  @override
  String get settingsAboutLegalese =>
      '© Die Caller\'s Compendium-Mitwirkenden. Lizenziert unter AGPL-3.0.';

  @override
  String settingsAboutVersion(String version) {
    return 'Version $version';
  }

  @override
  String settingsAboutVersionLine(
    String appName,
    String version,
    String license,
  ) {
    return '$appName · Version $version · $license';
  }

  @override
  String get settingsUpdatesHeader => 'Updates';

  @override
  String get settingsUpdatesCheckNowTitle => 'Nach Updates suchen';

  @override
  String settingsUpdatesStatusIdle(String version) {
    return 'Sie verwenden Version $version.';
  }

  @override
  String get settingsUpdatesStatusChecking => 'Wird geprüft…';

  @override
  String settingsUpdatesStatusNoUpdate(String version) {
    return 'Kein Update gefunden. Sie verwenden Version $version.';
  }

  @override
  String settingsUpdatesStatusAvailable(String version) {
    return 'Version $version ist verfügbar. Sehen Sie das Banner für weitere Details.';
  }

  @override
  String get settingsUpdatesChannelHeader => 'Kanal';

  @override
  String get settingsUpdatesBetaTitle => 'Beta-Kanal';

  @override
  String get settingsUpdatesBetaSubtitle =>
      'Beta-Vorabversionen erhalten. Deaktiviert bedeutet nur stabile Versionen.';

  @override
  String get settingsUpdatesAutoHeader => 'Automatische Prüfungen';

  @override
  String get settingsUpdatesAutoTitle => 'Automatisch prüfen';

  @override
  String get settingsUpdatesAutoSubtitle =>
      'Beim App-Start im Hintergrund nach einer neueren Version suchen. Standardmäßig deaktiviert.';

  @override
  String get settingsUpdatesPrivacyNote =>
      'Die Update-Prüfung lädt über HTTPS nur eine kleine Versionsdatei herunter – es werden keinerlei Daten über Sie, Ihr Gerät oder Ihre Nutzung übertragen. Es wird nichts automatisch heruntergeladen oder installiert: Sie entscheiden, wann ein Update heruntergeladen wird, es wird vor dem Öffnen verifiziert, und Ihr Systeminstallationsprogramm schließt die Installation ab.';

  @override
  String get settingsUpdatesDownloadingTitle => 'Update wird heruntergeladen';

  @override
  String get settingsUpdatesDownloadingIndeterminate => 'Wird heruntergeladen…';

  @override
  String settingsUpdatesDownloadingPercent(int percent) {
    return 'Wird heruntergeladen… $percent%';
  }

  @override
  String get settingsUpdatesVerifyingTitle => 'Download wird verifiziert';

  @override
  String get settingsUpdatesVerifyingSubtitle =>
      'SHA256-Integrität des Downloads wird überprüft…';

  @override
  String get settingsUpdatesHandoffTitle =>
      'Installationsprogramm wird vorbereitet';

  @override
  String get settingsUpdatesHandoffSubtitle =>
      'Das verifizierte Update wird an Ihr System übergeben…';

  @override
  String get settingsUpdatesCompletedTitle => 'Update heruntergeladen';

  @override
  String get settingsUpdatesCompletedSubtitle =>
      'Folgen Sie den Anweisungen Ihres Systeminstallationsprogramms, um die Aktualisierung abzuschließen.';

  @override
  String get settingsUpdatesCompletedSubtitleRevealed =>
      'Verifiziert und im Dateimanager angezeigt – führen Sie das Installationsprogramm aus, um die Aktualisierung abzuschließen.';

  @override
  String get settingsUpdatesDownloadTitle =>
      'Update herunterladen & installieren';

  @override
  String get settingsUpdatesDownloadError =>
      'Das Update konnte nicht heruntergeladen werden.';

  @override
  String settingsUpdatesDownloadSubtitle(String version) {
    return 'Version $version herunterladen, verifizieren und Installationsprogramm öffnen. Die App ersetzt sich nie selbst.';
  }

  @override
  String get settingsDialectHeader => 'Dialekte';

  @override
  String get settingsDialectNewButton => 'Neuer Dialekt';

  @override
  String get settingsDialectNewDefaultName => 'Mein Dialekt';

  @override
  String get settingsDialectCreateConfirm => 'Erstellen';

  @override
  String get settingsDialectDuplicateFrom => 'Duplizieren von…';

  @override
  String get settingsDialectRenameTitle => 'Dialekt umbenennen';

  @override
  String get settingsDialectRename => 'Umbenennen';

  @override
  String get settingsDialectEditTerms => 'Begriffe bearbeiten';

  @override
  String get settingsDialectDuplicateToCustomize => 'Duplizieren zum Anpassen';

  @override
  String get settingsDialectDeleteTitle => 'Dialekt löschen?';

  @override
  String settingsDialectDeleteConfirmBody(String name) {
    return '„$name“ wird dauerhaft entfernt.';
  }

  @override
  String get settingsDialectActionsTooltip => 'Dialekt-Aktionen';

  @override
  String get settingsDialectPresetBadge => 'Voreinstellung';

  @override
  String get settingsDialectNameLabel => 'Name';

  @override
  String get settingsAppearanceThemeHeader => 'Design';

  @override
  String get settingsAppearanceCustomThemesHeader =>
      'Benutzerdefinierte Designs';

  @override
  String get settingsAppearanceEasterEggsHeader => 'Easter Eggs';

  @override
  String get settingsAppearanceSetListsHeader => 'Setlisten';

  @override
  String get settingsAppearanceFormationColoursHeader => 'Formationsfarben';

  @override
  String get settingsAppearanceColourDanceTitle =>
      'Farbnamen in Tanztiteln tönen das Design ein';

  @override
  String get settingsAppearanceColourDanceSubtitle =>
      'Eine spielerische Überraschung: Wenn Sie einen Tanz öffnen, dessen Titel einen Farbnamen enthält – wie Baby Rose oder Blue Boy –, wird seine Ansicht in dieser Farbe getönt. Standardmäßig deaktiviert, und es weicht zurück, wenn ein Hochkontrast-Design aktiv ist, damit die Lesbarkeit immer gewährleistet bleibt.';

  @override
  String get settingsAppearanceSetListColorTitle =>
      'Setlisten-Zeilen farblich codieren';

  @override
  String get settingsAppearanceSetListColorSubtitle =>
      'Jede Tanzzeile nach Formationsfamilie (Contra, Mixer, Square, …) einfärben. Die Formation wird immer als Text angezeigt, sodass Zeilen auch ohne Farbe lesbar bleiben.';

  @override
  String get settingsAppearanceFormationColoursTitle =>
      'Farben der Formationsbezeichnungen';

  @override
  String get settingsAppearanceFormationColoursSubtitle =>
      'Einzelne Formationen in eigenen Farben hervorheben – z. B. Becket (CW) in Gelb, Becket (CCW) in Pink – auf Tanzkarten, in den Tanzdetails und im Perform-Header.';

  @override
  String get settingsAppearanceSelectedBadge => 'Ausgewählt';

  @override
  String get settingsAppearancePreviewHeading => 'Aa Vorschau';

  @override
  String get settingsAppearancePreviewBody => 'Beispiel Fließtext';

  @override
  String get settingsAppearanceNewThemeButton =>
      'Neues benutzerdefiniertes Design';

  @override
  String get settingsAppearanceNewThemeDefaultName => 'Mein Design';

  @override
  String get settingsAppearanceCustomThemesEmpty =>
      'Aktuelles Design kopieren und beliebige Farben anpassen. Benutzerdefinierte Designs werden auf diesem Gerät gespeichert.';

  @override
  String get settingsAppearanceDeleteThemeTitle => 'Design löschen?';

  @override
  String settingsAppearanceDeleteThemeBody(String name) {
    return '„$name“ wird dauerhaft entfernt.';
  }

  @override
  String settingsAppearanceCustomThemeSemantic(String name) {
    return 'Benutzerdefiniertes Design $name';
  }

  @override
  String get settingsAppearanceThemeActionsTooltip => 'Design-Aktionen';

  @override
  String get settingsDefaultsProgramHeader => 'Programm-Standardwerte';

  @override
  String get settingsDefaultsCallerLabel => 'Standard-Caller';

  @override
  String get settingsDefaultsPrefilledHelper =>
      'In neuen Programmen vorausgefüllt; pro Programm bearbeitbar.';

  @override
  String get settingsDefaultsBandLabel => 'Standard-Band';

  @override
  String get settingsDefaultsDisplayHeader => 'Anzeigestandards';

  @override
  String get settingsDefaultsSortTitle => 'Sortierreihenfolge der Sammlung';

  @override
  String get settingsDefaultsSortSubtitle =>
      'Wie die Sammlung beim Öffnen sortiert ist. Die Sortierung kann beim Durchsuchen noch geändert werden.';

  @override
  String get settingsDefaultsCanonicalTitle =>
      'Tanzdetails in kanonischen Begriffen öffnen';

  @override
  String get settingsDefaultsCanonicalSubtitle =>
      'Wenn aktiviert, wird ein Tanz mit kanonischen Rollen- und Bewegungsnamen statt Ihrem aktiven Dialekt geöffnet. Sie können die Ansicht noch wechseln, während der Tanz geöffnet ist.';

  @override
  String get settingsDefaultsCollectionCardHeader => 'Collection card fields';

  @override
  String get settingsDefaultsCollectionCardSubtitle =>
      'Choose which details appear on each dance row. All fields are shown by default.';

  @override
  String get settingsDefaultsCollectionCardAuthors => 'Authors';

  @override
  String get settingsDefaultsCollectionCardCalledCount => 'Times called';

  @override
  String get settingsDefaultsCollectionCardFormation => 'Formation';

  @override
  String get settingsDefaultsCollectionCardStatus => 'Status';

  @override
  String get settingsDefaultsCollectionCardLevel => 'Level';

  @override
  String get settingsDefaultsCollectionCardRating => 'Rating';

  @override
  String get settingsDefaultsCollectionCardTags => 'Tags';

  @override
  String get settingsDefaultsCollectionCardCustomFields => 'Custom fields';

  @override
  String get settingsDefaultsAuthoringHeader =>
      'Standardwerte für die Tanzerstellung';

  @override
  String get settingsDefaultsFreeTextEntryTitle => 'Freitexteingabe';

  @override
  String get settingsDefaultsFreeTextEntrySubtitle =>
      'Wenn aktiviert, können Sie beim Hinzufügen einer neuen Figur diese als eine Zeile eingeben (z. B. „neighbor balance & swing“) statt sie Feld für Feld aufzubauen. Die Zeile wird in Figuren geparst; Nichterkanntes wird als benutzerdefinierte Figur gespeichert, die Sie später korrigieren können. Das Bearbeiten einer bestehenden Figur verwendet immer den vollständigen Editor.';

  @override
  String get settingsDefaultsAggressiveBeatsUpdateTitle =>
      'Figurtakte aggressiv neu berechnen';

  @override
  String get settingsDefaultsAggressiveBeatsUpdateSubtitle =>
      'Wenn aktiviert, wird die Taktzahl einer Figur sofort neu berechnet, sobald sich die Bewegung oder ein zeitrelevanter Parameter ändert – auch wenn dabei eine manuell eingegebene Taktzahl überschrieben wird. Wenn deaktiviert (Standard), wird eine von Ihnen bearbeitete Taktzahl nie automatisch geändert.';

  @override
  String get settingsDefaultsFigureShorthandsTitle => 'Figur-Abkürzungen';

  @override
  String get settingsDefaultsFigureShorthandsEmptySubtitle =>
      'Kurze Tokens einer oder mehreren Figuren zuordnen, die bei der Freitexteingabe eingefügt werden können.';

  @override
  String settingsDefaultsFigureShorthandsCountSubtitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Abkürzungen definiert.',
      one: '1 Abkürzung definiert.',
    );
    return '$_temp0';
  }

  @override
  String get settingsDefaultsFormTitle => 'Tanzform';

  @override
  String get settingsDefaultsFormSubtitle =>
      'Die Tanzform, mit der ein neuer Tanz beginnt. Pro Tanz noch änderbar.';

  @override
  String get settingsDefaultsFormationTitle => 'Formation';

  @override
  String get settingsDefaultsFormationSubtitle =>
      'Die Formation, in der ein neuer Tanz beginnt. Pro Tanz noch änderbar.';

  @override
  String get settingsDefaultsProgressionTitle => 'Progression';

  @override
  String get settingsDefaultsProgressionSubtitle =>
      'Die Progression, mit der ein neuer Tanz beginnt. Pro Tanz noch änderbar.';

  @override
  String get settingsDefaultsPhraseLabel => 'Standard-Phrasierungsstruktur';

  @override
  String get settingsDefaultsPhraseHelper =>
      'In neue Tänze voreingestellt. Leer = Standard 4×16 (A1 A2 B1 B2); z. B. 6*8*2.';

  @override
  String get settingsDefaultsStartingFiguresTitle => 'Startfiguren';

  @override
  String get settingsDefaultsStartingFiguresSubtitle =>
      'Die Figuren, mit denen ein neuer Tanz beginnt. Standard ist ein einzelnes „Stand still“ (8 Takte); leer lassen für einen leeren neuen Tanz. Pro Tanz bearbeitbar.';

  @override
  String get settingsDefaultsMoveDefaultsTitle => 'Bewegungsstandards';

  @override
  String get settingsDefaultsMoveDefaultsSubtitle =>
      'Bevorzugte Parameterwerte, die beim Einfügen einer Bewegung während der Tanzeingabe angewendet werden. Diese überschreiben die integrierten Standardwerte der Bewegung; Sie können anschließend noch jeden Parameter der Figur ändern. Nicht gesetzte Bewegungen und Parameter verwenden die integrierten Standardwerte.';

  @override
  String get settingsDefaultsAddMoveButton => 'Bewegungsstandard hinzufügen';

  @override
  String get settingsDefaultsRemoveMoveTooltip => 'Entfernen';

  @override
  String get settingsDefaultsMoveGone =>
      'Diese Bewegung ist nicht mehr in der Taxonomie.';

  @override
  String get settingsDefaultsMoveNoParams =>
      'Diese Bewegung hat keine Standard-Parameter.';

  @override
  String get settingsFormationColoursTitle => 'Formationsfarben';

  @override
  String get settingsFormationColoursIntro =>
      'Einer Formation eine eigene Farbe geben, um ihre Bezeichnung auf Tanzkarten, in Tanzdetails und im Perform-Header hervorzuheben. Nur die angepassten Formationen werden hervorgehoben; die übrigen zeigen ihre Bezeichnung wie gewöhnlich. Die Formation wird immer als Text angezeigt, sodass Bezeichnungen auch ohne Farbe lesbar bleiben.';

  @override
  String get settingsFormationColoursListHeader => 'Formationen';

  @override
  String get settingsFormationColoursCustom => 'Benutzerdefinierte Farbe';

  @override
  String get settingsFormationColoursFamilyDefault => 'Familienstandard';

  @override
  String settingsFormationColoursResetTooltip(String label) {
    return '$label auf den Familienstandard zurücksetzen';
  }

  @override
  String get settingsAppearanceTagColoursHeader => 'Tag colours';

  @override
  String get settingsAppearanceTagColoursTitle => 'Tag colours';

  @override
  String get settingsAppearanceTagColoursSubtitle =>
      'Give a tag its own colour to make it stand out on dance cards and dance detail. The tag\'s name is always shown too, so tags stay readable without colour.';

  @override
  String get settingsTagColoursTitle => 'Tag colours';

  @override
  String get settingsTagColoursIntro =>
      'Give a tag its own colour to make it stand out wherever it appears. Only the tags you colour change; the rest look exactly as they do now. The tag\'s name is always shown too, so tags stay readable without colour.';

  @override
  String get settingsTagColoursListHeader => 'Tags';

  @override
  String get settingsTagColoursEmpty =>
      'You haven\'t created any tags yet. Add a tag to a dance and it will appear here.';

  @override
  String get settingsTagColoursCustom => 'Custom colour';

  @override
  String get settingsTagColoursNoColour => 'No colour';

  @override
  String settingsTagColoursResetTooltip(String label) {
    return 'Remove $label\'s colour';
  }

  @override
  String get settingsTagColoursSaveError =>
      'Couldn\'t save that colour. Please try again.';

  @override
  String get settingsTagColoursLoadError => 'Couldn\'t load your tags.';

  @override
  String get settingsGeneralLibraryHeader => 'Bibliothek';

  @override
  String get settingsGeneralSortIgnoreArticlesTitle =>
      'Führende Artikel beim Sortieren ignorieren';

  @override
  String get settingsGeneralSortIgnoreArticlesSubtitle =>
      'Wenn aktiviert, alphabetisiert die Tanzliste Titel ohne führendes „the“, „a“ oder „an“ – so wird „The Nice Combination“ unter N einsortiert. Deaktivieren, um nach dem wörtlichen Titel zu sortieren.';

  @override
  String get settingsGeneralVenuesHeader => 'Veranstaltungsorte';

  @override
  String get settingsGeneralVenueEntityModeTitle =>
      'Wiederverwendbare Veranstaltungsort-Einträge verwenden';

  @override
  String get settingsGeneralVenueEntityModeSubtitle =>
      'Veranstaltungsorte in wiederverwendbare Einträge mit Adresse, Kontakten und Terminen umwandeln, die von vielen Programmen geteilt und zentral bearbeitet werden können. Wenn deaktiviert, ist der Veranstaltungsort eines Programms ein einfaches Freitextfeld. Das Umschalten ist verlustfrei – Ihr eingetippter Veranstaltungsort und alle verknüpften Einträge bleiben erhalten.';

  @override
  String get settingsGeneralManageVenuesTitle => 'Veranstaltungsorte verwalten';

  @override
  String get settingsGeneralManageVenuesSubtitle =>
      'Wiederverwendbare Veranstaltungsort-Einträge durchsuchen, bearbeiten und löschen.';

  @override
  String get settingsGeneralPerformanceHeader => 'Leistung';

  @override
  String get settingsGeneralAutoSizePerformTitle =>
      'Perform-Karten automatisch skalieren';

  @override
  String get settingsGeneralAutoSizePerformSubtitle =>
      'Jede Karte so skalieren, dass der vollständige Tanz oder Slot ohne Scrollen auf den Bildschirm passt. Deaktivieren, um die Größe selbst mit A− / A+ einzustellen.';

  @override
  String get settingsGeneralCallingHistoryHeader => 'Calling-Verlauf';

  @override
  String get settingsGeneralRequirePerformedForHistoryTitle =>
      '„Als aufgeführt markieren“ für Calling-Verlauf erfordern';

  @override
  String get settingsGeneralRequirePerformedForHistorySubtitle =>
      'Wenn aktiviert, listet der Calling-Verlauf eines Tanzes nur Programme auf, deren Slot für diesen Tanz als aufgeführt markiert wurde. Wenn deaktiviert, erscheint ein Programm, sobald es den Tanz enthält.';

  @override
  String get settingsGeneralTrackHistoryForAllCallersTitle =>
      'Track calling history for all callers';

  @override
  String get settingsGeneralTrackHistoryForAllCallersSubtitle =>
      'When off and a default caller is set, calling history and counts include only programs led by that caller. When on — or when no default caller is set — every program that contains the dance is tracked.';

  @override
  String get settingsGeneralAccessibilityHeader => 'Barrierefreiheit';

  @override
  String get settingsGeneralReduceMotionTitle => 'Bewegung reduzieren';

  @override
  String get settingsGeneralReduceMotionSubtitle =>
      'Nicht wesentliche Animationen dämpfen oder überspringen, z. B. animiertes Scrollen beim Navigieren zwischen Suchergebnissen oder Figuren.';

  @override
  String get settingsGeneralVerboseFiguresTitle =>
      'Ausführlichen Figurentext immer anzeigen';

  @override
  String get settingsGeneralVerboseFiguresSubtitle =>
      'Den vollständigen gesprochen-artigen Figurentext in der Tanzansicht auf dem Bildschirm anzeigen, nicht nur für Bildschirmleseprogramme. Deaktivieren für die Kurznotation.';

  @override
  String get settingsGeneralDecimalTurnsTitle =>
      'Drehungen als Dezimalzahlen anzeigen';

  @override
  String get settingsGeneralDecimalTurnsSubtitle =>
      'Dreh- und Rotationsmengen als Dezimalzahlen (0,75) statt als Brüche (¾) anzeigen. Bildschirmleseprogramm-Text ist nicht betroffen.';

  @override
  String get settingsGeneralConfirmBeforeDeleteTitle =>
      'Vor dem Löschen bestätigen';

  @override
  String get settingsGeneralConfirmBeforeDeleteSubtitle =>
      'Vor dem Löschen eines Tanzes oder Programms um Bestätigung bitten. Löschvorgänge können noch rückgängig gemacht werden; dies fügt nur eine explizite Abfrage vorweg hinzu.';

  @override
  String get settingsGeneralDeletedItemsHeader => 'Gelöschte Elemente';

  @override
  String get settingsGeneralSoftDeleteRetentionTitle =>
      'Gelöschte Tänze behalten für';

  @override
  String get settingsGeneralSoftDeleteRetentionSubtitle =>
      'Gelöschte Tänze werden so lange aufbewahrt, bevor sie beim App-Start dauerhaft entfernt werden. „Nie“ behält sie, bis Sie sie manuell bereinigen.';

  @override
  String settingsGeneralSoftDeleteRetentionDays(int days) {
    return '$days Tage';
  }

  @override
  String get settingsGeneralSoftDeleteRetentionNever => 'Nie';

  @override
  String get settingsGeneralImportHeader => 'Import';

  @override
  String get settingsGeneralImportDancesSubtitle =>
      'Tänze aus einer Caller\'s Compendium JSON-Datei in Ihre Sammlung importieren. Sie überprüfen jeden Tanz und bestätigen, bevor etwas hinzugefügt wird.';

  @override
  String get settingsGeneralImportEllipsisAction => 'Importieren…';

  @override
  String get settingsGeneralReparseCustomFiguresTitle =>
      'Benutzerdefinierte Figuren erneut prüfen';

  @override
  String get settingsGeneralReparseCustomFiguresSubtitle =>
      'Importierte Tänze erneut parsen, deren Figuren nur deshalb als benutzerdefiniert gespeichert wurden, weil sie beim Import nicht erkannt werden konnten. Verbessertes Parsing aktualisiert sie an Ort und Stelle – Ihre Tags, Bewertungen und Notizen bleiben erhalten. Sie können eine Vorschau sehen und bestätigen, bevor etwas geändert wird.';

  @override
  String get settingsGeneralReparseCustomFiguresAction => 'Erneut prüfen…';

  @override
  String get settingsGeneralBackupRestoreHeader =>
      'Sicherung & Wiederherstellung';

  @override
  String get backupExported => 'Sicherung exportiert.';

  @override
  String get backupExportFailed => 'Sicherung konnte nicht exportiert werden.';

  @override
  String get backupRestoreIntegrityFailed =>
      'Diese Sicherung hat die Integritätsprüfung nicht bestanden, daher ist sie möglicherweise beschädigt oder wurde nach dem Export verändert. Die Wiederherstellung wurde abgebrochen und Ihre Daten sind unverändert.';

  @override
  String get backupRestoreIncompatibleVersion =>
      'Diese Sicherung enthält Elemente, die diese App-Version nicht lesen kann (sie stammt möglicherweise von einer neueren Version), daher wurde die Wiederherstellung abgebrochen. Ihre Daten sind unverändert.';

  @override
  String get backupRestoreInvalidFile =>
      'Wiederherstellung fehlgeschlagen: Die Datei ist keine gültige Sicherung. Ihre Daten sind unverändert.';

  @override
  String backupRestoreSkippedProblems(int count) {
    return 'Sicherung wiederhergestellt, $count Problem(e) übersprungen.';
  }

  @override
  String get backupRestored => 'Sicherung wiederhergestellt.';

  @override
  String get backupRestoreFailed =>
      'Sicherung konnte nicht wiederhergestellt werden.';

  @override
  String get backupRestoreSettingsFailed =>
      'Your dances and programs were restored, but applying your saved settings failed. Your restored content is safe — you can retry applying settings.';

  @override
  String get backupRestoreSettingsRetryAction => 'Retry settings';

  @override
  String get backupRestoreSettingsRetried => 'Settings applied.';

  @override
  String get backupExportTitle => 'Sicherung exportieren';

  @override
  String get backupExportSubtitle =>
      'Die gesamte Sammlung, Programme, benutzerdefinierte Felder, Dialekte, Designs und Einstellungen in einer einzelnen JSON-Datei speichern, die Sie sicher aufbewahren oder auf ein anderes Gerät übertragen können.';

  @override
  String get backupExportAction => 'Exportieren';

  @override
  String get backupRestoreTitle => 'Aus einer Sicherung wiederherstellen';

  @override
  String get backupRestoreSubtitle =>
      'Alles, was sich derzeit in der App befindet, durch den Inhalt einer Sicherungsdatei ersetzen. Dies kann nicht rückgängig gemacht werden.';

  @override
  String get backupRestoreAction => 'Wiederherstellen';

  @override
  String get backupReminderTitle => 'Sicherungserinnerung';

  @override
  String get backupLastBackupNever => 'Letzte Sicherung: nie';

  @override
  String backupLastBackupDate(String date) {
    return 'Letzte Sicherung: $date';
  }

  @override
  String get backupReminderOff => 'Aus';

  @override
  String get backupReminderWeekly => 'Wöchentlich';

  @override
  String get backupReminderMonthly => 'Monatlich';

  @override
  String get backupOverdueHint =>
      'Es ist schon eine Weile her seit Ihrer letzten Sicherung – erwägen Sie, jetzt eine zu exportieren.';

  @override
  String get backupRestoreDialogBody =>
      'Bei der Wiederherstellung wird alles in der App – Ihre Sammlung, Programme, Dialekte, Designs und Einstellungen – durch den Inhalt der Sicherung ersetzt. Dies kann nicht rückgängig gemacht werden.';

  @override
  String get backupChooseFileAction => 'Datei auswählen…';

  @override
  String get backupPasteJsonLabel => 'Oder Sicherungs-JSON einfügen';

  @override
  String get backupReplaceAllDataAction => 'Alle Daten ersetzen';

  @override
  String get diagnosticsNoDiagnosticsToExport =>
      'Keine Diagnosen zum Exportieren.';

  @override
  String get diagnosticsScrubbedExportUnavailable =>
      'Ein sicherer (bereinigter) Export konnte nicht vorbereitet werden, daher wurde nichts gespeichert. Bitte versuchen Sie es erneut oder verwenden Sie bewusst den vollständigen Detail-Export.';

  @override
  String get diagnosticsLogExported => 'Diagnoseprotokoll exportiert.';

  @override
  String get diagnosticsExportCancelled => 'Export abgebrochen.';

  @override
  String get diagnosticsExportFailed =>
      'Diagnoseprotokoll konnte nicht exportiert werden.';

  @override
  String get diagnosticsClearLogTitle => 'Diagnoseprotokoll löschen?';

  @override
  String get diagnosticsClearLogBody =>
      'Dies löscht das lokale Absturzprotokoll dauerhaft von diesem Gerät. Dies kann nicht rückgängig gemacht werden.';

  @override
  String get diagnosticsClearAction => 'Löschen';

  @override
  String get diagnosticsLogCleared => 'Diagnoseprotokoll geleert.';

  @override
  String get diagnosticsHeader => 'Diagnose';

  @override
  String get diagnosticsIntro =>
      'Wenn etwas schiefgeht, zeichnet die App einen technischen Hinweis in einem lokalen Protokoll auf diesem Gerät auf, um das Problem zu diagnostizieren. Es wird nie übermittelt – es gibt keine Telemetrie. Sie können es exportieren, um es einem Fehlerbericht beizufügen, oder es jederzeit löschen.';

  @override
  String get diagnosticsRecentEntriesHeader => 'Neueste Einträge';

  @override
  String get diagnosticsReadFailedTitle =>
      'Diagnoseprotokoll konnte nicht gelesen werden';

  @override
  String get diagnosticsReadFailedSubtitle =>
      'Das lokale Protokoll ist auf diesem Gerät möglicherweise nicht zugänglich. Sie können trotzdem versuchen, es zu exportieren oder zu löschen.';

  @override
  String get diagnosticsEmptyTitle => 'Keine Fehler aufgezeichnet';

  @override
  String get diagnosticsEmptySubtitle =>
      'Auf diesem Gerät wurde nichts erfasst.';

  @override
  String get diagnosticsExportHeader => 'Export';

  @override
  String get diagnosticsFullDetailTitle =>
      'Vollständige Details einschließen (kann Ihre Inhalte enthalten)';

  @override
  String get diagnosticsFullDetailSubtitle =>
      'Standardmäßig deaktiviert. Wenn deaktiviert, entfernt der Export Ihre Inhalte, Dateipfade, E-Mails und Telefonnummern.';

  @override
  String get diagnosticsExportShareLogTitle => 'Protokoll exportieren / teilen';

  @override
  String get diagnosticsExportShareFullSubtitle =>
      'Teilt das vollständige, ungeschwärzte Protokoll.';

  @override
  String get diagnosticsExportShareScrubbedSubtitle =>
      'Teilt eine bereinigte Kopie, die sicher einem Fehlerbericht beigefügt werden kann.';

  @override
  String get diagnosticsClearLogRowTitle => 'Protokoll leeren';

  @override
  String get diagnosticsClearLogRowSubtitle =>
      'Das lokale Absturzprotokoll von diesem Gerät löschen.';

  @override
  String get crashFallbackTitle => 'Hier ist etwas schiefgelaufen';

  @override
  String get crashFallbackBody =>
      'Dieser Teil der App ist auf einen unerwarteten Fehler gestoßen und hat sich erholt. Die Details wurden in einem lokalen Diagnoseprotokoll (Einstellungen ▸ Diagnose) gespeichert, das Ihr Gerät nie verlässt.';

  @override
  String get crashFallbackCopied => 'Kopiert';

  @override
  String get crashFallbackCopyDetails => 'Details kopieren';

  @override
  String get commonCancel => 'Abbrechen';

  @override
  String get commonUndo => 'Rückgängig';

  @override
  String get commonRetry => 'Erneut versuchen';

  @override
  String get commonDelete => 'Löschen';

  @override
  String get commonDuplicate => 'Duplizieren';

  @override
  String commonDuplicateTitleSuffix(String title) {
    return '$title (Kopie)';
  }

  @override
  String get commonYes => 'Ja';

  @override
  String get commonNo => 'Nein';

  @override
  String get commonOk => 'OK';

  @override
  String get commonApply => 'Anwenden';

  @override
  String get commonCouldntOpenLink => 'Link konnte nicht geöffnet werden';

  @override
  String get commonProgression => 'Progression';

  @override
  String get commonDanceFormContra => 'Contra';

  @override
  String get commonDanceFormEcd => 'Englisch (ECD)';

  @override
  String get commonDanceFormSquare => 'Square';

  @override
  String get commonProgressionNone => 'Keine Progression';

  @override
  String get commonProgressionSingle => 'Einfach';

  @override
  String get commonProgressionDouble => 'Doppelt';

  @override
  String get commonProgressionTriple => 'Dreifach';

  @override
  String get commonProgressionQuadruple => 'Vierfach';

  @override
  String get commonProgressionOther => 'Sonstige';

  @override
  String get commonDanceStatusActive => 'Aktiv';

  @override
  String get commonDanceStatusDeprecated => 'Veraltet';

  @override
  String get commonDanceStatusBroken => 'Fehlerhaft';

  @override
  String get commonDanceLevelBeginner => 'Anfänger';

  @override
  String get commonDanceLevelIntermediate => 'Mittelstufe';

  @override
  String get commonDanceLevelAdvanced => 'Fortgeschritten';

  @override
  String get commonFormationDupleImproper => 'Duple improper';

  @override
  String get commonFormationBecketCw => 'Becket (CW)';

  @override
  String get commonFormationBecketCcw => 'Becket (CCW)';

  @override
  String get commonFormationDupleProper => 'Duple proper';

  @override
  String get commonFormationDupleIndecent => 'Duple indecent';

  @override
  String get commonFormationTripleMinor => 'Triple minor';

  @override
  String get commonFormationThreeFaceThree => 'Three-face-three';

  @override
  String get commonFormationFourFaceFour => 'Four-face-four';

  @override
  String get commonFormationCircleMixer => 'Circle mixer';

  @override
  String get commonFormationSicilianCircle => 'Sicilian circle';

  @override
  String get commonFormationScatterMixer => 'Scatter mixer';

  @override
  String get commonFormationLongways => 'Longways';

  @override
  String get commonFormationTriplet => 'Triplet';

  @override
  String get commonFormationGrid => 'Grid';

  @override
  String get commonFormationOther => 'Sonstige';

  @override
  String commonFormationWithDetail(String shape, String detail) {
    return '$shape — $detail';
  }

  @override
  String get commonMixedLevel => 'Gemischtes Niveau';

  @override
  String commonShowDancesTaggedTooltip(String tagName) {
    return 'Tänze mit Tag „$tagName“ anzeigen';
  }

  @override
  String commonDeletedSnack(String title) {
    return '„$title“ gelöscht.';
  }

  @override
  String get importGapMessage =>
      'Dieser Aufruf konnte nicht geparst werden – als benutzerdefinierte Figur wörtlich gespeichert.';

  @override
  String get importGapDialogTitle => 'Nicht erkannte Figur';

  @override
  String get importGapSemanticLabel =>
      'Nicht erkannte Figur. Dieser Aufruf konnte nicht geparst werden – als benutzerdefinierte Figur wörtlich gespeichert.';

  @override
  String get collectionScreenTitle => 'Sammlung';

  @override
  String get collectionNewDance => 'Neuer Tanz';

  @override
  String get collectionSearchTooltip => 'Suchen (Strg/Cmd-K)';

  @override
  String get collectionSelectDancesTooltip => 'Tänze auswählen';

  @override
  String get collectionManageCustomFieldsTooltip =>
      'Benutzerdefinierte Felder verwalten';

  @override
  String get collectionRecentlyDeletedTooltip => 'Zuletzt gelöscht';

  @override
  String collectionSortByTooltip(String sortLabel) {
    return 'Sortieren nach ($sortLabel)';
  }

  @override
  String get collectionSortRelevance => 'Beste Übereinstimmung';

  @override
  String get collectionSortTitle => 'Titel';

  @override
  String get collectionSortAuthor => 'Autor';

  @override
  String get collectionSortRecentlyAdded => 'Zuletzt hinzugefügt';

  @override
  String get collectionSortLastCalled => 'Zuletzt aufgerufen';

  @override
  String get collectionSortAscendingTooltip =>
      'Aufsteigend (für absteigend tippen)';

  @override
  String get collectionSortDescendingTooltip =>
      'Absteigend (für aufsteigend tippen)';

  @override
  String get collectionGroupByCategoryTooltip => 'Nach Kategorie gruppieren';

  @override
  String collectionGroupByCategoryActiveTooltip(String tag) {
    return 'Gruppiert nach $tag';
  }

  @override
  String get collectionGroupByNone => 'Keine Gruppierung';

  @override
  String get collectionGroupByHeader => 'Kategorie';

  @override
  String get collectionGroupOther => 'Sonstige';

  @override
  String collectionGroupSectionSemantics(String label, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Tänze',
      one: '1 Tanz',
    );
    return '$label, $_temp0';
  }

  @override
  String get collectionExitSelectionTooltip => 'Auswahl beenden';

  @override
  String collectionSelectedCount(int count) {
    return '$count ausgewählt';
  }

  @override
  String get collectionAddTags => 'Tags hinzufügen';

  @override
  String get collectionRemoveTags => 'Tags entfernen';

  @override
  String get collectionSetLevel => 'Niveau festlegen';

  @override
  String get collectionSearchFieldLabel => 'Tänze suchen';

  @override
  String get collectionSearchFieldHint =>
      'Titel, Autoren, Figuren, Notizen suchen…';

  @override
  String get collectionClearSearchTooltip => 'Suche und Filter löschen';

  @override
  String get collectionLoadError => 'Sammlung konnte nicht geladen werden.';

  @override
  String collectionDuplicatedSnack(String title) {
    return 'Als „$title“ dupliziert.';
  }

  @override
  String get collectionEmpty =>
      'Ihre Sammlung ist leer. Fügen Sie einen Tanz hinzu oder importieren Sie einen, um loszulegen – oder aktivieren Sie die Online-Suche oben, um aus einer Online-Quelle zu importieren.';

  @override
  String get collectionFiltersTitle => 'Filter';

  @override
  String collectionFiltersActive(int count) {
    return 'Filter ($count aktiv)';
  }

  @override
  String get collectionByPhraseTitle => 'Nach Phrase';

  @override
  String collectionByPhraseActive(int count) {
    return 'Nach Phrase ($count aktiv)';
  }

  @override
  String get collectionAdvancedTitle => 'Erweitert';

  @override
  String get collectionUseAdvancedQuery => 'Erweiterte Abfrage verwenden';

  @override
  String get collectionUseAdvancedQuerySubtitle =>
      'Figuren und Sequenzen mit Alle- / Beliebige- / Keine-Gruppen kombinieren.';

  @override
  String collectionDanceCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Tänze',
      one: '1 Tanz',
    );
    return '$_temp0';
  }

  @override
  String get collectionSearchError => 'Bei der Suche ist etwas schiefgelaufen.';

  @override
  String get collectionNoResults => 'Keine Tänze entsprechen Ihrer Suche.';

  @override
  String get collectionBatchNoChanges => 'Keine Änderungen';

  @override
  String collectionBatchTagged(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Tänze getaggt',
      one: '1 Tanz getaggt',
    );
    return '$_temp0';
  }

  @override
  String collectionBatchUntagged(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Tags von $count Tänzen entfernt',
      one: 'Tags von 1 Tanz entfernt',
    );
    return '$_temp0';
  }

  @override
  String collectionBatchLevelSet(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Niveau bei $count Tänzen gesetzt',
      one: 'Niveau bei 1 Tanz gesetzt',
    );
    return '$_temp0';
  }

  @override
  String collectionBatchLevelCleared(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Niveau bei $count Tänzen geleert',
      one: 'Niveau bei 1 Tanz geleert',
    );
    return '$_temp0';
  }

  @override
  String get collectionBatchMore => 'Weitere Stapelaktionen';

  @override
  String get collectionSetRating => 'Bewertung festlegen';

  @override
  String get collectionAddTunes => 'Melodien hinzufügen';

  @override
  String get collectionClearTunes => 'Melodien löschen';

  @override
  String get collectionEditCustomField => 'Benutzerdefiniertes Feld bearbeiten';

  @override
  String collectionBatchRatingSet(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Bewertung bei $count Tänzen gesetzt',
      one: 'Bewertung bei 1 Tanz gesetzt',
    );
    return '$_temp0';
  }

  @override
  String collectionBatchRatingCleared(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Bewertung bei $count Tänzen geleert',
      one: 'Bewertung bei 1 Tanz geleert',
    );
    return '$_temp0';
  }

  @override
  String collectionBatchTunesAdded(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Melodien zu $count Tänzen hinzugefügt',
      one: 'Melodien zu 1 Tanz hinzugefügt',
    );
    return '$_temp0';
  }

  @override
  String collectionBatchTunesCleared(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Melodien von $count Tänzen geleert',
      one: 'Melodien von 1 Tanz geleert',
    );
    return '$_temp0';
  }

  @override
  String collectionBatchCustomFieldSet(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Feld bei $count Tänzen aktualisiert',
      one: 'Feld bei 1 Tanz aktualisiert',
    );
    return '$_temp0';
  }

  @override
  String collectionBatchCustomFieldCleared(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Feld bei $count Tänzen geleert',
      one: 'Feld bei 1 Tanz geleert',
    );
    return '$_temp0';
  }

  @override
  String collectionSelectDanceLabel(String title) {
    return '$title auswählen';
  }

  @override
  String collectionCalledBadge(int count) {
    return 'aufgerufen ×$count';
  }

  @override
  String collectionCalledBadgeSemantic(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count-mal aufgerufen',
      one: '1-mal aufgerufen',
    );
    return '$_temp0';
  }

  @override
  String collectionRatingSemantic(int rating) {
    return 'Bewertung: $rating von 5 Sternen';
  }

  @override
  String collectionRowActionsSemantic(String title) {
    return 'Aktionen für $title';
  }

  @override
  String get collectionSplitEmptyTitle => 'Tanz auswählen';

  @override
  String get collectionSplitEmptySubtitle =>
      'Wählen Sie einen Tanz aus der Liste, um seine Details anzuzeigen.';

  @override
  String get collectionFacetType => 'Typ';

  @override
  String get collectionFacetFormation => 'Formation';

  @override
  String get collectionFacetStatus => 'Status';

  @override
  String get collectionFacetLevel => 'Niveau';

  @override
  String get collectionFacetMinRating => 'Mindestbewertung';

  @override
  String collectionFacetMinRatingChip(int min) {
    return '≥$min★';
  }

  @override
  String get collectionFacetTags => 'Tags';

  @override
  String get collectionFacetSource => 'Quelle';

  @override
  String get collectionFacetAuthor => 'Autor';

  @override
  String get collectionFacetNone =>
      'Für diese Sammlung sind noch keine Filter verfügbar.';

  @override
  String get collectionFacetClear => 'Filter löschen';

  @override
  String collectionFacetRemoveAuthor(String name) {
    return '$name entfernen';
  }

  @override
  String get collectionFacetAuthorSearchHint => 'Autoren suchen…';

  @override
  String get collectionFacetOpContains => 'enthält';

  @override
  String get collectionFacetOpEquals => 'entspricht';

  @override
  String collectionFacetTextHint(String label) {
    return 'Nach $label filtern…';
  }

  @override
  String get collectionFacetNumOpEq => '=';

  @override
  String get collectionFacetNumOpLt => '<';

  @override
  String get collectionFacetNumOpGt => '>';

  @override
  String get collectionFacetNumOpBetween => 'zwischen';

  @override
  String get collectionFacetNumFrom => 'Von';

  @override
  String get collectionFacetNumValue => 'Wert';

  @override
  String get collectionFacetNumTo => 'Bis';

  @override
  String get collectionByPhraseOrdinalFirst => 'erste Phrase';

  @override
  String get collectionByPhraseOrdinalSecond => 'zweite Phrase';

  @override
  String get collectionByPhraseOrdinalThird => 'dritte Phrase';

  @override
  String get collectionByPhraseOrdinalFourth => 'vierte Phrase';

  @override
  String collectionByPhraseOrdinalN(int number) {
    return 'Phrase $number';
  }

  @override
  String collectionByPhraseCaption(String ordinal, String label) {
    return '$ordinal (gewöhnlich $label)';
  }

  @override
  String collectionByPhraseFieldMatch(String caption) {
    return '$caption, Figuren stimmen überein';
  }

  @override
  String collectionByPhraseFieldExclude(String caption) {
    return '$caption, Figuren stimmen nicht überein';
  }

  @override
  String collectionByPhraseRemoveMove(String move, String field) {
    return '$move aus $field entfernen';
  }

  @override
  String get collectionQueryMatchLabel => 'Übereinstimmung';

  @override
  String get collectionQueryGroupAll => 'Alle von';

  @override
  String get collectionQueryGroupAny => 'Beliebige von';

  @override
  String get collectionQueryGroupNone => 'Keine von';

  @override
  String get collectionQueryTheseConditions => 'diesen Bedingungen';

  @override
  String get collectionQueryRemoveGroup => 'Gruppe entfernen';

  @override
  String get collectionQueryEmptyGroup =>
      'Noch keine Bedingungen – fügen Sie unten eine hinzu.';

  @override
  String get collectionQueryAddCondition => 'Bedingung hinzufügen';

  @override
  String get collectionQueryHasFigure => 'Hat Figur';

  @override
  String get collectionQuerySequenceThen => 'Sequenz (dann)';

  @override
  String get collectionQueryConditionGroup => 'Bedingungsgruppe';

  @override
  String get collectionQueryAddButton => 'Hinzufügen';

  @override
  String get collectionQueryRemoveFigure => 'Figur entfernen';

  @override
  String get collectionQueryThenFirst => 'Zuerst';

  @override
  String get collectionQueryThenConnector => 'dann';

  @override
  String get collectionQueryThenLater => 'Später';

  @override
  String get collectionQueryRemoveSequence => 'Sequenz entfernen';

  @override
  String get collectionQueryGroupFigures => 'Figuren gruppieren';

  @override
  String get collectionQueryFigureGroupMatch =>
      'Figurengruppen-Übereinstimmung';

  @override
  String get collectionQueryOfTheseFigures => 'dieser Figuren';

  @override
  String get collectionQuerySingleFigure => 'Einzelne Figur';

  @override
  String get collectionQueryAddFigure => 'Figur hinzufügen';

  @override
  String get collectionQueryRemoveFigureGroup => 'Figurengruppe entfernen';

  @override
  String get collectionQueryMoveLabel => 'Bewegung';

  @override
  String get collectionQueryMoveHint => 'z. B. swing';

  @override
  String get collectionQuerySectionLabel => 'Abschnitt';

  @override
  String get collectionQueryAnySection => 'Beliebiger Abschnitt';

  @override
  String collectionQueryAnyParam(String param) {
    return 'Beliebig: $param';
  }

  @override
  String get collectionBatchLevelUnspecified => 'Nicht angegeben (löschen)';

  @override
  String get collectionBatchLevelConfirm => 'Festlegen';

  @override
  String get collectionBatchTagEmptyAdd =>
      'Noch keine Tags. Erstellen Sie unten einen.';

  @override
  String get collectionBatchTagEmptyRemove =>
      'Die ausgewählten Tänze haben keine Tags zum Entfernen.';

  @override
  String get collectionCreateTagLabel => 'Tag erstellen';

  @override
  String get collectionCreateTagButton => 'Tag erstellen';

  @override
  String get collectionCreateTagError =>
      'Tag konnte nicht erstellt werden. Versuchen Sie es erneut.';

  @override
  String get collectionBatchTagAddConfirm => 'Hinzufügen';

  @override
  String get collectionBatchTagRemoveConfirm => 'Entfernen';

  @override
  String collectionBatchRatingStars(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Sterne',
      one: '1 Stern',
    );
    return '$_temp0';
  }

  @override
  String get collectionBatchRatingUnrated => 'Ohne Bewertung (löschen)';

  @override
  String get collectionBatchRatingConfirm => 'Festlegen';

  @override
  String get collectionBatchTunesFieldLabel => 'Melodie hinzufügen';

  @override
  String get collectionBatchTunesAddButton => 'Melodie zur Liste hinzufügen';

  @override
  String get collectionBatchTunesEmpty =>
      'Melodienamen eingeben und zur Liste hinzufügen.';

  @override
  String collectionBatchTunesRemove(String tune) {
    return '$tune aus der Liste entfernen';
  }

  @override
  String get collectionBatchTunesConfirm => 'Hinzufügen';

  @override
  String get collectionBatchClearTunesConfirmTitle => 'Melodien löschen?';

  @override
  String get collectionBatchClearTunesConfirmBody =>
      'Dadurch werden alle Melodien von den ausgewählten Tänzen entfernt. Sie können dies danach rückgängig machen.';

  @override
  String get collectionBatchClearTunesConfirmButton => 'Melodien löschen';

  @override
  String get collectionBatchCustomFieldKeyLabel => 'Feld';

  @override
  String get collectionBatchCustomFieldClearOption => 'Dieses Feld löschen';

  @override
  String get collectionBatchCustomFieldEmpty =>
      'Noch keine benutzerdefinierten Felder definiert.';

  @override
  String get collectionBatchCustomFieldNumberInvalid =>
      'Geben Sie eine Zahl ein';

  @override
  String get collectionBatchCustomFieldConfirm => 'Anwenden';

  @override
  String get danceFiguresEmpty => 'Noch keine Figuren.';

  @override
  String danceFigureBeats(int beats) {
    String _temp0 = intl.Intl.pluralLogic(
      beats,
      locale: localeName,
      other: '$beats Takte',
      one: '1 Takt',
    );
    return '$_temp0';
  }

  @override
  String get danceFigureProgressionSemantic => 'Progression';

  @override
  String danceFigureNote(String note) {
    return 'Notiz: $note';
  }

  @override
  String get danceScreenTitle => 'Tanz';

  @override
  String get danceNotFound => 'Tanz nicht gefunden.';

  @override
  String get danceEditFab => 'Bearbeiten';

  @override
  String get danceDuplicateTooltip => 'Tanz duplizieren';

  @override
  String get danceDeleteTooltip => 'Tanz löschen';

  @override
  String get danceMoreActions => 'Weitere Aktionen';

  @override
  String get danceSectionFigures => 'Figuren';

  @override
  String get danceSectionCallingNotes => 'Calling-Notizen';

  @override
  String get danceSectionWalkthrough => 'Ablauf';

  @override
  String get danceSectionTunes => 'Melodien';

  @override
  String get danceSectionLinks => 'Links';

  @override
  String get danceMissingRelated => '(fehlender Tanz)';

  @override
  String get danceSectionPublishedSources => 'Veröffentlichte Quellen';

  @override
  String get danceSectionCustomFields => 'Benutzerdefinierte Felder';

  @override
  String get danceSectionCallingHistory => 'Calling-Verlauf';

  @override
  String get danceCallingHistoryEmpty => 'Noch in keinem Programm enthalten.';

  @override
  String get danceShowCanonicalTerms => 'Kanonische Begriffe anzeigen';

  @override
  String get danceCanonicalToggleLabel => 'Kanonisch';

  @override
  String danceProvenanceVia(String source) {
    return 'via $source';
  }

  @override
  String get danceProvenanceSourceManual => 'Manuelle Eingabe';

  @override
  String get danceProvenanceSourceJson => 'JSON-Import';

  @override
  String get danceLinkKindVideo => 'Video';

  @override
  String get danceLinkKindSource => 'Quellenlink';

  @override
  String get danceLinkKindLink => 'Link';

  @override
  String danceOpenLinkSemantic(String kind, String display) {
    return '$kind öffnen: $display';
  }

  @override
  String danceOpenProgramSemantic(String title, String details) {
    return 'Programm öffnen: $title, $details';
  }

  @override
  String danceHalfStatsFirstHalf(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count-mal in der ersten Hälfte aufgerufen',
      one: '1-mal in der ersten Hälfte aufgerufen',
    );
    return '$_temp0';
  }

  @override
  String danceHalfStatsSecondHalf(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count-mal in der zweiten Hälfte',
      one: '1-mal in der zweiten Hälfte',
    );
    return '$_temp0';
  }

  @override
  String danceHalfStatsOpened(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'die erste Hälfte $count-mal eröffnet',
      one: 'die erste Hälfte 1-mal eröffnet',
    );
    return '$_temp0';
  }

  @override
  String danceHalfStatsClosed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'den Abend $count-mal abgeschlossen (letzter Tanz der zweiten Hälfte)',
      one: 'den Abend 1-mal abgeschlossen (letzter Tanz der zweiten Hälfte)',
    );
    return '$_temp0';
  }

  @override
  String danceHalfStatsSemanticLabel(String description) {
    return 'Halbzeit-Aufschlüsselung: $description';
  }

  @override
  String get danceSourceUnknown => '(unbekannte Quelle)';

  @override
  String danceSourcePage(String page) {
    return 'S. $page';
  }

  @override
  String danceSourceNumber(String number) {
    return 'Nr. $number';
  }

  @override
  String danceOpenSourceLinkSemantic(String title) {
    return 'Quellenlink öffnen: $title';
  }

  @override
  String danceSourceSemanticPrefix(String title) {
    return 'Quelle: $title';
  }

  @override
  String danceOpenDanceCrossRefSemantic(String title) {
    return 'Tanz öffnen: $title';
  }

  @override
  String get commonAddToProgram => 'Zum Programm hinzufügen';

  @override
  String get programsEmptyTitle => 'Noch keine Programme';

  @override
  String get programsAddToProgramEmptyBody =>
      'Erstellen Sie ein Programm, um eine Setliste aufzubauen.';

  @override
  String get programsCreateWithDance =>
      'Neues Programm mit diesem Tanz erstellen';

  @override
  String programsAddDanceToProgramSemantic(
    String danceTitle,
    String programTitle,
    String details,
  ) {
    return '„$danceTitle“ zu $programTitle hinzufügen, $details';
  }

  @override
  String programsAddedToProgramSnack(String danceTitle, String programTitle) {
    return '„$danceTitle“ zu $programTitle hinzugefügt.';
  }

  @override
  String get programsNewProgram => 'Neues Programm';

  @override
  String programsCreatedProgramSnack(String programTitle, String danceTitle) {
    return '„$programTitle“ mit „$danceTitle“ erstellt.';
  }

  @override
  String get dancePerformTooltip => 'Diesen Tanz aufführen';

  @override
  String get commonSwitchDialectTooltip => 'Dialekt wechseln';

  @override
  String get programsStatusDraft => 'Entwurf';

  @override
  String get programsStatusFinalized => 'Abgeschlossen';

  @override
  String get programsStatusPerformed => 'Aufgeführt';

  @override
  String get programsNoLongerExists => 'Dieses Programm existiert nicht mehr.';

  @override
  String get programsFallbackTitle => 'Programm';

  @override
  String get programsUntitledDanceFallback => 'Tanz';

  @override
  String programsAddedDanceSnack(String title) {
    return '„$title“ hinzugefügt.';
  }

  @override
  String programsAddedDanceAnnounce(String title) {
    return '$title zum Programm hinzugefügt.';
  }

  @override
  String get programsAddedNoteAnnounce => 'Notiz zum Programm hinzugefügt.';

  @override
  String get programsAddedBreakAnnounce => 'Pause zum Programm hinzugefügt.';

  @override
  String get programsMarkedAllPerformed =>
      'Alle Tänze als aufgeführt markiert.';

  @override
  String programsSavedSnack(String title) {
    return '„$title“ gespeichert.';
  }

  @override
  String get programsSaveError => 'Programm konnte nicht gespeichert werden.';

  @override
  String programsDuplicatedSnack(String title) {
    return 'Als „$title“ dupliziert.';
  }

  @override
  String programsDeletedSnack(String title) {
    return '„$title“ gelöscht.';
  }

  @override
  String get programsDiscardTitle => 'Änderungen verwerfen?';

  @override
  String get programsDiscardBody =>
      'Sie haben nicht gespeicherte Änderungen an diesem Programm.';

  @override
  String get programsKeepEditing => 'Weiter bearbeiten';

  @override
  String get programsDiscard => 'Verwerfen';

  @override
  String get programsDraftTitle => 'Nicht gespeicherter Entwurf';

  @override
  String get programsDraftBody =>
      'Sie haben einen nicht gespeicherten Entwurf für dieses Programm. Möchten Sie ihn wiederherstellen?';

  @override
  String get programsDraftRestore => 'Wiederherstellen';

  @override
  String get programsDraftDiscard => 'Verwerfen';

  @override
  String get programsBuildProgram => 'Programm erstellen';

  @override
  String get programsBuildTab => 'Aufbau';

  @override
  String get programsMatrixTab => 'Matrix';

  @override
  String get programsPerformTooltip => 'Dieses Programm aufführen';

  @override
  String get programsMarkAllPerformedTooltip => 'Alle als aufgeführt markieren';

  @override
  String get programsSaveDirty => 'Speichern *';

  @override
  String get commonSave => 'Speichern';

  @override
  String get programsLoading => 'Programm wird geladen';

  @override
  String get programsLoadError => 'Programm konnte nicht geladen werden.';

  @override
  String get programsDeletedDanceFallback => '(gelöschter Tanz)';

  @override
  String get programsSlotsLabel => 'Slots';

  @override
  String get programsAddDanceButton => 'Tanz hinzufügen';

  @override
  String get programsAddNoteBreakButton => 'Notiz / Pause hinzufügen';

  @override
  String get programsInsertBreakButton => 'Pause einfügen';

  @override
  String get programsAddADanceSheetTitle => 'Tanz hinzufügen';

  @override
  String get commonClose => 'Schließen';

  @override
  String get programsNoDateSet => 'Kein Datum festgelegt';

  @override
  String get programsTitleLabel => 'Titel';

  @override
  String get programsTitleHint => 'z. B. Freitagsabend-Contra';

  @override
  String get programsTitleRequired => 'Ein Titel ist erforderlich.';

  @override
  String get programsEventDateLabel => 'Veranstaltungsdatum';

  @override
  String get programsSetDate => 'Datum festlegen';

  @override
  String get programsChangeDate => 'Ändern';

  @override
  String get programsClearEventDate => 'Veranstaltungsdatum löschen';

  @override
  String get programsVenueLabel => 'Veranstaltungsort';

  @override
  String get programsVenueHint => 'z. B. Gemeindesaal';

  @override
  String programsVenueLinkedHint(String venueName) {
    return 'Auch mit gespeichertem Veranstaltungsort verknüpft: $venueName. Aktivieren Sie wiederverwendbare Veranstaltungsorte in den Einstellungen, um ihn anzuzeigen oder zu ändern.';
  }

  @override
  String get programsVenueLinkedHintFallbackName =>
      'einem gespeicherten Veranstaltungsort';

  @override
  String programsVenueLegacyTextHint(String venueText) {
    return 'Zuvor eingegebener Veranstaltungsort: „$venueText“. Verknüpfen Sie unten einen gespeicherten Veranstaltungsort, um wiederverwendbare Details zu nutzen – Ihr eingetippter Veranstaltungsort bleibt erhalten.';
  }

  @override
  String get programsBandLabel => 'Band';

  @override
  String get programsBandHint => 'z. B. The Fiddleheads';

  @override
  String get programsCallerLabel => 'Caller';

  @override
  String get programsCallerHint => 'Haupt-Caller für die Veranstaltung';

  @override
  String get programsDancerLevelLabel => 'Tänzerniveau';

  @override
  String get programsDancerLevelHint => 'z. B. Alle willkommen, Erfahren';

  @override
  String get programsNotesLabel => 'Notizen';

  @override
  String get programsStatusFieldLabel => 'Status';

  @override
  String get programsHideAlternatesTitle =>
      'Alternativen in Setliste ausblenden';

  @override
  String get programsHideAlternatesSubtitle =>
      'Lässt ALT-Slots aus der Zusammenfassung, dem PDF und der exportierten Setliste aus. Der Builder zeigt weiterhin jeden Slot.';

  @override
  String programsWarningCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Warnungen',
      one: '1 Warnung',
    );
    return '$_temp0';
  }

  @override
  String get programsAddNoteBreakDialogTitle => 'Notiz oder Pause hinzufügen';

  @override
  String get programsFreeTextLabel => 'Text';

  @override
  String get programsFreeTextHint => 'z. B. Pause, Walzer, Ankündigung';

  @override
  String get commonAdd => 'Hinzufügen';

  @override
  String get programsTitle => 'Programme';

  @override
  String get programsSortTitle => 'Titel';

  @override
  String get programsSortRecentlyUpdated => 'Zuletzt aktualisiert';

  @override
  String get programsSortEventDate => 'Veranstaltungsdatum';

  @override
  String programsSortByTooltip(String label) {
    return 'Sortieren nach ($label)';
  }

  @override
  String get programsListLoadError => 'Programme konnten nicht geladen werden.';

  @override
  String get programsListEmptyBody =>
      'Erstellen Sie hier Setlisten für Ihre Veranstaltungen. Erstellen Sie Ihr erstes Programm, um loszulegen.';

  @override
  String programsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Programme',
      one: '1 Programm',
    );
    return '$_temp0';
  }

  @override
  String get programsSummaryTitle => 'Programm';

  @override
  String get programsEditProgram => 'Programm bearbeiten';

  @override
  String get programsSummaryUnavailable =>
      'Dieses Programm ist nicht mehr verfügbar.';

  @override
  String get programsPerformDisabledTooltip =>
      'Fügen Sie mindestens einen Slot hinzu, um dieses Programm aufzuführen';

  @override
  String programsSummaryBand(String band) {
    return 'Band: $band';
  }

  @override
  String programsSummaryCaller(String caller) {
    return 'Caller: $caller';
  }

  @override
  String programsSummaryLevel(String level) {
    return 'Niveau: $level';
  }

  @override
  String programsSetListHeader(int count) {
    return 'Setliste ($count)';
  }

  @override
  String get programsSummaryEmptySetList =>
      'Noch keine Slots – öffnen Sie den Builder, um Tänze hinzuzufügen.';

  @override
  String programsSummaryGuest(String caller) {
    return 'Gast: $caller';
  }

  @override
  String programsPlannedMinutes(int minutes) {
    return '$minutes Min.';
  }

  @override
  String get programsAltBadge => 'Alt';

  @override
  String get programsDanceUnavailable => 'Tanz nicht verfügbar';

  @override
  String programsSummaryNote(String note) {
    return 'Notiz: $note';
  }

  @override
  String programsSummaryAlternateSemantic(String title) {
    return 'Alternative: $title';
  }

  @override
  String get programsPerformed => 'Aufgeführt';

  @override
  String programsSlotCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Slots',
      one: '1 Slot',
    );
    return '$_temp0';
  }

  @override
  String get programsSlotNoteFallback => 'Notiz';

  @override
  String get programsSlotEditorEmpty =>
      'Noch keine Slots. Fügen Sie einen Tanz oder eine Notiz hinzu, um loszulegen.';

  @override
  String get programsSlotMoved => 'Slot verschoben.';

  @override
  String get programsSlotMovedUp => 'Slot nach oben verschoben.';

  @override
  String get programsSlotMovedDown => 'Slot nach unten verschoben.';

  @override
  String programsSlotCutBanner(String name) {
    return '„$name“ wurde ausgeschnitten – tippen Sie auf Einfügen, um ihn zu platzieren.';
  }

  @override
  String get programsPasteBeforeFirst => 'Vor dem ersten Slot einfügen';

  @override
  String programsPasteAfter(String title) {
    return 'Nach $title einfügen';
  }

  @override
  String get programsPasteHere => 'Hier einfügen';

  @override
  String get programsMarkedPrimary => 'Als primär markiert.';

  @override
  String get programsMarkedAlternate => 'Als Alternative markiert.';

  @override
  String get programsMarkedPerformed => 'Als aufgeführt markiert.';

  @override
  String get programsPerformedCleared => 'Aufführungsmarkierung entfernt.';

  @override
  String programsRemovedSlot(String name) {
    return '$name entfernt.';
  }

  @override
  String get programsAltOrdinal => 'ALT';

  @override
  String programsDragToReorder(String title) {
    return '$title zum Neuordnen ziehen';
  }

  @override
  String programsMoveSlotUp(String title) {
    return '$title nach oben verschieben';
  }

  @override
  String programsMoveSlotDown(String title) {
    return '$title nach unten verschieben';
  }

  @override
  String programsCutSlot(String title) {
    return '$title ausschneiden';
  }

  @override
  String programsMoreActionsForSlot(String title) {
    return 'Weitere Aktionen für $title';
  }

  @override
  String get programsEditSlotMenu => 'Slot bearbeiten';

  @override
  String get programsMakePrimaryMenu => 'Primär machen';

  @override
  String get programsMarkAlternateMenu => 'Als Alternative markieren';

  @override
  String get programsClearPerformedMenu => 'Aufführung zurücksetzen';

  @override
  String get programsMarkPerformedMenu => 'Als aufgeführt markieren';

  @override
  String get programsRemoveSlotMenu => 'Slot entfernen';

  @override
  String get programsSlotTextRequiredError =>
      'Geben Sie Text für diesen Slot ein.';

  @override
  String get programsWholeNumberError => 'Geben Sie eine ganze Zahl ≥ 0 ein.';

  @override
  String get programsEditDanceSlotTitle => 'Tanzslot bearbeiten';

  @override
  String get programsEditNoteTitle => 'Notiz bearbeiten';

  @override
  String get programsCallerNoteLabel => 'Caller-Notiz (optional)';

  @override
  String get programsCallerNoteHint => 'z. B. zuerst den Hey lehren';

  @override
  String get programsGuestCallerLabel => 'Gastcaller (optional)';

  @override
  String get programsPlannedMinutesLabel => 'Geplante Minuten (optional)';

  @override
  String get programsAlternateDanceTitle => 'Alternativer Tanz';

  @override
  String get programsAlternateDanceSubtitle =>
      'Wird eingerückt unter dem darüberliegenden Slot angezeigt.';

  @override
  String get commonDone => 'Fertig';

  @override
  String programsMatrixSemanticLabel(int danceCount, int moveCount) {
    String _temp0 = intl.Intl.pluralLogic(
      moveCount,
      locale: localeName,
      other: '$moveCount Bewegungen',
      one: '1 Bewegung',
    );
    return 'Programmiermatrix: $danceCount Tänze nach $_temp0';
  }

  @override
  String programsMatrixOmittedCaption(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Freitext-Slots',
      one: '1 Freitext-Slot',
    );
    return '$_temp0 (Pausen, Notizen) ausgelassen — die Matrix zeigt nur Tänze.';
  }

  @override
  String programsMatrixMoveHeaderSemantic(String label) {
    return 'Bewegung: $label';
  }

  @override
  String programsMatrixHideColumnSemantic(String label) {
    return 'Spalte „$label“ ausblenden';
  }

  @override
  String get programsMatrixShowAllColumnsSemantic => 'Alle Spalten anzeigen';

  @override
  String programsMatrixRowHeaderSemantic(
    String title,
    String alt,
    String half,
  ) {
    String _temp0 = intl.Intl.selectLogic(half, {
      'first': 'Alternativer Tanz: $title, erste Hälfte',
      'second': 'Alternativer Tanz: $title, zweite Hälfte',
      'other': 'Alternativer Tanz: $title',
    });
    String _temp1 = intl.Intl.selectLogic(half, {
      'first': 'Tanz: $title, erste Hälfte',
      'second': 'Tanz: $title, zweite Hälfte',
      'other': 'Tanz: $title',
    });
    String _temp2 = intl.Intl.selectLogic(alt, {
      'yes': '$_temp0',
      'other': '$_temp1',
    });
    return '$_temp2';
  }

  @override
  String programsMatrixHalfShort(String half) {
    String _temp0 = intl.Intl.selectLogic(half, {'first': '1.', 'other': '2.'});
    return '$_temp0';
  }

  @override
  String get programsMatrixFormationColumnHeader => 'Formation';

  @override
  String programsMatrixFormationSemantic(String dance, String label) {
    return '$dance, Formation: $label';
  }

  @override
  String programsMatrixCellSemantic(
    String dance,
    String move,
    String present,
    String collision,
    String debut,
    String first,
  ) {
    String _temp0 = intl.Intl.selectLogic(collision, {
      'yes': ', wiederholt sich in derselben Phrase wie ein Nachbartanz',
      'other': '',
    });
    String _temp1 = intl.Intl.selectLogic(debut, {
      'yes': ', hier eingeführt',
      'other': '',
    });
    String _temp2 = intl.Intl.selectLogic(first, {
      'yes': ', erste Figur des Tanzes',
      'other': '',
    });
    String _temp3 = intl.Intl.selectLogic(present, {
      'no': 'nicht vorhanden',
      'other': 'vorhanden$_temp0$_temp1$_temp2',
    });
    return '$dance, $move: $_temp3';
  }

  @override
  String programsMatrixChipQualifiedTitle(
    String title,
    String alt,
    String half,
  ) {
    String _temp0 = intl.Intl.selectLogic(half, {
      'first': '$title (Alternativer Tanz, erste Hälfte)',
      'second': '$title (Alternativer Tanz, zweite Hälfte)',
      'other': '$title (Alternativer Tanz)',
    });
    String _temp1 = intl.Intl.selectLogic(half, {
      'first': '$title (erste Hälfte)',
      'second': '$title (zweite Hälfte)',
      'other': '$title',
    });
    String _temp2 = intl.Intl.selectLogic(alt, {
      'yes': '$_temp0',
      'other': '$_temp1',
    });
    return '$_temp2';
  }

  @override
  String programsMatrixMoveUsedInSemantic(String label, int count, int total) {
    return 'Bewegung: $label, verwendet in $count von $total Tänzen';
  }

  @override
  String programsMatrixNOfTotal(int count, int total) {
    return '$count von $total';
  }

  @override
  String get programsMatrixNoComparableMoves =>
      'Keiner dieser Tänze hat noch strukturierte Figuren, daher gibt es keine Bewegungen zu vergleichen.';

  @override
  String get programsMatrixRepeatedMovesHeader => 'Wiederholte Bewegungen';

  @override
  String get programsMatrixRepeatedMovesSubtitle =>
      'Bewegungen, die in zwei oder mehr Tänzen vorkommen, häufigste zuerst.';

  @override
  String get programsMatrixNoRepeatsNote =>
      'Keine Bewegungen wiederholen sich über diese Tänze hinweg – jede Bewegung unten wird von einem einzigen Tanz verwendet.';

  @override
  String get programsMatrixUsedOnceHeader => 'Einmal verwendet';

  @override
  String get programsMatrixLegendIntroduced => 'Hier eingeführt';

  @override
  String get programsMatrixLegendFirstFigure => 'Erste Figur des Tanzes';

  @override
  String get programsMatrixLegendPresent => 'Vorhanden';

  @override
  String get programsMatrixLegendCollision => 'Gleiche Phrase wie Nachbartanz';

  @override
  String get programsMatrixEmptyTitle => 'Noch keine strukturierten Figuren';

  @override
  String get programsMatrixEmptyBody =>
      'Die Matrix wird automatisch gefüllt, wenn die Tänze des Programms strukturierte Figuren erhalten.';

  @override
  String get performTitle => 'Perform';

  @override
  String get performExitTooltip => 'Perform-Ansicht verlassen';

  @override
  String get performExitTitle => 'Perform verlassen?';

  @override
  String get performExitBody =>
      'Perform-Ansicht verlassen? Ihr Platz und die laufende Uhr werden gespeichert, sodass Sie dort weitermachen können, wo Sie aufgehört haben.';

  @override
  String get performExitCancel => 'Weitermachen';

  @override
  String get performExitConfirm => 'Verlassen';

  @override
  String get performTapTempo => 'Tempo klopfen';

  @override
  String performBpmReadout(int bpm) {
    return '$bpm BPM';
  }

  @override
  String get performTapToSetTempo => 'Zum Tempo-Setzen klopfen';

  @override
  String performBpmSemantic(int bpm) {
    return '$bpm Schläge pro Minute';
  }

  @override
  String get performNoTempoSemantic =>
      'Noch kein Tempo eingestellt. Tippen Sie auf das Ziel, um ein Tempo festzulegen.';

  @override
  String get performRecordBeatHint => 'Takt aufzeichnen';

  @override
  String get performTapRefineHint =>
      'Weiter klopfen zum Verfeinern · Zurücksetzen zum Neustart';

  @override
  String get performTapTwiceHint => 'Mindestens zweimal im Takt klopfen';

  @override
  String get performResetTempo => 'Zurücksetzen';

  @override
  String get performUntitledSlot => 'Unbenannter Slot';

  @override
  String performMarkedPerformedAnnounce(String label) {
    return '$label als aufgeführt markiert';
  }

  @override
  String get performClearedPerformedAnnounce =>
      'Aufführungsmarkierung entfernt';

  @override
  String performMovedToPosition(String label, int position) {
    return '$label auf Position $position verschoben';
  }

  @override
  String get performDanceFallback => 'Tanz';

  @override
  String performInsertedAnnounce(String title) {
    return '$title eingefügt';
  }

  @override
  String get performAddedNoteAnnounce => 'Notiz hinzugefügt';

  @override
  String get performInsertADance => 'Tanz einfügen';

  @override
  String get performAdjustProgram => 'Programm anpassen';

  @override
  String get performCurrentSlotSection => 'Aktueller Slot';

  @override
  String get performPerformedTapToClear =>
      'Aufgeführt – tippen zum Zurücksetzen';

  @override
  String get performReorderSection => 'Verbleibende Slots neu ordnen';

  @override
  String get performNoLaterSlots => 'Keine weiteren Slots zum Neuordnen.';

  @override
  String get performInsertDanceFromSearch => 'Tanz aus Suche einfügen';

  @override
  String get performAdHocNoteLabel => 'Ad-hoc-Notiz / Pause';

  @override
  String get performAdHocNoteHint => 'z. B. Walzer, Ankündigungen';

  @override
  String get performAddNote => 'Notiz hinzufügen';

  @override
  String performAlternatesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Alternativen',
      one: '1 Alternative',
    );
    return '$_temp0';
  }

  @override
  String performMoveLabelUp(String label) {
    return '„$label“ nach oben verschieben';
  }

  @override
  String performMoveLabelDown(String label) {
    return '„$label“ nach unten verschieben';
  }

  @override
  String performSlotPosition(int current, int total) {
    return 'Slot $current von $total';
  }

  @override
  String performShowingSlot(String label) {
    return '$label wird angezeigt';
  }

  @override
  String get performAdjustmentUndone => 'Anpassung rückgängig gemacht';

  @override
  String get performProgramAdjustedSnack => 'Programm angepasst.';

  @override
  String get performProgramAdjustedAnnounce => 'Programm angepasst';

  @override
  String get performNoSlots => 'Dieses Programm hat keine Slots.';

  @override
  String get performJumpToSlot => 'Zu Slot springen';

  @override
  String get performShowAlternate => 'Alternative anzeigen';

  @override
  String get performPreviousSlot => 'Vorheriger Slot';

  @override
  String get performNextSlot => 'Nächster Slot';

  @override
  String get performResumeTimers => 'Timer fortsetzen';

  @override
  String get performPauseTimers => 'Timer pausieren';

  @override
  String performTimingSemantic(
    String programTime,
    String slotTime,
    String hasPlanned,
    int planned,
    String over,
    String paused,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      planned,
      locale: localeName,
      other: '$planned Minuten',
      one: '1 Minute',
    );
    String _temp1 = intl.Intl.selectLogic(hasPlanned, {
      'yes': ', geplant $_temp0',
      'other': '',
    });
    String _temp2 = intl.Intl.selectLogic(over, {
      'yes': ', über geplante Zeit',
      'other': '',
    });
    String _temp3 = intl.Intl.selectLogic(paused, {
      'yes': ', pausiert',
      'other': '',
    });
    return 'Programmzeit $programTime, Slot-Zeit $slotTime$_temp1$_temp2$_temp3';
  }

  @override
  String performPlannedMin(int planned) {
    return 'geplant $planned Min.';
  }

  @override
  String get performOverSuffix => ' über';

  @override
  String get performCallingNotes => 'Calling-Notizen';

  @override
  String get performWalkthrough => 'Ablauf';

  @override
  String get performShowWalkthrough => 'Ablauf anzeigen';

  @override
  String get performWalkthroughEmpty => 'Kein Ablauf für diesen Tanz.';

  @override
  String get performNoFigures => 'Noch keine Figuren.';

  @override
  String get performDecreaseTextSize => 'Textgröße verringern';

  @override
  String get performIncreaseTextSize => 'Textgröße vergrößern';

  @override
  String get performShowCanonicalTerms => 'Kanonische Begriffe anzeigen';

  @override
  String get performMoreActions => 'Weitere Aktionen';

  @override
  String get performAutoSizeMenuLabel =>
      'Text automatisch an Bildschirm anpassen';

  @override
  String get performAutoSizeOnTooltip =>
      'Automatische Skalierung ein – tippen für manuelle Textgröße';

  @override
  String get performAutoSizeOffTooltip =>
      'Automatische Skalierung aus – tippen zum Anpassen an den Bildschirm';

  @override
  String get performStageThemeOnTooltip =>
      'Bühnen-Design ein – tippen für App-Design';

  @override
  String get performStageThemeOffTooltip =>
      'Bühnen-Design aus – tippen für dunkle Bühne';

  @override
  String get performProgression => 'Progression';

  @override
  String performFigureSemantic(
    String main,
    String importGap,
    String importGapText,
    String progression,
    int beats,
    String hasNote,
    String note,
  ) {
    String _temp0 = intl.Intl.selectLogic(importGap, {
      'yes': ', $importGapText',
      'other': '',
    });
    String _temp1 = intl.Intl.selectLogic(progression, {
      'yes': ', Progression',
      'other': '',
    });
    String _temp2 = intl.Intl.pluralLogic(
      beats,
      locale: localeName,
      other: '$beats Takte',
      one: '1 Takt',
    );
    String _temp3 = intl.Intl.selectLogic(hasNote, {
      'yes': ', Notiz: $note',
      'other': '',
    });
    return '$main$_temp0$_temp1, $_temp2$_temp3';
  }

  @override
  String get programsSelectTitle => 'Programm auswählen';

  @override
  String get programsSelectBody =>
      'Wählen Sie ein Programm aus der Liste oder erstellen Sie ein neues.';

  @override
  String get commonEdit => 'Bearbeiten';

  @override
  String get commonChange => 'Ändern';

  @override
  String get commonTryAgain => 'Erneut versuchen';

  @override
  String get exportTooltip => 'Exportieren';

  @override
  String get exportShareDanceText => 'Tanz teilen (Text)';

  @override
  String get exportCopyDance => 'Tanz kopieren';

  @override
  String get exportPrintPdf => 'PDF exportieren / drucken';

  @override
  String get exportDanceCopied => 'Tanz in die Zwischenablage kopiert.';

  @override
  String get exportShareDanceError => 'Dieser Tanz konnte nicht geteilt werden';

  @override
  String get exportDanceError => 'Dieser Tanz konnte nicht exportiert werden';

  @override
  String get exportShareSetListText => 'Setliste teilen (Text)';

  @override
  String get exportShareProgramBundle => 'Teilen (Programm + Tänze)';

  @override
  String get exportCopySetList => 'Setliste kopieren';

  @override
  String get exportSetListCopied => 'Setliste in die Zwischenablage kopiert.';

  @override
  String get exportShareSetListError =>
      'Diese Setliste konnte nicht geteilt werden';

  @override
  String get exportShareProgramError =>
      'Dieses Programm konnte nicht geteilt werden';

  @override
  String get exportSetListError =>
      'Diese Setliste konnte nicht exportiert werden';

  @override
  String get exportMatrixPdfTooltip =>
      'Matrix als PDF exportieren oder drucken';

  @override
  String get exportMatrixPdfFilename => 'Programmiermatrix';

  @override
  String get exportLabelFormation => 'Formation';

  @override
  String get exportLabelLevel => 'Niveau';

  @override
  String get exportLabelStatus => 'Status';

  @override
  String get exportLabelPhrase => 'Phrasierung';

  @override
  String get exportLabelFigures => 'Figuren';

  @override
  String get exportLabelCallingNotes => 'Calling-Notizen';

  @override
  String get exportLabelWalkthrough => 'Ablauf';

  @override
  String exportBeatsLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Takte',
      one: '1 Takt',
    );
    return '$_temp0';
  }

  @override
  String get exportLevelMixedOnly => 'Gemischt';

  @override
  String exportLevelWithMixed(String level) {
    return '$level (gemischt)';
  }

  @override
  String get exportLabelBand => 'Band';

  @override
  String get exportLabelCaller => 'Caller';

  @override
  String get exportLabelNotes => 'Notizen';

  @override
  String get exportLabelAlt => 'ALT';

  @override
  String get exportLabelGuest => 'Gast';

  @override
  String get exportLabelPerformed => 'aufgeführt';

  @override
  String get exportUnknownDanceLabel => 'Unbenannter Tanz';

  @override
  String exportMinutesLabel(int count) {
    return '$count Min.';
  }

  @override
  String get exportLabelVenue => 'Veranstaltungsort';

  @override
  String get exportLabelTime => 'Uhrzeit';

  @override
  String get exportLabelSchedule => 'Zeitplan';

  @override
  String get exportLabelPrice => 'Preis';

  @override
  String get exportLabelSponsor => 'Sponsor';

  @override
  String get exportMatrixDefaultTitle => 'Programmiermatrix';

  @override
  String get exportMatrixDanceColumn => 'Tanz';

  @override
  String get exportMatrixFormationColumn => 'Formation';

  @override
  String get exportMatrixEmptyState =>
      'Noch keine strukturierten Figuren — die Matrix wird automatisch gefüllt, wenn die Tänze des Programms strukturierte Figuren erhalten.';

  @override
  String get exportMatrixLegendDebut => 'Hier eingeführt';

  @override
  String get exportMatrixLegendFirst => 'Erste Figur des Tanzes';

  @override
  String get exportMatrixLegendPresent => 'Vorhanden';

  @override
  String get exportMatrixLegendCollision => 'Gleiche Phrase wie Nachbartanz';

  @override
  String exportMatrixOmittedCaption(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Freitext-Slots',
      one: '1 Freitext-Slot',
    );
    return '$_temp0 (Pausen, Notizen) ausgelassen — die Matrix zeigt nur Tänze.';
  }

  @override
  String get exportVenueContactTitle =>
      'Veranstaltungsort-Kontaktdaten in diesen Export einschließen?';

  @override
  String get exportVenueContactBody =>
      'Dies sind persönliche Kontaktdaten des Veranstaltungsortes. Sie werden aus diesem Export ausgelassen, es sei denn, Sie entscheiden sich, sie einzuschließen.';

  @override
  String get exportVenueContactConfirm => 'Weiter';

  @override
  String get exportVenueContact1Name => 'Kontaktperson 1 Name';

  @override
  String get exportVenueContact1Phone => 'Kontaktperson 1 Telefon';

  @override
  String get exportVenueContact1Email => 'Kontaktperson 1 E-Mail';

  @override
  String get exportVenueContact2Name => 'Kontaktperson 2 Name';

  @override
  String get exportVenueContact2Phone => 'Kontaktperson 2 Telefon';

  @override
  String get exportVenueContact2Email => 'Kontaktperson 2 E-Mail';

  @override
  String get onlineSearchToggleTitle => 'Online-Suche';

  @override
  String get onlineSearchToggleSubtitle =>
      'Online suchen und Tänze direkt importieren (Internetverbindung erforderlich). Lokale Filter gelten nicht.';

  @override
  String onlineSearchFieldLabel(String source) {
    return '$source durchsuchen';
  }

  @override
  String get onlineSearchFieldHint => 'Online-Tänze nach Titel suchen…';

  @override
  String onlineResultCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Online-Ergebnisse',
      one: '1 Online-Ergebnis',
    );
    return '$_temp0';
  }

  @override
  String onlineSearchHintByPhrase(String source) {
    return 'Geben Sie einen Titel ein oder fügen Sie Phrase-Figuren hinzu, um $source zu durchsuchen.';
  }

  @override
  String onlineSearchHintTitle(String source) {
    return 'Geben Sie einen Titel ein, um $source zu durchsuchen.';
  }

  @override
  String onlineNoResults(String source) {
    return 'Keine Tänze auf $source entsprechen Ihrer Suche.';
  }

  @override
  String onlineLoadError(String source) {
    return 'Dieser Tanz konnte nicht von $source geladen werden.';
  }

  @override
  String get onlineImportError => 'Dieser Tanz konnte nicht importiert werden.';

  @override
  String onlineSearchFailed(String source) {
    return '$source konnte nicht durchsucht werden. Bitte versuche es erneut.';
  }

  @override
  String onlineImportCreated(String title) {
    return '„$title“ importiert.';
  }

  @override
  String onlineImportAlreadyInCollection(String title) {
    return '„$title“ ist bereits in Ihrer Sammlung.';
  }

  @override
  String onlineImportVariationDialogBody(String existingTitle) {
    return 'This dance\'s title and caller match \"$existingTitle\", but its figures are different. How do you want to import it?';
  }

  @override
  String get onlineImportVariationDialogActionVariation =>
      'Import as a variation';

  @override
  String get onlineImportVariationDialogActionLink =>
      'Same dance (update existing)';

  @override
  String onlineImportVariationDialogLinkWarning(String existingTitle) {
    return 'Your version of \"$existingTitle\" will be replaced by the online record — including its figures, notes, tags, rating, and custom fields. It keeps its place in your programs and its calling history.';
  }

  @override
  String get onlineImportCrossSourceDuplicateDialogTitle =>
      'You already have this dance';

  @override
  String onlineImportCrossSourceDuplicateDialogBody(String existingTitle) {
    return 'Your collection already has \"$existingTitle\" from a different source. Both versions have the same sequence of moves.';
  }

  @override
  String get onlineImportCrossSourceDuplicateDialogActionDuplicate =>
      'Import a second copy';

  @override
  String get onlineAttributionCallersBox => 'Aus The Caller\'s Box (online)';

  @override
  String get onlineAttributionContraDb => 'Aus ContraDB (online)';

  @override
  String get importDances => 'Tänze importieren';

  @override
  String get importAction => 'Importieren';

  @override
  String get importProgramTooltip => 'Programm importieren';

  @override
  String get importFromTitleList => 'Aus Titelliste';

  @override
  String get importFromContraDb => 'Aus ContraDB';

  @override
  String get importProgramTitleLabel => 'Programmtitel';

  @override
  String get importProgramCreateError =>
      'Das importierte Programm konnte nicht gespeichert werden.';

  @override
  String importProgramCommitted(
    String title,
    int slots,
    int linked,
    int notes,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      slots,
      locale: localeName,
      other: '$slots Slots',
      one: '1 Slot',
    );
    String _temp1 = intl.Intl.pluralLogic(
      notes,
      locale: localeName,
      other: '$notes Notizen',
      one: '1 Notiz',
    );
    return '„$title“ importiert — $_temp0 ($linked verknüpft, $_temp1).';
  }

  @override
  String get importContraDbTitle => 'Aus ContraDB importieren';

  @override
  String get importContraDbPasteUrl => 'URL einfügen';

  @override
  String get importContraDbSearchByName => 'Nach Name suchen';

  @override
  String get importContraDbUrlLabel => 'ContraDB-Programm-URL';

  @override
  String get importContraDbUrlHint => 'z. B. https://contradb.com/programs/33';

  @override
  String get importContraDbFetching => 'Wird abgerufen…';

  @override
  String get importContraDbFetch => 'Programm abrufen';

  @override
  String get importContraDbSearchLabel => 'ContraDB-Programme suchen';

  @override
  String get importContraDbSearchHint => 'Teil eines Programmnamens eingeben';

  @override
  String get importContraDbListError =>
      'Die ContraDB-Programmliste konnte nicht geladen werden.';

  @override
  String get importContraDbSearchPrompt =>
      'Geben Sie einen Teil eines Programmnamens ein, um ContraDB zu durchsuchen.';

  @override
  String get importContraDbNoMatches => 'Keine passenden Programme.';

  @override
  String get importContraDbMarkerImported => 'Imported';

  @override
  String importContraDbMarkerImportedTooltip(String date) {
    return 'Imported on $date';
  }

  @override
  String get importContraDbMarkerImportedTooltipNoDate =>
      'Already imported from ContraDB';

  @override
  String get importContraDbMarkerPossible => 'Possibly imported';

  @override
  String get importContraDbMarkerPossibleTooltip =>
      'A program with this title already exists';

  @override
  String importContraDbFetchError(String error) {
    return 'Dieses Programm konnte nicht abgerufen werden.\n$error';
  }

  @override
  String get importContraDbFetchGenericError =>
      'Dieses Programm konnte nicht abgerufen werden.';

  @override
  String get importContraDbPastePrompt =>
      'Fügen Sie oben eine ContraDB-Programm-URL ein und tippen Sie auf „Programm abrufen“.';

  @override
  String get importContraDbEmptyProgram =>
      'Auf dieser Programmseite wurden keine Tänze oder Notizen gefunden.';

  @override
  String get importContraDbResolveError =>
      'Das ContraDB-Programm konnte nicht importiert werden.';

  @override
  String importContraDbActivityCount(int activities, int dances, int notes) {
    String _temp0 = intl.Intl.pluralLogic(
      activities,
      locale: localeName,
      other: '$activities Aktivitäten',
      one: '1 Aktivität',
    );
    String _temp1 = intl.Intl.pluralLogic(
      dances,
      locale: localeName,
      other: '$dances Tänze',
      one: '1 Tanz',
    );
    String _temp2 = intl.Intl.pluralLogic(
      notes,
      locale: localeName,
      other: '$notes Notizen',
      one: '1 Notiz',
    );
    return '$_temp0 ($_temp1, $_temp2)';
  }

  @override
  String get importContraDbDanceFallback => 'ContraDB-Tanz';

  @override
  String get importEventDateNone => 'Kein Datum festgelegt';

  @override
  String get importEventDateLabel => 'Veranstaltungsdatum';

  @override
  String get importEventDateSet => 'Datum festlegen';

  @override
  String get importEventDateClear => 'Veranstaltungsdatum löschen';

  @override
  String get importEventDateDetected =>
      'Datum aus Titel erkannt – vor dem Import prüfen.';

  @override
  String get importTitleListTitle => 'Aus Titelliste importieren';

  @override
  String get importCollectionLoadError =>
      'Sammlung konnte nicht geladen werden.';

  @override
  String get importTitleListDancesLabel => 'Tanztitel (einer pro Zeile)';

  @override
  String get importTitleListDancesHint =>
      'Fügen Sie einen Tanztitel pro Zeile ein.\nNicht erkannte Zeilen werden als Notizen gespeichert.';

  @override
  String get importTitleListEmptyHint =>
      'Fügen Sie oben eine Titelliste ein, um eine Vorschau des Programms zu sehen.';

  @override
  String get importResolving => 'Wird gesucht…';

  @override
  String get importResolveOnline => 'Nicht zugeordnete online auflösen';

  @override
  String get importPlaintextImportedOnline => 'Aus Caller\'s Box importiert';

  @override
  String get importPlaintextLinked => 'Mit Tanz verknüpft';

  @override
  String get importPlaintextAmbiguous =>
      'Mehrere Übereinstimmungen – als Notiz hinzugefügt';

  @override
  String get importPlaintextUnmatched =>
      'Keine Übereinstimmung – als Notiz hinzugefügt';

  @override
  String get importPlaintextSearchError =>
      'The Caller\'s Box konnte nicht durchsucht werden.';

  @override
  String importPlaintextSlotCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Slots',
      one: '1 Slot',
    );
    return '$_temp0';
  }

  @override
  String importPlaintextResolvedNone(int remaining) {
    String _temp0 = intl.Intl.pluralLogic(
      remaining,
      locale: localeName,
      other: '$remaining Titel als Notizen gespeichert',
      one: '$remaining Titel als Notiz gespeichert',
    );
    return 'Keine zuverlässigen Übereinstimmungen in The Caller\'s Box gefunden — $_temp0.';
  }

  @override
  String importPlaintextResolvedLinked(int linked, int remaining) {
    String _temp0 = intl.Intl.pluralLogic(
      linked,
      locale: localeName,
      other: '$linked Titel',
      one: '$linked Titel',
    );
    String _temp1 = intl.Intl.pluralLogic(
      remaining,
      locale: localeName,
      other: '; $remaining noch als Notizen.',
      one: '; $remaining noch als Notiz.',
      zero: '.',
    );
    return '$_temp0 aus The Caller\'s Box verknüpft$_temp1';
  }

  @override
  String get importReviewClose => 'Import schließen';

  @override
  String get importReviewSourceLabel => 'Quelle';

  @override
  String importReviewFromSource(String source) {
    return 'Aus $source importieren.';
  }

  @override
  String importReviewDancesFromSource(String source) {
    return 'Tänze aus $source importieren.';
  }

  @override
  String get importSourceLabelGenericJson =>
      'einer Caller\'s Compendium JSON-Datei';

  @override
  String get importSourceLabelCallersBox => 'The Caller\'s Box';

  @override
  String get importSourceLabelContraDb => 'ContraDB';

  @override
  String get importSourceLabelCallersCompanionUsr =>
      'einer Caller\'s Companion .USR-Datei';

  @override
  String get importSourceLabelTitleList => 'a list of titles';

  @override
  String get importReviewTitleListSubtitle =>
      'Paste one dance title per line. Every title is listed for review — the ones you already have are shown but never re-imported, and nothing is added to your collection until you confirm.';

  @override
  String get importReviewPasteTitles => 'Dance titles, one per line';

  @override
  String importReviewTitleListCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count titles',
      one: '1 title',
      zero: 'No titles yet',
    );
    return '$_temp0';
  }

  @override
  String importReviewTitleListDuplicates(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count repeated titles ignored',
      one: '1 repeated title ignored',
    );
    return '$_temp0';
  }

  @override
  String importTitleListTooManyTitles(int count, int max) {
    return 'That\'s $count titles. Import up to $max at a time.';
  }

  @override
  String importTitleListTextTooLong(int max) {
    return 'That paste is too long to be a list of titles. Import up to $max titles at a time.';
  }

  @override
  String importReviewTitleListProgress(int done, int total) {
    return 'Searching $done of $total…';
  }

  @override
  String importReviewTitleListPasted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pasted titles',
      one: '1 pasted title',
    );
    return '$_temp0';
  }

  @override
  String importReviewTitleListToImport(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count to import',
      one: '1 to import',
    );
    return '$_temp0';
  }

  @override
  String importReviewTitleListOwned(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count already in your collection',
      one: '1 already in your collection',
    );
    return '$_temp0';
  }

  @override
  String importReviewTitleListNotFound(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count not found',
      one: '1 not found',
    );
    return '$_temp0';
  }

  @override
  String importReviewTitleListOwnedBy(String authors) {
    return 'You already have this, by $authors.';
  }

  @override
  String get importReviewTitleListOwnedUnknownAuthor =>
      'You already have this dance.';

  @override
  String importReviewTitleListOwnedMany(int count) {
    return 'You have $count dances with this title.';
  }

  @override
  String get importTitleListReasonNoResults =>
      'The Caller\'s Box has no dance by this name.';

  @override
  String get importTitleListReasonNoExactMatch =>
      'Only near matches — nothing titled exactly this.';

  @override
  String get importTitleListReasonMultipleExactMatches =>
      'Several dances share this exact title, so it isn\'t clear which you meant.';

  @override
  String get importTitleListReasonFetchError =>
      'Couldn\'t reach The Caller\'s Box for this title.';

  @override
  String get importTitleListReasonLineTooLong =>
      'Too long to be a dance title, so it wasn\'t searched.';

  @override
  String get importReviewTitleListNothingToImport =>
      'Nothing here to import — every title is either already in your collection or couldn\'t be found.';

  @override
  String importReviewSummaryAlreadyOwned(int count) {
    return 'Already in your collection: $count';
  }

  @override
  String importReviewSummaryNotFound(int count) {
    return 'Not found: $count';
  }

  @override
  String get importErrorFileTooLarge =>
      'Diese Datei ist zu groß zum Importieren.';

  @override
  String get archiveIntakeRejectedTooLarge =>
      'Diese Datei ist zu groß zum Importieren.';

  @override
  String get archiveIntakeRejectedUnreadable =>
      'Die geteilte Datei konnte nicht gelesen werden.';

  @override
  String get archiveIntakeRejectedEmpty => 'Diese Datei ist leer.';

  @override
  String get archiveIntakeRejectedNotArchive =>
      'Diese Datei ist keine Freigabedatei von Caller’s Compendium.';

  @override
  String get archiveIntakeRejectedNewerVersion =>
      'Diese Datei wurde mit einer neueren Version der App erstellt. Bitte aktualisiere die App, um sie zu importieren.';

  @override
  String get archiveIntakeRejectedNoContent =>
      'Diese Datei enthielt keine Tänze oder Programme.';

  @override
  String get importErrorInsecureScheme =>
      'Importe müssen eine sichere https://-URL verwenden.';

  @override
  String get importErrorBlockedHost =>
      'Diese URL verweist auf einen Netzwerkspeicherort, von dem nicht importiert werden kann.';

  @override
  String get importErrorInvalidUrl =>
      'Das sieht nicht wie eine gültige http(s)-URL aus.';

  @override
  String get importErrorTooManyRedirects =>
      'Diese URL hat zu viele Umleitungen durchgeführt.';

  @override
  String get importErrorResponseTooLarge =>
      'Diese Antwort war zu groß zum Importieren.';

  @override
  String get importErrorEmptyUrl => 'Geben Sie eine URL zum Importieren ein.';

  @override
  String importErrorTimeout(int seconds) {
    return 'Die Anfrage hat nach $seconds s das Zeitlimit überschritten. Überprüfen Sie die URL und Ihre Verbindung, dann versuchen Sie es erneut.';
  }

  @override
  String get importErrorUnreachable =>
      'Diese URL konnte nicht erreicht werden. Überprüfen Sie die URL und Ihre Verbindung, dann versuchen Sie es erneut.';

  @override
  String importErrorHttpStatus(int status) {
    return 'Der Server antwortete mit HTTP $status.';
  }

  @override
  String get importErrorEmptyResponse =>
      'Die URL gab eine leere Antwort zurück.';

  @override
  String get importErrorCallersBoxEmptyInput =>
      'Geben Sie eine Caller\'s Box-Tanz-URL oder -ID zum Importieren ein.';

  @override
  String get importErrorCallersBoxInvalidUrl =>
      'Das sieht nicht wie eine Caller\'s Box-Tanz-URL oder eine numerische ID aus.';

  @override
  String get importErrorCallersBoxMissingId =>
      'Diese Caller\'s Box-URL fehlt eine Tanz-ID (…dance.php?id=N).';

  @override
  String get importErrorCallersBoxUnsupportedHost =>
      'Dieser Link ist kein unterstützter Caller\'s-Box-Link. Füge einen Link von ibiblio.org oder www.ibiblio.org unter /contradance/thecallersbox/ ein oder gib die numerische ID des Tanzes ein.';

  @override
  String get importErrorCallersBoxEmptySearch =>
      'Geben Sie einen Titel oder Phrase-Figuren ein, um The Caller\'s Box zu durchsuchen.';

  @override
  String importErrorSearchTimeout(int seconds) {
    return 'Die Suche hat nach $seconds s das Zeitlimit überschritten. Überprüfen Sie Ihre Verbindung, dann versuchen Sie es erneut.';
  }

  @override
  String get importErrorCallersBoxUnreachable =>
      'The Caller\'s Box konnte nicht erreicht werden. Überprüfen Sie Ihre Verbindung, dann versuchen Sie es erneut.';

  @override
  String importErrorCallersBoxHttpStatus(int status) {
    return 'The Caller\'s Box antwortete mit HTTP $status.';
  }

  @override
  String get importErrorCallersBoxEmptyPage =>
      'The Caller\'s Box gab eine leere Seite zurück.';

  @override
  String get importErrorCallersBoxNoDance =>
      'The Caller\'s Box hat keinen importierbaren Tanz zurückgegeben.';

  @override
  String get importErrorCallersBoxImportFailed =>
      'Der Caller\'s Box-Tanz konnte nicht importiert werden.';

  @override
  String get importErrorContraDbEmptyTitle =>
      'Geben Sie einen Titel ein, um ContraDB zu durchsuchen.';

  @override
  String get importErrorContraDbEmptyDanceInput =>
      'Geben Sie eine ContraDB-Tanz-URL oder -ID zum Importieren ein.';

  @override
  String get importErrorContraDbInvalidDanceUrl =>
      'Das sieht nicht wie eine ContraDB-Tanz-URL oder eine numerische ID aus.';

  @override
  String get importErrorContraDbMissingDanceId =>
      'Diese ContraDB-URL fehlt eine Tanz-ID (…/dances/N).';

  @override
  String get importErrorContraDbEmptyProgramInput =>
      'Geben Sie eine ContraDB-Programm-URL oder -ID zum Importieren ein.';

  @override
  String get importErrorContraDbInvalidProgramUrl =>
      'Das sieht nicht wie eine ContraDB-Programm-URL oder eine numerische ID aus.';

  @override
  String get importErrorContraDbMissingProgramId =>
      'Diese ContraDB-URL fehlt eine Programm-ID (…/programs/N).';

  @override
  String get importErrorContraDbInvalidProgramLink =>
      'Das sieht nicht wie ein ContraDB-Programm-Link aus.';

  @override
  String get importErrorContraDbUnsupportedHost =>
      'Dieser Link stammt nicht von einem unterstützten ContraDB-Host. Füge einen Link von contradb.com oder www.contradb.com ein oder gib die numerische ID des Tanzes oder Programms ein.';

  @override
  String get importErrorContraDbUnreachable =>
      'ContraDB konnte nicht erreicht werden. Überprüfen Sie Ihre Verbindung, dann versuchen Sie es erneut.';

  @override
  String importErrorContraDbHttpStatus(int status) {
    return 'ContraDB antwortete mit HTTP $status.';
  }

  @override
  String get importErrorContraDbEmptyResponse =>
      'ContraDB gab eine leere Antwort zurück.';

  @override
  String get importErrorContraDbNoDance =>
      'ContraDB hat keinen importierbaren Tanz zurückgegeben.';

  @override
  String get importErrorContraDbImportFailed =>
      'Der ContraDB-Tanz konnte nicht importiert werden.';

  @override
  String get importIssueGeneric =>
      'Dieses Element wurde mit einem Hinweis importiert.';

  @override
  String get importIssueProgramEmptySlot =>
      'Ein leerer Programmplatz wurde übersprungen.';

  @override
  String get importIssueProgramUnresolvedDance =>
      'Ein Programm verwies auf einen Tanz, der nicht importiert wurde; der Platz wurde als Text-Platzhalter beibehalten.';

  @override
  String get importIssueProgramUnresolvedVenue =>
      'Ein Programm verwies auf einen Veranstaltungsort, der nicht importiert wurde; das Programm wurde ohne Veranstaltungsort-Verknüpfung beibehalten.';

  @override
  String get importIssueArchiveReadError =>
      'Ein Eintrag in der geteilten Datei konnte nicht gelesen werden und wurde übersprungen.';

  @override
  String get importIssueArchiveReadWarning =>
      'Beim Dekodieren der geteilten Datei wurde eine Warnung gemeldet.';

  @override
  String get importIssueDirectionUnmapped =>
      'Eine Becket-Richtung wurde nicht erkannt; Standard ist im Uhrzeigersinn.';

  @override
  String get importIssueFormationUnclassified =>
      'Eine Formation konnte nicht erkannt werden; als Detail bei „other“ beibehalten.';

  @override
  String get importIssuePhraseStructureUnreadable =>
      'Eine Phrasierungsstruktur konnte nicht gelesen werden; es wurde eine Standardstruktur verwendet.';

  @override
  String get importIssueProgressionUnmapped =>
      'Eine Progression wurde nicht erkannt; als „other“ erfasst.';

  @override
  String get importIssueMetadataOnlyStub =>
      'Dieser Tanz ist nur als Metadaten verfügbar (keine Figuren); als Kurzeintrag importiert.';

  @override
  String importIssueDateAssumedMdy(String field) {
    return 'Ein mehrdeutiges Datum ($field) wurde als Monat/Tag (US-Reihenfolge) gelesen; prüfe es, falls die Quelle die Tag-zuerst-Reihenfolge verwendet hat.';
  }

  @override
  String importIssueDateReducedPrecision(int year, String field) {
    return 'Aus dem Datum ($field) konnte nur das Jahr $year gelesen werden; es war kein Monat oder Tag vorhanden.';
  }

  @override
  String get importIssueMissingTitle =>
      'Der Tanz hatte keinen Titel; ein Platzhaltertitel wurde verwendet. Bearbeite ihn vor dem Übernehmen.';

  @override
  String get importIssueProgramUnparsedDate =>
      'Ein Veranstaltungsdatum konnte nicht gelesen werden; nicht gesetzt.';

  @override
  String get importIssueRatingOutOfRange =>
      'Eine Bewertung lag außerhalb der Skala 1–5; nicht bewertet.';

  @override
  String get importIssueUnmappedFormation =>
      'Eine Formation wurde nicht erkannt; als Freitext-Detail beibehalten.';

  @override
  String get importIssueUnmappedLevel =>
      'Ein Niveau wurde nicht erkannt; nicht angegeben.';

  @override
  String get importIssueUnmappedProgression =>
      'Eine Progression wurde nicht erkannt; Standard ist einfach.';

  @override
  String get importIssueUnmappedType =>
      'Ein Tanztyp wurde nicht erkannt; als Contra importiert und in den Notizen erhalten.';

  @override
  String importIssueUnparsedDate(String field) {
    return 'Das Datum ($field) konnte nicht gelesen werden; nicht gesetzt.';
  }

  @override
  String get importIssueUnparsedRating =>
      'Eine Bewertung konnte nicht gelesen werden; nicht bewertet.';

  @override
  String get importIssueFiguresUnreadable =>
      'Die Figuren konnten nicht gelesen werden; es wurden keine Figuren importiert.';

  @override
  String get importIssueBeatsUnreadable =>
      'Eine Taktzahl konnte nicht gelesen werden; 0 verwendet.';

  @override
  String get importIssueNoFiguresTable =>
      'Die Seite hatte keine Figuren; als reiner Metadaten-Kurzeintrag importiert.';

  @override
  String get importIssueMoveFallback =>
      'Eine Figur konnte keiner bekannten Bewegung zugeordnet werden; als benutzerdefiniert importiert.';

  @override
  String importIssueMoveFallbackAt(int position) {
    return 'Figur $position konnte keiner bekannten Bewegung zugeordnet werden; als benutzerdefiniert importiert.';
  }

  @override
  String get importIssueParamUnmapped =>
      'Ein Figurenparameter konnte nicht zugeordnet werden; ein Taxonomie-Standard wurde verwendet.';

  @override
  String importIssueParamValueUnmapped(String param) {
    return 'Der Parameter $param konnte nicht konvertiert werden; ein Taxonomie-Standard wurde verwendet.';
  }

  @override
  String importIssueParamCountUnmapped(int provided, int mapped) {
    return 'Eine Figur hatte $provided Parameterwerte, aber nur $mapped sind zugeordnet; die überzähligen wurden ignoriert.';
  }

  @override
  String get importIssueRelatedDanceUnresolved =>
      'Eine Verknüpfung zu einem verwandten Tanz verwies auf einen Tanz, der nicht importiert wurde; die Verknüpfung wurde übersprungen.';

  @override
  String get importDateFieldComposed => 'komponiert';

  @override
  String get importDateFieldRevised => 'überarbeitet';

  @override
  String get importRecordErrorDiscover =>
      'Dieser Datensatz konnte nicht gefunden werden.';

  @override
  String get importRecordErrorFetch =>
      'Dieser Datensatz konnte nicht abgerufen werden.';

  @override
  String get importRecordErrorParse =>
      'Dieser Datensatz konnte nicht gelesen werden.';

  @override
  String get importRecordErrorDedupe =>
      'Dieser Datensatz konnte nicht verarbeitet werden.';

  @override
  String get importRecordErrorCommit =>
      'Dieser Datensatz konnte nicht gespeichert werden.';

  @override
  String get importReviewUsrSubtitle =>
      'Wählen Sie die Caller\'s Companion .USR-Datei aus, um deren Tänze und Programmverlauf zu migrieren. Ihrer Sammlung wird nichts hinzugefügt, bis Sie überprüfen und bestätigen.';

  @override
  String get importReviewChooseUsr => '.USR-Datei auswählen…';

  @override
  String importReviewFileReady(int bytes) {
    return 'Datei bereit ($bytes Bytes).';
  }

  @override
  String get importReviewGenericSubtitle =>
      'Wählen Sie eine Datei aus, fügen Sie deren Inhalt ein oder rufen Sie sie von einer URL ab. Ihrer Sammlung wird nichts hinzugefügt, bis Sie überprüfen und bestätigen.';

  @override
  String get importReviewChooseFile => 'Datei auswählen…';

  @override
  String get importReviewUrlLabel => 'Tanz-URL oder -ID';

  @override
  String get importReviewUrlLabelGeneric => 'Von URL importieren';

  @override
  String get importReviewUrlHint =>
      'https://www.ibiblio.org/contradance/thecallersbox/dance.php?id=1  · oder · 1';

  @override
  String get importReviewUrlHintGeneric => 'https://…';

  @override
  String get importReviewFetch => 'Abrufen';

  @override
  String get importReviewPasteJson => 'Oder JSON einfügen';

  @override
  String get importReviewReviewButton => 'Import prüfen';

  @override
  String importReviewWillImport(int importable, int total) {
    return '$importable von $total werden importiert';
  }

  @override
  String get importReviewCouldNotRead => 'Import konnte nicht gelesen werden';

  @override
  String get importReviewNoDancesTitle => 'Keine Tänze gefunden';

  @override
  String get importReviewNoDancesBody =>
      'Die Datei enthielt keine Tänze zum Importieren.';

  @override
  String get importReviewTryAnother => 'Andere Datei versuchen';

  @override
  String get importReviewImported => 'Importiert';

  @override
  String importReviewStructured(int structured, int total) {
    return '$structured/$total strukturiert';
  }

  @override
  String get importReviewCustom => 'Benutzerdefiniert';

  @override
  String get importReviewOptionNewDance => 'Neuer Tanz';

  @override
  String get importReviewOptionSkip => 'Überspringen';

  @override
  String importReviewOptionReimport(String title) {
    return 'Auf „$title“ neu importieren';
  }

  @override
  String get importReviewOptionDuplicate =>
      'Als neuen (doppelten) Tanz importieren';

  @override
  String get importReviewPossibleMatch =>
      'Mögliche Übereinstimmung — wählen Sie, wie importiert werden soll:';

  @override
  String importReviewOptionLink(String title, int percent) {
    return 'Mit „$title“ verknüpfen ($percent % Übereinstimmung)';
  }

  @override
  String importReviewOverwriteWarning(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count vorhandene Tänze werden überschrieben',
      one: '1 vorhandener Tanz wird überschrieben',
    );
    return '$_temp0';
  }

  @override
  String importReviewWarningPrefix(String message) {
    return 'Warnung: $message';
  }

  @override
  String get importReviewComplete => 'Import abgeschlossen';

  @override
  String sharedImportSoftCapWarning(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Dieser Import enthält $count Elemente — mehr als für eine normale Freigabe erwartet.',
      one:
          'Dieser Import enthält 1 Element — mehr als für eine normale Freigabe erwartet.',
    );
    return '$_temp0';
  }

  @override
  String sharedImportComplete(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Elemente importiert.',
      one: '1 Element importiert.',
      zero: 'Import abgeschlossen.',
    );
    return '$_temp0';
  }

  @override
  String sharedImportProgramsOnly(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Diese Freigabe enthält $count Programme und keine Tänze.',
      one: 'Diese Freigabe enthält 1 Programm und keine Tänze.',
    );
    return '$_temp0';
  }

  @override
  String importReviewSummaryCreated(int count) {
    return 'Erstellt: $count';
  }

  @override
  String importReviewSummaryReimported(int count) {
    return 'Neu importiert: $count';
  }

  @override
  String importReviewSummaryLinked(int count) {
    return 'Verknüpft: $count';
  }

  @override
  String importReviewSummaryDuplicated(int count) {
    return 'Dupliziert: $count';
  }

  @override
  String importReviewSummaryVariation(int count) {
    return 'Als Variante importiert: $count';
  }

  @override
  String importReviewSummarySkipped(int count) {
    return 'Übersprungen: $count';
  }

  @override
  String importReviewSummaryPrograms(int count) {
    return 'Programme: $count';
  }

  @override
  String importReviewProgramsUpdated(int count) {
    return '$count aktualisiert (neu importiert)';
  }

  @override
  String importReviewProgramNotes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Programm-Notizen:',
      one: '$count Programm-Notiz:',
    );
    return '$_temp0';
  }

  @override
  String importReviewRecordsFailed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Einträge konnten nicht importiert werden:',
      one: '$count Eintrag konnte nicht importiert werden:',
    );
    return '$_temp0';
  }

  @override
  String importReviewBatchErrors(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count Einträge konnten nicht gelesen werden (der Rest kann noch importiert werden):',
      one:
          '$count Eintrag konnte nicht gelesen werden (der Rest kann noch importiert werden):',
    );
    return '$_temp0';
  }

  @override
  String get importReviewUntitledProgram => 'Unbenanntes Programm';

  @override
  String get importReviewUndoWithPrograms =>
      'Rückgängig (entfernt die importierten Tänze und Programme)';

  @override
  String get importReviewUndone => 'Import rückgängig gemacht.';

  @override
  String get importReviewEditError =>
      'Dieser Tanz konnte nicht zum Bearbeiten importiert werden.';

  @override
  String get importReviewImportError =>
      'Der Import konnte nicht abgeschlossen werden.';

  @override
  String importReviewVariationTitle(String title) {
    return 'Variante von „$title“?';
  }

  @override
  String importReviewVariationBody(String title) {
    return 'Titel und Caller dieses Tanzes stimmen mit „$title“ überein, aber die Figuren unterscheiden sich. Sieh dir an, wie sie sich unterscheiden, und entscheide dann, wie er importiert werden soll.';
  }

  @override
  String importReviewOptionVariation(String title) {
    return 'Als Variante von „$title“ importieren';
  }

  @override
  String importReviewOptionSameDance(String title) {
    return 'Derselbe Tanz wie „$title“ (verknüpfen/aktualisieren)';
  }

  @override
  String importReviewOptionLinkBack(String title) {
    return 'Auch mit „$title“ als verwandten Tanz zurückverknüpfen';
  }

  @override
  String get importReviewVariationAdded => 'Hinzugefügt';

  @override
  String get importReviewVariationRemoved => 'Entfernt';

  @override
  String importReviewVariationMoreDifferences(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count weitere Unterschiede nicht angezeigt',
      one: '1 weiterer Unterschied nicht angezeigt',
    );
    return '$_temp0';
  }

  @override
  String get danceEditorDetailsSection => 'Details';

  @override
  String get danceEditorTitleRequiredLabel => 'Titel *';

  @override
  String get danceEditorTitleRequired => 'Titel ist erforderlich';

  @override
  String get danceEditorAuthorsLabel => 'Autoren';

  @override
  String get danceEditorFormationLabel => 'Formation';

  @override
  String get danceEditorFormationDetailLabel => 'Formationsdetail (optional)';

  @override
  String get danceEditorPhraseStructureLabel => 'Phrasierungsstruktur';

  @override
  String get danceEditorPhraseStructureHint =>
      'Leer = Standard A1 A2 B1 B2; z. B. 6*8*2';

  @override
  String get danceEditorFiguresSection => 'Figuren';

  @override
  String get danceEditorFiguresHelp =>
      'Geben Sie eine Bewegung ein (z. B. „sw“ → swing) und drücken Sie Eingabe, um sie mit Standardparametern hinzuzufügen; nicht erkannter Text wird eine benutzerdefinierte Figur.';

  @override
  String get danceEditorNotesSection => 'Notizen';

  @override
  String get danceEditorCallingNotesLabel => 'Calling-Notizen';

  @override
  String get danceEditorHookLabel => 'Hook';

  @override
  String get danceEditorHookHint => 'Einzeiliges „Warum diesen Tanz aufrufen“';

  @override
  String get danceEditorWalkthroughLabel => 'Ablauf';

  @override
  String get danceEditorWalkthroughHelper =>
      'Schritt-für-Schritt-Beschreibung des Tanzes und seiner Übergänge';

  @override
  String get danceEditorAddWalkthroughStep => 'Ablaufschritt hinzufügen';

  @override
  String get danceEditorWalkthroughStepLabel => 'Ablaufschritt (optional)';

  @override
  String get danceEditorWalkthroughStepHelper =>
      'Wird als Standard für diese Figur gespeichert und überall wiederverwendet, wo sie vorkommt.';

  @override
  String get danceEditorSnippetDivergenceTitle =>
      'Gespeicherten Ausschnitt aktualisieren?';

  @override
  String get danceEditorSnippetDivergenceBody =>
      'Dieser Text weicht von dem für diese Figur gespeicherten Ablauf-Ausschnitt ab. Neuen Text überall verwenden oder nur in diesem Tanz?';

  @override
  String get danceEditorSnippetUseEverywhere => 'Überall verwenden';

  @override
  String get danceEditorSnippetJustThisDance => 'Nur dieser Tanz';

  @override
  String get danceEditorFillWalkthroughFromSnippets =>
      'Aus Ausschnitten füllen';

  @override
  String get danceEditorFillWalkthroughReplaceTitle => 'Ablauf ersetzen?';

  @override
  String get danceEditorFillWalkthroughReplaceBody =>
      'Dies ersetzt den aktuellen Ablauf durch einen aus deinen Figur-Ausschnitten zusammengesetzten Text.';

  @override
  String get danceEditorFillWalkthroughReplaceConfirm => 'Ersetzen';

  @override
  String get danceEditorFillWalkthroughEmpty =>
      'Keine dieser Figuren hat bereits einen gespeicherten Ablauf-Ausschnitt.';

  @override
  String get settingsWalkthroughSnippetsTitle => 'Ablauf-Ausschnitte';

  @override
  String get settingsWalkthroughSnippetsSubtitle =>
      'Deine gespeicherten Schrittbeschreibungen pro Figur';

  @override
  String get settingsWalkthroughSnippetsHeader =>
      'Gespeicherte Ablauf-Ausschnitte';

  @override
  String get settingsWalkthroughSnippetsDescription =>
      'Diese Schrittbeschreibungen pro Figur füllen Abläufe vor, wenn du einen Tanz bearbeitest. Eine hier zu bearbeiten aktualisiert den überall verwendeten Standard.';

  @override
  String get settingsWalkthroughSnippetsEmpty =>
      'Noch keine gespeicherten Ausschnitte. Füge Ablaufschritt-Beschreibungen hinzu, während du die Figuren eines Tanzes bearbeitest.';

  @override
  String settingsWalkthroughSnippetsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Ausschnitte',
      one: '1 Ausschnitt',
    );
    return '$_temp0';
  }

  @override
  String get settingsWalkthroughSnippetDeleteTitle => 'Ausschnitt löschen?';

  @override
  String get settingsWalkthroughSnippetDeleteBody =>
      'Dies entfernt den gespeicherten Standard für diese Figur. Tänze behalten jeden bereits geschriebenen Ablauftext.';

  @override
  String get settingsWalkthroughSnippetEditTitle => 'Ausschnitt bearbeiten';

  @override
  String get danceEditorMoreDetailsTitle => 'Weitere Details';

  @override
  String get danceEditorStatusLabel => 'Status';

  @override
  String get danceEditorMixedLevelSubtitle =>
      'Umfasst die gesamte Schwierigkeitsskala';

  @override
  String get danceEditorComposedLabel => 'Komponiert';

  @override
  String get danceEditorComposedHelper =>
      'Wann der Tanz komponiert wurde (Jahr oder Monat/Tag hinzufügen)';

  @override
  String get danceEditorRevisedLabel => 'Überarbeitet';

  @override
  String get danceEditorRevisedHelper =>
      'Wann der Tanz zuletzt vom Autor überarbeitet wurde';

  @override
  String get danceEditorTagsLabel => 'Tags';

  @override
  String get danceEditorTunesLabel => 'Melodien';

  @override
  String get danceEditorLinksLabel => 'Links';

  @override
  String get danceEditorPublishedSourcesLabel => 'Veröffentlichte Quellen';

  @override
  String get danceEditorRelatedDancesLabel => 'Verwandte Tänze';

  @override
  String get danceEditorCustomFieldsLabel => 'Benutzerdefinierte Felder';

  @override
  String get danceEditorRatingLabel => 'Bewertung';

  @override
  String get danceEditorRatingUnrated => 'nicht bewertet';

  @override
  String danceEditorRatingValue(int rating, int max) {
    return '$rating von $max Sternen';
  }

  @override
  String danceEditorSetRatingTooltip(int rating, int max) {
    return 'Bewertung auf $rating von $max Sternen setzen';
  }

  @override
  String get danceEditorClearRating => 'Bewertung löschen';

  @override
  String get danceEditorLevelLabel => 'Niveau';

  @override
  String get danceEditorLevelUnspecified => 'Nicht angegeben';

  @override
  String get danceEditorYearLabel => 'Jahr';

  @override
  String get danceEditorYearHint => 'z. B. 1989';

  @override
  String get danceEditorYearRangeError => '1–9999';

  @override
  String get danceEditorMonthLabel => 'Monat';

  @override
  String get danceEditorDayLabel => 'Tag';

  @override
  String get danceEditorMonthJan => 'Jan.';

  @override
  String get danceEditorMonthFeb => 'Feb.';

  @override
  String get danceEditorMonthMar => 'Mär.';

  @override
  String get danceEditorMonthApr => 'Apr.';

  @override
  String get danceEditorMonthMay => 'Mai';

  @override
  String get danceEditorMonthJun => 'Jun.';

  @override
  String get danceEditorMonthJul => 'Jul.';

  @override
  String get danceEditorMonthAug => 'Aug.';

  @override
  String get danceEditorMonthSep => 'Sep.';

  @override
  String get danceEditorMonthOct => 'Okt.';

  @override
  String get danceEditorMonthNov => 'Nov.';

  @override
  String get danceEditorMonthDec => 'Dez.';

  @override
  String get monthFullJanuary => 'January';

  @override
  String get monthFullFebruary => 'February';

  @override
  String get monthFullMarch => 'March';

  @override
  String get monthFullApril => 'April';

  @override
  String get monthFullMay => 'May';

  @override
  String get monthFullJune => 'June';

  @override
  String get monthFullJuly => 'July';

  @override
  String get monthFullAugust => 'August';

  @override
  String get monthFullSeptember => 'September';

  @override
  String get monthFullOctober => 'October';

  @override
  String get monthFullNovember => 'November';

  @override
  String get monthFullDecember => 'December';

  @override
  String get danceEditorAddTuneHint => 'Vorgeschlagene Melodie hinzufügen…';

  @override
  String get danceEditorAddTuneTooltip => 'Melodie hinzufügen';

  @override
  String get danceEditorWarningsTitle => 'Warnungen';

  @override
  String validationPhraseBeatMismatch(int actual, int expected) {
    return 'Die Figuren ergeben insgesamt $actual Takte; die Phrasierungsstruktur erwartet $expected.';
  }

  @override
  String get validationPhraseInvalid =>
      'Diese Phrasierungsstruktur ist ungültig.';

  @override
  String validationOrphanedAlt(int position) {
    return 'Die Alternative an Position $position hat keinen vorangehenden Hauptplatz.';
  }

  @override
  String validationOrphanedAltNamed(int position, String text) {
    return 'Die Alternative an Position $position („$text“) hat keinen vorangehenden Hauptplatz.';
  }

  @override
  String validationEmptySubstitution(String term) {
    return 'Die Ersetzung für „$term“ ist leer.';
  }

  @override
  String validationDialectCollision(
    String source,
    String existing,
    String substitution,
  ) {
    return '„$source“ und „$existing“ werden beide auf „$substitution“ abgebildet – die Umkehrung wäre mehrdeutig.';
  }

  @override
  String get validationGeneric => 'Dieses Element hat ein Validierungsproblem.';

  @override
  String danceEditorDiscouragedTermSemantic(String term) {
    return 'Abgeratener Begriff: $term';
  }

  @override
  String danceEditorDiscouragedTermText(String term) {
    return 'Abgeraten: $term';
  }

  @override
  String get danceEditorLinkKindSource => 'Quelle';

  @override
  String get danceEditorLinkKindVideo => 'Video';

  @override
  String get danceEditorLinkKindOther => 'Sonstige';

  @override
  String get danceEditorUrlLabel => 'URL';

  @override
  String get danceEditorLabelOptional => 'Bezeichnung (optional)';

  @override
  String get danceEditorRemoveLinkTooltip => 'Link entfernen';

  @override
  String get danceEditorAddLink => 'Link hinzufügen';

  @override
  String get danceEditorMissingDance => '(fehlender Tanz)';

  @override
  String get danceEditorNoteOptionalLabel => 'Notiz (optional)';

  @override
  String get danceEditorRemoveRelatedDanceTooltip =>
      'Verwandten Tanz entfernen';

  @override
  String get danceEditorAddRelatedDance => 'Verwandten Tanz hinzufügen';

  @override
  String get danceEditorRelatedDanceLabel => 'Verwandter Tanz';

  @override
  String get danceEditorTypeToSearchHint => 'Zum Suchen eingeben…';

  @override
  String danceEditorEditItemTooltip(String item) {
    return '$item bearbeiten';
  }

  @override
  String get danceEditorTypeToAddOrCreateHint =>
      'Zum Hinzufügen oder Erstellen eingeben…';

  @override
  String danceEditorCreateQuotedName(String name) {
    return '„$name“ erstellen';
  }

  @override
  String get danceEditorUnknownSource => '(unbekannte Quelle)';

  @override
  String get danceEditorPageOptionalLabel => 'Seite (optional)';

  @override
  String get danceEditorNumberOptionalLabel => 'Nummer (optional)';

  @override
  String get danceEditorCiteSourceHint =>
      'Quelle zitieren: Zum Hinzufügen oder Erstellen eingeben…';

  @override
  String get danceEditorSaveError => 'Tanz konnte nicht gespeichert werden.';

  @override
  String get danceEditorFallbackDanceTitle => 'Tanz';

  @override
  String get danceEditorUnsavedDraftTitle => 'Nicht gespeicherter Entwurf';

  @override
  String get danceEditorUnsavedDraftMessage =>
      'Sie haben einen nicht gespeicherten Entwurf für diesen Tanz. Möchten Sie ihn wiederherstellen?';

  @override
  String get danceEditorDiscard => 'Verwerfen';

  @override
  String get danceEditorRestore => 'Wiederherstellen';

  @override
  String get danceEditorDiscardChangesTitle => 'Änderungen verwerfen?';

  @override
  String get danceEditorDiscardChangesMessage =>
      'Sie haben nicht gespeicherte Änderungen an diesem Tanz.';

  @override
  String get danceEditorKeepEditing => 'Weiter bearbeiten';

  @override
  String get danceEditorNewDanceTitle => 'Neuer Tanz';

  @override
  String get danceEditorEditDanceTitle => 'Tanz bearbeiten';

  @override
  String get danceEditorRedoLabel => 'Wiederholen';

  @override
  String get danceEditorUndoShortcutTooltip => 'Rückgängig (Strg+Z)';

  @override
  String get danceEditorRedoShortcutTooltip => 'Wiederholen (Strg+Umschalt+Z)';

  @override
  String get danceEditorDeleteDanceTooltip => 'Tanz löschen';

  @override
  String get danceEditorLoadError => 'Tanz konnte nicht geladen werden.';

  @override
  String get danceEditorChoreographerDetailsTitle => 'Choreografen-Details';

  @override
  String get danceEditorChoreographerDetailsIntro =>
      'Diese Details werden für alle Tänze geteilt, die diesem Autor zugeschrieben werden. E-Mail und Standort sind privat – nur auf diesem Gerät gespeichert und nie geteilt oder exportiert.';

  @override
  String get danceEditorNameRequiredLabel => 'Name *';

  @override
  String get danceEditorNameRequired => 'Name ist erforderlich';

  @override
  String get danceEditorWebsiteLabel => 'Website';

  @override
  String get danceEditorEmailPrivateLabel => 'E-Mail (privat)';

  @override
  String get danceEditorLocationPrivateLabel => 'Standort (privat)';

  @override
  String get danceEditorNotesLabel => 'Notizen';

  @override
  String get danceEditorDeceasedLabel => 'Verstorben';

  @override
  String get danceEditorSourceDetailsTitle => 'Quellen-Details';

  @override
  String get danceEditorSourceDetailsIntro =>
      'Diese Details werden für alle Tänze geteilt, die diese Quelle zitieren. Das Bearbeiten hier aktualisiert die Quelle überall, wo sie referenziert wird.';

  @override
  String get danceEditorSourceAuthorEditorLabel => 'Autor / Herausgeber';

  @override
  String get danceEditorEnterWholeNumber => 'Geben Sie eine ganze Zahl ein';

  @override
  String get danceEditorEnterPositiveYear => 'Geben Sie ein positives Jahr ein';

  @override
  String danceEditorAddedFigureChooseMove(int count) {
    return 'Figur $count hinzugefügt. Wählen Sie eine Bewegung.';
  }

  @override
  String danceEditorFigurePastedAnnouncement(int position) {
    return 'Figur an Position $position eingefügt.';
  }

  @override
  String danceEditorFigureMovedAnnouncement(int position, int total) {
    return 'Auf Position $position von $total verschoben.';
  }

  @override
  String danceEditorEditingFigureAnnouncement(int position, String name) {
    return 'Figur $position wird bearbeitet, $name.';
  }

  @override
  String danceEditorCollapsedFigureAnnouncement(int position) {
    return 'Figur $position eingeklappt.';
  }

  @override
  String get danceEditorTypeFigureAnnouncement =>
      'Geben Sie eine Figur ein und drücken Sie Eingabe, um sie hinzuzufügen.';

  @override
  String danceEditorFreeTextFiguresAddedAnnouncement(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count Figuren hinzugefügt. Geben Sie eine weitere ein oder drücken Sie Escape, um zu beenden.',
      one:
          '1 Figur hinzugefügt. Geben Sie eine weitere ein oder drücken Sie Escape, um zu beenden.',
    );
    return '$_temp0';
  }

  @override
  String danceEditorDeletedFigureAnnouncement(int position) {
    return 'Figur $position gelöscht. Rückgängig verfügbar.';
  }

  @override
  String danceEditorDuplicatedFigureAnnouncement(int position) {
    return 'Figur $position dupliziert.';
  }

  @override
  String get danceEditorAddFirstFigure => 'Erste Figur hinzufügen';

  @override
  String danceEditorCutBanner(String figure) {
    return '„$figure“ wurde ausgeschnitten – tippen Sie auf Einfügen, um sie zu platzieren.';
  }

  @override
  String get danceEditorPasteBeforeFirstFigure =>
      'Vor der ersten Figur einfügen';

  @override
  String danceEditorPasteAfterFigure(String figure) {
    return 'Nach $figure einfügen';
  }

  @override
  String get danceEditorAddFigure => 'Figur hinzufügen';

  @override
  String get danceEditorPasteAtEndOfFigureList =>
      'Am Ende der Figurenliste einfügen';

  @override
  String get danceEditorTypeFigureLabel => 'Figur eingeben';

  @override
  String get danceEditorTypeFigureHelper =>
      'z. B. „neighbor balance & swing“ oder „16 circle left 3/4“. Eingabe fügt sie hinzu; nicht erkannter Text wird als benutzerdefinierte Figur gespeichert.';

  @override
  String get danceEditorPasteHere => 'Hier einfügen';

  @override
  String get danceEditorEmptyFigureName => 'Leere Figur';

  @override
  String get danceEditorCustomFigureName => 'Benutzerdefinierte Figur';

  @override
  String get danceEditorEmptyFigureSummary => '(leer — Bewegung auswählen)';

  @override
  String get danceEditorEmptyFigureSemantic =>
      'leere Figur, Bewegung auswählen';

  @override
  String danceEditorFigureSummarySemantic(
    String main,
    String importGap,
    String importGapText,
    String progression,
    String hasMove,
    int beats,
    String hasNote,
    String note,
    int position,
    int total,
  ) {
    String _temp0 = intl.Intl.selectLogic(importGap, {
      'yes': ', $importGapText',
      'other': '',
    });
    String _temp1 = intl.Intl.selectLogic(progression, {
      'yes': ', Progression',
      'other': '',
    });
    String _temp2 = intl.Intl.pluralLogic(
      beats,
      locale: localeName,
      other: '$beats Takte',
      one: '1 Takt',
    );
    String _temp3 = intl.Intl.selectLogic(hasMove, {
      'yes': ', $_temp2',
      'other': '',
    });
    String _temp4 = intl.Intl.selectLogic(hasNote, {
      'yes': ', Notiz: $note',
      'other': '',
    });
    return '$main$_temp0$_temp1$_temp3$_temp4. Figur $position von $total.';
  }

  @override
  String get danceEditorActivateToEditHint => 'Aktivieren zum Bearbeiten';

  @override
  String danceEditorDragToReorderFigure(String figure) {
    return '$figure zum Neuordnen ziehen';
  }

  @override
  String danceEditorFigureActionsTooltip(String figure) {
    return 'Aktionen für $figure';
  }

  @override
  String get danceEditorMoveUp => 'Nach oben';

  @override
  String get danceEditorMoveDown => 'Nach unten';

  @override
  String get danceEditorCut => 'Ausschneiden';

  @override
  String get danceEditorClearProgression => 'Progression löschen';

  @override
  String get danceEditorMarkProgression => 'Progression markieren';

  @override
  String get danceEditorGroupWithNext => 'Group with next as meanwhile';

  @override
  String danceEditorMeanwhileGroupLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Meanwhile ($count sides)',
    );
    return '$_temp0';
  }

  @override
  String danceEditorMeanwhileGroupSemantic(int count, int beats) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count concurrent figures',
      one: '1 concurrent figure',
    );
    String _temp1 = intl.Intl.pluralLogic(
      beats,
      locale: localeName,
      other: '$beats shared beats',
      one: '1 shared beat',
    );
    return 'Meanwhile group, $_temp0, $_temp1.';
  }

  @override
  String danceEditorMeanwhileSideLabel(int number) {
    return 'Side $number';
  }

  @override
  String danceEditorMeanwhileSideSemantic(int number, int total) {
    return 'Side $number of $total.';
  }

  @override
  String get danceEditorAddMeanwhileSide => 'Add side';

  @override
  String get danceEditorRemoveMeanwhileSide => 'Remove this side';

  @override
  String danceEditorMeanwhileSidesCapReached(int max) {
    return 'Maximum of $max concurrent figures.';
  }

  @override
  String danceEditorUnrecognizedMoveReadOnly(String move) {
    return 'Nicht erkannte Bewegung „$move“ – nicht in der Taxonomie dieser Version. Schreibgeschützt angezeigt, damit die Daten erhalten bleiben; sie wird wieder normal bearbeitet, wenn die Bewegung bekannt wird. Sie können sie noch neu ordnen oder löschen.';
  }

  @override
  String get danceEditorFewerOptions => 'Weniger Optionen';

  @override
  String danceEditorMoreOptions(int count) {
    return 'Mehr Optionen ($count)';
  }

  @override
  String get danceEditorAddNote => 'Notiz hinzufügen';

  @override
  String get danceEditorBoldTooltip => 'Fett (*text*)';

  @override
  String get danceEditorUnderlineTooltip => 'Unterstrichen (_text_)';

  @override
  String get danceEditorCustomFigureTextLabel =>
      'Benutzerdefinierter Figurentext';

  @override
  String get danceEditorLingoStylingHelper =>
      'Bewegungsnamen gestrichelt unterstrichen, Rollenbegriffe unterstrichen, abgeratene Begriffe durchgestrichen';

  @override
  String danceEditorBeatTotal(int total, int expected) {
    return 'Gesamt: $total / $expected Takte';
  }

  @override
  String danceEditorOverByBeats(int beats) {
    return 'Um $beats Takte zu lang';
  }

  @override
  String danceEditorUnderByBeats(int beats) {
    return 'Um $beats Takte zu kurz';
  }

  @override
  String get danceEditorLessTooltip => 'Weniger';

  @override
  String get danceEditorParamNotStated => 'nicht angegeben';

  @override
  String get danceEditorParamClearTooltip => 'Löschen (nicht angegeben)';

  @override
  String get danceEditorMoreTooltip => 'Mehr';

  @override
  String danceEditorTurnCount(num count, String formatted) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$formatted Drehungen',
      one: '$formatted Drehung',
    );
    return '$_temp0';
  }

  @override
  String get commonBack => 'Zurück';

  @override
  String get commonRemove => 'Entfernen';

  @override
  String updateBannerDownloading(String appName, String version) {
    return '$appName $version wird heruntergeladen…';
  }

  @override
  String updateBannerDownloadingPct(String appName, String version, int pct) {
    return '$appName $version wird heruntergeladen… $pct%';
  }

  @override
  String updateBannerVerifying(String appName, String version) {
    return '$appName $version wird verifiziert…';
  }

  @override
  String get updateBannerPreparingInstaller =>
      'Installationsprogramm wird vorbereitet…';

  @override
  String updateBannerCompletedRevealed(String appName, String version) {
    return '$appName $version heruntergeladen und verifiziert – das Installationsprogramm wurde in Ihrem Dateimanager angezeigt. Führen Sie es aus, um die Aktualisierung abzuschließen.';
  }

  @override
  String updateBannerCompletedManual(String appName, String version) {
    return '$appName $version heruntergeladen – folgen Sie dem Installationsprogramm, um die Aktualisierung abzuschließen.';
  }

  @override
  String get updateBannerDownloadFailed =>
      'Das Update konnte nicht heruntergeladen werden.';

  @override
  String updateBannerAvailable(String appName, String version) {
    return 'Eine neuere Version von $appName ($version) ist verfügbar.';
  }

  @override
  String get updateBannerViewRelease => 'Release ansehen';

  @override
  String get updateBannerDismiss => 'Schließen';

  @override
  String get updateBannerDownloadInstall => 'Herunterladen & installieren';

  @override
  String get commandPaletteBarrierLabel => 'Globale Suche';

  @override
  String get commandPaletteSearchHint => 'Tänze und Programme suchen…';

  @override
  String get commandPaletteProgramSubtitle => 'Programm';

  @override
  String get commandPaletteEmptyInitial => 'Noch nichts zu suchen.';

  @override
  String get commandPaletteNoMatches =>
      'Keine Übereinstimmungen für diese Suche.';

  @override
  String get commandPaletteGroupDances => 'Tänze';

  @override
  String get commandPaletteGroupPrograms => 'Programme';

  @override
  String get collectionPickerSearchLabel => 'Tanz zum Hinzufügen suchen';

  @override
  String collectionPickerFilters(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Filter ($count aktiv)',
      zero: 'Filter',
    );
    return '$_temp0';
  }

  @override
  String collectionPickerByPhrase(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Nach Phrase ($count aktiv)',
      zero: 'Nach Phrase',
    );
    return '$_temp0';
  }

  @override
  String get collectionPickerAdvanced => 'Erweitert';

  @override
  String get collectionPickerUseAdvancedQuery => 'Erweiterte Abfrage verwenden';

  @override
  String get collectionPickerAdvancedQueryHelp =>
      'Figuren und Sequenzen mit Alle- / Beliebige- / Keine-Gruppen kombinieren.';

  @override
  String collectionPickerAddSemantic(String title) {
    return '$title zum Programm hinzufügen';
  }

  @override
  String collectionPickerAddTooltip(String title) {
    return '$title hinzufügen';
  }

  @override
  String collectionPickerAddedTooltip(String title) {
    return 'Added $title';
  }

  @override
  String collectionPickerInProgramSemantic(String title) {
    return '$title is already in the program';
  }

  @override
  String collectionPickerInProgramCountSemantic(String title, int count) {
    return '$title is in the program $count times';
  }

  @override
  String get userGuideTitle => 'Benutzerhandbuch';

  @override
  String userGuideMissing(String label) {
    return 'Der Leitfaden „$label“ ist noch nicht verfügbar.';
  }

  @override
  String get userGuideLoadError =>
      'Das Benutzerhandbuch konnte nicht geladen werden.';

  @override
  String get userGuideOpenOnline => 'Leitfaden online öffnen';

  @override
  String get shorthandMappingsTitle => 'Figur-Abkürzungen';

  @override
  String get shorthandMappingsIntro =>
      'Abkürzungen ermöglichen es Ihnen, bei der Freitexteingabe einen kurzen Token einzugeben, der zu einer oder mehreren hier eingerichteten Figuren erweitert wird.';

  @override
  String get shorthandMappingsNew => 'Neue Abkürzung';

  @override
  String get shorthandMappingsEmpty => 'Noch keine Abkürzungen.';

  @override
  String get shorthandMappingsDeleteTitle => 'Abkürzung löschen?';

  @override
  String shorthandMappingsDeleteBody(String token) {
    return '„$token“ wird dauerhaft entfernt.';
  }

  @override
  String get shorthandMappingsActionsTooltip => 'Abkürzungs-Aktionen';

  @override
  String get shorthandEditorTitleNew => 'Neue Abkürzung';

  @override
  String get shorthandEditorTitleEdit => 'Abkürzung bearbeiten';

  @override
  String get shorthandEditorTokenLabel => 'Abkürzung';

  @override
  String get shorthandEditorTokenHelper =>
      'Geben Sie diese exakte Zeile bei der Freitexteingabe ein, um die untenstehenden Figuren einzufügen. Groß-/Kleinschreibung wird nicht berücksichtigt.';

  @override
  String get shorthandEditorExpandsTo => 'Wird erweitert zu';

  @override
  String get shorthandEditorExpandsToHelp =>
      'Die Figur(en), die diese Abkürzung einfügt, in Reihenfolge. Genau wie eine normale Figur aufgebaut, sodass Parameter und Validierung identisch sind.';

  @override
  String get shorthandEditorErrorEmpty => 'Geben Sie ein Abkürzungs-Token ein.';

  @override
  String shorthandEditorErrorTooLong(int max) {
    return 'Abkürzung ist zu lang (max. $max Zeichen).';
  }

  @override
  String shorthandEditorErrorDuplicate(String token) {
    return 'Eine andere Abkürzung verwendet bereits „$token“ (Abkürzungen werden ohne Berücksichtigung der Groß-/Kleinschreibung abgeglichen).';
  }

  @override
  String get shorthandEditorErrorNoFigures =>
      'Fügen Sie mindestens eine Figur hinzu, zu der diese Abkürzung erweitert werden soll.';

  @override
  String get importShorthandSeedTitle => 'Seed figure shorthands';

  @override
  String get importShorthandSeedIntro =>
      'Your Caller\'s Companion file\'s call buttons can become figure shorthands. Pick the ones you want; each expands to the figures shown. Nothing is added until you confirm, and your existing shorthands are never overwritten.';

  @override
  String get importShorthandSeedAvailableHeader => 'From your call buttons';

  @override
  String get importShorthandSeedUsePrimary => 'Primary';

  @override
  String get importShorthandSeedUseAlt => 'Alternate';

  @override
  String get importShorthandSeedConflictHeader => 'Already defined — skipped';

  @override
  String importShorthandSeedConflictNote(String token) {
    return 'A shorthand named “$token” already exists, so this button was left as-is.';
  }

  @override
  String get importShorthandSeedSkip => 'Skip';

  @override
  String importShorthandSeedConfirm(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Seed $count shorthands',
      one: 'Seed 1 shorthand',
      zero: 'Seed shorthands',
    );
    return '$_temp0';
  }

  @override
  String importShorthandSeedComplete(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Seeded $count shorthands',
      one: 'Seeded 1 shorthand',
    );
    return '$_temp0';
  }

  @override
  String get themeEditorTitle => 'Design bearbeiten';

  @override
  String get themeEditorNameLabel => 'Designname';

  @override
  String get themeEditorContrastAllPass =>
      'Alle geprüften Paare bestehen den WCAG-AA-Kontrast.';

  @override
  String themeEditorContrastFailing(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count Kontrastpaare unterhalb von WCAG AA. Sie können trotzdem speichern, aber einiger Text könnte schwer lesbar sein.',
      one:
          '1 Kontrastpaar unterhalb von WCAG AA. Sie können trotzdem speichern, aber einiger Text könnte schwer lesbar sein.',
    );
    return '$_temp0';
  }

  @override
  String themeEditorRatioPass(String ratio) {
    return '$ratio:1 AA';
  }

  @override
  String themeEditorRatioFail(String ratio) {
    return '$ratio:1 nicht bestanden';
  }

  @override
  String get themeEditorPreviewHeading => 'Aa Vorschau';

  @override
  String get themeEditorBodySample => 'Beispiel Fließtext';

  @override
  String get themeEditorSwatchPrimary => 'Primär';

  @override
  String get themeEditorSwatchSecondary => 'Sekundär';

  @override
  String get themeEditorSwatchTertiary => 'Tertiär';

  @override
  String get themeEditorSwatchError => 'Fehler';

  @override
  String get reparseConfirmTitle => 'Benutzerdefinierte Figuren aktualisieren?';

  @override
  String reparseConfirmBody(int figureCount, int danceCount) {
    String _temp0 = intl.Intl.pluralLogic(
      figureCount,
      locale: localeName,
      other: '$figureCount Figuren',
      one: '1 Figur',
    );
    String _temp1 = intl.Intl.pluralLogic(
      danceCount,
      locale: localeName,
      other: '$danceCount Tänzen',
      one: '1 Tanz',
    );
    return 'Dadurch werden $_temp0 in $_temp1 neu geparst. Ihre Tags, Bewertungen, Notizen und alles andere bei jedem Tanz bleiben exakt erhalten. Dies ersetzt nur Figuren, die jetzt eine bekannte Bewegung erkennen.';
  }

  @override
  String get reparseConfirmUpgrade => 'Aktualisieren';

  @override
  String get reparseFailed =>
      'Figuren konnten nicht aktualisiert werden. Bitte versuchen Sie es erneut.';

  @override
  String get reparseNothingUpgradedSnack => 'Nichts zu aktualisieren.';

  @override
  String reparseUpgradedSnack(int danceCount) {
    String _temp0 = intl.Intl.pluralLogic(
      danceCount,
      locale: localeName,
      other: '$danceCount Tänzen',
      one: '1 Tanz',
    );
    return 'Benutzerdefinierte Figuren in $_temp0 aktualisiert.';
  }

  @override
  String get reparseScreenTitle => 'Benutzerdefinierte Figuren erneut prüfen';

  @override
  String reparseIntro(int figureCount, int danceCount) {
    String _temp0 = intl.Intl.pluralLogic(
      figureCount,
      locale: localeName,
      other: '$figureCount Figuren',
      one: '1 Figur',
    );
    String _temp1 = intl.Intl.pluralLogic(
      danceCount,
      locale: localeName,
      other: '$danceCount Tänzen',
      one: '1 Tanz',
    );
    return 'Verbessertes Figuren-Parsing kann $_temp0 in $_temp1 aktualisieren. Prüfen Sie unten, dann bestätigen – nichts ändert sich, bis Sie es tun, und alle Ihre Tags, Bewertungen und Notizen bleiben erhalten.';
  }

  @override
  String reparsePreviewCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Figuren',
      one: '1 Figur',
    );
    return '$_temp0 zum Aktualisieren';
  }

  @override
  String reparseUpgradeButton(int danceCount) {
    String _temp0 = intl.Intl.pluralLogic(
      danceCount,
      locale: localeName,
      other: '$danceCount Tänze',
      one: '1 Tanz',
    );
    return '$_temp0 aktualisieren';
  }

  @override
  String get reparseEmptyTitle => 'Nichts zu aktualisieren';

  @override
  String get reparseEmptyBody =>
      'Keine Ihrer benutzerdefinierten Figuren aus Importen kann derzeit als bekannte Bewegung erkannt werden. Schauen Sie nach einem zukünftigen Update wieder nach, das das Figuren-Parsing verbessert.';

  @override
  String get reparseErrorTitle => 'Ihre Figuren konnten nicht geprüft werden';

  @override
  String get reparseErrorBody =>
      'Beim Scannen Ihrer Sammlung ist etwas schiefgelaufen. Es wurde nichts geändert. Sie können es erneut versuchen.';

  @override
  String get customFieldsDeleteTitle => 'Benutzerdefiniertes Feld löschen';

  @override
  String customFieldsDeleteBody(String label) {
    return '„$label“ löschen? Dies kann nicht rückgängig gemacht werden.';
  }

  @override
  String customFieldsDeleteInUse(String label, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Tänzen',
      one: '1 Tanz',
    );
    return '„$label“ kann nicht gelöscht werden: noch in $_temp0 verwendet. Entfernen Sie zuerst den Wert aus allen Tänzen.';
  }

  @override
  String customFieldsDeleteInUseUnknown(String label) {
    return '„$label“ kann nicht gelöscht werden: noch von einigen Tänzen verwendet. Entfernen Sie zuerst den Wert aus allen Tänzen.';
  }

  @override
  String get customFieldsTitle => 'Benutzerdefinierte Felder';

  @override
  String get customFieldsNewField => 'Neues Feld';

  @override
  String get customFieldsLoadError =>
      'Benutzerdefinierte Felder konnten nicht geladen werden.';

  @override
  String get customFieldsEmpty =>
      'Noch keine benutzerdefinierten Felder.\nTippen Sie auf +, um eines zu definieren.';

  @override
  String get customFieldsFlagInList => 'In Liste';

  @override
  String get customFieldsSearchable => 'Suchbar';

  @override
  String get customFieldsTypeText => 'Text';

  @override
  String get customFieldsTypeNumber => 'Zahl';

  @override
  String get customFieldsTypeBoolean => 'Boolesch';

  @override
  String get customFieldsTypeChoice => 'Auswahl';

  @override
  String get customFieldsValidatorMinChoice =>
      'Fügen Sie mindestens eine Auswahl hinzu';

  @override
  String customFieldsRemoveValueError(String value) {
    return '„$value“ kann nicht entfernt werden: es ist bei mindestens einem Tanz gesetzt.';
  }

  @override
  String get customFieldsEditorNewTitle => 'Neues benutzerdefiniertes Feld';

  @override
  String get customFieldsEditorEditTitle =>
      'Benutzerdefiniertes Feld bearbeiten';

  @override
  String get customFieldsLabelLabel => 'Bezeichnung *';

  @override
  String get customFieldsLabelRequired => 'Bezeichnung ist erforderlich';

  @override
  String get customFieldsKeyLabel => 'Schlüssel *';

  @override
  String get customFieldsKeyHelper =>
      'Stabiler Maschinenschlüssel (Buchstaben, Ziffern, Unterstriche; muss mit einem Buchstaben oder Unterstrich beginnen)';

  @override
  String get customFieldsKeyLocked =>
      'Schlüssel ist gesperrt — Feld wird in Tänzen verwendet';

  @override
  String get customFieldsKeyRequired => 'Schlüssel ist erforderlich';

  @override
  String get customFieldsKeyInvalid =>
      'Schlüssel muss mit einem Buchstaben oder Unterstrich beginnen und nur Buchstaben, Ziffern und Unterstriche enthalten';

  @override
  String get customFieldsTypeFieldLabel => 'Typ';

  @override
  String get customFieldsTypeLocked =>
      'Typ ist gesperrt — Feld hat Werte in Tänzen';

  @override
  String get customFieldsShowInList => 'In Liste anzeigen';

  @override
  String get customFieldsShowInListSubtitle =>
      'Diesen Feldwert im Tanzlisten-Eintrag anzeigen';

  @override
  String get customFieldsSearchableSubtitle =>
      'Dieses Feld als Filter im Suchbereich verfügbar machen';

  @override
  String get customFieldsChoicesLabel => 'Auswahlmöglichkeiten *';

  @override
  String get customFieldsChoiceInUseTooltip =>
      'In Verwendung — kann nicht entfernt werden';

  @override
  String get customFieldsNewChoiceHint => 'Neue Auswahl…';

  @override
  String get customFieldsAddChoiceTooltip => 'Auswahl hinzufügen';

  @override
  String get customFieldsChoiceDuplicate => 'Diese Option existiert bereits.';

  @override
  String get customFieldsChoiceEmpty => 'Bitte eine Option eingeben.';

  @override
  String customFieldsAddOptionTooltip(String label) {
    return 'Option zu $label hinzufügen';
  }

  @override
  String customFieldsAddOptionTitle(String label) {
    return 'Option zu $label hinzufügen';
  }

  @override
  String get customFieldsShareable => 'Include in sharing';

  @override
  String get customFieldsShareableSubtitle =>
      'This field\'s values travel with your collection when you export or share it';

  @override
  String get customFieldsSharingNoticeTitle =>
      'Custom fields travel with your collection';

  @override
  String get customFieldsSharingNoticeBody =>
      'The contents of any custom field you create are included when you export or share your collection. To keep a field private, turn off \"Include in sharing\" in that field\'s settings.';

  @override
  String get customFieldsSharingNoticeOk => 'Got it';

  @override
  String dialectEditorTitle(String name) {
    return '$name bearbeiten';
  }

  @override
  String get dialectEditorSectionRoleTerms => 'Rollenbegriffe';

  @override
  String get dialectEditorSectionMoveSubs => 'Bewegungsersetzungen';

  @override
  String get dialectEditorSectionDancerSubs => 'Tänzerersetzungen';

  @override
  String get dialectEditorSectionDiscouraged => 'Abgeratene Begriffe';

  @override
  String get dialectEditorSectionPreview => 'Vorschau';

  @override
  String get dialectEditorRole1 => 'Rolle 1';

  @override
  String get dialectEditorRole2 => 'Rolle 2';

  @override
  String get dialectEditorRolesHelp =>
      'Lassen Sie eine Rolle leer, um den kanonischen Begriff zu verwenden. Der Plural wird abgeleitet, wenn er weggelassen wird.';

  @override
  String get dialectEditorSingular => 'Singular';

  @override
  String get dialectEditorPlural => 'Plural';

  @override
  String get dialectEditorMoveSubsAdd => 'Bewegungsersetzungen hinzufügen';

  @override
  String dialectEditorMoveSubsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Bewegungsersetzungen',
      one: '1 Bewegungsersetzung',
    );
    return '$_temp0';
  }

  @override
  String get dialectEditorMoveSubHint =>
      'Ersetzung (verwenden Sie %S für die Händigkeit)';

  @override
  String get dialectEditorAddMove => 'Bewegung hinzufügen…';

  @override
  String get dialectEditorDancerSubsAdd => 'Tänzerersetzungen hinzufügen';

  @override
  String dialectEditorDancerSubsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count Tänzerersetzungen',
      one: '1 Tänzerersetzung',
    );
    return '$_temp0';
  }

  @override
  String get dialectEditorDancerSubHint => 'Ersetzung';

  @override
  String get dialectEditorAddDancerTerm => 'Tänzerbegriff hinzufügen…';

  @override
  String get dialectEditorDiscouragedHelp =>
      'Begriffe, die der Editor markiert (durchgestrichen) — nie blockiert.';

  @override
  String get dialectEditorDiscouragedEmpty => 'Keine abgeratenen Begriffe.';

  @override
  String get dialectEditorAddTermLabel => 'Begriff hinzufügen';

  @override
  String get dialectEditorAddTermTooltip => 'Begriff hinzufügen';

  @override
  String get dialectEditorRestoreDefaults => 'Standardwerte wiederherstellen';

  @override
  String get dialectEditorPreviewHelp =>
      'Beispielfiguren, die mit diesem Dialekt gerendert werden. Wird beim Bearbeiten aktualisiert.';

  @override
  String get recentlyDeletedTitle => 'Zuletzt gelöscht';

  @override
  String get recentlyDeletedDeleteTitle => 'Dauerhaft löschen?';

  @override
  String recentlyDeletedDeleteBody(String title) {
    return '„$title“ wird sofort gelöscht und kann nicht wiederhergestellt werden.';
  }

  @override
  String get recentlyDeletedDeleteConfirm => 'Dauerhaft löschen';

  @override
  String recentlyDeletedDeletedSnack(String title) {
    return '„$title“ dauerhaft gelöscht.';
  }

  @override
  String get recentlyDeletedRestore => 'Wiederherstellen';

  @override
  String get recentlyDeletedPurgeKept => 'Aufbewahrt bis Sie es löschen';

  @override
  String recentlyDeletedPurgeCountdown(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days Tagen',
      one: '1 Tag',
    );
    return 'Wird automatisch gelöscht in $_temp0';
  }

  @override
  String get recentlyDeletedPurgeScheduled => 'Zum Löschen vorgemerkt';

  @override
  String get recentlyDeletedLoadingDances =>
      'Zuletzt gelöschte Tänze werden geladen';

  @override
  String get recentlyDeletedLoadingPrograms =>
      'Zuletzt gelöschte Programme werden geladen';

  @override
  String get recentlyDeletedEmptyDancesKept =>
      'Nichts im Papierkorb. Gelöschte Tänze werden hier aufbewahrt, bis Sie sie entfernen.';

  @override
  String recentlyDeletedEmptyDancesRetention(int days) {
    return 'Nichts im Papierkorb. Gelöschte Tänze erscheinen hier für $days Tage, bevor sie entfernt werden.';
  }

  @override
  String recentlyDeletedEmptyProgramsRetention(int days) {
    return 'Nichts im Papierkorb. Gelöschte Programme erscheinen hier für $days Tage, bevor sie entfernt werden.';
  }

  @override
  String recentlyDeletedRestoredDance(String title) {
    return '„$title“ in Ihre Sammlung wiederhergestellt.';
  }

  @override
  String recentlyDeletedRestoredProgram(String title) {
    return '„$title“ wiederhergestellt.';
  }

  @override
  String get venueNew => 'Neuer Veranstaltungsort';

  @override
  String get venueLoadError =>
      'Veranstaltungsorte konnten nicht geladen werden.';

  @override
  String get venueManagerTitle => 'Veranstaltungsorte';

  @override
  String get venueManagerSearchHint => 'Veranstaltungsorte suchen…';

  @override
  String get venueManagerClearSearchTooltip => 'Suche löschen';

  @override
  String get venueManagerEmpty =>
      'Noch keine Veranstaltungsorte. Fügen Sie einen mit der Schaltfläche unten hinzu oder über ein Programm, wenn wiederverwendbare Veranstaltungsorte aktiviert sind.';

  @override
  String get venueManagerNoMatches =>
      'Keine Veranstaltungsorte entsprechen Ihrer Suche.';

  @override
  String get venueManagerDeleteTitle => 'Veranstaltungsort löschen?';

  @override
  String venueManagerDeleteBody(String name) {
    return '„$name“ dauerhaft löschen? Dies kann nicht rückgängig gemacht werden.';
  }

  @override
  String venueManagerDeletedSnack(String name) {
    return '„$name“ gelöscht';
  }

  @override
  String venueManagerDeleteBlocked(String name) {
    return '„$name“ kann nicht gelöscht werden, solange er noch mit einem Programm verknüpft ist. Ändern oder entfernen Sie zuerst den Veranstaltungsort bei diesen Programmen.';
  }

  @override
  String venueManagerDeleteTooltip(String name) {
    return '$name löschen';
  }

  @override
  String get venueEditTitle => 'Veranstaltungsort bearbeiten';

  @override
  String get venueEditorSharedNote =>
      'Ein Veranstaltungsort wird für alle hier stattfindenden Programme geteilt, sodass Änderungen an Adresse, Kontakten oder Zeitplan bei allen angezeigt werden.';

  @override
  String get venueEditorNameLabel => 'Name *';

  @override
  String get venueEditorNameRequired => 'Name ist erforderlich';

  @override
  String get venueEditorWebsiteLabel => 'Website';

  @override
  String get venueEditorSponsorLabel => 'Sponsor / ausrichtende Organisation';

  @override
  String get venueEditorAddressSection => 'Adresse';

  @override
  String get venueEditorAddress1Label => 'Adresszeile 1';

  @override
  String get venueEditorAddress2Label => 'Adresszeile 2';

  @override
  String get venueEditorCityLabel => 'Stadt';

  @override
  String get venueEditorStateLabel => 'Bundesland / Provinz';

  @override
  String get venueEditorCountryLabel => 'Land';

  @override
  String get venueEditorPostalLabel => 'Postleitzahl';

  @override
  String get venueEditorPlus4Label => 'ZIP+4';

  @override
  String get venueEditorScheduleSection => 'Zeitplan';

  @override
  String get venueEditorEventNameLabel => 'Veranstaltungsname';

  @override
  String get venueEditorTimeLabel => 'Uhrzeit';

  @override
  String get venueEditorScheduleLabel => 'Zeitplan (z. B. „2. Samstage“)';

  @override
  String get venueEditorPriceLabel => 'Preis';

  @override
  String get venueEditorContactsSection => 'Kontakte';

  @override
  String get venueEditorContact1NameLabel => 'Kontaktperson 1 Name';

  @override
  String get venueEditorContact1PhoneLabel => 'Kontaktperson 1 Telefon';

  @override
  String get venueEditorContact1EmailLabel => 'Kontaktperson 1 E-Mail';

  @override
  String get venueEditorContact2NameLabel => 'Kontaktperson 2 Name';

  @override
  String get venueEditorContact2PhoneLabel => 'Kontaktperson 2 Telefon';

  @override
  String get venueEditorContact2EmailLabel => 'Kontaktperson 2 E-Mail';

  @override
  String get venueEditorNotesSection => 'Notizen';

  @override
  String get venuePickerLoading => 'Veranstaltungsorte werden geladen…';

  @override
  String get venuePickerUnlinkTooltip => 'Veranstaltungsort trennen';

  @override
  String get venuePickerUnresolvedTitle =>
      'Verknüpfter Veranstaltungsort nicht gefunden';

  @override
  String get venuePickerUnresolvedSubtitle =>
      'Er wurde möglicherweise gelöscht.';

  @override
  String get venuePickerClearLinkTooltip => 'Verknüpfung löschen';

  @override
  String get venuePickerSearchHint =>
      'Veranstaltungsort suchen oder hinzufügen…';

  @override
  String get venuePickerChangeHint => 'Veranstaltungsort ändern…';

  @override
  String venuePickerCreateOption(String name) {
    return 'Neuen Veranstaltungsort „$name“ hinzufügen';
  }
}
