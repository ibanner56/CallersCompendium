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
  String get danceEditorAddedMeanwhileAnnouncement =>
      'Een meanwhile-container is toegevoegd.';

  @override
  String get danceEditorAddedModifierAnnouncement =>
      'Een modifier-container is toegevoegd.';

  @override
  String get danceEditorAddedSequenceAnnouncement =>
      'Een reeks-container is toegevoegd.';

  @override
  String get navCollection => 'Collectie';

  @override
  String get settingsDefaultsMeanwhileTitle =>
      'Meanwhile-standaardinstellingen';

  @override
  String get settingsDefaultsMeanwhileSubtitle =>
      'De zijfiguren die worden ingevoegd wanneer je een meanwhile-container toevoegt. Maak de lijst leeg voor twee lege zijden; bij één ingestelde zijde wordt een lege tweede zijde toegevoegd. Je kunt de container na het invoegen bewerken.';

  @override
  String get settingsDefaultsModifierTitle =>
      'Standaardinstellingen voor modifiers';

  @override
  String get settingsDefaultsModifierSubtitle =>
      'De figuren die worden ingevoegd wanneer je een modifiercontainer toevoegt. Wis dit voor twee lege figuren; bij één ingestelde figuur wordt één lege begeleider toegevoegd.';

  @override
  String get navPrograms => 'Programma\'s';

  @override
  String get navSettings => 'Instellingen';

  @override
  String get navGlossary => 'Woordenlijst';

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
  String get menuFile => 'Archief';

  @override
  String get menuNewDance => 'Nieuwe dans';

  @override
  String get menuImportDances => 'Importeer dansen…';

  @override
  String get menuClose => 'Sluit';

  @override
  String get menuSettings => 'Instellingen…';

  @override
  String get menuView => 'Weergave';

  @override
  String get menuWindow => 'Venster';

  @override
  String get menuHelp => 'Help';

  @override
  String get menuUserGuide => 'Gebruikersgids';

  @override
  String get appBootstrapPreparing => 'Je bibliotheek voorbereiden';

  @override
  String get appBootstrapRebuildingIndex => 'Zoekindex opnieuw opbouwen';

  @override
  String appBootstrapRebuildingIndexProgress(int percent) {
    return 'Zoekindex opnieuw opbouwen… $percent%';
  }

  @override
  String get appBootstrapError =>
      'Je bibliotheek kon niet worden voorbereid. Probeer het opnieuw.';

  @override
  String get appBootstrapCopyDetails => 'Details kopiëren';

  @override
  String get appBootstrapCopiedDetails => 'Gekopieerd';

  @override
  String get appBootstrapLogHint =>
      'De details zijn ook naar het diagnoselogboek in de supportmap van de app geschreven.';

  @override
  String get appBootstrapReleasesLink => 'Releases-pagina openen';

  @override
  String migrationDowngradeVersions(int fileVersion, int appVersion) {
    final intl.NumberFormat fileVersionNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String fileVersionString = fileVersionNumberFormat.format(
      fileVersion,
    );
    final intl.NumberFormat appVersionNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String appVersionString = appVersionNumberFormat.format(appVersion);

    return 'Je gegevens gebruiken opslagformaat $fileVersionString. Deze versie van de app leest tot en met formaat $appVersionString.';
  }

  @override
  String get migrationDowngradeMessage =>
      'Deze gegevens zijn gemaakt met een nieuwere versie van Caller’s Compendium. Werk de app bij en open haar daarna opnieuw.';

  @override
  String get migrationRelocationBothExist =>
      'Caller’s Compendium is niet gestart, omdat opgeslagen gegevensbestanden zowel op de nieuwe locatie als in een map van een eerdere versie zijn gevonden. Er is niets gewijzigd of verwijderd. Bewaar de kopie die je wilt houden, verplaats de andere naar een andere plek en open de app daarna opnieuw. In het FAQ-onderdeel “Waar worden mijn gegevens opgeslagen?” staan de locaties.';

  @override
  String get migrationRelocationMultipleLegacy =>
      'Caller’s Compendium is niet gestart, omdat opgeslagen gegevens in meer dan één map van eerdere versies zijn gevonden. Er is niets gewijzigd of verwijderd. Bewaar de kopie die je wilt houden, verplaats de andere naar een andere plek en open de app daarna opnieuw. In het FAQ-onderdeel “Waar worden mijn gegevens opgeslagen?” staan de locaties.';

  @override
  String get migrationRelocationFailed =>
      'Caller’s Compendium is niet gestart, omdat het verplaatsen van je opgeslagen gegevens naar de nieuwe locatie niet kon worden voltooid. Er is niets verwijderd. Maak ruimte vrij, sluit andere programma’s die de gegevens mogelijk gebruiken of controleer de maprechten en open de app daarna opnieuw om het opnieuw te proberen.';

  @override
  String get migrationRelocationLegacyUnreachable =>
      'Caller’s Compendium is niet gestart, omdat je map Documenten, waarin eerdere versies je opgeslagen gegevens bewaarden, niet bereikbaar was. Er is niets gewijzigd of aangemaakt. Staat Documenten op een ander station of in een netwerkmap, sluit die dan opnieuw aan en open de app daarna opnieuw. Heb je geen map Documenten, maak dan een lege aan en open de app daarna opnieuw. In het FAQ-onderdeel “Waar worden mijn gegevens opgeslagen?” lees je meer.';

  @override
  String get migrationRelocationCopiesHeading =>
      'Grootte en laatste wijziging van elke kopie (de grootste, meest recent gewijzigde kopie is meestal je bibliotheek):';

  @override
  String get migrationRelocationCopyNewLocation => 'Nieuwe locatie';

  @override
  String get migrationRelocationCopyDocuments => 'Map Documenten';

  @override
  String get migrationRelocationCopyEarlierAppFolder =>
      'Eerdere app-gegevensmap';

  @override
  String migrationRelocationCopyDetails(
    String location,
    int kilobytes,
    String date,
  ) {
    final intl.NumberFormat kilobytesNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String kilobytesString = kilobytesNumberFormat.format(kilobytes);

    return '$location: $kilobytesString KB, laatst gewijzigd $date';
  }

  @override
  String migrationSnapshotAbortedMessage(String cause) {
    return 'Caller’s Compendium is niet gestart omdat er geen automatische back-up kon worden gemaakt voordat je opgeslagen gegevens werden gewijzigd. ${cause}Maak ruimte vrij (of herstel de back-upmap) en open de app dan opnieuw — of open opnieuw en kies om zonder back-up door te gaan.';
  }

  @override
  String get migrationSnapshotCauseDiskFull =>
      'Je apparaat lijkt weinig opslagruimte te hebben.';

  @override
  String get migrationSnapshotCauseUnwritableBackupsDir =>
      'Naar de map voor automatische back-ups kon niet worden geschreven.';

  @override
  String get migrationSnapshotCauseDatabaseInUse =>
      'Een andere app heeft je bibliotheek geopend, dus een back-up die nu wordt gemaakt, zou je laatste wijzigingen missen. Sluit elke andere app die je bibliotheek geopend heeft en probeer het dan opnieuw.';

  @override
  String get migrationSnapshotInUseConsentBody =>
      'Voordat je opgeslagen gegevens worden gewijzigd, maakt Caller’s Compendium een automatische back-up zodat de wijzigingen ongedaan kunnen worden gemaakt als er iets misgaat. Een andere app heeft je bibliotheek nu geopend, dus een back-up die nu wordt gemaakt, zou je laatste wijzigingen missen.\n\nAls je zonder back-up doorgaat en de wijzigingen worden onderbroken, kunnen sommige van je dansen of programma’s verloren gaan. Je kunt afsluiten, elke andere app sluiten die je bibliotheek geopend heeft, en Caller’s Compendium opnieuw openen om het nog eens te proberen.';

  @override
  String get migrationSnapshotInUseAbortedMessage =>
      'Caller’s Compendium is niet gestart omdat een andere app je bibliotheek geopend heeft, waardoor de automatische back-up die vóór het wijzigen van je opgeslagen gegevens wordt gemaakt, je laatste wijzigingen zou missen. Sluit elke andere app die je bibliotheek geopend heeft en open Caller’s Compendium dan opnieuw — of open het opnieuw en kies om zonder back-up door te gaan.';

  @override
  String get migrationSnapshotConsentTitle => 'Kon je gegevens niet back-uppen';

  @override
  String migrationSnapshotConsentBody(String cause) {
    return 'Voordat je opgeslagen gegevens worden gewijzigd, maakt Caller’s Compendium een automatische back-up zodat de wijzigingen ongedaan kunnen worden gemaakt als er iets misgaat. Die back-up kon deze keer niet worden gemaakt.$cause\n\nAls je zonder back-up doorgaat en de wijzigingen worden onderbroken, kunnen sommige van je dansen of programma’s verloren gaan. Je kunt afsluiten, ruimte vrijmaken (of de back-upmap herstellen) en de app opnieuw openen om het nog eens te proberen.';
  }

  @override
  String get migrationSnapshotConsentQuit => 'Afsluiten';

  @override
  String get migrationSnapshotConsentProceed => 'Doorgaan zonder back-up';

  @override
  String get migrationBelowFloorHeadline =>
      'Deze gegevens zijn van een versie die te oud is om te openen';

  @override
  String migrationBelowFloorBody(String bridgeTag) {
    return 'Je gegevens kunnen worden hersteld. Installeer $bridgeTag, open de app één keer zodat je gegevens worden bijgewerkt en installeer daarna deze versie opnieuw.\n\nAls je liever opnieuw begint, gebruik dan de opties hieronder — je huidige gegevens gaan verloren.';
  }

  @override
  String migrationBelowFloorBodyAndroid(String bridgeTag) {
    return 'Je gegevens staan nog op dit apparaat, maar deze versie kan ze hier niet bijwerken. Verwijder de app niet: daarmee worden je gegevens gewist, en Android installeert $bridgeTag sowieso niet over deze versie heen. Wil je je gegevens houden, kies dan ‘Een kopie van je gegevens delen’ en bewaar het bestand buiten de app, bijvoorbeeld op een computer of in cloudopslag. Een computer met $bridgeTag kan ze bijwerken, en daarna kan deze app ze terugzetten: zie ‘Zo werk je ze bij op een computer’.\n\nAls je liever opnieuw begint, gebruik dan de opties hieronder — je huidige gegevens gaan verloren.';
  }

  @override
  String migrationBelowFloorBodyIos(String bridgeVersion) {
    return 'Je gegevens staan nog op dit apparaat. Verwijder de app niet: daarmee worden je gegevens gewist. Open in TestFlight Caller’s Compendium en zoek onder ‘Vorige builds’ naar versie $bridgeVersion. Staat die erbij, installeer haar dan, open de app één keer zodat je gegevens worden bijgewerkt en installeer daarna weer de nieuwste build. Staat die er niet bij, kies dan ‘Een kopie van je gegevens delen’ en werk ze in plaats daarvan bij op een computer: zie ‘Zo werk je ze bij op een computer’.\n\nAls je liever opnieuw begint, gebruik dan de opties hieronder — je huidige gegevens gaan verloren.';
  }

  @override
  String get migrationBelowFloorShareCopy => 'Een kopie van je gegevens delen';

  @override
  String get migrationBelowFloorShareBackup => 'Kopie delen';

  @override
  String get migrationBelowFloorBackupKeptInApp =>
      'De back-up staat in de app, waar je hem niet kunt openen. Wil je een kopie houden die je op een computer kunt gebruiken, kies dan ‘Kopie delen’ voordat je reset.';

  @override
  String get migrationBelowFloorShareCopyFailedTitle => 'Kan geen kopie maken';

  @override
  String get migrationBelowFloorShareCopyFailedBody =>
      'Er is niets gedeeld en je gegevens zijn niet gewijzigd. Maak wat ruimte vrij en probeer het dan opnieuw.';

  @override
  String get migrationBelowFloorShareSheetFailedTitle =>
      'Kan het deelmenu niet openen';

  @override
  String get migrationBelowFloorShareSheetFailedBody =>
      'De kopie is gemaakt, maar kon niet worden gedeeld. Je gegevens zijn niet gewijzigd. Probeer het opnieuw.';

  @override
  String get migrationBelowFloorComputerGuide =>
      'Zo werk je ze bij op een computer';

  @override
  String migrationBelowFloorGetBridge(String bridgeTag) {
    return '$bridgeTag ophalen';
  }

  @override
  String get migrationBelowFloorStartFresh => 'Begin opnieuw';

  @override
  String get migrationBelowFloorBackUpAndReset => 'Back-up maken + Resetten';

  @override
  String get migrationBelowFloorResetOnly => 'Alleen resetten';

  @override
  String get migrationBelowFloorBackupFailedTitle => 'Back-up mislukt';

  @override
  String get migrationBelowFloorBackupFailedBody =>
      'De back-up kon niet worden geschreven, dus je gegevens zijn niet gereset. Maak ruimte vrij en probeer het opnieuw.';

  @override
  String get migrationBelowFloorResetConfirmTitle => 'App-gegevens resetten?';

  @override
  String get migrationBelowFloorResetConfirmBody =>
      'Er is een back-up opgeslagen. Door te resetten worden je huidige gegevens vervangen door een nieuwe, lege database.';

  @override
  String get migrationBelowFloorResetConfirmAction => 'Resetten';

  @override
  String migrationBelowFloorBackupSavedAt(String backupPath) {
    return 'Back-up opgeslagen in: $backupPath';
  }

  @override
  String migrationBelowFloorDiagnosticLogSavedAt(String logPath) {
    return 'Diagnoselogboek opgeslagen in: $logPath';
  }

  @override
  String get migrationBelowFloorResetOnlyConfirmBody =>
      'Er wordt geen back-up gemaakt. Door te resetten worden al je huidige gegevens definitief verwijderd en vervangen door een nieuwe, lege database. Dit kan niet ongedaan worden gemaakt.';

  @override
  String get migrationBelowFloorWipeFailedTitle => 'Opnieuw instellen mislukt';

  @override
  String get migrationBelowFloorWipeFailedBody =>
      'Het databasebestand kon niet worden verwijderd. Je gegevens zijn niet gewijzigd. Sluit andere apps die het bestand mogelijk gebruiken en probeer het opnieuw.';

  @override
  String get confirmDeleteTitle => 'Verwijderen?';

  @override
  String confirmDeleteBody(String itemLabel) {
    return '“$itemLabel” wordt verwijderd. Je kunt dit ongedaan maken.';
  }

  @override
  String confirmDeleteDancesBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count dansen worden verwijderd. Je kunt dit ongedaan maken.',
      one: '1 dans wordt verwijderd. Je kunt dit ongedaan maken.',
    );
    return '$_temp0';
  }

  @override
  String confirmDeleteDancesNotShownBody(int count, int notShown) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count dansen worden verwijderd, waarvan $notShown verborgen door je zoekopdracht. Je kunt dit ongedaan maken.',
      one:
          '1 dans wordt verwijderd. Je zoekopdracht verbergt hem. Je kunt dit ongedaan maken.',
    );
    return '$_temp0';
  }

  @override
  String confirmDeleteProgramHistoryBody(String itemLabel, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count dansen verliezen dit programma uit hun callerhistorie.',
      one: '1 dans verliest dit programma uit zijn callerhistorie.',
    );
    return '“$itemLabel” wordt verwijderd. $_temp0 Je kunt dit ongedaan maken.';
  }

  @override
  String get colorEditHexInvalid =>
      'Voer zes hexadecimale cijfers in, bijvoorbeeld #804020.';

  @override
  String get colorEditHexLabel => 'Hex';

  @override
  String get colorEditChannelRed => 'Rood';

  @override
  String get colorEditChannelGreen => 'Groen';

  @override
  String get colorEditChannelBlue => 'Blauw';

  @override
  String get settingsTitle => 'Instellingen';

  @override
  String get settingsGeneralTitle => 'Algemeen';

  @override
  String get settingsProgramTitle => 'Programma';

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
  String get settingsExperimentalTitle => 'Experimenteel';

  @override
  String get settingsDeveloperOptionsHeader => 'Ontwikkelaarsopties';

  @override
  String get settingsDeveloperResetTitle => 'Database resetten';

  @override
  String get settingsDeveloperResetSubtitle =>
      'Alles op dit apparaat verwijderen en opnieuw beginnen, zoals bij een verse installatie.';

  @override
  String get settingsDeveloperResetConfirmTitle => 'Database resetten?';

  @override
  String get settingsDeveloperResetConfirmBody =>
      'Hiermee wordt je hele bibliotheek op dit apparaat definitief verwijderd (elke dans, elk programma, elke instelling en notitie) en start de app opnieuw alsof hij net is geïnstalleerd. Dit kan niet ongedaan worden gemaakt.';

  @override
  String get settingsDeveloperResetConfirmSyncNote =>
      'Dit apparaat is verbonden met een synchronisatieopslag. Het verwijdert zichzelf eerst uit de opslag, zodat het niet als verweesd apparaat achterblijft. Alles wat het nog niet naar je andere apparaten heeft gesynchroniseerd, gaat verloren.';

  @override
  String get settingsDeveloperResetConfirmCheckbox =>
      'Ik begrijp dat dit niet ongedaan kan worden gemaakt en ik heb al een back-up gemaakt als ik die wil.';

  @override
  String get settingsDeveloperResetConfirmAction => 'Database resetten';

  @override
  String get settingsDeveloperResetLeaveFailed =>
      'Dit apparaat kon niet uit de synchronisatieopslag worden verwijderd, dus er is niets gereset. Controleer je verbinding en probeer het opnieuw.';

  @override
  String get settingsDeveloperResetFailed =>
      'De database kon niet worden gereset. Als dit apparaat met een synchronisatieopslag was verbonden, heeft het die al verlaten.';

  @override
  String get settingsExperimentalPlaceholder =>
      'Nieuwe functies kunnen hier verschijnen terwijl ze nog in ontwikkeling zijn.';

  @override
  String get glossaryTitle => 'Woordenlijst';

  @override
  String get glossarySearchHint => 'Figuren zoeken';

  @override
  String glossaryNoMatches(String query) {
    return 'Geen figuren komen overeen met ‘$query’.';
  }

  @override
  String get glossarySelectPrompt =>
      'Selecteer een figuur om de definitie te zien.';

  @override
  String get glossaryCopyAsOwnFigure => 'Kopiëren naar Eigen figuren';

  @override
  String glossaryCustomCopiedFrom(String name) {
    return 'Gekopieerd van $name';
  }

  @override
  String get importCcTermsTitle => 'Termen in dit bestand';

  @override
  String get importCcTermsIntro =>
      'Je Caller\'s Companion-bestand heeft eigen termen. Kies welke je als termen aan je woordenlijst toevoegt. Elke beschrijving begint als de definitie: bewerk een term om die, de definitie of de naam te wijzigen.';

  @override
  String get importCcTermsNameTaken =>
      'Een figuur, afkorting of term heeft deze naam al. Geef hem een andere naam om hem toe te voegen, of laat hem weg.';

  @override
  String get importCcTermsNeedsDefinition =>
      'Hij heeft geen definitie. Bewerk hem om er een te geven en hem toe te voegen.';

  @override
  String get importCcTermsIncomplete =>
      'Hij heeft een naam, een definitie en een beschrijving nodig. Bewerk hem om ze in te vullen en hem toe te voegen.';

  @override
  String get importCcTermsTooLong =>
      'Hij is langer dan een woordenlijstitem mag zijn. Bewerk hem om hem in te korten en toe te voegen.';

  @override
  String get importCcTermsEditTitle => 'Term bewerken';

  @override
  String importCcTermsEditLabel(String name) {
    return '$name bewerken';
  }

  @override
  String get importCcTermsSkip => 'Overslaan';

  @override
  String importCcTermsConfirm(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count termen toevoegen',
      one: '1 term toevoegen',
      zero: 'Termen toevoegen',
    );
    return '$_temp0';
  }

  @override
  String importCcTermsAdded(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count termen aan je woordenlijst toegevoegd.',
      one: '1 term aan je woordenlijst toegevoegd.',
    );
    return '$_temp0';
  }

  @override
  String importCcTermsFailed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count termen konden niet worden toegevoegd: ze zijn te lang, of je woordenlijst is vol.',
      one:
          '1 term kon niet worden toegevoegd: hij is te lang, of je woordenlijst is vol.',
    );
    return '$_temp0';
  }

  @override
  String glossaryTermSource(String source) {
    return 'Bron: $source';
  }

  @override
  String glossaryCustomShippedNameBody(String name) {
    return 'De app heeft nu een eigen figuur met de naam $name. Geef de jouwe een andere naam, of zet je dansen over op de figuur van de app en verwijder de jouwe.';
  }

  @override
  String get glossaryCustomRenameMine => 'Mijn figuur hernoemen';

  @override
  String get glossaryCustomSwitchToShipped =>
      'Overzetten op de figuur van de app';

  @override
  String userFigureSwitchTitle(String name) {
    return 'Overzetten op $name';
  }

  @override
  String userFigureSwitchIntro(String name) {
    return 'Kies welke parameter van $name elke parameter van je figuur wordt, en welke van de waarden elk van je opties wordt. Alles moet gekozen zijn voordat je kunt overzetten.';
  }

  @override
  String userFigureSwitchParam(String param) {
    return 'Je $param wordt';
  }

  @override
  String userFigureSwitchChoice(String choice) {
    return 'Je $choice wordt';
  }

  @override
  String userFigureSwitchNoTarget(String name, String param) {
    return '$name heeft niets wat je $param kan worden. Verwijder het eerst uit je figuur, of geef de jouwe liever een andere naam.';
  }

  @override
  String userFigureSwitchAllTaken(String name, String param) {
    return 'Elke parameter van $name die je $param kan worden, is al gekozen voor een andere van de jouwe. Kies daar eerst anders.';
  }

  @override
  String get userFigureSwitchAction => 'Overzetten';

  @override
  String userFigureSwitchConfirmTitle(String name) {
    return 'Overzetten op $name?';
  }

  @override
  String userFigureSwitchConfirmUses(int count, String name) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count dansen gebruiken je figuur en gaan $name gebruiken. De jouwe wordt uit je woordenlijst verwijderd.',
      one:
          '1 dans gebruikt je figuur en gaat $name gebruiken. De jouwe wordt uit je woordenlijst verwijderd.',
      zero:
          'Geen dans in je collectie gebruikt je figuur. Hij wordt uit je woordenlijst verwijderd.',
    );
    return '$_temp0';
  }

  @override
  String get userFigureSwitchConfirmDefaults =>
      'Je standaardfiguren gebruiken hem ook en worden op dezelfde manier overgezet.';

  @override
  String userFigureSwitchConfirmKeepsWording(String name) {
    return 'Elk gebruik van een groep dansers die $name niet heeft, behoudt in plaats daarvan zijn tekst.';
  }

  @override
  String userFigureSwitchConfirmShorthands(int count, String name) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Zijn $count afkortingen voegen dan $name in.',
      one: 'Zijn afkorting voegt dan $name in.',
    );
    return '$_temp0';
  }

  @override
  String get userFigureSwitchFailed =>
      'Er is niets overgezet: je figuur is gewijzigd of verdwenen. Open hem opnieuw om over te zetten.';

  @override
  String get glossaryNoDefinition => 'Nog geen definitie.';

  @override
  String glossaryVariantOf(String figure) {
    return 'Een variant van $figure.';
  }

  @override
  String glossaryNameWithDetail(String name, String detail) {
    return '$name ($detail)';
  }

  @override
  String get glossaryExample => 'Voorbeeld';

  @override
  String get glossaryParameters => 'Parameters';

  @override
  String get glossaryAlsoKnownAs => 'Ook bekend als';

  @override
  String get settingsExperimentalGlossaryHeader =>
      'Woordenlijst en eigen figuren';

  @override
  String get settingsExperimentalShowGlossaryTitle => 'Woordenlijst tonen';

  @override
  String get settingsExperimentalShowGlossarySubtitle =>
      'Voegt een woordenlijst van de ingebouwde figuren toe aan de navigatie, tussen Programma\'s en Instellingen.';

  @override
  String get settingsSyncHeader => 'Apparaatsynchronisatie';

  @override
  String get settingsSyncIntro =>
      'Houd je bibliotheek gelijk op je eigen apparaten. Apparaatsynchronisatie staat uit totdat je het aanzet, en er wordt niets verzonden zolang het uit staat.';

  @override
  String get settingsSyncEnableTitle => 'Apparaatsynchronisatie aanzetten';

  @override
  String get settingsSyncEnableSubtitle =>
      'Standaard uit. Als je het aanzet, wordt er niets verzonden totdat je een opslag hebt gekoppeld.';

  @override
  String get settingsSyncWifiOnlyTitle => 'Alleen synchroniseren via wifi';

  @override
  String get settingsSyncWifiOnlySubtitle =>
      'Standaard aan. Bij mobiele data wacht de synchronisatie tot je op wifi zit.';

  @override
  String get settingsSyncExcludeImportsTitle =>
      'Ongebruikte geïmporteerde dansen overslaan';

  @override
  String get settingsSyncExcludeImportsSubtitle =>
      'Standaard uit. Vermindert wat dit apparaat uploadt als je een grote geïmporteerde verzameling hebt; een dans die in een programma wordt gebruikt of vanuit een andere dans is gelinkt, wordt altijd meegenomen. Er wordt niets van je andere apparaten verwijderd, en als je het weer uitzet, worden de overgeslagen dansen opnieuw geüpload.';

  @override
  String get settingsSyncStatusHeader => 'Status';

  @override
  String get settingsSyncIdTitle => 'Je synchronisatiezin';

  @override
  String get settingsSyncIdMasked => 'Verborgen';

  @override
  String get settingsSyncIdShow => 'Synchronisatiezin tonen';

  @override
  String get settingsSyncIdHide => 'Synchronisatiezin verbergen';

  @override
  String get settingsSyncIdCopy => 'Synchronisatiezin kopiëren';

  @override
  String get settingsSyncIdCopied =>
      'Synchronisatiezin gekopieerd. Iedereen die hem heeft, kan je gedeelde bibliotheek openen, dus plak hem alleen op een apparaat dat van jou is.';

  @override
  String get settingsSyncIdCaution =>
      'Voer hem in op je andere apparaat om dat te verbinden. Daar staat je gedeelde bibliotheek, dus iedereen die hem heeft, kan die bibliotheek openen: alles lezen wat je synchroniseert, daarvan op elk verbonden apparaat iets wijzigen of verwijderen, en de hele opslag van de server verwijderen. Overstappen op een andere zin betekent alle apparaten ernaartoe verplaatsen.';

  @override
  String get settingsSyncStatusNotPaired =>
      'Nog niet gekoppeld aan een opslag.';

  @override
  String get settingsSyncStatusNeverSynced =>
      'Gekoppeld. Nog niet gesynchroniseerd.';

  @override
  String settingsSyncStatusLastSynced(String when) {
    return 'Laatst gesynchroniseerd: $when';
  }

  @override
  String settingsSyncEndpointStatus(String url) {
    return 'Synchroniseert met $url';
  }

  @override
  String settingsSyncCustomEndpointStatus(String url) {
    return 'Synchroniseert met een aangepaste server: $url';
  }

  @override
  String settingsSyncMergedDuplicates(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count dubbele dansen gevonden en samengevoegd.',
      one: '$count dubbele dans gevonden en samengevoegd.',
    );
    return '$_temp0';
  }

  @override
  String get settingsSyncStatusSyncing => 'Synchroniseren…';

  @override
  String get settingsSyncStatusFailed =>
      'De laatste synchronisatie is mislukt.';

  @override
  String get settingsSyncStatusSettingsUnreadable =>
      'De instellingen voor apparaatsynchronisatie konden niet worden gelezen, dus de hier getoonde instellingen kunnen verouderd zijn, en apparaatsynchronisatie kan uit staan, ook als je het had aangezet. Start de app opnieuw op om het nog eens te proberen.';

  @override
  String get syncRestoredCopyNotice =>
      'Apparaatsynchronisatie staat uit, omdat deze bibliotheek is hersteld uit een back-up van het apparaat. Zet het weer aan onder Instellingen ▸ Experimenteel ▸ Apparaatsynchronisatie, dan synchroniseert dit apparaat als een nieuw apparaat en niet als het apparaat waar de back-up van komt.';

  @override
  String get settingsSyncFailureUnreachable =>
      'Kan de synchronisatieserver niet bereiken.';

  @override
  String get settingsSyncFailureUnreachableAdvice =>
      'Controleer of dit apparaat online is. Als je een eigen server gebruikt, controleer dan of die draait en of het adres klopt.';

  @override
  String get settingsSyncFailureTimedOut =>
      'De synchronisatieserver deed te lang over een antwoord.';

  @override
  String get settingsSyncFailureTimedOutAdvice =>
      'Een trage of onstabiele verbinding is meestal de oorzaak. Probeer het opnieuw als de verbinding beter is.';

  @override
  String get settingsSyncFailureServerError =>
      'De synchronisatieserver liep zelf tegen een probleem aan.';

  @override
  String get settingsSyncFailureServerErrorAdvice =>
      'Er is niets mis met dit apparaat of je bibliotheek. Wacht even en probeer het opnieuw. Blijft het gebeuren, laat het dan weten aan wie de server beheert en geef de details door die hier staan.';

  @override
  String get settingsSyncFailureRateLimited =>
      'De synchronisatieserver vroeg dit apparaat het rustiger aan te doen.';

  @override
  String get settingsSyncFailureRateLimitedAdvice =>
      'Hij kreeg te veel verzoeken in korte tijd. Wacht een paar minuten voordat je het opnieuw probeert.';

  @override
  String get settingsSyncFailureStoreFull =>
      'De synchronisatieserver kan nu even niets meer opslaan.';

  @override
  String get settingsSyncFailureStoreFullAdvice =>
      'Wijzigingen van dit apparaat kunnen pas worden opgeslagen als er ruimte is. Als je Ongebruikte geïmporteerde dansen overslaan aanzet, kan dit apparaat minder uploaden. Als je een eigen server gebruikt, verhoog dan de opslaglimiet of maak schijfruimte vrij.';

  @override
  String get settingsSyncFailureTooLarge =>
      'Iets wat dit apparaat probeerde te uploaden is groter dan de synchronisatieserver accepteert.';

  @override
  String get settingsSyncFailureTooLargeAdvice =>
      'Als je een grote geïmporteerde collectie hebt, kan het aanzetten van Ongebruikte geïmporteerde dansen overslaan die onder de limiet brengen. Als je een eigen server gebruikt, controleer dan de limiet voor uploadgrootte.';

  @override
  String get settingsSyncFailureRejected =>
      'De synchronisatieserver weigerde wat dit apparaat stuurde.';

  @override
  String get settingsSyncFailureRejectedAdviceDefaultServer =>
      'Deze versie van de app is nieuwer dan de synchronisatieserver. Je wijzigingen zijn hier opgeslagen en worden gesynchroniseerd zodra de server is bijgewerkt.';

  @override
  String get settingsSyncFailureRejectedAdviceCustomServer =>
      'Werk je synchronisatieserver bij zodat die past bij deze versie van de app.';

  @override
  String get settingsSyncStatusWaiting =>
      'Wachten op synchronisatie. Je wijzigingen zijn hier opgeslagen.';

  @override
  String get settingsSyncQuotaNearlyFull => 'Je opslag is bijna vol.';

  @override
  String get settingsSyncQuotaExcludeImports =>
      'Ongebruikte geïmporteerde dansen overslaan';

  @override
  String settingsSyncNoticeNewerVersionItems(String items) {
    return 'Een ander apparaat gebruikt een nieuwere versie van de app. Werk de app op dit apparaat bij om $items te ontvangen. Als je ze hier bewerkt voordat je bijwerkt, kunnen de wijzigingen van het andere apparaat daarin verloren gaan.';
  }

  @override
  String settingsSyncNoticeCountDance(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count dansen',
      one: '1 dans',
    );
    return '$_temp0';
  }

  @override
  String settingsSyncNoticeCountProgram(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count programma\'s',
      one: '1 programma',
    );
    return '$_temp0';
  }

  @override
  String settingsSyncNoticeCountChoreographer(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count auteurs',
      one: '1 auteur',
    );
    return '$_temp0';
  }

  @override
  String settingsSyncNoticeCountTag(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tags',
      one: '1 tag',
    );
    return '$_temp0';
  }

  @override
  String settingsSyncNoticeCountCustomField(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count aangepaste velden',
      one: '1 aangepast veld',
    );
    return '$_temp0';
  }

  @override
  String settingsSyncNoticeCountDifficulty(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count moeilijkheidsgraden',
      one: '1 moeilijkheidsgraad',
    );
    return '$_temp0';
  }

  @override
  String settingsSyncNoticeCountPublishedSource(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count gepubliceerde bronnen',
      one: '1 gepubliceerde bron',
    );
    return '$_temp0';
  }

  @override
  String settingsSyncNoticeCountVenue(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count locaties',
      one: '1 locatie',
    );
    return '$_temp0';
  }

  @override
  String settingsSyncNoticeCountSetting(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count instellingen',
      one: '1 instelling',
    );
    return '$_temp0';
  }

  @override
  String settingsSyncNoticeCountGlossaryEntry(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count van je eigen figuren',
      one: '1 van je eigen figuren',
    );
    return '$_temp0';
  }

  @override
  String settingsSyncNoticeCountFigureNote(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'je notities bij $count figuren',
      one: 'je notities bij 1 figuur',
    );
    return '$_temp0';
  }

  @override
  String get settingsSyncNoticeNewerVersionUncounted =>
      'Een ander apparaat gebruikt een nieuwere versie van de app. Werk de app op dit apparaat bij om de wijzigingen ervan te ontvangen. Als je hier iets bewerkt dat het heeft gewijzigd voordat je bijwerkt, kunnen de wijzigingen ervan verloren gaan.';

  @override
  String settingsSyncNoticeKeptNewerItems(String items) {
    return 'Bewaard voor een nieuwere versie van de app: $items. Deze worden nog steeds gesynchroniseerd, met details die deze versie niet kan tonen. Werk de app op dit apparaat bij om ze te zien.';
  }

  @override
  String get settingsSyncCopyDetails => 'Details kopiëren';

  @override
  String get settingsSyncDetailsCopied => 'Details gekopieerd.';

  @override
  String get settingsSyncFailureAccessDenied =>
      'De synchronisatieserver accepteerde de synchronisatiezin van dit apparaat niet.';

  @override
  String get settingsSyncFailureAccessDeniedAdvice =>
      'Vergelijk de zin met die op je andere apparaat en controleer of het serveradres klopt.';

  @override
  String get settingsSyncFailureUnexpectedResponse =>
      'De synchronisatieserver stuurde een antwoord waar deze app niets mee kon.';

  @override
  String get settingsSyncFailureUnexpectedResponseAdvice =>
      'Als je een eigen server gebruikt, controleer dan het adres en of het een versie is die deze app ondersteunt. Werk anders de app bij en probeer het later opnieuw.';

  @override
  String get settingsSyncFailurePeerUnavailable =>
      'Kan niet lezen wat een van je andere apparaten het laatst heeft gedeeld.';

  @override
  String get settingsSyncFailurePeerUnavailableAdvice =>
      'Om verbinding te maken met een opslag is de nieuwste lijst van elk apparaat erop nodig. Open de app op je andere apparaten, laat ze synchroniseren en probeer het dan opnieuw. Is een apparaat voorgoed weg, verwijder het dan onder Andere apparaten.';

  @override
  String get settingsSyncFailureInternal =>
      'Synchroniseren is gestopt door een probleem in de app.';

  @override
  String get settingsSyncFailureInternalAdvice =>
      'Dit is geen probleem met je verbinding of de server. Probeer het opnieuw. Blijft het gebeuren, exporteer dan het log via Instellingen ▸ Diagnostics en voeg het toe wanneer je het probleem meldt.';

  @override
  String settingsSyncFailureStep(String step) {
    String _temp0 = intl.Intl.selectLogic(step, {
      'lookup': 'Gestopt tijdens het opzoeken van de opslag.',
      'download': 'Gestopt tijdens het downloaden van je andere apparaten.',
      'upload':
          'Gestopt tijdens het uploaden van de wijzigingen van dit apparaat.',
      'publish':
          'Gestopt tijdens het publiceren van de wijzigingen van dit apparaat.',
      'createStore': 'Gestopt tijdens het aanmaken van de opslag.',
      'other': 'Halverwege gestopt.',
    });
    return '$_temp0';
  }

  @override
  String settingsSyncFailureStatusCode(int code) {
    return 'Statuscode van de server: $code.';
  }

  @override
  String settingsSyncFailureDetails(String details) {
    return 'Details: $details';
  }

  @override
  String commonSyncFailed(String explanation) {
    return 'De synchronisatie is niet afgerond. $explanation';
  }

  @override
  String settingsSyncNoticeAffected(String records) {
    return 'Betreft: $records';
  }

  @override
  String get settingsSyncNoticeListSeparator => ', ';

  @override
  String get commonListSeparator => ', ';

  @override
  String get commonClauseSeparator => '; ';

  @override
  String commonSentencePair(String first, String second) {
    return '$first $second';
  }

  @override
  String settingsSyncNoticeRecordNamed(String kind, String name) {
    return '$kind ‘$name’';
  }

  @override
  String settingsSyncNoticeRecordNotHere(String kind) {
    return '$kind, niet op dit apparaat';
  }

  @override
  String settingsSyncNoticeRecordNewerFigures(String kind, String name) {
    return '$kind ‘$name’ (bevat figuren die alleen een nieuwere versie kan lezen)';
  }

  @override
  String settingsSyncNoticeRecordNotHereNewerFigures(String kind) {
    return '$kind niet op dit apparaat (bevat figuren die alleen een nieuwere versie kan lezen)';
  }

  @override
  String settingsSyncNoticeAffectedMore(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'en nog $count',
    );
    return '$_temp0';
  }

  @override
  String settingsSyncNoticeFromDevices(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Van $count andere apparaten.',
      one: 'Van 1 ander apparaat.',
    );
    return '$_temp0';
  }

  @override
  String settingsSyncDevicesFailedBecause(String explanation) {
    return 'Kan de apparatenlijst niet laden. $explanation';
  }

  @override
  String settingsSyncAdminFailedBecause(String message, String explanation) {
    return '$message $explanation';
  }

  @override
  String get settingsSyncStatusStaleStore =>
      'Deze opslag is sinds je laatste synchronisatie vervangen door een ander apparaat. De volgende synchronisatie sluit zich aan bij de nieuwe.';

  @override
  String get settingsSyncStatusStoreUnavailable =>
      'Deze opslag is mogelijk verlopen door inactiviteit of verwijderd.';

  @override
  String get settingsSyncStatusStoreNotFound =>
      'Geen opslag heeft deze synchronisatiezin. Vergelijk hem met je andere apparaat.';

  @override
  String get settingsSyncStatusPaused =>
      'Synchronisatie is gepauzeerd omdat de opslag die dit apparaat gebruikte niet meer bestaat. Tik op Nu synchroniseren om opnieuw te beslissen.';

  @override
  String get settingsSyncNoticeDivergence =>
      'Sommige items zijn op twee apparaten op hetzelfde moment gewijzigd en verschillen nog steeds. Staan ze onder Synchronisatiebeslissingen, kies dan daar; bewerk er anders één om dit op te lossen.';

  @override
  String get syncConflictTitle => 'Kies welke versie je wilt bewaren';

  @override
  String get syncConflictIntro =>
      'Deze zijn op meer dan één apparaat gewijzigd, en de app kan niet bepalen welke wijziging moet winnen. Beide versies blijven bewaard tot je kiest.';

  @override
  String get syncConflictThisDevice => 'Dit apparaat';

  @override
  String get syncConflictOtherDevice => 'Een ander apparaat';

  @override
  String syncConflictOtherDeviceNumbered(int number) {
    return 'Een ander apparaat ($number)';
  }

  @override
  String get syncConflictKeepAllThisDevice => 'Alles van dit apparaat bewaren';

  @override
  String get syncConflictKeepAllOtherDevice =>
      'Alles van het andere apparaat bewaren';

  @override
  String get syncConflictApply => 'Selectie bewaren';

  @override
  String get syncConflictDecideLater => 'Annuleren';

  @override
  String get syncConflictShowDifferences => 'Verschillen tonen';

  @override
  String syncConflictChangedAt(String when) {
    return 'Gewijzigd op $when';
  }

  @override
  String get syncConflictOnlyHereHeader => 'Alleen op dit apparaat';

  @override
  String get syncConflictOnlyThereHeader => 'Alleen op het andere apparaat';

  @override
  String get syncConflictDifferentHeader => 'Verschillend op elk apparaat';

  @override
  String syncConflictSameCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Nog $count zijn op beide gelijk',
      one: 'Nog 1 is op beide gelijk',
    );
    return '$_temp0';
  }

  @override
  String syncConflictSummaryOnlyHere(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count alleen op dit apparaat',
      one: '1 alleen op dit apparaat',
    );
    return '$_temp0';
  }

  @override
  String syncConflictSummaryOnlyThere(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count alleen op het andere apparaat',
      one: '1 alleen op het andere apparaat',
    );
    return '$_temp0';
  }

  @override
  String syncConflictSummaryChanged(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count verschillend',
      one: '1 verschillend',
    );
    return '$_temp0';
  }

  @override
  String syncConflictDiffersInFields(String fields) {
    return 'Verschilt in: $fields';
  }

  @override
  String syncConflictComparedWith(String version) {
    return 'Vergeleken met $version';
  }

  @override
  String get syncConflictNothingToShow =>
      'Deze versies verschillen alleen in details die hier niet worden getoond.';

  @override
  String get syncConflictFiguresUnreadable =>
      'De figuren kunnen hier niet worden vergeleken.';

  @override
  String get syncConflictSlotsReordered =>
      'Dezelfde dansen, in een andere volgorde.';

  @override
  String get syncConflictSlotsDetailsDiffer =>
      'Dezelfde dansen, met andere details zoals tijden of alternatieven.';

  @override
  String get syncConflictUnknownItem => 'Niet op dit apparaat';

  @override
  String syncConflictVersionLine(String device, String value) {
    return '$device: $value';
  }

  @override
  String syncConflictFieldValue(String field, String value) {
    return '$field: $value';
  }

  @override
  String get syncConflictFieldName => 'Naam';

  @override
  String get syncConflictCombineBoth => 'Beide combineren';

  @override
  String syncConflictCombineSummary(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Bewaart alle $count items van beide apparaten',
      one: 'Bewaart het ene item van beide apparaten',
    );
    return '$_temp0';
  }

  @override
  String syncConflictCombineOverLimit(int count, int limit) {
    return 'Combineren kan niet: samen zouden het er $count zijn, en deze lijst bevat er hoogstens $limit.';
  }

  @override
  String get syncConflictCombinePickEach =>
      'Beide apparaten hebben deze gewijzigd. Kies voor elk welke je wilt bewaren:';

  @override
  String get syncConflictCombineUnavailable =>
      'Deze kunnen niet worden gecombineerd, dus er is niets gewijzigd.';

  @override
  String get syncConflictCombineOverLimitError =>
      'Samen zou dit meer zijn dan deze lijst kan bevatten, dus er is niets gewijzigd.';

  @override
  String get syncConflictSaved => 'Je keuzes zijn opgeslagen.';

  @override
  String get syncConflictUndo => 'Ongedaan maken';

  @override
  String get syncConflictReconsiderIntro =>
      'Kies opnieuw tussen de versies die je had. Er verandert niets tot je opslaat.';

  @override
  String get syncConflictUndoChanged =>
      'Na je keuze is er iets nieuwers binnengekomen, dus er is niets gewijzigd.';

  @override
  String get syncConflictFieldProvenance => 'Herkomst';

  @override
  String get syncConflictFieldColour => 'Kleur';

  @override
  String get syncConflictThemeBrightness => 'Licht of donker';

  @override
  String syncConflictFigureWalkthrough(String text) {
    return 'doorloop: $text';
  }

  @override
  String syncConflictFigureWording(String text) {
    return 'formulering: $text';
  }

  @override
  String syncConflictFigureDetailsDiffer(String figure) {
    return '$figure (andere details verschillen)';
  }

  @override
  String get syncConflictLinkInGroup => 'in de groep verwante dansen';

  @override
  String get syncConflictValueNotSet => 'Niet ingesteld';

  @override
  String get syncConflictValueOn => 'Aan';

  @override
  String get syncConflictValueOff => 'Uit';

  @override
  String syncConflictValueItems(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count items',
      one: '1 item',
      zero: 'Geen',
    );
    return '$_temp0';
  }

  @override
  String syncConflictValueNamesAndMore(String names, int count) {
    return '$names en nog $count';
  }

  @override
  String get syncConflictNone => 'Er valt nu niets te kiezen.';

  @override
  String get syncConflictClockWrong =>
      'De datum en tijd van dit apparaat lijken niet te kloppen, dus je keuze kon niet worden opgeslagen. Corrigeer de datum en tijd en probeer het opnieuw.';

  @override
  String get syncConflictFailed =>
      'Je keuze kon niet worden opgeslagen. Probeer het opnieuw.';

  @override
  String get syncSettingActiveCustomTheme => 'Gebruikt aangepast thema';

  @override
  String get syncSettingActiveDialect => 'Gebruikt dialect';

  @override
  String get syncSettingLastCollectionSort =>
      'Sortering van de collectie (laatst gebruikt)';

  @override
  String get syncSettingLastCollectionSortDirection =>
      'Sorteerrichting van de collectie (laatst gebruikt)';

  @override
  String get syncSettingLastProgramSort =>
      'Sortering van programma\'s (laatst gebruikt)';

  @override
  String get syncSettingLastProgramSortDirection =>
      'Sorteerrichting van programma\'s (laatst gebruikt)';

  @override
  String get syncSettingDefaultCollectionSortDirection =>
      'Sorteerrichting van de collectie (standaard)';

  @override
  String get syncSettingDefaultProgramSortDirection =>
      'Sorteerrichting van programma\'s (standaard)';

  @override
  String get syncSettingPerformStageTheme => 'Podiumthema in Uitvoeren';

  @override
  String settingsSyncConflictsSubtitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count items zijn op twee apparaten gewijzigd en wachten op je keuze.',
      one: '1 item is op twee apparaten gewijzigd en wacht op je keuze.',
    );
    return '$_temp0';
  }

  @override
  String get settingsSyncConflictsCheckFailed =>
      'Kon niet controleren op conflicten. Probeer het opnieuw.';

  @override
  String commonSyncNowConflictsTooltip(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Nu synchroniseren ($count items wachten op je keuze)',
      one: 'Nu synchroniseren (1 item wacht op je keuze)',
    );
    return '$_temp0';
  }

  @override
  String get settingsSyncNoticeKeptLocalCreation =>
      'Iets dat op dit apparaat is gemaakt, zou zijn verwijderd door een ander apparaat dat het nooit had gezien. Het is hier in plaats daarvan bewaard.';

  @override
  String get settingsSyncNoticeQuarantinedLocal =>
      'Sommige items op dit apparaat hebben een datum die de app niet kan vertrouwen, dus ze worden niet naar je andere apparaten gestuurd. Controleer de datum en tijd op dit apparaat en bewerk daarna een van de items om het een nieuwe datum te geven.';

  @override
  String get settingsSyncNoticeWithheldUnreadable =>
      'Sommige dansen op dit apparaat hebben opgeslagen figuren of deuntjes die de app niet kan lezen, dus ze worden niet naar je andere apparaten gestuurd. Er is niets verwijderd — open er een en voer de figuren of deuntjes opnieuw in om die dans mee te nemen.';

  @override
  String get settingsSyncNoticeSkippedRecord =>
      'Sommige records van een ander apparaat konden niet worden gebruikt en zijn overgeslagen. Controleer of je andere apparaten dezelfde app-versie gebruiken en synchroniseer opnieuw.';

  @override
  String get settingsSyncNoticeClock =>
      'De klok van een ander apparaat lijkt sterk af te wijken van die van dit apparaat. Controleer de datum en tijd op je apparaten — synchronisatie bepaalt daarmee welke bewerking nieuwer is.';

  @override
  String get settingsSyncNoticeDeferredInbound =>
      'Een update van een ander apparaat kwam binnen terwijl je hetzelfde record bewerkte, dus die is niet toegepast. De volgende synchronisatie pikt hem op.';

  @override
  String settingsSyncNoticePeerNotTaking(int count, String tag) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Apparaat $tag synchroniseert, maar neemt $count wijzigingen van dit apparaat niet over. Ze zijn hier veilig. Het andere apparaat heeft misschien een app-update nodig, of de datum en tijd van dit apparaat kloppen niet.',
      one:
          'Apparaat $tag synchroniseert, maar neemt 1 wijziging van dit apparaat niet over. De wijziging is hier veilig. Het andere apparaat heeft misschien een app-update nodig, of de datum en tijd van dit apparaat kloppen niet.',
    );
    return '$_temp0';
  }

  @override
  String settingsSyncNoticeAwaitingDevice(String tag) {
    return 'Sommige nieuwe soorten gegevens op dit apparaat worden gesynchroniseerd zodra apparaat $tag is bijgewerkt naar de nieuwste versie van de app of is verwijderd uit Andere apparaten. Ze zijn hier veilig.';
  }

  @override
  String get settingsSyncNoticeNeedsYou => 'Actie nodig';

  @override
  String get settingsSyncNoticeSeeDevices => 'Andere apparaten bekijken';

  @override
  String get settingsSyncNotBackup =>
      'Synchronisatie is geen back-up. Een opslag die 30 dagen niet wordt gebruikt, wordt verwijderd, dus blijf bestandsback-ups maken.';

  @override
  String get settingsSyncExpiryWarning =>
      'Deze opslag is al een tijdje niet gesynchroniseerd en wordt na 30 dagen zonder gebruik verwijderd. Open de app op een gekoppeld apparaat en synchroniseer om hem te behouden.';

  @override
  String get settingsSyncNowTitle => 'Nu synchroniseren';

  @override
  String get settingsSyncDisconnectTitle => 'Dit apparaat loskoppelen';

  @override
  String get settingsSyncDisconnectSubtitle =>
      'Stop hier met synchroniseren. Je bibliotheek blijft zoals ze is, hier en op je andere apparaten.';

  @override
  String get settingsSyncDisconnectConfirmTitle => 'Dit apparaat loskoppelen?';

  @override
  String get settingsSyncDisconnectConfirmBody =>
      'Dit apparaat stopt met synchroniseren en vergeet zijn synchronisatiezin. Je bibliotheek op dit apparaat blijft zoals ze is, en op je andere apparaten ook. Bij het loskoppelen wordt dit apparaat uit de synchronisatieopslag verwijderd als je andere apparaten er al alles van hebben. Is dat niet zo, dan blijft het onder Andere apparaten in de lijst staan tot je het daar verwijdert. Om later opnieuw te verbinden heb je de zin nodig, dus zorg dat je hem hebt.';

  @override
  String get settingsSyncDisconnectConfirmAction => 'Loskoppelen';

  @override
  String get settingsSyncDisconnectFailed =>
      'Kan dit apparaat niet loskoppelen. Het is nog steeds verbonden; probeer het opnieuw.';

  @override
  String get settingsSyncDevicesTitle => 'Andere apparaten';

  @override
  String get settingsSyncDevicesSubtitle =>
      'Bekijk wat er nog meer met deze opslag verbonden is, en verwijder een apparaat dat je niet meer gebruikt.';

  @override
  String get settingsSyncDevicesScreenTitle => 'Andere apparaten';

  @override
  String get settingsSyncDevicesCaution =>
      'Elk apparaat bedenkt zijn eigen willekeurige identificatie, en bij elke verbinding een nieuwe, dus apparaten worden hier getoond met een kort label uit die identificatie in plaats van met een naam. Dit apparaat staat niet in de lijst; zijn eigen label staat hieronder, zodat je het op je andere apparaten kunt terugvinden. Weet je niet zeker welk apparaat je moet verwijderen, dan kun je het veilig laten staan: een apparaat dat je verwijdert, kan met de synchronisatiezin opnieuw verbinden.';

  @override
  String settingsSyncDevicesThisDevice(String tag) {
    return 'Dit apparaat: $tag';
  }

  @override
  String settingsSyncDeviceTag(String tag) {
    return 'Apparaat $tag';
  }

  @override
  String get settingsSyncDeviceLastSharedToday =>
      'Heeft vandaag voor het laatst wijzigingen gedeeld';

  @override
  String settingsSyncDeviceLastSharedDays(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Heeft $count dagen geleden voor het laatst wijzigingen gedeeld',
      one: 'Heeft gisteren voor het laatst wijzigingen gedeeld',
    );
    return '$_temp0';
  }

  @override
  String settingsSyncDeviceLastSharedWeeks(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Heeft ongeveer $count weken geleden voor het laatst wijzigingen gedeeld',
      one:
          'Heeft ongeveer een week geleden voor het laatst wijzigingen gedeeld',
    );
    return '$_temp0';
  }

  @override
  String settingsSyncDeviceWaiting(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count wijzigingen van dit apparaat wachten nog op dat apparaat.',
      one: '1 wijziging van dit apparaat wacht nog op dat apparaat.',
    );
    return '$_temp0';
  }

  @override
  String get settingsSyncDevicesEmptyTitle => 'Nog geen andere apparaten';

  @override
  String get settingsSyncDevicesEmptyBody =>
      'Andere apparaten die met deze opslag zijn verbonden, verschijnen hier.';

  @override
  String get settingsSyncDevicesFailed =>
      'Kan de apparatenlijst niet laden. Controleer je verbinding en probeer het opnieuw.';

  @override
  String get settingsSyncDevicesStoreMissing =>
      'Deze opslag staat niet meer op de server, dus er zijn geen apparaten om te tonen.';

  @override
  String get settingsSyncDevicesRetry => 'Opnieuw proberen';

  @override
  String get settingsSyncDeviceRemoveTooltip => 'Dit apparaat verwijderen';

  @override
  String get settingsSyncDeviceRemoveTitle => 'Dit apparaat verwijderen?';

  @override
  String get settingsSyncDeviceRemoveBody =>
      'De opslag laat de lijst van wat dit apparaat heeft gedeeld los en maakt de plek vrij die het innam. Er wordt niets van dat apparaat verwijderd, en er wordt niets van het jouwe verwijderd. Dit is bedoeld voor een apparaat dat echt weg is: verwijderen koppelt het niet los, dus een apparaat dat nog draait publiceert zijn lijst bij de volgende synchronisatie opnieuw, en elk apparaat kan met de synchronisatiezin opnieuw verbinden.';

  @override
  String get settingsSyncDeviceRemoveAction => 'Verwijderen';

  @override
  String get settingsSyncDeviceRemoveFailed =>
      'Kan dat apparaat niet verwijderen. Het is nog steeds verbonden; probeer het opnieuw.';

  @override
  String get settingsSyncWipeTitle =>
      'Alle apparaten loskoppelen en de opslag verwijderen';

  @override
  String get settingsSyncWipeSubtitle =>
      'Verwijder alles wat deze opslag bevat, voor alle apparaten tegelijk. Dit kan niet ongedaan worden gemaakt.';

  @override
  String get settingsSyncWipeConfirmTitle =>
      'Deze opslag van de server verwijderen?';

  @override
  String get settingsSyncWipeConfirmBody =>
      'Alles wat de opslag bevat, wordt van de server verwijderd, voor alle apparaten tegelijk. Dit kan niet ongedaan worden gemaakt. Je bibliotheek blijft op dit apparaat en op elk van je andere apparaten staan, maar wat alleen via synchronisatie op een ander apparaat terecht was gekomen, komt hier niet aan. Dit apparaat wordt losgekoppeld en vergeet zijn synchronisatiezin; je andere apparaten merken bij de volgende synchronisatie dat de opslag weg is en bieden aan een nieuwe zin in te stellen. Gebruik dit als je het adres van deze opslag niet meer wilt gebruiken: het is het enige wat bewaarde gegevens meteen verwijdert. Wil je blijven synchroniseren, stel dan op elk apparaat een nieuwe zin in: opnieuw verbinden met de oude zin zet een nieuwe opslag terug op hetzelfde adres.';

  @override
  String get settingsSyncWipeConfirmAction => 'Opslag verwijderen';

  @override
  String get settingsSyncWipeFailed =>
      'Kan de opslag niet verwijderen, of kan niet bevestigen dat ze verwijderd is. Dit apparaat is nog steeds verbonden. Controleer je andere apparaten voordat je het opnieuw probeert.';

  @override
  String get settingsSyncWipeDetachFailed =>
      'De opslag is van de server verwijderd, maar dit apparaat kon de verbinding ermee niet verbreken. De opslag is weg en kan niet worden teruggehaald. Gebruik Dit apparaat loskoppelen om het af te ronden.';

  @override
  String get settingsSyncWipeDetachFailedTitle =>
      'Opslag verwijderd, dit apparaat nog verbonden';

  @override
  String get settingsSyncMeteredRouted =>
      'Je gebruikt mobiele data en ‘Alleen synchroniseren via wifi’ staat aan. Zet die instelling hieronder uit om nu te synchroniseren.';

  @override
  String get settingsSyncOffline =>
      'Geen verbinding op dit moment. De synchronisatie draait bij de eerste kans.';

  @override
  String get settingsSyncNotPairedNow =>
      'Koppel een opslag voordat je synchroniseert.';

  @override
  String get commonSyncNowTooltip => 'Nu synchroniseren';

  @override
  String get commonSyncMeteredBlocked =>
      'Je gebruikt mobiele data en ‘Alleen synchroniseren via wifi’ staat aan. Zet die instelling uit in Instellingen om nu te synchroniseren.';

  @override
  String get settingsSyncConnectTitle => 'Verbinden';

  @override
  String get settingsSyncPairingTitle => 'Apparaatsynchronisatie verbinden';

  @override
  String get settingsSyncPairingChooseHeading =>
      'Is dit het eerste apparaat, of voeg je er nog een toe?';

  @override
  String get settingsSyncPairingCreateTitle => 'Nieuwe opslag maken';

  @override
  String get settingsSyncPairingCreateSubtitle =>
      'Begin opnieuw. Je krijgt een zin om aan je andere apparaten voor te lezen.';

  @override
  String get settingsSyncPairingConnectTitle =>
      'Verbinden met bestaande opslag';

  @override
  String get settingsSyncPairingConnectSubtitle =>
      'Voer de zin in die op het al ingestelde apparaat wordt getoond.';

  @override
  String get settingsSyncPairingYourPhrase => 'Je synchronisatiezin';

  @override
  String get settingsSyncPairingYourPhraseHelper =>
      'Vier woorden gescheiden door koppeltekens. Houd de gegenereerde zin aan of typ je eigen zin.';

  @override
  String get settingsSyncPairingRegenerate => 'Andere zin genereren';

  @override
  String get settingsSyncPairingPersonalInfoTitle =>
      'Zet geen persoonlijke gegevens in de zin';

  @override
  String get settingsSyncPairingPersonalInfoBody =>
      'Als je je eigen zin typt, houd er dan namen, adressen, geboortedata en al het andere over jezelf uit. De zin gaat bij elk verzoek naar de server en wordt op elk apparaat dat je verbindt voorgelezen of ingetypt, dus behandel hem als iets dat aan de buitenkant van een doos staat, niet als plek voor privégegevens.';

  @override
  String get settingsSyncPairingWeakPhraseTitle =>
      'Deze zin is mogelijk makkelijk te raden';

  @override
  String get settingsSyncPairingWeakPhraseBody =>
      'Wie hem raadt, kan alles lezen en wijzigen wat je synchroniseert. Een gegenereerde zin is veel moeilijker te raden. Je kunt deze toch gebruiken.';

  @override
  String get settingsSyncPairingEnterPhrase => 'Synchronisatiezin';

  @override
  String get settingsSyncPairingEnterPhraseHint => 'woord-woord-woord-woord';

  @override
  String get settingsSyncPairingEndpointLabel => 'Server';

  @override
  String get settingsSyncPairingEndpointHelper =>
      'Laat dit ongewijzigd, tenzij je een eigen synchronisatieserver gebruikt.';

  @override
  String get settingsSyncPairingInvalidPhrase =>
      'Dat lijkt niet op een volledige synchronisatiezin.';

  @override
  String get settingsSyncPairingInvalidEndpoint =>
      'Dat is geen geldig serveradres. Gebruik een https://-adres zonder gebruikersnaam en zonder ?- of #-deel (gewone http:// werkt alleen voor localhost of 127.0.0.1).';

  @override
  String get settingsSyncPairingNotFound =>
      'Geen opslag heeft die zin. Vergelijk hem met het andere apparaat en probeer het opnieuw.';

  @override
  String get settingsSyncPairingAlreadyInUse =>
      'Die zin is al in gebruik door een andere opslag. Genereer een andere.';

  @override
  String settingsSyncPairingCustomEndpointTitle(String host) {
    return 'Aangepaste server: $host';
  }

  @override
  String get settingsSyncPairingCustomEndpointBody =>
      'Dit is niet de standaardserver voor apparaatsynchronisatie. Wie deze server beheert, kan alles wat je synchroniseert lezen, wijzigen en verwijderen. Gebruik dus alleen een server die je vertrouwt.';

  @override
  String get settingsSyncPairingSharingTitle => 'Delen is geen samenwerking';

  @override
  String get settingsSyncPairingSharingBody =>
      'Een tweede persoon kan dezelfde zin op zijn apparaat gebruiken. Als jullie tegelijk dezelfde dans of hetzelfde programma bewerken, overschrijft de ene bewerking stilzwijgend de andere — er is geen waarschuwing en geen manier om ze te combineren.';

  @override
  String get settingsSyncPairingNewerDataTitle =>
      'Elk apparaat heeft een bijgewerkte app nodig';

  @override
  String get settingsSyncPairingNewerDataBody =>
      'Deze versie synchroniseert een aantal dingen die eerdere versies van de app niet kunnen lezen. Werk elk apparaat bij voordat je het verbindt: een apparaat met een eerdere versie kan mogelijk geen verbinding maken. Tot alle verbonden apparaten zijn bijgewerkt, worden die dingen niet naar je andere apparaten gestuurd.';

  @override
  String get settingsSyncPairingBearerTitle =>
      'Iedereen met deze zin kan je bibliotheek openen';

  @override
  String get settingsSyncPairingBearerBody =>
      'De zin is waar je gedeelde bibliotheek staat, geen wachtwoord ervoor — er is nergens om in te loggen. Iedereen aan wie je hem geeft, en iedereen die hem zomaar tegenkomt, kan die bibliotheek vanaf zijn eigen apparaat openen: alles lezen wat je synchroniseert, daarvan overal waar het terecht is gekomen iets wijzigen of verwijderen, en het geheel van de server verwijderen. Er bestaat geen versie van een zin die minder kan.';

  @override
  String get settingsSyncPairingCredentialTitle =>
      'Er is geen kopie van deze zin, en terugnemen kan niet';

  @override
  String get settingsSyncPairingCredentialBody =>
      'Nergens anders is deze zin bekend, dus als je hem kwijtraakt, blijft de bibliotheek liggen waar hij staat en kan niemand er nog bij. Iemand de zin vertellen valt evenmin ongedaan te maken. Je apparaten naar een nieuwe zin verplaatsen begint alleen een tweede bibliotheek ergens anders: de eerste staat er nog, en wie de oude zin heeft bewaard, kan die nog steeds openen en wijzigen. Alleen de opslag verwijderen haalt hem er meteen weg.';

  @override
  String get settingsSyncPairingBackupOfferTitle =>
      'Eerst je bibliotheek back-uppen?';

  @override
  String get settingsSyncPairingBackupOfferBody =>
      'Dit is optioneel en alleen voor je eigen veiligheid — verbinden zelf maakt geen back-up.';

  @override
  String get settingsSyncPairingBackupOfferAccept => 'Nu back-uppen';

  @override
  String get settingsSyncPairingBackupOfferSkip => 'Niet nu';

  @override
  String get settingsSyncPairingContinue => 'Doorgaan';

  @override
  String get settingsSyncPairingComplete => 'Verbonden';

  @override
  String get settingsSyncPairingCompleteBody =>
      'Je bibliotheek is verbonden en de eerste synchronisatie is klaar.';

  @override
  String get settingsSyncPairingCompleteFailed =>
      'Je bibliotheek is verbonden, maar de eerste synchronisatie is niet afgerond. Hij probeert het vanzelf opnieuw.';

  @override
  String get settingsSyncPairingCompleteMetered =>
      'Je bibliotheek is verbonden. De eerste synchronisatie wacht op wifi, omdat ‘Alleen synchroniseren via wifi’ aan staat.';

  @override
  String get settingsSyncPairingCompleteOffline =>
      'Je bibliotheek is verbonden. De eerste synchronisatie draait zodra je weer online bent.';

  @override
  String get settingsSyncPairingCompletePending =>
      'Je bibliotheek is verbonden. De eerste synchronisatie is nog niet gedraaid; hij draait de volgende keer dat dit apparaat synchroniseert.';

  @override
  String get settingsSyncReplacementTitle => 'Deze opslag bestaat niet meer';

  @override
  String get settingsSyncReplacementBody =>
      'De opslag waarmee dit apparaat synchroniseerde, bestaat niet meer. Mogelijk is deze verlopen door inactiviteit, of is deze verwijderd. Om het adres van deze opslag niet meer te gebruiken, stel je een nieuwe zin in: dit apparaat wordt losgekoppeld, en daarna maak je een nieuwe opslag of verbind je met een opslag die je op een ander apparaat hebt ingesteld. Doe dit op elk van je apparaten. Opnieuw verbinden maakt in plaats daarvan een nieuwe opslag op hetzelfde adres, met dezelfde zin, en stuurt je hele bibliotheek daarheen; als een ander apparaat dat al heeft gedaan, sluit dit apparaat zich bij die opslag aan.';

  @override
  String get settingsSyncReplacementConfirm => 'Opnieuw verbinden';

  @override
  String get settingsSyncReplacementNewPhrase => 'Instellen met een nieuwe zin';

  @override
  String get settingsSyncReplacementCancel => 'Niet nu';

  @override
  String get settingsSyncReplacementFailed =>
      'De laatste poging om opnieuw te verbinden is niet gelukt. Je kunt het opnieuw proberen, of Niet nu kiezen en later beslissen.';

  @override
  String get settingsAboutTitle => 'Over';

  @override
  String get commonSystemDefault => 'Systeemstandaard';

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
      'Tokens: yyyy of yy = jaar, MM = maand (MMM = korte naam, MMMM = volledige naam), d of dd = dag. Scheidingstekens: - / . , of spatie.';

  @override
  String get settingsDateFormatCustomInvalid =>
      'Onbekend patroon — de systeemstandaard wordt gebruikt totdat dit is gecorrigeerd.';

  @override
  String get settingsFirstDayOfWeekTitle => 'Eerste dag van de week';

  @override
  String get settingsFirstDayOfWeekSubtitle =>
      'Welke dag de week begint in de eigen datumweergaven van de app, zoals de weekstrook van de programmalijst.';

  @override
  String get settingsFirstDayOfWeekSunday => 'Zondag';

  @override
  String get settingsFirstDayOfWeekMonday => 'Maandag';

  @override
  String get settingsFirstDayOfWeekSaturday => 'Zaterdag';

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
      'Caller\'s Compendium is vrije software, uitgebracht onder de GNU Affero General Public License, versie 3 (AGPL-3.0-only). Je mag het gebruiken, bestuderen, delen en aanpassen onder die licentie. Omdat de AGPL dit vereist, wordt de volledige bijbehorende broncode aangeboden aan iedereen die de app gebruikt.';

  @override
  String get settingsAboutViewSourceTitle => 'Broncode bekijken op GitHub';

  @override
  String get settingsAboutFontsHeader => 'Lettertypen';

  @override
  String get settingsAboutFontsBody =>
      'Deze app bevat de volgende lettertypen onder de SIL Open Font License 1.1. De volledige licentieteksten zijn beschikbaar onder “Licenties bekijken” hieronder.';

  @override
  String get settingsAboutFontFrauncesSubtitle =>
      'SIL Open Font License 1.1 · © The Fraunces Project Authors — display en koppen';

  @override
  String get settingsAboutFontAtkinsonSubtitle =>
      'SIL Open Font License 1.1 · © Braille Institute of America, Inc. — tekst, UI & Uitvoeren';

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
      'Dansgegevens zijn afkomstig van The Caller\'s Box (Chris Page & Michael Dyck), waarvan de collectie is gepubliceerd onder de Creative Commons Attribution-NonCommercial-licentie (CC BY-NC), met dankbaarheid.';

  @override
  String get settingsAboutLicensesHeader => 'Licenties';

  @override
  String get settingsAboutViewLicensesTitle => 'Licenties bekijken';

  @override
  String get settingsAboutViewLicensesSubtitle =>
      'Volledige open-source licentieteksten, inclusief de meegeleverde lettertypen.';

  @override
  String get settingsAboutLegalese =>
      '© De bijdragers van Caller\'s Compendium. Uitgebracht onder AGPL-3.0-only.';

  @override
  String get settingsAboutTagline => 'De caller-koffer in de palm van je hand';

  @override
  String settingsAboutVersion(String version, String codename) {
    return 'Versie $version, “$codename”';
  }

  @override
  String settingsAboutVersionLine(
    String appName,
    String codename,
    String license,
  ) {
    return '$appName · “$codename” · $license';
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
  String settingsUpdatesStatusCouldNotCheck(String version) {
    return 'Kon nu niet op updates controleren. Je gebruikt versie $version.';
  }

  @override
  String get settingsUpdatesStatusNewerFormat =>
      'Er is een nieuwere versie beschikbaar op de Releases-pagina.';

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
  String get settingsUpdatesAutoStoreSubtitle =>
      'Zoek bij het opstarten van de app op de achtergrond naar een einddatum van de ondersteuning voor deze versie. Standaard uit.';

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
      'Controleren of de download compleet en ongewijzigd is…';

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
  String get settingsUpdatesMacosReadyTitle => 'Bijwerken en opnieuw starten';

  @override
  String get settingsUpdatesMacosReadySubtitle =>
      'Je update is klaar. Koppel de schijfkopie aan en sluit de app zodat je deze in Programma\'s kunt vervangen.';

  @override
  String get settingsUpdatesStoreTitle => 'Updates komen uit je appstore';

  @override
  String get settingsUpdatesStoreSubtitle =>
      'Deze kopie is geïnstalleerd vanuit een appstore, dus de store werkt hem bij. De app zoekt alleen naar een einddatum van de ondersteuning, nooit naar een nieuwe versie.';

  @override
  String get settingsUpdatesPortableTitle =>
      'Draagbare kopie: download het nieuwe archief';

  @override
  String get settingsUpdatesPortableSubtitle =>
      'Deze kopie draait vanuit een uitgepakt archief, dus de app kan de update niet voor je installeren. Download de nieuwe zip of tar.gz van de release en pak hem uit.';

  @override
  String get settingsUpdatesDownloadTitle => 'Update downloaden en installeren';

  @override
  String get settingsUpdatesDownloadError =>
      'De update kon niet worden gedownload. Probeer het opnieuw.';

  @override
  String settingsUpdatesDownloadSubtitle(String version) {
    return 'Download versie $version, verifieer het en open je installer. De app vervangt zichzelf nooit ter plekke.';
  }

  @override
  String get settingsDialectHeader => 'Dialecten';

  @override
  String get settingsDialectFormHelper =>
      'Elk danstype heeft zijn eigen dialecten. Kies een type om de dialecten ervan te bekijken en in te stellen.';

  @override
  String get settingsDialectDanceDetailsHeader => 'Dansdetails en afkortingen';

  @override
  String get settingsDialectCanonicalFigureTextTitle => 'Canonieke figuurtekst';

  @override
  String get settingsDialectCanonicalFigureTextSubtitle =>
      'Als dit is ingeschakeld, kunnen dansdetails canonieke rol- en bewegingsnamen tonen en is de schakelaar Canoniek beschikbaar voor niet-canonieke dialecten. Standaard uit.';

  @override
  String get settingsDialectCanonicalDiscouragedTermsTitle =>
      'Alle afgeraden termen automatisch omzetten';

  @override
  String get settingsDialectCanonicalDiscouragedTermsSubtitle =>
      'Als deze optie is ingeschakeld, gebruiken dansdetails, notities en exports canonieke bewoording voor ondersteunde afgeraden termen. Opgeslagen tekst en invoervelden blijven ongewijzigd. Standaard ingeschakeld.';

  @override
  String get settingsDialectNewButton => 'Nieuw dialect';

  @override
  String get settingsDialectNewDefaultName => 'Mijn dialect';

  @override
  String get settingsDialectCreateConfirm => 'Aanmaken';

  @override
  String get settingsDialectDuplicateFrom => 'Dupliceren van…';

  @override
  String get settingsDialectDuplicateFromOtherForm =>
      'Dupliceren van een ander type…';

  @override
  String get settingsDialectDuplicateFromOtherFormEmpty =>
      'Nog geen ander danstype heeft een eigen dialect van je.';

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
  String settingsDialectEditConflictSnack(String name) {
    return '\"$name\" is hernoemd of verwijderd terwijl je het bewerkte, dus je wijzigingen zijn niet opgeslagen.';
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
  String get appThemeGroupSystem => 'Systeem';

  @override
  String get appThemeGroupDefault => 'Standaard';

  @override
  String get appThemeGroupLight => 'Licht';

  @override
  String get appThemeGroupDark => 'Donker';

  @override
  String get themeScreenSearchHint => 'Thema\'s zoeken…';

  @override
  String get themeScreenClearSearchTooltip => 'Zoekopdracht wissen';

  @override
  String get themeScreenNoMatches =>
      'Geen thema\'s komen overeen met je zoekopdracht.';

  @override
  String themeScreenResultCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count thema\'s',
      one: '1 thema',
    );
    return '$_temp0';
  }

  @override
  String get themeScreenNewCustomTheme => 'Aangepast thema';

  @override
  String get themeScreenNewCustomThemeSemantic => 'Nieuw aangepast thema';

  @override
  String get appThemeKeywordRed => 'rood, karmijn, scharlaken, koraal';

  @override
  String get appThemeKeywordOrange => 'oranje, amber, koper';

  @override
  String get appThemeKeywordYellow => 'geel, goud, mosterd';

  @override
  String get appThemeKeywordGreen => 'groen, salie, olijf, bos';

  @override
  String get appThemeKeywordTeal => 'blauwgroen, cyaan, turquoise, aqua, mint';

  @override
  String get appThemeKeywordBlue => 'blauw, marine, azuur, hemelsblauw';

  @override
  String get appThemeKeywordPurple => 'paars, violet, lila, lavendel';

  @override
  String get appThemeKeywordPink => 'roze, magenta, fuchsia';

  @override
  String get appThemeKeywordBrown => 'bruin, beige, zand, crème, sepia';

  @override
  String get appThemeKeywordGrey => 'grijs, antraciet, leisteen, zilver';

  @override
  String get appThemeKeywordWarm => 'warm, gezellig, aards';

  @override
  String get appThemeKeywordCool => 'koel, koud, ijzig, arctisch';

  @override
  String get appThemeKeywordPastel => 'pastel, zacht, snoep';

  @override
  String get appThemeKeywordVivid => 'levendig, fel, verzadigd, neon, krachtig';

  @override
  String get appThemeKeywordMuted => 'gedempt, ingetogen, rustig, mild';

  @override
  String get appThemeKeywordRetro => 'retro, vintage, klassiek';

  @override
  String get appThemeKeywordAccessible => 'toegankelijk, leesbaar, contrast';

  @override
  String get appThemeKeywordAutomatic => 'automatisch, auto, apparaat, volgen';

  @override
  String get appThemeLabelSystem => 'Systeem';

  @override
  String get appThemeLabelLight => 'Licht';

  @override
  String get appThemeLabelDark => 'Donker';

  @override
  String get appThemeLabelSoftDark => 'Zacht donker';

  @override
  String get appThemeLabelHighContrast => 'Hoog contrast';

  @override
  String get appThemeDescriptionSystem =>
      'Volgt de licht/donker-instelling van het apparaat';

  @override
  String get appThemeDescriptionLight => 'Warm lichtpalet';

  @override
  String get appThemeDescriptionDark => 'Warm donker palet';

  @override
  String get appThemeDescriptionSoftDark =>
      'Warm donker op een zachtere, lichtere ondergrond';

  @override
  String get appThemeDescriptionHighContrast =>
      'Maximaal contrast voor schemerige ruimtes en slechtziendheid';

  @override
  String get appThemeDescriptionBlulocoLight =>
      'Heldere, koel-neutrale ondergrond met levendige juweeltinten';

  @override
  String get appThemeDescriptionOneDarkPro =>
      'One Dark Pro, het populaire editorthema';

  @override
  String get appThemeDescriptionMonokai =>
      'One Monokai – Monokai-syntaxis op antraciet';

  @override
  String get appThemeDescriptionNoctis => 'De originele diepteal Noctis-nacht';

  @override
  String get appThemeDescriptionGithubLight =>
      'GitHubs heldere, neutrale licht';

  @override
  String get appThemeDescriptionCatppuccinLatte =>
      'Zacht pastellicht, favoriet van de community';

  @override
  String get appThemeDescriptionGruvboxLight =>
      'Warm retro-crème en aardtinten';

  @override
  String get appThemeDescriptionEverforestLight =>
      'Zacht groen, rustig voor de ogen';

  @override
  String get appThemeDescriptionRosePineDawn =>
      'Gedempt roze en iris op warm papier';

  @override
  String get appThemeDescriptionAyuLight =>
      'Helder, minimaal licht met amberkleurige accenten';

  @override
  String get appThemeDescriptionTokyoNightLight =>
      'Heldere indigo daglicht, de dag van Tokyo Night';

  @override
  String get appThemeDescriptionNordLight =>
      'Koele arctische sneeuwstorm-neutrale tinten';

  @override
  String get appThemeDescriptionKanagawaLotus =>
      'Warm sumi-e-papier met inktaccenten';

  @override
  String get appThemeDescriptionDracula =>
      'De klassieke favoriet: paars op antraciet';

  @override
  String get appThemeDescriptionNord =>
      'Koele arctische blauwtinten, ingetogen';

  @override
  String get appThemeDescriptionTokyoNight =>
      'Neon-indigo palet van een stad bij nacht';

  @override
  String get appThemeDescriptionGruvboxDark => 'Warm retro-amber op antraciet';

  @override
  String get appThemeDescriptionCatppuccinMocha =>
      'Gezellig pasteldonker, favoriet van de community';

  @override
  String get appThemeDescriptionGithubDark => 'GitHubs neutrale donker';

  @override
  String get appThemeDescriptionEverforestDark =>
      'Zacht bosgroen, weinig vermoeiend';

  @override
  String get appThemeDescriptionRosePine =>
      'Gedempt roze en iris in het donker';

  @override
  String get appThemeDescriptionAyuMirage =>
      'Zacht leisteengrijs met amberkleurige accenten';

  @override
  String get appThemeDescriptionCutiePro =>
      'Superschattig donker pastel, roze als blikvanger';

  @override
  String get appThemeDescriptionPinkAsHeck =>
      'Onbeschaamd felroze op bessenkleur';

  @override
  String get appThemeDescriptionVitesseLight =>
      'Modern gedempt saliegroen, teal en roze';

  @override
  String get appThemeDescriptionZenburn =>
      'Het klassieke warmgrijs met laag contrast';

  @override
  String get appThemeDescriptionShadesOfPurple => 'Rijk goud op diep indigo';

  @override
  String get appThemeDescriptionCatppuccinFrappe =>
      'Lichter blauwgrijs pastel-Catppuccin';

  @override
  String get appThemeDescriptionSynthwave84 => 'Gloeiend neon op retropaars';

  @override
  String get appThemeDescriptionNoctisLilac => 'Zacht lila daglicht van Noctis';

  @override
  String get themeEditorGroupPrimary => 'Primair';

  @override
  String get themeEditorGroupSecondary => 'Secundair';

  @override
  String get themeEditorGroupTertiary => 'Tertiair';

  @override
  String get themeEditorGroupError => 'Fout';

  @override
  String get themeEditorGroupSurfaceText => 'Oppervlak en tekst';

  @override
  String get themeEditorGroupSurfaceContainers => 'Oppervlaktecontainers';

  @override
  String get themeEditorGroupOutlineEffects => 'Omlijning en effecten';

  @override
  String get themeEditorRolePrimary => 'Primair';

  @override
  String get themeEditorRoleOnPrimary => 'Op primair';

  @override
  String get themeEditorRolePrimaryContainer => 'Primaire container';

  @override
  String get themeEditorRoleOnPrimaryContainer => 'Op primaire container';

  @override
  String get themeEditorRoleSecondary => 'Secundair';

  @override
  String get themeEditorRoleOnSecondary => 'Op secundair';

  @override
  String get themeEditorRoleSecondaryContainer => 'Secundaire container';

  @override
  String get themeEditorRoleOnSecondaryContainer => 'Op secundaire container';

  @override
  String get themeEditorRoleTertiary => 'Tertiair';

  @override
  String get themeEditorRoleOnTertiary => 'Op tertiair';

  @override
  String get themeEditorRoleTertiaryContainer => 'Tertiaire container';

  @override
  String get themeEditorRoleOnTertiaryContainer => 'Op tertiaire container';

  @override
  String get themeEditorRoleError => 'Fout';

  @override
  String get themeEditorRoleOnError => 'Op fout';

  @override
  String get themeEditorRoleErrorContainer => 'Foutcontainer';

  @override
  String get themeEditorRoleOnErrorContainer => 'Op foutcontainer';

  @override
  String get themeEditorRoleSurface => 'Oppervlak';

  @override
  String get themeEditorRoleOnSurface => 'Op oppervlak';

  @override
  String get themeEditorRoleOnSurfaceVariant => 'Op oppervlakvariant';

  @override
  String get themeEditorRoleInverseSurface => 'Omgekeerd oppervlak';

  @override
  String get themeEditorRoleOnInverseSurface => 'Op omgekeerd oppervlak';

  @override
  String get themeEditorRoleInversePrimary => 'Omgekeerd primair';

  @override
  String get themeEditorRoleSurfaceContainerLowest => 'Container (laagste)';

  @override
  String get themeEditorRoleSurfaceContainerLow => 'Container (laag)';

  @override
  String get themeEditorRoleSurfaceContainer => 'Container';

  @override
  String get themeEditorRoleSurfaceContainerHigh => 'Container (hoog)';

  @override
  String get themeEditorRoleSurfaceContainerHighest => 'Container (hoogste)';

  @override
  String get themeEditorRoleOutline => 'Omlijning';

  @override
  String get themeEditorRoleOutlineVariant => 'Omlijningsvariant';

  @override
  String get themeEditorRoleSurfaceTint => 'Oppervlaktetint';

  @override
  String get themeEditorRoleShadow => 'Schaduw';

  @override
  String get themeEditorRoleScrim => 'Scrim';

  @override
  String get themeEditorPairOnPrimary => 'Tekst op primair';

  @override
  String get themeEditorPairOnPrimaryContainer => 'Tekst op primaire container';

  @override
  String get themeEditorPairOnSecondary => 'Tekst op secundair';

  @override
  String get themeEditorPairOnSecondaryContainer =>
      'Tekst op secundaire container';

  @override
  String get themeEditorPairOnTertiary => 'Tekst op tertiair';

  @override
  String get themeEditorPairOnTertiaryContainer =>
      'Tekst op tertiaire container';

  @override
  String get themeEditorPairOnError => 'Tekst op fout';

  @override
  String get themeEditorPairOnErrorContainer => 'Tekst op foutcontainer';

  @override
  String get themeEditorPairOnSurface => 'Lopende tekst op oppervlak';

  @override
  String get themeEditorPairOnSurfaceVariant => 'Secundaire tekst op oppervlak';

  @override
  String get themeEditorPairOnInverseSurface => 'Tekst op omgekeerd oppervlak';

  @override
  String get themeEditorPairOutline => 'Omlijning op oppervlak';

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
      'Kleur elke dansrij op basis van diens formatiefamilie (contra, mixer, square, …) — tenzij je die formatie een eigen kleur hebt gegeven; die gaat voor. Dansen die als mixer zijn gemarkeerd krijgen altijd de mixerkleur, ongeacht de formatie. De formatie wordt ook altijd als tekst weergegeven, zodat rijen leesbaar blijven zonder kleur.';

  @override
  String get settingsAppearanceFormationColoursTitle => 'Formatielabelkleuren';

  @override
  String get settingsAppearanceFormationColoursSubtitle =>
      'Markeer individuele formaties in je eigen kleuren — bijv. Becket (CW) in geel, Becket (CCW) in roze — op danskaarten, dansdetails, de uitvoerheader en rijen in de dansvolgorde.';

  @override
  String get settingsAppearanceSelectedBadge => 'Geselecteerd';

  @override
  String get settingsAppearancePreviewHeading => 'Aa Voorbeeld';

  @override
  String get settingsAppearancePreviewBody => 'Voorbeeld van tekst';

  @override
  String get settingsAppearanceNewThemeDefaultName => 'Mijn thema';

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
  String get settingsDefaultsStartingProgramTitle => 'Startprogramma';

  @override
  String get settingsDefaultsStartingProgramPickerTitle => 'Een dans toevoegen';

  @override
  String get settingsDefaultsStartingProgramTextLabel => 'Tekst van notitie';

  @override
  String get settingsDefaultsStartingProgramNoteLabel =>
      'Notitie van caller (optioneel)';

  @override
  String get settingsDefaultsStartingProgramUnavailableDance =>
      'Deze dans is niet meer beschikbaar';

  @override
  String get settingsDefaultsDifficultyLevelEmpty =>
      'Een moeilijkheidsniveau heeft een naam nodig.';

  @override
  String settingsDefaultsDifficultyLevelDuplicate(String label) {
    return 'Er bestaat al een niveau met de naam \"$label\".';
  }

  @override
  String settingsDefaultsDifficultyLevelInUse(String label, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count dansen gebruiken $label. Wijzig ze eerst.',
      one: '1 dans gebruikt $label. Wijzig die eerst.',
    );
    return '$_temp0';
  }

  @override
  String get settingsDefaultsDifficultyLevelActionFailed =>
      'De moeilijkheidsniveaus konden niet worden opgeslagen. Probeer het opnieuw.';

  @override
  String settingsDefaultsDifficultyLevelDeleted(String label) {
    return '“$label” verwijderd.';
  }

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
  String get settingsDefaultsSortLastUsed => 'Laatst gebruikt';

  @override
  String get settingsDefaultsProgramSortTitle =>
      'Sorteervolgorde van programma\'s';

  @override
  String get settingsDefaultsProgramSortSubtitle =>
      'Hoe de programmalijst wordt gesorteerd wanneer je deze opent. Je kunt de sortering tijdens het bladeren nog steeds wijzigen.';

  @override
  String get settingsDefaultsSortLastUsedSubtitle =>
      'Wordt geopend met de sortering en richting die je het laatst hebt gebruikt.';

  @override
  String get settingsDefaultsSortAscending => 'Oplopend';

  @override
  String get settingsDefaultsSortDescending => 'Aflopend';

  @override
  String get settingsDefaultsCanonicalTitle =>
      'Dansdetails openen in canonieke termen';

  @override
  String get settingsDefaultsCanonicalSubtitle =>
      'Als Canonieke figuurtekst is ingeschakeld, opent een dans met canonieke rol- en bewegingsnamen in plaats van je actieve dialect. Als het is uitgeschakeld, worden details in je actieve dialect geopend en blijft deze voorkeur behouden.';

  @override
  String get settingsDefaultsCollectionCardHeader =>
      'Velden op de collectiekaart';

  @override
  String get settingsDefaultsCollectionCardSubtitle =>
      'Kies welke details op elke dansrij verschijnen. Alle velden worden standaard getoond.';

  @override
  String get settingsDefaultsCollectionCardAuthors => 'Auteurs';

  @override
  String get settingsDefaultsCollectionCardCalledCount => 'Aantal keer gecalld';

  @override
  String get settingsDefaultsCollectionCardFormation => 'Formatie';

  @override
  String get settingsDefaultsCollectionCardStatus => 'Status';

  @override
  String get settingsDefaultsCollectionCardLevel => 'Niveau';

  @override
  String get settingsDefaultsCollectionCardRating => 'Beoordeling';

  @override
  String get settingsDefaultsCollectionCardTags => 'Tags';

  @override
  String get settingsDefaultsCollectionCardCustomFields => 'Aangepaste velden';

  @override
  String get settingsDefaultsShareFieldsHeader => 'Gedeelde dansvelden';

  @override
  String get settingsDefaultsShareFieldsSubtitle =>
      'Kies welke details worden weergegeven wanneer je een programma of dans deelt, kopieert of exporteert. Deuntjes, de hook en bronnen zijn verborgen totdat je ze inschakelt; al het andere wordt standaard weergegeven.';

  @override
  String get settingsDefaultsShareFieldsAuthors => 'Auteurs';

  @override
  String get settingsDefaultsShareFieldsFormation => 'Formatie';

  @override
  String get settingsDefaultsShareFieldsLevel => 'Niveau';

  @override
  String get settingsDefaultsShareFieldsMixer => 'Mixer';

  @override
  String get settingsDefaultsShareFieldsStatus => 'Status';

  @override
  String get settingsDefaultsShareFieldsPhraseStructure => 'Frase';

  @override
  String get settingsDefaultsShareFieldsCallingNotes => 'Callnotities';

  @override
  String get settingsDefaultsShareFieldsWalkthrough => 'Doorloop';

  @override
  String get settingsDefaultsShareFieldsTunes => 'Deuntjes';

  @override
  String get settingsDefaultsShareFieldsHook => 'Hook';

  @override
  String get settingsDefaultsShareFieldsSources => 'Bronnen';

  @override
  String get settingsDefaultsShareFieldsMusic =>
      'Maatsoort, toonsoort en Barnes';

  @override
  String get settingsDefaultsCollectionFiltersHeader => 'Collectiefilters';

  @override
  String get settingsDefaultsCollectionFiltersSubtitle =>
      'Kies welke filters verschijnen wanneer je de collectie filtert en wanneer je dansen voor een programma kiest. Alle filters worden standaard getoond. Als je een filter verbergt, wordt de selectie ervan gewist.';

  @override
  String get settingsDefaultsImportHeader => 'Importstandaarden';

  @override
  String get settingsDefaultsImportTagsTitle =>
      'Tags voor geïmporteerde dansen';

  @override
  String get settingsDefaultsImportTagsSubtitle =>
      'Wordt toegevoegd aan elke nieuwe dans die een import maakt, ook dansen uit een bestand dat iemand met je heeft gedeeld. Dansen die bij het importeren van een programma voor de slots ervan worden gemaakt, krijgen geen tags.';

  @override
  String get settingsDefaultsImportTagsEmpty =>
      'Je hebt nog geen tags. Voeg er een toe aan een dans in de editor en kies die dan hier.';

  @override
  String get settingsDefaultsAuthoringHeader =>
      'Standaarden voor dansen aanmaken';

  @override
  String get settingsDefaultsFreeTextEntryTitle => 'Vrije tekstinvoer';

  @override
  String get settingsDefaultsFreeTextEntrySubtitle =>
      'Als ingeschakeld, kun je een nieuwe figuur als één regel invoeren (bijv. “neighbor balance & swing”) in plaats van veld voor veld, en een regel die je in de beweging van een bestaande figuur typt vervangt die figuur wanneer je op Enter drukt. De regel wordt omgezet in figuren; tekst die de app niet kan lezen wordt bewaard als niet-herkende figuur die je later kunt corrigeren. Nieuwe dansen beginnen zonder figuren, tenzij je startfiguren hebt opgeslagen.';

  @override
  String get settingsDefaultsAggressiveBeatsUpdateTitle =>
      'Figuurtellen agressief herberekenen';

  @override
  String get settingsDefaultsAggressiveBeatsUpdateSubtitle =>
      'Indien ingeschakeld, wordt het aantal tellen van een figuur direct herberekend zodra je de beweging of een parameter wijzigt die de timing beïnvloedt — zelfs als dat een handmatig ingevoerd aantal tellen overschrijft. Indien uitgeschakeld (standaard) wordt een aantal tellen dat je hebt aangepast alleen automatisch gewijzigd wanneer je een balansoptie aan- of uitzet; dan worden er 4 tellen toegevoegd of verwijderd.';

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
  String get settingsDefaultsFormTitle => 'Type';

  @override
  String get settingsDefaultsFormSubtitle =>
      'Het danstype waarmee een nieuwe dans begint. Je kunt dit per dans aanpassen.';

  @override
  String get settingsDefaultsFormLastUsed => 'Laatst gebruikt';

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
      'De figuren waarmee een nieuwe dans begint. Standaard acht keer stilstaan (elk 8 tellen), of geen zolang vrije tekstinvoer aan staat; maak leeg voor een lege nieuwe dans. Aanpasbaar per dans.';

  @override
  String get settingsDefaultsMoveDefaultsTitle => 'Standaardwaarden voor moves';

  @override
  String get settingsDefaultsUserFiguresTitle =>
      'Standaarden voor Eigen figuren';

  @override
  String get settingsDefaultsUserFiguresSubtitle =>
      'Elke figuur van jou heeft zijn eigen standaarden: de waarden waarmee hij begint en zijn tellen. Kies er een om ze te wijzigen.';

  @override
  String get settingsDefaultsMoveDefaultsSubtitle =>
      'Voorkeursparameterwaarden die worden toegepast wanneer je een move invoegt bij het invoeren van een dans. Deze overschrijven de ingebouwde standaarden van die move; je kunt achteraf elk parameter van de figuur nog aanpassen. Niet-ingestelde moves en parameters gebruiken de ingebouwde standaarden.';

  @override
  String get settingsDefaultsAddMoveButton => 'Movestandaard toevoegen';

  @override
  String get settingsDefaultsRemoveMoveTooltip => 'Verwijderen';

  @override
  String get settingsDefaultsMoveGone => 'Deze move is niet meer beschikbaar.';

  @override
  String get settingsDefaultsMoveNoParams =>
      'Deze move heeft geen parameters om in te stellen.';

  @override
  String get settingsFormationColoursTitle => 'Formatiekleuren';

  @override
  String get settingsFormationColoursIntro =>
      'Geef een formatie een eigen kleur om het label te markeren op danskaarten, dansdetails en de uitvoerheader, en om de rijen in de dansvolgorde te kleuren (mixers houden de mixerkleur). Alleen de formaties die je aanpast worden gemarkeerd; de overige tonen hun label zoals gewoonlijk. De formatie wordt ook altijd als tekst weergegeven, zodat labels leesbaar blijven zonder kleur.';

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
  String get settingsAppearanceTagColoursHeader => 'Tagkleuren';

  @override
  String get settingsAppearanceTagColoursTitle => 'Tagkleuren';

  @override
  String get settingsAppearanceTagColoursSubtitle =>
      'Geef een tag een eigen kleur zodat die opvalt op danskaarten en in de dansdetails. De naam van de tag wordt altijd ook getoond, dus tags blijven leesbaar zonder kleur.';

  @override
  String get settingsTagColoursEmptyTitle => 'Nog geen tags';

  @override
  String get settingsTagColoursEmptyBody =>
      'Voeg een tag toe aan een dans en die verschijnt hier.';

  @override
  String get settingsTagColoursSaveError =>
      'Die kleur kon niet worden opgeslagen. Probeer het opnieuw.';

  @override
  String get settingsTagColoursLoadError =>
      'Je tags konden niet worden geladen. Er is niets gewijzigd. Probeer het opnieuw.';

  @override
  String get tagManagerTitle => 'Tags';

  @override
  String get tagManagerSearchHint => 'Tags zoeken';

  @override
  String get tagManagerNameLabel => 'Tagnaam';

  @override
  String get tagManagerShowDances => 'Dansen tonen';

  @override
  String get tagManagerColour => 'Kleur…';

  @override
  String get tagManagerRemoveColour => 'Kleur verwijderen';

  @override
  String tagManagerDeletedSnack(String name, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '“$name” verwijderd uit $count dansen',
      one: '“$name” verwijderd uit 1 dans',
      zero: '“$name” verwijderd',
    );
    return '$_temp0';
  }

  @override
  String tagManagerRenamedSnack(String from, String to) {
    return '“$from” hernoemd naar “$to”';
  }

  @override
  String tagManagerMergedSnack(String from, String into) {
    return '“$from” samengevoegd met “$into”';
  }

  @override
  String tagManagerMergedSeveralSnack(int count, String into) {
    return '$count tags samengevoegd tot “$into”';
  }

  @override
  String get authorManagerTitle => 'Auteurs';

  @override
  String get authorManagerSearchHint => 'Auteurs zoeken';

  @override
  String get authorManagerNameLabel => 'Naam van de auteur';

  @override
  String get authorManagerEmptyTitle => 'Nog geen auteurs';

  @override
  String get authorManagerEmptyBody =>
      'Auteurs die je bij een dans vermeldt, verschijnen hier.';

  @override
  String get authorManagerLoadError =>
      'Je auteurs konden niet worden geladen. Er is niets gewijzigd. Probeer het opnieuw.';

  @override
  String authorManagerMergedSeveralSnack(int count, String into) {
    return '$count auteurs samengevoegd tot “$into”';
  }

  @override
  String get sourceManagerTitle => 'Bronnen';

  @override
  String get sourceManagerSearchHint => 'Bronnen zoeken';

  @override
  String get sourceManagerTitleLabel => 'Titel van de bron';

  @override
  String get sourceManagerEmptyTitle => 'Nog geen bronnen';

  @override
  String get sourceManagerEmptyBody =>
      'Boeken en websites die je bij een dans citeert, verschijnen hier.';

  @override
  String get sourceManagerLoadError =>
      'Je bronnen konden niet worden geladen. Er is niets gewijzigd. Probeer het opnieuw.';

  @override
  String get libraryManagerClearSearch => 'Zoekopdracht wissen';

  @override
  String get libraryManagerNotUsed => 'Niet gebruikt';

  @override
  String get libraryManagerSortTooltip => 'Sorteren';

  @override
  String get libraryManagerSortByName => 'Naam';

  @override
  String get libraryManagerSortByDanceCount => 'Aantal dansen';

  @override
  String get libraryManagerNoMatches =>
      'Niets komt overeen met je zoekopdracht.';

  @override
  String libraryManagerDanceCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count dansen',
      one: '1 dans',
      zero: 'Niet gebruikt',
    );
    return '$_temp0';
  }

  @override
  String libraryManagerActionsTooltip(String name) {
    return 'Acties voor $name';
  }

  @override
  String get libraryManagerRename => 'Hernoemen';

  @override
  String libraryManagerRenameTitle(String name) {
    return '“$name” hernoemen';
  }

  @override
  String get libraryManagerMergeInto => 'Samenvoegen met…';

  @override
  String libraryManagerMergePickerTitle(String name) {
    return '“$name” samenvoegen met…';
  }

  @override
  String get libraryManagerMergeOfferTitle => 'Naam al in gebruik';

  @override
  String libraryManagerMergeOfferOne(String existing, String from) {
    return '“$existing” bestaat al. “$from” ermee samenvoegen?';
  }

  @override
  String libraryManagerMergeOfferOneRenamed(
    String existing,
    String from,
    String name,
  ) {
    return '“$existing” bestaat al. “$from” ermee samenvoegen en “$name” noemen?';
  }

  @override
  String libraryManagerMergeOfferSeveral(String name, String from) {
    return 'Meer dan één item heet al “$name”. Kies het item waarmee “$from” wordt samengevoegd; de andere worden er ook mee samengevoegd.';
  }

  @override
  String get libraryManagerMerge => 'Samenvoegen';

  @override
  String libraryManagerUndoConflict(String name) {
    return 'Ongedaan maken lukt niet: “$name” wordt nu door een ander item gebruikt.';
  }

  @override
  String get libraryManagerEditFailed =>
      'Die wijziging kon niet worden opgeslagen. Probeer het opnieuw.';

  @override
  String get libraryManagerEditDetails => 'Details bewerken…';

  @override
  String libraryManagerRenamedSnack(String from, String to) {
    return '“$from” hernoemd naar “$to”';
  }

  @override
  String libraryManagerMergedSnack(String from, String into) {
    return '“$from” samengevoegd met “$into”';
  }

  @override
  String libraryManagerDeletedSnack(String name) {
    return '“$name” verwijderd';
  }

  @override
  String libraryManagerMergeConfirmTitle(String from, String into) {
    return '“$from” samenvoegen met “$into”?';
  }

  @override
  String get libraryManagerMergeDropsHeading =>
      'Deze details verschillen. Het samengevoegde item houdt zijn eigen details, en deze vervallen:';

  @override
  String libraryManagerMergeDroppedLine(String field, String value) {
    return '$field: $value';
  }

  @override
  String get settingsGeneralLibraryHeader => 'Dansen';

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
  String get settingsGeneralProgramsHeader => 'Programma\'s';

  @override
  String get settingsSharingHeader => 'Delen';

  @override
  String get settingsSharingTitleTitle =>
      'Programmatitel opnemen bij het delen van een setlijst';

  @override
  String get settingsSharingCallerBandTitle =>
      'Caller en band opnemen bij het delen van een setlijst';

  @override
  String get settingsSharingDateVenueTitle =>
      'Datum, tijden en locatie opnemen bij het delen van een setlijst';

  @override
  String get settingsSharingSubtitle =>
      'Geldt voor het delen of kopiëren van de setlijst. Het hele programma delen als .ccshare- of JSON-bestand bevat altijd alles.';

  @override
  String get settingsGeneralMatrixExactCollisionTitle =>
      'Alleen exacte overlap van tellen markeren';

  @override
  String get settingsGeneralMatrixExactCollisionSubtitle =>
      'In de programmeringsmatrix wordt een herhaalde figuur tussen twee opeenvolgende dansen alleen gemarkeerd als de tellen daadwerkelijk overlappen — niet alleen wanneer deze in dezelfde benoemde frase (A1, A2, B1, B2…) valt. Zet uit om elke herhaling in dezelfde frase te markeren, ook als de tellen zelf niet overlappen.';

  @override
  String get settingsProgramAutoCommitTitle =>
      'Programmawijzigingen automatisch opslaan';

  @override
  String get settingsProgramAutoCommitSubtitle =>
      'Als dit is ingeschakeld, worden geldige wijzigingen tijdens het werken opgeslagen en wordt bij het verlaten van de editor niet gevraagd of je ze wilt verwerpen. Schakel dit uit om programma’s expliciet op te slaan.';

  @override
  String get settingsProgramShowPayTitle => 'Gage tonen';

  @override
  String get settingsProgramShowPaySubtitle =>
      'Als dit uit staat, verbergen de editor, het overzicht en de programmaspreadsheet de gage. Al ingevoerde gages blijven bewaard en verschijnen weer als je dit opnieuw aanzet.';

  @override
  String get settingsMatrixColumnsHeader => 'Matrixkolommen';

  @override
  String get settingsMatrixColumnsSubtitle =>
      'Herschik, hernoem of verwijder de kolommen in de programmamatrix. Wijzigingen gelden voor elk programma.';

  @override
  String settingsMatrixColumnsDragToReorder(String label) {
    return 'Sleep om kolom $label te herschikken';
  }

  @override
  String get settingsMatrixColumnsRenamedBadge => 'Hernoemd';

  @override
  String get settingsMatrixColumnsRenameTooltip => 'Kolom hernoemen';

  @override
  String get settingsMatrixColumnsRemoveTooltip => 'Kolom verwijderen';

  @override
  String get settingsMatrixColumnsRestoreTooltip => 'Kolom herstellen';

  @override
  String get settingsMatrixColumnsRenameTitle => 'Kolom hernoemen';

  @override
  String get settingsMatrixColumnsRenameLabel => 'Kolomlabel';

  @override
  String get settingsMatrixColumnsResetRemoved =>
      'Verwijderde kolommen herstellen';

  @override
  String get settingsMatrixColumnsResetTrue =>
      'Alle standaardinstellingen herstellen';

  @override
  String get settingsMatrixColumnsResetTrueTitle =>
      'Alle standaardinstellingen herstellen?';

  @override
  String get settingsMatrixColumnsResetTrueBody =>
      'Hiermee worden alle herschikkingen, hernoemingen en verwijderingen van kolommen gewist — inclusief eventuele aangepaste kolommen — en keert de matrix terug naar de standaardkolommen. Dit kan niet ongedaan worden gemaakt.';

  @override
  String get settingsMatrixColumnsResetTrueConfirm => 'Standaard herstellen';

  @override
  String get settingsMatrixColumnsParameterizedAdd =>
      'Geparametriseerde kolom toevoegen';

  @override
  String get settingsMatrixColumnsParameterizedTitle =>
      'Geparametriseerde kolom toevoegen';

  @override
  String get settingsMatrixColumnsParameterizedEditTitle =>
      'Geparametriseerde kolom bewerken';

  @override
  String get settingsMatrixColumnsParameterizedMove => 'Figuur';

  @override
  String get settingsMatrixColumnsParameterizedConstraints =>
      'Exacte parameters om te matchen';

  @override
  String get settingsMatrixColumnsParameterizedNoParams =>
      'Deze figuur heeft geen parameters.';

  @override
  String get settingsMatrixColumnsParameterizedLabel => 'Kolomnaam';

  @override
  String get settingsMatrixColumnsParameterizedEdit =>
      'Matchingsdetails bewerken';

  @override
  String get settingsMatrixColumnsParameterizedDelete =>
      'Geparametriseerde kolom verwijderen';

  @override
  String get settingsMatrixColumnsCompoundAdd =>
      'Samengestelde kolom toevoegen';

  @override
  String get settingsMatrixColumnsCompoundTitle =>
      'Samengestelde kolom toevoegen';

  @override
  String get settingsMatrixColumnsCompoundEditTitle =>
      'Samengestelde kolom bewerken';

  @override
  String get settingsMatrixColumnsCompoundSteps => 'Stappen';

  @override
  String get settingsMatrixColumnsCompoundMove => 'Figuur';

  @override
  String get settingsMatrixColumnsCompoundParameters => 'Exacte parameters';

  @override
  String get settingsMatrixColumnsCompoundAddStep => 'Stap toevoegen';

  @override
  String get settingsMatrixColumnsCompoundRemoveStep => 'Stap verwijderen';

  @override
  String get settingsMatrixColumnsCompoundMoveUp =>
      'Stap naar voren verplaatsen';

  @override
  String get settingsMatrixColumnsCompoundMoveDown =>
      'Stap naar achteren verplaatsen';

  @override
  String get settingsMatrixColumnsCompoundLabel => 'Kolomnaam';

  @override
  String get settingsMatrixColumnsCompoundEdit => 'Reeks bewerken';

  @override
  String get settingsMatrixColumnsCompoundDelete =>
      'Samengestelde kolom verwijderen';

  @override
  String get settingsGeneralPerformanceHeader => 'Uitvoeren';

  @override
  String get settingsGeneralAutoSizePerformTitle =>
      'Uitvoerkaarten automatisch schalen';

  @override
  String get settingsGeneralAutoSizePerformSubtitle =>
      'Schaal elke kaart zodat die op het scherm past, maar nooit kleiner dan je gebruikelijke tekstgrootte: een langere dans of een langer slot scrolt dan. Uitschakelen om de grootte zelf in te stellen met A− / A+.';

  @override
  String get settingsShowIndividualPerformTimerTitle =>
      'Timer tonen bij het uitvoeren van één dans';

  @override
  String get settingsShowIndividualPerformTimerSubtitle =>
      'Verstreken tijd tonen tijdens het uitvoeren van een enkele dans. De timer start zodra deze wordt weergegeven en kan worden gepauzeerd.';

  @override
  String get settingsConfirmPerformExitTitle =>
      'Bevestigen voor Uitvoeren verlaten';

  @override
  String get settingsConfirmPerformExitSubtitle =>
      'Vragen voordat de sluitknop of Terug je uit Uitvoeren haalt. Zet dit uit om met één tik te vertrekken; Uitvoeren voor een programma onthoudt je plek in beide gevallen.';

  @override
  String get settingsShowProgramSlotCallerNotesTitle =>
      'Callernotities tonen bij het uitvoeren van een programma';

  @override
  String get settingsShowProgramSlotCallerNotesSubtitle =>
      'Toon niet-lege callernotities per slot boven de danstitel wanneer je een programma uitvoert.';

  @override
  String get settingsGeneralCallingHistoryHeader => 'Callerhistorie';

  @override
  String get settingsGeneralRequirePerformedForHistoryTitle =>
      '“Markeer als uitgevoerd” vereisen voor callerhistorie';

  @override
  String get settingsGeneralRequirePerformedForHistorySubtitle =>
      'Bepaalt wat als gecalld telt. Als ingeschakeld, tellen alleen slots die als uitgevoerd zijn gemarkeerd overal waar callerhistorie wordt gelezen: de historielijst, gecalld ×N, het filter Gecalld en de sortering op laatst gecalld. Als uitgeschakeld, telt een slot zodra het programma de dans bevat. Gaat vóór de vier instellingen hieronder.';

  @override
  String get settingsGeneralShowPerformedTogglesTitle =>
      'Schakelaars voor ‘markeren als uitgevoerd’ tonen';

  @override
  String get settingsGeneralShowPerformedTogglesSubtitle =>
      'Als ingeschakeld, heeft elke dans in de programmaweergave een schakelaar om die als uitgevoerd te markeren of niet, zonder de editor te openen. Als uitgeschakeld, tonen de rijen alleen of een dans is uitgevoerd.';

  @override
  String get settingsGeneralMarkAllSetsStatusTitle =>
      'Alles markeren als uitgevoerd zet de status';

  @override
  String get settingsGeneralMarkAllSetsStatusSubtitle =>
      'Als ingeschakeld, zet Alles markeren als uitgevoerd ook de programmastatus op Uitgevoerd, en Ongedaan maken zet beide terug. Als uitgeschakeld, blijft de status zoals hij was.';

  @override
  String get settingsGeneralRequireEventDateForHistoryTitle =>
      'Eventdatum vereisen voor callerhistorie';

  @override
  String get settingsGeneralRequireEventDateForHistorySubtitle =>
      'Bepaalt wat als gecalld telt. Als ingeschakeld, telt een programma zonder eventdatum nergens mee in de callerhistorie tot je het een datum geeft. Gedupliceerde en ontvangen programma’s komen zonder datum binnen. Als uitgeschakeld, telt een programma mee, of het nu een datum heeft of niet. Gaat vóór de vier instellingen hieronder.';

  @override
  String get settingsTrackingHeader => 'Recentheid en historievolgorde';

  @override
  String get settingsRecencyRequireEventDateTitle =>
      'Recentheid telt alleen programma’s met datum';

  @override
  String get settingsRecencyRequireEventDateSubtitle =>
      'Wijzigt alleen de tijdvensters van het filter Gecalld, nooit de tellingen. Als ingeschakeld, valt een programma zonder eventdatum in geen enkel venster, al telt de dans nog steeds als gecalld. Als uitgeschakeld, wordt een programma zonder datum gedateerd op het moment waarop het slot als uitgevoerd is gemarkeerd, anders op het moment van de laatste bewerking.';

  @override
  String get settingsRecencyRequirePerformedTitle =>
      'Recentheid telt alleen slots die als uitgevoerd zijn gemarkeerd';

  @override
  String get settingsRecencyRequirePerformedSubtitle =>
      'Wijzigt alleen de tijdvensters van het filter Gecalld, nooit de tellingen. Als ingeschakeld, valt een slot dat niet als uitgevoerd is gemarkeerd in geen enkel venster, maar het telt nog steeds als gecalld. Tot je het zelf instelt, volgt dit de instelling “uitgevoerd vereisen” hierboven.';

  @override
  String get settingsHistoryOrderIgnoreUndatedTitle =>
      'Historievolgorde en Laatst gecalld negeren programma’s zonder datum';

  @override
  String get settingsHistoryOrderIgnoreUndatedSubtitle =>
      'Wijzigt alleen de volgorde van de historie van een dans en de sortering op laatst gecalld, nooit de tellingen. Als ingeschakeld, staat een programma zonder eventdatum na die met datum en geeft het geen datum voor Laatst gecalld. Als uitgeschakeld, wordt het gesorteerd op het moment waarop het slot als uitgevoerd is gemarkeerd, anders op de laatste bewerking.';

  @override
  String get settingsHistoryOrderIgnoreUnperformedTitle =>
      'Historievolgorde en Laatst gecalld negeren slots die niet als uitgevoerd zijn gemarkeerd';

  @override
  String get settingsHistoryOrderIgnoreUnperformedSubtitle =>
      'Wijzigt alleen de volgorde van de historie van een dans en de sortering op laatst gecalld, nooit de tellingen. Als ingeschakeld, staat een slot dat niet als uitgevoerd is gemarkeerd na de andere en geeft het geen datum voor Laatst gecalld. Als uitgeschakeld, wordt het gesorteerd op de datum van het programma.';

  @override
  String get settingsGeneralTrackHistoryForAllCallersTitle =>
      'Callerhistorie voor alle callers bijhouden';

  @override
  String get settingsGeneralTrackHistoryForAllCallersSubtitle =>
      'Als dit uit staat en er een standaardcaller is ingesteld, bevatten de callerhistorie en de aantallen programma’s die door die caller zijn geleid, plus programma’s zonder geregistreerde caller (behandeld als jouw eigen). Als dit aan staat — of als er geen standaardcaller is ingesteld — wordt elk programma dat de dans bevat bijgehouden.';

  @override
  String get settingsProgramVenueCallCountTitle =>
      'Herhaalde locaties in de belgeschiedenis';

  @override
  String get settingsProgramVenueCallCountSubtitle =>
      'Toon de belangrijkste locaties waar een dans meer dan één keer is gecalld. Kies “Niet tonen” om dit overzicht te verbergen.';

  @override
  String settingsProgramVenueCallCountOption(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count locaties',
      one: '1 locatie',
      zero: 'Niet tonen',
    );
    return '$_temp0';
  }

  @override
  String get settingsGeneralCapitalizeFiguresTitle =>
      'Figuren met hoofdletter beginnen';

  @override
  String get settingsGeneralCapitalizeFiguresSubtitle =>
      'Als ingeschakeld, begint elke figuur in de dansweergave, de Perform-modus en de figuureditor met een hoofdletter (“Neighbors allemande left”). Als uitgeschakeld, worden figuren getoond zoals ze zijn geschreven; ingebouwde figuren beginnen met een kleine letter, zoals in ContraDB. Alleen het uiterlijk van figuren op die plekken verandert; exports, zoeken, synchronisatievergelijkingen en de tekst voor schermlezers blijven ongewijzigd.';

  @override
  String get settingsGeneralLibraryTagsTitle => 'Tags';

  @override
  String get settingsGeneralLibraryTagsSubtitle =>
      'Je tags hernoemen, samenvoegen, kleuren en verwijderen.';

  @override
  String get settingsGeneralLibraryAuthorsTitle => 'Auteurs';

  @override
  String get settingsGeneralLibraryAuthorsSubtitle =>
      'Auteurs hernoemen, samenvoegen en verwijderen, en hun details bewerken.';

  @override
  String get settingsGeneralLibrarySourcesTitle => 'Bronnen';

  @override
  String get settingsGeneralLibrarySourcesSubtitle =>
      'Bronnen hernoemen, samenvoegen en verwijderen, en hun details bewerken.';

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
      'Vraag het voordat je iets verwijdert dat ongedaan kan worden gemaakt. Verwijderingen die niet ongedaan kunnen worden gemaakt, vragen het altijd eerst.';

  @override
  String get settingsGeneralUndoPromptTitle => 'Melding Ongedaan maken';

  @override
  String get settingsGeneralUndoPromptSubtitle =>
      'Hoe lang Ongedaan maken in beeld blijft nadat je iets verwijdert of wijzigt. De melding blijft ook staan zolang je ernaar wijst of er met het toetsenbord naartoe gaat.';

  @override
  String settingsGeneralUndoPromptSeconds(int seconds) {
    String _temp0 = intl.Intl.pluralLogic(
      seconds,
      locale: localeName,
      other: '$seconds seconden',
      one: '1 seconde',
    );
    return '$_temp0';
  }

  @override
  String get settingsGeneralUndoPromptUntilClosed => 'Tot ik de melding sluit';

  @override
  String get settingsGeneralDeletedItemsHeader => 'Onlangs verwijderd';

  @override
  String get settingsGeneralSoftDeleteRetentionTitle =>
      'Onlangs verwijderde items bewaren voor';

  @override
  String get settingsGeneralSoftDeleteRetentionSubtitle =>
      'Verwijderde dansen en programma’s worden zo lang bewaard voordat ze bij het opstarten van de app permanent worden verwijderd. Met apparaatsynchronisatie geldt dit op al je apparaten: een gedeeld item wordt overal leeggemaakt en alleen een kleine verwijderingsnotitie blijft over. Nooit bewaart ze totdat je ze handmatig opschoont.';

  @override
  String settingsGeneralSoftDeleteRetentionDays(int days) {
    return '$days dagen';
  }

  @override
  String get settingsGeneralSoftDeleteRetentionNever => 'Nooit';

  @override
  String get syncReviewSettingsTitle => 'Synchronisatiebeslissingen';

  @override
  String get syncReviewSettingsSubtitle =>
      'Bepaal hoe conflicten tussen je apparaten worden opgelost wanneer synchronisatie ze niet zelf kan beslechten.';

  @override
  String get syncReviewTitle => 'Synchronisatiebeslissingen';

  @override
  String get syncReviewLoading => 'Synchronisatiebeslissingen laden';

  @override
  String get syncReviewEmpty =>
      'Er zijn geen synchronisatiebeslissingen die op je wachten.';

  @override
  String get syncReviewIntro =>
      'Voor deze items is een beslissing nodig voordat een wijziging van een ander apparaat kan worden toegepast.';

  @override
  String get syncReviewLoadFailed =>
      'De synchronisatiekeuzes konden niet worden geladen. Probeer het opnieuw.';

  @override
  String get syncReviewResolved => 'Synchronisatiebeslissing toegepast.';

  @override
  String get syncReviewActionFailed =>
      'Die synchronisatiekeuze kon niet worden toegepast. Het item is bewaard, dus je kunt het opnieuw proberen.';

  @override
  String get syncReviewKindChoreographer => 'Auteur';

  @override
  String get syncReviewKindTag => 'Tag';

  @override
  String get syncReviewKindCustomField => 'Aangepast veld';

  @override
  String get syncReviewKindDifficulty => 'Moeilijkheidsgraad';

  @override
  String get syncReviewKindDance => 'Dans';

  @override
  String get syncReviewKindProgram => 'Programma';

  @override
  String get syncReviewKindPublishedSource => 'Gepubliceerde bron';

  @override
  String get syncReviewKindVenue => 'Locatie';

  @override
  String get syncReviewKindSetting => 'Instelling';

  @override
  String get syncReviewKindGlossaryEntry => 'Je figuur';

  @override
  String get syncReviewKindFigureNote => 'Je notities bij een figuur';

  @override
  String syncConflictFigureNoteTitle(String figure) {
    return 'Je notities bij $figure';
  }

  @override
  String syncReviewLocalRecord(String id) {
    return 'Op dit apparaat: $id';
  }

  @override
  String syncReviewPeerRecord(String identity) {
    return 'Van het andere apparaat: $identity';
  }

  @override
  String get syncReviewTombstoneReason =>
      'Een ander apparaat heeft een overeenkomend item verwijderd dat op dit apparaat is gemaakt.';

  @override
  String get syncReviewDanceAmbiguityReason =>
      'Live dansen hebben dezelfde titel, maar een andere choreografie.';

  @override
  String get syncReviewRenameCollisionReason =>
      'Een ander apparaat heeft dit record hernoemd naar een naam die een ander record hier al gebruikt.';

  @override
  String get syncReviewMergeDiscardsContactsTitle =>
      'Deze auteurs samenvoegen?';

  @override
  String get syncReviewMergeDiscardsContactsBody =>
      'Er blijft maar één record bewaard. Het e-mailadres, de locatie en de overleden-markering van het andere record staan alleen op dit apparaat en gaan verloren. Dit kan niet ongedaan worden gemaakt.';

  @override
  String get syncReviewCounterpartDeleted =>
      'Het andere record is verwijderd, dus deze twee kunnen niet worden samengevoegd. Gebruik \'Beide behouden\' om het een andere naam te geven.';

  @override
  String get syncReviewUnsupportedReason =>
      'Dit synchronisatieconflict wordt voorlopig bewaard; hier is geen veilige actie beschikbaar.';

  @override
  String get syncReviewUnsupportedAction =>
      'Bewaar dit item voorlopig; een latere synchronisatie of app-update kan het mogelijk verwerken.';

  @override
  String get syncReviewMergeAction => 'Samenvoegen';

  @override
  String get syncReviewKeepBothAction => 'Beide behouden';

  @override
  String get syncReviewKeepBothTitle => 'Kies een nieuwe lokale naam';

  @override
  String get syncReviewNewNameLabel => 'Nieuwe lokale naam';

  @override
  String get syncReviewNameRequired => 'Voer een naam in.';

  @override
  String get syncReviewNameNotDistinct => 'Kies een andere naam.';

  @override
  String get syncReviewCandidateInvalid =>
      'De opgeslagen wijziging van een ander apparaat is ongeldig en is daarom bewaard.';

  @override
  String get syncReviewCandidateChanged =>
      'De opgeslagen wijziging van een ander apparaat is niet meer actueel en is daarom bewaard.';

  @override
  String get syncReviewTargetMissing =>
      'Het lokale record is niet meer beschikbaar; de beslissing is bewaard.';

  @override
  String get syncReviewCandidateAlreadyPresent =>
      'Het item van het andere apparaat is al aanwezig; de beslissing is bewaard.';

  @override
  String get settingsGeneralImportHeader => 'Importeren';

  @override
  String get settingsGeneralImportDancesSubtitle =>
      'Breng dansen in je collectie vanuit een Caller\'s Compendium JSON-bestand. Je bekijkt elke dans en bevestigt voordat er iets wordt toegevoegd.';

  @override
  String get settingsGeneralImportEllipsisAction => 'Importeren…';

  @override
  String get settingsGeneralReparseCustomFiguresTitle =>
      'Niet-herkende figuren opnieuw controleren';

  @override
  String get settingsGeneralReparseCustomFiguresSubtitle =>
      'Controleer geïmporteerde dansen opnieuw waarvan de figuren alleen als onherkende figuren zijn bewaard omdat ze bij het importeren niet herkend werden. Kan de app ze nu wel herkennen, dan worden ze ter plekke bijgewerkt; je tags, beoordelingen en notities blijven behouden. Je ziet eerst een voorbeeld en bevestigt voordat er iets verandert.';

  @override
  String get settingsGeneralReparseCustomFiguresAction =>
      'Opnieuw controleren…';

  @override
  String get settingsGeneralEcdMigrationTitle => 'Engelse dansen omzetten';

  @override
  String get settingsGeneralEcdMigrationSubtitle =>
      'Engelse country dances die zijn opgeslagen voordat de app Engelse figuren kende, gebruiken nog contra-moves. Zet de moves om die in Engelse dans hetzelfde betekenen, lees niet-herkende figuren opnieuw en geef elke dans zijn Engelse formatie. Je kiest de dansen en bevestigt voordat er iets verandert.';

  @override
  String get settingsGeneralEcdMigrationAction => 'Omzetten…';

  @override
  String get settingsGeneralBackupRestoreHeader => 'Back-up en herstel';

  @override
  String get backupExported => 'Back-up geëxporteerd.';

  @override
  String get backupExportFailed =>
      'Er kon geen back-up worden geëxporteerd. Je gegevens zijn ongewijzigd. Probeer het opnieuw.';

  @override
  String get backupRestoreIntegrityFailed =>
      'Deze back-up is niet door de veiligheidscontrole gekomen, dus hij is mogelijk beschadigd of na het exporteren gewijzigd. Het herstellen is geannuleerd en je gegevens zijn ongewijzigd.';

  @override
  String get backupRestoreIncompatibleVersion =>
      'Deze back-up bevat items die deze versie van de app niet kan lezen (mogelijk van een nieuwere versie), dus het herstel is geannuleerd. Je gegevens zijn ongewijzigd.';

  @override
  String get backupRestoreMissingAppSection =>
      'Deze back-up bevat je app-instellingen, thema’s en dialecten niet, dus hij kan je huidige gegevens niet vervangen. Het herstel is geannuleerd en je gegevens zijn ongewijzigd.';

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
  String backupRestoreRemovedEventRules(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count avondregels zijn verwijderd, omdat de back-up hun opgeslagen zoekopdrachten niet bevat.',
      one:
          '1 avondregel is verwijderd, omdat de back-up de opgeslagen zoekopdracht ervan niet bevat.',
    );
    return '$_temp0';
  }

  @override
  String get backupRestoreFailed =>
      'De back-up kon niet worden hersteld. Probeer het opnieuw.';

  @override
  String get backupRestoreSettingsFailed =>
      'Je dansen en programma’s zijn hersteld, maar het toepassen van je opgeslagen instellingen is mislukt. Je herstelde inhoud is veilig; je kunt opnieuw proberen ze toe te passen.';

  @override
  String get backupRestoreSettingsRetryAction => 'Opnieuw proberen';

  @override
  String get backupRestoreSettingsRetried => 'Instellingen toegepast.';

  @override
  String get backupExportTitle => 'Een back-up exporteren';

  @override
  String get backupExportSubtitle =>
      'Sla je hele bibliotheek op in één JSON-bestand dat je veilig kunt bewaren of naar een ander apparaat kunt verplaatsen. Het bevat je dansen, programma’s, aangepaste velden, dialecten, thema’s en instellingen.';

  @override
  String get backupExportAction => 'Exporteren';

  @override
  String get backupRestoreTitle => 'Herstellen vanuit een back-up';

  @override
  String get backupRestoreSubtitle =>
      'Vervang alles wat nu in de app staat door de inhoud van een back-upbestand. Dit kan niet ongedaan worden gemaakt.';

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
  String get backupReminderBannerText =>
      'Je back-up is verlopen. Exporteer er nu een om je bibliotheek veilig te houden.';

  @override
  String get backupReminderBannerExport => 'Back-up exporteren';

  @override
  String get backupReminderBannerNotNow => 'Niet nu';

  @override
  String get backupRestoreDialogBody =>
      'Bij het herstellen wordt alles wat nu in de app staat, zoals je dansen, programma’s, dialecten, thema’s en instellingen, vervangen door de inhoud van de back-up. Dit kan niet ongedaan worden gemaakt.';

  @override
  String get backupRestoreDialogSyncNote =>
      'Dit apparaat is verbonden met apparaatsynchronisatie. Alles wat apparaatsynchronisatie meeneemt en na het maken van deze back-up is gewijzigd op een apparaat waarmee je synchroniseert, komt bij de volgende synchronisatie terug van dat apparaat, ook wijzigingen die hier zijn gemaakt en al zijn gesynchroniseerd. Al het andere krijgt de versie uit de back-up.';

  @override
  String get backupChooseFileAction => 'Bestand kiezen…';

  @override
  String get backupChooseFileFailed =>
      'Dat bestand kon niet worden gelezen. Kies het opnieuw of kies een ander bestand.';

  @override
  String get backupPasteJsonLabel => 'Of plak back-up JSON';

  @override
  String get backupReplaceAllDataAction => 'Alle gegevens vervangen';

  @override
  String backupFileSummary(String date, int dances, int programs, String size) {
    String _temp0 = intl.Intl.pluralLogic(
      dances,
      locale: localeName,
      other: '$dances dansen',
      one: '$dances dans',
    );
    String _temp1 = intl.Intl.pluralLogic(
      programs,
      locale: localeName,
      other: '$programs programma\'s',
      one: '$programs programma',
    );
    return 'Back-up van $date: $_temp0, $_temp1, $size MB';
  }

  @override
  String backupFileUnreadable(String size) {
    return 'Dit bestand lijkt geen leesbare back-up te zijn ($size MB). Bij het vervangen zie je waarom herstellen niet lukt.';
  }

  @override
  String get backupFileClearAction => 'Wissen';

  @override
  String backupFileTooLarge(String sizeMb, String limitMb) {
    return 'Dat bestand is te groot voor een Caller’s Compendium-back-up ($sizeMb MB; limiet $limitMb MB). Je gegevens zijn ongewijzigd.';
  }

  @override
  String backupExportTooLarge(String sizeMb, String limitMb) {
    return 'Je bibliotheek is te groot om als één back-up te exporteren ($sizeMb MB; limiet $limitMb MB), dus er is niets opgeslagen. Je gegevens zijn ongewijzigd.';
  }

  @override
  String backupExportDiskFull(String neededMb, String freeMb) {
    return 'Er is niet genoeg vrije ruimte om deze back-up te vervangen ($neededMb MB nodig; $freeMb MB vrij), dus er is niets opgeslagen. Je eerdere back-up is ongewijzigd.';
  }

  @override
  String get backupExportInProgress => 'Je back-up wordt voorbereid…';

  @override
  String get backupRestorePreparing => 'De back-up wordt gelezen…';

  @override
  String backupRestoreProgress(int done, int total) {
    return '$done van $total herstellen…';
  }

  @override
  String get diagnosticsNoDiagnosticsToExport =>
      'Geen diagnostics te exporteren.';

  @override
  String get diagnosticsScrubbedExportUnavailable =>
      'Er kon geen veilige (opgeschoonde) export worden gemaakt, dus er is niets opgeslagen. Probeer het opnieuw, of kies bewust de volledige details.';

  @override
  String get diagnosticsLogExported => 'Diagnosticslog geëxporteerd.';

  @override
  String get diagnosticsExportCancelled => 'Export geannuleerd.';

  @override
  String get diagnosticsExportFailed =>
      'Het diagnoselog kon niet worden geëxporteerd. Probeer het opnieuw.';

  @override
  String get diagnosticsClearFailed =>
      'Het diagnoselog kon niet worden gewist. Probeer het opnieuw.';

  @override
  String get diagnosticsClearLogTitle => 'Diagnosticslog wissen?';

  @override
  String get diagnosticsClearLogBody =>
      'Hiermee wordt het lokale crashlog definitief van dit apparaat verwijderd. Dit kan niet ongedaan worden gemaakt.';

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
  String get crashFallbackTitle =>
      'Dit onderdeel van de app kon niet worden getoond';

  @override
  String get crashFallbackBody =>
      'Dit onderdeel van de app heeft een onverwachte fout gehad. De details zijn bewaard in een lokaal diagnoselog (Instellingen ▸ Diagnostics) dat je apparaat nooit verlaat. Ga terug en probeer het opnieuw.';

  @override
  String get crashFallbackCopied => 'Gekopieerd';

  @override
  String get crashFallbackCopyDetails => 'Details kopiëren';

  @override
  String get commonCancel => 'Annuleren';

  @override
  String get commonDiscardChangesTitle => 'Wijzigingen verwerpen?';

  @override
  String get commonDiscardChangesBody => 'Je hebt niet-opgeslagen wijzigingen.';

  @override
  String get commonKeepEditing => 'Doorgaan met bewerken';

  @override
  String get commonDiscard => 'Verwerpen';

  @override
  String get commonContinue => 'Doorgaan';

  @override
  String get commonUndo => 'Ongedaan maken';

  @override
  String get commonUndoFailed =>
      'Dat kon niet ongedaan worden gemaakt. Controleer het resultaat en probeer het opnieuw.';

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
  String get commonDanceStatusDraft => 'Concept';

  @override
  String get commonDanceStatusVariation => 'Variatie';

  @override
  String get commonDanceLevelBeginner => 'Beginner';

  @override
  String get commonDanceLevelIntermediate => 'Gemiddeld';

  @override
  String get commonDanceLevelAdvanced => 'Gevorderd';

  @override
  String get commonFormationDupleImproper => 'Improper';

  @override
  String get commonFormationProgressedImproper =>
      'Improper, reeds doorgeschoven';

  @override
  String get commonFormationReverseProgressionImproper =>
      'Improper met omgekeerde progressie';

  @override
  String get commonFormationBecketCw => 'Becket (CW)';

  @override
  String get commonFormationBecketCcw => 'Becket (CCW)';

  @override
  String get commonFormationDupleProper => 'Proper';

  @override
  String get commonFormationDupleIndecent => 'Indecent';

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
  String get commonFormationQuadruplet => 'Quadruplet';

  @override
  String get commonFormationOther => 'Overig';

  @override
  String commonFormationWithDetail(String shape, String detail) {
    return '$shape — $detail';
  }

  @override
  String get commonFormationDupleMinor => 'Duple minor';

  @override
  String get commonFormationThreeCoupleLongways => 'Three-couple longways';

  @override
  String get commonFormationFourCoupleLongways => 'Four-couple longways';

  @override
  String get commonFormationFiveCoupleLongways => 'Five-couple longways';

  @override
  String get commonFormationSixCoupleLongways => 'Six-couple longways';

  @override
  String get commonFormationCircle => 'Cirkel';

  @override
  String get commonFormationSquare => 'Square';

  @override
  String get commonFormationTwoCoupleSet => 'Two-couple set';

  @override
  String commonFormationImproperFlag(String shape) {
    return '$shape, improper';
  }

  @override
  String get danceEditorMeterLabel => 'Maatsoort';

  @override
  String get danceEditorMusicalKeyLabel => 'Toonsoort';

  @override
  String get danceEditorMeterHint => 'bijv. 3/2';

  @override
  String get danceEditorMusicalKeyHint => 'bijv. g mineur';

  @override
  String get danceEditorAlternateTitlesLabel => 'Andere titels';

  @override
  String get danceEditorAlternateTitlesHelper =>
      'Eén per regel. Zoeken op titel vindt de dans onder elk ervan.';

  @override
  String get danceEditorBarnesReferenceLabel => 'Barnes-verwijzing';

  @override
  String get danceEditorBarnesReferenceHint => 'bijv. BIII p. 92 of NiB';

  @override
  String danceAlsoKnownAs(String titles) {
    return 'Ook bekend als $titles';
  }

  @override
  String get danceAlsoKnownAsSeparator => '; ';

  @override
  String get danceSectionBarnes => 'Barnes-boeken';

  @override
  String danceAuthorsWithYear(String names, String year) {
    return '$names ($year)';
  }

  @override
  String danceComposedYear(String year) {
    return 'Gecomponeerd in $year';
  }

  @override
  String danceInterpretedBy(String names) {
    return 'Geïnterpreteerd door $names';
  }

  @override
  String danceInterpretedByWithYear(String names, String year) {
    return 'Geïnterpreteerd door $names ($year)';
  }

  @override
  String danceInterpretedYear(String year) {
    return 'Geïnterpreteerd in $year';
  }

  @override
  String danceBarnesValue(String reference) {
    return 'Barnes: $reference';
  }

  @override
  String danceMeterValue(String meter) {
    return 'Maatsoort: $meter';
  }

  @override
  String danceMusicalKeyValue(String key) {
    return 'Toonsoort: $key';
  }

  @override
  String get commonMixedLevel => 'Gemengd niveau';

  @override
  String get commonMixer => 'Mixer';

  @override
  String commonShowDancesTaggedTooltip(String tagName) {
    return '“$tagName” toevoegen aan de filters van de Collectie';
  }

  @override
  String commonDeletedSnack(String title) {
    return '“$title” verwijderd.';
  }

  @override
  String get commonCantBeUndone => 'Dit kan niet ongedaan worden gemaakt.';

  @override
  String get importGapMessage =>
      'Deze aanroep is niet herkend — precies zoals geschreven bewaard als niet-herkende figuur.';

  @override
  String get importGapDialogTitle => 'Niet-herkende figuur';

  @override
  String get importGapSemanticLabel =>
      'Niet-herkende figuur. Precies zoals geschreven bewaard.';

  @override
  String get collectionScreenTitle => 'Collectie';

  @override
  String get collectionNewDance => 'Nieuwe dans';

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
  String collectionGroupSectionSelectedSemantics(
    String label,
    int count,
    int selected,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count dansen',
      one: '1 dans',
    );
    return '$label, $_temp0, $selected geselecteerd';
  }

  @override
  String get collectionExitSelectionTooltip => 'Selectie verlaten';

  @override
  String collectionSelectedCount(int count) {
    return '$count geselecteerd';
  }

  @override
  String collectionSelectAllTooltip(int count) {
    return 'Alle $count selecteren';
  }

  @override
  String collectionDeselectAllTooltip(int count) {
    return 'Alle $count deselecteren';
  }

  @override
  String collectionSelectionNotShown(int selected, int hidden) {
    return '$selected geselecteerd ($hidden niet getoond)';
  }

  @override
  String get collectionDeselectNotShown => 'Niet-getoonde deselecteren';

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
  String get collectionSearchScopeLabel => 'Zoeken in';

  @override
  String get collectionSearchScopeOmni => 'Alle velden';

  @override
  String get collectionSearchScopeTitle => 'Titel';

  @override
  String get collectionSearchScopeAuthor => 'Auteur';

  @override
  String get collectionSearchScopeFigure => 'Figuur';

  @override
  String get collectionClearSearchTooltip => 'Zoekterm en filters wissen';

  @override
  String get collectionLoadError =>
      'De collectie kon niet worden geladen. Er is niets gewijzigd. Probeer het opnieuw.';

  @override
  String collectionDuplicatedSnack(String title) {
    return 'Gedupliceerd als “$title”.';
  }

  @override
  String get collectionEmptyBody =>
      'Voeg een dans toe of importeer er een om te beginnen — of schakel Onlinezoeken hierboven in om te importeren vanuit een onlinebron.';

  @override
  String get collectionEmptyTitle => 'Je collectie is leeg';

  @override
  String get collectionImportCardTitle => 'Haal je dansen binnen';

  @override
  String get collectionImportCardBody =>
      'Importeer dansen die je al hebt, of schrijf je eerste. „The Baby Rose” staat er als voorbeeld om rond te kijken.';

  @override
  String get collectionBrowsePublishedCollections =>
      'Gepubliceerde collecties bekijken';

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
  String get collectionAdvancedActive => 'Geavanceerd (aan)';

  @override
  String searchToolActiveCount(String tool, int count) {
    return '$tool · $count';
  }

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
      'De zoekopdracht kon niet worden uitgevoerd. Er is niets gewijzigd. Probeer het opnieuw.';

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
  String get collectionSetStatus => 'Status instellen';

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
  String collectionBatchStatusSet(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Status ingesteld voor $count dansen',
      one: 'Status ingesteld voor 1 dans',
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
  String collectionBatchDeleted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count dansen verwijderd',
      one: '1 dans verwijderd',
    );
    return '$_temp0';
  }

  @override
  String collectionBatchDeletedAnnouncement(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count dansen verwijderd. Herstel ze via Onlangs verwijderd.',
      one: '1 dans verwijderd. Herstel hem via Onlangs verwijderd.',
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
  String get collectionFacetCallStatus => 'Belgeschiedenis';

  @override
  String get collectionFacetCalled => 'Gebeld';

  @override
  String get collectionFacetNotCalled => 'Niet gecalld';

  @override
  String get collectionFacetHistoryInert => 'Geldt bij Gecalld of Niet gecalld';

  @override
  String get collectionFacetVenue => 'Op locatie';

  @override
  String get collectionFacetVenueAny => 'Elke locatie';

  @override
  String get collectionFacetVenueUnnamed => 'Naamloze locatie';

  @override
  String get collectionFacetVenueClear => 'Locatie wissen';

  @override
  String get collectionFacetVenueSheetTitle => 'Locatie';

  @override
  String collectionFacetVenuePrograms(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count programma\'s',
      one: '1 programma',
    );
    return '$_temp0';
  }

  @override
  String get collectionFacetVenueTyped => 'getypt';

  @override
  String get collectionFacetWithin => 'Binnen';

  @override
  String get collectionFacetWithinAnyTime => 'Altijd';

  @override
  String get collectionFacetWithinNever => 'Nooit gecalld';

  @override
  String collectionFacetWithinMonths(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count maanden',
      one: '1 maand',
    );
    return '$_temp0';
  }

  @override
  String collectionFacetWithinMonthsSaved(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count maanden, opgeslagen',
      one: '1 maand, opgeslagen',
    );
    return '$_temp0';
  }

  @override
  String get collectionFacetWithinSince => 'Sinds een datum…';

  @override
  String collectionFacetWithinSinceDate(String date) {
    return 'Sinds $date';
  }

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
  String get collectionFacetUntagged => 'Zonder tags';

  @override
  String get collectionFacetTagsMatchLabel => 'Tags matchen';

  @override
  String get collectionFacetTagsMatchAll => 'Alle tags';

  @override
  String get collectionFacetTagsMatchAllTooltip =>
      'Dansen tonen die alle gekozen tags hebben';

  @override
  String get collectionFacetTagsMatchAny => 'Minstens één tag';

  @override
  String get collectionFacetTagsMatchAnyTooltip =>
      'Dansen tonen die minstens één van de gekozen tags hebben';

  @override
  String get collectionFacetMeter => 'Maatsoort';

  @override
  String get collectionFacetMusicalKey => 'Toonsoort';

  @override
  String get collectionFacetSource => 'Bron';

  @override
  String get collectionFacetAuthor => 'Auteur';

  @override
  String get collectionFacetNone =>
      'Nog geen filters beschikbaar voor deze collectie.';

  @override
  String get collectionFacetAllHidden =>
      'Alle filters zijn verborgen. Je kunt ze weer tonen via Instellingen ▸ Standaarden.';

  @override
  String get collectionFacetMissingValue => 'Niet in je bibliotheek';

  @override
  String get collectionFacetStaleFields =>
      'Verwijderde of gewijzigde aangepaste velden';

  @override
  String collectionFacetStaleFieldValue(String field, String value) {
    return '$field: $value';
  }

  @override
  String get collectionFacetClear => 'Filters wissen';

  @override
  String collectionFacetRemoveAuthor(String name) {
    return '$name verwijderen';
  }

  @override
  String get collectionFacetAuthorSearchHint => 'Auteurs zoeken…';

  @override
  String get collectionFacetTunes => 'Deuntjes';

  @override
  String get collectionFacetTunesSearchHint => 'Deuntje zoeken of toevoegen…';

  @override
  String collectionFacetAddTune(String name) {
    return '“$name” toevoegen';
  }

  @override
  String collectionFacetRemoveTune(String name) {
    return '$name verwijderen';
  }

  @override
  String get collectionFacetOpContains => 'bevat';

  @override
  String get collectionFacetOpEquals => 'is gelijk aan';

  @override
  String collectionFacetTextHint(String label) {
    return 'Filteren op $label…';
  }

  @override
  String get collectionFacetTextClearTooltip => 'Filter wissen';

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
  String get collectionQueryHasTag => 'Heeft tag';

  @override
  String collectionQueryHasTagUnavailable(String source) {
    return 'Heeft tag (niet beschikbaar bij $source)';
  }

  @override
  String get collectionQueryAnyFigure => 'Elke figuur';

  @override
  String get collectionQueryTagLabel => 'Tag';

  @override
  String get collectionQueryTagHint => 'Kies een tag';

  @override
  String get collectionQueryRemoveTag => 'Tag verwijderen';

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
  String get collectionQueryThenNext => 'Daarna';

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
  String collectionQueryParamNotOffered(String param, String value) {
    return '$param: $value (niet aangeboden)';
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
  String get collectionBatchApplyError =>
      'De batchwijzigingen konden niet worden toegepast. Probeer het opnieuw.';

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
  String get collectionBatchStatusConfirm => 'Instellen';

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
      other: '$beats tellen',
      one: '1 tel',
    );
    return '$_temp0';
  }

  @override
  String exportNamedPhrases(String order, String bars) {
    return '$order ($bars)';
  }

  @override
  String get exportNamedPhraseSeparator => ', ';

  @override
  String get exportLabelSeparator => ': ';

  @override
  String danceFigureBars(String bars, int halfBars) {
    String _temp0 = intl.Intl.pluralLogic(
      halfBars,
      locale: localeName,
      other: '$bars maten',
      two: '$bars maat',
      one: '$bars maat',
    );
    return '$_temp0';
  }

  @override
  String get danceEditorBarsLabel => 'Maten';

  @override
  String get danceEditorStepUntimed => 'Geen eigen duur';

  @override
  String danceEditorBarsRangeError(int max) {
    return 'Voer hele of halve maten in, tot $max';
  }

  @override
  String danceEditorHalfBarRefused(int beatsPerBar) {
    return 'Alleen hele maten, bij $beatsPerBar tellen per maat';
  }

  @override
  String danceEditorMeterFigureBarsKept(int beatsPerBar) {
    String _temp0 = intl.Intl.pluralLogic(
      beatsPerBar,
      locale: localeName,
      other: '$beatsPerBar tellen',
      one: '1 tel',
    );
    return 'De tellen van de figuren zijn aangepast, zodat elke figuur haar maten houdt, nu met $_temp0 per maat.';
  }

  @override
  String danceEditorMeterFigureBarsNotKept(int beatsPerBar) {
    String _temp0 = intl.Intl.pluralLogic(
      beatsPerBar,
      locale: localeName,
      other: '$beatsPerBar tellen',
      one: '1 tel',
    );
    return 'Tellen niet aangepast: niet elke figuur kon haar maten precies houden, dus ze lezen nu in maten van $_temp0. Controleer ze.';
  }

  @override
  String get danceEditorSequenceSpanLabel => 'Maten voor alles';

  @override
  String get danceEditorSequenceSpanEmptyHelp =>
      'Laat leeg om de maten van de stappen op te tellen, of geef de maten van de hele reeks, zoals ‘A, B en C in maat 1–4’.';

  @override
  String get danceEditorSequenceSpanHelp =>
      'De stappen delen deze maten, en elke stap mag zijn eigen maten leeg laten.';

  @override
  String danceEditorSequenceSpanMismatch(String steps, String span) {
    return 'De stappen duren $steps, maar de reeks duurt $span.';
  }

  @override
  String danceEditorSequenceSpanNoRoom(String steps, String span) {
    return 'De stappen met eigen maten duren $steps van de $span van de reeks, zodat er niets overblijft voor de rest.';
  }

  @override
  String get danceEditorSequenceSpanBeatsLabel => 'Tellen voor alles';

  @override
  String get danceEditorSequenceSpanBeatsEmptyHelp =>
      'Laat leeg om de tellen van de stappen op te tellen, of geef de tellen van de hele reeks, zoals ‘forward again and swing (8)’.';

  @override
  String get danceEditorSequenceSpanBeatsHelp =>
      'De stappen delen deze tellen, en elke stap mag zijn eigen tellen leeg laten.';

  @override
  String danceEditorSequenceSpanBeatsNoRoom(String steps, String span) {
    return 'De stappen met eigen tellen duren $steps van de $span van de reeks, zodat er niets overblijft voor de rest.';
  }

  @override
  String danceEditorSequenceOverPhraseTimed(String length, String limit) {
    return 'Deze reeks duurt $length, langer dan de frase waarin hij begint ($limit).';
  }

  @override
  String get danceFigureProgressionSemantic => 'progressie';

  @override
  String danceFigureNote(String note) {
    return 'notitie: $note';
  }

  @override
  String get danceScreenTitle => 'Dans';

  @override
  String get danceNotFound => 'Dans niet gevonden.';

  @override
  String get danceLoadError =>
      'Deze dans kon niet worden geladen. Er is niets gewijzigd. Probeer het opnieuw.';

  @override
  String get danceEditFab => 'Bewerken';

  @override
  String get danceDuplicateTooltip => 'Dans dupliceren';

  @override
  String get danceDeleteTooltip => 'Dans verwijderen';

  @override
  String get danceMoreActions => 'Meer acties';

  @override
  String get programsMoreActions => 'Meer acties';

  @override
  String get programsFormMatchLabel => 'Types matchen';

  @override
  String get programsFormMatchOnly => 'Alleen';

  @override
  String get programsFormMatchOnlyTooltip =>
      'Programma\'s met alleen de gekozen types';

  @override
  String get programsFormMatchIncludes => 'Bevat';

  @override
  String get programsFormMatchIncludesTooltip =>
      'Programma\'s met het gekozen type';

  @override
  String get danceSectionFigures => 'Figuren';

  @override
  String get danceSectionCallingNotes => 'Callnotities';

  @override
  String get danceSectionWalkthrough => 'Doorloop';

  @override
  String get danceFiguresUnreadable =>
      'Deze figuren kunnen niet worden gelezen.';

  @override
  String get danceTunesUnreadable =>
      'Deze deuntjes kunnen niet worden gelezen.';

  @override
  String get danceUnreadableReassurance =>
      'Er is niets verwijderd. Wat is opgeslagen blijft precies zoals het is, en als je iets anders aan deze dans bewerkt, wordt het niet vervangen.';

  @override
  String get danceEditorFiguresUnreadable =>
      'De opgeslagen figuren kunnen niet worden gelezen, dus ze worden hier niet getoond. Ze blijven zoals ze zijn, tenzij je zelf figuren toevoegt.';

  @override
  String get danceEditorTunesUnreadable =>
      'De opgeslagen deuntjes kunnen niet worden gelezen en worden hier daarom niet getoond. Ze blijven zoals ze zijn, tenzij je eigen deuntjes toevoegt.';

  @override
  String get danceListUnreadableBadge => 'Niet leesbaar';

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
  String get danceCallingHistoryError =>
      'De callinggeschiedenis kon niet worden geladen. Er is niets gewijzigd. Probeer het opnieuw.';

  @override
  String danceVenueCallCount(int count, String venue) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count keer gecalld bij $venue',
      one: '1 keer gecalld bij $venue',
    );
    return '$_temp0';
  }

  @override
  String get danceShowCanonicalTerms => 'Canonieke termen tonen';

  @override
  String get danceCanonicalToggleLabel => 'Canoniek';

  @override
  String get danceRoleTermsOverrideNote =>
      'Weergegeven met larks en robins: de auteur heeft gevraagd deze dans alleen ooit met die roltermen te callen, dus de roltermen van je dialect worden hier niet gebruikt.';

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
  String get programsDanceInThisProgram => 'In dit programma';

  @override
  String programsDanceInThisProgramCount(int count) {
    return 'In dit programma ×$count';
  }

  @override
  String get programsAddAgainTitle => 'Al in dit programma';

  @override
  String programsAddAgainBody(
    String danceTitle,
    String programTitle,
    int count,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '“$danceTitle” staat al $count keer in “$programTitle”. Opnieuw toevoegen?',
      one: '“$danceTitle” staat al in “$programTitle”. Opnieuw toevoegen?',
    );
    return '$_temp0';
  }

  @override
  String get programsAddAgain => 'Opnieuw toevoegen';

  @override
  String get programsAddToProgramSearchHint => 'Programma\'s zoeken';

  @override
  String get programsAddToProgramSearchClear => 'Zoekopdracht wissen';

  @override
  String get programsAddToProgramNoMatches =>
      'Geen programma\'s komen overeen met je zoekopdracht.';

  @override
  String programsAddToProgramPerformedGroup(int count) {
    return 'Uitgevoerd ($count)';
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
  String get programsMarkedAllPerformedExceptAlternates =>
      'Alle dansen behalve alternatieven gemarkeerd als uitgevoerd. Markeer een alternatief zelf als je het hebt gecalld.';

  @override
  String get programsMarkedAllPerformedSetStatus =>
      'Alle dansen gemarkeerd als uitgevoerd en de status op Uitgevoerd gezet.';

  @override
  String get programsMarkedAllPerformedExceptAlternatesSetStatus =>
      'Alle dansen behalve alternatieven gemarkeerd als uitgevoerd en de status op Uitgevoerd gezet. Markeer een alternatief zelf als je het hebt gecalld.';

  @override
  String programsSavedSnack(String title) {
    return '“$title” opgeslagen.';
  }

  @override
  String get programsSaveError =>
      'Het programma kon niet worden opgeslagen. Je wijzigingen staan er nog. Probeer het opnieuw.';

  @override
  String get programsUndoPerformedError =>
      'Dat kon niet ongedaan worden gemaakt. De uitgevoerd-markeringen zijn nog opgeslagen.';

  @override
  String get programsUndoRefreshError =>
      'Ongedaan maken is opgeslagen, maar de editor kon niet worden vernieuwd. Open het programma opnieuw om het te zien.';

  @override
  String programsDuplicatedSnack(String title) {
    return 'Gedupliceerd als “$title”.';
  }

  @override
  String programsDeletedSnack(String title) {
    return '“$title” verwijderd.';
  }

  @override
  String get programsArchive => 'Archiveren';

  @override
  String get programsUnarchive => 'Uit archief halen';

  @override
  String programsArchivedSnack(String title) {
    return '“$title” gearchiveerd.';
  }

  @override
  String programsUnarchivedSnack(String title) {
    return '“$title” uit het archief gehaald.';
  }

  @override
  String get programsArchivedLabel => 'Gearchiveerd';

  @override
  String get programsShowArchived => 'Gearchiveerde tonen';

  @override
  String get programsHideArchived => 'Gearchiveerde verbergen';

  @override
  String get programsAllArchivedTitle => 'Geen programma\'s om te tonen';

  @override
  String get programsAllArchivedBody => 'Al je programma\'s zijn gearchiveerd.';

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
  String programsDraftAnotherNewProgramBody(String title) {
    return 'Je hebt een niet-opgeslagen concept van een ander nieuw programma, ‘$title’. Wil je het herstellen in plaats van een nieuw te beginnen?';
  }

  @override
  String get programsDraftAnotherNewProgramUntitledBody =>
      'Je hebt een niet-opgeslagen concept van een ander nieuw programma, nog zonder titel. Wil je het herstellen in plaats van een nieuw te beginnen?';

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
  String get commonSave => 'Opslaan';

  @override
  String get programsLoading => 'Programma laden';

  @override
  String get programsLoadError =>
      'Het programma kon niet worden geladen. Er is niets gewijzigd. Probeer het opnieuw.';

  @override
  String get programsUndoRecoveryFailed =>
      'Het programma kon na het ongedaan maken niet opnieuw worden geladen. Ga terug en open het opnieuw om de huidige staat te zien.';

  @override
  String get programsDeletedDanceFallback => '(verwijderde dans)';

  @override
  String get programsRestoreDeletedDance => 'Herstellen uit Onlangs verwijderd';

  @override
  String programsRestoreDeletedDanceError(String title) {
    return 'Kon “$title” niet herstellen. De dans staat nog in Onlangs verwijderd.';
  }

  @override
  String get programsBlankedDanceTitle => 'Verwijderde dans';

  @override
  String get programsSlotsLabel => 'Slots';

  @override
  String get programsSlotsHelper =>
      'Elk slot is één plaats in je setlijst: een dans, een notitie of een pauze.';

  @override
  String get programsAddDanceButton => 'Dans toevoegen';

  @override
  String get programsAddNoteBreakButton => 'Notitie of pauze toevoegen';

  @override
  String get programsInsertBreakButton => 'Pauze invoegen';

  @override
  String get programsBreakSlotLabel => 'Pauze';

  @override
  String get programsAddADanceSheetTitle => 'Een dans toevoegen';

  @override
  String get commonClose => 'Sluiten';

  @override
  String get viewDetails => 'Details bekijken';

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
  String get programsStartTimeLabel => 'Begintijd';

  @override
  String get programsEndTimeLabel => 'Eindtijd';

  @override
  String get programsLessonTimeLabel => 'Beginnersles';

  @override
  String get programsArrivalTimeLabel => 'Aanwezig om';

  @override
  String get programsNoTimeSet => 'Niet ingesteld';

  @override
  String get programsSetTime => 'Instellen';

  @override
  String get programsChangeTime => 'Wijzigen';

  @override
  String programsSetTimeFor(String field) {
    return '$field instellen';
  }

  @override
  String programsChangeTimeFor(String field) {
    return '$field wijzigen';
  }

  @override
  String programsClearTime(String field) {
    return '$field wissen';
  }

  @override
  String get programsTimeNextDay => 'Eindigt de volgende dag';

  @override
  String programsVenueUsualTimeHint(String time) {
    return 'Gebruikelijke tijd van de locatie: $time';
  }

  @override
  String programsSummaryLessonTime(String time) {
    return 'Les $time';
  }

  @override
  String programsSummaryDanceTime(String times) {
    return 'Dans $times';
  }

  @override
  String programsSummaryArriveBy(String time) {
    return 'Aanwezig om $time';
  }

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
  String get programsPayLabel => 'Gage';

  @override
  String get programsPayHint => 'bijv. 250.00';

  @override
  String get programsPayCurrencyLabel => 'Valuta';

  @override
  String get programsPayInvalid =>
      'Voer een bedrag in zoals 250 of 250.50 in deze valuta in.';

  @override
  String get programsStatusFieldLabel => 'Status';

  @override
  String get programsStatusHelper =>
      'Sla je een wijziging naar Uitgevoerd op, dan wordt elke ongemarkeerde dans behalve alternatieven gemarkeerd als uitgevoerd. Zet je de status terug, dan blijven de markeringen staan.';

  @override
  String get programsStatusHelperMarkAllSetsStatus =>
      'Sla je een wijziging naar Uitgevoerd op, dan wordt elke ongemarkeerde dans behalve alternatieven gemarkeerd als uitgevoerd, en Alles markeren als uitgevoerd zet deze status. Zet je de status terug, dan blijven de markeringen staan.';

  @override
  String get programsHideAlternatesTitle =>
      'Alternatieven verbergen in de setlijst';

  @override
  String get programsHideAlternatesSubtitle =>
      'Laat ALT-slots weg uit de samenvatting, PDF en geëxporteerde setlijst. De opbouwer toont nog steeds elk slot.';

  @override
  String get programsDialectFieldLabel => 'Dialect voor Uitvoeren';

  @override
  String get programsDialectUseApp => 'App-dialect gebruiken';

  @override
  String programsDialectUnavailable(String name) {
    return '$name (niet beschikbaar)';
  }

  @override
  String get programsDialectHelper =>
      'Alleen in Uitvoeren van dit programma. Editor, samenvatting en exports blijven het app-dialect gebruiken.';

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
  String get programsSearchTooltip => 'Programma’s zoeken';

  @override
  String get programsSearchHint => 'Programma’s zoeken…';

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
      'Je programma\'s konden niet worden geladen. Er is niets gewijzigd. Probeer het opnieuw.';

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
  String programsSummaryPay(String amount) {
    return 'Gage: $amount';
  }

  @override
  String programsSetListHeader(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count dansen',
      one: '1 dans',
    );
    return 'Setlijst ($_temp0)';
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
    return 'Notitie: $note';
  }

  @override
  String programsSummaryAlternateSemantic(String title) {
    return 'Alternatief: $title';
  }

  @override
  String get programsPerformed => 'Uitgevoerd';

  @override
  String programsDanceCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count dansen',
      one: '1 dans',
    );
    return '$_temp0';
  }

  @override
  String get programsSlotNoteFallback => 'Notitie';

  @override
  String get programsSlotEditorEmptyTitle => 'Nog geen slots';

  @override
  String get programsSlotEditorEmptyBody =>
      'Voeg een dans of een notitie toe om te beginnen.';

  @override
  String get programsSlotMovedUp => 'Slot omhoog verplaatst.';

  @override
  String get programsSlotMovedDown => 'Slot omlaag verplaatst.';

  @override
  String get programsMarkedPrimary => 'Gemarkeerd als primair.';

  @override
  String get programsMarkedAlternate => 'Gemarkeerd als alternatief.';

  @override
  String get programsMarkedPerformed => 'Gemarkeerd als uitgevoerd.';

  @override
  String programsSummaryPerformedToggleOn(String title) {
    return '$title: uitgevoerd';
  }

  @override
  String programsSummaryPerformedToggleOff(String title) {
    return '$title: niet uitgevoerd';
  }

  @override
  String programsSummaryMarkPerformedTooltip(String title) {
    return '$title markeren als uitgevoerd';
  }

  @override
  String programsSummaryClearPerformedTooltip(String title) {
    return 'Uitvoermarkering van $title wissen';
  }

  @override
  String programsSummaryMarkedPerformedSnack(String title) {
    return '$title gemarkeerd als uitgevoerd.';
  }

  @override
  String programsSummaryClearedPerformedSnack(String title) {
    return 'Uitvoermarkering van $title gewist.';
  }

  @override
  String get programsSummaryPerformedToggleError =>
      'De uitgevoerd-markering kon niet worden bijgewerkt. Probeer het opnieuw.';

  @override
  String get programsSummaryUndoPerformedToggleError =>
      'Die wijziging van de uitgevoerd-markering kon niet ongedaan worden gemaakt. Probeer het opnieuw.';

  @override
  String get programsPerformedCleared => 'Uitvoermarkering gewist.';

  @override
  String programsRemovedSlot(String name) {
    return '$name verwijderd.';
  }

  @override
  String programsAlternatePromoted(String name) {
    return '$name neemt de plaats in.';
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
  String get programsAddDanceBeforeMenu => 'Dans ervoor toevoegen';

  @override
  String get programsAddDanceAfterMenu => 'Dans erna toevoegen';

  @override
  String programsAddBeforeSheetTitle(String title) {
    return 'Toevoegen vóór $title';
  }

  @override
  String programsAddAfterSheetTitle(String title) {
    return 'Toevoegen na $title';
  }

  @override
  String programsAddingBeforeBanner(String title) {
    return 'Toevoegen vóór $title';
  }

  @override
  String programsAddingAfterBanner(String title) {
    return 'Toevoegen na $title';
  }

  @override
  String programsAddedDanceBeforeAnnounce(String title, String target) {
    return '$title toegevoegd vóór $target.';
  }

  @override
  String programsAddedDanceAfterAnnounce(String title, String target) {
    return '$title toegevoegd na $target.';
  }

  @override
  String get programsInsertionCancelledAnnounce =>
      'Geannuleerd. Nieuwe dansen komen aan het eind.';

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
  String get programsCreateDanceFromNoteMenu => 'Maak hier een dans van';

  @override
  String programsCreatedDanceFromNoteAnnounce(String title) {
    return '$title aangemaakt en aan dit slot gekoppeld.';
  }

  @override
  String get programsSlotTextRequiredError =>
      'Voer wat tekst in voor dit slot.';

  @override
  String get programsWholeNumberError => 'Voer een geheel getal ≥ 0 in.';

  @override
  String get programsEditDanceSlotTitle => 'Dansslot bewerken';

  @override
  String get programsCurrentDanceLabel => 'Dans';

  @override
  String get programsReplaceDanceButton => 'Vervangen…';

  @override
  String get programsReplaceDanceSheetTitle => 'Dans vervangen';

  @override
  String programsReplacedDanceAnnounce(String title) {
    return 'Vervangen door $title.';
  }

  @override
  String get programsEditNoteTitle => 'Notitie bewerken';

  @override
  String get programsCallerNoteLabel => 'Callernotitie (optioneel)';

  @override
  String get programsCallerNoteHint => 'bijv. leer de hey eerst';

  @override
  String get programsGuestCallerLabel => 'Gastcaller (optioneel)';

  @override
  String get programsPlannedTimingHeader => 'Geplande timing';

  @override
  String get programsWalkthroughMinutesLabel => 'Doorloopminuten (optioneel)';

  @override
  String get programsDanceMinutesLabel => 'Dansminuten (optioneel)';

  @override
  String get programsAlternateDanceTitle => 'Alternatieve dans';

  @override
  String get programsAlternateDanceSubtitle =>
      'Wordt ingesprongen weergegeven onder het slot erboven.';

  @override
  String get commonDone => 'Klaar';

  @override
  String programsMatrixSemanticLabel(int danceCount, int moveCount) {
    String _temp0 = intl.Intl.pluralLogic(
      moveCount,
      locale: localeName,
      other: '$moveCount moves',
      one: '1 move',
    );
    return 'Programmeringsmatrix: $danceCount dansen bij $_temp0';
  }

  @override
  String programsMatrixOmittedCaption(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count vrije-tekstslots',
      one: '1 vrije-tekstslot',
    );
    return '$_temp0 (pauzes, notities) weggelaten — de matrix toont alleen dansen.';
  }

  @override
  String programsMatrixMoveHeaderSemantic(String label) {
    return 'Move: $label';
  }

  @override
  String programsMatrixHideColumnSemantic(String label) {
    return 'Kolom $label verbergen';
  }

  @override
  String get programsMatrixShowAllColumnsSemantic => 'Alle kolommen weergeven';

  @override
  String get programsMatrixHideAlternatesSemantic =>
      'Alternatieve rijen verbergen';

  @override
  String get programsMatrixShowAlternatesSemantic =>
      'Alternatieve rijen weergeven';

  @override
  String get programsMatrixShowPhrasesSemantic => 'Fraselabels tonen';

  @override
  String get programsMatrixHidePhrasesSemantic => 'Aanwezigheidsglyphs tonen';

  @override
  String programsMatrixSectionShort(String sectionKey, String sectionNumber) {
    String _temp0 = intl.Intl.selectLogic(sectionKey, {
      's1': '1e',
      's2': '2e',
      's3': '3e',
      's4': '4e',
      's5': '5e',
      's6': '6e',
      's7': '7e',
      's8': '8e',
      's9': '9e',
      'other': '$sectionNumber',
    });
    return '$_temp0';
  }

  @override
  String programsMatrixSectionRowHeaderSemantic(
    String title,
    String alt,
    String section,
  ) {
    String _temp0 = intl.Intl.selectLogic(section, {
      'none': 'Alternatieve dans: $title',
      'other': 'Alternatieve dans: $title, sectie $section',
    });
    String _temp1 = intl.Intl.selectLogic(section, {
      'none': 'Dans: $title',
      'other': 'Dans: $title, sectie $section',
    });
    String _temp2 = intl.Intl.selectLogic(alt, {
      'yes': '$_temp0',
      'other': '$_temp1',
    });
    return '$_temp2';
  }

  @override
  String programsMatrixSectionChipQualifiedTitle(
    String title,
    String alt,
    String section,
  ) {
    String _temp0 = intl.Intl.selectLogic(section, {
      'none': '$title (alternatieve dans)',
      'other': '$title (alternatieve dans, sectie $section)',
    });
    String _temp1 = intl.Intl.selectLogic(section, {
      'none': '$title',
      'other': '$title (sectie $section)',
    });
    String _temp2 = intl.Intl.selectLogic(alt, {
      'yes': '$_temp0',
      'other': '$_temp1',
    });
    return '$_temp2';
  }

  @override
  String get programsMatrixFormationColumnHeader => 'Formatie';

  @override
  String programsMatrixFormationSemantic(String dance, String label) {
    return '$dance, formatie: $label';
  }

  @override
  String programsMatrixCellSemantic(
    String dance,
    String move,
    String present,
    String phrases,
    String collision,
    String debut,
    String first,
  ) {
    String _temp0 = intl.Intl.selectLogic(collision, {
      'phrase': ', herhaalt in dezelfde frase als een aangrenzende dans',
      'beats': ', deelt tellen met een aangrenzende dans',
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
    String _temp4 = intl.Intl.selectLogic(phrases, {
      'none': '',
      'other': ', frase(n): $phrases',
    });
    return '$dance, $move: $_temp3$_temp4';
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
  String get programsMatrixLegendCollisionBeats =>
      'Deelt tellen met aangrenzende dans';

  @override
  String get programsMatrixEmptyTitle => 'Nog geen gestructureerde figuren';

  @override
  String get programsMatrixEmptyBody =>
      'De matrix wordt automatisch gevuld naarmate de dansen in het programma gestructureerde figuren krijgen.';

  @override
  String get performTitle => 'Uitvoeren';

  @override
  String get performExitTooltip => 'Uitvoeren verlaten';

  @override
  String get performExitTitle => 'Uitvoeren verlaten?';

  @override
  String get performExitBody =>
      'Uitvoeren verlaten? Je plek en de lopende klok worden bewaard, zodat je kunt hervatten waar je gebleven was.';

  @override
  String get performDanceExitBody =>
      'Uitvoeren verlaten? Bij het uitvoeren van één dans wordt je plek niet bewaard, dus de volgende keer begin je opnieuw.';

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
  String get performAddedNoteAnnounce => 'Notitie toegevoegd';

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
  String get performAdHocNoteLabel => 'Improvisatienotitie / pauze';

  @override
  String get performAdHocNoteHint => 'bijv. Wals, aankondigingen';

  @override
  String get performAddNote => 'Notitie toevoegen';

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
  String get performProgramClockLabel => 'Programma';

  @override
  String get performSlotClockLabel => 'Slot';

  @override
  String performShowingSlot(String label) {
    return '$label tonen';
  }

  @override
  String get performAdjustmentUndone => 'Aanpassing ongedaan gemaakt';

  @override
  String get performUndoNoLongerAvailable =>
      'Kan niet ongedaan maken: het programma is sindsdien gewijzigd.';

  @override
  String get performProgramChangedElsewhere =>
      'Dit programma was elders gewijzigd sinds Uitvoeren werd geopend. Uitvoeren toont nu de nieuwste versie, met jouw wijziging.';

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
    int walkthrough,
    int dance,
    String walkthroughComplete,
    String over,
    String paused,
    String manual,
    String actual,
    String direction,
    String delta,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      planned,
      locale: localeName,
      other: '$planned minuten',
      one: '1 minuut',
    );
    String _temp1 = intl.Intl.selectLogic(hasPlanned, {
      'yes':
          ', gepland $_temp0: $walkthrough minuten doorloop en $dance minuten dans',
      'other': '',
    });
    String _temp2 = intl.Intl.selectLogic(direction, {
      'over': ', $delta boven plan',
      'under': ', $delta onder plan',
      'other': ', volgens plan',
    });
    String _temp3 = intl.Intl.selectLogic(manual, {
      'yes': ', doorloop eindigde bij $actual$_temp2',
      'other': '',
    });
    String _temp4 = intl.Intl.selectLogic(walkthroughComplete, {
      'yes': ', doorloop voltooid',
      'other': '',
    });
    String _temp5 = intl.Intl.selectLogic(over, {
      'yes': ', over de geplande tijd',
      'other': '',
    });
    String _temp6 = intl.Intl.selectLogic(paused, {
      'yes': ', gepauzeerd',
      'other': '',
    });
    return 'Programmatijd $programTime, slottijd $slotTime$_temp1$_temp3$_temp4$_temp5$_temp6';
  }

  @override
  String performIndividualTimingSemantic(String elapsedTime, String paused) {
    String _temp0 = intl.Intl.selectLogic(paused, {
      'yes': ', gepauzeerd',
      'other': '',
    });
    return 'Verstreken tijd $elapsedTime$_temp0';
  }

  @override
  String performPlannedSplit(int planned, int walkthrough, int dance) {
    return 'gepland $planned min ($walkthrough:$dance)';
  }

  @override
  String get performDanceStartUnused => 'Doorloop klaar — start de dans';

  @override
  String get performDanceStartUsed => 'Dans gestart — tik om ongedaan te maken';

  @override
  String performWalkthroughActual(
    String actual,
    String direction,
    String delta,
  ) {
    String _temp0 = intl.Intl.selectLogic(direction, {
      'over': ' (+$delta)',
      'under': ' (−$delta)',
      'other': ' (volgens plan)',
    });
    return 'doorloop $actual$_temp0';
  }

  @override
  String get performWalkthroughCompleteSuffix => ' doorloop voltooid';

  @override
  String get performOverSuffix => ' over';

  @override
  String get performSlotCallerNote => 'Callernotitie';

  @override
  String get performCallingNotes => 'Callnotities';

  @override
  String get performWalkthrough => 'Doorloop';

  @override
  String get performShowWalkthrough => 'Doorloop tonen';

  @override
  String get performFullScreen => 'Volledig scherm';

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
      other: '$beats tellen',
      one: '1 tel',
    );
    String _temp3 = intl.Intl.selectLogic(hasNote, {
      'yes': ', notitie: $note',
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
  String get exportShareDanceBundle => 'Dansbestand delen';

  @override
  String get exportSaveDanceBundle => 'Dansbestand opslaan…';

  @override
  String get exportShowCode => 'Code tonen';

  @override
  String get exportShowCodeError =>
      'De code kon niet worden getoond. Je dans is ongewijzigd. Probeer het opnieuw.';

  @override
  String get danceCodeScreenTitle => 'Danscode';

  @override
  String danceCodeSemanticLabel(String title) {
    return 'QR-code voor $title';
  }

  @override
  String get danceCodeTooLong =>
      'Deze dans is te lang om als code te delen. Deel de dans in plaats daarvan als bestand.';

  @override
  String get exportCopyDance => 'Dans kopiëren';

  @override
  String get exportShareDanceJson => 'Dans exporteren als JSON';

  @override
  String get exportPrintPdf => 'Exporteren / afdrukken als PDF';

  @override
  String get exportDanceCopied => 'Dans gekopieerd naar klembord.';

  @override
  String get exportShareDanceError =>
      'Deze dans kon niet worden gedeeld. Je dans is ongewijzigd. Probeer het opnieuw.';

  @override
  String get exportDanceError =>
      'Deze dans kon niet worden geëxporteerd. Je dans is ongewijzigd. Probeer het opnieuw.';

  @override
  String get exportShareSetListText => 'Setlijst delen (tekst)';

  @override
  String get exportShareProgramBundle => 'Programma en dansen delen';

  @override
  String get exportSaveProgramBundle => 'Programmabestand opslaan…';

  @override
  String get exportCopySetList => 'Setlijst kopiëren';

  @override
  String get exportSetListCopied => 'Setlijst gekopieerd naar klembord.';

  @override
  String get exportShareProgramJson => 'Exporteren als JSON-bestand';

  @override
  String get exportJsonDialogTitle => 'JSON exporteren';

  @override
  String get exportJsonDialogMessage =>
      'Kies hoe je dit JSON-bestand wilt leveren.';

  @override
  String get exportJsonSave => 'Opslaan';

  @override
  String get exportJsonCopy => 'Ruwe JSON kopiëren';

  @override
  String get exportJsonShare => 'Delen';

  @override
  String get exportJsonSaveAs => 'Opslaan als…';

  @override
  String get exportJsonCancel => 'Annuleren';

  @override
  String get exportJsonCopied => 'JSON naar klembord gekopieerd.';

  @override
  String exportJsonSaved(String fileName) {
    return '\"$fileName\" opgeslagen.';
  }

  @override
  String get exportJsonSavedGeneric => 'JSON-bestand opgeslagen.';

  @override
  String exportJsonSavedTo(String fileName, String destination) {
    return '\"$fileName\" opgeslagen in $destination.';
  }

  @override
  String get exportJsonSaveError =>
      'Dit JSON-bestand kon niet worden opgeslagen. Probeer het opnieuw.';

  @override
  String get exportJsonCopyError =>
      'Deze JSON kon niet worden gekopieerd. Probeer het opnieuw.';

  @override
  String get exportJsonShareError =>
      'Dit JSON-bestand kon niet worden gedeeld. Probeer het opnieuw.';

  @override
  String get exportShareSetListError =>
      'Deze setlijst kon niet worden gedeeld. Probeer het opnieuw.';

  @override
  String get exportShareProgramError =>
      'Dit programma kon niet worden gedeeld. Je programma is ongewijzigd. Probeer het opnieuw.';

  @override
  String get exportSetListError =>
      'Deze setlijst kon niet worden geëxporteerd. Probeer het opnieuw.';

  @override
  String get exportIncludeFiguresTitle => 'Figuren opnemen?';

  @override
  String get exportIncludeFiguresSetListOnly => 'Alleen setlijst';

  @override
  String get exportIncludeFiguresSetListAndFigures => 'Setlijst en figuren';

  @override
  String get exportIncludeFiguresAlternate => 'Alternatief';

  @override
  String get exportMatrixPdfTooltip => 'Matrix exporteren of afdrukken als PDF';

  @override
  String get exportMatrixPdfFilename => 'Programmeringsmatrix';

  @override
  String get exportLabelFormation => 'Formatie';

  @override
  String get exportLabelLevel => 'Niveau';

  @override
  String get exportLabelMixer => 'Mixer';

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
  String get exportLabelTunes => 'Deuntjes';

  @override
  String get exportLabelHook => 'Hook';

  @override
  String get exportLabelSources => 'Bronnen';

  @override
  String exportSlotAuthorSuffix(String names) {
    return 'door $names';
  }

  @override
  String exportBeatsLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count tellen',
      one: '1 tel',
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
  String get exportUnknownDanceLabel => 'Naamloze dans';

  @override
  String exportMinutesLabel(int count) {
    return '$count min';
  }

  @override
  String exportPageOfPages(int page, int pages) {
    return 'Pagina $page van $pages';
  }

  @override
  String get exportLabelLesson => 'Les';

  @override
  String exportTimeRange(String start, String end) {
    return '$start–$end';
  }

  @override
  String exportEndsAt(String end) {
    return 'tot $end';
  }

  @override
  String exportNextDay(String times) {
    return '$times (volgende dag)';
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
  String get exportMatrixFormationColumn => 'Formatie';

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
  String get exportMatrixLegendCollisionBeats =>
      'Deelt tellen met aangrenzende dans';

  @override
  String exportMatrixOmittedCaption(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count vrije-tekstslots',
      one: '1 vrije-tekstslot',
    );
    return '$_temp0 (pauzes, notities) weggelaten — de matrix toont alleen dansen.';
  }

  @override
  String get exportVenueContactTitle =>
      'Locatiecontactgegevens opnemen in deze export?';

  @override
  String get exportVenueContactBody =>
      'Dit zijn persoonlijke contactgegevens van de locatie. Ze worden weggelaten uit deze export tenzij je kiest ze op te nemen.';

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
  String get collectionOnlineSearchFieldHint =>
      'Online dansen zoeken op titel, auteur of figuur…';

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
  String onlineResultCountCapped(int count) {
    return '$count online resultaten getoond. Er zijn er mogelijk meer: scroll omlaag om ze te laden.';
  }

  @override
  String onlineResultCountOfTotal(int count, int total) {
    return '$count van $total online resultaten getoond. Scroll omlaag om meer te laden.';
  }

  @override
  String onlineResultCountOfTotalStopped(int count, int total) {
    return '$count van $total online resultaten getoond.';
  }

  @override
  String onlineResultCountMaybeMore(int count) {
    return '$count online resultaten getoond. Er zijn er mogelijk meer.';
  }

  @override
  String get onlineAdvancedPartlyApplied =>
      'Sommige geavanceerde voorwaarden bestaan niet in ContraDB en zijn weggelaten.';

  @override
  String onlineSearchHintByPhrase(String source) {
    return 'Typ een titel of auteur, of voeg figuren per frase toe om te zoeken in $source.';
  }

  @override
  String onlineSearchHintTitle(String source) {
    return 'Typ een titel of auteur om te zoeken in $source.';
  }

  @override
  String collectionOnlineSearchHintByPhrase(String source) {
    return 'Typ een titel, auteur of figuur, of voeg figuren per frase toe om te zoeken in $source.';
  }

  @override
  String collectionOnlineSearchHintTitle(String source) {
    return 'Typ een titel, auteur of figuur om te zoeken in $source.';
  }

  @override
  String onlineNoResults(String source) {
    return 'Geen dansen op $source komen overeen met je zoekopdracht.';
  }

  @override
  String onlineLoadError(String source) {
    return 'Die dans kon niet van $source worden geladen. Probeer het opnieuw.';
  }

  @override
  String get onlineImportError =>
      'Die dans kon niet worden geïmporteerd. Probeer het opnieuw.';

  @override
  String onlineSearchFailed(String source) {
    return 'Zoeken in $source is niet gelukt. Probeer het opnieuw.';
  }

  @override
  String onlineImportCreated(String title) {
    return '“$title” geïmporteerd.';
  }

  @override
  String onlineImportUpdated(String title) {
    return '“$title” bijgewerkt met de onlineversie.';
  }

  @override
  String onlineImportUndoKeptChanged(String title) {
    return '“$title” is gewijzigd sinds je hem importeerde, dus Ongedaan maken heeft hem gelaten zoals hij is.';
  }

  @override
  String onlineImportAlreadyInCollection(String title) {
    return '“$title” staat al in je collectie.';
  }

  @override
  String onlineImportVariationDialogBody(String existingTitle) {
    return 'De titel en auteur van deze dans komen overeen met “$existingTitle”, maar de figuren verschillen. Hoe wil je hem importeren?';
  }

  @override
  String get onlineImportVariationDialogActionVariation =>
      'Importeren als variatie';

  @override
  String get onlineImportVariationDialogActionLink =>
      'Zelfde dans (bestaande bijwerken)';

  @override
  String onlineImportVariationDialogLinkWarning(String existingTitle) {
    return 'Jouw versie van “$existingTitle” wordt vervangen door het online record — inclusief de titel, figuren, callnotities en tags. De dans behoudt je beoordeling, je aangepaste velden, zijn plaats in je programma’s en zijn callerhistorie.';
  }

  @override
  String get onlineImportCrossSourceDuplicateDialogTitle =>
      'Je hebt deze dans al';

  @override
  String onlineImportCrossSourceDuplicateDialogBody(String existingTitle) {
    return 'Je collectie bevat “$existingTitle” al. Beide versies hebben dezelfde volgorde van moves.';
  }

  @override
  String get onlineImportCrossSourceDuplicateDialogActionDuplicate =>
      'Een tweede kopie importeren';

  @override
  String get onlineImportPossibleMatchDialogTitle => 'Heb je deze dans al?';

  @override
  String onlineImportPossibleMatchDialogBody(String incomingTitle) {
    return '“$incomingTitle” is misschien een dans die je al hebt onder een andere titel. Kies de dans die je door deze versie wilt vervangen, of importeer deze als nieuwe dans.';
  }

  @override
  String get onlineImportPossibleMatchDialogLinkWarning =>
      'De dans die je kiest wordt vervangen door het online record — inclusief de titel, figuren, callnotities en tags. De dans behoudt je beoordeling, je aangepaste velden, zijn plaats in je programma’s en zijn callerhistorie.';

  @override
  String get importFigurelessCannotReplace =>
      'Dit record bevat geen figuren en kan daarom geen van je dansen vervangen. Het kan nog wel als nieuwe dans worden geïmporteerd.';

  @override
  String get onlineImportPossibleMatchDialogActionNew =>
      'Importeren als nieuwe dans';

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
  String get importProgramFromTitleList => 'Importeren vanuit titellijst';

  @override
  String get importFromContraDb => 'Van ContraDB';

  @override
  String get importProgramFromContraDb => 'Importeren vanuit ContraDB';

  @override
  String get importProgramTitleLabel => 'Programmatitel';

  @override
  String get importProgramCreateError =>
      'Het geïmporteerde programma kon niet worden opgeslagen. Probeer het opnieuw.';

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
      other: '$notes notities',
      one: '1 notitie',
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
      'De ContraDB-programmalijst kon niet worden geladen. Er is niets geïmporteerd. Probeer het opnieuw.';

  @override
  String get importContraDbSearchPrompt =>
      'Typ een deel van een programmanaam om in ContraDB te zoeken.';

  @override
  String get importContraDbNoMatches => 'Geen overeenkomende programma\'s.';

  @override
  String get importContraDbMarkerImported => 'Geïmporteerd';

  @override
  String importContraDbMarkerImportedTooltip(String date) {
    return 'Geïmporteerd op $date';
  }

  @override
  String get importContraDbMarkerImportedTooltipNoDate =>
      'Al geïmporteerd uit ContraDB';

  @override
  String get importContraDbMarkerPossible => 'Mogelijk geïmporteerd';

  @override
  String get importContraDbMarkerPossibleTooltip =>
      'Er bestaat al een programma met deze titel';

  @override
  String importContraDbFetchError(String error) {
    return 'Dat programma kon niet worden opgehaald.\n$error';
  }

  @override
  String get importContraDbFetchGenericError =>
      'Dat programma kon niet worden opgehaald. Probeer het opnieuw.';

  @override
  String get importContraDbPastePrompt =>
      'Plak hierboven een ContraDB-programma-URL en tik op “Programma ophalen”.';

  @override
  String get importContraDbEmptyProgram =>
      'Geen dansen of notities gevonden op die programmapagina.';

  @override
  String get importContraDbResolveError =>
      'Het ContraDB-programma kon niet worden geïmporteerd. Probeer het opnieuw.';

  @override
  String importContraDbProgramProgress(int done, int total) {
    return 'Dans $done van $total importeren…';
  }

  @override
  String get importContraDbProgramConnectionFailed =>
      'De online archieven waren niet bereikbaar, dus er is niets geïmporteerd. Probeer het opnieuw zodra je online bent.';

  @override
  String get importContraDbProgramCancelled =>
      'Import geannuleerd – er is niets toegevoegd.';

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
      other: '$notes notities',
      one: '1 notitie',
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
      'Je collectie kon niet worden geladen. Er is niets gewijzigd. Probeer het opnieuw.';

  @override
  String get importTitleListDancesLabel => 'Danstitels (één per regel)';

  @override
  String get importTitleListDancesHint =>
      'Plak één danstitel per regel.\nNiet-herkende regels worden als notities bewaard.';

  @override
  String get importTitleListEmptyHint =>
      'Plak hierboven een lijst van danstitels voor een voorbeeld van het programma.';

  @override
  String get importResolving => 'Zoeken…';

  @override
  String get importResolveOnline => 'Niet-gekoppelde online zoeken';

  @override
  String get importPlaintextImportedOnline => 'Online geïmporteerd';

  @override
  String get importPlaintextLinked => 'Gekoppeld aan dans';

  @override
  String get importPlaintextAmbiguous =>
      'Meerdere overeenkomsten — als notitie toegevoegd';

  @override
  String get importPlaintextUnmatched =>
      'Geen overeenkomst — als notitie toegevoegd';

  @override
  String get importPlaintextSearchError =>
      'Online zoeken is niet gelukt. Probeer het opnieuw.';

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
      other: '$remaining titels bewaard als notities',
      one: '$remaining titel bewaard als notitie',
    );
    return 'Geen betrouwbare online overeenkomsten gevonden — $_temp0.';
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
      other: '; $remaining nog notities.',
      one: '; $remaining nog een notitie.',
      zero: '.',
    );
    return '$_temp0 online gekoppeld$_temp1';
  }

  @override
  String importPlaintextResolveConnectionFailed(int linked) {
    String _temp0 = intl.Intl.pluralLogic(
      linked,
      locale: localeName,
      other: ' – $linked titels online gekoppeld.',
      one: ' – $linked titel online gekoppeld.',
      zero: '.',
    );
    return 'Het opzoeken van titels is gestopt na een verbindingsfout$_temp0 Probeer de rest opnieuw zodra je online bent.';
  }

  @override
  String importPlaintextResolveCancelled(int linked) {
    String _temp0 = intl.Intl.pluralLogic(
      linked,
      locale: localeName,
      other: ' – $linked titels online gekoppeld.',
      one: ' – $linked titel online gekoppeld.',
      zero: '.',
    );
    return 'Het opzoeken van titels is gestopt$_temp0';
  }

  @override
  String get importReviewClose => 'Import sluiten';

  @override
  String get importReviewDiscardTitle => 'Deze import verwerpen?';

  @override
  String get importReviewDiscardBody =>
      'Als je nu weggaat, worden de lijst die je aan het nakijken bent en je keuzes erop verworpen.';

  @override
  String get importReviewKeepReviewing => 'Doorgaan met nakijken';

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
  String get fileDialogTypeBackupJson => 'Back-up (JSON)';

  @override
  String get fileDialogTypeCompendiumShare => 'Compendium-deelbestand';

  @override
  String get fileDialogTypeCompanionUsr => 'Caller’s Companion .USR';

  @override
  String get fileDialogTypeDiagnosticsLog => 'Diagnoselogboek';

  @override
  String get fileDialogTypeMacosUpdate => 'Caller’s Compendium-update';

  @override
  String get fileDialogTypeImages => 'Afbeeldingen';

  @override
  String get importSourceLabelCallersBox => 'The Caller\'s Box';

  @override
  String get importSourceLabelContraDb => 'ContraDB';

  @override
  String get importSourceLabelCallersCompanionUsr =>
      'een Caller\'s Companion .USR-bestand';

  @override
  String get importSourceLabelTitleList => 'een lijst met titels';

  @override
  String get importReviewTitleListSubtitle =>
      'Plak één danstitel per regel. Elke titel wordt ter controle getoond — de titels die je al hebt worden wel getoond maar nooit opnieuw geïmporteerd, en er wordt niets aan je collectie toegevoegd voordat je bevestigt.';

  @override
  String get importReviewPasteTitles => 'Danstitels, één per regel';

  @override
  String importReviewTitleListCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count titels',
      one: '1 titel',
      zero: 'Nog geen titels',
    );
    return '$_temp0';
  }

  @override
  String importReviewTitleListDuplicates(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count herhaalde titels genegeerd',
      one: '1 herhaalde titel genegeerd',
    );
    return '$_temp0';
  }

  @override
  String importTitleListTooManyTitles(int count, int max) {
    return 'Dat zijn $count titels. Importeer er maximaal $max tegelijk.';
  }

  @override
  String get importTitleListTextTooLong =>
      'Die plaktekst is te lang om als lijst met titels te worden gelezen. Probeer een kortere lijst te plakken.';

  @override
  String importReviewTitleListProgress(int done, int total) {
    return '$done van $total zoeken…';
  }

  @override
  String importReviewCommitProgress(int done, int total) {
    return '$done / $total';
  }

  @override
  String importReviewTitleListPasted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count geplakte titels',
      one: '1 geplakte titel',
    );
    return '$_temp0';
  }

  @override
  String importReviewProgramAmbiguousLine(String title) {
    return '„$title” — kies er één, of laat als notitie staan';
  }

  @override
  String importReviewAmbiguousGroup(String title) {
    return '„$title” — kies er één of sla alles over';
  }

  @override
  String importReviewMetadataAuthor(String author) {
    return 'Door $author';
  }

  @override
  String importReviewMetadataFormation(String formation) {
    return '$formation';
  }

  @override
  String importReviewMetadataSource(String source) {
    return 'Van $source';
  }

  @override
  String importReviewTitleListToImport(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count te importeren',
      one: '1 te importeren',
    );
    return '$_temp0';
  }

  @override
  String importReviewTitleListAmbiguous(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count vereisen een keuze',
      one: '1 vereist een keuze',
    );
    return '$_temp0';
  }

  @override
  String importReviewTitleListOwned(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count al in je collectie',
      one: '1 al in je collectie',
    );
    return '$_temp0';
  }

  @override
  String importReviewTitleListNotFound(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count niet gevonden',
      one: '1 niet gevonden',
    );
    return '$_temp0';
  }

  @override
  String importReviewTitleListOwnedBy(String authors) {
    return 'Je hebt deze dans al, van $authors.';
  }

  @override
  String get importReviewTitleListOwnedUnknownAuthor => 'Je hebt deze dans al.';

  @override
  String importReviewTitleListOwnedMany(int count) {
    return 'Je hebt $count dansen met deze titel.';
  }

  @override
  String get importTitleListReasonNoResults =>
      'The Caller\'s Box heeft geen dans met deze naam.';

  @override
  String get importTitleListReasonNoExactMatch =>
      'Alleen vergelijkbare resultaten — niets met precies deze titel.';

  @override
  String get importTitleListReasonMultipleExactMatches =>
      'Meerdere dansen hebben precies deze titel, dus het is niet duidelijk welke je bedoelde.';

  @override
  String get importTitleListReasonFetchError =>
      'The Caller\'s Box kon voor deze titel niet worden bereikt.';

  @override
  String get importTitleListReasonConnectionFailed =>
      'The Caller\'s Box kon niet worden bereikt – controleer je verbinding.';

  @override
  String get importTitleListConnectionBanner =>
      'Het opzoeken van titels is gestopt na een verbindingsfout. De titels die al in je collectie staan, worden getoond; probeer de rest zodra je online bent.';

  @override
  String get importTitleListReasonLineTooLong =>
      'Te lang voor een danstitel, dus er is niet naar gezocht.';

  @override
  String get importReviewTitleListNothingToImport =>
      'Hier is niets te importeren — elke titel staat al in je collectie of kon niet worden gevonden.';

  @override
  String importReviewSummaryAlreadyOwned(int count) {
    return 'Al in je collectie: $count';
  }

  @override
  String importReviewSummaryNotFound(int count) {
    return 'Niet gevonden: $count';
  }

  @override
  String importErrorFileTooLarge(int megabytes) {
    return 'Dat bestand is groter dan de limiet van $megabytes MB. Kies een kleiner bestand en probeer het opnieuw.';
  }

  @override
  String get archiveIntakeRejectedTooLarge =>
      'Dat bestand is te groot om te importeren.';

  @override
  String get archiveIntakeRejectedUnreadable =>
      'Het gedeelde bestand kon niet worden gelezen. Probeer het opnieuw, of vraag de afzender het opnieuw te delen.';

  @override
  String get archiveIntakeRejectedEmpty => 'Dat bestand is leeg.';

  @override
  String get danceLinkRefusedNewerVersion =>
      'Deze danscode is gemaakt met een nieuwere versie van Caller’s Compendium. Werk de app bij om de code te openen.';

  @override
  String get danceLinkRefusedDamaged =>
      'Deze danscode is beschadigd of onvolledig en kan niet worden geopend.';

  @override
  String get danceLinkRefusedNotADance =>
      'Deze code is geen danscode van Caller\'s Compendium.';

  @override
  String get danceLinkRefusedNoContent =>
      'Deze danscode bevat geen dansen of programma\'s.';

  @override
  String get importScanDanceCode => 'Danscode scannen';

  @override
  String get importScanNoCode =>
      'Er is geen danscode in de afbeelding gevonden. Zorg dat de hele code erop staat en scherp is.';

  @override
  String get importScanUnreadable => 'De afbeelding kon niet worden gelezen.';

  @override
  String get importDanceCodePicture => 'Danscode uit een afbeelding…';

  @override
  String importScanTooLarge(int limit) {
    return 'Deze afbeelding is groter dan $limit MB en is dus niet gelezen. Kies een kleinere.';
  }

  @override
  String get importScanNoCamera =>
      'Dit apparaat heeft geen camera-app om de foto te maken. Kies in plaats daarvan ‘Danscode uit een afbeelding…’.';

  @override
  String get importScanCameraOff =>
      'Cameratoegang staat uit voor Caller\'s Compendium. Zet hem aan in de app Instellingen om een code te scannen.';

  @override
  String get archiveIntakeRejectedNotArchive =>
      'Dat bestand is geen deelbestand van Caller’s Compendium.';

  @override
  String get archiveIntakeRejectedNoContent =>
      'Dat bestand bevatte geen dansen of programma’s.';

  @override
  String get archiveIntakeRejectedBackup =>
      'Dat bestand is een back-up, geen deelbestand. Om het op dit apparaat te zetten, ga je naar Instellingen ▸ Algemeen en kies je Herstellen vanuit een back-up.';

  @override
  String get importErrorInsecureScheme =>
      'Imports moeten een beveiligde https://-URL gebruiken.';

  @override
  String get importErrorBlockedHost =>
      'Die URL verwijst naar een netwerklocatie waaruit de app niet kan importeren. Controleer de URL en probeer het opnieuw.';

  @override
  String get importErrorInvalidUrl =>
      'Dat ziet er niet uit als een geldige http(s)-URL.';

  @override
  String get importErrorUnsupportedSharedLink =>
      'Die link wordt niet ondersteund voor import.';

  @override
  String get importErrorTooManyRedirects =>
      'Die URL is te vaak doorgestuurd. Open hem in een browser om het uiteindelijke adres te vinden en gebruik dat in plaats daarvan.';

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
    return 'De server stuurde een onverwacht antwoord (code $status). Controleer de URL en probeer het opnieuw.';
  }

  @override
  String get importErrorHttpNotFound =>
      'Op dat adres is niets gevonden. Controleer de URL en probeer het opnieuw.';

  @override
  String get importErrorHttpBusy =>
      'Die server is druk bezig of heeft problemen. Probeer het over een minuut opnieuw.';

  @override
  String get importErrorEmptyResponse =>
      'De URL gaf een leeg antwoord terug. Controleer of de link naar de gegevens verwijst die je wilt importeren en probeer het opnieuw.';

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
  String get importErrorCallersBoxUnsupportedHost =>
      'Die link is geen ondersteunde Caller\'s Box-link. Plak een link van ibiblio.org of www.ibiblio.org onder /contradance/thecallersbox/, of voer het numerieke dans-id in.';

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
  String importErrorCallersBoxTimeout(int seconds) {
    return 'The Caller\'s Box reageerde niet binnen ${seconds}s. Controleer je verbinding en probeer het opnieuw.';
  }

  @override
  String importErrorCallersBoxHttpStatus(int status) {
    return 'The Caller\'s Box stuurde een onverwacht antwoord (code $status). Probeer het over een minuut opnieuw.';
  }

  @override
  String get importErrorCallersBoxHttpNotFound =>
      'The Caller\'s Box heeft geen dans met die id. Controleer het nummer of de link en probeer het opnieuw.';

  @override
  String get importErrorCallersBoxHttpBusy =>
      'The Caller\'s Box is nu druk bezig. Probeer het over een minuut opnieuw.';

  @override
  String get importErrorCallersBoxEmptyPage =>
      'The Caller\'s Box heeft een lege pagina geretourneerd. Probeer het over een minuut opnieuw.';

  @override
  String get importErrorCallersBoxNoDance =>
      'The Caller\'s Box gaf geen importeerbare dans terug. Controleer de id of de link en probeer het opnieuw.';

  @override
  String get importErrorCallersBoxImportFailed =>
      'De Caller\'s Box-dans kon niet worden geïmporteerd.';

  @override
  String get importErrorContraDbEmptyTitle =>
      'Voer een titel of auteur in om ContraDB te doorzoeken.';

  @override
  String get importErrorContraDbUnsupportedFigure =>
      'ContraDB-figuurzoekopdrachten gebruiken een volledige bewegingsnaam, zoals \"box circulate\".';

  @override
  String get importErrorContraDbUnsupportedAdvanced =>
      'ContraDB kan alleen geavanceerde zoekopdrachten uitvoeren die bestaan uit groepen “Alle van”, “Een van” en “Geen van” met “Heeft figuur”- en “Reeks (dan)”-voorwaarden. Verwijder tags, figuursecties, bewegingen zonder exacte tegenhanger in ContraDB en andere voorwaarden om in ContraDB te zoeken.';

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
  String get importErrorContraDbUnsupportedHost =>
      'Die link is niet afkomstig van een ondersteunde ContraDB-host. Plak een link van contradb.com of www.contradb.com, of voer het numerieke dans- of programma-id in.';

  @override
  String get importErrorContraDbUnreachable =>
      'ContraDB kon niet worden bereikt. Controleer je verbinding en probeer het opnieuw.';

  @override
  String importErrorContraDbTimeout(int seconds) {
    return 'ContraDB reageerde niet binnen ${seconds}s. Controleer je verbinding en probeer het opnieuw.';
  }

  @override
  String importErrorContraDbHttpStatus(int status) {
    return 'ContraDB stuurde een onverwacht antwoord (code $status). Probeer het over een minuut opnieuw.';
  }

  @override
  String get importErrorContraDbHttpNotFound =>
      'ContraDB heeft geen dans met die id. Controleer het nummer of de link en probeer het opnieuw.';

  @override
  String get importErrorContraDbHttpBusy =>
      'ContraDB is nu druk bezig. Probeer het over een minuut opnieuw.';

  @override
  String get importErrorContraDbEmptyResponse =>
      'ContraDB heeft een lege response geretourneerd. Probeer het over een minuut opnieuw.';

  @override
  String get importErrorContraDbNoDance =>
      'ContraDB gaf geen importeerbare dans terug. Controleer de id of de link en probeer het opnieuw.';

  @override
  String get importErrorContraDbImportFailed =>
      'De ContraDB-dans kon niet worden geïmporteerd.';

  @override
  String get importIssueGeneric => 'Dit item is met een notitie geïmporteerd.';

  @override
  String get importIssueProgramEmptySlot =>
      'Een leeg slot in een programma is overgeslagen.';

  @override
  String get importIssueProgramDeletedDance =>
      'Een programma verwees naar een dans die in Caller\'s Companion is verwijderd; het slot is weggelaten.';

  @override
  String get importIssueProgramUnresolvedDance =>
      'Een programma verwees naar een dans die niet is geïmporteerd; het slot is als tekstplaatshouder bewaard.';

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
  String get importIssueArchiveNewerSchema =>
      'Dit is gemaakt met een nieuwere versie van Caller\'s Compendium. Werk de app bij voordat je importeert, anders ontbreken mogelijk sommige details.';

  @override
  String importIssueArchiveCustomFieldKeyConflict(String label, String key) {
    return 'Je aangepaste veld “$label” heeft in dit bestand een ander type of andere keuzes, dus de waarden uit het bestand komen in plaats daarvan in het veld met de sleutel “$key”, dat wordt toegevoegd als je het nog niet hebt. Je aangepaste veld blijft ongewijzigd.';
  }

  @override
  String get importIssueArchiveCustomFieldKeyConflictGeneric =>
      'Een aangepast veld in dit bestand kon zijn sleutel niet gebruiken, omdat die al in gebruik is, dus de waarden komen in een veld met een genummerde sleutel.';

  @override
  String get importIssueUsrFileTruncated =>
      'Dit bestand lijkt onvolledig – slechts een deel kon worden gelezen. Kopieer het opnieuw van het origineel en importeer het nogmaals.';

  @override
  String get importIssueUsrFiguresFromDanceRows =>
      'De figuren konden niet uit dit bestand worden gelezen, dus dansen komen mogelijk zonder figuren binnen. Controleer het originele bestand of exporteer het opnieuw vanuit Caller\'s Companion.';

  @override
  String get importIssueUsrPhraseGroupsOrphaned =>
      'Sommige figuren konden niet aan een dans worden gekoppeld en zijn weggelaten. Controleer of je dansen volledig zijn binnengekomen, of kopieer het bestand opnieuw van het origineel.';

  @override
  String get importIssueUsrLinesDropped =>
      'Enkele zeer lange figuurregels zijn weggelaten. De rest van elke dans is geïmporteerd.';

  @override
  String get importIssueUsrSetsSkipped =>
      'Programma\'s konden niet volledig uit dit bestand worden gelezen, dus sommige ontbreken mogelijk of komen zonder hun dansen binnen. Controleer ze na het importeren.';

  @override
  String get importIssueUsrRelatedRowsSkipped =>
      'Enkele gekoppelde dansen in dit bestand waren ongeldig en zijn overgeslagen.';

  @override
  String get importIssueUsrTermsSkipped =>
      'Sommige woordenlijsttermen in dit bestand waren te lang om te bewaren of onleesbaar, en zijn weggelaten.';

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
      'Alleen de gegevens van de dans waren beschikbaar (geen figuren), dus de dans is zonder figuren geïmporteerd.';

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
  String importIssueNewLevel(String level) {
    return 'Het niveau \"$level\" wordt aan je moeilijkheidsgraden toegevoegd.';
  }

  @override
  String get importIssueUnmappedProgression =>
      'Een progressie werd niet herkend; standaard op enkel.';

  @override
  String get importIssueBarsMeterUnstated =>
      'Deze dans telt in maten maar vermeldt geen maatsoort, dus elke maat is als 2 tellen geteld. Controleer de tellingen.';

  @override
  String get importIssueBarsMeterMixed =>
      'Deze dans telt in maten maar vermeldt maatsoorten met verschillende maatlengtes, dus elke maat is als 2 tellen geteld. Controleer de tellingen.';

  @override
  String get importIssueUnmappedType =>
      'Een danstype werd niet herkend; geïmporteerd als contra en bewaard in de notities.';

  @override
  String importIssueUnparsedDate(String field) {
    return 'De datum ($field) kon niet worden gelezen; niet ingesteld.';
  }

  @override
  String get importIssueCcUserFieldKeyAdjusted =>
      'De sleutel van een Caller\'s Companion-veld is aangepast zodat deze geldig en uniek is; de naam blijft behouden.';

  @override
  String get importIssueCcUserFieldLabelMissing =>
      'Een Caller\'s Companion-veld had geen naam, dus er is een algemene naam aan gegeven.';

  @override
  String get importIssueUnparsedRating =>
      'Een beoordeling kon niet worden gelezen; niet beoordeeld.';

  @override
  String get importIssueFiguresUnreadable =>
      'De figuren konden niet worden gelezen; er zijn geen figuren geïmporteerd.';

  @override
  String get importIssueBeatsUnreadable =>
      'Een aantal tellen kon niet worden gelezen; 0 gebruikt.';

  @override
  String get importIssueNoFiguresTable =>
      'De pagina had geen figuren, dus de dans is zonder figuren geïmporteerd.';

  @override
  String get importIssueMoveFallback =>
      'Een figuur kon niet aan een bekende move worden gekoppeld; geïmporteerd als niet-herkende figuur.';

  @override
  String importIssueMoveFallbackAt(int position) {
    return 'Figuur $position kon niet aan een bekende move worden gekoppeld; geïmporteerd als niet-herkende figuur.';
  }

  @override
  String get importIssueParamUnmapped =>
      'Een instelling van een figuur kon niet worden gekoppeld, dus de standaardwaarde is gebruikt.';

  @override
  String importIssueParamValueUnmapped(String param) {
    return 'De instelling $param kon niet worden omgezet, dus de standaardwaarde is gebruikt.';
  }

  @override
  String importIssueParamCountUnmapped(int provided, int mapped) {
    return 'Een figuur had $provided instellingen maar slechts $mapped konden worden gekoppeld; de extra instellingen zijn genegeerd.';
  }

  @override
  String get importIssueRelatedDanceUnresolved =>
      'Een link naar een verwante dans verwees naar een dans die niet is geïmporteerd; de link is overgeslagen.';

  @override
  String get importIssueDuplicateExternalIdInBatch =>
      'De bron vermeldde deze dans twee keer in één import; de herhaalde kopie is weggelaten.';

  @override
  String get importDateFieldComposed => 'gecomponeerd';

  @override
  String get importDateFieldRevised => 'herzien';

  @override
  String get importRecordErrorDiscover =>
      'Dit record kon niet worden gevonden.';

  @override
  String get importRecordErrorEmptyFile =>
      'Dit bestand of deze tekst is leeg. Kies een bestand met inhoud of plak de tekst opnieuw.';

  @override
  String get importRecordErrorNotJson =>
      'Dit is geen JSON-bestand. Kies het .json-bestand dat de bron heeft geëxporteerd, of plak de JSON opnieuw.';

  @override
  String get importRecordErrorNotCompendiumArchive =>
      'Dit is geen deelbestand. Kies een .json- of .ccshare-bestand dat uit deze app is geëxporteerd.';

  @override
  String get importRecordErrorNotCallersBoxDance =>
      'Dit is geen Caller\'s Box-dans. Controleer of je een dans van The Caller\'s Box hebt gekopieerd en probeer het opnieuw.';

  @override
  String get importRecordErrorNotContraDbDance =>
      'Dit is geen ContraDB-dans. Controleer of je een dansenpagina van ContraDB hebt gekopieerd en probeer het opnieuw.';

  @override
  String get importRecordErrorNotUsrDatabase =>
      'Dit is geen Caller\'s Companion-gegevensbestand (.USR). Zoek in Caller\'s Companion het .USR-bestand in de gegevensmap.';

  @override
  String get importRecordErrorFileTooLarge =>
      'Dit bestand is te groot om te importeren. Kies een kleiner bestand of splits het in delen.';

  @override
  String get importRecordErrorNoDanceAtId =>
      'Daar is geen dans gevonden. Controleer de id of link van de Caller\'s Box-dans en probeer het opnieuw.';

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
      'Kies het Caller\'s Companion .USR-bestand om de dansen en programmageschiedenis te migreren. Er wordt niets aan je bibliotheek toegevoegd totdat je controleert en bevestigt.';

  @override
  String get importReviewChooseUsr => 'Kies .USR-bestand…';

  @override
  String get importReviewFileReady => 'Bestand klaar.';

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
  String importReviewWillImportPrograms(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count programma\'s',
      one: '1 programma',
    );
    return 'Bevat ook $_temp0.';
  }

  @override
  String get importReviewCouldNotRead => 'De import kon niet worden gelezen';

  @override
  String get importReviewPlanFailedBody =>
      'Deze import kon niet worden gelezen. Er is niets toegevoegd. Probeer het opnieuw; blijft het gebeuren, dan is het bestand mogelijk beschadigd.';

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
  String get importReviewImportAndEdit => 'Importeren en bewerken';

  @override
  String importReviewStructured(int structured, int total) {
    return '$structured/$total gestructureerd';
  }

  @override
  String get importReviewCustom => 'Niet herkend';

  @override
  String get importReviewOptionNewDance => 'Nieuwe dans';

  @override
  String get importReviewBulkSetAllLabel =>
      'Alle overeenkomende dansen instellen op:';

  @override
  String get importReviewBulkReimport => 'Opnieuw importeren';

  @override
  String get importReviewBulkSkip => 'Overslaan';

  @override
  String get importReviewBulkSkipAmbiguous =>
      'Alle mogelijke overeenkomsten overslaan';

  @override
  String get importReviewOptionSkip => 'Overslaan';

  @override
  String importReviewOptionReimport(String title) {
    return 'Opnieuw importeren in “$title”';
  }

  @override
  String get importReviewReimportTitleAndCredit =>
      'Ook titel en auteur bijwerken';

  @override
  String importReviewReimportTitleAndCreditHint(String title) {
    return 'Neemt de titel en auteursvermelding uit dit bestand over voor “$title”. Je beoordeling, tags, notities en links blijven zoals ze zijn.';
  }

  @override
  String get importReviewOptionDuplicate =>
      'Importeren als nieuwe (dubbele) dans';

  @override
  String get importReviewPossibleMatch =>
      'Mogelijke overeenkomst — kies hoe je wilt importeren:';

  @override
  String get importReviewPossibleTitleMatch =>
      'Misschien een dans die je al hebt, onder een andere titel — kies hoe je wilt importeren:';

  @override
  String importReviewOptionPossibleTitle(String title) {
    return 'Dezelfde dans onder een andere titel – “$title” vervangen door deze versie';
  }

  @override
  String importReviewOptionLink(String title, int percent) {
    return 'Dezelfde dans – “$title” vervangen door deze versie ($percent% overeenkomst)';
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
  String importReviewReimportWarning(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Opnieuw importeren vervangt de figuren, formatie en progressie van $count bestaande dansen en kan hun dansvorm wijzigen. Hun beoordelingen, tags en notities blijven.',
      one:
          'Opnieuw importeren vervangt de figuren, formatie en progressie van 1 bestaande dans en kan de dansvorm wijzigen. De beoordeling, tags en notities blijven.',
    );
    return '$_temp0';
  }

  @override
  String importReviewReimportTitleWarning(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Bij $count daarvan worden ook de titel en auteur uit het bestand overgenomen.',
      one:
          'Bij 1 daarvan worden ook de titel en auteur uit het bestand overgenomen.',
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
  String importReviewSummaryVariation(int count) {
    return 'Geïmporteerd als variatie: $count';
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
  String importReviewSummaryFigures(int count) {
    return 'Figuren toegevoegd aan of bijgewerkt in je woordenlijst: $count';
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
      one: '$count programmanotitie:',
    );
    return '$_temp0';
  }

  @override
  String importReviewNotes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count opmerkingen:',
      one: '1 opmerking:',
    );
    return '$_temp0';
  }

  @override
  String importReviewRecordsFailed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count records konden niet worden geïmporteerd:',
      one: '$count record kon niet worden geïmporteerd:',
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
          '$count record kon niet worden gelezen (de rest kan nog worden geïmporteerd):',
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
      'Die dans kon niet worden geïmporteerd om te bewerken. Probeer het opnieuw.';

  @override
  String get importUsrEnglishTitle => 'Zijn dit Engelse country dances?';

  @override
  String get importUsrEnglishBody =>
      'Caller\'s Companion zet Engelse country dances vaak onder Contra. Bevat dit bestand Engelse dansen, dan worden ze gelezen met Engelse figuren, formaties en maattellingen, en een dans die als Square staat wordt een Engelse dans in een squareset.';

  @override
  String get importUsrEnglishNo => 'Nee, lees hun type';

  @override
  String get importUsrEnglishYes => 'Ja, Engelse dansen';

  @override
  String get importReviewEditOverwriteTitle => 'Bestaande dans nu vervangen?';

  @override
  String importReviewEditOverwriteBody(String title) {
    return 'Importeren om te bewerken vervangt “$title” in je verzameling meteen. Ongedaan maken van de hele import herstelt hem niet.';
  }

  @override
  String get importReviewEditOverwriteConfirm => 'Vervangen';

  @override
  String get importReviewEditReimportTitle =>
      'Nu opnieuw importeren in de bestaande dans?';

  @override
  String importReviewEditReimportBody(String title) {
    return 'Importeren om te bewerken vervangt de figuren, formatie en progressie van “$title” in je verzameling meteen en kan de dansvorm wijzigen. Ongedaan maken van de hele import herstelt ze niet.';
  }

  @override
  String importReviewEditReimportTitleAndCreditBody(String title) {
    return 'Importeren om te bewerken vervangt de figuren, formatie, progressie, titel en auteur van “$title” in je verzameling meteen en kan de dansvorm wijzigen. Ongedaan maken van de hele import herstelt ze niet.';
  }

  @override
  String get importReviewImportError =>
      'De import kon niet worden voltooid. Probeer het opnieuw.';

  @override
  String get importFileNotText =>
      'Dat bestand kon niet worden gelezen: het is geen deelbestand en ook geen tekst die de app kan lezen. Als een andere app het als tekst heeft opgeslagen, sla het daar opnieuw op als UTF-8 en probeer het nog eens.';

  @override
  String get importFileUnreadable =>
      'Dat bestand kon niet worden geopend. Misschien gebruikt een andere app het, of staat het op een schijf die niet is verbonden.';

  @override
  String importReviewVariationTitle(String title) {
    return 'Variatie van \"$title\"?';
  }

  @override
  String importReviewVariationBody(String title) {
    return 'De titel en auteur van deze dans komen overeen met \"$title\", maar de figuren verschillen. Bekijk de verschillen en kies vervolgens hoe je hem wilt importeren.';
  }

  @override
  String importReviewOptionVariation(String title) {
    return 'Importeren als variatie van \"$title\"';
  }

  @override
  String importReviewOptionSameDance(String title) {
    return 'Dezelfde dans – “$title” vervangen door deze versie';
  }

  @override
  String importReviewOptionLinkBack(String title) {
    return 'Ook terugkoppelen naar \"$title\" als gerelateerde dans';
  }

  @override
  String get importReviewVariationAdded => 'Toegevoegd';

  @override
  String get importReviewVariationRemoved => 'Verwijderd';

  @override
  String importReviewVariationMoreDifferences(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count verschillen niet weergegeven',
      one: '1 verschil niet weergegeven',
    );
    return '$_temp0';
  }

  @override
  String get danceEditorDetailsSection => 'Details';

  @override
  String get danceEditorTitleRequiredLabel => 'Titel';

  @override
  String get danceEditorTitleRequired => 'Titel is vereist';

  @override
  String get danceEditorAuthorsLabel => 'Auteurs';

  @override
  String get danceEditorFormLabel => 'Type';

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
  String get danceEditorPhrasesNameThem => 'Frasen benoemen';

  @override
  String get danceEditorPhrasesTitle => 'Frasen';

  @override
  String get danceEditorPhrasesHelp =>
      'Benoem elk deel van de melodie A, B of C, geef het aantal maten en de tellen per maat, en kies of het één of twee keer gespeeld wordt. Een frase die twee keer gespeeld wordt, heet A1 en A2.';

  @override
  String get danceEditorPhrasesAdd => 'Frase toevoegen';

  @override
  String danceEditorPhrasesInvalid(int maxBars, int maxBeats) {
    return 'Geef elke frase 1 tot $maxBars maten en 1 tot $maxBeats tellen per maat. Tot dan houdt de dans zijn laatste geldige frasen, en Opslaan slaat die op.';
  }

  @override
  String danceEditorPhraseBarsLabel(String name) {
    return 'Maten in $name';
  }

  @override
  String danceEditorPhraseBarsRange(int max) {
    return '1 tot $max';
  }

  @override
  String danceEditorPhraseBeatsPerBarLabel(String name) {
    return 'Tellen per maat in $name';
  }

  @override
  String danceEditorPhraseBeatsPerBarRange(int max) {
    return '1 tot $max';
  }

  @override
  String get danceEditorPhraseNameLabel => 'Naam van de frase';

  @override
  String danceEditorPhrasePlaysLabel(String name) {
    return 'Hoe vaak $name speelt';
  }

  @override
  String get danceEditorPhrasePlaysOnce => 'Eén keer';

  @override
  String get danceEditorPhrasePlaysTwice => 'Twee keer';

  @override
  String danceEditorPhraseRemove(String name) {
    return 'Frase $name verwijderen';
  }

  @override
  String get danceEditorPhraseRowsHelp =>
      'Elke rij is een reeks gelijke frasen: hoeveel het er zijn, de maten in elke frase en de tellen in een maat. De fraseopbouw hieronder verandert mee met de rijen.';

  @override
  String get danceEditorPhraseRowsPhrasesLabel => 'Frasen';

  @override
  String get danceEditorPhraseRowsBarsLabel => 'Maten per frase';

  @override
  String get danceEditorPhraseRowsBeatsLabel => 'Tellen per maat';

  @override
  String danceEditorPhraseRowsRange(int max) {
    return '1 tot $max';
  }

  @override
  String get danceEditorPhraseRowsAdd => 'Rij toevoegen';

  @override
  String danceEditorPhraseRowsRemove(int number) {
    return 'Rij $number verwijderen';
  }

  @override
  String danceEditorPhraseRowsRow(int number) {
    return 'Rij $number';
  }

  @override
  String danceEditorPhraseRowsInvalid(int max) {
    return 'Vul in elk veld een geheel getal van 1 tot $max in, in een structuur die niet te lang is. Tot dan blijft de laatste geldige fraseopbouw behouden.';
  }

  @override
  String danceEditorPhraseRowsSummary(String labels, int beats) {
    String _temp0 = intl.Intl.pluralLogic(
      beats,
      locale: localeName,
      other: '$beats tellen',
      one: '1 tel',
    );
    return '$labels · $_temp0';
  }

  @override
  String get danceEditorPhraseRowsDisabledNote =>
      'Deze rijen tonen de laatste geldige fraseopbouw. Corrigeer de fraseopbouw hieronder om ze weer te bewerken.';

  @override
  String get danceEditorFiguresSection => 'Figuren';

  @override
  String get danceEditorFiguresHelp =>
      'Typ een move (bijv. “sw” → swing) en druk op Enter om het toe te voegen met standaardwaarden; tekst die de app niet kan lezen wordt een niet-herkende figuur.';

  @override
  String get danceEditorFiguresHelpFreeText =>
      'Voeg een figuur toe door een hele regel te typen (bijv. “neighbor balance & swing”) en op Enter te drukken. Een regel die je in de beweging van een bestaande figuur typt, vervangt die figuur. Tekst die de app niet kan lezen wordt een niet-herkende figuur.';

  @override
  String get danceEditorNotesSection => 'Notities';

  @override
  String get danceEditorCallingNotesLabel => 'Callnotities';

  @override
  String get danceEditorHookLabel => 'Hook';

  @override
  String get danceEditorHookHint => 'Één zin “waarom deze dans callen”';

  @override
  String get danceEditorHookHelper =>
      'Waarom je deze dans zou callen, in één regel. Dit kan op callingkaarten en in wat je deelt verschijnen.';

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
  String get danceEditorAddWordingOverride =>
      'Woording voor deze dans aanpassen';

  @override
  String get danceEditorGroupTitleLabel => 'Groepstitel (optioneel)';

  @override
  String get danceEditorGroupTitleHelper =>
      'Een naam voor de hele groep, zoals Flutterwheel. Die staat vóór de figuren van de groep, gevolgd door een streepje.';

  @override
  String get danceEditorWordingOverrideLabel =>
      'Woording van de figuur voor deze dans';

  @override
  String get danceEditorWordingOverrideHelper =>
      'Vervangt de weergegeven regel voor deze figuur in deze dans. De canonieke figuur blijft doorzoekbaar.';

  @override
  String get danceEditorResetWordingOverride => 'Standaardwoording gebruiken';

  @override
  String danceEditorWordingOverridePreview(Object text) {
    return 'Voorbeeld: $text';
  }

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
  String get settingsWalkthroughSnippetsEmptyTitle =>
      'Nog geen opgeslagen fragmenten';

  @override
  String get settingsWalkthroughSnippetsEmptyBody =>
      'Voeg beschrijvingen van doorloopstappen toe terwijl je de figuren van een dans bewerkt.';

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
  String get settingsWalkthroughSnippetEditTitle => 'Fragment bewerken';

  @override
  String get danceEditorSetupTitle => 'Makers, formatie en muziek';

  @override
  String get danceEditorMoreDetailsTitle => 'Meer details';

  @override
  String get danceEditorStatusLabel => 'Status';

  @override
  String get danceEditorMixedLevelSubtitle => 'Beslaat de moeilijkheidsschaal';

  @override
  String get danceEditorMixerSubtitle =>
      'Dansers wisselen elke keer van partner';

  @override
  String danceDetailSquareField(String field, String value) {
    return '$field: $value';
  }

  @override
  String get danceEditorSquareKindLabel => 'Soort square';

  @override
  String get squareKindMain => 'Hoofddeel';

  @override
  String get squareKindBreak => 'Break';

  @override
  String get squareKindPatter => 'Patter';

  @override
  String get danceEditorRepeatOrderLabel => 'Herhalingsvolgorde';

  @override
  String get squareRepeatOrderUnstated => 'Niet vermeld';

  @override
  String get squareRepeatOrderHeadsHeadsSidesSides =>
      'Twee keer heads, dan twee keer sides';

  @override
  String get squareRepeatOrderHeadsSidesHeadsSides =>
      'Heads en sides om de beurt';

  @override
  String get squareRepeatOrderAllFour => 'Vier keer, iedereen actief';

  @override
  String get squareRepeatOrderOther => 'Overig';

  @override
  String get danceEditorRepeatOrderOtherLabel =>
      'Herhalingsvolgorde in eigen woorden';

  @override
  String get danceEditorNewPartnerLabel => 'Nieuwe partner';

  @override
  String get squareNewPartnerUnstated => 'Niet vermeld';

  @override
  String get squareNewPartnerNone => 'Partners blijven hetzelfde';

  @override
  String get squareNewPartnerCorner => 'Corner';

  @override
  String squareNewPartnerRightHand(String role) {
    return '$role rechts';
  }

  @override
  String get squareNewPartnerOpposite => 'Opposite';

  @override
  String get squareNewPartnerOther => 'Overig';

  @override
  String get danceEditorNewPartnerOtherLabel =>
      'Nieuwe partner in eigen woorden';

  @override
  String get danceEditorSingingLabel => 'Singing call';

  @override
  String get danceEditorSingingSubtitle => 'Het lied komt onder Deuntjes';

  @override
  String get danceEditorFreeFormLabel => 'Vrije vorm';

  @override
  String get danceEditorFreeFormSubtitle =>
      'Volgt geen frasering: geen frasenamen en geen frasecontrole';

  @override
  String get danceEditorImproperLabel => 'Begint improper';

  @override
  String get danceEditorImproperSubtitle =>
      'Laat uit voor een dans die proper begint.';

  @override
  String get danceEditorComposedLabel => 'Gecomponeerd';

  @override
  String get danceEditorComposedHelper =>
      'Wanneer de dans is gecomponeerd (jaar, of voeg maand/dag toe)';

  @override
  String get danceEditorInterpretedByLabel => 'Geïnterpreteerd door';

  @override
  String get danceEditorInterpretedOnLabel => 'Geïnterpreteerd';

  @override
  String get danceEditorInterpretedOnHelper =>
      'Wanneer de dans is geïnterpreteerd (jaar, of voeg maand/dag toe)';

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
  String get monthFullJanuary => 'Januari';

  @override
  String get monthFullFebruary => 'Februari';

  @override
  String get monthFullMarch => 'Maart';

  @override
  String get monthFullApril => 'April';

  @override
  String get monthFullMay => 'Mei';

  @override
  String get monthFullJune => 'Juni';

  @override
  String get monthFullJuly => 'Juli';

  @override
  String get monthFullAugust => 'Augustus';

  @override
  String get monthFullSeptember => 'September';

  @override
  String get monthFullOctober => 'Oktober';

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
    return 'De figuren komen samen op $actual tellen; de fraseopbouw verwacht $expected.';
  }

  @override
  String validationSequenceExceedsPhrase(int position, int actual, int limit) {
    return 'Een reeks in figuur $position duurt $actual tellen, langer dan de frase waarin hij begint ($limit tellen).';
  }

  @override
  String validationSequenceSpanMismatch(
    int position,
    int actual,
    int expected,
  ) {
    return 'De stappen van de reeks in figuur $position duren $actual tellen; de reeks duurt $expected.';
  }

  @override
  String validationPhraseCountMismatch(String actual, String expected) {
    return 'De figuren duren samen $actual; de fraseopbouw verwacht $expected.';
  }

  @override
  String validationSequenceExceedsPhraseCount(
    int position,
    String actual,
    String limit,
  ) {
    return 'Een reeks in figuur $position duurt $actual, langer dan de frase waarin hij begint ($limit).';
  }

  @override
  String validationSequenceSpanNoRoomCount(
    int position,
    String actual,
    String expected,
  ) {
    return 'De getimede stappen van de reeks in figuur $position duren $actual, zodat er van de $expected niets overblijft voor de rest.';
  }

  @override
  String validationSequenceSpanMismatchCount(
    int position,
    String actual,
    String expected,
  ) {
    return 'De stappen van de reeks in figuur $position duren $actual; de reeks duurt $expected.';
  }

  @override
  String validationSequenceSpanNoRoom(int position, int actual, int expected) {
    return 'De getimede stappen van de reeks in figuur $position duren $actual tellen, zodat er van de $expected niets overblijft voor de rest.';
  }

  @override
  String validationOtherFormFigures(
    int count,
    String danceForm,
    String figureForm,
    String pickerForm,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count figuren komen',
      one: '1 figuur komt',
    );
    return 'Dit is een $danceForm-dans, maar $_temp0 uit $figureForm. Ze blijven zoals ze zijn, maar de figuurkiezer biedt alleen $pickerForm-figuren aan.';
  }

  @override
  String validationFigureCrossesPhrase(int position, String label) {
    return 'Figuur $position loopt door tot voorbij het einde van $label. In een squaredans horen de calls van elke frase die precies te vullen.';
  }

  @override
  String validationIncompleteFigure(int position) {
    return 'Figuur $position is niet compleet, dus Opslaan laat hem weg.';
  }

  @override
  String get validationPhraseInvalid => 'Die fraseopbouw is ongeldig.';

  @override
  String get validationPhraseNamedEnglishOnly =>
      'Frasenamen (A:, B:, C:) zijn alleen voor Engelse dansen.';

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
  String get danceEditorNoteOptionalLabel => 'Notitie (optioneel)';

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
  String get danceEditorTransitiveGroup =>
      'Opnemen in groep gerelateerde dansen';

  @override
  String get danceEditorTransitiveGroupHint =>
      'Alle dansen in deze groep worden met elkaar verbonden.';

  @override
  String danceEditorEditItemTooltip(String item) {
    return '$item bewerken';
  }

  @override
  String get danceEditorTypeToAddOrCreateHint =>
      'Typ om toe te voegen of aan te maken…';

  @override
  String get danceEditorChooseHint => 'Kies…';

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
  String get danceEditorSaveError =>
      'De dans kon niet worden opgeslagen. Je wijzigingen staan er nog. Probeer het opnieuw.';

  @override
  String danceEditorChoreographerDuplicate(String name) {
    return 'Een auteur met de naam “$name” bestaat al. De naam is niet gewijzigd.';
  }

  @override
  String danceEditorChoreographerCreateDuplicate(String name) {
    return 'Er bestaat al een auteur met de naam “$name”. De nieuwe auteur is niet aangemaakt — kies de bestaande.';
  }

  @override
  String get danceEditorFallbackDanceTitle => 'Dans';

  @override
  String get danceEditorUnsavedDraftTitle => 'Niet-opgeslagen concept';

  @override
  String get danceEditorUnsavedDraftMessage =>
      'Je hebt een niet-opgeslagen concept voor deze dans. Wil je het herstellen?';

  @override
  String danceEditorUnsavedNewDanceDraftMessage(String title) {
    return 'Je hebt een niet-opgeslagen concept van een andere nieuwe dans, ‘$title’. Wil je het herstellen in plaats van een nieuwe te beginnen?';
  }

  @override
  String get danceEditorUnsavedNewDanceDraftUntitledMessage =>
      'Je hebt een niet-opgeslagen concept van een andere nieuwe dans, nog zonder titel. Wil je het herstellen in plaats van een nieuwe te beginnen?';

  @override
  String danceEditorUnsavedDraftSavedAt(String when) {
    return 'Concept opgeslagen op $when.';
  }

  @override
  String get danceEditorUnsavedDraftChangedSince =>
      'Deze dans is gewijzigd sinds het concept werd opgeslagen. Als je het concept herstelt, worden die wijzigingen vervangen.';

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
  String get editorDraftNotSaved =>
      'Concept niet opgeslagen – je laatste wijzigingen worden nog niet bewaard';

  @override
  String danceEditorUndoShortcutTooltip(String platform) {
    String _temp0 = intl.Intl.selectLogic(platform, {
      'apple': 'Ongedaan maken (⌘Z)',
      'other': 'Ongedaan maken (Ctrl+Z)',
    });
    return '$_temp0';
  }

  @override
  String danceEditorRedoShortcutTooltip(String platform) {
    String _temp0 = intl.Intl.selectLogic(platform, {
      'apple': 'Opnieuw uitvoeren (⇧⌘Z)',
      'other': 'Opnieuw uitvoeren (Ctrl+Shift+Z)',
    });
    return '$_temp0';
  }

  @override
  String get danceEditorDeleteDanceTooltip => 'Dans verwijderen';

  @override
  String get danceEditorLoadError =>
      'De dans kon niet worden geladen. Er is niets gewijzigd. Probeer het opnieuw.';

  @override
  String get danceEditorChoreographerDetailsTitle => 'Auteurdetails';

  @override
  String get danceEditorChoreographerDetailsIntro =>
      'Deze details zijn gedeeld over elke dans op naam van deze auteur. E-mail, locatie en de markering “overleden” zijn privé — alleen opgeslagen op dit apparaat en nooit gedeeld of geëxporteerd.';

  @override
  String get danceEditorNameRequiredLabel => 'Naam';

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
  String danceEditorFreeTextFiguresAddedConfirmation(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count figuren toegevoegd. Typ nog een figuur of kies Toevoegen afronden als je klaar bent.',
      one:
          '1 figuur toegevoegd. Typ nog een figuur of kies Toevoegen afronden als je klaar bent.',
    );
    return '$_temp0';
  }

  @override
  String get danceEditorFreeTextFinish => 'Toevoegen afronden';

  @override
  String danceEditorFreeTextFinishedAnnouncement(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count figuren toegevoegd.',
      one: '1 figuur toegevoegd.',
    );
    return '$_temp0';
  }

  @override
  String danceEditorFreeTextRowReplacedAnnouncement(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Figuur vervangen door $count figuren.',
      one: 'Figuur vervangen.',
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
  String get danceEditorAddMeanwhile => 'Meanwhile toevoegen';

  @override
  String get danceEditorAddModifier => 'Modifier toevoegen';

  @override
  String get danceEditorAddSequence => 'Reeks toevoegen';

  @override
  String get danceEditorAddFiguresFromText => 'Figuren toevoegen uit tekst…';

  @override
  String get figureTextSheetTitle => 'Figuren toevoegen uit tekst';

  @override
  String get figureTextSheetHelp =>
      'Typ of plak één figuur per regel, bijvoorbeeld “(8) neighbor balance & swing”. Elke regel wordt gelezen zoals het bewegingsveld een getypte regel leest met vrije tekstinvoer aan, ook als die uit staat. Er wordt niets bewaard voordat je de dans bewaart.';

  @override
  String get figureTextSheetHelpDropsLabels =>
      'Typ of plak één figuur per regel, bijvoorbeeld “A1 (8) neighbor balance & swing”. Een fraselabel zoals A1 aan het begin van een regel wordt weggelaten, en elke regel wordt gelezen zoals het bewegingsveld een getypte regel leest met vrije tekstinvoer aan, ook als die uit staat. Er wordt niets bewaard voordat je de dans bewaart.';

  @override
  String get figureTextSheetFieldLabel => 'Figuren, één per regel';

  @override
  String figureTextSheetSummary(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString figuren om toe te voegen',
      one: '1 figuur om toe te voegen',
      zero: 'Nog geen figuren om toe te voegen',
    );
    return '$_temp0';
  }

  @override
  String figureTextSheetUnrecognizedSummary(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$countString regels worden niet herkend. Die worden toegevoegd als niet-herkende figuren met hun tekst, zodat je ze kunt verbeteren.',
      one:
          '1 regel wordt niet herkend. Die wordt toegevoegd als niet-herkende figuur met de tekst, zodat je die kunt verbeteren.',
    );
    return '$_temp0';
  }

  @override
  String figureTextSheetLineFigures(int count) {
    final intl.NumberFormat countNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String countString = countNumberFormat.format(count);

    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$countString figuren',
      one: '1 figuur',
      zero: 'Geen figuur',
    );
    return '$_temp0';
  }

  @override
  String get figureTextSheetLineUnrecognized =>
      'Niet herkend: toegevoegd als niet-herkende figuur';

  @override
  String figureTextSheetTooLong(int max) {
    final intl.NumberFormat maxNumberFormat = intl.NumberFormat.decimalPattern(
      localeName,
    );
    final String maxString = maxNumberFormat.format(max);

    return 'Dit is meer dan $maxString tekens, meer dan in één keer gelezen kan worden. Er wordt niets toegevoegd. Voeg het in delen toe.';
  }

  @override
  String figureTextSheetTooManyLines(int max) {
    final intl.NumberFormat maxNumberFormat = intl.NumberFormat.decimalPattern(
      localeName,
    );
    final String maxString = maxNumberFormat.format(max);

    return 'Dit is meer dan $maxString regels, meer dan in één keer gelezen kan worden. Er wordt niets toegevoegd. Voeg het in delen toe.';
  }

  @override
  String figureTextSheetLineTooLong(int max) {
    final intl.NumberFormat maxNumberFormat = intl.NumberFormat.decimalPattern(
      localeName,
    );
    final String maxString = maxNumberFormat.format(max);

    return 'Een regel is langer dan $maxString tekens, meer dan als één figuurregel gelezen kan worden. Er wordt niets toegevoegd. Verdeel hem over meer regels.';
  }

  @override
  String get figureTextSheetAdd => 'Figuren toevoegen';

  @override
  String get figureTextSheetFromImage => 'Uit een afbeelding…';

  @override
  String get figureTextSheetTakePhoto => 'Foto maken';

  @override
  String get figureTextSheetCameraOff =>
      'Cameratoegang staat uit voor Caller\'s Compendium. Zet hem aan in de app Instellingen om een foto te maken.';

  @override
  String get figureTextSheetReadingImage => 'Afbeelding wordt gelezen…';

  @override
  String get figureTextSheetImageUnavailable =>
      'Dit apparaat kan geen tekst in afbeeldingen lezen in de taal van de app of in het Engels.';

  @override
  String get figureTextSheetImageEnglishOnly =>
      'Dit apparaat leest afbeeldingen in het Engels, niet in de taal van de app.';

  @override
  String figureTextSheetImageTooLarge(int limit) {
    final intl.NumberFormat limitNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String limitString = limitNumberFormat.format(limit);

    return 'Deze afbeelding is groter dan $limitString MB en is daarom niet gelezen. Kies een kleinere.';
  }

  @override
  String get figureTextSheetImageTooManyPixels =>
      'Deze afbeelding heeft te veel pixels om te lezen. Kies een kleinere of snijd hem bij.';

  @override
  String get figureTextSheetImageUnreadable =>
      'Dit bestand is geen afbeelding die dit apparaat kan openen.';

  @override
  String get figureTextSheetImageNoText =>
      'Er is geen tekst gevonden in deze afbeelding.';

  @override
  String get figureTextSheetImageFailed =>
      'De tekst van de afbeelding kon niet worden gelezen.';

  @override
  String get danceEditorPasteAtEndOfFigureList =>
      'Plakken aan het einde van de figurenlijst';

  @override
  String get danceEditorTypeFigureLabel => 'Typ een figuur';

  @override
  String get danceEditorTypeFigureHelper =>
      'bijv. “neighbor balance & swing” of “16 circle left 3/4”. Enter voegt het toe; tekst die de app niet kan lezen wordt bewaard als niet-herkende figuur.';

  @override
  String get danceEditorPasteHere => 'Hier plakken';

  @override
  String get danceEditorEmptyFigureName => 'Lege figuur';

  @override
  String get danceEditorCustomFigureName => 'Niet-herkende figuur';

  @override
  String get danceEditorEmptyFigureSummary => '(leeg — kies een move)';

  @override
  String get danceEditorEmptyFigureSemantic => 'lege figuur, kies een move';

  @override
  String danceEditorCompoundSummary(String name, String values) {
    return '$name: $values';
  }

  @override
  String danceEditorCompoundSemantic(String summary, String unavailable) {
    String _temp0 = intl.Intl.selectLogic(unavailable, {
      'yes': ', kan niet worden uitgevouwen',
      'other': '',
    });
    return '$summary, je figuur$_temp0';
  }

  @override
  String danceEditorCompoundExpandsTo(int count, int beats) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count figuren',
      one: '1 figuur',
    );
    String _temp1 = intl.Intl.pluralLogic(
      beats,
      locale: localeName,
      other: '$beats tellen',
      one: '1 tel',
    );
    return 'Wordt bij het opslaan van de dans $_temp0 ($_temp1).';
  }

  @override
  String get danceEditorCompoundUnavailable =>
      'Je figuur kan niet worden uitgevouwen: hij is verwijderd of gewijzigd, of accepteert deze waarden niet. Bij opslaan blijven alleen zijn naam, tellen, notitie en progressiemarkering behouden.';

  @override
  String get danceEditorIncompleteFigure =>
      'Niet compleet, dus Opslaan laat hem weg.';

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
      other: '$beats tellen',
      one: '1 tel',
    );
    String _temp3 = intl.Intl.selectLogic(hasMove, {
      'yes': ', $_temp2',
      'other': '',
    });
    String _temp4 = intl.Intl.selectLogic(hasNote, {
      'yes': ', notitie: $note',
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
  String commonMoveItemUp(String name) {
    return '$name omhoog verplaatsen';
  }

  @override
  String commonMoveItemDown(String name) {
    return '$name omlaag verplaatsen';
  }

  @override
  String commonMovedItemPosition(String name, int position, int count) {
    return '$name verplaatst naar positie $position van $count';
  }

  @override
  String get danceEditorFigureCutState => 'Geknipt';

  @override
  String get danceEditorCut => 'Knippen';

  @override
  String get danceEditorClearProgression => 'Progressie wissen';

  @override
  String get danceEditorMarkProgression => 'Progressie markeren';

  @override
  String get danceEditorGroupWithNext =>
      'Groeperen met volgende als gelijktijdig';

  @override
  String get danceEditorGroupWithNextAsModifier =>
      'Met volgende groeperen als modifier';

  @override
  String get danceEditorGroupWithNextAsSequence =>
      'Met volgende groeperen als reeks';

  @override
  String get danceEditorConvertToMeanwhile => 'Omzetten naar meanwhile';

  @override
  String get danceEditorConvertToModifier => 'Omzetten naar modifier';

  @override
  String get danceEditorConvertToSequence => 'Omzetten naar reeks';

  @override
  String get danceEditorUngroupMeanwhile => 'Meanwhile-groepering opheffen';

  @override
  String get danceEditorUngroupModifier => 'Modifier-groepering opheffen';

  @override
  String get danceEditorUngroupSequence => 'Reeks-groepering opheffen';

  @override
  String get danceEditorSequenceOptionLabel => 'reeks';

  @override
  String danceEditorSequenceGroupLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Reeks ($count figuren)',
    );
    return '$_temp0';
  }

  @override
  String danceEditorSequenceGroupSemantic(int count, int beats) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count figuren',
      one: '1 figuur',
    );
    String _temp1 = intl.Intl.pluralLogic(
      beats,
      locale: localeName,
      other: '$beats tellen',
      one: '1 tel',
    );
    return 'Reeksgroep, $_temp0 na elkaar, $_temp1 in totaal.';
  }

  @override
  String danceEditorSequenceTotalBeats(int beats) {
    String _temp0 = intl.Intl.pluralLogic(
      beats,
      locale: localeName,
      other: '$beats tellen in totaal',
      one: '1 tel in totaal',
    );
    return '$_temp0';
  }

  @override
  String danceEditorSequenceOverPhrase(int beats, int limit) {
    return 'Deze reeks duurt $beats tellen, langer dan de frase waarin hij begint ($limit tellen).';
  }

  @override
  String danceEditorSequencePhraseFull(int limit) {
    return 'Deze figuren vullen de frase waarin ze beginnen ($limit tellen).';
  }

  @override
  String danceEditorSequenceStepsCapReached(int max) {
    return 'Maximaal $max figuren in een reeks.';
  }

  @override
  String danceEditorSequenceStepLabel(int number) {
    return 'Figuur $number';
  }

  @override
  String danceEditorSequenceStepSemantic(int number, int total) {
    return 'Figuur $number van $total in de reeks.';
  }

  @override
  String get danceEditorAddSequenceStep => 'Volgende figuur toevoegen';

  @override
  String get danceEditorRemoveSequenceStep => 'Deze figuur verwijderen';

  @override
  String danceEditorModifierGroupLabel(num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Modifier ($count figuren)',
    );
    return '$_temp0';
  }

  @override
  String danceEditorModifierGroupSemantic(num beats, num count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count figuren',
      one: '1 figuur',
    );
    String _temp1 = intl.Intl.pluralLogic(
      beats,
      locale: localeName,
      other: '$beats tellen',
      one: '1 tel',
    );
    return 'Modifiergroep, $_temp0, $_temp1.';
  }

  @override
  String get danceEditorAddModifierChild => 'Modifier toevoegen';

  @override
  String get danceEditorModifierCoreLabel => 'Kern';

  @override
  String get danceEditorModifierChildLabel => 'Modifier';

  @override
  String get danceEditorModifierCoreSemantic => 'Kernfiguur in modifiergroep.';

  @override
  String danceEditorModifierChildSemantic(int number, int total) {
    return 'Modifierfiguur $number van $total.';
  }

  @override
  String get danceEditorRemoveModifierCore => 'Kernfiguur verwijderen';

  @override
  String get danceEditorRemoveModifierChild => 'Modifierfiguur verwijderen';

  @override
  String danceEditorMeanwhileGroupLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Gelijktijdig ($count kanten)',
    );
    return '$_temp0';
  }

  @override
  String danceEditorMeanwhileGroupSemantic(int count, int beats) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count gelijktijdige figuren',
      one: '1 gelijktijdige figuur',
    );
    String _temp1 = intl.Intl.pluralLogic(
      beats,
      locale: localeName,
      other: '$beats gedeelde tellen',
      one: '1 gedeelde tel',
    );
    return 'Gelijktijdige groep, $_temp0, $_temp1.';
  }

  @override
  String danceEditorMeanwhileSideLabel(int number) {
    return 'Kant $number';
  }

  @override
  String danceEditorMeanwhileSideSemantic(int number, int total) {
    return 'Kant $number van $total.';
  }

  @override
  String get danceEditorAddMeanwhileSide => 'Kant toevoegen';

  @override
  String get danceEditorRemoveMeanwhileSide => 'Deze kant verwijderen';

  @override
  String danceEditorMeanwhileSidesCapReached(int max) {
    return 'Maximaal $max gelijktijdige figuren.';
  }

  @override
  String danceEditorModifierChildrenCapReached(int max) {
    return 'Maximaal $max geordende modifierfiguren.';
  }

  @override
  String danceEditorUnrecognizedMoveReadOnly(String move) {
    return 'Onbekende move \"$move\": deze versie van de app kent hem niet. Hij wordt alleen-lezen getoond zodat de gegevens behouden blijven, en hij is weer gewoon te bewerken als de move bekend wordt. Je kunt hem nog wel verplaatsen of verwijderen.';
  }

  @override
  String get danceEditorFewerOptions => 'Minder opties';

  @override
  String danceEditorMoreOptions(int count) {
    return 'Meer opties ($count)';
  }

  @override
  String get danceEditorAddNote => 'Notitie toevoegen';

  @override
  String get danceEditorBoldTooltip => 'Vet (*tekst*)';

  @override
  String get danceEditorUnderlineTooltip => 'Onderstrepen (_tekst_)';

  @override
  String get danceEditorCustomFigureTextLabel =>
      'Tekst van niet-herkende figuur';

  @override
  String get danceEditorLingoStylingHelper =>
      'Bewegingsnamen krijgen een gestippelde onderstreping, roltermen een onderstreping en ontmoedigde termen een doorhaling';

  @override
  String danceEditorBeatTotalFreeForm(int total) {
    String _temp0 = intl.Intl.pluralLogic(
      total,
      locale: localeName,
      other: 'Totaal: $total tellen',
      one: 'Totaal: 1 tel',
    );
    return '$_temp0';
  }

  @override
  String danceEditorBeatTotal(int total, int expected) {
    return 'Totaal: $total / $expected tellen';
  }

  @override
  String danceEditorOverByBeats(int beats) {
    return '$beats tellen te veel';
  }

  @override
  String danceEditorUnderByBeats(int beats) {
    return '$beats tellen te weinig';
  }

  @override
  String get danceEditorLessTooltip => 'Minder';

  @override
  String get danceEditorParamNotStated => 'niet opgegeven';

  @override
  String get figureParamFacingStarBackingUp => 'achteruit';

  @override
  String get danceEditorParamChooseValue => 'kies een waarde';

  @override
  String get danceEditorParamClearTooltip => 'Wissen (niet opgegeven)';

  @override
  String danceEditorIntParamRangeError(int min, int max) {
    return 'Voer een geheel getal in van $min tot $max';
  }

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
  String danceEditorFractionAmountValue(String amount) {
    return '$amount×';
  }

  @override
  String get figureParamFractionOther => 'andere hoeveelheid';

  @override
  String get figureParamFractionOtherPick => 'andere hoeveelheid…';

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
  String updateBannerMacosReady(String appName, String version) {
    return '$appName $version is klaar om te installeren.';
  }

  @override
  String get updateBannerDownloadFailed =>
      'De update kon niet worden gedownload. Probeer het opnieuw.';

  @override
  String get updateDownloadFailureDestination =>
      'Er kon geen plek voor het downloaden van de update worden gekozen. Probeer het opnieuw, of gebruik \"Release bekijken\".';

  @override
  String get updateDownloadFailureDestinationOccupied =>
      'Er staat al iets op die locatie. Kies een andere naam of map, of gebruik „Release bekijken”.';

  @override
  String get updateDownloadFailureIncomplete =>
      'De download kon niet worden voltooid en het onvolledige bestand is verwijderd. Probeer het opnieuw, of gebruik \"Release bekijken\".';

  @override
  String get updateDownloadFailureRefusedHost =>
      'De update-download is geweigerd omdat die naar een onverwachte locatie verwees. Gebruik „Release bekijken” om de update handmatig te downloaden.';

  @override
  String get updateDownloadFailureUnreachable =>
      'De update kon niet worden gedownload. Controleer je verbinding en probeer het opnieuw, of gebruik \"Release bekijken\".';

  @override
  String get updateDownloadFailureServerError =>
      'De updateserver kon het bestand niet leveren. Probeer het later opnieuw, of gebruik \"Release bekijken\".';

  @override
  String get updateDownloadFailureDiskFull =>
      'Er is te weinig vrije schijfruimte om de update op te slaan. Maak ruimte vrij en probeer het opnieuw, of gebruik \"Release bekijken\".';

  @override
  String get updateDownloadFailureUnwritable =>
      'De update kon niet worden opgeslagen omdat er niet naar de downloadlocatie kan worden geschreven. Controleer de rechten en probeer het opnieuw, of gebruik \"Release bekijken\".';

  @override
  String get updateDownloadFailureChecksumMismatch =>
      'De gedownloade update is niet door de beveiligingscontrole gekomen en is verwijderd. Probeer het opnieuw of gebruik „Release bekijken” om de update handmatig te downloaden.';

  @override
  String get updateDownloadFailureHandoffFailed =>
      'De update is gedownload en gecontroleerd, maar kon niet automatisch worden geopend. Gebruik \"Release bekijken\" om de installatie af te ronden.';

  @override
  String get updateDownloadFailureInstallFailed =>
      'De update kon niet worden geïnstalleerd. Probeer het opnieuw, of gebruik \"Release bekijken\" om hem handmatig te downloaden.';

  @override
  String get startupIntegrityCheckIncomplete =>
      'Je gegevens konden deze keer niet volledig worden gecontroleerd, dus ze konden niet worden geverifieerd. Blijven er problemen, overweeg dan te herstellen vanuit een back-up. Technische details zijn bewaard in Instellingen ▸ Diagnostics.';

  @override
  String get startupIntegrityCheckFailed =>
      'Je gegevens zijn niet door de veiligheidscontrole gekomen en zijn mogelijk beschadigd. Overweeg te herstellen vanuit een back-up.';

  @override
  String get startupEcdConvertTitle => 'ECD-dansen converteren?';

  @override
  String get startupEcdConvertMessage =>
      'Wil je alle niet-Engelse dansen in je collectie met de tag “ECD” converteren naar Engelse dansen?';

  @override
  String get startupEcdConvertDontShowAgain => 'Dit niet meer tonen';

  @override
  String get startupEcdConvertDecline => 'Niet nu';

  @override
  String get startupEcdConvertConfirm => 'Converteren';

  @override
  String startupEcdConvertSnackbar(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count dansen geconverteerd naar Engels (ECD).',
      one: '1 dans geconverteerd naar Engels (ECD).',
    );
    return '$_temp0';
  }

  @override
  String startupEcdConvertUndoneSnackbar(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count dansen teruggezet.',
      one: '1 dans teruggezet.',
      zero:
          'Er zijn geen dansen teruggezet: van elke dans zijn sindsdien het type of de tags gewijzigd.',
    );
    return '$_temp0';
  }

  @override
  String get appClosingMessage => 'Bezig met sluiten…';

  @override
  String updateBannerAvailable(String appName, String version) {
    return 'Een nieuwere versie van $appName ($version) is beschikbaar.';
  }

  @override
  String updateBannerPortable(String appName, String version) {
    return 'Er is een nieuwere versie van $appName ($version) beschikbaar. Dit is een draagbare kopie, dus download de nieuwe zip of tar.gz van de release.';
  }

  @override
  String retirementNoticeUpcoming(String appName, String version, String date) {
    return 'De ondersteuning voor deze versie van $appName ($version) stopt op $date. Werk vóór die datum bij naar een nieuwere versie.';
  }

  @override
  String retirementNoticePast(String appName, String version, String date) {
    return 'De ondersteuning voor deze versie van $appName ($version) is gestopt op $date. Werk nu bij naar een nieuwere versie.';
  }

  @override
  String get retirementBannerGetUpdate => 'Update ophalen';

  @override
  String get retirementBannerLater => 'Sluiten';

  @override
  String installLocationBannerMessage(String appName) {
    return '$appName is mogelijk niet geïnstalleerd. De app draait vanaf de gedownloade schijfkopie of het archief, of vanaf een tijdelijke alleen-lezen locatie die macOS ervoor heeft aangemaakt. Stop de app, sleep hem in de Finder naar de map Apps of kopieer hem daarheen en open hem daarna vanaf daar. Staat de app al in de map Apps, dan kun je deze melding sluiten.';
  }

  @override
  String get installLocationBannerDismiss => 'Sluiten';

  @override
  String get settingsUpdatesRetirementTitle => 'Einde van ondersteuning';

  @override
  String get updateBannerViewRelease => 'Release bekijken';

  @override
  String get updateBannerDismiss => 'Sluiten';

  @override
  String get updateBannerDownloadInstall => 'Downloaden en installeren';

  @override
  String get updateBannerUpdateRestart => 'Bijwerken en opnieuw starten';

  @override
  String get updateMacosReadyTitle => 'Klaar om bij te werken?';

  @override
  String get updateMacosReadyBody =>
      'De update is geverifieerd. Nu bijwerken opent de schijfkopie en sluit Caller\'s Compendium zodat je de app in Programma\'s kunt vervangen.';

  @override
  String get updateMacosNotNow => 'Niet nu';

  @override
  String get updateMacosUpdateNow => 'Nu bijwerken';

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
  String commandPaletteHighlightedResult(String name, int index, int count) {
    return '$name, $index van $count';
  }

  @override
  String commandPaletteResultCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count resultaten',
      one: '1 resultaat',
    );
    return '$_temp0';
  }

  @override
  String commandPaletteResultCountCapped(int shown, int total) {
    return '$shown van $total resultaten worden getoond';
  }

  @override
  String get collectionPickerSearchLabel => 'Een dans zoeken';

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
  String collectionPickerAddSemantic(String title) {
    return '$title aan programma toevoegen';
  }

  @override
  String collectionPickerAddTooltip(String title) {
    return '$title toevoegen';
  }

  @override
  String collectionPickerAddedTooltip(String title) {
    return '$title toegevoegd';
  }

  @override
  String collectionPickerReplaceSemantic(String title) {
    return 'Vervangen door $title';
  }

  @override
  String collectionPickerReplaceTooltip(String title) {
    return 'Vervangen door $title';
  }

  @override
  String collectionPickerInProgramSemantic(String title) {
    return '$title staat al in het programma';
  }

  @override
  String collectionPickerInProgramCountSemantic(String title, int count) {
    return '$title staat $count keer in het programma';
  }

  @override
  String get userGuideTitle => 'Gebruikersgids';

  @override
  String userGuideMissing(String label) {
    return 'De gids “$label” is nog niet beschikbaar.';
  }

  @override
  String get userGuideLoadError =>
      'De gebruikersgids kon niet worden geladen. Probeer het opnieuw.';

  @override
  String get userGuideOpenOnline => 'De gids online openen';

  @override
  String get userGuideEnglishOnly => 'De gebruikersgids is in het Engels.';

  @override
  String get shorthandMappingsTitle => 'Figuurafkortingen';

  @override
  String get shorthandMappingsIntro =>
      'Afkortingen laten je een korte token typen tijdens vrije tekstinvoer die uitklapt tot één of meer figuren die je hier hebt ingesteld.';

  @override
  String get shorthandMappingsNew => 'Nieuwe afkorting';

  @override
  String get shorthandMappingsEmptyTitle => 'Nog geen afkortingen';

  @override
  String get shorthandMappingsEmptyBody =>
      'Kies Nieuwe afkorting om er een toe te voegen.';

  @override
  String shorthandMappingsLimitReached(int max) {
    return 'Je hebt de limiet van $max afkortingen bereikt. Verwijder er een om een nieuwe toe te voegen.';
  }

  @override
  String get shorthandMappingsActionsTooltip => 'Afkortingsacties';

  @override
  String get shorthandsCompoundTitle => 'Afkortingen voor je eigen figuren';

  @override
  String get shorthandsUserFigureSyncLabel => 'Afkortingen voor nieuwe figuren';

  @override
  String get syncSavedSearchLabel => 'Opgeslagen zoekopdracht';

  @override
  String get shorthandsCompoundIntro =>
      'Als vrije tekstinvoer aan staat, voegt het typen van een van deze afkortingen als hele regel tijdens het bewerken van een dans een van je eigen figuren toe, met de waarden die hier zijn gekozen.';

  @override
  String get shorthandsCompoundNew =>
      'Nieuwe afkorting voor een van je figuren';

  @override
  String get shorthandsCompoundEmpty =>
      'Nog geen afkortingen voor je eigen figuren.';

  @override
  String get shorthandsCompoundUnavailable =>
      'Niet bruikbaar: de figuur is verwijderd of gewijzigd, of accepteert deze waarden niet. Getypt wordt het als een gewone regel gelezen.';

  @override
  String get shorthandsCompoundShadowed =>
      'Niet gebruikt: een figuurafkorting heeft dezelfde tekst.';

  @override
  String get shorthandsUserFigureShadowedByCompound =>
      'Niet gebruikt: een afkorting voor een combinatie heeft dezelfde tekst.';

  @override
  String get compoundShorthandEditorFigureLabel => 'Je figuur';

  @override
  String get compoundShorthandEditorNoFigure => 'Kies een van je figuren.';

  @override
  String get compoundShorthandEditorNoCompounds =>
      'Je hebt nog geen eigen figuren. Voeg er eerst een toe in de Woordenlijst.';

  @override
  String get compoundShorthandEditorInvalidValues =>
      'Deze waarden passen niet bij deze figuur. Kies andere.';

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
  String shorthandEditorTokenShadowsFigure(String token) {
    return 'Als je “$token” typt, wordt er al een figuur ingevoegd. Als je deze afkorting opslaat, voegt typen ervan in plaats daarvan in wat je hier hebt ingesteld. Je kunt hem nog steeds opslaan.';
  }

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
  String shorthandEditorErrorDuplicateHidden(String token) {
    return '“$token” is al een afkorting voor een van je eigen figuren. Die worden hier getoond zolang Eigen figuren aan staat.';
  }

  @override
  String get shorthandEditorErrorNoFigures =>
      'Voeg ten minste één figuur toe om deze afkorting naar uit te klappen.';

  @override
  String get importShorthandSeedTitle => 'Figuurafkortingen aanmaken';

  @override
  String get importShorthandSeedIntro =>
      'De callknoppen in je Caller\'s Companion-bestand kunnen figuurafkortingen worden. Kies degene die je wilt; elke knop wordt uitgebreid tot de getoonde figuren. Er wordt niets toegevoegd voordat je bevestigt, en je bestaande afkortingen worden nooit overschreven.';

  @override
  String get importShorthandSeedAvailableHeader => 'Uit je callknoppen';

  @override
  String get importShorthandSeedUsePrimary => 'Primair';

  @override
  String get importShorthandSeedUseAlt => 'Alternatief';

  @override
  String get importShorthandSeedConflictHeader =>
      'Al gedefinieerd — overgeslagen';

  @override
  String importShorthandSeedConflictNote(String token) {
    return 'Er bestaat al een afkorting met de naam “$token”, dus deze knop is ongewijzigd gelaten.';
  }

  @override
  String get importShorthandSeedSkip => 'Overslaan';

  @override
  String importShorthandSeedConfirm(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count afkortingen aanmaken',
      one: '1 afkorting aanmaken',
      zero: 'Afkortingen aanmaken',
    );
    return '$_temp0';
  }

  @override
  String get importUserFiguresTitle => 'Figuren in dit bestand';

  @override
  String get importUserFiguresIntro =>
      'De dansen die je importeerde gebruiken figuren die de afzender heeft gemaakt. Kies wat je aan je woordenlijst toevoegt. Een dans waarvan je de figuur niet toevoegt, toont de regel waarmee hij werd gedeeld.';

  @override
  String get importUserFiguresNewHeader => 'Nieuw voor jou';

  @override
  String get importUserFiguresDiffersHeader => 'Anders dan die van jou';

  @override
  String get importUserFiguresCopyHeader => 'Toegevoegd als kopie';

  @override
  String get importUserFiguresCopyNote =>
      'Dit apparaat heeft zijn id al eerder gebruikt, dus hij wordt onder een nieuwe toegevoegd. De dansen die je importeerde gebruiken de kopie.';

  @override
  String get importUserFiguresSameHeader => 'Al in je woordenlijst';

  @override
  String get importUserFiguresNameTaken =>
      'Zijn naam is hier al in gebruik, dus je woordenlijst markeert hem met Nieuwe naam nodig.';

  @override
  String get importUserFiguresKeepMine => 'Mijn versie houden';

  @override
  String get importUserFiguresUseTheirs => 'Hun versie gebruiken';

  @override
  String get importUserFiguresSkip => 'Overslaan';

  @override
  String importUserFiguresConfirm(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count wijzigingen toepassen',
      one: '1 wijziging toepassen',
      zero: 'Klaar',
    );
    return '$_temp0';
  }

  @override
  String importUserFiguresFailed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count figuren konden niet in je Woordenlijst worden opgeslagen.',
      one: '1 figuur kon niet in je Woordenlijst worden opgeslagen.',
    );
    return '$_temp0';
  }

  @override
  String importShorthandSeedComplete(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count afkortingen aangemaakt',
      one: '1 afkorting aangemaakt',
    );
    return '$_temp0';
  }

  @override
  String importShorthandSeedUnreadableNote(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count oproepknoppen zijn weggelaten omdat hun tekst niet als figuren te lezen is.',
      one:
          '1 oproepknop is weggelaten omdat de tekst niet als figuren te lezen is.',
    );
    return '$_temp0';
  }

  @override
  String importShorthandSeedRoomHint(int free, int max) {
    String _temp0 = intl.Intl.pluralLogic(
      free,
      locale: localeName,
      other:
          'Er is plek voor nog $free afkortingen (limiet $max). Alleen de eerste $free die geselecteerd blijven, worden toegevoegd.',
      one:
          'Er is plek voor nog 1 afkorting (limiet $max). Alleen de eerste die geselecteerd blijft, wordt toegevoegd.',
      zero: 'Je lijst met afkortingen is vol ($max), dus er kan niets bij.',
    );
    return '$_temp0';
  }

  @override
  String importShorthandSeedLimitSkipped(int skipped, int max) {
    String _temp0 = intl.Intl.pluralLogic(
      skipped,
      locale: localeName,
      other:
          '$skipped afkortingen zijn niet toegevoegd omdat de lijst vol is (limiet $max). Verwijder er een om een nieuwe toe te voegen.',
      one:
          '1 afkorting is niet toegevoegd omdat de lijst vol is (limiet $max). Verwijder er een om een nieuwe toe te voegen.',
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
  String get reparseConfirmTitle => 'Niet-herkende figuren upgraden?';

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
    return 'Dit controleert $_temp0 in $_temp1 opnieuw. Je tags, beoordelingen, notities en alles anders van elke dans blijven exact zoals ze zijn. Alleen figuren die nu een bekende move herkennen worden vervangen.';
  }

  @override
  String get reparseConfirmUpgrade => 'Upgraden';

  @override
  String get reparseFailed =>
      'De figuren konden niet worden bijgewerkt. Probeer het opnieuw.';

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
    return 'Niet-herkende figuren geüpgraded in $_temp0.';
  }

  @override
  String get reparseScreenTitle => 'Niet-herkende figuren opnieuw controleren';

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
    return 'Verbeterde figuurherkenning kan $_temp0 in $_temp1 upgraden. Bekijk hieronder, bevestig dan — er wijzigt niets voordat je dat doet, en al je tags, beoordelingen en notities blijven bewaard.';
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
      'Geen van je niet-herkende figuren uit imports kan momenteel worden herkend als bekende move. Kijk later terug nadat een toekomstige update de figuurherkenning verbetert.';

  @override
  String get reparseErrorTitle => 'Je figuren konden niet worden gecontroleerd';

  @override
  String get reparseErrorBody =>
      'Je collectie kon niet worden gescand. Er is niets gewijzigd. Probeer het opnieuw.';

  @override
  String get ecdMigrationScreenTitle => 'Engelse dansen omzetten';

  @override
  String ecdMigrationIntro(int danceCount) {
    String _temp0 = intl.Intl.pluralLogic(
      danceCount,
      locale: localeName,
      other: '$danceCount Engelse dansen gebruiken',
      one: '1 Engelse dans gebruikt',
    );
    return '$_temp0 nog contra-moves, niet-herkende figuren of een contra-formatie. Kies de dansen om om te zetten en bevestig dan. Een move zonder duidelijke Engelse betekenis blijft zoals hij is.';
  }

  @override
  String ecdMigrationPreviewMoves(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count moves om te zetten',
      one: '1 move om te zetten',
    );
    return '$_temp0';
  }

  @override
  String ecdMigrationPreviewLines(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count niet-herkende figuren nu gelezen',
      one: '1 niet-herkende figuur nu gelezen',
    );
    return '$_temp0';
  }

  @override
  String get ecdMigrationPreviewShape => 'Engelse formatie';

  @override
  String ecdMigrationConvertButton(int danceCount) {
    String _temp0 = intl.Intl.pluralLogic(
      danceCount,
      locale: localeName,
      other: '$danceCount dansen omzetten',
      one: '1 dans omzetten',
    );
    return '$_temp0';
  }

  @override
  String get ecdMigrationConfirmTitle => 'Deze Engelse dansen omzetten?';

  @override
  String ecdMigrationConfirmBody(int danceCount) {
    String _temp0 = intl.Intl.pluralLogic(
      danceCount,
      locale: localeName,
      other: '$danceCount dansen',
      one: '1 dans',
    );
    return 'Dit wijzigt de figuren en formatie van $_temp0. Tags, beoordelingen, notities en al het andere blijven behouden. Dit kan niet ongedaan worden gemaakt, dus maak eventueel eerst een back-up.';
  }

  @override
  String get ecdMigrationConfirmAction => 'Omzetten';

  @override
  String ecdMigrationDoneSnack(int danceCount) {
    String _temp0 = intl.Intl.pluralLogic(
      danceCount,
      locale: localeName,
      other: '$danceCount dansen omgezet.',
      one: '1 dans omgezet.',
    );
    return '$_temp0';
  }

  @override
  String get ecdMigrationNothingSnack => 'Niets om om te zetten.';

  @override
  String get ecdMigrationFailed =>
      'De dansen konden niet worden omgezet. Er is niets gewijzigd. Probeer het opnieuw.';

  @override
  String get ecdMigrationEmptyTitle => 'Niets om om te zetten';

  @override
  String get ecdMigrationEmptyBody =>
      'Geen van je Engelse country dances bevat iets dat kan worden omgezet. Een beweging zonder duidelijke Engelse betekenis blijft zoals hij is.';

  @override
  String get ecdMigrationErrorTitle =>
      'Je Engelse dansen konden niet worden gecontroleerd';

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
  String customFieldsDeleteFailed(String label) {
    return '“$label” kon niet worden verwijderd. Probeer het opnieuw.';
  }

  @override
  String customFieldsKeyDuplicate(String key) {
    return 'Een veld met de sleutel “$key” bestaat al. De sleutel is niet gewijzigd.';
  }

  @override
  String customFieldsKeyDuplicateNew(String key) {
    return 'Een veld met de sleutel “$key” bestaat al. Het nieuwe veld is niet aangemaakt.';
  }

  @override
  String get customFieldsTitle => 'Aangepaste velden';

  @override
  String get customFieldsNewField => 'Nieuw veld';

  @override
  String get customFieldsLoadError =>
      'Eigen velden konden niet worden geladen. Er is niets gewijzigd. Probeer het opnieuw.';

  @override
  String get customFieldsEmptyTitle => 'Nog geen aangepaste velden';

  @override
  String get customFieldsEmptyBody =>
      'Kies Nieuw veld om er een toe te voegen.';

  @override
  String get customFieldsFlagInList => 'In lijst';

  @override
  String get customFieldsSearchable => 'Doorzoekbaar';

  @override
  String get customFieldsTypeText => 'Tekst';

  @override
  String get customFieldsTypeNumber => 'Getal';

  @override
  String get customFieldsTypeBoolean => 'Ja/nee';

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
  String get customFieldsLabelLabel => 'Label';

  @override
  String get customFieldsLabelRequired => 'Label is vereist';

  @override
  String get customFieldsKeyLabel => 'Sleutel';

  @override
  String get customFieldsKeyHelper =>
      'Een korte id voor dit veld. Alleen letters, cijfers en underscores; moet beginnen met een letter of underscore. Kan niet meer worden gewijzigd zodra het veld bij dansen wordt gebruikt.';

  @override
  String get customFieldsKeyLocked =>
      'Sleutel is vergrendeld — veld is in gebruik op dansen';

  @override
  String get customFieldsKeyRequired => 'Sleutel is vereist';

  @override
  String get customFieldsKeyInvalid =>
      'Sleutel moet beginnen met een letter of underscore en alleen letters, cijfers en underscores bevatten';

  @override
  String get customFieldsSaveFailed =>
      'Het veld kon niet worden opgeslagen. Controleer de sleutel en keuzes en probeer het opnieuw.';

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
      'Bied dit veld aan in het paneel Filters en laat de zoekbalk de waarden ervan vinden';

  @override
  String get customFieldsSearchableSubtitleYesNo =>
      'Bied dit veld aan in het paneel Filters';

  @override
  String get customFieldsChoicesLabel => 'Keuzes';

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
  String get customFieldsShareable => 'Opnemen bij delen';

  @override
  String get customFieldsShareableSubtitle =>
      'De waarden van dit veld gaan mee met je collectie wanneer je die deelt; back-ups bevatten ze altijd';

  @override
  String get customFieldsSharingNoticeTitle =>
      'Aangepaste velden gaan mee met je collectie';

  @override
  String get customFieldsSharingNoticeBody =>
      'De inhoud van elk aangepast veld dat je aanmaakt, wordt opgenomen in je back-ups. Zet \"Opnemen bij delen\" uit in de instellingen van het veld wanneer je je collectie deelt om het veld privé te houden.';

  @override
  String get customFieldsSharingNoticeOk => 'Begrepen';

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
  String get dialectEditorMoveSubHint =>
      'substitutie (gebruik %S voor handedness)';

  @override
  String get dialectEditorAddMove => 'Een move toevoegen…';

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
  String get dialectEditorDiscouragedResetTitle =>
      'Standaard afgeraden termen herstellen?';

  @override
  String get dialectEditorDiscouragedResetBody =>
      'Je huidige afgeraden termen worden vervangen door de standaardtermen.';

  @override
  String get dialectEditorExitTitle => 'Wijzigingen opslaan?';

  @override
  String get dialectEditorExitBody =>
      'Je hebt niet-opgeslagen wijzigingen in dit dialect.';

  @override
  String get dialectEditorSaveAndExit => 'Opslaan en afsluiten';

  @override
  String get dialectEditorExitWithoutSaving => 'Afsluiten zonder opslaan';

  @override
  String get dialectEditorPreviewHelp =>
      'Voorbeeldfiguren weergegeven met dit dialect. Wordt bijgewerkt tijdens het bewerken.';

  @override
  String get recentlyDeletedTitle => 'Onlangs verwijderd';

  @override
  String get recentlyDeletedLoadError =>
      'Je onlangs verwijderde items konden niet worden geladen. Er is niets verwijderd. Probeer het opnieuw.';

  @override
  String get recentlyDeletedDeleteTitle => 'Permanent verwijderen?';

  @override
  String recentlyDeletedDeleteBody(String title) {
    return '“$title” wordt nu verwijderd.';
  }

  @override
  String get recentlyDeletedDeleteConfirm => 'Permanent verwijderen';

  @override
  String recentlyDeletedDeletedSnack(String title) {
    return '“$title” permanent verwijderd.';
  }

  @override
  String recentlyDeletedDeletedSyncedSnack(String title) {
    return '“$title” permanent verwijderd. Er blijft een kleine verwijderingsnotitie bewaard zodat je andere apparaten het ook verwijderen.';
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
      'Geen onlangs verwijderde dansen. Verwijderde dansen worden hier bewaard totdat je ze verwijdert.';

  @override
  String get recentlyDeletedEmptyTitle => 'Niets verwijderd';

  @override
  String recentlyDeletedEmptyDancesRetention(int days) {
    return 'Geen onlangs verwijderde dansen. Verwijderde dansen verschijnen hier voor $days dagen voordat ze worden verwijderd.';
  }

  @override
  String get recentlyDeletedEmptyProgramsKept =>
      'Geen onlangs verwijderde programma’s. Verwijderde programma’s worden hier bewaard totdat je ze verwijdert.';

  @override
  String recentlyDeletedEmptyProgramsRetention(int days) {
    return 'Geen onlangs verwijderde programma’s. Verwijderde programma’s verschijnen hier voor $days dagen voordat ze worden verwijderd.';
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
  String get venueLoadError =>
      'Locaties konden niet worden geladen. Er is niets gewijzigd. Probeer het opnieuw.';

  @override
  String get venueManagerTitle => 'Locaties';

  @override
  String get venueManagerSearchHint => 'Locaties zoeken…';

  @override
  String get venueManagerClearSearchTooltip => 'Zoekopdracht wissen';

  @override
  String get venueManagerEmptyBody =>
      'Voeg er hier een toe, of vanuit een programma wanneer herbruikbare locaties zijn ingeschakeld.';

  @override
  String get venueManagerEmptyTitle => 'Nog geen locaties';

  @override
  String get venueManagerNoMatches =>
      'Geen locaties komen overeen met je zoekopdracht.';

  @override
  String get venueLinkOfferTitle => 'Eerdere programma\'s koppelen?';

  @override
  String get venueLinkOfferBody =>
      'Bij sommige programma\'s is een locatie als tekst ingevoerd die overeenkomt met een locatiegegeven. Door ze te koppelen telt de oproephistorie ze als één locatie. De ingevoerde tekst blijft bewaard.';

  @override
  String venueLinkOfferRow(String name, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count programma\'s',
      one: '1 programma',
    );
    return '“$name”: $_temp0';
  }

  @override
  String get venueLinkOfferConfirm => 'Koppelen';

  @override
  String get venueLinkOfferDecline => 'Niet nu';

  @override
  String venueLinkOfferDone(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count programma\'s gekoppeld.',
      one: '1 programma gekoppeld.',
    );
    return '$_temp0';
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
  String get venueEditorSaveError =>
      'De locatie kon niet worden opgeslagen. Je wijzigingen staan er nog. Probeer het opnieuw.';

  @override
  String get venueEditorSharedNote =>
      'Een locatie is gedeeld over elk programma dat hier wordt gehouden, dus bewerkingen van het adres, contacten of schema zijn zichtbaar op al die programma’s.';

  @override
  String get venueEditorPartialSyncHint =>
      'De adres- en contactvelden van deze locatie hieronder blijven op dit apparaat — Apparaatsynchronisatie draagt ze niet over naar je andere apparaten, dus daar kunnen ze leeg zijn. Het veld Notities synchroniseert wel, dus vermijd daar contactgegevens als je die liever privé op dit apparaat houdt.';

  @override
  String get venueEditorNameLabel => 'Naam';

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

  @override
  String get danceReimport => 'Choreografie opnieuw importeren';

  @override
  String get danceReimportJson => 'Caller’s Compendium JSON';

  @override
  String get danceReimportLinkOrId => 'Link of id';

  @override
  String get danceReimportNoResults =>
      'Geen overeenkomende dansen gevonden. Probeer een link of id, kies een andere bron of probeer het later opnieuw.';

  @override
  String get danceReimportFiguresUnavailable =>
      'Die bron heeft de figuren van deze dans niet geleverd, dus je choreografie kan niet worden bijgewerkt. Je dans is niet gewijzigd.';

  @override
  String get danceReimportChooseResult =>
      'Kies de dans om opnieuw te importeren';

  @override
  String get danceReimportProgramArchive =>
      'Dit bestand bevat een programma en kan niet worden gebruikt om één dans opnieuw te importeren.';

  @override
  String get danceReimportInvalidJson =>
      'Kies een geldig bestand met precies één dans.';

  @override
  String get danceReimportSourceFailed =>
      'Er kon geen dans van die bron worden geladen. Je dans is niet gewijzigd. Probeer het opnieuw.';

  @override
  String get danceReimportApplyFailed =>
      'De dans kon niet vanuit die bron worden bijgewerkt. Je dans is niet gewijzigd. Probeer het opnieuw.';

  @override
  String get danceReimported => 'Choreografie bijgewerkt.';

  @override
  String get danceReimportTargetMissing =>
      'Deze dans is verwijderd voordat deze kon worden bijgewerkt.';

  @override
  String get danceReimportTargetChanged =>
      'Deze dans is gewijzigd voordat deze kon worden bijgewerkt. Controleer de dans en probeer het opnieuw.';

  @override
  String get publishedCollectionsTitle => 'Gepubliceerde collecties';

  @override
  String get importSourceLabelPublishedCollection => 'Gepubliceerde collectie';

  @override
  String get publishedCollectionsDescription =>
      'Importeer ondertekende, onveranderlijke danscollecties uit Compendium Analect.';

  @override
  String get publishedCollectionsLoading => 'Gepubliceerde collecties laden…';

  @override
  String get publishedCollectionsUnavailable =>
      'Gepubliceerde collecties zijn tijdelijk niet beschikbaar.';

  @override
  String get publishedCollectionsUnverified =>
      'De gepubliceerde collecties konden niet worden geverifieerd, dus er is niets geladen. Blijft dit gebeuren, werk dan de app bij.';

  @override
  String get publishedCollectionsOffline =>
      'De gepubliceerde collecties zijn niet bereikbaar. Controleer je verbinding en probeer het opnieuw.';

  @override
  String get publishedCollectionsNeedsNewerApp =>
      'Deze gepubliceerde collecties hebben een nieuwere appversie nodig. Werk de app bij om ze te zien.';

  @override
  String get publishedCollectionImport => 'Collectie importeren';

  @override
  String get publishedCollectionUnsupported =>
      'Voor deze collectie is een nieuwere appversie nodig.';

  @override
  String publishedCollectionImportedVersion(String version) {
    return 'Geïmporteerde versie: $version';
  }

  @override
  String publishedCollectionHeldCount(int held, int total) {
    return '$held van $total dansen in bezit';
  }

  @override
  String publishedCollectionDetails(String id, String version, int count) {
    return '$id · $version · $count dansen';
  }

  @override
  String publishedCollectionPermission(
    String license,
    String grantor,
    String holder,
    String basis,
    String fields,
  ) {
    return 'Licentie: $license\nToestemming: $grantor verleent $holder toestemming op basis van $basis. Gedekte velden: $fields';
  }

  @override
  String get publishedCollectionNoCoveredFields => 'geen';

  @override
  String publishedCollectionSupersedes(String version) {
    return 'Vervangt versie $version';
  }

  @override
  String get dialectEditorSectionMoveWordings =>
      'Sjablonen voor bewegingsformuleringen';

  @override
  String get dialectEditorMoveWordingsHelp =>
      'Optionele sjablonen voor alleen de weergave vervangen de normale zin van een beweging. Canonieke tekst en zoeken blijven ongewijzigd.';

  @override
  String get dialectEditorMoveWordingsConditionalHelp =>
      'Voorwaardelijke bewegingssjablonen worden gekozen op basis van de parameters van de figuur. Vul elke vermelde invulplaats in; onvolledige voorwaardelijke sjablonen worden genegeerd.';

  @override
  String dialectEditorMoveWordingsForceHelp(String example) {
    return 'Sommige velden worden weggelaten als ze niets toevoegen, zoals de hand bij een chain wanneer de rol die al aangeeft. Zet een ! voor een veld, zoals $example, om het altijd te tonen.';
  }

  @override
  String dialectEditorMoveWordingsConditionalLabel(String move) {
    return '$move (voorwaardelijk)';
  }

  @override
  String get dialectEditorMoveWordingBranchInOnly => 'Alleen in';

  @override
  String get dialectEditorMoveWordingBranchOutOnly => 'Alleen uit';

  @override
  String get dialectEditorMoveWordingBranchInAndOut => 'In en uit';

  @override
  String get dialectEditorMoveWordingBranchNeither => 'Geen van beide';

  @override
  String get dialectEditorMoveWordingBranchOrdinary => 'Gewoon';

  @override
  String get dialectEditorMoveWordingBranchSingleFile => 'Enkele rij';

  @override
  String get dialectEditorAddMoveWording =>
      'Een sjabloon voor bewegingsformulering toevoegen…';

  @override
  String get dialectEditorMoveWordingLabel => 'Weergavesjabloon';

  @override
  String dialectEditorMoveWordingSlots(String slots) {
    return 'Beschikbare plaatshouders: $slots';
  }

  @override
  String get dialectEditorMoveWordingInvalid =>
      'Dit sjabloon is ongeldig; daarom wordt de normale formulering gebruikt.';

  @override
  String dialectEditorMoveWordingSaveError(String figures) {
    return 'Los ongeldige sjablonen voor bewegingsformuleringen op voordat je opslaat: $figures';
  }

  @override
  String dialectEditorMoveWordingUnknownSlots(String slots) {
    return 'Onbekende plaatshouders zijn leeg: $slots';
  }

  @override
  String dialectEditorMoveWordingMissingSlots(String slots) {
    return 'Deze template laat beschikbare slots weg: $slots';
  }

  @override
  String get dialectEditorUserFigureGone =>
      'Een van je figuren, niet op dit apparaat';

  @override
  String get dialectEditorUserFigureNameHint =>
      'Hoe dit dialect je figuur noemt';

  @override
  String get dialectEditorUserFigureNameSide =>
      'Je figuur heeft geen kant die %S kan invullen, dus behoudt die zijn eigen naam.';

  @override
  String dialectEditorUserFigureWordingUnknownSlots(String slots) {
    return 'Je figuur heeft geen $slots, dus wordt die met zijn eigen bewoording gelezen tot je ze verwijdert.';
  }

  @override
  String dialectEditorMoveWordingOptionalSlots(String slots) {
    return 'Deze template laat optionele slots weg: $slots';
  }

  @override
  String dialectEditorMoveWordingPreview(String preview) {
    return 'Voorbeeld: $preview';
  }

  @override
  String get dialectEditorMoveWordingsReset =>
      'Sjablonen voor bewegingsformuleringen resetten';

  @override
  String get dialectEditorMoveWordingsResetTitle =>
      'Sjablonen voor bewegingsformuleringen resetten?';

  @override
  String get dialectEditorMoveWordingsResetBody =>
      'Hiermee verwijder je al je aangepaste sjablonen voor bewegingsformuleringen.';

  @override
  String get dialectEditorMoveWordingConfirmTitle =>
      'Onvolledige woordingssjablonen opslaan?';

  @override
  String dialectEditorMoveWordingConfirmBody(String figures) {
    return 'Deze sjablonen laten beschikbare slots weg en kunnen figuurdetails verbergen:\n$figures\n\nToch opslaan?';
  }

  @override
  String get settingsExperimentalShowCustomFiguresTitle => 'Eigen figuren';

  @override
  String get settingsExperimentalShowCustomFiguresSubtitle =>
      'Laat je je eigen figuren toevoegen en bewerken, en biedt ze aan wanneer je een dans bewerkt. De woordenlijst is hiervoor niet nodig. Als je dit uitzet, worden ze verborgen, niet verwijderd.';

  @override
  String get settingsExperimentalCustomFiguresManageTitle => 'Eigen figuren';

  @override
  String get settingsExperimentalCustomFiguresManageSubtitle =>
      'Voeg je eigen figuren toe, bewerk of verwijder ze.';

  @override
  String get customFiguresTitle => 'Eigen figuren';

  @override
  String get customFiguresEmpty =>
      'Je hebt nog geen eigen figuren gemaakt. Kies + om er een toe te voegen.';

  @override
  String get customFiguresEmptyTitle => 'Nog geen eigen figuren';

  @override
  String get glossaryAddCustomFigure => 'Eigen figuur toevoegen';

  @override
  String get customFiguresNewFigure => 'Eigen figuur toevoegen';

  @override
  String get glossaryCustomMarker => 'Eigen';

  @override
  String get glossaryCustomNeedsRepair => 'Reparatie nodig';

  @override
  String get glossaryCustomNeedsRepairBody =>
      'Deze figuur kan zo niet worden gebruikt: een van de figuren of parameters erin is niet meer geldig. Bewerk de figuur om dit te herstellen.';

  @override
  String get glossaryCustomRenameNeeded => 'Nieuwe naam nodig';

  @override
  String get glossaryCustomRenameNeededBody =>
      'Een andere figuur of afkorting heeft al deze naam. Geef deze een andere naam, zodat je ze uit elkaar kunt houden.';

  @override
  String get glossaryCustomUnsupported => 'Nieuwere versie';

  @override
  String get glossaryCustomUnsupportedBody =>
      'Dit item is gemaakt met een nieuwere versie van de app. Werk de app op dit apparaat bij om het te bewerken of te gebruiken.';

  @override
  String glossaryCustomExpandsTo(int beats) {
    return 'Wordt uitgevouwen tot ($beats tellen)';
  }

  @override
  String get glossaryCustomGone => 'Deze figuur is verwijderd.';

  @override
  String glossaryCustomDeleteTitle(String name) {
    return '‘$name’ verwijderen?';
  }

  @override
  String get glossaryCustomDeleteBody =>
      'Ze wordt uit je woordenlijst verwijderd. Dansen die je er al mee hebt opgeslagen, behouden hun figuren.';

  @override
  String get glossaryNotes => 'Jouw notities';

  @override
  String get glossaryNotesEmpty => 'Nog geen notities.';

  @override
  String get glossaryNotesAdd => 'Notities toevoegen';

  @override
  String get glossaryNotesEdit => 'Notities bewerken';

  @override
  String get glossaryNotesEditTitle => 'Jouw notities';

  @override
  String get glossaryNotesHint =>
      'Hoe je de figuur callt, waar je op moet letten…';

  @override
  String get glossaryNotesTooLong =>
      'Je notities zijn te lang om op te slaan. Maak ze korter en probeer het opnieuw.';

  @override
  String get glossaryOverBudget =>
      'Je woordenlijst heeft de maximale grootte bereikt, dus dit kon niet worden opgeslagen. Maak ruimte door andere figuren of notities te verwijderen of in te korten en probeer het opnieuw.';

  @override
  String get compoundEditorTitleNew => 'Eigen figuur toevoegen';

  @override
  String get compoundEditorTitleEdit => 'Figuur bewerken';

  @override
  String get compoundEditorName => 'Naam';

  @override
  String get compoundEditorDefinition => 'Definitie';

  @override
  String get compoundEditorDefinitionHelper =>
      'Eén zin, getoond in de woordenlijst.';

  @override
  String get compoundEditorDescription => 'Meer details';

  @override
  String get compoundEditorKeywords => 'Andere namen';

  @override
  String get compoundEditorKeywordsHelper =>
      'Optioneel. Scheid ze met komma’s.';

  @override
  String get compoundEditorNotes => 'Notities';

  @override
  String get compoundEditorOptional => 'Optioneel.';

  @override
  String get compoundEditorFieldRequired => 'Verplicht';

  @override
  String get compoundEditorRequired =>
      'Geef de figuur een naam en een definitie.';

  @override
  String get compoundEditorParams => 'Parameters';

  @override
  String get compoundEditorParamsHelp =>
      'Wat je kiest telkens als je de figuur gebruikt, zoals wie en welke hand.';

  @override
  String get compoundEditorParamName => 'Parameternaam';

  @override
  String get compoundEditorParamKind => 'Type';

  @override
  String get compoundEditorAddParam => 'Parameter toevoegen';

  @override
  String get compoundEditorRemoveParam => 'Parameter verwijderen';

  @override
  String get compoundEditorParamNames => 'Geef elke parameter een andere naam.';

  @override
  String get compoundEditorFigures => 'Figuren';

  @override
  String get compoundEditorFiguresHelp =>
      'De figuren waarnaar ze uitklapt wanneer je een dans opslaat, op volgorde.';

  @override
  String get compoundEditorBindings => 'Ingevuld door parameters';

  @override
  String get compoundEditorBindingsHelp =>
      'Kies per figuur welke instellingen uit een parameter komen. De rest blijft zoals je die hebt ingesteld.';

  @override
  String compoundEditorFigureN(int number, String figure) {
    return 'Figuur $number: $figure';
  }

  @override
  String get compoundBindingFixed => 'Zoals ingesteld in de figuur';

  @override
  String compoundBindingOpposite(String param) {
    return 'Tegenovergestelde van $param';
  }

  @override
  String compoundBindingUnavailable(String option, String reason) {
    return '$option (niet beschikbaar: $reason)';
  }

  @override
  String get compoundBindingNoName => 'heeft nog geen naam';

  @override
  String compoundBindingWrongKind(String paramKind, String slotKind) {
    return 'is van het type $paramKind; deze instelling is van het type $slotKind';
  }

  @override
  String get compoundBindingNoOpposite =>
      'dit type heeft geen tegenovergestelde';

  @override
  String get compoundBindingNoSharedValues =>
      'geen waarde past bij alle instellingen die hij invult';

  @override
  String compoundEditorNameTaken(String name) {
    return '‘$name’ is al de naam van een figuur of afkorting. Kies een andere naam.';
  }

  @override
  String compoundEditorNameTakenHidden(String name) {
    return '‘$name’ is al de naam van een van je eigen figuren. Die staan in de woordenlijst wanneer Eigen figuren aan staat. Kies een andere naam.';
  }

  @override
  String compoundEditorNameTakenHiddenTerm(String name) {
    return '“$name” is al de naam van een van je eigen termen. Die staan in de woordenlijst zolang Woordenlijst tonen aanstaat. Kies een andere naam.';
  }

  @override
  String get compoundEditorNoFigures => 'Voeg ten minste één figuur toe.';

  @override
  String compoundEditorEmptyDomain(String param) {
    return 'Geen waarde van $param past bij alle instellingen die hij invult.';
  }

  @override
  String get compoundEditorTooLarge =>
      'Deze figuur heeft meer figuren of parameters dan ze kan bevatten.';

  @override
  String get compoundEditorBindingInvalid =>
      'Een instelling van een figuur wordt ingevuld door een parameter die er niet meer bij past. Controleer ‘Ingevuld door parameters’.';

  @override
  String get compoundEditorInvalidFigures =>
      'Een van de figuren is nog niet volledig of geldig.';

  @override
  String compoundEditorOtherFormFigures(
    int count,
    String figureForm,
    String entryForm,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count figuren komen',
      one: '1 figuur komt',
    );
    String _temp1 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'ze',
      one: 'hem',
    );
    return '$_temp0 uit $figureForm, niet uit $entryForm. Zet het danstype terug, of verwijder $_temp1.';
  }

  @override
  String get compoundEditorTooLong => 'Een van de velden is te lang.';

  @override
  String get compoundEditorUnusedTitle =>
      'Sommige parameters worden niet gebruikt';

  @override
  String compoundEditorUnusedBody(String params) {
    return '$params vult geen instellingen van een figuur in, dus kiezen verandert niets.';
  }

  @override
  String get compoundEditorUnusedBack => 'Terug naar editor';

  @override
  String get compoundEditorUnusedSave => 'Toch opslaan';

  @override
  String get glossaryEntryKindHeading => 'Wat het is';

  @override
  String get glossaryEntryKindHelp =>
      'Een combinatie wordt ingebouwde figuren wanneer een dans wordt opgeslagen. Een nieuwe figuur blijft één figuur, met je eigen formulering. Een term is een woord dat je zelf definieert, zonder figuur; je kunt er later een figuur aan geven.';

  @override
  String get glossaryEntryKindHelpFiguresOnly =>
      'Een combinatie wordt ingebouwde figuren wanneer een dans wordt opgeslagen. Een nieuwe figuur blijft één figuur, met je eigen formulering.';

  @override
  String get glossaryEntryKindCombination => 'Combinatie';

  @override
  String get glossaryEntryKindNewFigure => 'Nieuwe figuur';

  @override
  String get glossaryEntryKindTerm => 'Term';

  @override
  String get glossaryAddTerm => 'Term toevoegen';

  @override
  String get glossaryTermTitleNew => 'Nieuwe term';

  @override
  String get glossaryTermMakeFigure => 'Maak er een figuur van';

  @override
  String get glossaryTermMakeFigureTitle => 'Maak er een figuur van';

  @override
  String get glossaryEntryFormLabel => 'Dansvorm';

  @override
  String get glossaryEntryFormHelper =>
      'Het soort dans waarvoor hij bedoeld is.';

  @override
  String get userFigureEditorParamNames =>
      'Begin de naam van elke parameter met een letter, gebruik alleen letters, cijfers en _, en geef elke parameter een andere naam. Een naam kan niet move, beats, text, een rol, het tegenovergestelde van een andere parameter, zoals otherHand, of een woord waarmee voorwaarden geschreven worden zijn: if, then, else, not, and, or, is.';

  @override
  String userFigureEditorChoiceLabel(int number) {
    return 'Optie $number';
  }

  @override
  String get userFigureEditorAddChoice => 'Optie toevoegen';

  @override
  String get userFigureEditorRemoveChoice => 'Optie verwijderen';

  @override
  String get userFigureEditorDefault => 'Standaard';

  @override
  String get userFigureEditorNoDefault => 'Geen standaard';

  @override
  String get userFigureEditorFlagOff => 'Uit';

  @override
  String get userFigureEditorFlagLabel => 'Formulering als aan';

  @override
  String get userFigureEditorFlagLabelHelper =>
      'Getoond in de formulering als dit aan staat, zoals ‘met een zwier’.';

  @override
  String get userFigureEditorWording => 'Formulering';

  @override
  String userFigureEditorWordingHelp(String example) {
    return 'Hoe de figuur in een dans leest. Zet een parameter tussen accolades, zoals $example; een deel tussen vierkante haken valt weg als de parameters ervan leeg zijn.';
  }

  @override
  String userFigureEditorWordingSlots(String slots) {
    return 'Je kunt gebruiken: $slots';
  }

  @override
  String get userFigureEditorDefaultBeats => 'Standaardtellen';

  @override
  String get userFigureEditorDefaultBeatsHelper =>
      'Een dans kan ze wijzigen telkens als die de figuur gebruikt.';

  @override
  String userFigureEditorPreview(String text) {
    return 'Leest als: $text';
  }

  @override
  String get userFigureEditorPreviewUnavailable =>
      'Maak de formulering af om te zien hoe die leest.';

  @override
  String get userFigureEditorBadWording =>
      'De formulering is niet compleet: controleer de accolades en vierkante haken.';

  @override
  String userFigureEditorUnknownSlot(String slot) {
    return 'De formulering gebruikt $slot, dat geen parameter van deze figuur is.';
  }

  @override
  String userFigureEditorBadChoices(String param) {
    return 'Geef $param minstens één optie, elk met een andere naam.';
  }

  @override
  String get userFigureEditorBadBeats =>
      'Standaardtellen moeten tussen 0 en 64 liggen.';

  @override
  String userFigureEditorUnusedBody(String params) {
    return 'Niet in de formulering, dus kiezen verandert niets: $params.';
  }

  @override
  String get glossaryCustomWording => 'Formulering';

  @override
  String get glossaryCustomExample => 'Voorbeeld';

  @override
  String glossaryCustomDeleteTrash(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count dansen onder “Onlangs verwijderd” gebruiken hem en behouden de regels die ze het laatst opsloegen.',
      one:
          '1 dans onder “Onlangs verwijderd” gebruikt hem en behoudt de regel die hij het laatst opsloeg.',
    );
    return '$_temp0';
  }

  @override
  String get glossaryCustomDeleteDefaults =>
      'Je standaardfiguren in Instellingen gebruiken hem en behouden zijn huidige formulering als platte tekst.';

  @override
  String glossaryCustomDeleteShorthands(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Je $count afkortingen ervoor blijven, en als je die typt, worden ze als gewone regels gelezen.',
      one:
          'Je afkorting ervoor blijft, en als je die typt, wordt hij als een gewone regel gelezen.',
    );
    return '$_temp0';
  }

  @override
  String glossaryCustomDeleteUses(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count dansen gebruiken hem. Hij wordt uit je woordenlijst verwijderd en die dansen behouden hun huidige formulering als platte tekst.',
      one:
          '1 dans gebruikt hem. Hij wordt uit je woordenlijst verwijderd en die dans behoudt zijn huidige formulering als platte tekst.',
      zero:
          'Geen dans in je collectie gebruikt hem. Hij wordt uit je woordenlijst verwijderd.',
    );
    return '$_temp0';
  }

  @override
  String get danceEditorUserFigureUnavailable =>
      'Je figuur is niet beschikbaar, dus deze rij behoudt zijn huidige tekst.';

  @override
  String get compoundEditorDiscardBody =>
      'Je hebt niet-opgeslagen wijzigingen in deze figuur.';

  @override
  String compoundParamWithKind(String param, String kind) {
    return '$param ($kind)';
  }

  @override
  String get compoundParamKindDancers => 'dansers';

  @override
  String get compoundParamKindDancerPair => 'paar dansers';

  @override
  String get compoundParamKindHand => 'hand';

  @override
  String get compoundParamKindShoulder => 'schouder';

  @override
  String get compoundParamKindSpin => 'draairichting';

  @override
  String get compoundParamKindDirection => 'richting';

  @override
  String get compoundParamKindFraction => 'breuk';

  @override
  String get compoundParamKindRotation => 'draaihoek';

  @override
  String get compoundParamKindPlaces => 'plaatsen';

  @override
  String get compoundParamKindNumber => 'getal';

  @override
  String get compoundParamKindBeats => 'tellen';

  @override
  String get compoundParamKindFlag => 'aan/uit';

  @override
  String get compoundParamKindChoice => 'optie';

  @override
  String get compoundParamKindText => 'tekst';

  @override
  String wordingConditionsHelp(String example) {
    return 'Gebruik vierkante haken met if, then en else om het in sommige gevallen anders te formuleren, zoals $example';
  }

  @override
  String wordingConditionsNames(String names) {
    return 'Een voorwaarde kan testen: $names';
  }

  @override
  String wordingIssueUnclosedGroup(String context) {
    return 'Een “[” is niet gesloten: “$context”. Voeg “]” toe waar dat deel eindigt.';
  }

  @override
  String wordingIssueStrayCloseBracket(String context) {
    return 'Er staat een “]” zonder “[” ervoor, bij “$context”. Verwijder die, of voeg “[” toe waar dat deel begint.';
  }

  @override
  String wordingIssueUnclosedSlot(
    String brace,
    String closeBrace,
    String context,
    String example,
  ) {
    return 'De “$brace” in “$context” is niet gesloten. Voeg “$closeBrace” toe na de naam, zoals $example.';
  }

  @override
  String wordingIssueStrayCloseBrace(
    String brace,
    String closeBrace,
    String context,
  ) {
    return 'Er staat een “$closeBrace” zonder “$brace” ervoor, bij “$context”. Verwijder die, of voeg “$brace” toe voor de naam.';
  }

  @override
  String wordingIssueBadSlot(String found, String fix) {
    return '“$found” is geen plaatshouder: zet precies één naam tussen accolades, zoals $fix.';
  }

  @override
  String wordingIssueConditionInBraces(String found, String fix) {
    return 'Accolades bevatten één naam, geen voorwaarde: “$found”. Gebruik vierkante haken om een formulering alleen in sommige gevallen te tonen: $fix';
  }

  @override
  String wordingIssueTooLongStored(String max) {
    return 'Deze formulering is te lang om op te slaan: opgeslagen is ze langer dan $max tekens (een voorwaarde neemt opgeslagen iets meer ruimte in dan getypt). Maak haar korter of gebruik minder voorwaarden.';
  }

  @override
  String wordingIssueMissingCondition(String word, String example) {
    return 'Schrijf na “$word” wat er getest moet worden, bijvoorbeeld “$example”.';
  }

  @override
  String wordingIssueMissingThen(String condition) {
    return 'Schrijf na de voorwaarde “$condition” het woord “then” en de formulering die in dat geval getoond wordt.';
  }

  @override
  String wordingIssueColonForThen(String condition) {
    return 'Schrijf “then” in plaats van “:” na “$condition”.';
  }

  @override
  String wordingIssueUnknownName(String found, String names) {
    return '“$found” is niet iets wat deze formulering kan testen. Je kunt testen: $names.';
  }

  @override
  String wordingIssueUnknownNameSuggest(
    String found,
    String suggestion,
    String names,
  ) {
    return '“$found” is niet iets wat deze formulering kan testen. Bedoelde je “$suggestion”? Je kunt testen: $names.';
  }

  @override
  String wordingIssueUnknownNameAfterIf(String found, String names) {
    return 'Vierkante haken die met “if” beginnen bevatten een voorwaarde, en “$found” is niet iets wat deze formulering kan testen. Je kunt testen: $names.';
  }

  @override
  String wordingIssueUnknownNameAfterIfSuggest(
    String found,
    String suggestion,
    String names,
  ) {
    return 'Vierkante haken die met “if” beginnen bevatten een voorwaarde, en “$found” is niet iets wat deze formulering kan testen. Bedoelde je “$suggestion”? Je kunt testen: $names.';
  }

  @override
  String wordingIssueNameInBraces(String name, String found) {
    return 'Schrijf in een voorwaarde de naam zonder accolades: “$name”, niet “$found”.';
  }

  @override
  String wordingIssueIsntForIsNot(String found, String fix) {
    return 'Schrijf “is not” in plaats van “$found”: “$fix”.';
  }

  @override
  String wordingIssueSymbolForWord(String word, String found, String fix) {
    return 'Schrijf “$word” in plaats van “$found”: “$fix”.';
  }

  @override
  String wordingIssueQuotedValue(String fix) {
    return 'Laat de aanhalingstekens weg: “$fix”.';
  }

  @override
  String wordingIssueUnknownValue(String found, String name, String values) {
    return '“$found” is geen van de waarden die $name kan hebben. $name kan zijn: $values.';
  }

  @override
  String wordingIssueUnknownValueSuggest(
    String found,
    String name,
    String suggestion,
    String values,
  ) {
    return '“$found” is geen van de waarden die $name kan hebben. Bedoelde je “$suggestion”? $name kan zijn: $values.';
  }

  @override
  String wordingIssueExpectedValue(
    String before,
    String name,
    String example,
    String values,
  ) {
    return 'Schrijf na “$before” een waarde die $name kan hebben, zoals “$example”. $name kan zijn: $values.';
  }

  @override
  String wordingIssueListNeedsParens(String fix) {
    return 'Zet de waarden na “is in” tussen haakjes: “$fix”.';
  }

  @override
  String wordingIssueOneOfForIsIn(String word, String found, String fix) {
    return 'Schrijf “$word” in plaats van “$found”: “$fix”.';
  }

  @override
  String wordingIssueEmptyList(String example) {
    return 'De haakjes na “is in” zijn leeg. Noem minstens één waarde, zoals “$example”.';
  }

  @override
  String wordingIssueUnclosedParen(String context, String before) {
    return 'Een “(” is niet gesloten: “$context”. Voeg “)” toe na “$before”.';
  }

  @override
  String wordingIssueStrayCloseParen(String context) {
    return 'Er staat een “)” zonder “(” ervoor, bij “$context”. Verwijder die, of voeg de “(” toe waar die begint.';
  }

  @override
  String get wordingIssueEmptyParens =>
      'Er staat niets tussen “(” en “)”. Zet er een voorwaarde in, of verwijder ze.';

  @override
  String wordingIssueExpectedConnective(String before, String found) {
    return 'Schrijf na “$before” “and”, “or” of “then”: “$found” kan daar niet staan.';
  }

  @override
  String wordingIssueExpectedConnectiveInParens(String before, String found) {
    return 'Schrijf na “$before” “and”, “or” of “)”: “$found” kan daar niet staan.';
  }

  @override
  String wordingIssueExpectedConnectiveList(String before, String fix) {
    return 'Schrijf na “$before” “and”, “or” of “then”. Zet de waarden in een lijst om op meer dan één te testen: “$fix”.';
  }

  @override
  String wordingIssueExpectedListSeparator(String before, String found) {
    return 'Zet in de lijst “$before” een komma voor “$found”, of sluit de lijst af met “)”.';
  }

  @override
  String wordingIssueMixedAndOr(String found, String fixA, String fixB) {
    return '“$found” mengt “and” en “or”, dus het is niet duidelijk wat eerst komt. Voeg haakjes toe: “$fixA” of “$fixB”.';
  }

  @override
  String wordingIssueFlagCompare(String name) {
    return '$name staat aan of uit en wordt dus niet met een waarde vergeleken. Schrijf “if $name” voor aan, of “if not $name” voor uit.';
  }

  @override
  String wordingIssuePresenceOnly(String name) {
    return 'Bij $name kun je alleen testen of het ingevuld is. Schrijf “$name is empty”, “$name is not empty” of gewoon “$name”.';
  }

  @override
  String wordingIssueNotANumber(String name, String op) {
    return '$name is geen getal en kan dus niet “$op” iets zijn. Gebruik “$name is …” of “$name is in (…)”.';
  }

  @override
  String wordingIssueExpectedNumber(String op, String example, String found) {
    return 'Schrijf na “$op” een getal, zoals $example: “$found” is er geen.';
  }

  @override
  String wordingIssueNumberOutOfRange(
    String name,
    String min,
    String max,
    String found,
  ) {
    return '$name loopt van $min tot $max, dus $found valt erbuiten.';
  }

  @override
  String wordingIssueNumberNotWhole(String name, String found) {
    return '$name telt in hele getallen, dus $found kan geen van de waarden zijn.';
  }

  @override
  String wordingIssueNumberNotQuarter(String name, String found) {
    return '$name gaat in kwartslagen, zoals 0.25, 0.5, ¾ of 1½, dus $found kan geen van de waarden zijn.';
  }

  @override
  String wordingIssueNegatedComparison(String fix, String found) {
    return 'Schrijf “$fix” in plaats van “$found”.';
  }

  @override
  String wordingIssueAmbiguous(String found, String readingA, String readingB) {
    return '“$found” kan op twee manieren gelezen worden: “$readingA” of “$readingB”. Schrijf wat je bedoelt.';
  }

  @override
  String get wordingIssueSecondElse =>
      'Dit deel heeft al een “else”, dus een tweede kan niet volgen. Hoort “else” hier bij de formulering, zet die woorden dan tussen eigen vierkante haken, zoals “[everyone else]”.';

  @override
  String wordingIssueElseAfterWord(String phrase) {
    return '“else” begint hier de formulering voor alle andere gevallen. Bedoelde je de woorden “$phrase”, zet ze dan tussen eigen vierkante haken: “[$phrase]”.';
  }

  @override
  String wordingIssueOtherwiseWord(String found) {
    return '“$found” wordt hier als formulering getoond. Schrijf “else” om een formulering voor alle andere gevallen te geven.';
  }

  @override
  String wordingIssueEmptyMeansNoValue(String name, String fix) {
    return '“$name is empty” test of $name geen waarde heeft, niet op de optie “empty”. Schrijf “$fix” om op die optie te testen.';
  }

  @override
  String wordingIssueValueAfterConnective(
    String found,
    String word,
    String fixA,
    String fixB,
  ) {
    return '“$found” na “$word” is een waarde, niet iets om te testen. Herhaal wat je test, “$fixA”, of zet de waarden in een lijst: “$fixB”.';
  }

  @override
  String get wordingIssueNothingToTest =>
      'Deze formulering kan hier niets testen: de figuur waar ze bij hoort staat niet op dit apparaat, of deze versie van de app kent haar niet, dus haar voorwaarden kunnen niet gecontroleerd worden. Wijzig haar op een apparaat met die figuur, of verwijder de voorwaarde.';

  @override
  String wordingIssueTooLongTyped(String max) {
    return 'Deze formulering is te lang om te lezen: getypt is ze langer dan $max tekens. Maak haar korter.';
  }

  @override
  String wordingIssueTooDeep(String max) {
    return 'Deze formulering zet te veel vierkante haken of haakjes in elkaar: er kunnen er hoogstens $max genest worden. Haal er een paar weg.';
  }

  @override
  String wordingIssueTooManyNots(String max) {
    return 'Deze voorwaarde zet te veel “not” in elkaar: hoogstens $max. Haal er een paar weg: twee “not” achter elkaar heffen elkaar op.';
  }

  @override
  String get settingsCallingCardsHeader => 'Callkaarten';

  @override
  String get settingsCallingCardsEnableTitle => 'Callkaarten afdrukken';

  @override
  String get settingsCallingCardsEnableSubtitle =>
      'Voegt Callkaart afdrukken toe aan het exportmenu van een dans, en Callkaarten afdrukken aan dat van een programma: één kleine kaart per dans, opgemaakt zoals je hieronder kiest.';

  @override
  String get settingsCallingCardsSizeTitle => 'Kaartformaat';

  @override
  String settingsCallingCardsSizeIndexCard(String size) {
    return 'Systeemkaart, $size';
  }

  @override
  String settingsCallingCardsSizeIsoA(String name, String size) {
    return '$name ($size)';
  }

  @override
  String settingsCallingCardsSizeInches(String width, String height) {
    return '$width × $height inch';
  }

  @override
  String settingsCallingCardsSizeMillimetres(String width, String height) {
    return '$width × $height mm';
  }

  @override
  String get settingsCallingCardsSizeCustom => 'Eigen formaat';

  @override
  String get settingsCallingCardsWidthLabel => 'Breedte';

  @override
  String get settingsCallingCardsHeightLabel => 'Hoogte';

  @override
  String get settingsCallingCardsUnitInches => 'Inch';

  @override
  String get settingsCallingCardsUnitMillimetres => 'Millimeter';

  @override
  String get settingsCallingCardsSizeInvalid =>
      'Elke zijde moet tussen 1 en 14 inch (26 tot 355 mm) liggen.';

  @override
  String get settingsCallingCardsLandscapeTitle => 'Liggend';

  @override
  String get settingsCallingCardsLandscapeSubtitle =>
      'Afdrukken met de lange zijde bovenaan.';

  @override
  String get settingsCallingCardsLayoutTitle => 'Kaartopmaak';

  @override
  String get settingsCallingCardsLayoutSubtitle =>
      'Kies wat er op elke kaart komt, en waar.';

  @override
  String get callingCardEditorTitle => 'Opmaak van de callkaart';

  @override
  String get callingCardEditorFieldLabel => 'Opmaak';

  @override
  String get callingCardEditorAutosaveHint =>
      'Wijzigingen worden opgeslagen terwijl je typt.';

  @override
  String get callingCardEditorReset => 'Standaard herstellen';

  @override
  String get callingCardEditorResetConfirmTitle => 'Opmaak herstellen?';

  @override
  String get callingCardEditorResetConfirmBody =>
      'Je opmaak wordt vervangen door de standaardopmaak.';

  @override
  String get callingCardEditorReplaced => 'Opmaak vervangen.';

  @override
  String get callingCardEditorPreviewTitle => 'Voorbeeld';

  @override
  String callingCardEditorPreviewCaption(String size) {
    return 'Een voorbeelddans op een kaart van $size.';
  }

  @override
  String get callingCardEditorPreviewError =>
      'Het voorbeeld kon niet worden getekend. Probeer het opnieuw.';

  @override
  String callingCardEditorPreviewShrunk(int percent) {
    return 'De tekst wordt verkleind tot $percent% om op deze kaart te passen.';
  }

  @override
  String get callingCardEditorPreviewOverflow =>
      'Deze kaart past zelfs op halve grootte niet, dus de onderkant is afgesneden. Haal een blok weg, of voeg lines= toe aan een lang blok.';

  @override
  String get callingCardEditorIssuesTitle =>
      'Regels die niet gelezen konden worden';

  @override
  String callingCardIssueUnknownBlock(int line, String name) {
    return 'Regel $line: \"$name\" is geen blok. De blokken staan onder Zo schrijf je een opmaak.';
  }

  @override
  String callingCardIssueUnknownOption(int line, String name) {
    return 'Regel $line: dit blok heeft geen optie \"$name\".';
  }

  @override
  String callingCardIssueBadValue(int line, String option, String value) {
    return 'Regel $line: \"$value\" werkt niet voor $option.';
  }

  @override
  String callingCardIssueUnclosedQuote(int line) {
    return 'Regel $line: een aanhalingsteken wordt nooit gesloten, dus de hele regel wordt overgeslagen.';
  }

  @override
  String callingCardIssueMissingText(int line) {
    return 'Regel $line: text heeft woorden tussen aanhalingstekens nodig, zoals text \"Called by me\".';
  }

  @override
  String callingCardIssueCardNotAlone(int line) {
    return 'Regel $line: card stelt de hele kaart in en heeft dus een eigen regel nodig.';
  }

  @override
  String callingCardIssueEmptyBlock(int line) {
    return 'Regel $line: aan één kant van een | staat niets.';
  }

  @override
  String get callingCardHelpTitle => 'Zo schrijf je een opmaak';

  @override
  String get callingCardHelpIntro =>
      'Elke regel is één rij van de kaart, van boven naar beneden. Begin de regel met de naam van een blok en voeg daarna eventuele opties toe. Zet | tussen blokken om ze naast elkaar te plaatsen. Een regel die met # begint, is een notitie voor jezelf en wordt niet afgedrukt.';

  @override
  String get callingCardHelpFields =>
      'Een blok drukt alleen af wat de dans heeft, en alleen velden die zijn aangezet onder Instellingen ▸ Standaarden ▸ Gedeelde dansvelden. Een rij zonder iets om af te drukken neemt geen ruimte in. Is een kaart te vol, dan wordt alles erop gelijkmatig verkleind om te passen, tot op de helft van de grootte.';

  @override
  String get callingCardHelpTapToInsert =>
      'Tik op een naam om die aan je opmaak toe te voegen.';

  @override
  String get callingCardHelpBlocksTitle => 'Blokken';

  @override
  String get callingCardHelpOptionsTitle => 'Opties';

  @override
  String get callingCardHelpExamplesTitle => 'Voorbeelden';

  @override
  String get callingCardHelpExampleUse => 'Deze opmaak gebruiken';

  @override
  String get callingCardHelpBlockTitle => 'De titel van de dans.';

  @override
  String get callingCardHelpBlockAuthors =>
      'Wie de dans heeft geschreven en wanneer, daarna wie hem heeft geïnterpreteerd en wanneer.';

  @override
  String get callingCardHelpBlockFormation =>
      'De opstelling, zoals Improper of Becket.';

  @override
  String get callingCardHelpBlockLevel => 'Het niveau van de dans.';

  @override
  String get callingCardHelpBlockMeta =>
      'Opstelling, niveau, mixer, status en frase op één regel, elk met zijn label.';

  @override
  String get callingCardHelpBlockMusic =>
      'De maatsoort en toonsoort van het deuntje en de Barnes-verwijzing op één regel.';

  @override
  String get callingCardHelpBlockFigures =>
      'De figuren, gegroepeerd per frase (A1, A2, B1, B2), met hun lengte: in tellen, of in maten voor een Engelse dans.';

  @override
  String get callingCardHelpBlockNotes => 'Je callnotities.';

  @override
  String get callingCardHelpBlockWalkthrough => 'De walkthrough.';

  @override
  String get callingCardHelpBlockHook => 'De hook van de dans.';

  @override
  String get callingCardHelpBlockTunes => 'Voorgestelde melodieën.';

  @override
  String get callingCardHelpBlockSources => 'Gepubliceerde bronnen.';

  @override
  String get callingCardHelpBlockProgram =>
      'De titel van het programma, als je een programma afdrukt.';

  @override
  String get callingCardHelpBlockNumber =>
      'De plaats van de dans in het programma (1, 2, 3 of Alternatief), als je een programma afdrukt.';

  @override
  String get callingCardHelpBlockText =>
      'Je eigen woorden, tussen aanhalingstekens.';

  @override
  String get callingCardHelpBlockRule => 'Een lijn over de kaart.';

  @override
  String get callingCardHelpBlockSpace =>
      'Een witruimte, in punten (72 per inch).';

  @override
  String get callingCardHelpBlockCard =>
      'Instellingen voor de hele kaart: margin is de ruimte langs de rand, in punten.';

  @override
  String get callingCardHelpOptionSize => 'Tekstgrootte, in punten.';

  @override
  String get callingCardHelpOptionStyle => 'Vette of schuine tekst.';

  @override
  String get callingCardHelpOptionAlign =>
      'Waar de tekst in zijn ruimte staat.';

  @override
  String get callingCardHelpOptionColor => 'Tekst- of lijnkleur, als hexcode.';

  @override
  String get callingCardHelpOptionLines =>
      'Druk hooguit zoveel regels van een lang blok af.';

  @override
  String get callingCardHelpOptionLabel =>
      'Woorden vóór de tekst. label=\"\" drukt er geen af.';

  @override
  String get callingCardHelpOptionWidth =>
      'In een rij neemt een blok met width=2 twee keer zoveel ruimte in als een met width=1.';

  @override
  String get callingCardHelpOptionFigures =>
      'Voor figures: laat de lengtes, de eigen notities van de figuren, de frasenamen of de lijnen tussen de frasen weg.';

  @override
  String get callingCardHelpOptionThickness =>
      'Hoe dik een lijn is, in punten.';

  @override
  String get callingCardExampleClassic => 'Klassiek';

  @override
  String get callingCardExampleBigPrint => 'Grote letters';

  @override
  String get callingCardExampleProgram => 'Programma-avond';

  @override
  String get callingCardExampleTeaching => 'Leskaart';

  @override
  String get callingCardSampleTitle => 'Voorbeeldcontra';

  @override
  String get callingCardSampleAuthor => 'A. Caller';

  @override
  String get callingCardSampleNotes =>
      'Schuif naar links langs de rij om door te schuiven.';

  @override
  String get callingCardSampleFigureNote => 'Houd vast voor de hele draai.';

  @override
  String get callingCardSampleProgram => 'Vrijdagavonddans';

  @override
  String get exportPrintCallingCard => 'Callkaart afdrukken';

  @override
  String get exportPrintCallingCards => 'Callkaarten afdrukken';

  @override
  String exportCallingCardsCutOff(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count kaarten pasten niet en zijn onderaan afgesneden.',
      one: '1 kaart paste niet en is onderaan afgesneden.',
    );
    return '$_temp0';
  }

  @override
  String get callingCardHelpOptionHighlight =>
      'Voor figures: de bewegingen vet in donkerrood, de dansers vet, en hoeveelheden zoals ½ of 3 places in blauwgrijs.';

  @override
  String get settingsCallingCardsSheetsTitle => 'Meerdere kaarten per pagina';

  @override
  String get settingsCallingCardsSheetsSubtitle =>
      'Afdrukken op gewoon papier, zoveel kaarten per pagina als er passen, met snijtekens. Het papier is het papier dat je kiest bij het afdrukken.';

  @override
  String get exportCallingCardsBiggerThanPaper =>
      'Deze kaarten zijn groter dan het papier, dus elke kaart is kleiner afgedrukt, één per pagina.';

  @override
  String get settingsProgramTemplatesTitle => 'Programmasjablonen';

  @override
  String settingsProgramTemplatesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count sjablonen',
      one: '1 sjabloon',
      zero: 'Nog geen sjablonen',
    );
    return '$_temp0';
  }

  @override
  String get settingsProgramTemplateDefaultTitle => 'Standaardsjabloon';

  @override
  String get settingsProgramTemplateDefaultSubtitle =>
      'Waarmee een nieuw programma begint als je niet wordt gevraagd te kiezen.';

  @override
  String get settingsProgramTemplatesMigratedName => 'Startprogramma';

  @override
  String get programTemplateBlankProgram => 'Leeg programma';

  @override
  String get programTemplateDefaultBadge => 'Standaard';

  @override
  String get programTemplateChooserTitle => 'Beginnen met een sjabloon';

  @override
  String get programTemplateNew => 'Nieuw sjabloon';

  @override
  String get programTemplatesEmptyTitle => 'Nog geen sjablonen';

  @override
  String get programTemplatesEmptyBody =>
      'Een sjabloon is een startlijst met dansen, notities en pauzes voor één soort avond. Met twee of meer vraagt Nieuw programma waarmee je wilt beginnen.';

  @override
  String get programTemplateNameLabel => 'Naam van sjabloon';

  @override
  String get programTemplateRename => 'Naam wijzigen';

  @override
  String get programTemplateRenameTitle => 'Sjabloon hernoemen';

  @override
  String programTemplateCopyName(String name) {
    return '$name (kopie)';
  }

  @override
  String get programTemplateUntitled => 'Naamloos sjabloon';

  @override
  String programTemplateSlotCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count slots',
      one: '1 slot',
      zero: 'Leeg',
    );
    return '$_temp0';
  }

  @override
  String programTemplateDefaultWithSlots(String slots) {
    return 'Standaard · $slots';
  }

  @override
  String programTemplateActionsTooltip(String name) {
    return 'Acties voor $name';
  }

  @override
  String get programTemplateEditorTitle => 'Sjabloon bewerken';

  @override
  String get programTemplateSlotsHeader => 'Slots';

  @override
  String get programTemplateSlotsSubtitle =>
      'Dansen, notities en pauzes waarmee een programma op basis van dit sjabloon begint.';

  @override
  String get programTemplatesLoadError =>
      'Je programmasjablonen konden niet worden geladen.';

  @override
  String get programTemplateSaveError =>
      'Die wijziging in je sjablonen kon niet worden opgeslagen. Probeer het opnieuw.';

  @override
  String get settingsSuggestionsHeader => 'Suggesties';

  @override
  String get settingsSuggestionsEnabledTitle => 'De volgende dans voorstellen';

  @override
  String get settingsSuggestionsEnabledSubtitle =>
      'Voegt Voorgesteld toe aan het menu Sorteren van de danslijsten in de programma-editor. Het ordent de dansen voor de plek waar de nieuwe dans komt en zegt waarom.';

  @override
  String get settingsSuggestionsInPerformSwapTitle =>
      'Gebruiken bij Deze dans wisselen in Uitvoeren';

  @override
  String get settingsSuggestionsInPerformSwapSubtitle =>
      'Als je in Uitvoeren een dans wisselt, staan de dansen onder Je alternatieven in de volgorde die het best past bij die plek in het programma, met de reden erbij. Er valt niets weg.';

  @override
  String get settingsSuggestionsEditorTitle => 'Waar suggesties op letten';

  @override
  String get settingsSuggestionsEditorSubtitle =>
      'Kies hoeveel elk punt meetelt als er dansen worden voorgesteld.';

  @override
  String get suggestionFactorMatrixVarietyTitle => 'Afwisseling in de matrix';

  @override
  String get suggestionFactorMatrixVarietyHelp =>
      'Geeft voorkeur aan dansen met figuren die het programma nog niet gebruikt. Vermijdt figuren op dezelfde tellen als de dans ervoor.';

  @override
  String get suggestionFactorFormationBalanceTitle => 'Evenwicht in formaties';

  @override
  String get suggestionFactorFormationBalanceHelp =>
      'Vermijdt de formatie van de dans ervoor en formaties waarvan het programma er al veel heeft.';

  @override
  String get suggestionFactorDifficultyCurveTitle => 'Moeilijkheidscurve';

  @override
  String get suggestionFactorDifficultyCurveHelp =>
      'Laat de moeilijkheid van de avond een vorm volgen.';

  @override
  String get suggestionFactorVenueRecencyTitle => 'Recent op deze locatie';

  @override
  String get suggestionFactorVenueRecencyHelp =>
      'Vermijdt dansen die onlangs op de locatie van het programma zijn gecalld. Een programma zonder locatie slaat dit over.';

  @override
  String get suggestionWeightOff => 'Uit';

  @override
  String get suggestionWeightALittle => 'Een beetje';

  @override
  String get suggestionWeightALot => 'Veel';

  @override
  String suggestionWeightSemantic(String factor) {
    return 'Hoeveel $factor meetelt';
  }

  @override
  String get suggestionCurveShapeLabel => 'Vorm';

  @override
  String get suggestionCurveBuildThenEase => 'Opbouwen, dan afbouwen';

  @override
  String get suggestionCurveEven => 'Gelijkmatig';

  @override
  String get suggestionsResetDefaults => 'Standaardwaarden herstellen';

  @override
  String get suggestionsResetDone =>
      'Suggesties letten weer op de standaardpunten.';

  @override
  String get suggestionsNewerVersion =>
      'Deze keuzes zijn opgeslagen door een nieuwere versie van de app en kunnen hier niet worden gewijzigd. Werk de app bij om ze te wijzigen.';

  @override
  String get collectionSortSuggested => 'Voorgesteld';

  @override
  String suggestionReasonNewMoves(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count nieuwe figuren voor vanavond',
      one: 'Een nieuwe figuur voor vanavond',
    );
    return '$_temp0';
  }

  @override
  String suggestionReasonBeatOverlapPrevious(String move) {
    return '$move op dezelfde tellen als de vorige dans';
  }

  @override
  String suggestionReasonBeatOverlapNext(String move) {
    return '$move op dezelfde tellen als de volgende dans';
  }

  @override
  String suggestionReasonSameFormationPrevious(String formation) {
    return '$formation, net als de vorige dans';
  }

  @override
  String suggestionReasonSameFormationNext(String formation) {
    return '$formation, net als de volgende dans';
  }

  @override
  String suggestionReasonFormationCommon(int count, String formation) {
    return 'Vanavond al $count dansen in $formation';
  }

  @override
  String suggestionReasonFirstFormation(String formation) {
    return '$formation: de eerste vanavond';
  }

  @override
  String get suggestionReasonFitsCurve => 'Past hier bij de moeilijkheidscurve';

  @override
  String get suggestionReasonHarderThanCurve =>
      'Moeilijker dan de moeilijkheidscurve hier wil';

  @override
  String get suggestionReasonEasierThanCurve =>
      'Makkelijker dan de moeilijkheidscurve hier wil';

  @override
  String suggestionReasonCalledHereRecently(String venue, String date) {
    return 'Op $date gecalld in $venue';
  }

  @override
  String suggestionReasonNotCalledHereSince(String venue, String date) {
    return 'Sinds $date niet gecalld in $venue';
  }

  @override
  String suggestionReasonNeverCalledHere(String venue) {
    return 'Nooit gecalld in $venue';
  }

  @override
  String get suggestionReasonVenueSkipped =>
      'Recent op deze locatie: overgeslagen, omdat het programma geen locatie heeft';

  @override
  String get suggestionReasonNoFactor =>
      'Geen van de punten heeft deze dans verschoven';

  @override
  String get suggestionReasonEnglishNotCovered =>
      'Suggesties gelden nog niet voor Engelse dansen';

  @override
  String suggestionReasonPhraseOverlapPrevious(String move) {
    return '$move in dezelfde frase als de vorige dans';
  }

  @override
  String suggestionReasonPhraseOverlapNext(String move) {
    return '$move in dezelfde frase als de volgende dans';
  }

  @override
  String suggestionReasonBeatOverlapAfterDance(String move, String dance) {
    return '$move op dezelfde tellen als $dance, de dans er vlak voor';
  }

  @override
  String suggestionReasonBeatOverlapBeforeDance(String move, String dance) {
    return '$move op dezelfde tellen als $dance, de dans er vlak na';
  }

  @override
  String suggestionReasonPhraseOverlapAfterDance(String move, String dance) {
    return '$move in dezelfde frase als $dance, de dans er vlak voor';
  }

  @override
  String suggestionReasonPhraseOverlapBeforeDance(String move, String dance) {
    return '$move in dezelfde frase als $dance, de dans er vlak na';
  }

  @override
  String suggestionReasonSameFormationAfterDance(
    String formation,
    String dance,
  ) {
    return '$formation, net als $dance, de dans er vlak voor';
  }

  @override
  String suggestionReasonSameFormationBeforeDance(
    String formation,
    String dance,
  ) {
    return '$formation, net als $dance, de dans er vlak na';
  }

  @override
  String get suggestionReasonAlreadyInProgram => 'Al in dit programma';

  @override
  String get suggestionRankingFailed =>
      'Deze dansen konden niet worden gerangschikt, dus ze staan in de gewone volgorde.';

  @override
  String suggestionWhyTooltip(String title) {
    return 'Waarom $title hier wordt voorgesteld';
  }

  @override
  String suggestionWhyTitle(String title) {
    return 'Waarom $title';
  }

  @override
  String suggestionWhyRaises(String reason) {
    return 'Zet hem hoger: $reason';
  }

  @override
  String suggestionWhyLowers(String reason) {
    return 'Zet hem lager: $reason';
  }

  @override
  String suggestionWouldBreak(int count, String rules) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Zou $count regels overtreden: $rules',
      one: 'Zou overtreden: $rules',
    );
    return '$_temp0';
  }

  @override
  String suggestionWouldBreakSemantic(int count, String rules) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Zou $count avondregels overtreden: $rules',
      one: 'Zou de avondregel overtreden: $rules',
    );
    return '$_temp0';
  }

  @override
  String get figureParamSearchDancersHint => 'Dansers zoeken';

  @override
  String get exportAddToCalendar => 'Toevoegen aan agenda (.ics)';

  @override
  String get programsExportCalendar => 'Agenda exporteren (.ics)';

  @override
  String get exportCalendarPickTitle => 'Agenda exporteren';

  @override
  String get exportCalendarPickBody =>
      'Kies de programma\'s die in het agendabestand komen.';

  @override
  String get exportCalendarShowPast => 'Eerdere programma\'s tonen';

  @override
  String get exportCalendarNoUpcoming =>
      'Geen komende programma\'s om te tonen. Gearchiveerde programma\'s staan hier niet. Zet Eerdere programma\'s tonen aan om een eerder programma te kiezen.';

  @override
  String get exportCalendarNoDated =>
      'Nog geen enkel programma heeft een datum. Geef een programma een datum om het aan een agenda toe te voegen.';

  @override
  String get exportCalendarPickConfirm => 'Exporteren';

  @override
  String get exportCalendarAddressTitle => 'Adres van de locatie opnemen?';

  @override
  String get exportCalendarAddressBody =>
      'Het agendabestand noemt de locatie. Het adres blijft weg, tenzij je het opneemt. Agenda\'s worden vaak gesynchroniseerd of met anderen gedeeld.';

  @override
  String get exportCalendarAddressInclude => 'Adres van de locatie opnemen';

  @override
  String get exportCalendarDialogTitle => 'Agendabestand exporteren';

  @override
  String get exportCalendarDialogMessage =>
      'Kies hoe je dit agendabestand wilt afleveren.';

  @override
  String get exportCalendarSavedGeneric => 'Agendabestand opgeslagen.';

  @override
  String get exportCalendarSaveError =>
      'Dit agendabestand kon niet worden opgeslagen. Probeer het opnieuw.';

  @override
  String get exportCalendarShareError =>
      'Dit agendabestand kon niet worden gedeeld. Probeer het opnieuw.';

  @override
  String get importErrorNotACalendar =>
      'Dat adres gaf geen agenda terug. Gebruik bij een Google-agenda het adres in iCal-indeling (Instellingen en delen ▸ Agenda integreren), niet de gewone link.';

  @override
  String get importFromCalendar => 'Uit agenda';

  @override
  String get importProgramFromCalendar => 'Importeren uit agenda';

  @override
  String get calendarImportTitle => 'Importeren uit agenda';

  @override
  String get calendarImportImport => 'Importeren';

  @override
  String get calendarAddressLabel => 'Agenda-adres';

  @override
  String get calendarAddressHelper =>
      'Het iCal-adres van de agenda, beginnend met https:// of webcal://. Het geheime adres van een privé-agenda werkt ook; houd het voor jezelf.';

  @override
  String get calendarImportFetch => 'Afspraken ophalen';

  @override
  String get calendarImportFailed =>
      'Importeren uit de agenda is mislukt. Probeer het opnieuw.';

  @override
  String get calendarImportUntitled => 'Afspraak zonder titel';

  @override
  String calendarImportCommitted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count conceptprogramma\'s toegevoegd uit je agenda.',
      one: '1 conceptprogramma toegevoegd uit je agenda.',
    );
    return '$_temp0';
  }

  @override
  String get calendarImportNothingFound => 'Geen afspraken in deze periode.';

  @override
  String calendarImportSummary(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count nieuwe afspraken.',
      one: '1 nieuwe afspraak.',
      zero: 'Geen nieuwe afspraken.',
    );
    return '$_temp0';
  }

  @override
  String get calendarImportNewHeader => 'Nieuw in je agenda';

  @override
  String get calendarImportDeletedHeader =>
      'Programma\'s die je hebt verwijderd';

  @override
  String get calendarImportDeletedNote =>
      'Je hebt het programma verwijderd dat van deze afspraak is gemaakt. Vink het aan om het opnieuw te importeren.';

  @override
  String get calendarImportAlreadyHeader => 'Al geïmporteerd';

  @override
  String get calendarImportFromThisAppHeader => 'Uit deze app';

  @override
  String get calendarImportUnreadableHeader =>
      'Terugkerende afspraken die de app niet kan lezen';

  @override
  String get calendarImportUnreadableBody =>
      'Deze herhalen zich op een manier die de app niet begrijpt, dus ze worden niet geïmporteerd.';

  @override
  String calendarImportSkippedNoUid(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count afspraken hebben geen id en zijn overgeslagen.',
      one: '1 afspraak heeft geen id en is overgeslagen.',
    );
    return '$_temp0';
  }

  @override
  String calendarImportTruncated(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'De agenda heeft meer dan $count afspraken. Alleen de eerste $count zijn gelezen.',
    );
    return '$_temp0';
  }

  @override
  String get calendarSettingsHeader => 'Agenda';

  @override
  String get calendarSettingsSaveError =>
      'Die instelling kon niet worden opgeslagen. Probeer het opnieuw.';

  @override
  String get calendarAddressSet => 'Ingesteld. Tik om het te wijzigen.';

  @override
  String get calendarAddressNotSet => 'Niet ingesteld';

  @override
  String get calendarWindowTitle => 'Welke afspraken';

  @override
  String get calendarWindowSubtitle =>
      'Afspraken vanaf vandaag tot zo ver vooruit. Terugkerende afspraken worden maar 30 dagen vooruit gelezen.';

  @override
  String calendarWindowOption(int months) {
    String _temp0 = intl.Intl.pluralLogic(
      months,
      locale: localeName,
      other: '$months maanden',
      one: '1 maand',
    );
    return '$_temp0';
  }

  @override
  String get calendarTitleFilterTitle =>
      'Alleen afspraken waarvan de titel bevat';

  @override
  String get calendarTitleFilterHelper =>
      'Voor een agenda waar ook andere afspraken in staan. Laat leeg voor alle afspraken.';

  @override
  String get calendarTitleFilterNone => 'Alle afspraken';

  @override
  String calendarTitleFilterValue(String filter) {
    return '‘$filter’';
  }

  @override
  String get calendarPullNowTitle => 'Nu ophalen';

  @override
  String get calendarPullNowSubtitle =>
      'Lees de agenda en kies afspraken om als conceptprogramma\'s toe te voegen.';

  @override
  String get collectionExportCsv => 'Exporteren als CSV';

  @override
  String get settingsExportDancesCsvTitle =>
      'Dansen exporteren als spreadsheet';

  @override
  String get settingsExportDancesCsvSubtitle =>
      'Alle dansen in je collectie, als CSV-bestand voor Excel, Numbers of Google Sheets. De regels voor delen gelden, plus je sterbeoordelingen. Het is geen back-up en kan niet worden hersteld.';

  @override
  String get settingsExportDancesCsvAction => 'Exporteren';

  @override
  String get exportCsvDialogTitle => 'Een spreadsheet exporteren (CSV)';

  @override
  String get exportCsvDialogMessage =>
      'Sla het bestand op of deel het met een andere app. Het opent in Excel, Numbers, LibreOffice of Google Sheets.';

  @override
  String get exportCsvSavedGeneric => 'Spreadsheet opgeslagen.';

  @override
  String get exportCsvSaveError =>
      'Deze spreadsheet kon niet worden opgeslagen. Probeer het opnieuw.';

  @override
  String get exportCsvShareError =>
      'Deze spreadsheet kon niet worden gedeeld. Probeer het opnieuw.';

  @override
  String get exportCsvError =>
      'Deze spreadsheet kon niet worden gemaakt. Probeer het opnieuw.';

  @override
  String get csvDancesFileStem => 'dansen';

  @override
  String get csvColumnTitle => 'Titel';

  @override
  String get csvColumnAuthors => 'Auteurs';

  @override
  String get csvColumnInterpreters => 'Geïnterpreteerd door';

  @override
  String get csvColumnForm => 'Type';

  @override
  String get csvColumnFormation => 'Formatie';

  @override
  String get csvColumnProgression => 'Progressie';

  @override
  String get csvColumnLevel => 'Niveau';

  @override
  String get csvColumnMixedLevel => 'Gemengd niveau';

  @override
  String get csvColumnMixer => 'Mixer';

  @override
  String get csvColumnStatus => 'Status';

  @override
  String get csvColumnRating => 'Beoordeling';

  @override
  String get csvColumnTags => 'Tags';

  @override
  String get csvColumnTunes => 'Deuntjes';

  @override
  String get csvColumnMeter => 'Maatsoort';

  @override
  String get csvColumnKey => 'Toonsoort';

  @override
  String get csvColumnSources => 'Gepubliceerde bronnen';

  @override
  String get csvColumnHook => 'Hook';

  @override
  String get csvColumnCallingNotes => 'Callnotities';

  @override
  String get csvColumnWalkthrough => 'Doorloop';

  @override
  String get csvColumnFigures => 'Figuren';

  @override
  String get csvColumnComposed => 'Gecomponeerd';

  @override
  String get csvColumnInterpreted => 'Geïnterpreteerd';

  @override
  String get csvColumnBarnes => 'Barnes-verwijzing';

  @override
  String get programsExportCsv => 'Programma\'s exporteren als CSV';

  @override
  String get csvProgramsFileStem => 'programmas';

  @override
  String get csvColumnEventDate => 'Eventdatum';

  @override
  String get csvColumnVenue => 'Locatie';

  @override
  String get csvColumnCaller => 'Caller';

  @override
  String get csvColumnBand => 'Band';

  @override
  String get csvColumnDancerLevel => 'Dansersniveau';

  @override
  String get csvColumnPayAmount => 'Gage';

  @override
  String get csvColumnPayCurrency => 'Valuta';

  @override
  String get csvColumnNotes => 'Notities';

  @override
  String get csvColumnDanceCount => 'Aantal dansen';

  @override
  String get csvColumnDances => 'Dansen';

  @override
  String get exportCsvPayHiddenNotice =>
      'De gage is verborgen in Instellingen en wordt daarom weggelaten. Zet ‘Gage tonen’ aan onder Instellingen ▸ Programma om hem op te nemen.';

  @override
  String get performSwapThisDance => 'Deze dans wisselen';

  @override
  String performSwapDanceNamed(String title) {
    return '$title wisselen';
  }

  @override
  String performSwappedAnnounce(String title) {
    return '$title ingewisseld';
  }

  @override
  String get performSwapKeepHeader => 'Behouden';

  @override
  String performSwapKeepFormation(String formation) {
    return 'Zelfde formatie: $formation';
  }

  @override
  String performSwapKeepLevel(String level) {
    return 'Dit niveau of makkelijker: $level';
  }

  @override
  String performSwapKeepType(String type) {
    return 'Zelfde type: $type';
  }

  @override
  String get performSwapKeepNotInProgram =>
      'Nog niet in het programma van vanavond';

  @override
  String get performSwapFiguresHeader => 'Figuren behouden';

  @override
  String performSwapFigureInPhrase(String figure, String phrase) {
    return '$figure in $phrase';
  }

  @override
  String performSwapKeepFigureSemantic(String figure) {
    return '$figure behouden';
  }

  @override
  String performSwapSamePhrase(String phrase) {
    return 'In dezelfde frase ($phrase)';
  }

  @override
  String performSwapSamePhraseSemantic(String figure, String phrase) {
    return '$figure in dezelfde frase behouden, $phrase';
  }

  @override
  String performSwapWithBefore(String figure) {
    return 'Met wat eraan voorafgaat ($figure)';
  }

  @override
  String performSwapWithBeforeSemantic(String figure, String before) {
    return '$figure direct na $before behouden';
  }

  @override
  String get performSwapMoreFilters => 'Meer filters';

  @override
  String get performSwapKeepInPanels =>
      'De andere keuzes om te behouden staan nu onder Filters en Geavanceerd.';

  @override
  String get performSwapEnglishNote =>
      'Voor Engelse dansen zijn zelfde formatie en de verfijningen van figuren nog niet beschikbaar.';

  @override
  String get performSwapAlternatesHeading => 'Je alternatieven';

  @override
  String get performSwapResultsHeading => 'Passende dansen';

  @override
  String get performSwapRefused =>
      'Dit programma is op een ander apparaat gewijzigd, dus een van je wijzigingen is niet opgeslagen. Controleer het programma en breng de wijziging opnieuw aan als je die nog wilt.';

  @override
  String get settingsPerformSwapTitle => 'Een dans wisselen';

  @override
  String get settingsPerformSwapSubtitle =>
      'Kies welke keuzes om te behouden aan staan als je een dans wisselt tijdens het uitvoeren.';

  @override
  String get settingsPerformSwapFormation => 'Zelfde formatie';

  @override
  String get settingsPerformSwapLevel => 'Dit niveau of makkelijker';

  @override
  String get settingsPerformSwapType => 'Zelfde type';

  @override
  String get settingsPerformSwapTypeSubtitle =>
      'Alleen in een programma met verschillende types, zoals contra’s en Engelse dansen.';

  @override
  String get settingsPerformSwapNewerVersion =>
      'Deze keuzes zijn opgeslagen door een nieuwere versie van de app. Deze versie gebruikt haar beginkeuzes, allemaal aan, en overschrijft die van jou niet. Werk de app bij om ze te wijzigen.';

  @override
  String get settingsPerformSwapReadError =>
      'Je keuzes voor ‘Een dans wisselen’ konden niet worden gelezen en kunnen nu niet worden gewijzigd. Sluit dit scherm en probeer het opnieuw.';

  @override
  String get collectionRepertoireMenuItem => 'Repertoire';

  @override
  String get repertoireTitle => 'Repertoire';

  @override
  String get repertoireLoadError => 'Je repertoire kon niet worden berekend';

  @override
  String get repertoirePeriodLabel => 'Periode';

  @override
  String get repertoirePeriodAllTime => 'Altijd';

  @override
  String repertoirePeriodMonths(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Afgelopen $count maanden',
      one: 'Afgelopen maand',
    );
    return '$_temp0';
  }

  @override
  String get repertoirePeriodSinceDate => 'Sinds een datum…';

  @override
  String repertoirePeriodSince(String date) {
    return 'Sinds $date';
  }

  @override
  String get repertoireTypeLabel => 'Type';

  @override
  String get repertoireTypeAll => 'Alle soorten';

  @override
  String repertoireSummary(int calls, int called, int total) {
    return 'Keer gecalld in deze periode: $calls. Dansen gecalld: $called van $total.';
  }

  @override
  String get repertoireMostCalledHeader => 'Vaakst gecalld';

  @override
  String get repertoireLeastCalledHeader =>
      'Minst gecalld (van wat je hebt gecalld)';

  @override
  String get repertoireLeastCalledAllShown =>
      'Elke dans die je in deze periode hebt gecalld, staat al onder Vaakst gecalld.';

  @override
  String get repertoireNoCalls => 'Niets gecalld in deze periode.';

  @override
  String repertoireDanceCalls(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count keer gecalld',
      one: 'één keer gecalld',
    );
    return '$_temp0';
  }

  @override
  String repertoireDanceSemantics(String title, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count keer gecalld',
      one: 'één keer gecalld',
    );
    return '$title: $_temp0';
  }

  @override
  String get repertoireNeverCalledHeader => 'Nooit gecalld';

  @override
  String get repertoireNeverCalledLabel => 'Nooit gecalld';

  @override
  String repertoireOfDances(int count, int total) {
    return '$count van $total dansen';
  }

  @override
  String repertoireNeverCalledSemantics(int count, int total) {
    return 'Nooit gecalld: $count van $total dansen';
  }

  @override
  String repertoireNeverCalledDanceSemantics(String title) {
    return '$title: nooit gecalld';
  }

  @override
  String get repertoireNotCalledInPeriodLabel => 'Niet gecalld in deze periode';

  @override
  String repertoireNotCalledInPeriodSemantics(int count, int total) {
    return 'Niet gecalld in deze periode: $count van $total dansen';
  }

  @override
  String get repertoireFigureHeader => 'Hoe vaak figuren voorkomen';

  @override
  String get repertoireNoFigures =>
      'Geen van deze dansen heeft ingevoerde figuren.';

  @override
  String repertoireFigureValue(int dances, int total, int percent, int calls) {
    String _temp0 = intl.Intl.pluralLogic(
      calls,
      locale: localeName,
      other: '$calls keer gecalld',
      one: '1 keer gecalld',
    );
    return 'in $dances van $total dansen ($percent%) · $_temp0';
  }

  @override
  String repertoireFigureSemantics(
    String move,
    int dances,
    int total,
    int percent,
    int calls,
  ) {
    String _temp0 = intl.Intl.pluralLogic(
      calls,
      locale: localeName,
      other: '$calls keer gecalld',
      one: '1 keer gecalld',
    );
    return '$move: in $dances van $total dansen, $percent procent; $_temp0 in deze periode';
  }

  @override
  String repertoireShowAll(int count) {
    return 'Alle $count tonen';
  }

  @override
  String get repertoireShowFewer => 'Minder tonen';

  @override
  String get repertoireAuthorsHeader => 'Auteurs van wie je dansen callt';

  @override
  String repertoireAuthorsSummary(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count auteurs gecalld in deze periode.',
      one: '1 auteur gecalld in deze periode.',
      zero: 'Geen auteur gecalld in deze periode.',
    );
    return '$_temp0';
  }

  @override
  String repertoireShareValue(int calls, int percent) {
    String _temp0 = intl.Intl.pluralLogic(
      calls,
      locale: localeName,
      other: '$calls keer gecalld',
      one: '1 keer gecalld',
    );
    return '$_temp0 ($percent%)';
  }

  @override
  String repertoireShareSemantics(String label, int calls, int percent) {
    String _temp0 = intl.Intl.pluralLogic(
      calls,
      locale: localeName,
      other: '$calls keer gecalld',
      one: '1 keer gecalld',
    );
    return '$label: $_temp0, $percent procent van wat in deze periode is gecalld';
  }

  @override
  String get repertoireFormationHeader => 'Formaties';

  @override
  String get repertoireVenuesHeader => 'Herhalingen per locatie';

  @override
  String get repertoireNoRepeats =>
      'Geen dans is in deze periode meer dan één keer op dezelfde locatie gecalld.';

  @override
  String get repertoireVenueUnnamed => 'Naamloze locatie';

  @override
  String repertoireVenueRepeats(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count dansen herhaald',
      one: '1 dans herhaald',
    );
    return '$_temp0';
  }

  @override
  String repertoireVenueSemantics(String venue, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count dansen meer dan één keer gecalld',
      one: '1 dans meer dan één keer gecalld',
    );
    return '$venue: $_temp0';
  }

  @override
  String get settingsExperimentalRepertoireHeader => 'Repertoire';

  @override
  String get settingsExperimentalShowRepertoireTitle => 'Repertoire';

  @override
  String get settingsExperimentalShowRepertoireSubtitle =>
      'Voegt Repertoire toe aan het menu Meer acties van de Collectie: je vaakst en minst gecallde dansen, wat je nooit hebt gecalld, hoe vaak figuren voorkomen, auteurs, formaties en herhalingen per locatie.';

  @override
  String get importSourceLabelCsv => 'Je eigen spreadsheet (CSV)';

  @override
  String get importCsvPickFile => 'CSV-bestand kiezen…';

  @override
  String get importSourceLabelTextDocument =>
      'Je eigen tekst- of Markdown-bestand';

  @override
  String get importTextHint =>
      'Kies een .txt- of .md-bestand. Begin elke dans met een kop (## Title), of met de titel na een lege regel. Zet details op regels met “Label: value” (Formation: Improper) en één figuur per regel (A1 (8) Neighbor swing).';

  @override
  String get importTextPickFile => 'Kies een tekst- of Markdown-bestand…';

  @override
  String get importTextMapTitle => 'Labels koppelen';

  @override
  String get importTextMapIntro =>
      'Kies wat elk label in je bestand bevat. Een label dat geen veld overneemt, blijft met zijn naam in de callnotities staan; kies Negeren om het weg te laten. Er wordt niets toegevoegd voordat je hebt nagekeken en bevestigd.';

  @override
  String get importTextDanceStartLabel => 'Elke dans begint bij';

  @override
  String importTextDanceStartHeading(String marks) {
    return 'Een $marks-kop';
  }

  @override
  String get importTextDanceStartBlankLine => 'Een titel na een lege regel';

  @override
  String get importTextTargetLabelledNotes => 'Callnotities, met het label';

  @override
  String get importTextNotUtf8 =>
      'Dit bestand is niet als UTF-8-tekst bewaard, dus letters met accenten zouden verkeerd binnenkomen. Bewaar het opnieuw als UTF-8-tekst en kies dat bestand.';

  @override
  String importTextTooManyDances(int limit) {
    final intl.NumberFormat limitNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String limitString = limitNumberFormat.format(limit);

    return 'Dit bestand bevat meer dan $limitString dansen. Splits het in kleinere bestanden.';
  }

  @override
  String importTextLineTooLong(int limit) {
    final intl.NumberFormat limitNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String limitString = limitNumberFormat.format(limit);

    return 'Een regel in dit bestand is langer dan $limitString tekens.';
  }

  @override
  String importTextDanceTooLong(int limit) {
    final intl.NumberFormat limitNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String limitString = limitNumberFormat.format(limit);

    return 'Een dans in dit bestand heeft meer dan $limitString tekens aan figuren, notities of één detail.';
  }

  @override
  String importTextTooManyLabels(int limit) {
    final intl.NumberFormat limitNumberFormat =
        intl.NumberFormat.decimalPattern(localeName);
    final String limitString = limitNumberFormat.format(limit);

    return 'Dit bestand gebruikt meer dan $limitString verschillende labels.';
  }

  @override
  String get importCsvSaveAsHint =>
      'Kies in je spreadsheetprogramma Bestand ▸ Opslaan als (of Downloaden) en ‘CSV UTF-8’, en kies dat bestand dan hier.';

  @override
  String get importCsvMapTitle => 'Kolommen koppelen';

  @override
  String get importCsvMapIntro =>
      'Kies wat elke kolom bevat. Kolommen op ‘Negeren’ worden weggelaten. Er wordt niets toegevoegd voordat je controleert en bevestigt.';

  @override
  String get importCsvSeparatorLabel => 'Scheidingsteken';

  @override
  String get importCsvSeparatorComma => 'Komma (,)';

  @override
  String get importCsvSeparatorSemicolon => 'Puntkomma (;)';

  @override
  String get importCsvSeparatorTab => 'Tab';

  @override
  String get importCsvFirstRowHeader => 'De eerste rij noemt de kolommen';

  @override
  String importCsvColumnFallback(int number) {
    return 'Kolom $number';
  }

  @override
  String get importCsvTargetIgnore => 'Negeren';

  @override
  String importCsvTargetPhrase(String phrase) {
    return 'Figuren, $phrase';
  }

  @override
  String importCsvTargetNewField(String type) {
    return 'Nieuw aangepast veld ($type)';
  }

  @override
  String importCsvTargetExistingField(String name) {
    return 'Eigen veld: $name';
  }

  @override
  String get importCsvNeedsTitle => 'Kies de kolom met de titel van elke dans.';

  @override
  String get importCsvContinue => 'Doorgaan';

  @override
  String get importCsvPreviewHeading => 'Eerste rijen';

  @override
  String get importCsvNotUtf8 =>
      'Dit bestand is niet als UTF-8-tekst opgeslagen, dus letters met accenten zouden verkeerd binnenkomen. Sla het in je spreadsheetprogramma opnieuw op als ‘CSV UTF-8’ en kies dat bestand.';

  @override
  String get importCsvTooLarge =>
      'Dit bestand is te groot om te importeren. Splits het in kleinere bestanden.';

  @override
  String importCsvTooManyRows(int limit) {
    return 'Dit bestand heeft meer dan $limit rijen. Splits het in kleinere bestanden.';
  }

  @override
  String importCsvTooManyColumns(int limit) {
    return 'Een rij in dit bestand heeft meer dan $limit kolommen.';
  }

  @override
  String importCsvCellTooLong(int limit) {
    return 'Een cel in dit bestand is langer dan $limit tekens.';
  }

  @override
  String get importCsvUnterminatedQuote =>
      'Dit bestand heeft een cel tussen aanhalingstekens die nooit eindigt, dus het kan niet worden gelezen.';

  @override
  String importCsvLargeBatch(int count) {
    return 'Dit bestand heeft $count rijen. Controleren kan even duren.';
  }

  @override
  String get importCsvNoRows =>
      'Dit bestand heeft geen rijen met dansen, alleen de kolomnamen.';

  @override
  String calendarImportUpdated(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count programma\'s bijgewerkt uit je agenda.',
      one: '1 programma bijgewerkt uit je agenda.',
    );
    return '$_temp0';
  }

  @override
  String get calendarImportReviewed =>
      'Agenda gecontroleerd. Er is niets toegevoegd of gewijzigd.';

  @override
  String calendarChangeDate(String before, String after) {
    return 'Datum: $before → $after';
  }

  @override
  String calendarChangeTitle(String before, String after) {
    return 'Titel: $before → $after';
  }

  @override
  String calendarChangeTime(String before, String after) {
    return 'Tijd: $before → $after';
  }

  @override
  String calendarChangeVenue(String before, String after) {
    return 'Locatie: $before → $after';
  }

  @override
  String get calendarImportUpdatedHeader => 'Bijgewerkt in je agenda';

  @override
  String get calendarImportChangedHeader => 'Gewijzigd in je agenda';

  @override
  String get calendarImportChangedBody =>
      'Je hebt aan deze programma\'s gewerkt, dus er verandert niets tenzij je het aanvinkt.';

  @override
  String get calendarImportFlaggedHeader =>
      'Geannuleerd of verdwenen uit je agenda';

  @override
  String get calendarImportFlaggedBody =>
      'Deze programma\'s blijven zoals ze zijn en krijgen een label. Archiveer of verwijder ze zelf als je ze niet meer nodig hebt.';

  @override
  String get calendarFlagCancelled => 'Geannuleerd in je agenda';

  @override
  String get calendarFlagMissing => 'Niet meer in je agenda';

  @override
  String get calendarFlagOther => 'Gemarkeerd door je agenda';

  @override
  String get calendarFlagFieldLabel => 'Agendamarkering';

  @override
  String get calendarClearFlag => 'Agendamarkering wissen';

  @override
  String get calendarClearFlagError =>
      'De agendamarkering kon niet worden gewist. Probeer het opnieuw.';

  @override
  String get calendarOnStartupTitle => 'Agenda importeren als de app start';

  @override
  String get calendarOnStartupSubtitle =>
      'Standaard uit. Als het aan staat, leest de app je agenda één keer bij elke start en meldt niets als dat niet lukt.';

  @override
  String get calendarStartupModeTitle => 'Bij het starten';

  @override
  String get calendarStartupModeReport => 'Nieuwe afspraken melden';

  @override
  String get calendarStartupModeAdd => 'Toevoegen als concept';

  @override
  String get calendarStartupModeReportSubtitle =>
      'Meldt nieuwe afspraken; er wordt niets toegevoegd tot je ze hebt bekeken.';

  @override
  String get calendarStartupModeAddSubtitle =>
      'Voegt nieuwe afspraken toe als conceptprogramma\'s, met Ongedaan maken. Gewijzigde of geannuleerde afspraken worden alleen gemeld.';

  @override
  String calendarLastResultFailed(String when) {
    return 'Agenda niet bereikbaar bij het starten ($when)';
  }

  @override
  String calendarLastResultAdded(String when, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count concepten toegevoegd',
      one: '1 concept toegevoegd',
    );
    return 'Gecontroleerd bij het starten op $when: $_temp0';
  }

  @override
  String calendarLastResultNew(String when, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count nieuwe afspraken',
      one: '1 nieuwe afspraak',
      zero: 'geen nieuwe afspraken',
    );
    return 'Gecontroleerd bij het starten op $when: $_temp0';
  }

  @override
  String calendarStartupFailureNotice(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'De agenda was de laatste $count keer dat de app startte niet bereikbaar.',
    );
    return '$_temp0';
  }

  @override
  String get calendarStartupFailureHint =>
      'Controleer het agenda-adres of je verbinding.';

  @override
  String calendarStartupNewEvents(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count nieuwe afspraken in je agenda.',
      one: '1 nieuwe afspraak in je agenda.',
    );
    return '$_temp0';
  }

  @override
  String calendarStartupChanges(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count wijzigingen wachten op je.',
      one: '1 wijziging wacht op je.',
    );
    return '$_temp0';
  }

  @override
  String get calendarStartupShow => 'Tonen';

  @override
  String get calendarStartupReview => 'Bekijken';

  @override
  String calendarLastResultError(String when) {
    return 'Importeren uit de agenda bij het starten mislukt ($when)';
  }

  @override
  String get savedSearchSaveThis => 'Deze zoekopdracht opslaan…';

  @override
  String savedSearchUpdate(String name) {
    return '\"$name\" bijwerken';
  }

  @override
  String savedSearchRename(String name) {
    return '\"$name\" hernoemen…';
  }

  @override
  String savedSearchDelete(String name) {
    return '\"$name\" verwijderen';
  }

  @override
  String get savedSearchNeedsAttention => 'Vraagt aandacht';

  @override
  String get savedSearchUnreadableItem =>
      'Een opgeslagen zoekopdracht die niet te openen is';

  @override
  String get savedSearchUnreadableTitle =>
      'Deze opgeslagen zoekopdracht kan niet worden geopend';

  @override
  String get savedSearchUnreadableBody =>
      'Hij is opgeslagen door een nieuwere versie van de app, of hij is beschadigd, dus hij wordt niet gebruikt. Je kunt hem verwijderen en dat ongedaan maken.';

  @override
  String get savedSearchSaveDialogTitle => 'Deze zoekopdracht opslaan';

  @override
  String get savedSearchRenameDialogTitle =>
      'Opgeslagen zoekopdracht hernoemen';

  @override
  String get savedSearchNameLabel => 'Naam';

  @override
  String savedSearchWindowNotCalled(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Niet gecalld in de afgelopen $count maanden',
      one: 'Niet gecalld in de afgelopen maand',
    );
    return '$_temp0';
  }

  @override
  String savedSearchWindowCalled(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Gebeld in de afgelopen $count maanden',
      one: 'Gebeld in de afgelopen maand',
    );
    return '$_temp0';
  }

  @override
  String savedSearchWindowInert(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Bewaarde periode van de belgeschiedenis: de afgelopen $count maanden',
      one: 'Bewaarde periode van de belgeschiedenis: de afgelopen maand',
    );
    return '$_temp0';
  }

  @override
  String get savedSearchTooLargeTitle => 'Zoekopdracht te groot';

  @override
  String get savedSearchTooLargeBody =>
      'Deze zoekopdracht heeft te veel filters of rijen om op te slaan. Verwijder er een paar en sla hem dan opnieuw op.';

  @override
  String get savedSearchLimitTitle => 'Te veel opgeslagen zoekopdrachten';

  @override
  String savedSearchLimitBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Je kunt tot $count opgeslagen zoekopdrachten bewaren. Verwijder er een om een andere op te slaan.',
      one:
          'Je kunt 1 opgeslagen zoekopdracht bewaren. Verwijder die om een andere op te slaan.',
    );
    return '$_temp0';
  }

  @override
  String get savedSearchNameRefused =>
      'Die naam kan niet worden gebruikt. Probeer een andere.';

  @override
  String get savedSearchFailed =>
      'Dat lukte niet met je opgeslagen zoekopdrachten. Probeer het opnieuw.';

  @override
  String savedSearchSavedSnack(String name) {
    return '\"$name\" opgeslagen';
  }

  @override
  String savedSearchUpdatedSnack(String name) {
    return '\"$name\" bijgewerkt';
  }

  @override
  String savedSearchDeletedSnack(String name) {
    return '\"$name\" verwijderd';
  }

  @override
  String savedSearchInUseTitle(String name) {
    return '\"$name\" kan niet worden verwijderd';
  }

  @override
  String get savedSearchInUseBody =>
      'Hij wordt nog gebruikt door deze. Wijzig of verwijder die eerst en verwijder hem daarna.';

  @override
  String savedSearchNoticeTitle(String name) {
    return '\"$name\" gebruikt dingen die er niet meer zijn:';
  }

  @override
  String get savedSearchNoticeRest =>
      'De rest van de zoekopdracht wordt getoond. Verwijder deze zelf om hem bij te werken.';

  @override
  String get savedSearchNoticeFieldSkipped =>
      'Een filter op een verwijderd aangepast veld wordt bij de resultaten weggelaten.';

  @override
  String get savedSearchNoticeClose => 'Melding sluiten';

  @override
  String savedSearchMissingTag(String name) {
    return 'De tag $name, die is verwijderd';
  }

  @override
  String get savedSearchMissingTagUnnamed => 'Een tag die is verwijderd';

  @override
  String savedSearchMissingAuthor(String name) {
    return 'De auteur $name, die is verwijderd';
  }

  @override
  String get savedSearchMissingAuthorUnnamed => 'Een auteur die is verwijderd';

  @override
  String savedSearchMissingSource(String name) {
    return 'De bron $name, die is verwijderd';
  }

  @override
  String get savedSearchMissingSourceUnnamed => 'Een bron die is verwijderd';

  @override
  String savedSearchMissingLevel(String name) {
    return 'Het niveau $name, dat is verwijderd';
  }

  @override
  String get savedSearchMissingLevelUnnamed => 'Een niveau dat is verwijderd';

  @override
  String savedSearchMissingVenue(String name) {
    return 'De locatie $name, die is verwijderd';
  }

  @override
  String get savedSearchMissingVenueUnnamed => 'Een locatie die is verwijderd';

  @override
  String savedSearchMissingField(String name) {
    return 'Het aangepaste veld $name, dat is verwijderd';
  }

  @override
  String get savedSearchMissingFieldUnnamed =>
      'Een aangepast veld dat is verwijderd';

  @override
  String savedSearchMissingFieldType(String name) {
    return 'Het aangepaste veld $name, waarvan het type is veranderd';
  }

  @override
  String savedSearchMissingFieldChoice(String choice, String name) {
    return 'De keuze $choice van $name, die is verwijderd';
  }

  @override
  String get savedSearchMissingFigureDetail =>
      'Een figuurdetail in Geavanceerd dat niet kan worden getoond';

  @override
  String get savedSearchMissingUserFigure =>
      'Een eigen figuur die is verwijderd';

  @override
  String get savedSearchMissingInvalid => 'Iets wat deze versie niet kan lezen';

  @override
  String savedSearchSearchFor(String text) {
    return 'Zoeken naar \"$text\"';
  }

  @override
  String savedSearchHighlightedRow(String name, int index, int count) {
    return '$name, $index van $count';
  }

  @override
  String get savedSearchSaveAsNewSearch => 'Opslaan als nieuwe zoekopdracht…';

  @override
  String get settingsCollectionTitle => 'Collectie';

  @override
  String get settingsSavedSearchesHeader => 'Opgeslagen zoekopdrachten';

  @override
  String get settingsSavedSearchesLoadError =>
      'Je opgeslagen zoekopdrachten konden niet worden geladen. Er is niets gewijzigd. Probeer het opnieuw.';

  @override
  String get settingsSavedSearchesEmpty =>
      'Nog geen opgeslagen zoekopdrachten. Sla er een op vanuit de collectie: stel een zoekopdracht in en kies dan Deze zoekopdracht opslaan… in het menu Meer acties.';

  @override
  String settingsSavedSearchRenameTooltip(String name) {
    return '\"$name\" hernoemen';
  }

  @override
  String settingsSavedSearchDeleteTooltip(String name) {
    return '\"$name\" verwijderen';
  }

  @override
  String savedSearchGone(String name) {
    return '\"$name\" is verwijderd, hier of op een ander apparaat, dus er is niets gewijzigd.';
  }

  @override
  String get settingsExperimentalEventRulesHeader => 'Avondregels';

  @override
  String get settingsExperimentalEventRulesTitle =>
      'Programma\'s toetsen aan je regels';

  @override
  String get settingsExperimentalEventRulesSubtitle =>
      'Voeg regels toe aan een programma, bijvoorbeeld geen twee Becket-dansen achter elkaar, en de editor waarschuwt je wanneer het programma er een overtreedt. Waarschuwingen houden je nooit tegen bij opslaan of callen.';

  @override
  String get settingsEventRulesCheckPerformSwapTitle =>
      'Controleren bij Deze dans wisselen in Uitvoeren';

  @override
  String get settingsEventRulesCheckPerformSwapSubtitle =>
      'Als je in Uitvoeren een dans wisselt, wordt elke dans die een van de regels van het programma zou breken gemarkeerd en als laatste getoond. Er valt niets weg.';

  @override
  String get eventRulesManageTitle => 'Regels beheren';

  @override
  String get eventRulesManageSubtitle =>
      'Je regels bekijken, toevoegen, bewerken, herschikken en verwijderen.';

  @override
  String get eventRulesEmpty =>
      'Nog geen regels. Een regel gebruikt een van je opgeslagen zoekopdrachten om te zeggen welke dansen hij bedoelt.';

  @override
  String get eventRulesNewRule => 'Nieuwe regel…';

  @override
  String get eventRuleDeletedSnack => 'Regel verwijderd.';

  @override
  String get eventRuleEditorNewTitle => 'Nieuwe regel';

  @override
  String get eventRuleEditorEditTitle => 'Regel bewerken';

  @override
  String get eventRuleSearchLabel => 'Welke dansen';

  @override
  String get eventRuleNoSavedSearches =>
      'Sla eerst een zoekopdracht op in de Collectie: een regel gebruikt een opgeslagen zoekopdracht om te zeggen welke dansen hij bedoelt.';

  @override
  String get eventRuleSavedSearchGone =>
      'Die opgeslagen zoekopdracht is net verwijderd, dus de regel is niet opgeslagen. Kies een andere.';

  @override
  String get eventRuleSaveFailed =>
      'Kan de regel niet opslaan. Probeer het opnieuw.';

  @override
  String eventRuleSaveLimit(int max) {
    return 'Dit apparaat heeft $max regels, het maximum. Verwijder er een om een andere toe te voegen.';
  }

  @override
  String get eventRuleSearchesUnreadable =>
      'Je opgeslagen zoekopdrachten kunnen nu niet worden gelezen, dus hier kan er geen worden gekozen.';

  @override
  String get eventRuleQuantifierLabel => 'Hoeveel';

  @override
  String get eventRuleQuantifierAtMost => 'Hoogstens';

  @override
  String get eventRuleQuantifierAtLeast => 'Minstens';

  @override
  String get eventRuleQuantifierNone => 'Geen';

  @override
  String get eventRuleCountLabel => 'Aantal dansen';

  @override
  String eventRuleCountInvalid(int max) {
    return 'Voer een geheel getal van 1 tot $max in.';
  }

  @override
  String get eventRuleCountOnlyOne =>
      'Voer 1 in, het enige toegestane getal hier.';

  @override
  String get eventRuleScopeLabel => 'Waar';

  @override
  String get eventRuleScopeWholeProgram => 'Het hele programma';

  @override
  String get eventRuleScopeBeforeFirstBreak => 'Voor de eerste pauze';

  @override
  String get eventRuleScopeAfterFirstBreak => 'Na de eerste pauze';

  @override
  String get eventRuleScopeNeighbouring => 'Elke twee aangrenzende dansen';

  @override
  String get eventRuleNicknameLabel => 'Bijnaam (optioneel)';

  @override
  String get eventRuleNicknameHelp =>
      'Wordt boven de zin van de regel getoond en gevonden door de zoekfunctie van de regelkiezer.';

  @override
  String eventRuleSpokenTitle(String nickname, String sentence) {
    return '$nickname ($sentence)';
  }

  @override
  String get eventRulesOrderTitle => 'Volgorde van regels';

  @override
  String get eventRulesOrderManual => 'Mijn volgorde';

  @override
  String get eventRulesOrderManualSubtitle =>
      'De regelkiezer toont je regels in de volgorde die je ze in Regels beheren hebt gegeven.';

  @override
  String get eventRulesOrderMostUsed => 'Meest gebruikt';

  @override
  String get eventRulesOrderMostUsedSubtitle =>
      'De regelkiezer toont eerst de regels die je programma\'s het meest gebruiken; programma\'s in Onlangs verwijderd tellen niet mee.';

  @override
  String eventRulesDragToReorder(String rule) {
    return 'Sleep om $rule te verplaatsen';
  }

  @override
  String eventRuleSentenceAtMostWhole(int count, String search) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Hoogstens $count dansen die passen bij \"$search\" in het hele programma',
      one: 'Hoogstens 1 dans die past bij \"$search\" in het hele programma',
    );
    return '$_temp0';
  }

  @override
  String eventRuleSentenceAtMostBefore(int count, String search) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Hoogstens $count dansen die passen bij \"$search\" voor de eerste pauze',
      one: 'Hoogstens 1 dans die past bij \"$search\" voor de eerste pauze',
    );
    return '$_temp0';
  }

  @override
  String eventRuleSentenceAtMostAfter(int count, String search) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Hoogstens $count dansen die passen bij \"$search\" na de eerste pauze',
      one: 'Hoogstens 1 dans die past bij \"$search\" na de eerste pauze',
    );
    return '$_temp0';
  }

  @override
  String eventRuleSentenceAtMostNeighbouring(int count, String search) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Hoogstens $count dansen die passen bij \"$search\" in elke twee aangrenzende dansen',
      one:
          'Hoogstens 1 dans die past bij \"$search\" in elke twee aangrenzende dansen',
    );
    return '$_temp0';
  }

  @override
  String eventRuleSentenceAtLeastWhole(int count, String search) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Minstens $count dansen die passen bij \"$search\" in het hele programma',
      one: 'Minstens 1 dans die past bij \"$search\" in het hele programma',
    );
    return '$_temp0';
  }

  @override
  String eventRuleSentenceAtLeastBefore(int count, String search) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Minstens $count dansen die passen bij \"$search\" voor de eerste pauze',
      one: 'Minstens 1 dans die past bij \"$search\" voor de eerste pauze',
    );
    return '$_temp0';
  }

  @override
  String eventRuleSentenceAtLeastAfter(int count, String search) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Minstens $count dansen die passen bij \"$search\" na de eerste pauze',
      one: 'Minstens 1 dans die past bij \"$search\" na de eerste pauze',
    );
    return '$_temp0';
  }

  @override
  String eventRuleSentenceAtLeastNeighbouring(int count, String search) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Minstens $count dansen die passen bij \"$search\" in elke twee aangrenzende dansen',
      one:
          'Minstens 1 dans die past bij \"$search\" in elke twee aangrenzende dansen',
    );
    return '$_temp0';
  }

  @override
  String eventRuleSentenceNoneWhole(String search) {
    return 'Geen dans die past bij \"$search\" in het hele programma';
  }

  @override
  String eventRuleSentenceNoneBefore(String search) {
    return 'Geen dans die past bij \"$search\" voor de eerste pauze';
  }

  @override
  String eventRuleSentenceNoneAfter(String search) {
    return 'Geen dans die past bij \"$search\" na de eerste pauze';
  }

  @override
  String eventRuleSentenceNoneNeighbouring(String search) {
    return 'Geen dans die past bij \"$search\" in elke twee aangrenzende dansen';
  }

  @override
  String get eventRuleSentenceUnreadable =>
      'Een regel uit een nieuwere versie van de app';

  @override
  String get eventRuleSearchUnknown => '…';

  @override
  String get eventRuleAttentionUnreadable =>
      'Gemaakt door een nieuwere versie van de app, dus hij wordt niet gecontroleerd.';

  @override
  String get eventRuleAttentionSearchGone =>
      'Zijn opgeslagen zoekopdracht is verwijderd of kan niet worden gelezen, dus hij wordt niet gecontroleerd.';

  @override
  String get eventRuleAttentionUnresolvable =>
      'Zijn opgeslagen zoekopdracht gebruikt dingen die er niet meer zijn, dus hij wordt niet gecontroleerd:';

  @override
  String programsRulesButton(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Regels ($count)',
      zero: 'Regels',
    );
    return '$_temp0';
  }

  @override
  String get programsRulesLabel => 'Regels';

  @override
  String get programsRulesPickerTitle => 'Regels voor dit programma';

  @override
  String get programsRulesPickerEmpty => 'Je hebt nog geen regels.';

  @override
  String get programsRulesPickerSearchHint => 'Regels zoeken';

  @override
  String get programsRulesPickerSearchClear => 'Zoekopdracht wissen';

  @override
  String programsRulesPickerNoMatches(String query) {
    return 'Geen regel komt overeen met \"$query\".';
  }

  @override
  String programsRulesPickerNewNamed(String nickname) {
    return 'Nieuwe regel \"$nickname\"…';
  }

  @override
  String programsRulesStripBroken(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count regels niet nageleefd',
      one: '1 regel niet nageleefd',
    );
    return '$_temp0';
  }

  @override
  String programsRulesStripAttention(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count regels vragen aandacht',
      one: '1 regel vraagt aandacht',
    );
    return '$_temp0';
  }

  @override
  String programsRuleBreachMatching(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count passende dansen',
      one: '1 passende dans',
      zero: 'Geen passende dansen',
    );
    return '$_temp0';
  }

  @override
  String programsRuleBreachPairs(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count paren aangrenzende dansen',
      one: '1 paar aangrenzende dansen',
    );
    return '$_temp0';
  }

  @override
  String programsRuleBreachDances(String titles) {
    return 'Dansen: $titles';
  }

  @override
  String programsRuleBreachIfCalled(String title) {
    return 'Als je $title callt';
  }

  @override
  String get programsSlotRuleMarker => 'Overtreedt een regel';

  @override
  String get programsSlotRuleMarkerAlternate =>
      'Overtreedt een regel als hij wordt gecalld';

  @override
  String programsSlotRuleMarkerSemantic(int count, String rules) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Overtreedt $count regels: $rules',
      one: 'Overtreedt de regel: $rules',
    );
    return '$_temp0';
  }

  @override
  String programsSlotRuleMarkerAlternateSemantic(int count, String rules) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Overtreedt $count regels als hij wordt gecalld: $rules',
      one: 'Overtreedt de regel als hij wordt gecalld: $rules',
    );
    return '$_temp0';
  }

  @override
  String get savedSearchInUseRulesOff =>
      'Avondregels staat uit, maar met Regels beheren kun je je regels nu wijzigen. Zet “Programma\'s toetsen aan je regels” aan onder Instellingen ▸ Experimenteel ▸ Avondregels om programma\'s aan je regels te toetsen.';

  @override
  String programsRulesPickerFull(int max) {
    return 'Dit programma gebruikt $max regels, het maximum. Vink er een uit om een andere toe te voegen.';
  }

  @override
  String get programTemplateRulesLabel => 'Regels';

  @override
  String get programTemplateRulesNone => 'Geen';

  @override
  String programTemplateDuplicateSearchGone(String label) {
    return 'Dupliceren is niet gelukt: de opgeslagen zoekopdracht van de slotregel “$label” is verwijderd. Bewerk of verwijder die regel en probeer het opnieuw.';
  }

  @override
  String get programTemplateSlotRuleNotSavedSearchGone =>
      'Die opgeslagen zoekopdracht is net verwijderd, dus de slotregel is niet opgeslagen.';

  @override
  String get programTemplateRulesHelp =>
      'Toegevoegd aan elk nieuw programma dat met dit sjabloon wordt gemaakt.';

  @override
  String programTemplateRuleRemoved(String rule) {
    return 'Verwijderd: $rule';
  }

  @override
  String get programTemplateRuleRemovedUnknown =>
      'Een regel die niet op dit apparaat staat';

  @override
  String get programTemplateRulesPickerTitle => 'Regels voor dit sjabloon';

  @override
  String programTemplateRulesPickerFull(int max) {
    return 'Dit sjabloon gebruikt $max regels, het maximum. Vink er een uit om een andere toe te voegen.';
  }

  @override
  String programsRulesPickerNotHere(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count regels niet op dit apparaat',
      one: '1 regel niet op dit apparaat',
    );
    return '$_temp0';
  }

  @override
  String get programsRulesPickerNotHereHelp =>
      'Toegevoegd op een ander apparaat en nog onderweg, of voorgoed weg. Verwijderen haalt ze van dit programma.';

  @override
  String get programTemplateRulesPickerNotHereHelp =>
      'Toegevoegd op een ander apparaat en nog onderweg, of voorgoed weg. Verwijderen haalt ze van dit sjabloon.';

  @override
  String get programsRulesPickerUnreadable =>
      'Je regels kunnen nu niet worden gelezen.';

  @override
  String get programsRulesChangeFailed =>
      'Kan de regels van dit programma niet wijzigen. Probeer het opnieuw.';

  @override
  String get eventRuleCountNeighbouringHelp =>
      'Twee aangrenzende dansen bevatten hoogstens 2 passende dansen.';

  @override
  String settingsSyncNoticeCountEventRule(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count avondregels',
      one: '1 avondregel',
    );
    return '$_temp0';
  }

  @override
  String get syncReviewKindEventRule => 'Avondregel';

  @override
  String get danceEditorFigureNeedsValues =>
      'Kies een waarde voor elk veld van deze figuur voordat je opslaat.';

  @override
  String get danceEditorSaveNeedsFigureValues =>
      'Sommige toegevoegde figuren hebben nog lege velden. Vul ze in om op te slaan.';

  @override
  String get programTemplateAddSlotRule => 'Slotregel toevoegen';

  @override
  String get programTemplateSlotRuleBadge => 'Slotregel';

  @override
  String programTemplateSlotEditTooltip(String name) {
    return '$name bewerken';
  }

  @override
  String programTemplateSlotDeleteTooltip(String name) {
    return '$name verwijderen';
  }

  @override
  String programTemplateSlotRuleSubtitle(String name) {
    return 'Gevuld uit de opgeslagen zoekopdracht \"$name\"';
  }

  @override
  String get programTemplateSlotRuleSearchGone =>
      'De opgeslagen zoekopdracht is verwijderd';

  @override
  String get programTemplateSlotRuleDialogTitle => 'Slotregel toevoegen';

  @override
  String get programTemplateSlotRuleDialogBody =>
      'Beschrijf een soort dans in plaats van er een te noemen. Een programma dat met dit sjabloon is gemaakt, toont het als een tijdelijke plek die je vult uit de opgeslagen zoekopdracht.';

  @override
  String get programTemplateSlotRuleLabel => 'Label';

  @override
  String get programTemplateSlotRuleLabelHint => 'Eenvoudige improper-opener';

  @override
  String get programTemplateSlotRuleSearch => 'Opgeslagen zoekopdracht';

  @override
  String get programTemplateSlotRuleNoSearches =>
      'Een slotregel gebruikt een opgeslagen zoekopdracht. Sla eerst een zoekopdracht op in Collectie en kies die dan hier.';

  @override
  String get programsPlaceholderSubtitle => 'Tijdelijke plek';

  @override
  String get programsFillPlaceholderButton => 'Vullen';

  @override
  String programsFillPlaceholderSemantics(String label) {
    return '\"$label\" met een dans vullen';
  }

  @override
  String programsFillSheetTitle(String label) {
    return '\"$label\" vullen';
  }

  @override
  String programsFillSearchGone(String label) {
    return 'De opgeslagen zoekopdracht voor \"$label\" is verwijderd, dus alle dansen worden getoond.';
  }

  @override
  String programsFillSearchUnresolvable(String label, String name) {
    return '\"$label\" kan de opgeslagen zoekopdracht \"$name\" niet gebruiken, omdat die dingen gebruikt die er niet meer zijn, dus alle dansen worden getoond:';
  }

  @override
  String savedSearchUsedBySlotRule(String rule, String template) {
    return 'De slotregel \"$rule\" in het sjabloon $template';
  }

  @override
  String get programTemplateSlotRuleSearchUnreadable =>
      'De opgeslagen zoekopdracht kan niet worden geopend';

  @override
  String get programTemplateSlotRuleEditTitle => 'Slotregel bewerken';

  @override
  String get programTemplateSlotRuleLabelBreak =>
      '\"Break\" markeert een pauze in het programma, dus een slotregel kan het niet als label gebruiken.';

  @override
  String programsFillSearchUnreadable(String label) {
    return 'De opgeslagen zoekopdracht voor \"$label\" kan niet worden geopend: die is opgeslagen door een nieuwere versie van de app, of is beschadigd. Alle dansen worden getoond.';
  }

  @override
  String get settingsExperimentalSeriesHeader => 'Weekenden en reeksen';

  @override
  String get settingsExperimentalSeriesTitle =>
      'Meerdere programma\'s samen controleren';

  @override
  String get settingsExperimentalSeriesSubtitle =>
      'Kies in de programmalijst Programma\'s selecteren onder Meer acties, selecteer er twee of meer, en zie één matrix over allemaal en de dansen die terugkomen. Er wordt niets nieuws opgeslagen.';

  @override
  String get programsSelectPrograms => 'Programma\'s selecteren';

  @override
  String programsSelectProgramLabel(String title) {
    return '$title selecteren';
  }

  @override
  String get programsCombinedView => 'Gecombineerde weergave';

  @override
  String get programsCombinedViewNeedsTwo =>
      'Selecteer minstens twee programma\'s';

  @override
  String get programsCombinedRepeatsTab => 'Herhalingen';

  @override
  String get programsCombinedLoadError =>
      'De programma\'s konden niet worden geladen. Er is niets gewijzigd. Probeer het opnieuw.';

  @override
  String get programsCombinedGoneTitle => 'Deze programma\'s bestaan niet meer';

  @override
  String get programsCombinedGoneBody =>
      'De programma\'s die je selecteerde zijn verwijderd. Ga terug naar de programmalijst om andere te kiezen.';

  @override
  String programsCombinedBlockLabel(String title, String date) {
    return '$title · $date';
  }

  @override
  String programsCombinedRowInProgram(String title, String program) {
    return '$title, in $program';
  }

  @override
  String get programsCombinedPdfTitle => 'Gecombineerde matrix';

  @override
  String get programsCombinedRepeatsEmptyTitle => 'Geen herhaalde dansen';

  @override
  String get programsCombinedRepeatsEmptyBody =>
      'Geen enkele dans komt in meer dan één van deze programma\'s voor.';

  @override
  String programsCombinedRepeatsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count dansen komen in meer dan één programma voor',
      one: '1 dans komt in meer dan één programma voor',
    );
    return '$_temp0';
  }

  @override
  String programsCombinedRepeatProgramCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'In $count programma\'s',
      one: 'In 1 programma',
    );
    return '$_temp0';
  }

  @override
  String get programsCombinedRepeatAlternateChip => 'Soms alleen alternatief';

  @override
  String programsCombinedRepeatUse(String program, String position) {
    return '$program: $position';
  }

  @override
  String programsCombinedPositionDance(int number) {
    return 'dans $number';
  }

  @override
  String programsCombinedPositionAlternateFor(int number) {
    return 'alternatief voor dans $number';
  }

  @override
  String get programsCombinedPositionAlternate => 'alternatief';

  @override
  String get programsCombinedRepeatAlternateEverywhereChip =>
      'Alleen alternatief';
}
