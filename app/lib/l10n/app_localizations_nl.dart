// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Dutch Flemish (`nl`).
class AppLocalizationsNl extends AppLocalizations {
  AppLocalizationsNl([String locale = 'nl']) : super(locale);

  @override
  String get appTitle => 'Caller\'s Compendium';

  @override
  String get navCollection => 'Collectie';

  @override
  String get navPrograms => 'Programma\'s';

  @override
  String get navSettings => 'Instellingen';

  @override
  String get navGuide => 'Gids';

  @override
  String get navGuideTooltip => 'Gebruikersgids';

  @override
  String get navSearch => 'Zoeken';

  @override
  String navSearchTooltip(String hint) {
    return 'Zoeken ($hint)';
  }

  @override
  String get appBootstrapPreparing => 'Je collectie voorbereiden';

  @override
  String get appBootstrapRebuildingIndex => 'Zoekindex opnieuw opbouwen';

  @override
  String appBootstrapRebuildingIndexProgress(int percent) {
    return 'Zoekindex opnieuw opbouwen… $percent%';
  }

  @override
  String get appBootstrapError => 'De collectie kon niet worden voorbereid.';

  @override
  String get migrationDowngradeMessage =>
      'Deze gegevens zijn gemaakt met een nieuwere versie van Caller’s Compendium — werk de app bij.';

  @override
  String migrationSnapshotAbortedMessage(String cause) {
    return 'Caller’s Compendium is niet gestart omdat er geen automatische back-up kon worden gemaakt voordat je opgeslagen gegevens werden bijgewerkt. ${cause}Maak ruimte vrij (of herstel de back-upmap) en open de app dan opnieuw — of open opnieuw en kies om zonder back-up door te gaan.';
  }

  @override
  String get migrationSnapshotCauseDiskFull =>
      'Je apparaat lijkt weinig opslagruimte te hebben.';

  @override
  String get migrationSnapshotCauseUnwritableBackupsDir =>
      'Naar de automatische back-upmap kon niet worden geschreven.';

  @override
  String get migrationSnapshotConsentTitle => 'Kon je gegevens niet back-uppen';

  @override
  String migrationSnapshotConsentBody(String cause) {
    return 'Voordat je opgeslagen gegevens naar een nieuw formaat worden bijgewerkt, maakt Caller’s Compendium een automatische back-up zodat een mislukte update ongedaan kan worden gemaakt. Die back-up kon deze keer niet worden gemaakt.$cause\n\nAls je zonder back-up doorgaat en de update wordt onderbroken, kunnen sommige van je dansen of programma’s verloren gaan. Je kunt afsluiten, ruimte vrijmaken (of de back-upmap herstellen) en de app opnieuw openen om het nog eens te proberen.';
  }

  @override
  String get migrationSnapshotConsentQuit => 'Afsluiten';

  @override
  String get migrationSnapshotConsentProceed => 'Doorgaan zonder back-up';

  @override
  String get confirmDeleteTitle => 'Verwijderen?';

  @override
  String confirmDeleteBody(String itemLabel) {
    return '“$itemLabel” wordt verwijderd. Je kunt dit ongedaan maken.';
  }

  @override
  String get colorEditHexLabel => 'Hex';

  @override
  String get settingsTitle => 'Instellingen';

  @override
  String get settingsGeneralTitle => 'Algemeen';

  @override
  String get settingsAppearanceTitle => 'Weergave';

  @override
  String get settingsDialectTitle => 'Dialect';

  @override
  String get settingsDefaultsTitle => 'Standaardwaarden';

  @override
  String get settingsUpdatesTitle => 'Updates';

  @override
  String get settingsDiagnosticsTitle => 'Diagnostics';

  @override
  String get settingsAboutTitle => 'Over';

  @override
  String get commonSystemDefault => 'Systeemstandaard';

  @override
  String get commonComingSoon => 'Binnenkort beschikbaar';

  @override
  String get settingsLanguageRegionTitle => 'Taal en regio';

  @override
  String get settingsRegionalFormatsHeader => 'Opmaak';

  @override
  String get settingsRegionalLanguageHeader => 'Taal';

  @override
  String get settingsDateFormatTitle => 'Datumnotatie';

  @override
  String settingsDateFormatSubtitle(String example) {
    return 'Hoe programma-eventdata worden weergegeven. Voorbeeld: $example';
  }

  @override
  String get settingsDateFormatYmd => 'Jaar-maand-dag (2026-07-15)';

  @override
  String get settingsDateFormatDmy => 'Dag/maand/jaar (15/07/2026)';

  @override
  String get settingsDateFormatMdy => 'Maand/dag/jaar (07/15/2026)';

  @override
  String get settingsDateFormatCustom => 'Aangepast…';

  @override
  String get settingsDateFormatCustomPatternLabel => 'Aangepast datumpatroon';

  @override
  String get settingsDateFormatCustomPatternHint => 'MM.DD.YY';

  @override
  String get settingsDateFormatCustomLegend =>
      'Tokens: yyyy of yy = jaar, MM = maand (MMM = korte naam, MMMM = volledige naam), dd = dag. Scheidingstekens: - / . of spatie.';

  @override
  String get settingsDateFormatCustomInvalid =>
      'Onbekend patroon — de systeemstandaard wordt gebruikt totdat dit is gecorrigeerd.';

  @override
  String get settingsFirstDayOfWeekTitle => 'Eerste dag van de week';

  @override
  String get settingsFirstDayOfWeekSubtitle =>
      'Welke dag de week begint in de datumweergaven van de app. Komt in een toekomstige update.';

  @override
  String get settingsAppLanguageTitle => 'Apptaal';

  @override
  String get settingsAppLanguageSubtitle =>
      'Kies de taal van de app-interface.';

  @override
  String get settingsAboutHelpHeader => 'Help';

  @override
  String get settingsAboutUserGuideTitle => 'Gebruikersgids';

  @override
  String get settingsAboutUserGuideSubtitle =>
      'Lees de ingebouwde handleidingen — aan de slag, dialecten, importeren en meer. Werkt offline.';

  @override
  String get settingsAboutLicenseHeader => 'Licentie';

  @override
  String get settingsAboutLicenseBody =>
      'Caller\'s Compendium is vrije software, uitgebracht onder de GNU Affero General Public License, versie 3 (AGPL-3.0). Je mag het gebruiken, bestuderen, delen en aanpassen onder die licentie. Omdat de AGPL dit vereist, wordt de volledige bijbehorende broncode aangeboden aan iedereen die de app gebruikt.';

  @override
  String get settingsAboutViewSourceTitle => 'Broncode bekijken op GitHub';

  @override
  String get settingsAboutFontsHeader => 'Lettertypen';

  @override
  String get settingsAboutFontsBody =>
      'Deze app bevat de volgende lettertypen onder de SIL Open Font License 1.1. De volledige licentieteksten zijn beschikbaar onder “Licenties bekijken” hieronder.';

  @override
  String get settingsAboutFontFrauncesSubtitle =>
      'SIL Open Font License 1.1 · © The Fraunces Project Authors — display & koppen';

  @override
  String get settingsAboutFontAtkinsonSubtitle =>
      'SIL Open Font License 1.1 · © Braille Institute of America, Inc. — tekst, UI & uitvoeren';

  @override
  String get settingsAboutFontRobotoSubtitle =>
      'SIL Open Font License 1.1 · © The Roboto Project Authors — reservelettertype';

  @override
  String get settingsAboutThemesHeader => 'Thema\'s';

  @override
  String get settingsAboutThemesBody =>
      'Diverse optionele kleurthema\'s zijn geïnspireerd op populaire code-editorpaletten — waaronder One Dark, Dracula, Nord, Tokyo Night, Gruvbox en Catppuccin — opnieuw afgeleid en qua contrast afgestemd op deze app. Thema-namen worden alleen gebruikt om die inspiratie te erkennen.';

  @override
  String get settingsAboutDanceDataHeader => 'Dansgegevens';

  @override
  String get settingsAboutDanceDataBody =>
      'Dansgegevens zijn afkomstig van The Caller\'s Box (Chris Page & Michael Dyck), waarvan de collectie is gepubliceerd onder de Creative Commons Attribution-NonCommercial-licentie (CC BY-NC), met dankbaarheid.';

  @override
  String get settingsAboutLicensesHeader => 'Licenties';

  @override
  String get settingsAboutViewLicensesTitle => 'Licenties bekijken';

  @override
  String get settingsAboutViewLicensesSubtitle =>
      'Volledige open-source licentieteksten, inclusief de meegeleverde lettertypen.';

  @override
  String get settingsAboutLegalese =>
      '© De bijdragers van Caller\'s Compendium. Uitgebracht onder AGPL-3.0.';

  @override
  String settingsAboutVersion(String version) {
    return 'Versie $version';
  }

  @override
  String settingsAboutVersionLine(
    String appName,
    String version,
    String license,
  ) {
    return '$appName · Versie $version · $license';
  }

  @override
  String get settingsUpdatesHeader => 'Updates';

  @override
  String get settingsUpdatesCheckNowTitle => 'Controleren op updates';

  @override
  String settingsUpdatesStatusIdle(String version) {
    return 'Je gebruikt versie $version.';
  }

  @override
  String get settingsUpdatesStatusChecking => 'Controleren…';

  @override
  String settingsUpdatesStatusNoUpdate(String version) {
    return 'Geen update gevonden. Je gebruikt versie $version.';
  }

  @override
  String settingsUpdatesStatusAvailable(String version) {
    return 'Versie $version is beschikbaar. Zie de banner om het te bekijken.';
  }

  @override
  String get settingsUpdatesChannelHeader => 'Kanaal';

  @override
  String get settingsUpdatesBetaTitle => 'Bètakanaal';

  @override
  String get settingsUpdatesBetaSubtitle =>
      'Ontvang pre-release bètaupdates. Uit betekent alleen stabiele releases.';

  @override
  String get settingsUpdatesAutoHeader => 'Automatische controles';

  @override
  String get settingsUpdatesAutoTitle => 'Automatisch controleren';

  @override
  String get settingsUpdatesAutoSubtitle =>
      'Controleer bij het opstarten op een nieuwere versie op de achtergrond. Standaard uitgeschakeld.';

  @override
  String get settingsUpdatesPrivacyNote =>
      'De updatecontrole downloadt alleen een klein versiebestand via HTTPS — er worden nooit gegevens over jou, je apparaat of je gebruik verstuurd. Er wordt niets automatisch gedownload of geïnstalleerd: jij kiest wanneer je een update downloadt, het wordt geverifieerd voordat het wordt geopend, en je systeeminstaller voltooit de installatie.';

  @override
  String get settingsUpdatesDownloadingTitle => 'Update downloaden';

  @override
  String get settingsUpdatesDownloadingIndeterminate => 'Downloaden…';

  @override
  String settingsUpdatesDownloadingPercent(int percent) {
    return 'Downloaden… $percent%';
  }

  @override
  String get settingsUpdatesVerifyingTitle => 'Download verifiëren';

  @override
  String get settingsUpdatesVerifyingSubtitle =>
      'De sha256-integriteit van de download controleren…';

  @override
  String get settingsUpdatesHandoffTitle => 'Installer voorbereiden';

  @override
  String get settingsUpdatesHandoffSubtitle =>
      'De geverifieerde update wordt doorgegeven aan je systeem…';

  @override
  String get settingsUpdatesCompletedTitle => 'Update gedownload';

  @override
  String get settingsUpdatesCompletedSubtitle =>
      'Volg je systeeminstaller om het bijwerken te voltooien.';

  @override
  String get settingsUpdatesCompletedSubtitleRevealed =>
      'Geverifieerd en zichtbaar in je bestandsbeheer — voer de installer uit om het bijwerken te voltooien.';

  @override
  String get settingsUpdatesDownloadTitle => 'Update downloaden en installeren';

  @override
  String get settingsUpdatesDownloadError =>
      'De update kon niet worden gedownload.';

  @override
  String settingsUpdatesDownloadSubtitle(String version) {
    return 'Download versie $version, verifieer het en open je installer. De app vervangt zichzelf nooit ter plekke.';
  }

  @override
  String get settingsDialectHeader => 'Dialecten';

  @override
  String get settingsDialectNewButton => 'Nieuw dialect';

  @override
  String get settingsDialectNewDefaultName => 'Mijn dialect';

  @override
  String get settingsDialectCreateConfirm => 'Aanmaken';

  @override
  String get settingsDialectDuplicateFrom => 'Dupliceren van…';

  @override
  String get settingsDialectRenameTitle => 'Dialect hernoemen';

  @override
  String get settingsDialectRename => 'Hernoemen';

  @override
  String get settingsDialectEditTerms => 'Termen bewerken';

  @override
  String get settingsDialectDuplicateToCustomize =>
      'Dupliceren om aan te passen';

  @override
  String get settingsDialectDeleteTitle => 'Dialect verwijderen?';

  @override
  String settingsDialectDeleteConfirmBody(String name) {
    return '“$name” wordt permanent verwijderd.';
  }

  @override
  String get settingsDialectActionsTooltip => 'Dialectacties';

  @override
  String get settingsDialectPresetBadge => 'Voorinstelling';

  @override
  String get settingsDialectNameLabel => 'Naam';

  @override
  String get settingsAppearanceThemeHeader => 'Thema';

  @override
  String get settingsAppearanceCustomThemesHeader => 'Aangepaste thema\'s';

  @override
  String get settingsAppearanceEasterEggsHeader => 'Verrassingen';

  @override
  String get settingsAppearanceSetListsHeader => 'Setlijsten';

  @override
  String get settingsAppearanceFormationColoursHeader => 'Formatiekleuren';

  @override
  String get settingsAppearanceColourDanceTitle =>
      'Kleurbenoemde dansen kleuren het thema';

  @override
  String get settingsAppearanceColourDanceSubtitle =>
      'Een speelse verrassing: wanneer je een dans opent waarvan de titel een kleur benoemt — zoals Baby Rose of Blue Boy — wordt de weergave in die kleur getint. Standaard uitgeschakeld; bij een hoog-contrastthema wordt het automatisch uitgeschakeld zodat de leesbaarheid altijd wint.';

  @override
  String get settingsAppearanceSetListColorTitle =>
      'Setlijstrijen kleurcoderen';

  @override
  String get settingsAppearanceSetListColorSubtitle =>
      'Kleur elke dansrij op basis van diens formatiefamilie (contra, mixer, square, …). De formatie wordt ook altijd als tekst weergegeven, zodat rijen leesbaar blijven zonder kleur.';

  @override
  String get settingsAppearanceFormationColoursTitle => 'Formatielabelkleuren';

  @override
  String get settingsAppearanceFormationColoursSubtitle =>
      'Markeer individuele formaties in je eigen kleuren — bijv. Becket (CW) in geel, Becket (CCW) in roze — op danskaarten, dansdetails en de uitvoerheader.';

  @override
  String get settingsAppearanceSelectedBadge => 'Geselecteerd';

  @override
  String get settingsAppearancePreviewHeading => 'Aa Voorbeeld';

  @override
  String get settingsAppearancePreviewBody => 'Voorbeeld van tekst';

  @override
  String get settingsAppearanceNewThemeButton => 'Nieuw aangepast thema';

  @override
  String get settingsAppearanceNewThemeDefaultName => 'Mijn thema';

  @override
  String get settingsAppearanceCustomThemesEmpty =>
      'Kopieer het huidige thema en pas elke kleur aan. Aangepaste thema\'s worden op dit apparaat opgeslagen.';

  @override
  String get settingsAppearanceDeleteThemeTitle => 'Thema verwijderen?';

  @override
  String settingsAppearanceDeleteThemeBody(String name) {
    return '“$name” wordt permanent verwijderd.';
  }

  @override
  String settingsAppearanceCustomThemeSemantic(String name) {
    return 'Aangepast thema $name';
  }

  @override
  String get settingsAppearanceThemeActionsTooltip => 'Thema-acties';

  @override
  String get settingsDefaultsProgramHeader => 'Programmastandaarden';

  @override
  String get settingsDefaultsCallerLabel => 'Standaard caller';

  @override
  String get settingsDefaultsPrefilledHelper =>
      'Vooraf ingevuld in nieuwe programma\'s; aanpasbaar per programma.';

  @override
  String get settingsDefaultsBandLabel => 'Standaard band';

  @override
  String get settingsDefaultsDisplayHeader => 'Weergavestandaarden';

  @override
  String get settingsDefaultsSortTitle => 'Sorteervolgorde van de collectie';

  @override
  String get settingsDefaultsSortSubtitle =>
      'Hoe de collectie wordt gesorteerd wanneer je die opent. Je kunt de sortering nog steeds aanpassen tijdens het bladeren.';

  @override
  String get settingsDefaultsCanonicalTitle =>
      'Dansdetails openen in canonieke termen';

  @override
  String get settingsDefaultsCanonicalSubtitle =>
      'Als ingeschakeld, opent een dans met canonieke rol- en bewegingsnamen in plaats van je actieve dialect. Je kunt nog steeds van weergave wisselen terwijl de dans open is.';

  @override
  String get settingsDefaultsAuthoringHeader =>
      'Standaarden voor dansen aanmaken';

  @override
  String get settingsDefaultsFreeTextEntryTitle => 'Vrije tekstinvoer';

  @override
  String get settingsDefaultsFreeTextEntrySubtitle =>
      'Als ingeschakeld, kun je een nieuwe figuur als één regel invoeren (bijv. “neighbor balance & swing”) in plaats van veld voor veld. De regel wordt geparseerd tot figuur(en); niet-herkende delen worden bewaard als een aangepaste figuur die je later kunt corrigeren. Het bewerken van een bestaande figuur gebruikt altijd de volledige editor.';

  @override
  String get settingsDefaultsFigureShorthandsTitle => 'Figuurafkortingen';

  @override
  String get settingsDefaultsFigureShorthandsEmptySubtitle =>
      'Wijs korte tokens toe aan één of meer figuren die je kunt invoegen tijdens vrije tekstinvoer.';

  @override
  String settingsDefaultsFigureShorthandsCountSubtitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count afkortingen gedefinieerd.',
      one: '1 afkorting gedefinieerd.',
    );
    return '$_temp0';
  }

  @override
  String get settingsDefaultsFormTitle => 'Dansvorm';

  @override
  String get settingsDefaultsFormSubtitle =>
      'De dansvorm waarmee een nieuwe dans begint. Je kunt dit per dans aanpassen.';

  @override
  String get settingsDefaultsFormationTitle => 'Formatie';

  @override
  String get settingsDefaultsFormationSubtitle =>
      'De formatie waarmee een nieuwe dans begint. Je kunt dit per dans aanpassen.';

  @override
  String get settingsDefaultsProgressionTitle => 'Progressie';

  @override
  String get settingsDefaultsProgressionSubtitle =>
      'De progressie waarmee een nieuwe dans begint. Je kunt dit per dans aanpassen.';

  @override
  String get settingsDefaultsPhraseLabel => 'Standaard fraseopbouw';

  @override
  String get settingsDefaultsPhraseHelper =>
      'Ingesteld voor nieuwe dansen. Leeg = standaard 4×16 (A1 A2 B1 B2); anders bijv. 6*8*2.';

  @override
  String get settingsDefaultsStartingFiguresTitle => 'Beginfiguren';

  @override
  String get settingsDefaultsStartingFiguresSubtitle =>
      'De figuren waarmee een nieuwe dans begint. Standaard één stilstaan (8 beats); maak leeg voor een lege nieuwe dans. Aanpasbaar per dans.';

  @override
  String get settingsDefaultsMoveDefaultsTitle => 'Standaardwaarden voor moves';

  @override
  String get settingsDefaultsMoveDefaultsSubtitle =>
      'Voorkeursparameterwaarden die worden toegepast wanneer je een move invoegt bij het invoeren van een dans. Deze overschrijven de ingebouwde standaarden van die move; je kunt achteraf elk parameter van de figuur nog aanpassen. Niet-ingestelde moves en parameters gebruiken de ingebouwde standaarden.';

  @override
  String get settingsDefaultsAddMoveButton => 'Movestandaard toevoegen';

  @override
  String get settingsDefaultsRemoveMoveTooltip => 'Verwijderen';

  @override
  String get settingsDefaultsMoveGone =>
      'Deze move bevindt zich niet meer in de taxonomie.';

  @override
  String get settingsDefaultsMoveNoParams =>
      'Deze move heeft geen parameters om in te stellen.';

  @override
  String get settingsFormationColoursTitle => 'Formatiekleuren';

  @override
  String get settingsFormationColoursIntro =>
      'Geef een formatie een eigen kleur om het label te markeren op danskaarten, dansdetails en de uitvoerheader. Alleen de formaties die je aanpast worden gemarkeerd; de overige tonen hun label zoals gewoonlijk. De formatie wordt ook altijd als tekst weergegeven, zodat labels leesbaar blijven zonder kleur.';

  @override
  String get settingsFormationColoursListHeader => 'Formaties';

  @override
  String get settingsFormationColoursCustom => 'Aangepaste kleur';

  @override
  String get settingsFormationColoursFamilyDefault => 'Familiestandaard';

  @override
  String settingsFormationColoursResetTooltip(String label) {
    return '$label opnieuw instellen op de familiestandaard';
  }

  @override
  String get settingsGeneralLibraryHeader => 'Bibliotheek';

  @override
  String get settingsGeneralSortIgnoreArticlesTitle =>
      'Lidwoorden aan het begin negeren bij sorteren';

  @override
  String get settingsGeneralSortIgnoreArticlesSubtitle =>
      'Als ingeschakeld, sorteert de danslijst titels alfabetisch waarbij een voorlopend “the”, “a” of “an” wordt genegeerd — zodat “The Nice Combination” onder N valt. Uitschakelen om op de letterlijke titel te sorteren.';

  @override
  String get settingsGeneralVenuesHeader => 'Locaties';

  @override
  String get settingsGeneralVenueEntityModeTitle =>
      'Herbruikbare locatierecords gebruiken';

  @override
  String get settingsGeneralVenueEntityModeSubtitle =>
      'Maak van locaties herbruikbare records met adres, contacten en schema die veel programma\'s kunnen delen en die je op één plek bewerkt. Als uitgeschakeld, is de locatie van een programma een eenvoudig tekstveld. Omschakelen is verliesvrij — je ingetypte locatie en eventueel gekoppelde records worden beide bewaard.';

  @override
  String get settingsGeneralManageVenuesTitle => 'Locaties beheren';

  @override
  String get settingsGeneralManageVenuesSubtitle =>
      'Blader door, bewerk en verwijder je herbruikbare locatierecords.';

  @override
  String get settingsGeneralPerformanceHeader => 'Uitvoering';

  @override
  String get settingsGeneralAutoSizePerformTitle =>
      'Uitvoerkaarten automatisch schalen';

  @override
  String get settingsGeneralAutoSizePerformSubtitle =>
      'Schaal elke kaart zodat de volledige dans of het slot op het scherm past zonder scrollen. Uitschakelen om de grootte zelf in te stellen met A− / A+.';

  @override
  String get settingsGeneralCallingHistoryHeader => 'Callerhistorie';

  @override
  String get settingsGeneralRequirePerformedForHistoryTitle =>
      '“Markeer als uitgevoerd” vereisen voor callerhistorie';

  @override
  String get settingsGeneralRequirePerformedForHistorySubtitle =>
      'Als ingeschakeld, toont de callerhistorie van een dans alleen programma’s waarvan het slot voor die dans als uitgevoerd is gemarkeerd. Als uitgeschakeld, verschijnt een programma zodra het de dans bevat.';

  @override
  String get settingsGeneralTrackHistoryForAllCallersTitle =>
      'Track calling history for all callers';

  @override
  String get settingsGeneralTrackHistoryForAllCallersSubtitle =>
      'When off and a default caller is set, calling history and counts include only programs led by that caller. When on — or when no default caller is set — every program that contains the dance is tracked.';

  @override
  String get settingsGeneralAccessibilityHeader => 'Toegankelijkheid';

  @override
  String get settingsGeneralReduceMotionTitle => 'Beweging verminderen';

  @override
  String get settingsGeneralReduceMotionSubtitle =>
      'Dempt of slaat niet-essentiële animaties over, zoals geanimeerd scrollen bij het navigeren tussen zoekresultaten of figuren.';

  @override
  String get settingsGeneralVerboseFiguresTitle =>
      'Altijd volledige figuurtekst tonen';

  @override
  String get settingsGeneralVerboseFiguresSubtitle =>
      'Toon de volledige gesproken figuurtekst in de dansweergave, niet alleen aan schermlezers. Uitschakelen voor de bondige notatie.';

  @override
  String get settingsGeneralDecimalTurnsTitle => 'Draaien als decimalen tonen';

  @override
  String get settingsGeneralDecimalTurnsSubtitle =>
      'Toon draai- en rotatiehoeveelheden als decimalen (0,75) in plaats van breuken (¾). De schermlezertekst is hier niet van invloed.';

  @override
  String get settingsGeneralConfirmBeforeDeleteTitle =>
      'Bevestigen voor verwijderen';

  @override
  String get settingsGeneralConfirmBeforeDeleteSubtitle =>
      'Vraag om bevestiging voor het verwijderen van een dans of programma. Verwijderingen kunnen nog steeds ongedaan worden gemaakt; dit voegt slechts een expliciete bevestigingsstap toe.';

  @override
  String get settingsGeneralDeletedItemsHeader => 'Verwijderde items';

  @override
  String get settingsGeneralSoftDeleteRetentionTitle =>
      'Verwijderde dansen bewaren voor';

  @override
  String get settingsGeneralSoftDeleteRetentionSubtitle =>
      'Verwijderde dansen worden zo lang bewaard voordat ze bij het opstarten van de app permanent worden verwijderd. Nooit bewaart ze totdat je ze handmatig opschoont.';

  @override
  String settingsGeneralSoftDeleteRetentionDays(int days) {
    return '$days dagen';
  }

  @override
  String get settingsGeneralSoftDeleteRetentionNever => 'Nooit';

  @override
  String get settingsGeneralImportHeader => 'Importeren';

  @override
  String get settingsGeneralImportDancesSubtitle =>
      'Breng dansen in je collectie vanuit een Caller\'s Compendium JSON-bestand. Je bekijkt elke dans en bevestigt voordat er iets wordt toegevoegd.';

  @override
  String get settingsGeneralImportEllipsisAction => 'Importeren…';

  @override
  String get settingsGeneralReparseCustomFiguresTitle =>
      'Aangepaste figuren opnieuw controleren';

  @override
  String get settingsGeneralReparseCustomFiguresSubtitle =>
      'Herverwerk geïmporteerde dansen waarvan de figuren als aangepast zijn bewaard omdat ze niet herkend konden worden bij het importeren. Verbeterde verwerking actualiseert ze ter plekke — je tags, beoordelingen en notities blijven bewaard. Je bekijkt een voorbeeld en bevestigt voordat er iets wijzigt.';

  @override
  String get settingsGeneralReparseCustomFiguresAction =>
      'Opnieuw controleren…';

  @override
  String get settingsGeneralBackupRestoreHeader => 'Back-up en herstel';

  @override
  String get backupExported => 'Back-up geëxporteerd.';

  @override
  String get backupExportFailed => 'Back-up kon niet worden geëxporteerd.';

  @override
  String get backupRestoreIntegrityFailed =>
      'Deze back-up is niet door de integriteitscontrole gekomen, dus mogelijk is deze beschadigd of na het exporteren gewijzigd. Het herstel is geannuleerd en je gegevens zijn ongewijzigd.';

  @override
  String get backupRestoreIncompatibleVersion =>
      'Deze back-up bevat items die deze versie van de app niet kan lezen (mogelijk van een nieuwere versie), dus het herstel is geannuleerd. Je gegevens zijn ongewijzigd.';

  @override
  String get backupRestoreInvalidFile =>
      'Herstel mislukt: het bestand is geen geldige back-up. Je gegevens zijn ongewijzigd.';

  @override
  String backupRestoreSkippedProblems(int count) {
    return 'Back-up hersteld, $count probleem/problemen overgeslagen.';
  }

  @override
  String get backupRestored => 'Back-up hersteld.';

  @override
  String get backupRestoreFailed => 'De back-up kon niet worden hersteld.';

  @override
  String get backupRestoreSettingsFailed =>
      'Your dances and programs were restored, but applying your saved settings failed. Your restored content is safe — you can retry applying settings.';

  @override
  String get backupRestoreSettingsRetryAction => 'Retry settings';

  @override
  String get backupRestoreSettingsRetried => 'Settings applied.';

  @override
  String get backupExportTitle => 'Een back-up exporteren';

  @override
  String get backupExportSubtitle =>
      'Sla je volledige collectie, programma\'s, aangepaste velden, dialecten, thema\'s en instellingen op in één JSON-bestand dat je veilig kunt bewaren of naar een ander apparaat kunt overzetten.';

  @override
  String get backupExportAction => 'Exporteren';

  @override
  String get backupRestoreTitle => 'Herstellen vanuit een back-up';

  @override
  String get backupRestoreSubtitle =>
      'Vervang alles wat momenteel in de app staat door de inhoud van een back-upbestand. Dit kan niet ongedaan worden gemaakt.';

  @override
  String get backupRestoreAction => 'Herstellen';

  @override
  String get backupReminderTitle => 'Herinnering voor back-up';

  @override
  String get backupLastBackupNever => 'Laatste back-up: nooit';

  @override
  String backupLastBackupDate(String date) {
    return 'Laatste back-up: $date';
  }

  @override
  String get backupReminderOff => 'Uit';

  @override
  String get backupReminderWeekly => 'Wekelijks';

  @override
  String get backupReminderMonthly => 'Maandelijks';

  @override
  String get backupOverdueHint =>
      'Het is al een tijdje geleden dat je een back-up hebt gemaakt — overweeg er nu een te exporteren.';

  @override
  String get backupRestoreDialogBody =>
      'Herstellen vervangt alles in de app — je collectie, programma’s, dialecten, thema’s en instellingen — met de inhoud van de back-up. Dit kan niet ongedaan worden gemaakt.';

  @override
  String get backupChooseFileAction => 'Bestand kiezen…';

  @override
  String get backupPasteJsonLabel => 'Of plak back-up JSON';

  @override
  String get backupReplaceAllDataAction => 'Alle gegevens vervangen';

  @override
  String get diagnosticsNoDiagnosticsToExport =>
      'Geen diagnostics te exporteren.';

  @override
  String get diagnosticsScrubbedExportUnavailable =>
      'Er kon geen veilige (geredigeerde) export worden voorbereid, dus er is niets opgeslagen. Probeer het opnieuw of gebruik volledige details met opzet.';

  @override
  String get diagnosticsLogExported => 'Diagnosticslog geëxporteerd.';

  @override
  String get diagnosticsExportCancelled => 'Export geannuleerd.';

  @override
  String get diagnosticsExportFailed =>
      'Het diagnosticslog kon niet worden geëxporteerd.';

  @override
  String get diagnosticsClearLogTitle => 'Diagnosticslog wissen?';

  @override
  String get diagnosticsClearLogBody =>
      'Dit verwijdert het lokale crashlog permanent van dit apparaat. Dit kan niet ongedaan worden gemaakt.';

  @override
  String get diagnosticsClearAction => 'Wissen';

  @override
  String get diagnosticsLogCleared => 'Diagnosticslog gewist.';

  @override
  String get diagnosticsHeader => 'Diagnostics';

  @override
  String get diagnosticsIntro =>
      'Wanneer er iets misgaat, registreert de app een technische notitie in een lokaal log op dit apparaat om het probleem te helpen diagnosticeren. Dit wordt nooit ergens naartoe gestuurd — er is geen telemetrie. Je kunt het exporteren om bij een bugrapport te voegen, of op elk moment wissen.';

  @override
  String get diagnosticsRecentEntriesHeader => 'Recente vermeldingen';

  @override
  String get diagnosticsReadFailedTitle =>
      'Het diagnosticslog kon niet worden gelezen';

  @override
  String get diagnosticsReadFailedSubtitle =>
      'Het lokale log is mogelijk niet toegankelijk op dit apparaat. Je kunt nog steeds proberen het te exporteren of te wissen.';

  @override
  String get diagnosticsEmptyTitle => 'Geen fouten geregistreerd';

  @override
  String get diagnosticsEmptySubtitle =>
      'Er is niets vastgelegd op dit apparaat.';

  @override
  String get diagnosticsExportHeader => 'Exporteren';

  @override
  String get diagnosticsFullDetailTitle =>
      'Volledige details opnemen (kan je inhoud bevatten)';

  @override
  String get diagnosticsFullDetailSubtitle =>
      'Standaard uitgeschakeld. Als uitgeschakeld, verwijdert de export je inhoud, bestandspaden, e-mailadressen en telefoonnummers.';

  @override
  String get diagnosticsExportShareLogTitle => 'Log exporteren / delen';

  @override
  String get diagnosticsExportShareFullSubtitle =>
      'Deelt het volledige, ongeredigeerde log.';

  @override
  String get diagnosticsExportShareScrubbedSubtitle =>
      'Deelt een geredigeerde kopie die veilig bij een bugrapport kan worden gevoegd.';

  @override
  String get diagnosticsClearLogRowTitle => 'Log wissen';

  @override
  String get diagnosticsClearLogRowSubtitle =>
      'Het lokale crashlog van dit apparaat verwijderen.';

  @override
  String get crashFallbackTitle => 'Er is hier iets misgegaan';

  @override
  String get crashFallbackBody =>
      'Dit deel van de app heeft een onverwachte fout ondervonden en is hersteld. De details zijn opgeslagen in een lokaal diagnosticslog (Instellingen ▸ Diagnostics) dat je apparaat nooit verlaat.';

  @override
  String get crashFallbackCopied => 'Gekopieerd';

  @override
  String get crashFallbackCopyDetails => 'Details kopiëren';

  @override
  String get commonCancel => 'Annuleren';

  @override
  String get commonUndo => 'Ongedaan maken';

  @override
  String get commonRetry => 'Opnieuw proberen';

  @override
  String get commonDelete => 'Verwijderen';

  @override
  String get commonDuplicate => 'Dupliceren';

  @override
  String commonDuplicateTitleSuffix(String title) {
    return '$title (kopie)';
  }

  @override
  String get commonYes => 'Ja';

  @override
  String get commonNo => 'Nee';

  @override
  String get commonOk => 'OK';

  @override
  String get commonApply => 'Toepassen';

  @override
  String get commonCouldntOpenLink => 'Link kon niet worden geopend';

  @override
  String get commonProgression => 'Progressie';

  @override
  String get commonDanceFormContra => 'Contra';

  @override
  String get commonDanceFormEcd => 'Engels (ECD)';

  @override
  String get commonDanceFormSquare => 'Square';

  @override
  String get commonProgressionNone => 'Geen progressie';

  @override
  String get commonProgressionSingle => 'Enkelvoudig';

  @override
  String get commonProgressionDouble => 'Dubbel';

  @override
  String get commonProgressionTriple => 'Drievoudig';

  @override
  String get commonProgressionQuadruple => 'Viervoudig';

  @override
  String get commonProgressionOther => 'Overig';

  @override
  String get commonDanceStatusActive => 'Actief';

  @override
  String get commonDanceStatusDeprecated => 'Verouderd';

  @override
  String get commonDanceStatusBroken => 'Defect';

  @override
  String get commonDanceLevelBeginner => 'Beginner';

  @override
  String get commonDanceLevelIntermediate => 'Gemiddeld';

  @override
  String get commonDanceLevelAdvanced => 'Gevorderd';

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
  String get commonFormationOther => 'Overig';

  @override
  String commonFormationWithDetail(String shape, String detail) {
    return '$shape — $detail';
  }

  @override
  String get commonMixedLevel => 'Gemengd niveau';

  @override
  String commonShowDancesTaggedTooltip(String tagName) {
    return 'Dansen met tag “$tagName” tonen';
  }

  @override
  String commonDeletedSnack(String title) {
    return '“$title” verwijderd.';
  }

  @override
  String get importGapMessage =>
      'Deze aanroep kon niet worden geparseerd — woordelijk bewaard als aangepaste figuur.';

  @override
  String get importGapDialogTitle => 'Niet-herkende figuur';

  @override
  String get importGapSemanticLabel =>
      'Niet-herkende figuur. Deze aanroep kon niet worden geparseerd — woordelijk bewaard als aangepaste figuur.';

  @override
  String get collectionScreenTitle => 'Collectie';

  @override
  String get collectionNewDance => 'Nieuwe dans';

  @override
  String get collectionSearchTooltip => 'Zoeken (Ctrl/Cmd-K)';

  @override
  String get collectionSelectDancesTooltip => 'Dansen selecteren';

  @override
  String get collectionManageCustomFieldsTooltip => 'Aangepaste velden beheren';

  @override
  String get collectionRecentlyDeletedTooltip => 'Onlangs verwijderd';

  @override
  String collectionSortByTooltip(String sortLabel) {
    return 'Sorteren op ($sortLabel)';
  }

  @override
  String get collectionSortRelevance => 'Beste overeenkomst';

  @override
  String get collectionSortTitle => 'Titel';

  @override
  String get collectionSortAuthor => 'Auteur';

  @override
  String get collectionSortRecentlyAdded => 'Recent toegevoegd';

  @override
  String get collectionSortLastCalled => 'Laatste keer gecalld';

  @override
  String get collectionSortAscendingTooltip => 'Oplopend (tik voor aflopend)';

  @override
  String get collectionSortDescendingTooltip => 'Aflopend (tik voor oplopend)';

  @override
  String get collectionGroupByCategoryTooltip => 'Groeperen op categorie';

  @override
  String collectionGroupByCategoryActiveTooltip(String tag) {
    return 'Gegroepeerd op $tag';
  }

  @override
  String get collectionGroupByNone => 'Geen groepering';

  @override
  String get collectionGroupByHeader => 'Categorie';

  @override
  String get collectionGroupOther => 'Overige';

  @override
  String collectionGroupSectionSemantics(String label, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count dansen',
      one: '1 dans',
    );
    return '$label, $_temp0';
  }

  @override
  String get collectionExitSelectionTooltip => 'Selectie verlaten';

  @override
  String collectionSelectedCount(int count) {
    return '$count geselecteerd';
  }

  @override
  String get collectionAddTags => 'Tags toevoegen';

  @override
  String get collectionRemoveTags => 'Tags verwijderen';

  @override
  String get collectionSetLevel => 'Niveau instellen';

  @override
  String get collectionSearchFieldLabel => 'Dansen zoeken';

  @override
  String get collectionSearchFieldHint =>
      'Zoek titels, auteurs, figuren, notities…';

  @override
  String get collectionClearSearchTooltip => 'Zoekterm en filters wissen';

  @override
  String get collectionLoadError => 'De collectie kon niet worden geladen.';

  @override
  String collectionDuplicatedSnack(String title) {
    return 'Gedupliceerd als “$title”.';
  }

  @override
  String get collectionEmpty =>
      'Je collectie is leeg. Voeg een dans toe of importeer er een om te beginnen — of schakel Onlinezoeken hierboven in om te importeren vanuit een onlinebron.';

  @override
  String get collectionFiltersTitle => 'Filters';

  @override
  String collectionFiltersActive(int count) {
    return 'Filters ($count actief)';
  }

  @override
  String get collectionByPhraseTitle => 'Per frase';

  @override
  String collectionByPhraseActive(int count) {
    return 'Per frase ($count actief)';
  }

  @override
  String get collectionAdvancedTitle => 'Geavanceerd';

  @override
  String get collectionUseAdvancedQuery =>
      'Geavanceerde zoekopdracht gebruiken';

  @override
  String get collectionUseAdvancedQuerySubtitle =>
      'Combineer figuren en reeksen met alle / een van / geen groepen.';

  @override
  String collectionDanceCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count dansen',
      one: '1 dans',
    );
    return '$_temp0';
  }

  @override
  String get collectionSearchError =>
      'Er is iets misgegaan bij het uitvoeren van de zoekopdracht.';

  @override
  String get collectionNoResults =>
      'Geen dansen komen overeen met je zoekopdracht.';

  @override
  String get collectionBatchNoChanges => 'Geen wijzigingen';

  @override
  String collectionBatchTagged(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count dansen getagd',
      one: '1 dans getagd',
    );
    return '$_temp0';
  }

  @override
  String collectionBatchUntagged(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Tags verwijderd van $count dansen',
      one: 'Tags verwijderd van 1 dans',
    );
    return '$_temp0';
  }

  @override
  String collectionBatchLevelSet(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Niveau ingesteld voor $count dansen',
      one: 'Niveau ingesteld voor 1 dans',
    );
    return '$_temp0';
  }

  @override
  String collectionBatchLevelCleared(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Niveau gewist van $count dansen',
      one: 'Niveau gewist van 1 dans',
    );
    return '$_temp0';
  }

  @override
  String get collectionBatchMore => 'Meer batchacties';

  @override
  String get collectionSetRating => 'Beoordeling instellen';

  @override
  String get collectionAddTunes => 'Deuntjes toevoegen';

  @override
  String get collectionClearTunes => 'Deuntjes wissen';

  @override
  String get collectionEditCustomField => 'Aangepast veld bewerken';

  @override
  String collectionBatchRatingSet(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Beoordeling ingesteld voor $count dansen',
      one: 'Beoordeling ingesteld voor 1 dans',
    );
    return '$_temp0';
  }

  @override
  String collectionBatchRatingCleared(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Beoordeling gewist van $count dansen',
      one: 'Beoordeling gewist van 1 dans',
    );
    return '$_temp0';
  }

  @override
  String collectionBatchTunesAdded(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Deuntjes toegevoegd aan $count dansen',
      one: 'Deuntjes toegevoegd aan 1 dans',
    );
    return '$_temp0';
  }

  @override
  String collectionBatchTunesCleared(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Deuntjes gewist van $count dansen',
      one: 'Deuntjes gewist van 1 dans',
    );
    return '$_temp0';
  }

  @override
  String collectionBatchCustomFieldSet(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Veld bijgewerkt van $count dansen',
      one: 'Veld bijgewerkt van 1 dans',
    );
    return '$_temp0';
  }

  @override
  String collectionBatchCustomFieldCleared(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Veld gewist van $count dansen',
      one: 'Veld gewist van 1 dans',
    );
    return '$_temp0';
  }

  @override
  String collectionSelectDanceLabel(String title) {
    return '$title selecteren';
  }

  @override
  String collectionCalledBadge(int count) {
    return 'gecalld ×$count';
  }

  @override
  String collectionCalledBadgeSemantic(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count keer gecalld',
      one: '1 keer gecalld',
    );
    return '$_temp0';
  }

  @override
  String collectionRatingSemantic(int rating) {
    return 'Beoordeling: $rating van 5 sterren';
  }

  @override
  String collectionRowActionsSemantic(String title) {
    return 'Acties voor $title';
  }

  @override
  String get collectionSplitEmptyTitle => 'Selecteer een dans';

  @override
  String get collectionSplitEmptySubtitle =>
      'Kies een dans uit de lijst om de details te bekijken.';

  @override
  String get collectionFacetType => 'Type';

  @override
  String get collectionFacetFormation => 'Formatie';

  @override
  String get collectionFacetStatus => 'Status';

  @override
  String get collectionFacetLevel => 'Niveau';

  @override
  String get collectionFacetMinRating => 'Minimale beoordeling';

  @override
  String collectionFacetMinRatingChip(int min) {
    return '≥$min★';
  }

  @override
  String get collectionFacetTags => 'Tags';

  @override
  String get collectionFacetSource => 'Bron';

  @override
  String get collectionFacetAuthor => 'Auteur';

  @override
  String get collectionFacetNone =>
      'Nog geen filters beschikbaar voor deze collectie.';

  @override
  String get collectionFacetClear => 'Filters wissen';

  @override
  String collectionFacetRemoveAuthor(String name) {
    return '$name verwijderen';
  }

  @override
  String get collectionFacetAuthorSearchHint => 'Auteurs zoeken…';

  @override
  String get collectionFacetOpContains => 'bevat';

  @override
  String get collectionFacetOpEquals => 'is gelijk aan';

  @override
  String collectionFacetTextHint(String label) {
    return 'Filteren op $label…';
  }

  @override
  String get collectionFacetNumOpEq => '=';

  @override
  String get collectionFacetNumOpLt => '<';

  @override
  String get collectionFacetNumOpGt => '>';

  @override
  String get collectionFacetNumOpBetween => 'tussen';

  @override
  String get collectionFacetNumFrom => 'Van';

  @override
  String get collectionFacetNumValue => 'Waarde';

  @override
  String get collectionFacetNumTo => 'Tot';

  @override
  String get collectionByPhraseOrdinalFirst => 'eerste frase';

  @override
  String get collectionByPhraseOrdinalSecond => 'tweede frase';

  @override
  String get collectionByPhraseOrdinalThird => 'derde frase';

  @override
  String get collectionByPhraseOrdinalFourth => 'vierde frase';

  @override
  String collectionByPhraseOrdinalN(int number) {
    return 'frase $number';
  }

  @override
  String collectionByPhraseCaption(String ordinal, String label) {
    return '$ordinal (gewoonlijk $label)';
  }

  @override
  String collectionByPhraseFieldMatch(String caption) {
    return '$caption, figuren komen overeen';
  }

  @override
  String collectionByPhraseFieldExclude(String caption) {
    return '$caption, maar komen niet overeen';
  }

  @override
  String collectionByPhraseRemoveMove(String move, String field) {
    return '$move verwijderen uit $field';
  }

  @override
  String get collectionQueryMatchLabel => 'Overeenkomst';

  @override
  String get collectionQueryGroupAll => 'Alle van';

  @override
  String get collectionQueryGroupAny => 'Een van';

  @override
  String get collectionQueryGroupNone => 'Geen van';

  @override
  String get collectionQueryTheseConditions => 'deze voorwaarden';

  @override
  String get collectionQueryRemoveGroup => 'Groep verwijderen';

  @override
  String get collectionQueryEmptyGroup =>
      'Nog geen voorwaarden — voeg er hieronder een toe.';

  @override
  String get collectionQueryAddCondition => 'Een voorwaarde toevoegen';

  @override
  String get collectionQueryHasFigure => 'Heeft figuur';

  @override
  String get collectionQuerySequenceThen => 'Reeks (dan)';

  @override
  String get collectionQueryConditionGroup => 'Voorwaardegroep';

  @override
  String get collectionQueryAddButton => 'Toevoegen';

  @override
  String get collectionQueryRemoveFigure => 'Figuur verwijderen';

  @override
  String get collectionQueryThenFirst => 'Eerst';

  @override
  String get collectionQueryThenConnector => 'dan';

  @override
  String get collectionQueryThenLater => 'Later';

  @override
  String get collectionQueryRemoveSequence => 'Reeks verwijderen';

  @override
  String get collectionQueryGroupFigures => 'Figuren groeperen';

  @override
  String get collectionQueryFigureGroupMatch => 'Figuurgroepovereenkomst';

  @override
  String get collectionQueryOfTheseFigures => 'van deze figuren';

  @override
  String get collectionQuerySingleFigure => 'Enkele figuur';

  @override
  String get collectionQueryAddFigure => 'Figuur toevoegen';

  @override
  String get collectionQueryRemoveFigureGroup => 'Figuurgroep verwijderen';

  @override
  String get collectionQueryMoveLabel => 'Move';

  @override
  String get collectionQueryMoveHint => 'bijv. swing';

  @override
  String get collectionQuerySectionLabel => 'Sectie';

  @override
  String get collectionQueryAnySection => 'Elke sectie';

  @override
  String collectionQueryAnyParam(String param) {
    return 'Elke $param';
  }

  @override
  String get collectionBatchLevelUnspecified => 'Niet opgegeven (wissen)';

  @override
  String get collectionBatchLevelConfirm => 'Instellen';

  @override
  String get collectionBatchTagEmptyAdd =>
      'Nog geen tags. Maak er hieronder een aan.';

  @override
  String get collectionBatchTagEmptyRemove =>
      'De geselecteerde dansen hebben geen tags om te verwijderen.';

  @override
  String get collectionCreateTagLabel => 'Een tag aanmaken';

  @override
  String get collectionCreateTagButton => 'Tag aanmaken';

  @override
  String get collectionCreateTagError =>
      'Tag kon niet worden aangemaakt. Probeer het opnieuw.';

  @override
  String get collectionBatchTagAddConfirm => 'Toevoegen';

  @override
  String get collectionBatchTagRemoveConfirm => 'Verwijderen';

  @override
  String collectionBatchRatingStars(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sterren',
      one: '1 ster',
    );
    return '$_temp0';
  }

  @override
  String get collectionBatchRatingUnrated => 'Niet beoordeeld (wissen)';

  @override
  String get collectionBatchRatingConfirm => 'Instellen';

  @override
  String get collectionBatchTunesFieldLabel => 'Een deuntje toevoegen';

  @override
  String get collectionBatchTunesAddButton => 'Deuntje aan lijst toevoegen';

  @override
  String get collectionBatchTunesEmpty =>
      'Typ een deuntjenaam en voeg het toe aan de lijst.';

  @override
  String collectionBatchTunesRemove(String tune) {
    return '$tune uit lijst verwijderen';
  }

  @override
  String get collectionBatchTunesConfirm => 'Toevoegen';

  @override
  String get collectionBatchClearTunesConfirmTitle => 'Deuntjes wissen?';

  @override
  String get collectionBatchClearTunesConfirmBody =>
      'Dit verwijdert alle deuntjes van de geselecteerde dansen. Je kunt dit daarna ongedaan maken.';

  @override
  String get collectionBatchClearTunesConfirmButton => 'Deuntjes wissen';

  @override
  String get collectionBatchCustomFieldKeyLabel => 'Veld';

  @override
  String get collectionBatchCustomFieldClearOption => 'Dit veld wissen';

  @override
  String get collectionBatchCustomFieldEmpty =>
      'Er zijn nog geen aangepaste velden gedefinieerd.';

  @override
  String get collectionBatchCustomFieldNumberInvalid => 'Voer een getal in';

  @override
  String get collectionBatchCustomFieldConfirm => 'Toepassen';

  @override
  String get danceFiguresEmpty => 'Nog geen figuren.';

  @override
  String danceFigureBeats(int beats) {
    String _temp0 = intl.Intl.pluralLogic(
      beats,
      locale: localeName,
      other: '$beats beats',
      one: '1 beat',
    );
    return '$_temp0';
  }

  @override
  String get danceFigureProgressionSemantic => 'progressie';

  @override
  String danceFigureNote(String note) {
    return 'noot: $note';
  }

  @override
  String get danceScreenTitle => 'Dans';

  @override
  String get danceNotFound => 'Dans niet gevonden.';

  @override
  String get danceEditFab => 'Bewerken';

  @override
  String get danceDuplicateTooltip => 'Dans dupliceren';

  @override
  String get danceDeleteTooltip => 'Dans verwijderen';

  @override
  String get danceMoreActions => 'Meer acties';

  @override
  String get danceSectionFigures => 'Figuren';

  @override
  String get danceSectionCallingNotes => 'Callnotities';

  @override
  String get danceSectionWalkthrough => 'Doorloop';

  @override
  String get danceSectionTunes => 'Deuntjes';

  @override
  String get danceSectionLinks => 'Links';

  @override
  String get danceMissingRelated => '(ontbrekende dans)';

  @override
  String get danceSectionPublishedSources => 'Gepubliceerde bronnen';

  @override
  String get danceSectionCustomFields => 'Aangepaste velden';

  @override
  String get danceSectionCallingHistory => 'Callerhistorie';

  @override
  String get danceCallingHistoryEmpty => 'Nog niet opgenomen in een programma.';

  @override
  String get danceShowCanonicalTerms => 'Canonieke termen tonen';

  @override
  String get danceCanonicalToggleLabel => 'Canoniek';

  @override
  String danceProvenanceVia(String source) {
    return 'via $source';
  }

  @override
  String get danceProvenanceSourceManual => 'handmatige invoer';

  @override
  String get danceProvenanceSourceJson => 'JSON-import';

  @override
  String get danceLinkKindVideo => 'video';

  @override
  String get danceLinkKindSource => 'bronlink';

  @override
  String get danceLinkKindLink => 'link';

  @override
  String danceOpenLinkSemantic(String kind, String display) {
    return 'Open $kind: $display';
  }

  @override
  String danceOpenProgramSemantic(String title, String details) {
    return 'Programma openen: $title, $details';
  }

  @override
  String danceHalfStatsFirstHalf(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count keer gecalld in de eerste helft',
      one: '1 keer gecalld in de eerste helft',
    );
    return '$_temp0';
  }

  @override
  String danceHalfStatsSecondHalf(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count keer in de tweede helft',
      one: '1 keer in de tweede helft',
    );
    return '$_temp0';
  }

  @override
  String danceHalfStatsOpened(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'de eerste helft $count keer geopend',
      one: 'de eerste helft 1 keer geopend',
    );
    return '$_temp0';
  }

  @override
  String danceHalfStatsClosed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'de avond $count keer afgesloten (laatste dans van de tweede helft)',
      one: 'de avond 1 keer afgesloten (laatste dans van de tweede helft)',
    );
    return '$_temp0';
  }

  @override
  String danceHalfStatsSemanticLabel(String description) {
    return 'Helftverdeling: $description';
  }

  @override
  String get danceSourceUnknown => '(onbekende bron)';

  @override
  String danceSourcePage(String page) {
    return 'p. $page';
  }

  @override
  String danceSourceNumber(String number) {
    return 'nr. $number';
  }

  @override
  String danceOpenSourceLinkSemantic(String title) {
    return 'Bronlink openen: $title';
  }

  @override
  String danceSourceSemanticPrefix(String title) {
    return 'Bron: $title';
  }

  @override
  String danceOpenDanceCrossRefSemantic(String title) {
    return 'Dans openen: $title';
  }

  @override
  String get commonAddToProgram => 'Aan programma toevoegen';

  @override
  String get programsEmptyTitle => 'Nog geen programma\'s';

  @override
  String get programsAddToProgramEmptyBody =>
      'Maak een programma aan om een setlijst op te bouwen.';

  @override
  String get programsCreateWithDance =>
      'Een nieuw programma aanmaken met deze dans';

  @override
  String programsAddDanceToProgramSemantic(
    String danceTitle,
    String programTitle,
    String details,
  ) {
    return '“$danceTitle” toevoegen aan $programTitle, $details';
  }

  @override
  String programsAddedToProgramSnack(String danceTitle, String programTitle) {
    return '“$danceTitle” toegevoegd aan $programTitle.';
  }

  @override
  String get programsNewProgram => 'Nieuw programma';

  @override
  String programsCreatedProgramSnack(String programTitle, String danceTitle) {
    return '“$programTitle” aangemaakt met “$danceTitle”.';
  }

  @override
  String get dancePerformTooltip => 'Deze dans uitvoeren';

  @override
  String get commonSwitchDialectTooltip => 'Dialect wisselen';

  @override
  String get programsStatusDraft => 'Concept';

  @override
  String get programsStatusFinalized => 'Definitief';

  @override
  String get programsStatusPerformed => 'Uitgevoerd';

  @override
  String get programsNoLongerExists => 'Dit programma bestaat niet meer.';

  @override
  String get programsFallbackTitle => 'Programma';

  @override
  String get programsUntitledDanceFallback => 'dans';

  @override
  String programsAddedDanceSnack(String title) {
    return '“$title” toegevoegd.';
  }

  @override
  String programsAddedDanceAnnounce(String title) {
    return '$title toegevoegd aan programma.';
  }

  @override
  String get programsAddedNoteAnnounce => 'Notitie toegevoegd aan programma.';

  @override
  String get programsAddedBreakAnnounce => 'Pauze toegevoegd aan programma.';

  @override
  String get programsMarkedAllPerformed =>
      'Alle dansen gemarkeerd als uitgevoerd.';

  @override
  String programsSavedSnack(String title) {
    return '“$title” opgeslagen.';
  }

  @override
  String get programsSaveError => 'Het programma kon niet worden opgeslagen.';

  @override
  String programsDuplicatedSnack(String title) {
    return 'Gedupliceerd als “$title”.';
  }

  @override
  String programsDeletedSnack(String title) {
    return '“$title” verwijderd.';
  }

  @override
  String get programsDiscardTitle => 'Wijzigingen verwerpen?';

  @override
  String get programsDiscardBody =>
      'Je hebt niet-opgeslagen wijzigingen in dit programma.';

  @override
  String get programsKeepEditing => 'Doorgaan met bewerken';

  @override
  String get programsDiscard => 'Verwerpen';

  @override
  String get programsDraftTitle => 'Niet-opgeslagen concept';

  @override
  String get programsDraftBody =>
      'Je hebt een niet-opgeslagen concept voor dit programma. Wil je het herstellen?';

  @override
  String get programsDraftRestore => 'Herstellen';

  @override
  String get programsDraftDiscard => 'Verwerpen';

  @override
  String get programsBuildProgram => 'Programma opbouwen';

  @override
  String get programsBuildTab => 'Opbouwen';

  @override
  String get programsMatrixTab => 'Matrix';

  @override
  String get programsPerformTooltip => 'Dit programma uitvoeren';

  @override
  String get programsMarkAllPerformedTooltip => 'Alles markeren als uitgevoerd';

  @override
  String get programsSaveDirty => 'Opslaan *';

  @override
  String get commonSave => 'Opslaan';

  @override
  String get programsLoading => 'Programma laden';

  @override
  String get programsLoadError => 'Het programma kon niet worden geladen.';

  @override
  String get programsDeletedDanceFallback => '(verwijderde dans)';

  @override
  String get programsSlotsLabel => 'Slots';

  @override
  String get programsAddDanceButton => 'Dans toevoegen';

  @override
  String get programsAddNoteBreakButton => 'Notitie / pauze toevoegen';

  @override
  String get programsInsertBreakButton => 'Pauze invoegen';

  @override
  String get programsAddADanceSheetTitle => 'Een dans toevoegen';

  @override
  String get commonClose => 'Sluiten';

  @override
  String get programsNoDateSet => 'Geen datum ingesteld';

  @override
  String get programsTitleLabel => 'Titel';

  @override
  String get programsTitleHint => 'bijv. Vrijdagavond Contra';

  @override
  String get programsTitleRequired => 'Een titel is vereist.';

  @override
  String get programsEventDateLabel => 'Eventdatum';

  @override
  String get programsSetDate => 'Datum instellen';

  @override
  String get programsChangeDate => 'Wijzigen';

  @override
  String get programsClearEventDate => 'Eventdatum wissen';

  @override
  String get programsVenueLabel => 'Locatie';

  @override
  String get programsVenueHint => 'bijv. Dorpshuis';

  @override
  String programsVenueLinkedHint(String venueName) {
    return 'Ook gekoppeld aan opgeslagen locatie: $venueName. Schakel herbruikbare locaties in bij Instellingen om het te bekijken of te wijzigen.';
  }

  @override
  String get programsVenueLinkedHintFallbackName => 'een opgeslagen locatie';

  @override
  String programsVenueLegacyTextHint(String venueText) {
    return 'Eerder ingevoerde locatie: “$venueText”. Koppel hieronder een opgeslagen locatie om herbruikbare gegevens te gebruiken — je ingetypte locatie blijft bewaard.';
  }

  @override
  String get programsBandLabel => 'Band';

  @override
  String get programsBandHint => 'bijv. The Fiddleheads';

  @override
  String get programsCallerLabel => 'Caller';

  @override
  String get programsCallerHint => 'Hoofdcaller voor het event';

  @override
  String get programsDancerLevelLabel => 'Dansersniveau';

  @override
  String get programsDancerLevelHint => 'bijv. Iedereen welkom, Ervaren';

  @override
  String get programsNotesLabel => 'Notities';

  @override
  String get programsStatusFieldLabel => 'Status';

  @override
  String get programsHideAlternatesTitle =>
      'Alternatieven verbergen in de setlijst';

  @override
  String get programsHideAlternatesSubtitle =>
      'Laat ALT-slots weg uit de samenvatting, PDF en geëxporteerde setlijst. De opbouwer toont nog steeds elk slot.';

  @override
  String programsWarningCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count waarschuwingen',
      one: '1 waarschuwing',
    );
    return '$_temp0';
  }

  @override
  String get programsAddNoteBreakDialogTitle => 'Notitie of pauze toevoegen';

  @override
  String get programsFreeTextLabel => 'Tekst';

  @override
  String get programsFreeTextHint => 'bijv. Pauze, wals, aankondiging';

  @override
  String get commonAdd => 'Toevoegen';

  @override
  String get programsTitle => 'Programma\'s';

  @override
  String get programsSortTitle => 'Titel';

  @override
  String get programsSortRecentlyUpdated => 'Recent bijgewerkt';

  @override
  String get programsSortEventDate => 'Eventdatum';

  @override
  String programsSortByTooltip(String label) {
    return 'Sorteren op ($label)';
  }

  @override
  String get programsListLoadError =>
      'Je programma\'s konden niet worden geladen.';

  @override
  String get programsListEmptyBody =>
      'Bouw hier setlijsten voor je events. Maak je eerste programma aan om te beginnen.';

  @override
  String programsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count programma\'s',
      one: '1 programma',
    );
    return '$_temp0';
  }

  @override
  String get programsSummaryTitle => 'Programma';

  @override
  String get programsEditProgram => 'Programma bewerken';

  @override
  String get programsSummaryUnavailable =>
      'Dit programma is niet meer beschikbaar.';

  @override
  String get programsPerformDisabledTooltip =>
      'Voeg ten minste één slot toe om dit programma uit te voeren';

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
    return 'Setlijst ($count)';
  }

  @override
  String get programsSummaryEmptySetList =>
      'Nog geen slots — open de opbouwer om dansen toe te voegen.';

  @override
  String programsSummaryGuest(String caller) {
    return 'Gast: $caller';
  }

  @override
  String programsPlannedMinutes(int minutes) {
    return '$minutes min';
  }

  @override
  String get programsAltBadge => 'Alt';

  @override
  String get programsDanceUnavailable => 'Dans niet beschikbaar';

  @override
  String programsSummaryNote(String note) {
    return 'Noot: $note';
  }

  @override
  String programsSummaryAlternateSemantic(String title) {
    return 'Alternatief: $title';
  }

  @override
  String get programsPerformed => 'Uitgevoerd';

  @override
  String programsSlotCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count slots',
      one: '1 slot',
    );
    return '$_temp0';
  }

  @override
  String get programsSlotNoteFallback => 'Noot';

  @override
  String get programsSlotEditorEmpty =>
      'Nog geen slots. Voeg een dans of een noot toe om te beginnen.';

  @override
  String get programsSlotMoved => 'Slot verplaatst.';

  @override
  String get programsSlotMovedUp => 'Slot omhoog verplaatst.';

  @override
  String get programsSlotMovedDown => 'Slot omlaag verplaatst.';

  @override
  String programsSlotCutBanner(String name) {
    return '“$name” is geknipt — tik op Plakken om het te plaatsen.';
  }

  @override
  String get programsPasteBeforeFirst => 'Plakken vóór het eerste slot';

  @override
  String programsPasteAfter(String title) {
    return 'Plakken na $title';
  }

  @override
  String get programsPasteHere => 'Hier plakken';

  @override
  String get programsMarkedPrimary => 'Gemarkeerd als primair.';

  @override
  String get programsMarkedAlternate => 'Gemarkeerd als alternatief.';

  @override
  String get programsMarkedPerformed => 'Gemarkeerd als uitgevoerd.';

  @override
  String get programsPerformedCleared => 'Uitvoermarkering gewist.';

  @override
  String programsRemovedSlot(String name) {
    return '$name verwijderd.';
  }

  @override
  String get programsAltOrdinal => 'ALT';

  @override
  String programsDragToReorder(String title) {
    return '$title slepen om te herordenen';
  }

  @override
  String programsMoveSlotUp(String title) {
    return '$title omhoog verplaatsen';
  }

  @override
  String programsMoveSlotDown(String title) {
    return '$title omlaag verplaatsen';
  }

  @override
  String programsCutSlot(String title) {
    return '$title knippen';
  }

  @override
  String programsMoreActionsForSlot(String title) {
    return 'Meer acties voor $title';
  }

  @override
  String get programsEditSlotMenu => 'Slot bewerken';

  @override
  String get programsMakePrimaryMenu => 'Als primair instellen';

  @override
  String get programsMarkAlternateMenu => 'Markeren als alternatief';

  @override
  String get programsClearPerformedMenu => 'Uitvoering wissen';

  @override
  String get programsMarkPerformedMenu => 'Markeren als uitgevoerd';

  @override
  String get programsRemoveSlotMenu => 'Slot verwijderen';

  @override
  String get programsSlotTextRequiredError =>
      'Voer wat tekst in voor dit slot.';

  @override
  String get programsWholeNumberError => 'Voer een geheel getal ≥ 0 in.';

  @override
  String get programsEditDanceSlotTitle => 'Dansslot bewerken';

  @override
  String get programsEditNoteTitle => 'Noot bewerken';

  @override
  String get programsCallerNoteLabel => 'Callernoot (optioneel)';

  @override
  String get programsCallerNoteHint => 'bijv. leer de hey eerst';

  @override
  String get programsGuestCallerLabel => 'Gastcaller (optioneel)';

  @override
  String get programsPlannedMinutesLabel => 'Geplande minuten (optioneel)';

  @override
  String get programsAlternateDanceTitle => 'Alternatieve dans';

  @override
  String get programsAlternateDanceSubtitle =>
      'Wordt ingesprongen weergegeven onder het slot erboven.';

  @override
  String get commonDone => 'Klaar';

  @override
  String programsMatrixSemanticLabel(int danceCount, int moveCount) {
    return 'Programmeringsmatrix: $danceCount dansen bij $moveCount moves';
  }

  @override
  String programsMatrixOmittedCaption(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count vrije-tekstslots',
      one: '1 vrije-tekstslot',
    );
    return '$_temp0 (pauzes, noten) weggelaten — de matrix toont alleen dansen.';
  }

  @override
  String programsMatrixMoveHeaderSemantic(String label) {
    return 'Move: $label';
  }

  @override
  String programsMatrixRowHeaderSemantic(
    String title,
    String alt,
    String half,
  ) {
    String _temp0 = intl.Intl.selectLogic(half, {
      'first': 'Alternatieve dans: $title, eerste helft',
      'second': 'Alternatieve dans: $title, tweede helft',
      'other': 'Alternatieve dans: $title',
    });
    String _temp1 = intl.Intl.selectLogic(half, {
      'first': 'Dans: $title, eerste helft',
      'second': 'Dans: $title, tweede helft',
      'other': 'Dans: $title',
    });
    String _temp2 = intl.Intl.selectLogic(alt, {
      'yes': '$_temp0',
      'other': '$_temp1',
    });
    return '$_temp2';
  }

  @override
  String programsMatrixHalfShort(String half) {
    String _temp0 = intl.Intl.selectLogic(half, {'first': '1e', 'other': '2e'});
    return '$_temp0';
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
      'yes': ', herhaalt in dezelfde frase als een aangrenzende dans',
      'other': '',
    });
    String _temp1 = intl.Intl.selectLogic(debut, {
      'yes': ', hier geïntroduceerd',
      'other': '',
    });
    String _temp2 = intl.Intl.selectLogic(first, {
      'yes': ', eerste figuur van de dans',
      'other': '',
    });
    String _temp3 = intl.Intl.selectLogic(present, {
      'no': 'niet aanwezig',
      'other': 'aanwezig$_temp0$_temp1$_temp2',
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
      'first': '$title (alternatieve dans, eerste helft)',
      'second': '$title (alternatieve dans, tweede helft)',
      'other': '$title (alternatieve dans)',
    });
    String _temp1 = intl.Intl.selectLogic(half, {
      'first': '$title (eerste helft)',
      'second': '$title (tweede helft)',
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
    return 'Move: $label, gebruikt in $count van $total dansen';
  }

  @override
  String programsMatrixNOfTotal(int count, int total) {
    return '$count van $total';
  }

  @override
  String get programsMatrixNoComparableMoves =>
      'Geen van deze dansen heeft nog gestructureerde figuren, dus er zijn geen moves om te vergelijken.';

  @override
  String get programsMatrixRepeatedMovesHeader => 'Herhaalde moves';

  @override
  String get programsMatrixRepeatedMovesSubtitle =>
      'Moves die in twee of meer dansen voorkomen, meest herhaald eerst.';

  @override
  String get programsMatrixNoRepeatsNote =>
      'Geen moves herhalen zich in deze dansen — elke onderstaande move wordt door één dans gebruikt.';

  @override
  String get programsMatrixUsedOnceHeader => 'Eenmaal gebruikt';

  @override
  String get programsMatrixLegendIntroduced => 'Hier geïntroduceerd';

  @override
  String get programsMatrixLegendFirstFigure => 'Eerste figuur van de dans';

  @override
  String get programsMatrixLegendPresent => 'Aanwezig';

  @override
  String get programsMatrixLegendCollision =>
      'Zelfde frase als aangrenzende dans';

  @override
  String get programsMatrixEmptyTitle => 'Nog geen gestructureerde figuren';

  @override
  String get programsMatrixEmptyBody =>
      'De matrix wordt automatisch gevuld naarmate de dansen in het programma gestructureerde figuren krijgen.';

  @override
  String get performTitle => 'Uitvoeren';

  @override
  String get performExitTooltip => 'Uitvoerweergave verlaten';

  @override
  String get performExitTitle => 'Uitvoeren verlaten?';

  @override
  String get performExitBody =>
      'De uitvoerweergave verlaten? Je plek en de lopende klok worden bewaard, zodat je kunt hervatten waar je gebleven was.';

  @override
  String get performExitCancel => 'Doorgaan met uitvoeren';

  @override
  String get performExitConfirm => 'Verlaten';

  @override
  String get performTapTempo => 'Tap-tempo';

  @override
  String performBpmReadout(int bpm) {
    return '$bpm BPM';
  }

  @override
  String get performTapToSetTempo => 'Tik om tempo in te stellen';

  @override
  String performBpmSemantic(int bpm) {
    return '$bpm slagen per minuut';
  }

  @override
  String get performNoTempoSemantic =>
      'Nog geen tempo ingesteld. Tik op het doel om een tempo in te stellen.';

  @override
  String get performRecordBeatHint => 'een slag opnemen';

  @override
  String get performTapRefineHint =>
      'Blijf tikken om te verfijnen · Reset om opnieuw te beginnen';

  @override
  String get performTapTwiceHint => 'Tik ten minste twee keer mee op de maat';

  @override
  String get performResetTempo => 'Reset';

  @override
  String get performUntitledSlot => 'Naamloos slot';

  @override
  String performMarkedPerformedAnnounce(String label) {
    return '$label gemarkeerd als uitgevoerd';
  }

  @override
  String get performClearedPerformedAnnounce => 'Uitvoermarkering gewist';

  @override
  String performMovedToPosition(String label, int position) {
    return '$label verplaatst naar positie $position';
  }

  @override
  String get performDanceFallback => 'dans';

  @override
  String performInsertedAnnounce(String title) {
    return '$title ingevoegd';
  }

  @override
  String get performAddedNoteAnnounce => 'Noot toegevoegd';

  @override
  String get performInsertADance => 'Een dans invoegen';

  @override
  String get performAdjustProgram => 'Programma aanpassen';

  @override
  String get performCurrentSlotSection => 'Huidig slot';

  @override
  String get performPerformedTapToClear => 'Uitgevoerd — tik om te wissen';

  @override
  String get performReorderSection => 'Resterende slots herordenen';

  @override
  String get performNoLaterSlots => 'Geen latere slots om te herordenen.';

  @override
  String get performInsertDanceFromSearch => 'Dans invoegen via zoeken';

  @override
  String get performAdHocNoteLabel => 'Improvisatienoot / pauze';

  @override
  String get performAdHocNoteHint => 'bijv. Wals, aankondigingen';

  @override
  String get performAddNote => 'Noot toevoegen';

  @override
  String performAlternatesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count alternatieven',
      one: '1 alternatief',
    );
    return '$_temp0';
  }

  @override
  String performMoveLabelUp(String label) {
    return '“$label” omhoog verplaatsen';
  }

  @override
  String performMoveLabelDown(String label) {
    return '“$label” omlaag verplaatsen';
  }

  @override
  String performSlotPosition(int current, int total) {
    return 'Slot $current van $total';
  }

  @override
  String performShowingSlot(String label) {
    return '$label tonen';
  }

  @override
  String get performAdjustmentUndone => 'Aanpassing ongedaan gemaakt';

  @override
  String get performProgramAdjustedSnack => 'Programma aangepast.';

  @override
  String get performProgramAdjustedAnnounce => 'Programma aangepast';

  @override
  String get performNoSlots => 'Dit programma heeft geen slots.';

  @override
  String get performJumpToSlot => 'Naar slot springen';

  @override
  String get performShowAlternate => 'Alternatief tonen';

  @override
  String get performPreviousSlot => 'Vorig slot';

  @override
  String get performNextSlot => 'Volgend slot';

  @override
  String get performResumeTimers => 'Timers hervatten';

  @override
  String get performPauseTimers => 'Timers pauzeren';

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
      other: '$planned minuten',
      one: '1 minuut',
    );
    String _temp1 = intl.Intl.selectLogic(hasPlanned, {
      'yes': ', gepland $_temp0',
      'other': '',
    });
    String _temp2 = intl.Intl.selectLogic(over, {
      'yes': ', over gepland',
      'other': '',
    });
    String _temp3 = intl.Intl.selectLogic(paused, {
      'yes': ', gepauzeerd',
      'other': '',
    });
    return 'Programmatijd $programTime, slottijd $slotTime$_temp1$_temp2$_temp3';
  }

  @override
  String performPlannedMin(int planned) {
    return 'gepland $planned min';
  }

  @override
  String get performOverSuffix => ' over';

  @override
  String get performCallingNotes => 'Callnotities';

  @override
  String get performWalkthrough => 'Doorloop';

  @override
  String get performShowWalkthrough => 'Doorloop tonen';

  @override
  String get performWalkthroughEmpty => 'Geen doorloop voor deze dans.';

  @override
  String get performNoFigures => 'Nog geen figuren.';

  @override
  String get performDecreaseTextSize => 'Tekstgrootte verkleinen';

  @override
  String get performIncreaseTextSize => 'Tekstgrootte vergroten';

  @override
  String get performShowCanonicalTerms => 'Canonieke termen tonen';

  @override
  String get performMoreActions => 'Meer acties';

  @override
  String get performAutoSizeMenuLabel =>
      'Tekst automatisch aanpassen aan scherm';

  @override
  String get performAutoSizeOnTooltip =>
      'Automatisch schalen aan — tik voor handmatige tekstgrootte';

  @override
  String get performAutoSizeOffTooltip =>
      'Automatisch schalen uit — tik om tekst aan scherm aan te passen';

  @override
  String get performStageThemeOnTooltip =>
      'Podiumthema aan — tik voor app-thema';

  @override
  String get performStageThemeOffTooltip =>
      'Podiumthema uit — tik voor donker podium';

  @override
  String get performProgression => 'Progressie';

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
      'yes': ', progressie',
      'other': '',
    });
    String _temp2 = intl.Intl.pluralLogic(
      beats,
      locale: localeName,
      other: '$beats beats',
      one: '1 beat',
    );
    String _temp3 = intl.Intl.selectLogic(hasNote, {
      'yes': ', noot: $note',
      'other': '',
    });
    return '$main$_temp0$_temp1, $_temp2$_temp3';
  }

  @override
  String get programsSelectTitle => 'Een programma selecteren';

  @override
  String get programsSelectBody =>
      'Kies een programma uit de lijst of maak een nieuw programma aan.';

  @override
  String get commonEdit => 'Bewerken';

  @override
  String get commonChange => 'Wijzigen';

  @override
  String get commonTryAgain => 'Opnieuw proberen';

  @override
  String get exportTooltip => 'Exporteren';

  @override
  String get exportShareDanceText => 'Dans delen (tekst)';

  @override
  String get exportCopyDance => 'Dans kopiëren';

  @override
  String get exportPrintPdf => 'Exporteren / afdrukken als PDF';

  @override
  String get exportDanceCopied => 'Dans gekopieerd naar klembord.';

  @override
  String get exportShareDanceError => 'Deze dans kon niet worden gedeeld';

  @override
  String get exportDanceError => 'Deze dans kon niet worden geëxporteerd';

  @override
  String get exportShareSetListText => 'Setlijst delen (tekst)';

  @override
  String get exportShareProgramBundle => 'Delen (programma + dansen)';

  @override
  String get exportCopySetList => 'Setlijst kopiëren';

  @override
  String get exportSetListCopied => 'Setlijst gekopieerd naar klembord.';

  @override
  String get exportShareSetListError => 'Deze setlijst kon niet worden gedeeld';

  @override
  String get exportShareProgramError => 'Dit programma kon niet worden gedeeld';

  @override
  String get exportSetListError => 'Deze setlijst kon niet worden geëxporteerd';

  @override
  String get exportMatrixPdfTooltip => 'Matrix exporteren of afdrukken als PDF';

  @override
  String get exportMatrixPdfFilename => 'Programmeringsmatrix';

  @override
  String get exportLabelFormation => 'Formatie';

  @override
  String get exportLabelLevel => 'Niveau';

  @override
  String get exportLabelStatus => 'Status';

  @override
  String get exportLabelPhrase => 'Frase';

  @override
  String get exportLabelFigures => 'Figuren';

  @override
  String get exportLabelCallingNotes => 'Callnotities';

  @override
  String get exportLabelWalkthrough => 'Doorloop';

  @override
  String exportBeatsLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count beats',
      one: '1 beat',
    );
    return '$_temp0';
  }

  @override
  String get exportLevelMixedOnly => 'Gemengd';

  @override
  String exportLevelWithMixed(String level) {
    return '$level (gemengd)';
  }

  @override
  String get exportLabelBand => 'Band';

  @override
  String get exportLabelCaller => 'Caller';

  @override
  String get exportLabelNotes => 'Notities';

  @override
  String get exportLabelAlt => 'ALT';

  @override
  String get exportLabelGuest => 'gast';

  @override
  String get exportLabelPerformed => 'uitgevoerd';

  @override
  String get exportUnknownDanceLabel => 'Naamloze dans';

  @override
  String exportMinutesLabel(int count) {
    return '$count min';
  }

  @override
  String get exportLabelVenue => 'Locatie';

  @override
  String get exportLabelTime => 'Tijdstip';

  @override
  String get exportLabelSchedule => 'Schema';

  @override
  String get exportLabelPrice => 'Prijs';

  @override
  String get exportLabelSponsor => 'Sponsor';

  @override
  String get exportMatrixDefaultTitle => 'Programmeringsmatrix';

  @override
  String get exportMatrixDanceColumn => 'Dans';

  @override
  String get exportMatrixEmptyState =>
      'Nog geen gestructureerde figuren — de matrix wordt automatisch gevuld naarmate de dansen in het programma gestructureerde figuren krijgen.';

  @override
  String get exportMatrixLegendDebut => 'Hier geïntroduceerd';

  @override
  String get exportMatrixLegendFirst => 'Eerste figuur van de dans';

  @override
  String get exportMatrixLegendPresent => 'Aanwezig';

  @override
  String get exportMatrixLegendCollision =>
      'Zelfde frase als aangrenzende dans';

  @override
  String exportMatrixOmittedCaption(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count vrije-tekstslots',
      one: '1 vrije-tekstslot',
    );
    return '$_temp0 (pauzes, noten) weggelaten — de matrix toont alleen dansen.';
  }

  @override
  String get exportVenueContactTitle =>
      'Locatiecontactgegevens opnemen in deze export?';

  @override
  String get exportVenueContactBody =>
      'Dit zijn persoonlijke contactgegevens van de locatie. Ze worden weggelaten uit deze export tenzij je kiest ze op te nemen.';

  @override
  String get exportVenueContactConfirm => 'Doorgaan';

  @override
  String get exportVenueContact1Name => 'Contactpersoon 1 naam';

  @override
  String get exportVenueContact1Phone => 'Contactpersoon 1 telefoon';

  @override
  String get exportVenueContact1Email => 'Contactpersoon 1 e-mail';

  @override
  String get exportVenueContact2Name => 'Contactpersoon 2 naam';

  @override
  String get exportVenueContact2Phone => 'Contactpersoon 2 telefoon';

  @override
  String get exportVenueContact2Email => 'Contactpersoon 2 e-mail';

  @override
  String get onlineSearchToggleTitle => 'Online zoeken';

  @override
  String get onlineSearchToggleSubtitle =>
      'Zoek online en importeer dansen direct (vereist internet). Lokale filters zijn niet van toepassing.';

  @override
  String onlineSearchFieldLabel(String source) {
    return 'Zoeken in $source';
  }

  @override
  String get onlineSearchFieldHint => 'Zoek online dansen op titel…';

  @override
  String onlineResultCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count online resultaten',
      one: '1 online resultaat',
    );
    return '$_temp0';
  }

  @override
  String onlineSearchHintByPhrase(String source) {
    return 'Typ een titel of voeg per-frase-figuren toe om in $source te zoeken.';
  }

  @override
  String onlineSearchHintTitle(String source) {
    return 'Typ een titel om in $source te zoeken.';
  }

  @override
  String onlineNoResults(String source) {
    return 'Geen dansen op $source komen overeen met je zoekopdracht.';
  }

  @override
  String onlineLoadError(String source) {
    return 'Die dans kon niet worden geladen van $source.';
  }

  @override
  String get onlineImportError => 'Die dans kon niet worden geïmporteerd.';

  @override
  String onlineSearchFailed(String source) {
    return 'Kon $source niet doorzoeken. Probeer het opnieuw.';
  }

  @override
  String onlineImportCreated(String title) {
    return '“$title” geïmporteerd.';
  }

  @override
  String onlineImportAlreadyInCollection(String title) {
    return '“$title” staat al in je collectie.';
  }

  @override
  String get onlineAttributionCallersBox => 'Van The Caller\'s Box (online)';

  @override
  String get onlineAttributionContraDb => 'Van ContraDB (online)';

  @override
  String get importDances => 'Dansen importeren';

  @override
  String get importAction => 'Importeren';

  @override
  String get importProgramTooltip => 'Programma importeren';

  @override
  String get importFromTitleList => 'Van titellijst';

  @override
  String get importFromContraDb => 'Van ContraDB';

  @override
  String get importProgramTitleLabel => 'Programmatitel';

  @override
  String get importProgramCreateError =>
      'Het geïmporteerde programma kon niet worden opgeslagen.';

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
      other: '$slots slots',
      one: '1 slot',
    );
    String _temp1 = intl.Intl.pluralLogic(
      notes,
      locale: localeName,
      other: '$notes noten',
      one: '1 noot',
    );
    return '“$title” geïmporteerd — $_temp0 ($linked gekoppeld, $_temp1).';
  }

  @override
  String get importContraDbTitle => 'Importeren vanuit ContraDB';

  @override
  String get importContraDbPasteUrl => 'URL plakken';

  @override
  String get importContraDbSearchByName => 'Zoeken op naam';

  @override
  String get importContraDbUrlLabel => 'ContraDB-programma-URL';

  @override
  String get importContraDbUrlHint => 'bijv. https://contradb.com/programs/33';

  @override
  String get importContraDbFetching => 'Ophalen…';

  @override
  String get importContraDbFetch => 'Programma ophalen';

  @override
  String get importContraDbSearchLabel => 'ContraDB-programma\'s zoeken';

  @override
  String get importContraDbSearchHint => 'Typ een deel van een programmanaam';

  @override
  String get importContraDbListError =>
      'De ContraDB-programmalijst kon niet worden geladen.';

  @override
  String get importContraDbSearchPrompt =>
      'Typ een deel van een programmanaam om in ContraDB te zoeken.';

  @override
  String get importContraDbNoMatches => 'Geen overeenkomende programma\'s.';

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
    return 'Dat programma kon niet worden opgehaald.\n$error';
  }

  @override
  String get importContraDbFetchGenericError =>
      'Dat programma kon niet worden opgehaald.';

  @override
  String get importContraDbPastePrompt =>
      'Plak hierboven een ContraDB-programma-URL en tik op “Programma ophalen”.';

  @override
  String get importContraDbEmptyProgram =>
      'Geen dansen of noten gevonden op die programmapagina.';

  @override
  String get importContraDbResolveError =>
      'Het ContraDB-programma kon niet worden geïmporteerd.';

  @override
  String importContraDbActivityCount(int activities, int dances, int notes) {
    String _temp0 = intl.Intl.pluralLogic(
      activities,
      locale: localeName,
      other: '$activities activiteiten',
      one: '1 activiteit',
    );
    String _temp1 = intl.Intl.pluralLogic(
      dances,
      locale: localeName,
      other: '$dances dansen',
      one: '1 dans',
    );
    String _temp2 = intl.Intl.pluralLogic(
      notes,
      locale: localeName,
      other: '$notes noten',
      one: '1 noot',
    );
    return '$_temp0 ($_temp1, $_temp2)';
  }

  @override
  String get importContraDbDanceFallback => 'ContraDB-dans';

  @override
  String get importEventDateNone => 'Geen datum ingesteld';

  @override
  String get importEventDateLabel => 'Eventdatum';

  @override
  String get importEventDateSet => 'Datum instellen';

  @override
  String get importEventDateClear => 'Eventdatum wissen';

  @override
  String get importEventDateDetected =>
      'Datum gedetecteerd uit titel — controleer het voor het importeren.';

  @override
  String get importTitleListTitle => 'Importeren van titellijst';

  @override
  String get importCollectionLoadError =>
      'Je collectie kon niet worden geladen.';

  @override
  String get importTitleListDancesLabel => 'Danstitels (één per regel)';

  @override
  String get importTitleListDancesHint =>
      'Plak één danstitel per regel.\nNiet-herkende regels worden als noten bewaard.';

  @override
  String get importTitleListEmptyHint =>
      'Plak hierboven een lijst van danstitels voor een voorbeeld van het programma.';

  @override
  String get importResolving => 'Zoeken…';

  @override
  String get importResolveOnline => 'Niet-gekoppelde online zoeken';

  @override
  String get importPlaintextImportedOnline => 'Geïmporteerd uit Caller\'s Box';

  @override
  String get importPlaintextLinked => 'Gekoppeld aan dans';

  @override
  String get importPlaintextAmbiguous =>
      'Meerdere overeenkomsten — als noot toegevoegd';

  @override
  String get importPlaintextUnmatched =>
      'Geen overeenkomst — als noot toegevoegd';

  @override
  String get importPlaintextSearchError =>
      'The Caller\'s Box kon niet worden doorzocht.';

  @override
  String importPlaintextSlotCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count slots',
      one: '1 slot',
    );
    return '$_temp0';
  }

  @override
  String importPlaintextResolvedNone(int remaining) {
    String _temp0 = intl.Intl.pluralLogic(
      remaining,
      locale: localeName,
      other: '$remaining titels als noten bewaard',
      one: '$remaining titel als noot bewaard',
    );
    return 'Geen betrouwbare overeenkomsten van Caller\'s Box gevonden — $_temp0.';
  }

  @override
  String importPlaintextResolvedLinked(int linked, int remaining) {
    String _temp0 = intl.Intl.pluralLogic(
      linked,
      locale: localeName,
      other: '$linked titels',
      one: '$linked titel',
    );
    String _temp1 = intl.Intl.pluralLogic(
      remaining,
      locale: localeName,
      other: '; $remaining nog steeds noten.',
      one: '; $remaining nog steeds een noot.',
      zero: '.',
    );
    return '$_temp0 van The Caller\'s Box gekoppeld$_temp1';
  }

  @override
  String get importReviewClose => 'Import sluiten';

  @override
  String get importReviewSourceLabel => 'Bron';

  @override
  String importReviewFromSource(String source) {
    return 'Importeren van $source.';
  }

  @override
  String importReviewDancesFromSource(String source) {
    return 'Dansen importeren van $source.';
  }

  @override
  String get importSourceLabelGenericJson =>
      'een Caller\'s Compendium JSON-bestand';

  @override
  String get importSourceLabelCallersBox => 'The Caller\'s Box';

  @override
  String get importSourceLabelContraDb => 'ContraDB';

  @override
  String get importSourceLabelCallersCompanionUsr =>
      'een Caller\'s Companion .USR-bestand';

  @override
  String get importErrorFileTooLarge =>
      'Dat bestand is te groot om te importeren.';

  @override
  String get archiveIntakeRejectedTooLarge =>
      'Dat bestand is te groot om te importeren.';

  @override
  String get archiveIntakeRejectedUnreadable =>
      'Kon het gedeelde bestand niet lezen.';

  @override
  String get archiveIntakeRejectedEmpty => 'Dat bestand is leeg.';

  @override
  String get archiveIntakeRejectedNotArchive =>
      'Dat bestand is geen deelbestand van Caller’s Compendium.';

  @override
  String get archiveIntakeRejectedNewerVersion =>
      'Dat bestand is gemaakt met een nieuwere versie van de app. Werk de app bij om het te importeren.';

  @override
  String get archiveIntakeRejectedNoContent =>
      'Dat bestand bevatte geen dansen of programma’s.';

  @override
  String get importErrorInsecureScheme =>
      'Imports moeten een beveiligde https://-URL gebruiken.';

  @override
  String get importErrorBlockedHost =>
      'Die URL verwijst naar een netwerklocatie waarvan niet kan worden geïmporteerd.';

  @override
  String get importErrorInvalidUrl =>
      'Dat ziet er niet uit als een geldige http(s)-URL.';

  @override
  String get importErrorTooManyRedirects =>
      'Die URL heeft te vaak doorgestuurd.';

  @override
  String get importErrorResponseTooLarge =>
      'Die response was te groot om te importeren.';

  @override
  String get importErrorEmptyUrl => 'Voer een URL in om van te importeren.';

  @override
  String importErrorTimeout(int seconds) {
    return 'Het verzoek is na ${seconds}s verlopen. Controleer de URL en je verbinding en probeer het opnieuw.';
  }

  @override
  String get importErrorUnreachable =>
      'Die URL kon niet worden bereikt. Controleer de URL en je verbinding en probeer het opnieuw.';

  @override
  String importErrorHttpStatus(int status) {
    return 'De server heeft gereageerd met HTTP $status.';
  }

  @override
  String get importErrorEmptyResponse => 'De URL gaf een lege response.';

  @override
  String get importErrorCallersBoxEmptyInput =>
      'Voer een Caller\'s Box dans-URL of -id in om van te importeren.';

  @override
  String get importErrorCallersBoxInvalidUrl =>
      'Dat ziet er niet uit als een Caller\'s Box dans-URL of een numeriek id.';

  @override
  String get importErrorCallersBoxMissingId =>
      'Die Caller\'s Box-URL mist een dans-id (…dance.php?id=N).';

  @override
  String get importErrorCallersBoxEmptySearch =>
      'Voer een titel of per-frase-figuren in om The Caller\'s Box te doorzoeken.';

  @override
  String importErrorSearchTimeout(int seconds) {
    return 'De zoekopdracht is na ${seconds}s verlopen. Controleer je verbinding en probeer het opnieuw.';
  }

  @override
  String get importErrorCallersBoxUnreachable =>
      'The Caller\'s Box kon niet worden bereikt. Controleer je verbinding en probeer het opnieuw.';

  @override
  String importErrorCallersBoxHttpStatus(int status) {
    return 'The Caller\'s Box heeft gereageerd met HTTP $status.';
  }

  @override
  String get importErrorCallersBoxEmptyPage =>
      'The Caller\'s Box heeft een lege pagina geretourneerd.';

  @override
  String get importErrorCallersBoxNoDance =>
      'The Caller\'s Box heeft geen importeerbare dans geretourneerd.';

  @override
  String get importErrorCallersBoxImportFailed =>
      'De Caller\'s Box-dans kon niet worden geïmporteerd.';

  @override
  String get importErrorContraDbEmptyTitle =>
      'Voer een titel in om ContraDB te doorzoeken.';

  @override
  String get importErrorContraDbEmptyDanceInput =>
      'Voer een ContraDB dans-URL of -id in om van te importeren.';

  @override
  String get importErrorContraDbInvalidDanceUrl =>
      'Dat ziet er niet uit als een ContraDB dans-URL of een numeriek id.';

  @override
  String get importErrorContraDbMissingDanceId =>
      'Die ContraDB-URL mist een dans-id (…/dances/N).';

  @override
  String get importErrorContraDbEmptyProgramInput =>
      'Voer een ContraDB programma-URL of -id in om van te importeren.';

  @override
  String get importErrorContraDbInvalidProgramUrl =>
      'Dat ziet er niet uit als een ContraDB programma-URL of een numeriek id.';

  @override
  String get importErrorContraDbMissingProgramId =>
      'Die ContraDB-URL mist een programma-id (…/programs/N).';

  @override
  String get importErrorContraDbInvalidProgramLink =>
      'Dat ziet er niet uit als een ContraDB-programmalink.';

  @override
  String get importErrorContraDbUnreachable =>
      'ContraDB kon niet worden bereikt. Controleer je verbinding en probeer het opnieuw.';

  @override
  String importErrorContraDbHttpStatus(int status) {
    return 'ContraDB heeft gereageerd met HTTP $status.';
  }

  @override
  String get importErrorContraDbEmptyResponse =>
      'ContraDB heeft een lege response geretourneerd.';

  @override
  String get importErrorContraDbNoDance =>
      'ContraDB heeft geen importeerbare dans geretourneerd.';

  @override
  String get importErrorContraDbImportFailed =>
      'De ContraDB-dans kon niet worden geïmporteerd.';

  @override
  String get importIssueGeneric => 'Dit item is met een notitie geïmporteerd.';

  @override
  String get importIssueProgramEmptySlot =>
      'Een lege plek in een programma is overgeslagen.';

  @override
  String get importIssueProgramUnresolvedDance =>
      'Een programma verwees naar een dans die niet is geïmporteerd; de plek is als tekstplaatshouder bewaard.';

  @override
  String get importIssueProgramUnresolvedVenue =>
      'Een programma verwees naar een locatie die niet is geïmporteerd; het programma is zonder locatiekoppeling bewaard.';

  @override
  String get importIssueArchiveReadError =>
      'Een item in het gedeelde bestand kon niet worden gelezen en is overgeslagen.';

  @override
  String get importIssueArchiveReadWarning =>
      'Bij het decoderen van het gedeelde bestand is een waarschuwing gemeld.';

  @override
  String get importIssueDirectionUnmapped =>
      'Een Becket-richting werd niet herkend; standaard met de klok mee.';

  @override
  String get importIssueFormationUnclassified =>
      'Een formatie kon niet worden herkend; bewaard als detail bij “other”.';

  @override
  String get importIssuePhraseStructureUnreadable =>
      'Een fraseopbouw kon niet worden gelezen; er is een standaardopbouw gebruikt.';

  @override
  String get importIssueProgressionUnmapped =>
      'Een progressie werd niet herkend; vastgelegd als “other”.';

  @override
  String get importIssueMetadataOnlyStub =>
      'Deze dans is alleen als metadata beschikbaar (geen figuren); geïmporteerd als stub.';

  @override
  String importIssueDateAssumedMdy(String field) {
    return 'Een dubbelzinnige datum ($field) is gelezen als maand/dag (US-volgorde); controleer die als de bron dag-eerst gebruikte.';
  }

  @override
  String importIssueDateReducedPrecision(int year, String field) {
    return 'Alleen het jaar $year kon uit de datum ($field) worden gelezen; er was geen maand of dag aanwezig.';
  }

  @override
  String get importIssueMissingTitle =>
      'De dans had geen titel; er is een plaatshoudertitel gebruikt. Bewerk die vóór het vastleggen.';

  @override
  String get importIssueProgramUnparsedDate =>
      'Een evenementdatum kon niet worden gelezen; niet ingesteld.';

  @override
  String get importIssueRatingOutOfRange =>
      'Een beoordeling viel buiten de schaal 1–5; niet beoordeeld.';

  @override
  String get importIssueUnmappedFormation =>
      'Een formatie werd niet herkend; bewaard als vrijetekstdetail.';

  @override
  String get importIssueUnmappedLevel =>
      'Een niveau werd niet herkend; niet opgegeven.';

  @override
  String get importIssueUnmappedProgression =>
      'Een progressie werd niet herkend; standaard op enkel.';

  @override
  String get importIssueUnmappedType =>
      'Een danstype werd niet herkend; geïmporteerd als contra en bewaard in de notities.';

  @override
  String importIssueUnparsedDate(String field) {
    return 'De datum ($field) kon niet worden gelezen; niet ingesteld.';
  }

  @override
  String get importIssueUnparsedRating =>
      'Een beoordeling kon niet worden gelezen; niet beoordeeld.';

  @override
  String get importIssueFiguresUnreadable =>
      'De figuren konden niet worden gelezen; er zijn geen figuren geïmporteerd.';

  @override
  String get importIssueBeatsUnreadable =>
      'Een aantal beats kon niet worden gelezen; 0 gebruikt.';

  @override
  String get importIssueNoFiguresTable =>
      'De pagina had geen figuren; geïmporteerd als metadata-only stub.';

  @override
  String get importIssueMoveFallback =>
      'Een figuur kon niet aan een bekende move worden gekoppeld; geïmporteerd als aangepast.';

  @override
  String importIssueMoveFallbackAt(int position) {
    return 'Figuur $position kon niet aan een bekende move worden gekoppeld; geïmporteerd als aangepast.';
  }

  @override
  String get importIssueParamUnmapped =>
      'Een figuurparameter kon niet worden gekoppeld; een taxonomie-standaard is gebruikt.';

  @override
  String importIssueParamValueUnmapped(String param) {
    return 'De parameter $param kon niet worden geconverteerd; een taxonomie-standaard is gebruikt.';
  }

  @override
  String importIssueParamCountUnmapped(int provided, int mapped) {
    return 'Een figuur had $provided parameterwaarden maar slechts $mapped zijn toegewezen; de extra waarden zijn genegeerd.';
  }

  @override
  String get importDateFieldComposed => 'gecomponeerd';

  @override
  String get importDateFieldRevised => 'herzien';

  @override
  String get importRecordErrorDiscover =>
      'Dit record kon niet worden gevonden.';

  @override
  String get importRecordErrorFetch => 'Dit record kon niet worden opgehaald.';

  @override
  String get importRecordErrorParse => 'Dit record kon niet worden gelezen.';

  @override
  String get importRecordErrorDedupe => 'Dit record kon niet worden verwerkt.';

  @override
  String get importRecordErrorCommit =>
      'Dit record kon niet worden opgeslagen.';

  @override
  String get importReviewUsrSubtitle =>
      'Kies het Caller\'s Companion .USR-bestand om de dansen en programmageschiedenis te migreren. Er wordt niets aan je collectie toegevoegd totdat je controleert en bevestigt.';

  @override
  String get importReviewChooseUsr => 'Kies .USR-bestand…';

  @override
  String importReviewFileReady(int bytes) {
    return 'Bestand klaar ($bytes bytes).';
  }

  @override
  String get importReviewGenericSubtitle =>
      'Kies een bestand, plak de inhoud of haal het op via een URL. Er wordt niets aan je collectie toegevoegd totdat je controleert en bevestigt.';

  @override
  String get importReviewChooseFile => 'Bestand kiezen…';

  @override
  String get importReviewUrlLabel => 'Dans-URL of -id';

  @override
  String get importReviewUrlLabelGeneric => 'Importeren via URL';

  @override
  String get importReviewUrlHint =>
      'https://www.ibiblio.org/contradance/thecallersbox/dance.php?id=1  · of · 1';

  @override
  String get importReviewUrlHintGeneric => 'https://…';

  @override
  String get importReviewFetch => 'Ophalen';

  @override
  String get importReviewPasteJson => 'Of plak JSON';

  @override
  String get importReviewReviewButton => 'Import controleren';

  @override
  String importReviewWillImport(int importable, int total) {
    return '$importable van $total worden geïmporteerd';
  }

  @override
  String get importReviewCouldNotRead => 'De import kon niet worden gelezen';

  @override
  String get importReviewNoDancesTitle => 'Geen dansen gevonden';

  @override
  String get importReviewNoDancesBody =>
      'Het bestand bevatte geen dansen om te importeren.';

  @override
  String get importReviewTryAnother => 'Probeer een ander bestand';

  @override
  String get importReviewImported => 'Geïmporteerd';

  @override
  String importReviewStructured(int structured, int total) {
    return '$structured/$total gestructureerd';
  }

  @override
  String get importReviewCustom => 'Aangepast';

  @override
  String get importReviewOptionNewDance => 'Nieuwe dans';

  @override
  String get importReviewOptionSkip => 'Overslaan';

  @override
  String importReviewOptionReimport(String title) {
    return 'Opnieuw importeren in “$title”';
  }

  @override
  String get importReviewOptionDuplicate =>
      'Importeren als nieuwe (dubbele) dans';

  @override
  String get importReviewPossibleMatch =>
      'Mogelijke overeenkomst — kies hoe je wilt importeren:';

  @override
  String importReviewOptionLink(String title, int percent) {
    return 'Koppelen aan “$title” ($percent% overeenkomst)';
  }

  @override
  String importReviewOverwriteWarning(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count bestaande dansen worden overschreven',
      one: '1 bestaande dans wordt overschreven',
    );
    return '$_temp0';
  }

  @override
  String importReviewWarningPrefix(String message) {
    return 'Waarschuwing: $message';
  }

  @override
  String get importReviewComplete => 'Import voltooid';

  @override
  String sharedImportSoftCapWarning(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Deze import bevat $count items — meer dan verwacht voor een gewone share.',
      one:
          'Deze import bevat 1 item — meer dan verwacht voor een gewone share.',
    );
    return '$_temp0';
  }

  @override
  String sharedImportComplete(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items geïmporteerd.',
      one: '1 item geïmporteerd.',
      zero: 'Import voltooid.',
    );
    return '$_temp0';
  }

  @override
  String sharedImportProgramsOnly(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Deze share bevat $count programma’s en geen dansen.',
      one: 'Deze share bevat 1 programma en geen dansen.',
    );
    return '$_temp0';
  }

  @override
  String importReviewSummaryCreated(int count) {
    return 'Aangemaakt: $count';
  }

  @override
  String importReviewSummaryReimported(int count) {
    return 'Opnieuw geïmporteerd: $count';
  }

  @override
  String importReviewSummaryLinked(int count) {
    return 'Gekoppeld: $count';
  }

  @override
  String importReviewSummaryDuplicated(int count) {
    return 'Gedupliceerd: $count';
  }

  @override
  String importReviewSummarySkipped(int count) {
    return 'Overgeslagen: $count';
  }

  @override
  String importReviewSummaryPrograms(int count) {
    return 'Programma’s: $count';
  }

  @override
  String importReviewProgramsUpdated(int count) {
    return '$count bijgewerkt (opnieuw geïmporteerd)';
  }

  @override
  String importReviewProgramNotes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count programmanotities:',
      one: '$count programmanotitie(s):',
    );
    return '$_temp0';
  }

  @override
  String importReviewRecordsFailed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count records konden niet worden geïmporteerd:',
      one: '$count record(s) kon niet worden geïmporteerd:',
    );
    return '$_temp0';
  }

  @override
  String importReviewBatchErrors(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count records konden niet worden gelezen (de rest kan nog worden geïmporteerd):',
      one:
          '$count record(s) kon niet worden gelezen (de rest kan nog worden geïmporteerd):',
    );
    return '$_temp0';
  }

  @override
  String get importReviewUntitledProgram => 'Naamloos programma';

  @override
  String get importReviewUndoWithPrograms =>
      'Ongedaan maken (verwijdert de geïmporteerde dansen en programma’s)';

  @override
  String get importReviewUndone => 'Import ongedaan gemaakt.';

  @override
  String get importReviewEditError =>
      'Die dans kon niet worden geïmporteerd om te bewerken.';

  @override
  String get importReviewImportError => 'De import kon niet worden voltooid.';

  @override
  String get danceEditorDetailsSection => 'Details';

  @override
  String get danceEditorTitleRequiredLabel => 'Titel *';

  @override
  String get danceEditorTitleRequired => 'Titel is vereist';

  @override
  String get danceEditorAuthorsLabel => 'Auteurs';

  @override
  String get danceEditorFormationLabel => 'Formatie';

  @override
  String get danceEditorFormationDetailLabel => 'Formatiedetail (optioneel)';

  @override
  String get danceEditorPhraseStructureLabel => 'Fraseopbouw';

  @override
  String get danceEditorPhraseStructureHint =>
      'Leeg = standaard A1 A2 B1 B2; anders bijv. 6*8*2';

  @override
  String get danceEditorFiguresSection => 'Figuren';

  @override
  String get danceEditorFiguresHelp =>
      'Typ een move (bijv. “sw” → swing) en druk op Enter om het toe te voegen met standaardparameters; niet-herkende tekst wordt een aangepaste figuur.';

  @override
  String get danceEditorNotesSection => 'Notities';

  @override
  String get danceEditorCallingNotesLabel => 'Callnotities';

  @override
  String get danceEditorHookLabel => 'Haak';

  @override
  String get danceEditorHookHint => 'Één zin “waarom deze dans callen”';

  @override
  String get danceEditorWalkthroughLabel => 'Doorloop';

  @override
  String get danceEditorWalkthroughHelper =>
      'Stapsgewijze beschrijving van de dans en de overgangen';

  @override
  String get danceEditorAddWalkthroughStep => 'Doorloopstap toevoegen';

  @override
  String get danceEditorWalkthroughStepLabel => 'Doorloopstap (optioneel)';

  @override
  String get danceEditorWalkthroughStepHelper =>
      'Opgeslagen als je standaard voor deze figuur en overal hergebruikt waar ze voorkomt.';

  @override
  String get danceEditorSnippetDivergenceTitle =>
      'Opgeslagen fragment bijwerken?';

  @override
  String get danceEditorSnippetDivergenceBody =>
      'Dit verschilt van het doorloopfragment dat je voor deze figuur hebt opgeslagen. De nieuwe tekst overal gebruiken, of alleen in deze dans?';

  @override
  String get danceEditorSnippetUseEverywhere => 'Overal gebruiken';

  @override
  String get danceEditorSnippetJustThisDance => 'Alleen deze dans';

  @override
  String get danceEditorFillWalkthroughFromSnippets => 'Vullen met fragmenten';

  @override
  String get danceEditorFillWalkthroughReplaceTitle => 'Doorloop vervangen?';

  @override
  String get danceEditorFillWalkthroughReplaceBody =>
      'Dit vervangt de huidige doorloop door tekst die is samengesteld uit je figuurfragmenten.';

  @override
  String get danceEditorFillWalkthroughReplaceConfirm => 'Vervangen';

  @override
  String get danceEditorFillWalkthroughEmpty =>
      'Geen van deze figuren heeft al een opgeslagen doorloopfragment.';

  @override
  String get settingsWalkthroughSnippetsTitle => 'Doorloopfragmenten';

  @override
  String get settingsWalkthroughSnippetsSubtitle =>
      'Je opgeslagen stapbeschrijvingen per figuur';

  @override
  String get settingsWalkthroughSnippetsHeader =>
      'Opgeslagen doorloopfragmenten';

  @override
  String get settingsWalkthroughSnippetsDescription =>
      'Deze stapbeschrijvingen per figuur vullen doorlopen vooraf in wanneer je een dans bewerkt. Een hier bewerken werkt de overal gebruikte standaard bij.';

  @override
  String get settingsWalkthroughSnippetsEmpty =>
      'Nog geen opgeslagen fragmenten. Voeg doorloopstapbeschrijvingen toe terwijl je de figuren van een dans bewerkt.';

  @override
  String settingsWalkthroughSnippetsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count fragmenten',
      one: '1 fragment',
    );
    return '$_temp0';
  }

  @override
  String get settingsWalkthroughSnippetDeleteTitle => 'Fragment verwijderen?';

  @override
  String get settingsWalkthroughSnippetDeleteBody =>
      'Dit verwijdert de opgeslagen standaard voor deze figuur. Dansen behouden alle doorlooptekst die je al hebt geschreven.';

  @override
  String get settingsWalkthroughSnippetEditTitle => 'Fragment bewerken';

  @override
  String get danceEditorMoreDetailsTitle => 'Meer details';

  @override
  String get danceEditorStatusLabel => 'Status';

  @override
  String get danceEditorMixedLevelSubtitle => 'Beslaat de moeilijkheidsschaal';

  @override
  String get danceEditorComposedLabel => 'Gecomponeerd';

  @override
  String get danceEditorComposedHelper =>
      'Wanneer de dans is gecomponeerd (jaar, of voeg maand/dag toe)';

  @override
  String get danceEditorRevisedLabel => 'Herzien';

  @override
  String get danceEditorRevisedHelper =>
      'Wanneer de dans voor het laatst door de auteur is herzien';

  @override
  String get danceEditorTagsLabel => 'Tags';

  @override
  String get danceEditorTunesLabel => 'Deuntjes';

  @override
  String get danceEditorLinksLabel => 'Links';

  @override
  String get danceEditorPublishedSourcesLabel => 'Gepubliceerde bronnen';

  @override
  String get danceEditorRelatedDancesLabel => 'Gerelateerde dansen';

  @override
  String get danceEditorCustomFieldsLabel => 'Aangepaste velden';

  @override
  String get danceEditorRatingLabel => 'Beoordeling';

  @override
  String get danceEditorRatingUnrated => 'niet beoordeeld';

  @override
  String danceEditorRatingValue(int rating, int max) {
    return '$rating van $max sterren';
  }

  @override
  String danceEditorSetRatingTooltip(int rating, int max) {
    return 'Beoordeling instellen op $rating van $max sterren';
  }

  @override
  String get danceEditorClearRating => 'Beoordeling wissen';

  @override
  String get danceEditorLevelLabel => 'Niveau';

  @override
  String get danceEditorLevelUnspecified => 'Niet opgegeven';

  @override
  String get danceEditorYearLabel => 'Jaar';

  @override
  String get danceEditorYearHint => 'bijv. 1989';

  @override
  String get danceEditorYearRangeError => '1–9999';

  @override
  String get danceEditorMonthLabel => 'Maand';

  @override
  String get danceEditorDayLabel => 'Dag';

  @override
  String get danceEditorMonthJan => 'Jan';

  @override
  String get danceEditorMonthFeb => 'Feb';

  @override
  String get danceEditorMonthMar => 'Mrt';

  @override
  String get danceEditorMonthApr => 'Apr';

  @override
  String get danceEditorMonthMay => 'Mei';

  @override
  String get danceEditorMonthJun => 'Jun';

  @override
  String get danceEditorMonthJul => 'Jul';

  @override
  String get danceEditorMonthAug => 'Aug';

  @override
  String get danceEditorMonthSep => 'Sep';

  @override
  String get danceEditorMonthOct => 'Okt';

  @override
  String get danceEditorMonthNov => 'Nov';

  @override
  String get danceEditorMonthDec => 'Dec';

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
  String get danceEditorAddTuneHint => 'Een voorgesteld deuntje toevoegen…';

  @override
  String get danceEditorAddTuneTooltip => 'Deuntje toevoegen';

  @override
  String get danceEditorWarningsTitle => 'Waarschuwingen';

  @override
  String validationPhraseBeatMismatch(int actual, int expected) {
    return 'De figuren tellen samen $actual beats; de fraseopbouw verwacht $expected.';
  }

  @override
  String get validationPhraseInvalid => 'Die fraseopbouw is ongeldig.';

  @override
  String validationOrphanedAlt(int position) {
    return 'Het alternatief op positie $position heeft geen voorafgaande hoofdplek.';
  }

  @override
  String validationOrphanedAltNamed(int position, String text) {
    return 'Het alternatief op positie $position (“$text”) heeft geen voorafgaande hoofdplek.';
  }

  @override
  String validationEmptySubstitution(String term) {
    return 'De vervanging voor “$term” is leeg.';
  }

  @override
  String validationDialectCollision(
    String source,
    String existing,
    String substitution,
  ) {
    return '“$source” en “$existing” verwijzen beide naar “$substitution” — omkeren zou dubbelzinnig zijn.';
  }

  @override
  String get validationGeneric => 'Dit item heeft een validatieprobleem.';

  @override
  String danceEditorDiscouragedTermSemantic(String term) {
    return 'Ontmoedigde term: $term';
  }

  @override
  String danceEditorDiscouragedTermText(String term) {
    return 'Ontmoedigd: $term';
  }

  @override
  String get danceEditorLinkKindSource => 'Bron';

  @override
  String get danceEditorLinkKindVideo => 'Video';

  @override
  String get danceEditorLinkKindOther => 'Overig';

  @override
  String get danceEditorUrlLabel => 'URL';

  @override
  String get danceEditorLabelOptional => 'Label (optioneel)';

  @override
  String get danceEditorRemoveLinkTooltip => 'Link verwijderen';

  @override
  String get danceEditorAddLink => 'Link toevoegen';

  @override
  String get danceEditorMissingDance => '(ontbrekende dans)';

  @override
  String get danceEditorNoteOptionalLabel => 'Noot (optioneel)';

  @override
  String get danceEditorRemoveRelatedDanceTooltip =>
      'Gerelateerde dans verwijderen';

  @override
  String get danceEditorAddRelatedDance => 'Gerelateerde dans toevoegen';

  @override
  String get danceEditorRelatedDanceLabel => 'Gerelateerde dans';

  @override
  String get danceEditorTypeToSearchHint => 'Typ om te zoeken…';

  @override
  String danceEditorEditItemTooltip(String item) {
    return '$item bewerken';
  }

  @override
  String get danceEditorTypeToAddOrCreateHint =>
      'Typ om toe te voegen of aan te maken…';

  @override
  String danceEditorCreateQuotedName(String name) {
    return '“$name” aanmaken';
  }

  @override
  String get danceEditorUnknownSource => '(onbekende bron)';

  @override
  String get danceEditorPageOptionalLabel => 'Pagina (optioneel)';

  @override
  String get danceEditorNumberOptionalLabel => 'Nummer (optioneel)';

  @override
  String get danceEditorCiteSourceHint =>
      'Een bron citeren: typ om toe te voegen of aan te maken…';

  @override
  String get danceEditorSaveError => 'De dans kon niet worden opgeslagen.';

  @override
  String get danceEditorFallbackDanceTitle => 'Dans';

  @override
  String get danceEditorUnsavedDraftTitle => 'Niet-opgeslagen concept';

  @override
  String get danceEditorUnsavedDraftMessage =>
      'Je hebt een niet-opgeslagen concept voor deze dans. Wil je het herstellen?';

  @override
  String get danceEditorDiscard => 'Verwerpen';

  @override
  String get danceEditorRestore => 'Herstellen';

  @override
  String get danceEditorDiscardChangesTitle => 'Wijzigingen verwerpen?';

  @override
  String get danceEditorDiscardChangesMessage =>
      'Je hebt niet-opgeslagen wijzigingen in deze dans.';

  @override
  String get danceEditorKeepEditing => 'Doorgaan met bewerken';

  @override
  String get danceEditorNewDanceTitle => 'Nieuwe dans';

  @override
  String get danceEditorEditDanceTitle => 'Dans bewerken';

  @override
  String get danceEditorRedoLabel => 'Opnieuw uitvoeren';

  @override
  String get danceEditorUndoShortcutTooltip => 'Ongedaan maken (Ctrl+Z)';

  @override
  String get danceEditorRedoShortcutTooltip =>
      'Opnieuw uitvoeren (Ctrl+Shift+Z)';

  @override
  String get danceEditorDeleteDanceTooltip => 'Dans verwijderen';

  @override
  String get danceEditorLoadError => 'De dans kon niet worden geladen.';

  @override
  String get danceEditorChoreographerDetailsTitle => 'Choreografendetails';

  @override
  String get danceEditorChoreographerDetailsIntro =>
      'Deze details zijn gedeeld over elke dans op naam van deze auteur. E-mail en locatie zijn privé — alleen opgeslagen op dit apparaat en nooit gedeeld of geëxporteerd.';

  @override
  String get danceEditorNameRequiredLabel => 'Naam *';

  @override
  String get danceEditorNameRequired => 'Naam is vereist';

  @override
  String get danceEditorWebsiteLabel => 'Website';

  @override
  String get danceEditorEmailPrivateLabel => 'E-mail (privé)';

  @override
  String get danceEditorLocationPrivateLabel => 'Locatie (privé)';

  @override
  String get danceEditorNotesLabel => 'Notities';

  @override
  String get danceEditorDeceasedLabel => 'Overleden';

  @override
  String get danceEditorSourceDetailsTitle => 'Brondetails';

  @override
  String get danceEditorSourceDetailsIntro =>
      'Deze details zijn gedeeld over elke dans die naar deze bron verwijst. Ze hier bewerken werkt de bron bij overal waar ernaar wordt verwezen.';

  @override
  String get danceEditorSourceAuthorEditorLabel => 'Auteur / redacteur';

  @override
  String get danceEditorEnterWholeNumber => 'Voer een geheel getal in';

  @override
  String get danceEditorEnterPositiveYear => 'Voer een positief jaar in';

  @override
  String danceEditorAddedFigureChooseMove(int count) {
    return 'Figuur $count toegevoegd. Kies een move.';
  }

  @override
  String danceEditorFigurePastedAnnouncement(int position) {
    return 'Figuur geplakt op positie $position.';
  }

  @override
  String danceEditorFigureMovedAnnouncement(int position, int total) {
    return 'Verplaatst naar positie $position van $total.';
  }

  @override
  String danceEditorEditingFigureAnnouncement(int position, String name) {
    return 'Figuur $position bewerken, $name.';
  }

  @override
  String danceEditorCollapsedFigureAnnouncement(int position) {
    return 'Figuur $position ingeklapt.';
  }

  @override
  String get danceEditorTypeFigureAnnouncement =>
      'Typ een figuur en druk op Enter om het toe te voegen.';

  @override
  String danceEditorFreeTextFiguresAddedAnnouncement(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count figuren toegevoegd. Typ nog een figuur of druk op Escape om te voltooien.',
      one:
          '1 figuur toegevoegd. Typ nog een figuur of druk op Escape om te voltooien.',
    );
    return '$_temp0';
  }

  @override
  String danceEditorDeletedFigureAnnouncement(int position) {
    return 'Figuur $position verwijderd. Ongedaan maken mogelijk.';
  }

  @override
  String danceEditorDuplicatedFigureAnnouncement(int position) {
    return 'Figuur $position gedupliceerd.';
  }

  @override
  String get danceEditorAddFirstFigure => 'Eerste figuur toevoegen';

  @override
  String danceEditorCutBanner(String figure) {
    return '“$figure” is geknipt — tik op Plakken om het te plaatsen.';
  }

  @override
  String get danceEditorPasteBeforeFirstFigure =>
      'Plakken vóór de eerste figuur';

  @override
  String danceEditorPasteAfterFigure(String figure) {
    return 'Plakken na $figure';
  }

  @override
  String get danceEditorAddFigure => 'Figuur toevoegen';

  @override
  String get danceEditorPasteAtEndOfFigureList =>
      'Plakken aan het einde van de figurenlijst';

  @override
  String get danceEditorTypeFigureLabel => 'Typ een figuur';

  @override
  String get danceEditorTypeFigureHelper =>
      'bijv. “neighbor balance & swing” of “16 circle left 3/4”. Enter voegt het toe; niet-herkende tekst wordt bewaard als aangepaste figuur.';

  @override
  String get danceEditorPasteHere => 'Hier plakken';

  @override
  String get danceEditorEmptyFigureName => 'Lege figuur';

  @override
  String get danceEditorCustomFigureName => 'Aangepaste figuur';

  @override
  String get danceEditorEmptyFigureSummary => '(leeg — kies een move)';

  @override
  String get danceEditorEmptyFigureSemantic => 'lege figuur, kies een move';

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
      'yes': ', progressie',
      'other': '',
    });
    String _temp2 = intl.Intl.pluralLogic(
      beats,
      locale: localeName,
      other: '$beats beats',
      one: '1 beat',
    );
    String _temp3 = intl.Intl.selectLogic(hasMove, {
      'yes': ', $_temp2',
      'other': '',
    });
    String _temp4 = intl.Intl.selectLogic(hasNote, {
      'yes': ', noot: $note',
      'other': '',
    });
    return '$main$_temp0$_temp1$_temp3$_temp4. Figuur $position van $total.';
  }

  @override
  String get danceEditorActivateToEditHint => 'Activeer om te bewerken';

  @override
  String danceEditorDragToReorderFigure(String figure) {
    return '$figure slepen om te herordenen';
  }

  @override
  String danceEditorFigureActionsTooltip(String figure) {
    return 'Acties voor $figure';
  }

  @override
  String get danceEditorMoveUp => 'Omhoog verplaatsen';

  @override
  String get danceEditorMoveDown => 'Omlaag verplaatsen';

  @override
  String get danceEditorCut => 'Knippen';

  @override
  String get danceEditorClearProgression => 'Progressie wissen';

  @override
  String get danceEditorMarkProgression => 'Progressie markeren';

  @override
  String danceEditorUnrecognizedMoveReadOnly(String move) {
    return 'Niet-herkende move “$move” — niet in de taxonomie van deze versie. Alleen-lezen weergegeven zodat de gegevens bewaard blijven; de move kan weer normaal worden bewerkt als hij herkend wordt. Je kunt hem nog steeds herordenen of verwijderen.';
  }

  @override
  String get danceEditorFewerOptions => 'Minder opties';

  @override
  String danceEditorMoreOptions(int count) {
    return 'Meer opties ($count)';
  }

  @override
  String get danceEditorMoveCanCarryProgression =>
      'Deze move kan de progressie dragen.';

  @override
  String get danceEditorAddNote => 'Noot toevoegen';

  @override
  String get danceEditorBoldTooltip => 'Vet (*tekst*)';

  @override
  String get danceEditorUnderlineTooltip => 'Onderstrepen (_tekst_)';

  @override
  String get danceEditorCustomFigureTextLabel => 'Aangepaste figuurtekst';

  @override
  String get danceEditorLingoStylingHelper =>
      'Bewegingsnamen gestippeld·onderstreept, roltermen onderstreept, ontmoedigde termen doorgestreept';

  @override
  String danceEditorBeatTotal(int total, int expected) {
    return 'Totaal: $total / $expected beats';
  }

  @override
  String danceEditorOverByBeats(int beats) {
    return '$beats beats te veel';
  }

  @override
  String danceEditorUnderByBeats(int beats) {
    return '$beats beats te weinig';
  }

  @override
  String get danceEditorLessTooltip => 'Minder';

  @override
  String get danceEditorMoreTooltip => 'Meer';

  @override
  String danceEditorTurnCount(num count, String formatted) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$formatted draaien',
      one: '$formatted draai',
    );
    return '$_temp0';
  }

  @override
  String get commonBack => 'Terug';

  @override
  String get commonRemove => 'Verwijderen';

  @override
  String updateBannerDownloading(String appName, String version) {
    return '$appName $version downloaden…';
  }

  @override
  String updateBannerDownloadingPct(String appName, String version, int pct) {
    return '$appName $version downloaden… $pct%';
  }

  @override
  String updateBannerVerifying(String appName, String version) {
    return '$appName $version verifiëren…';
  }

  @override
  String get updateBannerPreparingInstaller => 'Installer voorbereiden…';

  @override
  String updateBannerCompletedRevealed(String appName, String version) {
    return '$appName $version gedownload en geverifieerd — de installer is zichtbaar in je bestandsbeheer. Voer hem uit om het bijwerken te voltooien.';
  }

  @override
  String updateBannerCompletedManual(String appName, String version) {
    return '$appName $version gedownload — volg de installer om het bijwerken te voltooien.';
  }

  @override
  String get updateBannerDownloadFailed =>
      'De update kon niet worden gedownload.';

  @override
  String updateBannerAvailable(String appName, String version) {
    return 'Een nieuwere versie van $appName ($version) is beschikbaar.';
  }

  @override
  String get updateBannerViewRelease => 'Release bekijken';

  @override
  String get updateBannerDismiss => 'Sluiten';

  @override
  String get updateBannerDownloadInstall => 'Downloaden en installeren';

  @override
  String get commandPaletteBarrierLabel => 'Globaal zoeken';

  @override
  String get commandPaletteSearchHint => 'Dansen en programma’s zoeken…';

  @override
  String get commandPaletteProgramSubtitle => 'Programma';

  @override
  String get commandPaletteEmptyInitial => 'Nog niets om in te zoeken.';

  @override
  String get commandPaletteNoMatches =>
      'Geen overeenkomsten voor die zoekopdracht.';

  @override
  String get commandPaletteGroupDances => 'Dansen';

  @override
  String get commandPaletteGroupPrograms => 'Programma’s';

  @override
  String get collectionPickerSearchLabel => 'Een dans zoeken om toe te voegen';

  @override
  String collectionPickerFilters(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Filters ($count actief)',
      zero: 'Filters',
    );
    return '$_temp0';
  }

  @override
  String collectionPickerByPhrase(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Per frase ($count actief)',
      zero: 'Per frase',
    );
    return '$_temp0';
  }

  @override
  String get collectionPickerAdvanced => 'Geavanceerd';

  @override
  String get collectionPickerUseAdvancedQuery =>
      'Geavanceerde zoekopdracht gebruiken';

  @override
  String get collectionPickerAdvancedQueryHelp =>
      'Combineer figuren en reeksen met alle / een van / geen groepen.';

  @override
  String collectionPickerAddSemantic(String title) {
    return '$title aan programma toevoegen';
  }

  @override
  String collectionPickerAddTooltip(String title) {
    return '$title toevoegen';
  }

  @override
  String get userGuideTitle => 'Gebruikersgids';

  @override
  String userGuideMissing(String label) {
    return 'De gids “$label” is nog niet beschikbaar.';
  }

  @override
  String get userGuideLoadError => 'De gebruikersgids kon niet worden geladen.';

  @override
  String get userGuideOpenOnline => 'De gids online openen';

  @override
  String get shorthandMappingsTitle => 'Figuurafkortingen';

  @override
  String get shorthandMappingsIntro =>
      'Afkortingen laten je een korte token typen tijdens vrije tekstinvoer die uitklapt tot één of meer figuren die je hier hebt ingesteld.';

  @override
  String get shorthandMappingsNew => 'Nieuwe afkorting';

  @override
  String get shorthandMappingsEmpty => 'Nog geen afkortingen.';

  @override
  String get shorthandMappingsDeleteTitle => 'Afkorting verwijderen?';

  @override
  String shorthandMappingsDeleteBody(String token) {
    return '“$token” wordt permanent verwijderd.';
  }

  @override
  String get shorthandMappingsActionsTooltip => 'Afkortingsacties';

  @override
  String get shorthandEditorTitleNew => 'Nieuwe afkorting';

  @override
  String get shorthandEditorTitleEdit => 'Afkorting bewerken';

  @override
  String get shorthandEditorTokenLabel => 'Afkorting';

  @override
  String get shorthandEditorTokenHelper =>
      'Typ deze exacte regel tijdens vrije tekstinvoer om de onderstaande figuren in te voegen. Hoofdletterongevoelig vergeleken.';

  @override
  String get shorthandEditorExpandsTo => 'Klapt uit naar';

  @override
  String get shorthandEditorExpandsToHelp =>
      'De figuur(en) die deze afkorting invoegt, op volgorde. Precies zoals een normale figuur opgebouwd, dus parameters en validatie zijn hetzelfde.';

  @override
  String get shorthandEditorErrorEmpty => 'Voer een afkortingstoken in.';

  @override
  String shorthandEditorErrorTooLong(int max) {
    return 'Afkorting is te lang (max $max tekens).';
  }

  @override
  String shorthandEditorErrorDuplicate(String token) {
    return 'Een andere afkorting gebruikt al “$token” (afkortingen worden hoofdletterongevoelig vergeleken).';
  }

  @override
  String get shorthandEditorErrorNoFigures =>
      'Voeg ten minste één figuur toe om deze afkorting naar uit te klappen.';

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
  String get themeEditorTitle => 'Thema bewerken';

  @override
  String get themeEditorNameLabel => 'Themanaam';

  @override
  String get themeEditorContrastAllPass =>
      'Alle gecontroleerde paren voldoen aan WCAG AA-contrast.';

  @override
  String themeEditorContrastFailing(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count contrastparen onder WCAG AA. Je kunt nog steeds opslaan, maar sommige tekst is mogelijk moeilijk leesbaar.',
      one:
          '1 contrastpaar onder WCAG AA. Je kunt nog steeds opslaan, maar sommige tekst is mogelijk moeilijk leesbaar.',
    );
    return '$_temp0';
  }

  @override
  String themeEditorRatioPass(String ratio) {
    return '$ratio:1 AA';
  }

  @override
  String themeEditorRatioFail(String ratio) {
    return '$ratio:1 mislukt';
  }

  @override
  String get themeEditorPreviewHeading => 'Aa Voorbeeld';

  @override
  String get themeEditorBodySample => 'Voorbeeld van tekst';

  @override
  String get themeEditorSwatchPrimary => 'Primair';

  @override
  String get themeEditorSwatchSecondary => 'Secundair';

  @override
  String get themeEditorSwatchTertiary => 'Tertiair';

  @override
  String get themeEditorSwatchError => 'Fout';

  @override
  String get reparseConfirmTitle => 'Aangepaste figuren upgraden?';

  @override
  String reparseConfirmBody(int figureCount, int danceCount) {
    String _temp0 = intl.Intl.pluralLogic(
      figureCount,
      locale: localeName,
      other: '$figureCount figuren',
      one: '1 figuur',
    );
    String _temp1 = intl.Intl.pluralLogic(
      danceCount,
      locale: localeName,
      other: '$danceCount dansen',
      one: '1 dans',
    );
    return 'Dit herverwerkt $_temp0 in $_temp1. Je tags, beoordelingen, notities en alles anders van elke dans blijven exact zoals ze zijn. Alleen figuren die nu een bekende move herkennen worden vervangen.';
  }

  @override
  String get reparseConfirmUpgrade => 'Upgraden';

  @override
  String get reparseFailed =>
      'Figuren konden niet worden geüpgraded. Probeer het opnieuw.';

  @override
  String get reparseNothingUpgradedSnack => 'Niets te upgraden.';

  @override
  String reparseUpgradedSnack(int danceCount) {
    String _temp0 = intl.Intl.pluralLogic(
      danceCount,
      locale: localeName,
      other: '$danceCount dansen',
      one: '1 dans',
    );
    return 'Aangepaste figuren geüpgraded in $_temp0.';
  }

  @override
  String get reparseScreenTitle => 'Aangepaste figuren opnieuw controleren';

  @override
  String reparseIntro(int figureCount, int danceCount) {
    String _temp0 = intl.Intl.pluralLogic(
      figureCount,
      locale: localeName,
      other: '$figureCount figuren',
      one: '1 figuur',
    );
    String _temp1 = intl.Intl.pluralLogic(
      danceCount,
      locale: localeName,
      other: '$danceCount dansen',
      one: '1 dans',
    );
    return 'Verbeterde figuurverwerking kan $_temp0 in $_temp1 upgraden. Bekijk hieronder, bevestig dan — er wijzigt niets voordat je dat doet, en al je tags, beoordelingen en notities blijven bewaard.';
  }

  @override
  String reparsePreviewCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count figuren',
      one: '1 figuur',
    );
    return '$_temp0 te upgraden';
  }

  @override
  String reparseUpgradeButton(int danceCount) {
    String _temp0 = intl.Intl.pluralLogic(
      danceCount,
      locale: localeName,
      other: '$danceCount dansen',
      one: '1 dans',
    );
    return '$_temp0 upgraden';
  }

  @override
  String get reparseEmptyTitle => 'Niets te upgraden';

  @override
  String get reparseEmptyBody =>
      'Geen van je aangepaste figuren uit imports kan momenteel worden herkend als bekende move. Kijk later terug nadat een toekomstige update de figuurverwerking verbetert.';

  @override
  String get reparseErrorTitle => 'Je figuren konden niet worden gecontroleerd';

  @override
  String get reparseErrorBody =>
      'Er ging iets mis tijdens het scannen van je collectie. Er is niets gewijzigd. Je kunt het opnieuw proberen.';

  @override
  String get customFieldsDeleteTitle => 'Aangepast veld verwijderen';

  @override
  String customFieldsDeleteBody(String label) {
    return '“$label” verwijderen? Dit kan niet ongedaan worden gemaakt.';
  }

  @override
  String customFieldsDeleteInUse(String label, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count dansen',
      one: '1 dans',
    );
    return '“$label” kan niet worden verwijderd: nog in gebruik door $_temp0. Verwijder de waarde eerst van alle dansen.';
  }

  @override
  String customFieldsDeleteInUseUnknown(String label) {
    return '“$label” kan niet worden verwijderd: nog in gebruik door sommige dansen. Verwijder de waarde eerst van alle dansen.';
  }

  @override
  String get customFieldsTitle => 'Aangepaste velden';

  @override
  String get customFieldsNewField => 'Nieuw veld';

  @override
  String get customFieldsLoadError =>
      'Aangepaste velden konden niet worden geladen.';

  @override
  String get customFieldsEmpty =>
      'Nog geen aangepaste velden.\nTik op + om er één te definiëren.';

  @override
  String get customFieldsFlagInList => 'In lijst';

  @override
  String get customFieldsSearchable => 'Doorzoekbaar';

  @override
  String get customFieldsTypeText => 'Tekst';

  @override
  String get customFieldsTypeNumber => 'Getal';

  @override
  String get customFieldsTypeBoolean => 'Boolean';

  @override
  String get customFieldsTypeChoice => 'Keuze';

  @override
  String get customFieldsValidatorMinChoice => 'Voeg ten minste één keuze toe';

  @override
  String customFieldsRemoveValueError(String value) {
    return '“$value” kan niet worden verwijderd: het is ingesteld op ten minste één dans.';
  }

  @override
  String get customFieldsEditorNewTitle => 'Nieuw aangepast veld';

  @override
  String get customFieldsEditorEditTitle => 'Aangepast veld bewerken';

  @override
  String get customFieldsLabelLabel => 'Label *';

  @override
  String get customFieldsLabelRequired => 'Label is vereist';

  @override
  String get customFieldsKeyLabel => 'Sleutel *';

  @override
  String get customFieldsKeyHelper =>
      'Stabiele machinesleutel (letters, cijfers, underscores; moet beginnen met een letter of underscore)';

  @override
  String get customFieldsKeyLocked =>
      'Sleutel is vergrendeld — veld is in gebruik op dansen';

  @override
  String get customFieldsKeyRequired => 'Sleutel is vereist';

  @override
  String get customFieldsKeyInvalid =>
      'Sleutel moet beginnen met een letter of underscore en alleen letters, cijfers en underscores bevatten';

  @override
  String get customFieldsTypeFieldLabel => 'Type';

  @override
  String get customFieldsTypeLocked =>
      'Type is vergrendeld — veld heeft waarden op dansen';

  @override
  String get customFieldsShowInList => 'In lijst tonen';

  @override
  String get customFieldsShowInListSubtitle =>
      'Toon deze veldwaarde in de danslijsttegel';

  @override
  String get customFieldsSearchableSubtitle =>
      'Stel dit veld beschikbaar als filter in het zoekpaneel';

  @override
  String get customFieldsChoicesLabel => 'Keuzes *';

  @override
  String get customFieldsChoiceInUseTooltip =>
      'In gebruik — kan niet worden verwijderd';

  @override
  String get customFieldsNewChoiceHint => 'Nieuwe keuze…';

  @override
  String get customFieldsAddChoiceTooltip => 'Keuze toevoegen';

  @override
  String get customFieldsChoiceDuplicate => 'Die optie bestaat al.';

  @override
  String get customFieldsChoiceEmpty => 'Voer een optie in.';

  @override
  String customFieldsAddOptionTooltip(String label) {
    return 'Optie toevoegen aan $label';
  }

  @override
  String customFieldsAddOptionTitle(String label) {
    return 'Optie toevoegen aan $label';
  }

  @override
  String dialectEditorTitle(String name) {
    return '$name bewerken';
  }

  @override
  String get dialectEditorSectionRoleTerms => 'Roltermen';

  @override
  String get dialectEditorSectionMoveSubs => 'Movesubstituties';

  @override
  String get dialectEditorSectionDancerSubs => 'Danserssubstituties';

  @override
  String get dialectEditorSectionDiscouraged => 'Ontmoedigde termen';

  @override
  String get dialectEditorSectionPreview => 'Voorbeeld';

  @override
  String get dialectEditorRole1 => 'Rol 1';

  @override
  String get dialectEditorRole2 => 'Rol 2';

  @override
  String get dialectEditorRolesHelp =>
      'Laat een rol leeg om de canonieke term te gebruiken. Meervoud wordt afgeleid als weggelaten.';

  @override
  String get dialectEditorSingular => 'Enkelvoud';

  @override
  String get dialectEditorPlural => 'Meervoud';

  @override
  String get dialectEditorMoveSubsAdd => 'Movesubstituties toevoegen';

  @override
  String dialectEditorMoveSubsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count movesubstituties',
      one: '1 movesubstitutie',
    );
    return '$_temp0';
  }

  @override
  String get dialectEditorMoveSubHint =>
      'substitutie (gebruik %S voor handedness)';

  @override
  String get dialectEditorAddMove => 'Een move toevoegen…';

  @override
  String get dialectEditorDancerSubsAdd => 'Danserssubstituties toevoegen';

  @override
  String dialectEditorDancerSubsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count danserssubstituties',
      one: '1 danserssubstitutie',
    );
    return '$_temp0';
  }

  @override
  String get dialectEditorDancerSubHint => 'substitutie';

  @override
  String get dialectEditorAddDancerTerm => 'Een danserterm toevoegen…';

  @override
  String get dialectEditorDiscouragedHelp =>
      'Termen die de invoereditor markeert (doorgestreept) — nooit geblokkeerd.';

  @override
  String get dialectEditorDiscouragedEmpty => 'Geen ontmoedigde termen.';

  @override
  String get dialectEditorAddTermLabel => 'Een term toevoegen';

  @override
  String get dialectEditorAddTermTooltip => 'Term toevoegen';

  @override
  String get dialectEditorRestoreDefaults => 'Standaarden herstellen';

  @override
  String get dialectEditorPreviewHelp =>
      'Voorbeeldfiguren weergegeven met dit dialect. Wordt bijgewerkt tijdens het bewerken.';

  @override
  String get recentlyDeletedTitle => 'Onlangs verwijderd';

  @override
  String get recentlyDeletedDeleteTitle => 'Permanent verwijderen?';

  @override
  String recentlyDeletedDeleteBody(String title) {
    return '“$title” wordt onmiddellijk verwijderd en kan niet worden hersteld.';
  }

  @override
  String get recentlyDeletedDeleteConfirm => 'Permanent verwijderen';

  @override
  String recentlyDeletedDeletedSnack(String title) {
    return '“$title” permanent verwijderd.';
  }

  @override
  String get recentlyDeletedRestore => 'Herstellen';

  @override
  String get recentlyDeletedPurgeKept => 'Bewaard totdat je het verwijdert';

  @override
  String recentlyDeletedPurgeCountdown(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days dagen',
      one: '1 dag',
    );
    return 'Automatisch verwijderd over $_temp0';
  }

  @override
  String get recentlyDeletedPurgeScheduled => 'Gepland voor verwijdering';

  @override
  String get recentlyDeletedLoadingDances => 'Onlangs verwijderde dansen laden';

  @override
  String get recentlyDeletedLoadingPrograms =>
      'Onlangs verwijderde programma’s laden';

  @override
  String get recentlyDeletedEmptyDancesKept =>
      'Niets in de prullenbak. Verwijderde dansen worden hier bewaard totdat je ze verwijdert.';

  @override
  String recentlyDeletedEmptyDancesRetention(int days) {
    return 'Niets in de prullenbak. Verwijderde dansen verschijnen hier voor $days dagen voordat ze worden verwijderd.';
  }

  @override
  String recentlyDeletedEmptyProgramsRetention(int days) {
    return 'Niets in de prullenbak. Verwijderde programma’s verschijnen hier voor $days dagen voordat ze worden verwijderd.';
  }

  @override
  String recentlyDeletedRestoredDance(String title) {
    return '“$title” hersteld naar je collectie.';
  }

  @override
  String recentlyDeletedRestoredProgram(String title) {
    return '“$title” hersteld.';
  }

  @override
  String get venueNew => 'Nieuwe locatie';

  @override
  String get venueLoadError => 'Locaties konden niet worden geladen.';

  @override
  String get venueManagerTitle => 'Locaties';

  @override
  String get venueManagerSearchHint => 'Locaties zoeken…';

  @override
  String get venueManagerClearSearchTooltip => 'Zoekopdracht wissen';

  @override
  String get venueManagerEmpty =>
      'Nog geen locaties. Voeg er een toe via de knop hieronder, of vanuit een programma wanneer herbruikbare locaties zijn ingeschakeld.';

  @override
  String get venueManagerNoMatches =>
      'Geen locaties komen overeen met je zoekopdracht.';

  @override
  String get venueManagerDeleteTitle => 'Locatie verwijderen?';

  @override
  String venueManagerDeleteBody(String name) {
    return '“$name” permanent verwijderen? Dit kan niet ongedaan worden gemaakt.';
  }

  @override
  String venueManagerDeletedSnack(String name) {
    return '“$name” verwijderd';
  }

  @override
  String venueManagerDeleteBlocked(String name) {
    return '“$name” kan niet worden verwijderd zolang het nog aan een programma is gekoppeld. Wijzig of verwijder de locatie van die programma’s eerst.';
  }

  @override
  String venueManagerDeleteTooltip(String name) {
    return '$name verwijderen';
  }

  @override
  String get venueEditTitle => 'Locatie bewerken';

  @override
  String get venueEditorSharedNote =>
      'Een locatie is gedeeld over elk programma dat hier wordt gehouden, dus bewerkingen van het adres, contacten of schema zijn zichtbaar op al die programma’s.';

  @override
  String get venueEditorNameLabel => 'Naam *';

  @override
  String get venueEditorNameRequired => 'Naam is vereist';

  @override
  String get venueEditorWebsiteLabel => 'Website';

  @override
  String get venueEditorSponsorLabel => 'Sponsor / organiserende organisatie';

  @override
  String get venueEditorAddressSection => 'Adres';

  @override
  String get venueEditorAddress1Label => 'Adresregel 1';

  @override
  String get venueEditorAddress2Label => 'Adresregel 2';

  @override
  String get venueEditorCityLabel => 'Stad';

  @override
  String get venueEditorStateLabel => 'Provincie / staat';

  @override
  String get venueEditorCountryLabel => 'Land';

  @override
  String get venueEditorPostalLabel => 'Postcode';

  @override
  String get venueEditorPlus4Label => 'ZIP+4';

  @override
  String get venueEditorScheduleSection => 'Schema';

  @override
  String get venueEditorEventNameLabel => 'Eventnaam';

  @override
  String get venueEditorTimeLabel => 'Tijdstip';

  @override
  String get venueEditorScheduleLabel => 'Schema (bijv. “2e zaterdagen”)';

  @override
  String get venueEditorPriceLabel => 'Prijs';

  @override
  String get venueEditorContactsSection => 'Contacten';

  @override
  String get venueEditorContact1NameLabel => 'Contactpersoon 1 naam';

  @override
  String get venueEditorContact1PhoneLabel => 'Contactpersoon 1 telefoon';

  @override
  String get venueEditorContact1EmailLabel => 'Contactpersoon 1 e-mail';

  @override
  String get venueEditorContact2NameLabel => 'Contactpersoon 2 naam';

  @override
  String get venueEditorContact2PhoneLabel => 'Contactpersoon 2 telefoon';

  @override
  String get venueEditorContact2EmailLabel => 'Contactpersoon 2 e-mail';

  @override
  String get venueEditorNotesSection => 'Notities';

  @override
  String get venuePickerLoading => 'Locaties laden…';

  @override
  String get venuePickerUnlinkTooltip => 'Locatie ontkoppelen';

  @override
  String get venuePickerUnresolvedTitle => 'Gekoppelde locatie niet gevonden';

  @override
  String get venuePickerUnresolvedSubtitle => 'Het is mogelijk verwijderd.';

  @override
  String get venuePickerClearLinkTooltip => 'Koppeling wissen';

  @override
  String get venuePickerSearchHint => 'Locatie zoeken of toevoegen…';

  @override
  String get venuePickerChangeHint => 'Locatie wijzigen…';

  @override
  String venuePickerCreateOption(String name) {
    return 'Nieuwe locatie “$name” toevoegen';
  }
}
