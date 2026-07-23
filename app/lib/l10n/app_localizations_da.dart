// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Danish (`da`).
class AppLocalizationsDa extends AppLocalizations {
  AppLocalizationsDa([String locale = 'da']) : super(locale);

  @override
  String get appTitle => 'Caller\'s Compendium';

  @override
  String get navCollection => 'Samling';

  @override
  String get navPrograms => 'Programmer';

  @override
  String get navSettings => 'Indstillinger';

  @override
  String get navGuide => 'Vejledning';

  @override
  String get navGuideTooltip => 'Brugervejledning';

  @override
  String get navSearch => 'Søg';

  @override
  String navSearchTooltip(String hint) {
    return 'Søg ($hint)';
  }

  @override
  String get appBootstrapPreparing => 'Forbereder din samling';

  @override
  String get appBootstrapRebuildingIndex => 'Genopbygger søgeindeks';

  @override
  String appBootstrapRebuildingIndexProgress(int percent) {
    return 'Genopbygger søgeindeks… $percent%';
  }

  @override
  String get appBootstrapError => 'Kunne ikke forberede samlingen.';

  @override
  String get confirmDeleteTitle => 'Slet?';

  @override
  String confirmDeleteBody(String itemLabel) {
    return '„$itemLabel“ slettes. Du kan fortryde dette.';
  }

  @override
  String get colorEditHexLabel => 'Hex';

  @override
  String get settingsTitle => 'Indstillinger';

  @override
  String get commonSystemDefault => 'Systemstandard';

  @override
  String get commonComingSoon => 'Kommer snart';

  @override
  String get settingsLanguageRegionTitle => 'Sprog og region';

  @override
  String get settingsRegionalFormatsHeader => 'Formater';

  @override
  String get settingsRegionalLanguageHeader => 'Sprog';

  @override
  String get settingsDateFormatTitle => 'Datoformat';

  @override
  String settingsDateFormatSubtitle(String example) {
    return 'Hvordan programdatoer vises. Eksempel: $example';
  }

  @override
  String get settingsDateFormatYmd => 'År-måned-dag (2026-07-15)';

  @override
  String get settingsDateFormatDmy => 'Dag/måned/år (15/07/2026)';

  @override
  String get settingsDateFormatMdy => 'Måned/dag/år (07/15/2026)';

  @override
  String get settingsFirstDayOfWeekTitle => 'Ugens første dag';

  @override
  String get settingsFirstDayOfWeekSubtitle =>
      'Hvilken dag ugen starter på i appens datovisninger. Kommer i en fremtidig opdatering.';

  @override
  String get settingsAppLanguageTitle => 'Appsprog';

  @override
  String get settingsAppLanguageSubtitle =>
      'Vælg sproget for appens grænseflade.';

  @override
  String get settingsAboutHelpHeader => 'Hjælp';

  @override
  String get settingsAboutUserGuideTitle => 'Brugervejledning';

  @override
  String get settingsAboutUserGuideSubtitle =>
      'Læs de indbyggede vejledninger – kom i gang, dialekter, import og mere. Virker offline.';

  @override
  String get settingsAboutLicenseHeader => 'Licens';

  @override
  String get settingsAboutLicenseBody =>
      'Caller\'s Compendium er fri software, licenseret under GNU Affero General Public License, version 3 (AGPL-3.0). Du er fri til at bruge, studere, dele og ændre det under den licens. Da AGPL kræver det, tilbydes den komplette tilsvarende kildekode til alle, der bruger appen.';

  @override
  String get settingsAboutViewSourceTitle => 'Se kildekode på GitHub';

  @override
  String get settingsAboutFontsHeader => 'Skrifttyper';

  @override
  String get settingsAboutFontsBody =>
      'Denne app inkluderer følgende skrifttyper under SIL Open Font License 1.1. De fulde licensetekster er tilgængelige under \"Se licenser\" nedenfor.';

  @override
  String get settingsAboutFontFrauncesSubtitle =>
      'SIL Open Font License 1.1 · © The Fraunces Project Authors — skærm og overskrifter';

  @override
  String get settingsAboutFontAtkinsonSubtitle =>
      'SIL Open Font License 1.1 · © Braille Institute of America, Inc. — brødtekst, UI og Perform';

  @override
  String get settingsAboutFontRobotoSubtitle =>
      'SIL Open Font License 1.1 · © The Roboto Project Authors — reserveskrifttype';

  @override
  String get settingsAboutThemesHeader => 'Temaer';

  @override
  String get settingsAboutThemesBody =>
      'Flere valgfri farvetemaer er inspireret af populære kodeeditor-paletter – heriblandt One Dark, Dracula, Nord, Tokyo Night, Gruvbox og Catppuccin – genafledt og kontrasttilpasset til denne app. Temanavne bruges kun for at kreditere denne inspiration.';

  @override
  String get settingsAboutDanceDataHeader => 'Dansdata';

  @override
  String get settingsAboutDanceDataBody =>
      'Dansdata trækker på The Caller\'s Box (Chris Page & Michael Dyck), hvis samling er udgivet under Creative Commons Attribution-NonCommercial-licensen (CC BY-NC), med taknemmelighed.';

  @override
  String get settingsAboutLicensesHeader => 'Licenser';

  @override
  String get settingsAboutViewLicensesTitle => 'Se licenser';

  @override
  String get settingsAboutViewLicensesSubtitle =>
      'Fulde open source-licensetekster, inkl. de medfølgende skrifttyper.';

  @override
  String get settingsAboutLegalese =>
      '© The Caller\'s Compendium contributors. Licenseret under AGPL-3.0.';

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
  String get settingsUpdatesHeader => 'Opdateringer';

  @override
  String get settingsUpdatesCheckNowTitle => 'Søg efter opdateringer';

  @override
  String settingsUpdatesStatusIdle(String version) {
    return 'Du bruger version $version.';
  }

  @override
  String get settingsUpdatesStatusChecking => 'Søger…';

  @override
  String settingsUpdatesStatusNoUpdate(String version) {
    return 'Ingen opdatering fundet. Du bruger version $version.';
  }

  @override
  String settingsUpdatesStatusAvailable(String version) {
    return 'Version $version er tilgængelig. Se banneret for at se den.';
  }

  @override
  String get settingsUpdatesChannelHeader => 'Kanal';

  @override
  String get settingsUpdatesBetaTitle => 'Betakanal';

  @override
  String get settingsUpdatesBetaSubtitle =>
      'Modtag foreløbige betaopdateringer. Fra betyder kun stabile udgivelser.';

  @override
  String get settingsUpdatesAutoHeader => 'Automatiske tjek';

  @override
  String get settingsUpdatesAutoTitle => 'Tjek automatisk';

  @override
  String get settingsUpdatesAutoSubtitle =>
      'Tjek for en nyere version i baggrunden, når appen starter. Fra som standard.';

  @override
  String get settingsUpdatesPrivacyNote =>
      'Opdateringstjekket henter en lille versionsfil over HTTPS og intet andet – der sendes ingen oplysninger om dig, din enhed eller din brug. Intet hentes eller installeres automatisk: du vælger, hvornår du vil hente en opdatering, den verificeres inden den åbnes, og dit systeminstallationsprogram fuldfører installationen.';

  @override
  String get settingsUpdatesDownloadingTitle => 'Henter opdatering';

  @override
  String get settingsUpdatesDownloadingIndeterminate => 'Henter…';

  @override
  String settingsUpdatesDownloadingPercent(int percent) {
    return 'Henter… $percent%';
  }

  @override
  String get settingsUpdatesVerifyingTitle => 'Verificerer download';

  @override
  String get settingsUpdatesVerifyingSubtitle =>
      'Kontrollerer downloadens sha256-integritet…';

  @override
  String get settingsUpdatesHandoffTitle =>
      'Forbereder installationsprogrammet';

  @override
  String get settingsUpdatesHandoffSubtitle =>
      'Sender den verificerede opdatering til dit system…';

  @override
  String get settingsUpdatesCompletedTitle => 'Opdatering hentet';

  @override
  String get settingsUpdatesCompletedSubtitle =>
      'Følg dit systeminstallationsprogram for at fuldføre opdateringen.';

  @override
  String get settingsUpdatesCompletedSubtitleRevealed =>
      'Verificeret og vist i din filhåndtering – kør installationsprogrammet for at fuldføre opdateringen.';

  @override
  String get settingsUpdatesDownloadTitle => 'Hent og installer opdatering';

  @override
  String get settingsUpdatesDownloadError => 'Opdateringen kunne ikke hentes.';

  @override
  String settingsUpdatesDownloadSubtitle(String version) {
    return 'Hent version $version, verificer den, og åbn derefter dit installationsprogram. Appen erstatter aldrig sig selv på stedet.';
  }

  @override
  String get settingsDialectHeader => 'Dialekter';

  @override
  String get settingsDialectNewButton => 'Ny dialekt';

  @override
  String get settingsDialectNewDefaultName => 'Min dialekt';

  @override
  String get settingsDialectCreateConfirm => 'Opret';

  @override
  String get settingsDialectDuplicateFrom => 'Kopier fra…';

  @override
  String get settingsDialectRenameTitle => 'Omdøb dialekt';

  @override
  String get settingsDialectRename => 'Omdøb';

  @override
  String get settingsDialectEditTerms => 'Rediger termer';

  @override
  String get settingsDialectDuplicateToCustomize => 'Kopier for at tilpasse';

  @override
  String get settingsDialectDeleteTitle => 'Slet dialekt?';

  @override
  String settingsDialectDeleteConfirmBody(String name) {
    return '„$name“ fjernes permanent.';
  }

  @override
  String get settingsDialectActionsTooltip => 'Dialekthandlinger';

  @override
  String get settingsDialectPresetBadge => 'Forudindstillet';

  @override
  String get settingsDialectNameLabel => 'Navn';

  @override
  String get settingsAppearanceThemeHeader => 'Tema';

  @override
  String get settingsAppearanceCustomThemesHeader => 'Brugerdefinerede temaer';

  @override
  String get settingsAppearanceEasterEggsHeader => 'Påskeæg';

  @override
  String get settingsAppearanceSetListsHeader => 'Sætlister';

  @override
  String get settingsAppearanceFormationColoursHeader => 'Formationsfarver';

  @override
  String get settingsAppearanceColourDanceTitle =>
      'Farvenavngivne danse farver temaet';

  @override
  String get settingsAppearanceColourDanceSubtitle =>
      'En legende overraskelse: når du åbner en dans, hvis titel nævner en farve – som Baby Rose eller Blue Boy – farvetones visningen i den farve. Fra som standard, og den træder til side, når et højkontrast-tema er aktivt, så læsbarheden altid vinder.';

  @override
  String get settingsAppearanceSetListColorTitle => 'Farvekod sætlistrækker';

  @override
  String get settingsAppearanceSetListColorSubtitle =>
      'Farveton hver dansrække efter dens formationsfamilie (contra, mixer, firkantet dans, …). Formationen vises altid som tekst, så rækkerne forbliver læsbare uden farver.';

  @override
  String get settingsAppearanceFormationColoursTitle =>
      'Formationsetiketfarver';

  @override
  String get settingsAppearanceFormationColoursSubtitle =>
      'Fremhæv individuelle formationer i dine egne farver – f.eks. Becket (CW) i gult, Becket (CCW) i lyserødt – på danskort, dansdetaljer og Perform-overskriften.';

  @override
  String get settingsAppearanceSelectedBadge => 'Valgt';

  @override
  String get settingsAppearancePreviewHeading => 'Aa Forhåndsvisning';

  @override
  String get settingsAppearancePreviewBody => 'Eksempel på brødtekst';

  @override
  String get settingsAppearanceNewThemeButton => 'Nyt brugerdefineret tema';

  @override
  String get settingsAppearanceNewThemeDefaultName => 'Mit tema';

  @override
  String get settingsAppearanceCustomThemesEmpty =>
      'Kopier det aktuelle tema og juster en vilkårlig farve. Brugerdefinerede temaer gemmes på denne enhed.';

  @override
  String get settingsAppearanceDeleteThemeTitle => 'Slet tema?';

  @override
  String settingsAppearanceDeleteThemeBody(String name) {
    return '„$name“ fjernes permanent.';
  }

  @override
  String settingsAppearanceCustomThemeSemantic(String name) {
    return 'Brugerdefineret tema $name';
  }

  @override
  String get settingsAppearanceThemeActionsTooltip => 'Temahandlinger';

  @override
  String get settingsDefaultsProgramHeader => 'Programstandarder';

  @override
  String get settingsDefaultsCallerLabel => 'Standard-caller';

  @override
  String get settingsDefaultsPrefilledHelper =>
      'Udfyldes i nye programmer; kan redigeres per program.';

  @override
  String get settingsDefaultsBandLabel => 'Standardband';

  @override
  String get settingsDefaultsDisplayHeader => 'Visningsstandarder';

  @override
  String get settingsDefaultsSortTitle => 'Samlingens sorteringsrækkefølge';

  @override
  String get settingsDefaultsSortSubtitle =>
      'Hvordan samlingen sorteres, når du åbner den. Du kan stadig ændre sorteringen under gennemsynet.';

  @override
  String get settingsDefaultsCanonicalTitle =>
      'Åbn dansdetaljer med kanoniske termer';

  @override
  String get settingsDefaultsCanonicalSubtitle =>
      'Når aktiveret åbner en dans med kanoniske rolle- og bevægelsesnavne i stedet for din aktive dialekt. Du kan stadig skifte visning, mens dansen er åben.';

  @override
  String get settingsDefaultsAuthoringHeader => 'Standarder for dansforfatning';

  @override
  String get settingsDefaultsFreeTextEntryTitle => 'Fri tekstindtastning';

  @override
  String get settingsDefaultsFreeTextEntrySubtitle =>
      'Når aktiveret kan du ved tilføjelse af en ny figur skrive den som én linje (f.eks. \"nabo balance & swing\") i stedet for at bygge den felt for felt. Linjen parses til figur(er); alt der ikke genkendes gemmes som en brugerdefineret figur, du kan rette senere. Redigering af en eksisterende figur bruger altid den fulde editor.';

  @override
  String get settingsDefaultsFigureShorthandsTitle => 'Figurkortformer';

  @override
  String get settingsDefaultsFigureShorthandsEmptySubtitle =>
      'Map korte tokens til en eller flere figurer, du kan indsætte under fri tekstindtastning.';

  @override
  String settingsDefaultsFigureShorthandsCountSubtitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count kortformer defineret.',
      one: '1 kortform defineret.',
    );
    return '$_temp0';
  }

  @override
  String get settingsDefaultsFormTitle => 'Form';

  @override
  String get settingsDefaultsFormSubtitle =>
      'Den dansform en ny dans starter som. Du kan stadig ændre det per dans.';

  @override
  String get settingsDefaultsFormationTitle => 'Formation';

  @override
  String get settingsDefaultsFormationSubtitle =>
      'Den formation en ny dans starter i. Du kan stadig ændre det per dans.';

  @override
  String get settingsDefaultsProgressionTitle => 'Progression';

  @override
  String get settingsDefaultsProgressionSubtitle =>
      'Den progression en ny dans starter med. Du kan stadig ændre det per dans.';

  @override
  String get settingsDefaultsPhraseLabel => 'Standard frastruktur';

  @override
  String get settingsDefaultsPhraseHelper =>
      'Sås i nye danse. Tom = standard 4×16 (A1 A2 B1 B2); ellers f.eks. 6*8*2.';

  @override
  String get settingsDefaultsStartingFiguresTitle => 'Startfigurer';

  @override
  String get settingsDefaultsStartingFiguresSubtitle =>
      'De figurer en ny dans starter med. Standard er en enkelt stand still (8 slag); ryd for en blank ny dans. Kan redigeres per dans.';

  @override
  String get settingsDefaultsMoveDefaultsTitle => 'Bevægelsesstandarder';

  @override
  String get settingsDefaultsMoveDefaultsSubtitle =>
      'Foretrukne parameterværdier der anvendes, når du indsætter en bevægelse under dansinputet. Disse tilsidesætter bevægelsens indbyggede standarder; du kan stadig ændre enhver parameter på figuren bagefter. Ikke-angivne bevægelser og parametre bruger de indbyggede standarder.';

  @override
  String get settingsDefaultsAddMoveButton => 'Tilføj bevægelsestandard';

  @override
  String get settingsDefaultsRemoveMoveTooltip => 'Fjern';

  @override
  String get settingsDefaultsMoveGone =>
      'Denne bevægelse er ikke længere i taksonomien.';

  @override
  String get settingsDefaultsMoveNoParams =>
      'Denne bevægelse har ingen parametre at angive standard for.';

  @override
  String get settingsFormationColoursTitle => 'Formationsfarver';

  @override
  String get settingsFormationColoursIntro =>
      'Giv en formation sin egen farve for at fremhæve dens etiket på danskort, dansdetaljer og Perform-overskriften. Kun de formationer, du tilpasser, fremhæves; de øvrige viser deres etiket som normalt. Formationen vises altid som tekst, så etiketter forbliver læsbare uden farver.';

  @override
  String get settingsFormationColoursListHeader => 'Formationer';

  @override
  String get settingsFormationColoursCustom => 'Brugerdefineret farve';

  @override
  String get settingsFormationColoursFamilyDefault => 'Familiestandard';

  @override
  String settingsFormationColoursResetTooltip(String label) {
    return 'Nulstil $label til familiestandarden';
  }

  @override
  String get settingsGeneralLibraryHeader => 'Bibliotek';

  @override
  String get settingsGeneralSortIgnoreArticlesTitle =>
      'Ignorer foranstillede artikler ved sortering';

  @override
  String get settingsGeneralSortIgnoreArticlesSubtitle =>
      'Når aktiveret alfabetiserer danslisten titler og ignorerer et foranstillet \"the\", \"a\" eller \"an\" – så \"The Nice Combination\" arkiveres under N. Deaktiver for at sortere efter den bogstavelige titel.';

  @override
  String get settingsGeneralVenuesHeader => 'Spillesteder';

  @override
  String get settingsGeneralVenueEntityModeTitle =>
      'Brug genanvendelige spillestedsposter';

  @override
  String get settingsGeneralVenueEntityModeSubtitle =>
      'Gør spillesteder til genanvendelige poster med adresse, kontakter og tidsplan, som mange programmer kan dele og du redigerer ét sted. Når deaktiveret er et programs spillested et simpelt fritekstfelt. Skiftet er tabsfrit – dit indtastede spillested og eventuel tilknyttet post bevares begge.';

  @override
  String get settingsGeneralManageVenuesTitle => 'Administrer spillesteder';

  @override
  String get settingsGeneralManageVenuesSubtitle =>
      'Gennemse, rediger og slet dine genanvendelige spillestedsposter.';

  @override
  String get settingsGeneralPerformanceHeader => 'Performance';

  @override
  String get settingsGeneralAutoSizePerformTitle =>
      'Auto-størrelse Perform-kort';

  @override
  String get settingsGeneralAutoSizePerformSubtitle =>
      'Skalér hvert kort, så den fulde dans eller slot passer på skærmen uden at skulle rulle. Deaktiver for at angive størrelsen selv med A- / A+.';

  @override
  String get settingsGeneralCallingHistoryHeader => 'Kaldshistorik';

  @override
  String get settingsGeneralRequirePerformedForHistoryTitle =>
      'Kræv \"markeret som fremført\" til kaldshistorik';

  @override
  String get settingsGeneralRequirePerformedForHistorySubtitle =>
      'Når aktiveret viser en dans\' kaldshistorik kun programmer, hvis slot for den dans er markeret som fremført. Når deaktiveret vises et program, så snart det indeholder dansen.';

  @override
  String get settingsGeneralAccessibilityHeader => 'Tilgængelighed';

  @override
  String get settingsGeneralReduceMotionTitle => 'Reducer bevægelse';

  @override
  String get settingsGeneralReduceMotionSubtitle =>
      'Dæmp eller spring ikke-essentielle animationer over, f.eks. animeret rulning ved flytning mellem søgeresultater eller figurer.';

  @override
  String get settingsGeneralVerboseFiguresTitle =>
      'Vis altid udvidet figurtekst';

  @override
  String get settingsGeneralVerboseFiguresSubtitle =>
      'Vis den fulde talte figurtekst på skærmen i dansvisningen, ikke kun til skærmlæsere. Deaktiver for den korte notation.';

  @override
  String get settingsGeneralDecimalTurnsTitle =>
      'Vis drejninger som decimaltal';

  @override
  String get settingsGeneralDecimalTurnsSubtitle =>
      'Vis dreje- og rotationsbeløb som decimaltal (0,75) i stedet for brøker (¾). Skærmlæserteksten er upåvirket.';

  @override
  String get settingsGeneralConfirmBeforeDeleteTitle => 'Bekræft før sletning';

  @override
  String get settingsGeneralConfirmBeforeDeleteSubtitle =>
      'Bed om bekræftelse inden sletning af en dans eller et program. Sletninger kan stadig fortrydes; dette tilføjer blot en eksplicit prompt først.';

  @override
  String get settingsGeneralDeletedItemsHeader => 'Slettede elementer';

  @override
  String get settingsGeneralSoftDeleteRetentionTitle =>
      'Behold slettede danse i';

  @override
  String get settingsGeneralSoftDeleteRetentionSubtitle =>
      'Slettede danse bevares i denne periode, inden de fjernes permanent ved appopstart. Aldrig bevarer dem, indtil du renser manuelt.';

  @override
  String settingsGeneralSoftDeleteRetentionDays(int days) {
    return '$days dage';
  }

  @override
  String get settingsGeneralSoftDeleteRetentionNever => 'Aldrig';

  @override
  String get settingsGeneralImportHeader => 'Import';

  @override
  String get settingsGeneralImportDancesSubtitle =>
      'Tilføj danse til din samling fra en Caller\'s Compendium JSON-fil. Du gennemgår hver dans og bekræfter, inden noget tilføjes.';

  @override
  String get settingsGeneralImportEllipsisAction => 'Importér…';

  @override
  String get settingsGeneralReparseCustomFiguresTitle =>
      'Genkontrollér brugerdefinerede figurer';

  @override
  String get settingsGeneralReparseCustomFiguresSubtitle =>
      'Genpars importerede danse, hvis figurer kun er gemt som brugerdefinerede, fordi de ikke kunne genkendes ved importtidspunktet. Forbedret parsing opgraderer dem på stedet – dine tags, vurderinger og noter bevares. Du forhåndsviser og bekræfter, inden noget ændres.';

  @override
  String get settingsGeneralReparseCustomFiguresAction => 'Genkontrollér…';

  @override
  String get settingsGeneralBackupRestoreHeader =>
      'Sikkerhedskopiering og gendannelse';

  @override
  String get backupEncryptingProgress => 'Krypterer sikkerhedskopi…';

  @override
  String get backupEncryptedExported => 'Krypteret sikkerhedskopi eksporteret.';

  @override
  String get backupExported => 'Sikkerhedskopi eksporteret.';

  @override
  String get backupExportFailed => 'Kunne ikke eksportere en sikkerhedskopi.';

  @override
  String get backupDecryptingProgress => 'Dekrypterer sikkerhedskopi…';

  @override
  String get backupDecryptFailed =>
      'Kunne ikke dekryptere sikkerhedskopien. Dine data er uændret.';

  @override
  String get backupRestoreIncompatibleVersion =>
      'Denne sikkerhedskopi indeholder elementer, som denne version af appen ikke kan læse (den kan stamme fra en nyere version), så gendannelsen blev annulleret. Dine data er uændret.';

  @override
  String get backupRestoreInvalidFile =>
      'Kunne ikke gendanne: filen er ikke en gyldig sikkerhedskopi. Dine data er uændret.';

  @override
  String backupRestoreSkippedProblems(int count) {
    return 'Sikkerhedskopi gendannet med $count problem(er) sprunget over.';
  }

  @override
  String get backupRestored => 'Sikkerhedskopi gendannet.';

  @override
  String get backupRestoreFailed => 'Kunne ikke gendanne sikkerhedskopien.';

  @override
  String get backupExportTitle => 'Eksportér en sikkerhedskopi';

  @override
  String get backupExportSubtitle =>
      'Gem hele din samling, programmer, brugerdefinerede felter, dialekter, temaer og indstillinger i én JSON-fil, du kan opbevare sikkert eller flytte til en anden enhed.';

  @override
  String get backupExportAction => 'Eksportér';

  @override
  String get backupRestoreTitle => 'Gendan fra en sikkerhedskopi';

  @override
  String get backupRestoreSubtitle =>
      'Erstat alt, der i øjeblikket er i appen, med indholdet af en sikkerhedskopifil. Dette kan ikke fortrydes.';

  @override
  String get backupRestoreAction => 'Gendan';

  @override
  String get backupReminderTitle => 'Påmindelse om sikkerhedskopi';

  @override
  String get backupLastBackupNever => 'Seneste sikkerhedskopi: aldrig';

  @override
  String backupLastBackupDate(String date) {
    return 'Seneste sikkerhedskopi: $date';
  }

  @override
  String get backupReminderOff => 'Fra';

  @override
  String get backupReminderWeekly => 'Ugentlig';

  @override
  String get backupReminderMonthly => 'Månedlig';

  @override
  String get backupOverdueHint =>
      'Det er et stykke tid siden din seneste sikkerhedskopi – overvej at eksportere en nu.';

  @override
  String get backupRestoreDialogBody =>
      'Gendannelse erstatter alt i appen – din samling, programmer, dialekter, temaer og indstillinger – med indholdet af sikkerhedskopien. Dette kan ikke fortrydes.';

  @override
  String get backupChooseFileAction => 'Vælg fil…';

  @override
  String get backupPasteJsonLabel => 'Eller indsæt sikkerhedskopi-JSON';

  @override
  String get backupReplaceAllDataAction => 'Erstat alle data';

  @override
  String get backupExportDialogBody =>
      'Dette gemmer alt i appen – din samling, programmer, dialekter, temaer og indstillinger – i én JSON-fil.';

  @override
  String get backupEncryptToggleTitle =>
      'Kryptér denne sikkerhedskopi med en adgangssætning';

  @override
  String get backupEncryptToggleSubtitle =>
      'Beskytter filen, så kun nogen med adgangssætningen kan åbne den.';

  @override
  String get backupPassphraseLabel => 'Adgangssætning';

  @override
  String get backupConfirmPassphraseLabel => 'Bekræft adgangssætning';

  @override
  String get backupPassphrasesDontMatch =>
      'Adgangssætningerne stemmer ikke overens';

  @override
  String backupPassphraseStrength(String level) {
    String _temp0 = intl.Intl.selectLogic(level, {
      'weak': 'Styrke: Svag',
      'fair': 'Styrke: Fair',
      'strong': 'Styrke: Stærk',
      'other': '',
    });
    return '$_temp0';
  }

  @override
  String get backupShowPassphrase => 'Vis adgangssætning';

  @override
  String get backupHidePassphrase => 'Skjul adgangssætning';

  @override
  String get backupNoRecoveryWarning =>
      'Vi kan ikke gendanne denne adgangssætning. Hvis du mister den, kan denne sikkerhedskopi aldrig åbnes.';

  @override
  String get backupEncryptAndExportAction => 'Kryptér og eksportér';

  @override
  String get backupEnterPassphraseTitle => 'Indtast adgangssætning';

  @override
  String get backupEnterPassphraseBody =>
      'Denne sikkerhedskopi er krypteret. Indtast dens adgangssætning for at låse op og gendanne den.';

  @override
  String get backupUnlockAndRestoreAction => 'Lås op og gendan';

  @override
  String get diagnosticsNoDiagnosticsToExport =>
      'Ingen diagnostik at eksportere.';

  @override
  String get diagnosticsScrubbedExportUnavailable =>
      'Kunne ikke forberede en sikker (renset) eksport, så intet blev gemt. Prøv venligst igen.';

  @override
  String get diagnosticsLogExported => 'Diagnostiklog eksporteret.';

  @override
  String get diagnosticsExportCancelled => 'Eksport annulleret.';

  @override
  String get diagnosticsExportFailed =>
      'Kunne ikke eksportere diagnostikloggen.';

  @override
  String get diagnosticsClearLogTitle => 'Ryd diagnostiklog?';

  @override
  String get diagnosticsClearLogBody =>
      'Dette sletter permanent den lokale fejllog fra denne enhed. Dette kan ikke fortrydes.';

  @override
  String get diagnosticsClearAction => 'Ryd';

  @override
  String get diagnosticsLogCleared => 'Diagnostiklog ryddet.';

  @override
  String get diagnosticsHeader => 'Diagnostik';

  @override
  String get diagnosticsIntro =>
      'Når noget går galt, registrerer appen en teknisk note til en lokal log på denne enhed.';

  @override
  String get diagnosticsRecentEntriesHeader => 'Seneste poster';

  @override
  String get diagnosticsReadFailedTitle => 'Kunne ikke læse diagnostikloggen';

  @override
  String get diagnosticsReadFailedSubtitle =>
      'Den lokale log kan være utilgængelig på denne enhed. Du kan stadig prøve at eksportere eller rydde den.';

  @override
  String get diagnosticsEmptyTitle => 'Ingen fejl registreret';

  @override
  String get diagnosticsEmptySubtitle => 'Intet er optaget på denne enhed.';

  @override
  String get diagnosticsExportHeader => 'Eksportér';

  @override
  String get diagnosticsFullDetailTitle =>
      'Inkluder fulde detaljer (kan indeholde dit indhold)';

  @override
  String get diagnosticsFullDetailSubtitle =>
      'Fra som standard. Når fra fjerner eksporten dit indhold, filstier, e-mails og andre personoplysninger.';

  @override
  String get diagnosticsExportShareLogTitle => 'Eksportér / del log';

  @override
  String get diagnosticsExportShareFullSubtitle =>
      'Deler den fulde, ikke-redigerede log.';

  @override
  String get diagnosticsExportShareScrubbedSubtitle =>
      'Deler en renset kopi, der er sikker at vedhæfte til en fejlrapport.';

  @override
  String get diagnosticsClearLogRowTitle => 'Ryd log';

  @override
  String get diagnosticsClearLogRowSubtitle =>
      'Slet den lokale fejllog fra denne enhed.';

  @override
  String get crashFallbackTitle => 'Noget gik galt her';

  @override
  String get crashFallbackBody =>
      'Denne del af appen stødte på en uventet fejl og kom sig. Detaljerne blev gemt til en lokal log.';

  @override
  String get crashFallbackCopied => 'Kopieret';

  @override
  String get crashFallbackCopyDetails => 'Kopiér detaljer';

  @override
  String get commonCancel => 'Annuller';

  @override
  String get commonUndo => 'Fortryd';

  @override
  String get commonRetry => 'Prøv igen';

  @override
  String get commonDelete => 'Slet';

  @override
  String get commonDuplicate => 'Kopier';

  @override
  String commonDuplicateTitleSuffix(String title) {
    return '$title (kopi)';
  }

  @override
  String get commonYes => 'Ja';

  @override
  String get commonNo => 'Nej';

  @override
  String get commonOk => 'OK';

  @override
  String get commonApply => 'Anvend';

  @override
  String get commonCouldntOpenLink => 'Kunne ikke åbne linket';

  @override
  String get commonProgression => 'Progression';

  @override
  String get commonDanceFormContra => 'Contra';

  @override
  String get commonDanceFormEcd => 'Engelsk (ECD)';

  @override
  String get commonDanceFormSquare => 'Squaredans';

  @override
  String get commonProgressionNone => 'Ingen progression';

  @override
  String get commonProgressionSingle => 'Enkelt';

  @override
  String get commonProgressionDouble => 'Dobbelt';

  @override
  String get commonProgressionTriple => 'Tredobbelt';

  @override
  String get commonProgressionQuadruple => 'Firedobbelt';

  @override
  String get commonProgressionOther => 'Andet';

  @override
  String get commonDanceStatusActive => 'Aktiv';

  @override
  String get commonDanceStatusDeprecated => 'Forældet';

  @override
  String get commonDanceStatusBroken => 'Ødelagt';

  @override
  String get commonDanceLevelBeginner => 'Begynder';

  @override
  String get commonDanceLevelIntermediate => 'Øvet';

  @override
  String get commonDanceLevelAdvanced => 'Avanceret';

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
  String get commonFormationOther => 'Anden';

  @override
  String commonFormationWithDetail(String shape, String detail) {
    return '$shape — $detail';
  }

  @override
  String get commonMixedLevel => 'Blandet niveau';

  @override
  String commonShowDancesTaggedTooltip(String tagName) {
    return 'Vis danse tagget „$tagName“';
  }

  @override
  String commonDeletedSnack(String title) {
    return '„$title“ slettet.';
  }

  @override
  String get importGapMessage =>
      'Kunne ikke fortolke dette kald – beholdt ordret som en brugerdefineret figur.';

  @override
  String get importGapDialogTitle => 'Ukendt figur';

  @override
  String get importGapSemanticLabel =>
      'Ukendt figur. Kunne ikke fortolke dette kald – beholdt ordret som en brugerdefineret figur.';

  @override
  String get collectionScreenTitle => 'Samling';

  @override
  String get collectionNewDance => 'Ny dans';

  @override
  String get collectionSearchTooltip => 'Søg (Ctrl/Cmd-K)';

  @override
  String get collectionSelectDancesTooltip => 'Vælg danse';

  @override
  String get collectionManageCustomFieldsTooltip =>
      'Administrer brugerdefinerede felter';

  @override
  String get collectionRecentlyDeletedTooltip => 'For nylig slettet';

  @override
  String collectionSortByTooltip(String sortLabel) {
    return 'Sortér efter ($sortLabel)';
  }

  @override
  String get collectionSortRelevance => 'Bedste match';

  @override
  String get collectionSortTitle => 'Titel';

  @override
  String get collectionSortAuthor => 'Forfatter';

  @override
  String get collectionSortRecentlyAdded => 'For nylig tilføjet';

  @override
  String get collectionSortLastCalled => 'Sidst kaldt';

  @override
  String get collectionSortAscendingTooltip => 'Stigende (tryk for faldende)';

  @override
  String get collectionSortDescendingTooltip => 'Faldende (tryk for stigende)';

  @override
  String get collectionExitSelectionTooltip => 'Afslut valg';

  @override
  String collectionSelectedCount(int count) {
    return '$count valgt';
  }

  @override
  String get collectionAddTags => 'Tilføj tags';

  @override
  String get collectionRemoveTags => 'Fjern tags';

  @override
  String get collectionSetLevel => 'Angiv niveau';

  @override
  String get collectionSearchFieldLabel => 'Søg danse';

  @override
  String get collectionSearchFieldHint =>
      'Søg titler, forfattere, figurer, noter…';

  @override
  String get collectionClearSearchTooltip => 'Ryd søgning og filtre';

  @override
  String get collectionLoadError => 'Kunne ikke indlæse samlingen.';

  @override
  String collectionDuplicatedSnack(String title) {
    return 'Kopieret som „$title“.';
  }

  @override
  String get collectionEmpty =>
      'Din samling er tom. Tilføj eller importér en dans for at komme i gang – eller aktiver onlinesøgning i indstillinger.';

  @override
  String get collectionFiltersTitle => 'Filtre';

  @override
  String collectionFiltersActive(int count) {
    return 'Filtre ($count aktive)';
  }

  @override
  String get collectionByPhraseTitle => 'Efter frase';

  @override
  String collectionByPhraseActive(int count) {
    return 'Efter frase ($count aktive)';
  }

  @override
  String get collectionAdvancedTitle => 'Avanceret';

  @override
  String get collectionUseAdvancedQuery => 'Brug avanceret forespørgsel';

  @override
  String get collectionUseAdvancedQuerySubtitle =>
      'Kombiner figurer og sekvenser med alle / nogen / ingen grupper.';

  @override
  String collectionDanceCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count danse',
      one: '1 dans',
    );
    return '$_temp0';
  }

  @override
  String get collectionSearchError => 'Noget gik galt under søgningen.';

  @override
  String get collectionNoResults => 'Ingen danse matcher din søgning.';

  @override
  String get collectionBatchNoChanges => 'Ingen ændringer';

  @override
  String collectionBatchTagged(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Tagget $count danse',
      one: 'Tagget 1 dans',
    );
    return '$_temp0';
  }

  @override
  String collectionBatchUntagged(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Fjernede tags fra $count danse',
      one: 'Fjernede tags fra 1 dans',
    );
    return '$_temp0';
  }

  @override
  String collectionBatchLevelSet(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Angav niveau på $count danse',
      one: 'Angav niveau på 1 dans',
    );
    return '$_temp0';
  }

  @override
  String collectionBatchLevelCleared(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Ryddede niveau på $count danse',
      one: 'Ryddede niveau på 1 dans',
    );
    return '$_temp0';
  }

  @override
  String get collectionBatchMore => 'Flere batchhandlinger';

  @override
  String get collectionSetRating => 'Angiv vurdering';

  @override
  String get collectionAddTunes => 'Tilføj melodier';

  @override
  String get collectionClearTunes => 'Ryd melodier';

  @override
  String get collectionEditCustomField => 'Rediger brugerdefineret felt';

  @override
  String collectionBatchRatingSet(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Angav vurdering på $count danse',
      one: 'Angav vurdering på 1 dans',
    );
    return '$_temp0';
  }

  @override
  String collectionBatchRatingCleared(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Ryddede vurdering på $count danse',
      one: 'Ryddede vurdering på 1 dans',
    );
    return '$_temp0';
  }

  @override
  String collectionBatchTunesAdded(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Tilføjede melodier til $count danse',
      one: 'Tilføjede melodier til 1 dans',
    );
    return '$_temp0';
  }

  @override
  String collectionBatchTunesCleared(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Ryddede melodier fra $count danse',
      one: 'Ryddede melodier fra 1 dans',
    );
    return '$_temp0';
  }

  @override
  String collectionBatchCustomFieldSet(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Opdaterede felt på $count danse',
      one: 'Opdaterede felt på 1 dans',
    );
    return '$_temp0';
  }

  @override
  String collectionBatchCustomFieldCleared(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Ryddede felt på $count danse',
      one: 'Ryddede felt på 1 dans',
    );
    return '$_temp0';
  }

  @override
  String collectionSelectDanceLabel(String title) {
    return 'Vælg $title';
  }

  @override
  String collectionCalledBadge(int count) {
    return 'kaldt ×$count';
  }

  @override
  String collectionCalledBadgeSemantic(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'kaldt $count gange',
      one: 'kaldt 1 gang',
    );
    return '$_temp0';
  }

  @override
  String collectionRatingSemantic(int rating) {
    return 'Vurdering: $rating af 5 stjerner';
  }

  @override
  String collectionRowActionsSemantic(String title) {
    return 'Handlinger for $title';
  }

  @override
  String get collectionSplitEmptyTitle => 'Vælg en dans';

  @override
  String get collectionSplitEmptySubtitle =>
      'Vælg en dans fra listen for at se dens detaljer.';

  @override
  String get collectionFacetType => 'Type';

  @override
  String get collectionFacetFormation => 'Formation';

  @override
  String get collectionFacetStatus => 'Status';

  @override
  String get collectionFacetLevel => 'Niveau';

  @override
  String get collectionFacetMinRating => 'Minimumsvurdering';

  @override
  String collectionFacetMinRatingChip(int min) {
    return '≥$min★';
  }

  @override
  String get collectionFacetTags => 'Tags';

  @override
  String get collectionFacetSource => 'Kilde';

  @override
  String get collectionFacetAuthor => 'Forfatter';

  @override
  String get collectionFacetNone =>
      'Ingen filtre tilgængelige for denne samling endnu.';

  @override
  String get collectionFacetClear => 'Ryd filtre';

  @override
  String collectionFacetRemoveAuthor(String name) {
    return 'Fjern $name';
  }

  @override
  String get collectionFacetAuthorSearchHint => 'Søg forfattere…';

  @override
  String get collectionFacetOpContains => 'indeholder';

  @override
  String get collectionFacetOpEquals => 'er lig med';

  @override
  String collectionFacetTextHint(String label) {
    return 'Filtrer efter $label…';
  }

  @override
  String get collectionFacetNumOpEq => '=';

  @override
  String get collectionFacetNumOpLt => '<';

  @override
  String get collectionFacetNumOpGt => '>';

  @override
  String get collectionFacetNumOpBetween => 'mellem';

  @override
  String get collectionFacetNumFrom => 'Fra';

  @override
  String get collectionFacetNumValue => 'Værdi';

  @override
  String get collectionFacetNumTo => 'Til';

  @override
  String get collectionByPhraseOrdinalFirst => 'første frase';

  @override
  String get collectionByPhraseOrdinalSecond => 'anden frase';

  @override
  String get collectionByPhraseOrdinalThird => 'tredje frase';

  @override
  String get collectionByPhraseOrdinalFourth => 'fjerde frase';

  @override
  String collectionByPhraseOrdinalN(int number) {
    return 'frase $number';
  }

  @override
  String collectionByPhraseCaption(String ordinal, String label) {
    return '$ordinal (normalt $label)';
  }

  @override
  String collectionByPhraseFieldMatch(String caption) {
    return '$caption, figurer matcher';
  }

  @override
  String collectionByPhraseFieldExclude(String caption) {
    return '$caption, men matcher ikke';
  }

  @override
  String collectionByPhraseRemoveMove(String move, String field) {
    return 'Fjern $move fra $field';
  }

  @override
  String get collectionQueryMatchLabel => 'Match';

  @override
  String get collectionQueryGroupAll => 'Alle af';

  @override
  String get collectionQueryGroupAny => 'Nogen af';

  @override
  String get collectionQueryGroupNone => 'Ingen af';

  @override
  String get collectionQueryTheseConditions => 'disse betingelser';

  @override
  String get collectionQueryRemoveGroup => 'Fjern gruppe';

  @override
  String get collectionQueryEmptyGroup =>
      'Ingen betingelser endnu – tilføj en nedenfor.';

  @override
  String get collectionQueryAddCondition => 'Tilføj en betingelse';

  @override
  String get collectionQueryHasFigure => 'Har figur';

  @override
  String get collectionQuerySequenceThen => 'Sekvens (derefter)';

  @override
  String get collectionQueryConditionGroup => 'Betingelsesgruppe';

  @override
  String get collectionQueryAddButton => 'Tilføj';

  @override
  String get collectionQueryRemoveFigure => 'Fjern figur';

  @override
  String get collectionQueryThenFirst => 'Første';

  @override
  String get collectionQueryThenConnector => 'derefter';

  @override
  String get collectionQueryThenLater => 'Senere';

  @override
  String get collectionQueryRemoveSequence => 'Fjern sekvens';

  @override
  String get collectionQueryGroupFigures => 'Gruppér figurer';

  @override
  String get collectionQueryFigureGroupMatch => 'Figurgruppes match';

  @override
  String get collectionQueryOfTheseFigures => 'af disse figurer';

  @override
  String get collectionQuerySingleFigure => 'Enkelt figur';

  @override
  String get collectionQueryAddFigure => 'Tilføj figur';

  @override
  String get collectionQueryRemoveFigureGroup => 'Fjern figurgruppe';

  @override
  String get collectionQueryMoveLabel => 'Bevægelse';

  @override
  String get collectionQueryMoveHint => 'f.eks. swing';

  @override
  String get collectionQuerySectionLabel => 'Sektion';

  @override
  String get collectionQueryAnySection => 'Enhver sektion';

  @override
  String collectionQueryAnyParam(String param) {
    return 'Vilkårlig $param';
  }

  @override
  String get collectionBatchLevelUnspecified => 'Uspecificeret (ryd)';

  @override
  String get collectionBatchLevelConfirm => 'Angiv';

  @override
  String get collectionBatchTagEmptyAdd =>
      'Ingen tags endnu. Opret et nedenfor.';

  @override
  String get collectionBatchTagEmptyRemove =>
      'De valgte danse har ingen tags at fjerne.';

  @override
  String get collectionCreateTagLabel => 'Opret et tag';

  @override
  String get collectionCreateTagButton => 'Opret tag';

  @override
  String get collectionCreateTagError => 'Kunne ikke oprette tag. Prøv igen.';

  @override
  String get collectionBatchTagAddConfirm => 'Tilføj';

  @override
  String get collectionBatchTagRemoveConfirm => 'Fjern';

  @override
  String collectionBatchRatingStars(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count stjerner',
      one: '1 stjerne',
    );
    return '$_temp0';
  }

  @override
  String get collectionBatchRatingUnrated => 'Ikke vurderet (ryd)';

  @override
  String get collectionBatchRatingConfirm => 'Angiv';

  @override
  String get collectionBatchTunesFieldLabel => 'Tilføj en melodi';

  @override
  String get collectionBatchTunesAddButton => 'Tilføj melodi til liste';

  @override
  String get collectionBatchTunesEmpty =>
      'Skriv et melodinavn og tilføj det til listen.';

  @override
  String collectionBatchTunesRemove(String tune) {
    return 'Fjern $tune fra liste';
  }

  @override
  String get collectionBatchTunesConfirm => 'Tilføj';

  @override
  String get collectionBatchClearTunesConfirmTitle => 'Ryd melodier?';

  @override
  String get collectionBatchClearTunesConfirmBody =>
      'Dette fjerner alle melodier fra de valgte danse. Du kan fortryde det bagefter.';

  @override
  String get collectionBatchClearTunesConfirmButton => 'Ryd melodier';

  @override
  String get collectionBatchCustomFieldKeyLabel => 'Felt';

  @override
  String get collectionBatchCustomFieldClearOption => 'Ryd dette felt';

  @override
  String get collectionBatchCustomFieldEmpty =>
      'Ingen brugerdefinerede felter er defineret endnu.';

  @override
  String get collectionBatchCustomFieldNumberInvalid => 'Indtast et tal';

  @override
  String get collectionBatchCustomFieldConfirm => 'Anvend';

  @override
  String get danceFiguresEmpty => 'Ingen figurer endnu.';

  @override
  String danceFigureBeats(int beats) {
    String _temp0 = intl.Intl.pluralLogic(
      beats,
      locale: localeName,
      other: '$beats slag',
      one: '1 slag',
    );
    return '$_temp0';
  }

  @override
  String get danceFigureProgressionSemantic => 'progression';

  @override
  String danceFigureNote(String note) {
    return 'note: $note';
  }

  @override
  String get danceScreenTitle => 'Dans';

  @override
  String get danceNotFound => 'Dans ikke fundet.';

  @override
  String get danceEditFab => 'Rediger';

  @override
  String get danceDuplicateTooltip => 'Kopier dans';

  @override
  String get danceDeleteTooltip => 'Slet dans';

  @override
  String get danceMoreActions => 'Flere handlinger';

  @override
  String get danceSectionFigures => 'Figurer';

  @override
  String get danceSectionCallingNotes => 'Kaldsnotes';

  @override
  String get danceSectionTunes => 'Melodier';

  @override
  String get danceSectionLinks => 'Links';

  @override
  String get danceMissingRelated => '(manglende dans)';

  @override
  String get danceSectionPublishedSources => 'Publicerede kilder';

  @override
  String get danceSectionCustomFields => 'Brugerdefinerede felter';

  @override
  String get danceSectionCallingHistory => 'Kaldshistorik';

  @override
  String get danceCallingHistoryEmpty =>
      'Endnu ikke inkluderet i noget program.';

  @override
  String get danceShowCanonicalTerms => 'Vis kanoniske termer';

  @override
  String get danceCanonicalToggleLabel => 'Kanonisk';

  @override
  String danceProvenanceVia(String source) {
    return 'via $source';
  }

  @override
  String get danceProvenanceSourceManual => 'manuel indlæsning';

  @override
  String get danceProvenanceSourceJson => 'JSON-import';

  @override
  String get danceLinkKindVideo => 'video';

  @override
  String get danceLinkKindSource => 'kildelink';

  @override
  String get danceLinkKindLink => 'link';

  @override
  String danceOpenLinkSemantic(String kind, String display) {
    return 'Åbn $kind: $display';
  }

  @override
  String danceOpenProgramSemantic(String title, String details) {
    return 'Åbn program: $title, $details';
  }

  @override
  String danceHalfStatsFirstHalf(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Kaldt $count gange i første halvdel',
      one: 'Kaldt 1 gang i første halvdel',
    );
    return '$_temp0';
  }

  @override
  String danceHalfStatsSecondHalf(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count gange i anden halvdel',
      one: '1 gang i anden halvdel',
    );
    return '$_temp0';
  }

  @override
  String danceHalfStatsOpened(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'åbnede første halvdel $count gange',
      one: 'åbnede første halvdel 1 gang',
    );
    return '$_temp0';
  }

  @override
  String danceHalfStatsClosed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'afsluttede aftenen (sidste dans i anden halvdel) $count gange',
      one: 'afsluttede aftenen (sidste dans i anden halvdel) 1 gang',
    );
    return '$_temp0';
  }

  @override
  String danceHalfStatsSemanticLabel(String description) {
    return 'Halvdelsopdeling: $description';
  }

  @override
  String get danceSourceUnknown => '(ukendt kilde)';

  @override
  String danceSourcePage(String page) {
    return 's. $page';
  }

  @override
  String danceSourceNumber(String number) {
    return 'nr. $number';
  }

  @override
  String danceOpenSourceLinkSemantic(String title) {
    return 'Åbn kildelink: $title';
  }

  @override
  String danceSourceSemanticPrefix(String title) {
    return 'Kilde: $title';
  }

  @override
  String danceOpenDanceCrossRefSemantic(String title) {
    return 'Åbn dans: $title';
  }

  @override
  String get commonAddToProgram => 'Tilføj til program';

  @override
  String get programsEmptyTitle => 'Ingen programmer endnu';

  @override
  String get programsAddToProgramEmptyBody =>
      'Opret et program for at begynde at bygge en sætliste.';

  @override
  String get programsCreateWithDance => 'Opret et nyt program med denne dans';

  @override
  String programsAddDanceToProgramSemantic(
    String danceTitle,
    String programTitle,
    String details,
  ) {
    return 'Tilføj „$danceTitle“ til $programTitle, $details';
  }

  @override
  String programsAddedToProgramSnack(String danceTitle, String programTitle) {
    return 'Tilføjede „$danceTitle“ til $programTitle.';
  }

  @override
  String get programsNewProgram => 'Nyt program';

  @override
  String programsCreatedProgramSnack(String programTitle, String danceTitle) {
    return 'Oprettede „$programTitle“ med „$danceTitle“.';
  }

  @override
  String get dancePerformTooltip => 'Fremfør denne dans';

  @override
  String get commonSwitchDialectTooltip => 'Skift dialekt';

  @override
  String get programsStatusDraft => 'Kladde';

  @override
  String get programsStatusFinalized => 'Afsluttet';

  @override
  String get programsStatusPerformed => 'Fremført';

  @override
  String get programsNoLongerExists => 'Dette program eksisterer ikke længere.';

  @override
  String get programsFallbackTitle => 'Program';

  @override
  String get programsUntitledDanceFallback => 'dans';

  @override
  String programsAddedDanceSnack(String title) {
    return 'Tilføjede „$title“.';
  }

  @override
  String programsAddedDanceAnnounce(String title) {
    return 'Tilføjede $title til program.';
  }

  @override
  String get programsAddedNoteAnnounce => 'Tilføjede note til program.';

  @override
  String get programsAddedBreakAnnounce => 'Tilføjede pause til program.';

  @override
  String get programsMarkedAllPerformed => 'Markerede alle danse som fremført.';

  @override
  String programsSavedSnack(String title) {
    return '„$title“ gemt.';
  }

  @override
  String get programsSaveError => 'Kunne ikke gemme programmet.';

  @override
  String programsDuplicatedSnack(String title) {
    return 'Kopieret som „$title“.';
  }

  @override
  String programsDeletedSnack(String title) {
    return '„$title“ slettet.';
  }

  @override
  String get programsDiscardTitle => 'Kassér ændringer?';

  @override
  String get programsDiscardBody => 'Du har ugemte ændringer i dette program.';

  @override
  String get programsKeepEditing => 'Fortsæt redigering';

  @override
  String get programsDiscard => 'Kassér';

  @override
  String get programsDraftTitle => 'Ugemt kladde';

  @override
  String get programsDraftBody =>
      'Du har en ugemt kladde til dette program. Vil du gendanne den?';

  @override
  String get programsDraftRestore => 'Gendan';

  @override
  String get programsDraftDiscard => 'Kassér';

  @override
  String get programsBuildProgram => 'Byg program';

  @override
  String get programsBuildTab => 'Byg';

  @override
  String get programsMatrixTab => 'Matrix';

  @override
  String get programsPerformTooltip => 'Fremfør dette program';

  @override
  String get programsMarkAllPerformedTooltip => 'Markér alle som fremført';

  @override
  String get programsSaveDirty => 'Gem *';

  @override
  String get commonSave => 'Gem';

  @override
  String get programsLoading => 'Indlæser program';

  @override
  String get programsLoadError => 'Kunne ikke indlæse programmet.';

  @override
  String get programsDeletedDanceFallback => '(slettet dans)';

  @override
  String get programsSlotsLabel => 'Slots';

  @override
  String get programsAddDanceButton => 'Tilføj dans';

  @override
  String get programsAddNoteBreakButton => 'Tilføj note / pause';

  @override
  String get programsInsertBreakButton => 'Indsæt pause';

  @override
  String get programsAddADanceSheetTitle => 'Tilføj en dans';

  @override
  String get commonClose => 'Luk';

  @override
  String get programsNoDateSet => 'Ingen dato angivet';

  @override
  String get programsTitleLabel => 'Titel';

  @override
  String get programsTitleHint => 'f.eks. Fredagsaften contra';

  @override
  String get programsTitleRequired => 'En titel er påkrævet.';

  @override
  String get programsEventDateLabel => 'Begivenhedsdato';

  @override
  String get programsSetDate => 'Angiv dato';

  @override
  String get programsChangeDate => 'Skift';

  @override
  String get programsClearEventDate => 'Ryd begivenhedsdato';

  @override
  String get programsVenueLabel => 'Spillested';

  @override
  String get programsVenueHint => 'f.eks. Forsamlingshuset';

  @override
  String programsVenueLinkedHint(String venueName) {
    return 'Også knyttet til gemt spillested: $venueName. Aktiver genanvendelige spillesteder i indstillinger for at se eller ændre.';
  }

  @override
  String get programsVenueLinkedHintFallbackName => 'et gemt spillested';

  @override
  String programsVenueLegacyTextHint(String venueText) {
    return 'Tidligere indtastet spillested: „$venueText“. Knyt et gemt spillested nedenfor for at bruge genanvendelige detaljer.';
  }

  @override
  String get programsBandLabel => 'Band';

  @override
  String get programsBandHint => 'f.eks. The Fiddleheads';

  @override
  String get programsCallerLabel => 'Caller';

  @override
  String get programsCallerHint => 'Værtscaller for begivenheden';

  @override
  String get programsDancerLevelLabel => 'Danserniveau';

  @override
  String get programsDancerLevelHint => 'f.eks. Alle velkomne, Erfarne';

  @override
  String get programsNotesLabel => 'Noter';

  @override
  String get programsStatusFieldLabel => 'Status';

  @override
  String get programsHideAlternatesTitle => 'Skjul alternativer i sætliste';

  @override
  String get programsHideAlternatesSubtitle =>
      'Udelader ALT-slots fra oversigten, PDF og eksporteret sætliste. Byggeren viser stadig alt.';

  @override
  String programsWarningCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count advarsler',
      one: '1 advarsel',
    );
    return '$_temp0';
  }

  @override
  String get programsAddNoteBreakDialogTitle => 'Tilføj note eller pause';

  @override
  String get programsFreeTextLabel => 'Tekst';

  @override
  String get programsFreeTextHint => 'f.eks. Pause, vals, bekendtgørelse';

  @override
  String get commonAdd => 'Tilføj';

  @override
  String get programsTitle => 'Programmer';

  @override
  String get programsSortTitle => 'Titel';

  @override
  String get programsSortRecentlyUpdated => 'For nylig opdateret';

  @override
  String get programsSortEventDate => 'Begivenhedsdato';

  @override
  String programsSortByTooltip(String label) {
    return 'Sortér efter ($label)';
  }

  @override
  String get programsListLoadError => 'Kunne ikke indlæse dine programmer.';

  @override
  String get programsListEmptyBody =>
      'Byg sætlister til dine begivenheder her. Opret dit første program for at komme i gang.';

  @override
  String programsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count programmer',
      one: '1 program',
    );
    return '$_temp0';
  }

  @override
  String get programsSummaryTitle => 'Program';

  @override
  String get programsEditProgram => 'Rediger program';

  @override
  String get programsSummaryUnavailable =>
      'Dette program er ikke længere tilgængeligt.';

  @override
  String get programsPerformDisabledTooltip =>
      'Tilføj mindst én slot for at fremføre dette program';

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
    return 'Sætliste ($count)';
  }

  @override
  String get programsSummaryEmptySetList =>
      'Ingen slots endnu – åbn byggeren for at tilføje danse.';

  @override
  String programsSummaryGuest(String caller) {
    return 'Gæst: $caller';
  }

  @override
  String programsPlannedMinutes(int minutes) {
    return '$minutes min';
  }

  @override
  String get programsAltBadge => 'Alt';

  @override
  String get programsDanceUnavailable => 'Dans ikke tilgængelig';

  @override
  String programsSummaryNote(String note) {
    return 'Note: $note';
  }

  @override
  String programsSummaryAlternateSemantic(String title) {
    return 'Alternativ: $title';
  }

  @override
  String get programsPerformed => 'Fremført';

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
  String get programsSlotNoteFallback => 'Note';

  @override
  String get programsSlotEditorEmpty =>
      'Ingen slots endnu. Tilføj en dans eller en note for at komme i gang.';

  @override
  String get programsSlotMoved => 'Slot flyttet.';

  @override
  String get programsSlotMovedUp => 'Slot flyttet op.';

  @override
  String get programsSlotMovedDown => 'Slot flyttet ned.';

  @override
  String programsSlotCutBanner(String name) {
    return '„$name“ er klippet – tryk Indsæt for at placere det.';
  }

  @override
  String get programsPasteBeforeFirst => 'Indsæt før første slot';

  @override
  String programsPasteAfter(String title) {
    return 'Indsæt efter $title';
  }

  @override
  String get programsPasteHere => 'Indsæt her';

  @override
  String get programsMarkedPrimary => 'Markeret som primær.';

  @override
  String get programsMarkedAlternate => 'Markeret som alternativ.';

  @override
  String get programsMarkedPerformed => 'Markeret som fremført.';

  @override
  String get programsPerformedCleared => 'Fremført-markering ryddet.';

  @override
  String programsRemovedSlot(String name) {
    return '$name fjernet.';
  }

  @override
  String get programsAltOrdinal => 'ALT';

  @override
  String programsDragToReorder(String title) {
    return 'Træk for at omarrangere $title';
  }

  @override
  String programsMoveSlotUp(String title) {
    return 'Flyt $title op';
  }

  @override
  String programsMoveSlotDown(String title) {
    return 'Flyt $title ned';
  }

  @override
  String programsCutSlot(String title) {
    return 'Klip $title';
  }

  @override
  String programsMoreActionsForSlot(String title) {
    return 'Flere handlinger for $title';
  }

  @override
  String get programsEditSlotMenu => 'Rediger slot';

  @override
  String get programsMakePrimaryMenu => 'Gør primær';

  @override
  String get programsMarkAlternateMenu => 'Markér som alternativ';

  @override
  String get programsClearPerformedMenu => 'Ryd fremført';

  @override
  String get programsMarkPerformedMenu => 'Markér som fremført';

  @override
  String get programsRemoveSlotMenu => 'Fjern slot';

  @override
  String get programsSlotTextRequiredError =>
      'Indtast noget tekst til denne slot.';

  @override
  String get programsWholeNumberError => 'Indtast et heltal ≥ 0.';

  @override
  String get programsEditDanceSlotTitle => 'Rediger dans-slot';

  @override
  String get programsEditNoteTitle => 'Rediger note';

  @override
  String get programsCallerNoteLabel => 'Caller-note (valgfrit)';

  @override
  String get programsCallerNoteHint => 'f.eks. lær hey\'et først';

  @override
  String get programsGuestCallerLabel => 'Gæstecaller (valgfrit)';

  @override
  String get programsPlannedMinutesLabel => 'Planlagte minutter (valgfrit)';

  @override
  String get programsAlternateDanceTitle => 'Alternativ dans';

  @override
  String get programsAlternateDanceSubtitle =>
      'Vises indrykket under slottet ovenfor.';

  @override
  String get commonDone => 'Færdig';

  @override
  String programsMatrixSemanticLabel(int danceCount, int moveCount) {
    return 'Programmeringsmatrix: $danceCount danse med $moveCount bevægelser';
  }

  @override
  String programsMatrixOmittedCaption(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count fritekst-slots',
      one: '1 fritekst-slot',
    );
    return '$_temp0 (pauser, noter) udeladt – matrixen viser kun danse.';
  }

  @override
  String programsMatrixMoveHeaderSemantic(String label) {
    return 'Bevægelse: $label';
  }

  @override
  String programsMatrixRowHeaderSemantic(
    String title,
    String alt,
    String half,
  ) {
    String _temp0 = intl.Intl.selectLogic(half, {
      'first': 'Alternativ dans: $title, første halvdel',
      'second': 'Alternativ dans: $title, anden halvdel',
      'other': 'Alternativ dans: $title',
    });
    String _temp1 = intl.Intl.selectLogic(half, {
      'first': 'Dans: $title, første halvdel',
      'second': 'Dans: $title, anden halvdel',
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
    String _temp0 = intl.Intl.selectLogic(half, {'first': '1.', 'other': '2.'});
    return '$_temp0';
  }

  @override
  String programsMatrixCellSemantic(
    String dance,
    String move,
    String present,
    String debut,
    String first,
  ) {
    String _temp0 = intl.Intl.selectLogic(debut, {
      'yes': ', introduceret her',
      'other': '',
    });
    String _temp1 = intl.Intl.selectLogic(first, {
      'yes': ', dansens første figur',
      'other': '',
    });
    String _temp2 = intl.Intl.selectLogic(present, {
      'no': 'ikke til stede',
      'other': 'til stede$_temp0$_temp1',
    });
    return '$dance, $move: $_temp2';
  }

  @override
  String programsMatrixChipQualifiedTitle(
    String title,
    String alt,
    String half,
  ) {
    String _temp0 = intl.Intl.selectLogic(half, {
      'first': '$title (alternativ dans, første halvdel)',
      'second': '$title (alternativ dans, anden halvdel)',
      'other': '$title (alternativ dans)',
    });
    String _temp1 = intl.Intl.selectLogic(half, {
      'first': '$title (første halvdel)',
      'second': '$title (anden halvdel)',
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
    return 'Bevægelse: $label, brugt i $count af $total danse';
  }

  @override
  String programsMatrixNOfTotal(int count, int total) {
    return '$count af $total';
  }

  @override
  String get programsMatrixNoComparableMoves =>
      'Ingen af disse danse har strukturerede figurer endnu, så der er ingen bevægelser at sammenligne.';

  @override
  String get programsMatrixRepeatedMovesHeader => 'Gentagne bevægelser';

  @override
  String get programsMatrixRepeatedMovesSubtitle =>
      'Bevægelser delt på tværs af to eller flere danse, mest-gentagne først.';

  @override
  String get programsMatrixNoRepeatsNote =>
      'Ingen bevægelser gentages på tværs af disse danse – hver bevægelse nedenfor bruges af én enkelt dans.';

  @override
  String get programsMatrixUsedOnceHeader => 'Brugt én gang';

  @override
  String get programsMatrixLegendIntroduced => 'Introduceret her';

  @override
  String get programsMatrixLegendFirstFigure => 'Dansens første figur';

  @override
  String get programsMatrixLegendPresent => 'Til stede';

  @override
  String get programsMatrixEmptyTitle => 'Ingen strukturerede figurer endnu';

  @override
  String get programsMatrixEmptyBody =>
      'Matrixen udfyldes automatisk, efterhånden som programmets danse får strukturerede figurer.';

  @override
  String get performTitle => 'Fremfør';

  @override
  String get performExitTooltip => 'Afslut fremførelsesvisning';

  @override
  String get performExitTitle => 'Afslut Fremfør?';

  @override
  String get performExitBody =>
      'Forlad fremførelsesvisningen? Din placering og det kørende ur bevares, så du kan genoptage når som helst.';

  @override
  String get performExitCancel => 'Fortsæt fremførelse';

  @override
  String get performExitConfirm => 'Afslut';

  @override
  String get performTapTempo => 'Tryk tempo';

  @override
  String performBpmReadout(int bpm) {
    return '$bpm BPM';
  }

  @override
  String get performTapToSetTempo => 'Tryk for at angive tempo';

  @override
  String performBpmSemantic(int bpm) {
    return '$bpm slag pr. minut';
  }

  @override
  String get performNoTempoSemantic =>
      'Intet tempo angivet endnu. Tryk på målet for at angive et tempo.';

  @override
  String get performRecordBeatHint => 'registrér et slag';

  @override
  String get performTapRefineHint =>
      'Bliv ved med at trykke for at forfine · Nulstil for at starte forfra';

  @override
  String get performTapTwiceHint => 'Tryk mindst to gange i takt med takten';

  @override
  String get performResetTempo => 'Nulstil';

  @override
  String get performUntitledSlot => 'Unavngiven slot';

  @override
  String performMarkedPerformedAnnounce(String label) {
    return 'Markerede $label som fremført';
  }

  @override
  String get performClearedPerformedAnnounce => 'Ryddede fremført-markering';

  @override
  String performMovedToPosition(String label, int position) {
    return 'Flyttede $label til position $position';
  }

  @override
  String get performDanceFallback => 'dans';

  @override
  String performInsertedAnnounce(String title) {
    return 'Indsatte $title';
  }

  @override
  String get performAddedNoteAnnounce => 'Tilføjede note';

  @override
  String get performInsertADance => 'Indsæt en dans';

  @override
  String get performAdjustProgram => 'Juster program';

  @override
  String get performCurrentSlotSection => 'Nuværende slot';

  @override
  String get performPerformedTapToClear => 'Fremført – tryk for at rydde';

  @override
  String get performReorderSection => 'Omarranger resterende slots';

  @override
  String get performNoLaterSlots => 'Ingen senere slots at omarrangere.';

  @override
  String get performInsertDanceFromSearch => 'Indsæt dans fra søgning';

  @override
  String get performAdHocNoteLabel => 'Ad-hoc-note / pause';

  @override
  String get performAdHocNoteHint => 'f.eks. Vals, bekendtgørelser';

  @override
  String get performAddNote => 'Tilføj note';

  @override
  String performAlternatesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count alternativer',
      one: '1 alternativ',
    );
    return '$_temp0';
  }

  @override
  String performMoveLabelUp(String label) {
    return 'Flyt „$label“ op';
  }

  @override
  String performMoveLabelDown(String label) {
    return 'Flyt „$label“ ned';
  }

  @override
  String performSlotPosition(int current, int total) {
    return 'Slot $current af $total';
  }

  @override
  String performShowingSlot(String label) {
    return 'Viser $label';
  }

  @override
  String get performAdjustmentUndone => 'Justering fortrudt.';

  @override
  String get performProgramAdjustedSnack => 'Program justeret.';

  @override
  String get performProgramAdjustedAnnounce => 'Program justeret';

  @override
  String get performNoSlots => 'Dette program har ingen slots.';

  @override
  String get performJumpToSlot => 'Hop til slot';

  @override
  String get performShowAlternate => 'Vis alternativ';

  @override
  String get performPreviousSlot => 'Forrige slot';

  @override
  String get performNextSlot => 'Næste slot';

  @override
  String get performResumeTimers => 'Genoptag timere';

  @override
  String get performPauseTimers => 'Sæt timere på pause';

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
      other: '$planned minutter',
      one: '1 minut',
    );
    String _temp1 = intl.Intl.selectLogic(hasPlanned, {
      'yes': ', planlagt $_temp0',
      'other': '',
    });
    String _temp2 = intl.Intl.selectLogic(over, {
      'yes': ', over planlagt',
      'other': '',
    });
    String _temp3 = intl.Intl.selectLogic(paused, {
      'yes': ', sat på pause',
      'other': '',
    });
    return 'Programtid $programTime, slot-tid $slotTime$_temp1$_temp2$_temp3';
  }

  @override
  String performPlannedMin(int planned) {
    return 'planlagt $planned min';
  }

  @override
  String get performOverSuffix => ' over';

  @override
  String get performCallingNotes => 'Kaldsnotes';

  @override
  String get performNoFigures => 'Ingen figurer endnu.';

  @override
  String get performDecreaseTextSize => 'Formindsk tekststørrelse';

  @override
  String get performIncreaseTextSize => 'Forstør tekststørrelse';

  @override
  String get performShowCanonicalTerms => 'Vis kanoniske termer';

  @override
  String get performMoreActions => 'Flere handlinger';

  @override
  String get performAutoSizeMenuLabel => 'Auto-størrelse tekst til skærm';

  @override
  String get performAutoSizeOnTooltip =>
      'Auto-størrelse til – tryk for manuel tekststørrelse';

  @override
  String get performAutoSizeOffTooltip =>
      'Auto-størrelse fra – tryk for at tilpasse tekst til skærm';

  @override
  String get performStageThemeOnTooltip =>
      'Scenetema til – tryk for at bruge apptema';

  @override
  String get performStageThemeOffTooltip =>
      'Scenetema fra – tryk for mørk scene';

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
      'yes': ', progression',
      'other': '',
    });
    String _temp2 = intl.Intl.pluralLogic(
      beats,
      locale: localeName,
      other: '$beats slag',
      one: '1 slag',
    );
    String _temp3 = intl.Intl.selectLogic(hasNote, {
      'yes': ', note: $note',
      'other': '',
    });
    return '$main$_temp0$_temp1, $_temp2$_temp3';
  }

  @override
  String get programsSelectTitle => 'Vælg et program';

  @override
  String get programsSelectBody =>
      'Vælg et program fra listen, eller opret et nyt.';

  @override
  String get commonEdit => 'Rediger';

  @override
  String get commonChange => 'Skift';

  @override
  String get commonTryAgain => 'Prøv igen';

  @override
  String get exportTooltip => 'Eksportér';

  @override
  String get exportShareDanceText => 'Del dans (tekst)';

  @override
  String get exportCopyDance => 'Kopiér dans';

  @override
  String get exportPrintPdf => 'Eksportér / udskriv PDF';

  @override
  String get exportDanceCopied => 'Dans kopieret til udklipsholder.';

  @override
  String get exportShareDanceError => 'Kunne ikke dele denne dans';

  @override
  String get exportDanceError => 'Kunne ikke eksportere denne dans';

  @override
  String get exportShareSetListText => 'Del sætliste (tekst)';

  @override
  String get exportShareProgramBundle => 'Del (program + danse)';

  @override
  String get exportCopySetList => 'Kopiér sætliste';

  @override
  String get exportSetListCopied => 'Sætliste kopieret til udklipsholder.';

  @override
  String get exportShareSetListError => 'Kunne ikke dele denne sætliste';

  @override
  String get exportShareProgramError => 'Kunne ikke dele dette program';

  @override
  String get exportSetListError => 'Kunne ikke eksportere denne sætliste';

  @override
  String get exportMatrixPdfTooltip => 'Eksportér eller udskriv matrix som PDF';

  @override
  String get exportMatrixPdfFilename => 'Programmeringsmatrix';

  @override
  String get exportVenueContactTitle =>
      'Inkluder spillestedets kontaktoplysninger i denne eksport?';

  @override
  String get exportVenueContactBody =>
      'Dette er personlige kontaktoplysninger for spillestedet. De udelades fra denne eksport, medmindre du bekræfter nedenfor.';

  @override
  String get exportVenueContactConfirm => 'Fortsæt';

  @override
  String get exportVenueContact1Name => 'Kontaktperson 1 navn';

  @override
  String get exportVenueContact1Phone => 'Kontaktperson 1 telefon';

  @override
  String get exportVenueContact1Email => 'Kontaktperson 1 e-mail';

  @override
  String get exportVenueContact2Name => 'Kontaktperson 2 navn';

  @override
  String get exportVenueContact2Phone => 'Kontaktperson 2 telefon';

  @override
  String get exportVenueContact2Email => 'Kontaktperson 2 e-mail';

  @override
  String get onlineSearchToggleTitle => 'Onlinesøgning';

  @override
  String get onlineSearchToggleSubtitle =>
      'Søg online og importér danse direkte (kræver internet). Lokale filtre gælder ikke.';

  @override
  String onlineSearchFieldLabel(String source) {
    return 'Søg $source';
  }

  @override
  String get onlineSearchFieldHint => 'Søg online danse efter titel…';

  @override
  String onlineResultCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count online-resultater',
      one: '1 online-resultat',
    );
    return '$_temp0';
  }

  @override
  String onlineSearchHintByPhrase(String source) {
    return 'Skriv en titel eller tilføj frase-figurer for at søge $source.';
  }

  @override
  String onlineSearchHintTitle(String source) {
    return 'Skriv en titel for at søge $source.';
  }

  @override
  String onlineNoResults(String source) {
    return 'Ingen danse på $source matcher din søgning.';
  }

  @override
  String onlineLoadError(String source) {
    return 'Kunne ikke indlæse den dans fra $source.';
  }

  @override
  String get onlineImportError => 'Kunne ikke importere den dans.';

  @override
  String onlineImportCreated(String title) {
    return 'Importerede „$title“.';
  }

  @override
  String onlineImportAlreadyInCollection(String title) {
    return '„$title“ er allerede i din samling.';
  }

  @override
  String get onlineAttributionCallersBox => 'Fra The Caller\'s Box (online)';

  @override
  String get onlineAttributionContraDb => 'Fra ContraDB (online)';

  @override
  String get importDances => 'Importér danse';

  @override
  String get importAction => 'Importér';

  @override
  String get importProgramTooltip => 'Importér program';

  @override
  String get importFromTitleList => 'Fra titelliste';

  @override
  String get importFromContraDb => 'Fra ContraDB';

  @override
  String get importProgramTitleLabel => 'Programtitel';

  @override
  String get importProgramCreateError =>
      'Kunne ikke gemme det importerede program.';

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
      other: '$notes noter',
      one: '1 note',
    );
    return 'Importerede „$title“ – $_temp0 ($linked tilknyttet, $_temp1).';
  }

  @override
  String get importContraDbTitle => 'Importér fra ContraDB';

  @override
  String get importContraDbPasteUrl => 'Indsæt URL';

  @override
  String get importContraDbSearchByName => 'Søg efter navn';

  @override
  String get importContraDbUrlLabel => 'ContraDB-program-URL';

  @override
  String get importContraDbUrlHint => 'f.eks. https://contradb.com/programs/33';

  @override
  String get importContraDbFetching => 'Henter…';

  @override
  String get importContraDbFetch => 'Hent program';

  @override
  String get importContraDbSearchLabel => 'Søg ContraDB-programmer';

  @override
  String get importContraDbSearchHint => 'Skriv en del af et programnavn';

  @override
  String get importContraDbListError =>
      'Kunne ikke indlæse ContraDB-programlisten.';

  @override
  String get importContraDbSearchPrompt =>
      'Skriv en del af et programnavn for at søge ContraDB.';

  @override
  String get importContraDbNoMatches => 'Ingen matchende programmer.';

  @override
  String importContraDbFetchError(String error) {
    return 'Kunne ikke hente det program.\n$error';
  }

  @override
  String get importContraDbFetchGenericError => 'Kunne ikke hente det program.';

  @override
  String get importContraDbPastePrompt =>
      'Indsæt en ContraDB-program-URL ovenfor og tryk \"Hent program\".';

  @override
  String get importContraDbEmptyProgram =>
      'Ingen danse eller noter fundet på den programside.';

  @override
  String get importContraDbResolveError =>
      'Kunne ikke importere ContraDB-programmet.';

  @override
  String importContraDbActivityCount(int activities, int dances, int notes) {
    String _temp0 = intl.Intl.pluralLogic(
      activities,
      locale: localeName,
      other: '$activities aktiviteter',
      one: '1 aktivitet',
    );
    String _temp1 = intl.Intl.pluralLogic(
      dances,
      locale: localeName,
      other: '$dances danse',
      one: '1 dans',
    );
    String _temp2 = intl.Intl.pluralLogic(
      notes,
      locale: localeName,
      other: '$notes noter',
      one: '1 note',
    );
    return '$_temp0 ($_temp1, $_temp2)';
  }

  @override
  String get importContraDbDanceFallback => 'ContraDB-dans';

  @override
  String get importEventDateNone => 'Ingen dato angivet';

  @override
  String get importEventDateLabel => 'Begivenhedsdato';

  @override
  String get importEventDateSet => 'Angiv dato';

  @override
  String get importEventDateClear => 'Ryd begivenhedsdato';

  @override
  String get importEventDateDetected =>
      'Dato registreret fra titel – kontrollér den inden import.';

  @override
  String get importTitleListTitle => 'Importér fra titelliste';

  @override
  String get importCollectionLoadError => 'Kunne ikke indlæse din samling.';

  @override
  String get importTitleListDancesLabel => 'Dansetitler (én pr. linje)';

  @override
  String get importTitleListDancesHint =>
      'Indsæt én dansetitel pr. linje.\nUigenkendte linjer gemmes som noter.';

  @override
  String get importTitleListEmptyHint =>
      'Indsæt en liste med dansetitler ovenfor for at forhåndsvise programmet.';

  @override
  String get importResolving => 'Søger…';

  @override
  String get importResolveOnline => 'Opløs umatchede online';

  @override
  String get importPlaintextImportedOnline => 'Importeret fra Caller\'s Box';

  @override
  String get importPlaintextLinked => 'Knyttet til dans';

  @override
  String get importPlaintextAmbiguous => 'Flere matches – tilføjet som note';

  @override
  String get importPlaintextUnmatched => 'Intet match – tilføjet som note';

  @override
  String get importPlaintextSearchError => 'Kunne ikke søge The Caller\'s Box.';

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
      other: '$remaining titler beholdt som noter',
      one: '$remaining titel beholdt som note',
    );
    return 'Ingen sikre Caller\'s Box-matches fundet – $_temp0.';
  }

  @override
  String importPlaintextResolvedLinked(int linked, int remaining) {
    String _temp0 = intl.Intl.pluralLogic(
      linked,
      locale: localeName,
      other: '$linked titler',
      one: '$linked titel',
    );
    String _temp1 = intl.Intl.pluralLogic(
      remaining,
      locale: localeName,
      other: '; $remaining stadig noter.',
      one: '; $remaining stadig en note.',
      zero: '.',
    );
    return 'Tilknyttede $_temp0 fra The Caller\'s Box$_temp1';
  }

  @override
  String get importReviewClose => 'Luk import';

  @override
  String get importReviewSourceLabel => 'Kilde';

  @override
  String importReviewFromSource(String source) {
    return 'Importér fra $source.';
  }

  @override
  String importReviewDancesFromSource(String source) {
    return 'Importér danse fra $source.';
  }

  @override
  String get importSourceLabelGenericJson => 'en Caller\'s Compendium JSON-fil';

  @override
  String get importSourceLabelCallersBox => 'The Caller\'s Box';

  @override
  String get importSourceLabelContraDb => 'ContraDB';

  @override
  String get importSourceLabelCallersCompanionUsr =>
      'en Caller\'s Companion .USR-fil';

  @override
  String get importErrorFileTooLarge => 'Den fil er for stor til at importere.';

  @override
  String get importErrorInsecureScheme =>
      'Imports skal bruge en sikker https://-URL.';

  @override
  String get importErrorBlockedHost =>
      'Den URL peger på en netværksplacering, der ikke kan importeres fra.';

  @override
  String get importErrorInvalidUrl => 'Det ligner ikke en gyldig http(s)-URL.';

  @override
  String get importErrorTooManyRedirects =>
      'Den URL omdirigerede for mange gange.';

  @override
  String get importErrorResponseTooLarge =>
      'Det svar var for stort til at importere.';

  @override
  String get importErrorEmptyUrl => 'Indtast en URL at importere fra.';

  @override
  String importErrorTimeout(int seconds) {
    return 'Anmodningen fik timeout efter ${seconds}s. Kontrollér URL\'en og din forbindelse, og prøv igen.';
  }

  @override
  String get importErrorUnreachable =>
      'Kunne ikke nå den URL. Kontrollér URL\'en og din forbindelse, og prøv igen.';

  @override
  String importErrorHttpStatus(int status) {
    return 'Serveren svarede med HTTP $status.';
  }

  @override
  String get importErrorEmptyResponse => 'URL\'en returnerede et tomt svar.';

  @override
  String get importErrorCallersBoxEmptyInput =>
      'Indtast en Caller\'s Box dans-URL eller id at importere fra.';

  @override
  String get importErrorCallersBoxInvalidUrl =>
      'Det ligner ikke en Caller\'s Box dans-URL eller et numerisk id.';

  @override
  String get importErrorCallersBoxMissingId =>
      'Den Caller\'s Box-URL mangler et dans-id (…dance.php?id=N).';

  @override
  String get importErrorCallersBoxEmptySearch =>
      'Indtast en titel eller frase-figurer for at søge The Caller\'s Box.';

  @override
  String importErrorSearchTimeout(int seconds) {
    return 'Søgningen fik timeout efter ${seconds}s. Kontrollér din forbindelse, og prøv igen.';
  }

  @override
  String get importErrorCallersBoxUnreachable =>
      'Kunne ikke nå The Caller\'s Box. Kontrollér din forbindelse, og prøv igen.';

  @override
  String importErrorCallersBoxHttpStatus(int status) {
    return 'The Caller\'s Box svarede med HTTP $status.';
  }

  @override
  String get importErrorCallersBoxEmptyPage =>
      'The Caller\'s Box returnerede en tom side.';

  @override
  String get importErrorCallersBoxNoDance =>
      'The Caller\'s Box returnerede ingen importerbar dans.';

  @override
  String get importErrorCallersBoxImportFailed =>
      'The Caller\'s Box-dansen kunne ikke importeres.';

  @override
  String get importErrorContraDbEmptyTitle =>
      'Indtast en titel for at søge ContraDB.';

  @override
  String get importErrorContraDbEmptyDanceInput =>
      'Indtast en ContraDB dans-URL eller id at importere fra.';

  @override
  String get importErrorContraDbInvalidDanceUrl =>
      'Det ligner ikke en ContraDB dans-URL eller et numerisk id.';

  @override
  String get importErrorContraDbMissingDanceId =>
      'Den ContraDB-URL mangler et dans-id (…/dances/N).';

  @override
  String get importErrorContraDbEmptyProgramInput =>
      'Indtast en ContraDB program-URL eller id at importere fra.';

  @override
  String get importErrorContraDbInvalidProgramUrl =>
      'Det ligner ikke en ContraDB program-URL eller et numerisk id.';

  @override
  String get importErrorContraDbMissingProgramId =>
      'Den ContraDB-URL mangler et program-id (…/programs/N).';

  @override
  String get importErrorContraDbInvalidProgramLink =>
      'Det ligner ikke et ContraDB-programlink.';

  @override
  String get importErrorContraDbUnreachable =>
      'Kunne ikke nå ContraDB. Kontrollér din forbindelse, og prøv igen.';

  @override
  String importErrorContraDbHttpStatus(int status) {
    return 'ContraDB svarede med HTTP $status.';
  }

  @override
  String get importErrorContraDbEmptyResponse =>
      'ContraDB returnerede et tomt svar.';

  @override
  String get importErrorContraDbNoDance =>
      'ContraDB returnerede ingen importerbar dans.';

  @override
  String get importErrorContraDbImportFailed =>
      'ContraDB-dansen kunne ikke importeres.';

  @override
  String get importReviewUsrSubtitle =>
      'Vælg Caller\'s Companion .USR-filen for at migrere dens danse og programhistorik. Intet tilføjes til din samling, før du bekræfter.';

  @override
  String get importReviewChooseUsr => 'Vælg .USR-fil…';

  @override
  String importReviewFileReady(int bytes) {
    return 'Fil klar ($bytes bytes).';
  }

  @override
  String get importReviewGenericSubtitle =>
      'Vælg en fil, indsæt dens indhold, eller hent den fra en URL. Intet tilføjes til din samling, før du bekræfter.';

  @override
  String get importReviewChooseFile => 'Vælg fil…';

  @override
  String get importReviewUrlLabel => 'Dans-URL eller id';

  @override
  String get importReviewUrlLabelGeneric => 'Importér fra URL';

  @override
  String get importReviewUrlHint =>
      'https://www.ibiblio.org/contradance/thecallersbox/dance.php?id=1  · eller · 1';

  @override
  String get importReviewUrlHintGeneric => 'https://…';

  @override
  String get importReviewFetch => 'Hent';

  @override
  String get importReviewPasteJson => 'Eller indsæt JSON';

  @override
  String get importReviewReviewButton => 'Gennemse import';

  @override
  String importReviewWillImport(int importable, int total) {
    return '$importable af $total importeres';
  }

  @override
  String get importReviewCouldNotRead => 'Kunne ikke læse importen';

  @override
  String get importReviewNoDancesTitle => 'Ingen danse fundet';

  @override
  String get importReviewNoDancesBody =>
      'Filen indeholdt ingen danse at importere.';

  @override
  String get importReviewTryAnother => 'Prøv en anden fil';

  @override
  String get importReviewImported => 'Importeret';

  @override
  String importReviewStructured(int structured, int total) {
    return '$structured/$total struktureret';
  }

  @override
  String get importReviewCustom => 'Brugerdefineret';

  @override
  String get importReviewOptionNewDance => 'Ny dans';

  @override
  String get importReviewOptionSkip => 'Spring over';

  @override
  String importReviewOptionReimport(String title) {
    return 'Reimportér på „$title“';
  }

  @override
  String get importReviewOptionDuplicate => 'Importér som ny (duplikat) dans';

  @override
  String get importReviewPossibleMatch =>
      'Muligt match – vælg hvordan den importeres:';

  @override
  String importReviewOptionLink(String title, int percent) {
    return 'Knyt til „$title“ ($percent% match)';
  }

  @override
  String importReviewOverwriteWarning(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count eksisterende danse overskrives',
      one: '1 eksisterende dans overskrives',
    );
    return '$_temp0';
  }

  @override
  String importReviewWarningPrefix(String message) {
    return 'Advarsel: $message';
  }

  @override
  String get importReviewComplete => 'Import fuldført';

  @override
  String sharedImportSoftCapWarning(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Denne import indeholder $count elementer – mere end forventet for en normal deling.',
      one:
          'Denne import indeholder 1 element – mere end forventet for en normal deling.',
    );
    return '$_temp0';
  }

  @override
  String sharedImportComplete(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Importerede $count elementer.',
      one: 'Importerede 1 element.',
      zero: 'Import fuldført.',
    );
    return '$_temp0';
  }

  @override
  String sharedImportProgramsOnly(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Denne deling indeholder $count programmer og ingen danse.',
      one: 'Denne deling indeholder 1 program og ingen danse.',
    );
    return '$_temp0';
  }

  @override
  String importReviewSummaryCreated(int count) {
    return 'Oprettet: $count';
  }

  @override
  String importReviewSummaryReimported(int count) {
    return 'Reimporteret: $count';
  }

  @override
  String importReviewSummaryLinked(int count) {
    return 'Knyttet: $count';
  }

  @override
  String importReviewSummaryDuplicated(int count) {
    return 'Kopieret: $count';
  }

  @override
  String importReviewSummarySkipped(int count) {
    return 'Sprunget over: $count';
  }

  @override
  String importReviewSummaryPrograms(int count) {
    return 'Programmer: $count';
  }

  @override
  String importReviewProgramsUpdated(int count) {
    return '$count opdateret (reimporteret)';
  }

  @override
  String importReviewProgramNotes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count programnoter:',
      one: '$count programnote:',
    );
    return '$_temp0';
  }

  @override
  String importReviewRecordsFailed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count poster kunne ikke importeres:',
      one: '$count post kunne ikke importeres:',
    );
    return '$_temp0';
  }

  @override
  String importReviewBatchErrors(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count poster kunne ikke læses (resten kan stadig importeres):',
      one: '$count post kunne ikke læses (resten kan stadig importeres):',
    );
    return '$_temp0';
  }

  @override
  String get importReviewUntitledProgram => 'Unavngivet program';

  @override
  String get importReviewUndoWithPrograms =>
      'Fortryd (fjerner de importerede danse og programmer)';

  @override
  String get importReviewUndone => 'Import fortrudt.';

  @override
  String get importReviewEditError =>
      'Kunne ikke importere den dans til redigering.';

  @override
  String get importReviewImportError => 'Kunne ikke fuldføre importen.';

  @override
  String get danceEditorDetailsSection => 'Detaljer';

  @override
  String get danceEditorTitleRequiredLabel => 'Titel *';

  @override
  String get danceEditorTitleRequired => 'Titel er påkrævet';

  @override
  String get danceEditorAuthorsLabel => 'Forfattere';

  @override
  String get danceEditorFormationLabel => 'Formation';

  @override
  String get danceEditorFormationDetailLabel => 'Formationsdetalje (valgfrit)';

  @override
  String get danceEditorPhraseStructureLabel => 'Frastruktur';

  @override
  String get danceEditorPhraseStructureHint =>
      'Tom = standard A1 A2 B1 B2; ellers f.eks. 6*8*2';

  @override
  String get danceEditorFiguresSection => 'Figurer';

  @override
  String get danceEditorFiguresHelp =>
      'Skriv en bevægelse (f.eks. \"sw\" → swing) og tryk Enter for at tilføje den med standardparametre; umatched tekst gemmes som en brugerdefineret figur.';

  @override
  String get danceEditorNotesSection => 'Noter';

  @override
  String get danceEditorCallingNotesLabel => 'Kaldsnotes';

  @override
  String get danceEditorHookLabel => 'Hook';

  @override
  String get danceEditorHookHint => 'Én linje „hvorfor kalde denne dans“';

  @override
  String get danceEditorMoreDetailsTitle => 'Flere detaljer';

  @override
  String get danceEditorStatusLabel => 'Status';

  @override
  String get danceEditorMixedLevelSubtitle => 'Spænder over sværhedsskalaen';

  @override
  String get danceEditorComposedLabel => 'Komponeret';

  @override
  String get danceEditorComposedHelper =>
      'Hvornår dansen blev komponeret (år, eller tilføj måned/dag)';

  @override
  String get danceEditorRevisedLabel => 'Revideret';

  @override
  String get danceEditorRevisedHelper =>
      'Hvornår dansen sidst blev revideret af dens forfatter';

  @override
  String get danceEditorTagsLabel => 'Tags';

  @override
  String get danceEditorTunesLabel => 'Melodier';

  @override
  String get danceEditorLinksLabel => 'Links';

  @override
  String get danceEditorPublishedSourcesLabel => 'Publicerede kilder';

  @override
  String get danceEditorRelatedDancesLabel => 'Relaterede danse';

  @override
  String get danceEditorCustomFieldsLabel => 'Brugerdefinerede felter';

  @override
  String get danceEditorRatingLabel => 'Vurdering';

  @override
  String get danceEditorRatingUnrated => 'ikke vurderet';

  @override
  String danceEditorRatingValue(int rating, int max) {
    return '$rating af $max stjerner';
  }

  @override
  String danceEditorSetRatingTooltip(int rating, int max) {
    return 'Angiv vurdering til $rating af $max stjerner';
  }

  @override
  String get danceEditorClearRating => 'Ryd vurdering';

  @override
  String get danceEditorLevelLabel => 'Niveau';

  @override
  String get danceEditorLevelUnspecified => 'Uspecificeret';

  @override
  String get danceEditorYearLabel => 'År';

  @override
  String get danceEditorYearHint => 'f.eks. 1989';

  @override
  String get danceEditorYearRangeError => '1–9999';

  @override
  String get danceEditorMonthLabel => 'Måned';

  @override
  String get danceEditorDayLabel => 'Dag';

  @override
  String get danceEditorMonthJan => 'Jan';

  @override
  String get danceEditorMonthFeb => 'Feb';

  @override
  String get danceEditorMonthMar => 'Mar';

  @override
  String get danceEditorMonthApr => 'Apr';

  @override
  String get danceEditorMonthMay => 'Maj';

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
  String get danceEditorAddTuneHint => 'Tilføj en foreslået melodi…';

  @override
  String get danceEditorAddTuneTooltip => 'Tilføj melodi';

  @override
  String get danceEditorWarningsTitle => 'Advarsler';

  @override
  String danceEditorDiscouragedTermSemantic(String term) {
    return 'Frarådet term: $term';
  }

  @override
  String danceEditorDiscouragedTermText(String term) {
    return 'Frarådet: $term';
  }

  @override
  String get danceEditorLinkKindSource => 'Kilde';

  @override
  String get danceEditorLinkKindVideo => 'Video';

  @override
  String get danceEditorLinkKindOther => 'Andet';

  @override
  String get danceEditorUrlLabel => 'URL';

  @override
  String get danceEditorLabelOptional => 'Etiket (valgfrit)';

  @override
  String get danceEditorRemoveLinkTooltip => 'Fjern link';

  @override
  String get danceEditorAddLink => 'Tilføj link';

  @override
  String get danceEditorMissingDance => '(manglende dans)';

  @override
  String get danceEditorNoteOptionalLabel => 'Note (valgfrit)';

  @override
  String get danceEditorRemoveRelatedDanceTooltip => 'Fjern relateret dans';

  @override
  String get danceEditorAddRelatedDance => 'Tilføj relateret dans';

  @override
  String get danceEditorRelatedDanceLabel => 'Relateret dans';

  @override
  String get danceEditorTypeToSearchHint => 'Skriv for at søge…';

  @override
  String danceEditorEditItemTooltip(String item) {
    return 'Rediger $item';
  }

  @override
  String get danceEditorTypeToAddOrCreateHint =>
      'Skriv for at tilføje eller oprette…';

  @override
  String danceEditorCreateQuotedName(String name) {
    return 'Opret „$name“';
  }

  @override
  String get danceEditorUnknownSource => '(ukendt kilde)';

  @override
  String get danceEditorPageOptionalLabel => 'Side (valgfrit)';

  @override
  String get danceEditorNumberOptionalLabel => 'Nummer (valgfrit)';

  @override
  String get danceEditorCiteSourceHint =>
      'Anfør en kilde: skriv for at tilføje eller oprette…';

  @override
  String get danceEditorSaveError => 'Kunne ikke gemme dansen.';

  @override
  String get danceEditorFallbackDanceTitle => 'Dans';

  @override
  String get danceEditorUnsavedDraftTitle => 'Ugemt kladde';

  @override
  String get danceEditorUnsavedDraftMessage =>
      'Du har en ugemt kladde til denne dans. Vil du gendanne den?';

  @override
  String get danceEditorDiscard => 'Kassér';

  @override
  String get danceEditorRestore => 'Gendan';

  @override
  String get danceEditorDiscardChangesTitle => 'Kassér ændringer?';

  @override
  String get danceEditorDiscardChangesMessage =>
      'Du har ugemte ændringer i denne dans.';

  @override
  String get danceEditorKeepEditing => 'Fortsæt redigering';

  @override
  String get danceEditorNewDanceTitle => 'Ny dans';

  @override
  String get danceEditorEditDanceTitle => 'Rediger dans';

  @override
  String get danceEditorRedoLabel => 'Annullér fortryd';

  @override
  String get danceEditorUndoShortcutTooltip => 'Fortryd (Ctrl+Z)';

  @override
  String get danceEditorRedoShortcutTooltip =>
      'Annullér fortryd (Ctrl+Shift+Z)';

  @override
  String get danceEditorDeleteDanceTooltip => 'Slet dans';

  @override
  String get danceEditorLoadError => 'Kunne ikke indlæse dansen.';

  @override
  String get danceEditorChoreographerDetailsTitle => 'Koreografdetaljer';

  @override
  String get danceEditorChoreographerDetailsIntro =>
      'Disse detaljer deles på tværs af alle danse krediteret til denne forfatter. E-mail og placering er private og inkluderes ikke i eksporter.';

  @override
  String get danceEditorNameRequiredLabel => 'Navn *';

  @override
  String get danceEditorNameRequired => 'Navn er påkrævet';

  @override
  String get danceEditorWebsiteLabel => 'Hjemmeside';

  @override
  String get danceEditorEmailPrivateLabel => 'E-mail (privat)';

  @override
  String get danceEditorLocationPrivateLabel => 'Placering (privat)';

  @override
  String get danceEditorNotesLabel => 'Noter';

  @override
  String get danceEditorDeceasedLabel => 'Afdød';

  @override
  String get danceEditorSourceDetailsTitle => 'Kildedetaljer';

  @override
  String get danceEditorSourceDetailsIntro =>
      'Disse detaljer deles på tværs af alle danse, der citerer denne kilde. Redigering af dem her opdaterer dem overalt.';

  @override
  String get danceEditorSourceAuthorEditorLabel => 'Forfatter / redaktør';

  @override
  String get danceEditorEnterWholeNumber => 'Indtast et heltal';

  @override
  String get danceEditorEnterPositiveYear => 'Indtast et positivt år';

  @override
  String danceEditorAddedFigureChooseMove(int count) {
    return 'Tilføjede figur $count. Vælg en bevægelse.';
  }

  @override
  String danceEditorFigurePastedAnnouncement(int position) {
    return 'Figur indsat ved position $position.';
  }

  @override
  String danceEditorFigureMovedAnnouncement(int position, int total) {
    return 'Flyttet til position $position af $total.';
  }

  @override
  String danceEditorEditingFigureAnnouncement(int position, String name) {
    return 'Redigerer figur $position, $name.';
  }

  @override
  String danceEditorCollapsedFigureAnnouncement(int position) {
    return 'Kollapsede figur $position.';
  }

  @override
  String get danceEditorTypeFigureAnnouncement =>
      'Skriv en figur og tryk Enter for at tilføje den.';

  @override
  String danceEditorFreeTextFiguresAddedAnnouncement(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Tilføjede $count figurer. Skriv en anden, eller tryk Escape for at afslutte.',
      one:
          'Tilføjede 1 figur. Skriv en anden, eller tryk Escape for at afslutte.',
    );
    return '$_temp0';
  }

  @override
  String danceEditorDeletedFigureAnnouncement(int position) {
    return 'Slettede figur $position. Fortryd er tilgængeligt.';
  }

  @override
  String danceEditorDuplicatedFigureAnnouncement(int position) {
    return 'Kopierede figur $position.';
  }

  @override
  String get danceEditorAddFirstFigure => 'Tilføj første figur';

  @override
  String danceEditorCutBanner(String figure) {
    return '„$figure“ er klippet – tryk Indsæt for at placere det.';
  }

  @override
  String get danceEditorPasteBeforeFirstFigure => 'Indsæt før første figur';

  @override
  String danceEditorPasteAfterFigure(String figure) {
    return 'Indsæt efter $figure';
  }

  @override
  String get danceEditorAddFigure => 'Tilføj figur';

  @override
  String get danceEditorPasteAtEndOfFigureList =>
      'Indsæt i slutningen af figurlisten';

  @override
  String get danceEditorTypeFigureLabel => 'Skriv en figur';

  @override
  String get danceEditorTypeFigureHelper =>
      'f.eks. „nabo balance & swing“ eller „16 circle left 3/4“. Enter tilføjer den; uigenkendt tekst gemmes som en brugerdefineret figur.';

  @override
  String get danceEditorPasteHere => 'Indsæt her';

  @override
  String get danceEditorEmptyFigureName => 'Tom figur';

  @override
  String get danceEditorCustomFigureName => 'Brugerdefineret figur';

  @override
  String get danceEditorEmptyFigureSummary => '(tom – vælg en bevægelse)';

  @override
  String get danceEditorEmptyFigureSemantic => 'tom figur, vælg en bevægelse';

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
      'yes': ', progression',
      'other': '',
    });
    String _temp2 = intl.Intl.pluralLogic(
      beats,
      locale: localeName,
      other: '$beats slag',
      one: '1 slag',
    );
    String _temp3 = intl.Intl.selectLogic(hasMove, {
      'yes': ', $_temp2',
      'other': '',
    });
    String _temp4 = intl.Intl.selectLogic(hasNote, {
      'yes': ', note: $note',
      'other': '',
    });
    return '$main$_temp0$_temp1$_temp3$_temp4. Figur $position af $total.';
  }

  @override
  String get danceEditorActivateToEditHint => 'Aktiver for at redigere';

  @override
  String danceEditorDragToReorderFigure(String figure) {
    return 'Træk for at omarrangere $figure';
  }

  @override
  String danceEditorFigureActionsTooltip(String figure) {
    return 'Handlinger for $figure';
  }

  @override
  String get danceEditorMoveUp => 'Flyt op';

  @override
  String get danceEditorMoveDown => 'Flyt ned';

  @override
  String get danceEditorCut => 'Klip';

  @override
  String get danceEditorClearProgression => 'Ryd progression';

  @override
  String get danceEditorMarkProgression => 'Markér progression';

  @override
  String danceEditorUnrecognizedMoveReadOnly(String move) {
    return 'Ukendt bevægelse „$move“ – ikke i denne versions taksonomi. Vist som skrivebeskyttet, så dens data er bevaret.';
  }

  @override
  String get danceEditorFewerOptions => 'Færre muligheder';

  @override
  String danceEditorMoreOptions(int count) {
    return 'Flere muligheder ($count)';
  }

  @override
  String get danceEditorMoveCanCarryProgression =>
      'Denne bevægelse kan bære progressionen.';

  @override
  String get danceEditorAddNote => 'Tilføj note';

  @override
  String get danceEditorBoldTooltip => 'Fed (*tekst*)';

  @override
  String get danceEditorUnderlineTooltip => 'Understreget (_tekst_)';

  @override
  String get danceEditorCustomFigureTextLabel => 'Brugerdefineret figurtekst';

  @override
  String get danceEditorLingoStylingHelper =>
      'Bevægelses navne prikket·understreget, rolleudtryk understreget, frarådte termer gennemstreget';

  @override
  String danceEditorBeatTotal(int total, int expected) {
    return 'Total: $total / $expected slag';
  }

  @override
  String danceEditorOverByBeats(int beats) {
    return 'Over med $beats slag';
  }

  @override
  String danceEditorUnderByBeats(int beats) {
    return 'Under med $beats slag';
  }

  @override
  String get danceEditorLessTooltip => 'Færre';

  @override
  String get danceEditorMoreTooltip => 'Flere';

  @override
  String danceEditorTurnCount(num count, String formatted) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$formatted drejninger',
      one: '$formatted drejning',
    );
    return '$_temp0';
  }

  @override
  String get commonBack => 'Tilbage';

  @override
  String get commonRemove => 'Fjern';

  @override
  String updateBannerDownloading(String appName, String version) {
    return 'Henter $appName $version…';
  }

  @override
  String updateBannerDownloadingPct(String appName, String version, int pct) {
    return 'Henter $appName $version… $pct%';
  }

  @override
  String updateBannerVerifying(String appName, String version) {
    return 'Verificerer $appName $version…';
  }

  @override
  String get updateBannerPreparingInstaller =>
      'Forbereder installationsprogrammet…';

  @override
  String updateBannerCompletedRevealed(String appName, String version) {
    return '$appName $version hentet og verificeret – vi viste installationsprogrammet i din filhåndtering.';
  }

  @override
  String updateBannerCompletedManual(String appName, String version) {
    return '$appName $version hentet – følg installationsprogrammet for at fuldføre opdateringen.';
  }

  @override
  String get updateBannerDownloadFailed => 'Opdateringen kunne ikke hentes.';

  @override
  String updateBannerAvailable(String appName, String version) {
    return 'En nyere version af $appName ($version) er tilgængelig.';
  }

  @override
  String get updateBannerViewRelease => 'Se udgivelse';

  @override
  String get updateBannerDismiss => 'Afvis';

  @override
  String get updateBannerDownloadInstall => 'Hent og installer';

  @override
  String get commandPaletteBarrierLabel => 'Global søgning';

  @override
  String get commandPaletteSearchHint => 'Søg danse og programmer…';

  @override
  String get commandPaletteProgramSubtitle => 'Program';

  @override
  String get commandPaletteEmptyInitial => 'Intet at søge endnu.';

  @override
  String get commandPaletteNoMatches => 'Ingen matches for den søgning.';

  @override
  String get commandPaletteGroupDances => 'Danse';

  @override
  String get commandPaletteGroupPrograms => 'Programmer';

  @override
  String get collectionPickerSearchLabel => 'Find en dans at tilføje';

  @override
  String collectionPickerFilters(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Filtre ($count aktive)',
      zero: 'Filtre',
    );
    return '$_temp0';
  }

  @override
  String collectionPickerByPhrase(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Efter frase ($count aktive)',
      zero: 'Efter frase',
    );
    return '$_temp0';
  }

  @override
  String get collectionPickerAdvanced => 'Avanceret';

  @override
  String get collectionPickerUseAdvancedQuery => 'Brug avanceret forespørgsel';

  @override
  String get collectionPickerAdvancedQueryHelp =>
      'Kombiner figurer og sekvenser med alle / nogen / ingen grupper.';

  @override
  String collectionPickerAddSemantic(String title) {
    return 'Tilføj $title til program';
  }

  @override
  String collectionPickerAddTooltip(String title) {
    return 'Tilføj $title';
  }

  @override
  String get userGuideTitle => 'Brugervejledning';

  @override
  String userGuideMissing(String label) {
    return 'Vejledningen „$label“ er ikke tilgængelig endnu.';
  }

  @override
  String get userGuideLoadError => 'Brugervejledningen kunne ikke indlæses.';

  @override
  String get userGuideOpenOnline => 'Åbn vejledningen online';

  @override
  String get shorthandMappingsTitle => 'Figurkortformer';

  @override
  String get shorthandMappingsIntro =>
      'Kortformer lader dig skrive et kort token under fri tekstindtastning og få det udvidet til en eller flere figurer.';

  @override
  String get shorthandMappingsNew => 'Ny kortform';

  @override
  String get shorthandMappingsEmpty => 'Ingen kortformer endnu.';

  @override
  String get shorthandMappingsDeleteTitle => 'Slet kortform?';

  @override
  String shorthandMappingsDeleteBody(String token) {
    return '„$token“ fjernes permanent.';
  }

  @override
  String get shorthandMappingsActionsTooltip => 'Kortformhandlinger';

  @override
  String get shorthandEditorTitleNew => 'Ny kortform';

  @override
  String get shorthandEditorTitleEdit => 'Rediger kortform';

  @override
  String get shorthandEditorTokenLabel => 'Kortform';

  @override
  String get shorthandEditorTokenHelper =>
      'Skriv denne nøjagtige linje under fri tekstindtastning for at indsætte figurerne nedenfor. Matches store/små bogstaver ufølsomt.';

  @override
  String get shorthandEditorExpandsTo => 'Udvider til';

  @override
  String get shorthandEditorExpandsToHelp =>
      'Den/de figur(er) denne kortform indsætter, i rækkefølge. Bygget nøjagtigt som en normal figur, så parametre og progression virker.';

  @override
  String get shorthandEditorErrorEmpty => 'Indtast et kortform-token.';

  @override
  String shorthandEditorErrorTooLong(int max) {
    return 'Kortform er for lang (maks. $max tegn).';
  }

  @override
  String shorthandEditorErrorDuplicate(String token) {
    return 'En anden kortform bruger allerede „$token“ (kortformer matches store/små bogstaver ufølsomt).';
  }

  @override
  String get shorthandEditorErrorNoFigures =>
      'Tilføj mindst én figur, som denne kortform skal udvide til.';

  @override
  String get themeEditorTitle => 'Rediger tema';

  @override
  String get themeEditorNameLabel => 'Temanavn';

  @override
  String get themeEditorContrastAllPass =>
      'Alle markerede par består WCAG AA-kontrast.';

  @override
  String themeEditorContrastFailing(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count kontrastpar under WCAG AA. Du kan stadig gemme, men noget tekst kan være svær at læse.',
      one:
          '1 kontrastpar under WCAG AA. Du kan stadig gemme, men noget tekst kan være svær at læse.',
    );
    return '$_temp0';
  }

  @override
  String themeEditorRatioPass(String ratio) {
    return '$ratio:1 AA';
  }

  @override
  String themeEditorRatioFail(String ratio) {
    return '$ratio:1 fejl';
  }

  @override
  String get themeEditorPreviewHeading => 'Aa Forhåndsvisning';

  @override
  String get themeEditorBodySample => 'Eksempel på brødtekst';

  @override
  String get themeEditorSwatchPrimary => 'Primær';

  @override
  String get themeEditorSwatchSecondary => 'Sekundær';

  @override
  String get themeEditorSwatchTertiary => 'Tertiær';

  @override
  String get themeEditorSwatchError => 'Fejl';

  @override
  String get reparseConfirmTitle => 'Opgradér brugerdefinerede figurer?';

  @override
  String reparseConfirmBody(int figureCount, int danceCount) {
    String _temp0 = intl.Intl.pluralLogic(
      figureCount,
      locale: localeName,
      other: '$figureCount figurer',
      one: '1 figur',
    );
    String _temp1 = intl.Intl.pluralLogic(
      danceCount,
      locale: localeName,
      other: '$danceCount danse',
      one: '1 dans',
    );
    return 'Dette vil genparsere $_temp0 i $_temp1. Dine tags, vurderinger, noter og alt andet på hver dans bevares nøjagtigt som de er. Dette erstatter kun figurer, der nu genkender en kendt bevægelse.';
  }

  @override
  String get reparseConfirmUpgrade => 'Opgradér';

  @override
  String get reparseFailed =>
      'Kunne ikke opgradere figurer. Prøv venligst igen.';

  @override
  String get reparseNothingUpgradedSnack => 'Intet at opgradere.';

  @override
  String reparseUpgradedSnack(int danceCount) {
    String _temp0 = intl.Intl.pluralLogic(
      danceCount,
      locale: localeName,
      other: '$danceCount danse',
      one: '1 dans',
    );
    return 'Opgraderede brugerdefinerede figurer i $_temp0.';
  }

  @override
  String get reparseScreenTitle => 'Genkontrollér brugerdefinerede figurer';

  @override
  String reparseIntro(int figureCount, int danceCount) {
    String _temp0 = intl.Intl.pluralLogic(
      figureCount,
      locale: localeName,
      other: '$figureCount figurer',
      one: '1 figur',
    );
    String _temp1 = intl.Intl.pluralLogic(
      danceCount,
      locale: localeName,
      other: '$danceCount danse',
      one: '1 dans',
    );
    return 'Forbedret figurparsing kan opgradere $_temp0 i $_temp1. Gennemse nedenfor, og bekræft derefter – intet ændres før du gør det, og alle dine tags, vurderinger og noter bevares.';
  }

  @override
  String reparsePreviewCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count figurer',
      one: '1 figur',
    );
    return '$_temp0 at opgradere';
  }

  @override
  String reparseUpgradeButton(int danceCount) {
    String _temp0 = intl.Intl.pluralLogic(
      danceCount,
      locale: localeName,
      other: '$danceCount danse',
      one: '1 dans',
    );
    return 'Opgradér $_temp0';
  }

  @override
  String get reparseEmptyTitle => 'Intet at opgradere';

  @override
  String get reparseEmptyBody =>
      'Ingen af dine brugerdefinerede figurer fra imports kan genkendes som en kendt bevægelse lige nu. Tjek igen efter fremtidige opdateringer.';

  @override
  String get reparseErrorTitle => 'Kunne ikke kontrollere dine figurer';

  @override
  String get reparseErrorBody =>
      'Noget gik galt under scanning af din samling. Intet blev ændret. Du kan prøve igen.';

  @override
  String get customFieldsDeleteTitle => 'Slet brugerdefineret felt';

  @override
  String customFieldsDeleteBody(String label) {
    return 'Slet „$label“? Dette kan ikke fortrydes.';
  }

  @override
  String customFieldsDeleteInUse(String label, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count danse',
      one: '1 dans',
    );
    return 'Kan ikke slette „$label“: bruges stadig af $_temp0. Fjern værdien fra alle danse først.';
  }

  @override
  String customFieldsDeleteInUseUnknown(String label) {
    return 'Kan ikke slette „$label“: bruges stadig af nogle danse. Fjern værdien fra alle danse først.';
  }

  @override
  String get customFieldsTitle => 'Brugerdefinerede felter';

  @override
  String get customFieldsNewField => 'Nyt felt';

  @override
  String get customFieldsLoadError =>
      'Kunne ikke indlæse brugerdefinerede felter.';

  @override
  String get customFieldsEmpty =>
      'Ingen brugerdefinerede felter endnu.\nTryk + for at definere ét.';

  @override
  String get customFieldsFlagInList => 'I liste';

  @override
  String get customFieldsSearchable => 'Søgbar';

  @override
  String get customFieldsTypeText => 'Tekst';

  @override
  String get customFieldsTypeNumber => 'Tal';

  @override
  String get customFieldsTypeBoolean => 'Boolean';

  @override
  String get customFieldsTypeChoice => 'Valg';

  @override
  String get customFieldsValidatorMinChoice => 'Tilføj mindst ét valg';

  @override
  String customFieldsRemoveValueError(String value) {
    return 'Kan ikke fjerne „$value“: det er angivet på mindst én dans.';
  }

  @override
  String get customFieldsEditorNewTitle => 'Nyt brugerdefineret felt';

  @override
  String get customFieldsEditorEditTitle => 'Rediger brugerdefineret felt';

  @override
  String get customFieldsLabelLabel => 'Etiket *';

  @override
  String get customFieldsLabelRequired => 'Etiket er påkrævet';

  @override
  String get customFieldsKeyLabel => 'Nøgle *';

  @override
  String get customFieldsKeyHelper =>
      'Stabil maskinnøgle (bogstaver, cifre, underscores; skal starte med et bogstav eller underscore)';

  @override
  String get customFieldsKeyLocked => 'Nøgle er låst – felt bruges på danse';

  @override
  String get customFieldsKeyRequired => 'Nøgle er påkrævet';

  @override
  String get customFieldsKeyInvalid =>
      'Nøgle skal starte med et bogstav eller underscore og kun indeholde bogstaver, cifre og underscores.';

  @override
  String get customFieldsTypeFieldLabel => 'Type';

  @override
  String get customFieldsTypeLocked =>
      'Type er låst – felt har værdier på danse';

  @override
  String get customFieldsShowInList => 'Vis i liste';

  @override
  String get customFieldsShowInListSubtitle =>
      'Vis dette felts værdi i danselistens felt';

  @override
  String get customFieldsSearchableSubtitle =>
      'Eksponér dette felt som et filter i søgepanelet';

  @override
  String get customFieldsChoicesLabel => 'Valg *';

  @override
  String get customFieldsChoiceInUseTooltip => 'I brug – kan ikke fjernes';

  @override
  String get customFieldsNewChoiceHint => 'Nyt valg…';

  @override
  String get customFieldsAddChoiceTooltip => 'Tilføj valg';

  @override
  String dialectEditorTitle(String name) {
    return 'Rediger $name';
  }

  @override
  String get dialectEditorSectionRoleTerms => 'Rolletermer';

  @override
  String get dialectEditorSectionMoveSubs => 'Bevægelseserstatninger';

  @override
  String get dialectEditorSectionDancerSubs => 'Danser-erstatninger';

  @override
  String get dialectEditorSectionDiscouraged => 'Frarådte termer';

  @override
  String get dialectEditorSectionPreview => 'Forhåndsvisning';

  @override
  String get dialectEditorRole1 => 'Rolle 1';

  @override
  String get dialectEditorRole2 => 'Rolle 2';

  @override
  String get dialectEditorRolesHelp =>
      'Lad en rolle stå tom for at bruge den kanoniske term. Flertal udledes, når det er udeladt.';

  @override
  String get dialectEditorSingular => 'Ental';

  @override
  String get dialectEditorPlural => 'Flertal';

  @override
  String get dialectEditorMoveSubsAdd => 'Tilføj bevægelseserstatninger';

  @override
  String dialectEditorMoveSubsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count bevægelseserstatninger',
      one: '1 bevægelseserstatning',
    );
    return '$_temp0';
  }

  @override
  String get dialectEditorMoveSubHint => 'erstatning (brug %S til håndretning)';

  @override
  String get dialectEditorAddMove => 'Tilføj en bevægelse…';

  @override
  String get dialectEditorDancerSubsAdd => 'Tilføj danser-erstatninger';

  @override
  String dialectEditorDancerSubsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count danser-erstatninger',
      one: '1 danser-erstatning',
    );
    return '$_temp0';
  }

  @override
  String get dialectEditorDancerSubHint => 'erstatning';

  @override
  String get dialectEditorAddDancerTerm => 'Tilføj en dansertterm…';

  @override
  String get dialectEditorDiscouragedHelp =>
      'Termer som indlæsningseditoren markerer (gennemstreget) – blokeres aldrig.';

  @override
  String get dialectEditorDiscouragedEmpty => 'Ingen frarådte termer.';

  @override
  String get dialectEditorAddTermLabel => 'Tilføj en term';

  @override
  String get dialectEditorAddTermTooltip => 'Tilføj term';

  @override
  String get dialectEditorRestoreDefaults => 'Gendan standarder';

  @override
  String get dialectEditorPreviewHelp =>
      'Eksempelfigurer renderet med denne dialekt. Opdateres, når du redigerer.';

  @override
  String get recentlyDeletedTitle => 'For nylig slettet';

  @override
  String get recentlyDeletedDeleteTitle => 'Slet permanent?';

  @override
  String recentlyDeletedDeleteBody(String title) {
    return '„$title“ slettes øjeblikkeligt og kan ikke gendannes.';
  }

  @override
  String get recentlyDeletedDeleteConfirm => 'Slet permanent';

  @override
  String recentlyDeletedDeletedSnack(String title) {
    return '„$title“ slettet permanent.';
  }

  @override
  String get recentlyDeletedRestore => 'Gendan';

  @override
  String get recentlyDeletedPurgeKept => 'Bevares, indtil du sletter det';

  @override
  String recentlyDeletedPurgeCountdown(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days dage',
      one: '1 dag',
    );
    return 'Auto-slettes om $_temp0';
  }

  @override
  String get recentlyDeletedPurgeScheduled => 'Planlagt til sletning';

  @override
  String get recentlyDeletedLoadingDances =>
      'Indlæser for nylig slettede danse';

  @override
  String get recentlyDeletedLoadingPrograms =>
      'Indlæser for nylig slettede programmer';

  @override
  String get recentlyDeletedEmptyDancesKept =>
      'Intet i papirkurven. Slettede danse bevares her, indtil du fjerner dem.';

  @override
  String recentlyDeletedEmptyDancesRetention(int days) {
    return 'Intet i papirkurven. Slettede danse vises her i $days dage, inden de fjernes.';
  }

  @override
  String recentlyDeletedEmptyProgramsRetention(int days) {
    return 'Intet i papirkurven. Slettede programmer vises her i $days dage, inden de fjernes.';
  }

  @override
  String recentlyDeletedRestoredDance(String title) {
    return '„$title“ gendannet til din samling.';
  }

  @override
  String recentlyDeletedRestoredProgram(String title) {
    return '„$title“ gendannet.';
  }

  @override
  String get venueNew => 'Nyt spillested';

  @override
  String get venueLoadError => 'Kunne ikke indlæse spillesteder.';

  @override
  String get venueManagerTitle => 'Spillesteder';

  @override
  String get venueManagerSearchHint => 'Søg spillesteder…';

  @override
  String get venueManagerClearSearchTooltip => 'Ryd søgning';

  @override
  String get venueManagerEmpty =>
      'Ingen spillesteder endnu. Tilføj et med knappen nedenfor, eller fra et program når genanvendelige spillesteder er aktiveret.';

  @override
  String get venueManagerNoMatches => 'Ingen spillesteder matcher din søgning.';

  @override
  String get venueManagerDeleteTitle => 'Slet spillested?';

  @override
  String venueManagerDeleteBody(String name) {
    return 'Slet „$name“ permanent? Dette kan ikke fortrydes.';
  }

  @override
  String venueManagerDeletedSnack(String name) {
    return 'Slettede „$name“';
  }

  @override
  String venueManagerDeleteBlocked(String name) {
    return 'Kan ikke slette „$name“ mens det stadig er knyttet til et program. Skift eller fjern dets spillested på programmet først.';
  }

  @override
  String venueManagerDeleteTooltip(String name) {
    return 'Slet $name';
  }

  @override
  String get venueEditTitle => 'Rediger spillested';

  @override
  String get venueEditorSharedNote =>
      'Et spillested deles på tværs af alle programmer afholdt her, så redigering af dets adresse, kontakter eller tidsplan opdaterer alle disse programmer på én gang.';

  @override
  String get venueEditorNameLabel => 'Navn *';

  @override
  String get venueEditorNameRequired => 'Navn er påkrævet';

  @override
  String get venueEditorWebsiteLabel => 'Hjemmeside';

  @override
  String get venueEditorSponsorLabel => 'Sponsor / værtorganisation';

  @override
  String get venueEditorAddressSection => 'Adresse';

  @override
  String get venueEditorAddress1Label => 'Adresselinje 1';

  @override
  String get venueEditorAddress2Label => 'Adresselinje 2';

  @override
  String get venueEditorCityLabel => 'By';

  @override
  String get venueEditorStateLabel => 'Stat / provins';

  @override
  String get venueEditorCountryLabel => 'Land';

  @override
  String get venueEditorPostalLabel => 'Postnummer';

  @override
  String get venueEditorPlus4Label => 'ZIP+4';

  @override
  String get venueEditorScheduleSection => 'Tidsplan';

  @override
  String get venueEditorEventNameLabel => 'Begivenhedsnavn';

  @override
  String get venueEditorTimeLabel => 'Tidspunkt';

  @override
  String get venueEditorScheduleLabel => 'Tidsplan (f.eks. „2. lørdage“)';

  @override
  String get venueEditorPriceLabel => 'Pris';

  @override
  String get venueEditorContactsSection => 'Kontakter';

  @override
  String get venueEditorContact1NameLabel => 'Kontaktperson 1 navn';

  @override
  String get venueEditorContact1PhoneLabel => 'Kontaktperson 1 telefon';

  @override
  String get venueEditorContact1EmailLabel => 'Kontaktperson 1 e-mail';

  @override
  String get venueEditorContact2NameLabel => 'Kontaktperson 2 navn';

  @override
  String get venueEditorContact2PhoneLabel => 'Kontaktperson 2 telefon';

  @override
  String get venueEditorContact2EmailLabel => 'Kontaktperson 2 e-mail';

  @override
  String get venueEditorNotesSection => 'Noter';

  @override
  String get venuePickerLoading => 'Indlæser spillesteder…';

  @override
  String get venuePickerUnlinkTooltip => 'Frigør spillested';

  @override
  String get venuePickerUnresolvedTitle => 'Tilknyttet spillested ikke fundet';

  @override
  String get venuePickerUnresolvedSubtitle => 'Det kan være blevet slettet.';

  @override
  String get venuePickerClearLinkTooltip => 'Ryd tilknytning';

  @override
  String get venuePickerSearchHint => 'Søg eller tilføj et spillested…';

  @override
  String get venuePickerChangeHint => 'Skift spillested…';

  @override
  String venuePickerCreateOption(String name) {
    return 'Tilføj nyt spillested „$name“';
  }
}
