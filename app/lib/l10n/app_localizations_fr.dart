// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for French (`fr`).
class AppLocalizationsFr extends AppLocalizations {
  AppLocalizationsFr([String locale = 'fr']) : super(locale);

  @override
  String get appTitle => 'Caller\'s Compendium';

  @override
  String get navCollection => 'Collection';

  @override
  String get navPrograms => 'Programmes';

  @override
  String get navSettings => 'Paramètres';

  @override
  String get navGuide => 'Guide';

  @override
  String get navGuideTooltip => 'Guide d’utilisation';

  @override
  String get navSearch => 'Recherche';

  @override
  String navSearchTooltip(String hint) {
    return 'Rechercher ($hint)';
  }

  @override
  String get appBootstrapPreparing => 'Préparation de votre collection';

  @override
  String get appBootstrapRebuildingIndex =>
      'Reconstruction de l’index de recherche';

  @override
  String appBootstrapRebuildingIndexProgress(int percent) {
    return 'Reconstruction de l’index… $percent %';
  }

  @override
  String get appBootstrapError => 'Impossible de préparer la collection.';

  @override
  String get migrationDowngradeMessage =>
      'Ces données ont été créées avec une version plus récente de Caller’s Compendium — veuillez mettre à jour l\'application.';

  @override
  String migrationSnapshotAbortedMessage(String cause) {
    return 'Caller’s Compendium n\'a pas démarré car une sauvegarde automatique n\'a pas pu être créée avant la mise à niveau de vos données enregistrées. ${cause}Libérez de l\'espace (ou réparez le dossier de sauvegardes), puis rouvrez l\'application — ou rouvrez-la et choisissez de continuer sans sauvegarde.';
  }

  @override
  String get migrationSnapshotCauseDiskFull =>
      'Votre appareil semble manquer d\'espace de stockage.';

  @override
  String get migrationSnapshotCauseUnwritableBackupsDir =>
      'Impossible d\'écrire dans le dossier de sauvegardes automatiques.';

  @override
  String get migrationSnapshotConsentTitle =>
      'Impossible de sauvegarder vos données';

  @override
  String migrationSnapshotConsentBody(String cause) {
    return 'Avant de mettre à niveau vos données enregistrées vers un nouveau format, Caller’s Compendium crée une sauvegarde automatique afin qu\'une mise à niveau échouée puisse être annulée. Cette sauvegarde n\'a pas pu être créée cette fois.$cause\n\nSi vous continuez sans sauvegarde et que la mise à niveau est interrompue, certaines de vos danses ou de vos programmes pourraient être perdus. Vous pouvez quitter, libérer de l\'espace (ou réparer le dossier de sauvegardes) et rouvrir l\'application pour réessayer.';
  }

  @override
  String get migrationSnapshotConsentQuit => 'Quitter';

  @override
  String get migrationSnapshotConsentProceed => 'Continuer sans sauvegarde';

  @override
  String get migrationBelowFloorHeadline =>
      'Ces données proviennent d’une version trop ancienne pour être ouvertes';

  @override
  String migrationBelowFloorBody(String bridgeTag) {
    return 'Vos données sont récupérables. Installez $bridgeTag, ouvrez l’application une fois pour qu’elle mette à jour vos données, puis réinstallez cette version.\n\nSi vous préférez repartir de zéro, utilisez les options ci-dessous — vos données actuelles seront perdues.';
  }

  @override
  String get migrationBelowFloorBackUpAndReset => 'Sauvegarder + Réinitialiser';

  @override
  String get migrationBelowFloorResetOnly => 'Réinitialiser uniquement';

  @override
  String get migrationBelowFloorBackupFailedTitle => 'Sauvegarde échouée';

  @override
  String get migrationBelowFloorBackupFailedBody =>
      'La sauvegarde n’a pas pu être écrite, vos données n’ont donc pas été réinitialisées.';

  @override
  String get migrationBelowFloorResetConfirmTitle =>
      'Réinitialiser les données de l’application ?';

  @override
  String get migrationBelowFloorResetConfirmBody =>
      'Une sauvegarde a été enregistrée. La réinitialisation remplacera vos données actuelles par une base de données vierge.';

  @override
  String migrationBelowFloorBackupSavedAt(String backupPath) {
    return 'Sauvegarde enregistrée dans : $backupPath';
  }

  @override
  String migrationBelowFloorDiagnosticLogSavedAt(String logPath) {
    return 'Journal de diagnostic enregistré dans : $logPath';
  }

  @override
  String get migrationBelowFloorResetOnlyConfirmBody =>
      'Aucune sauvegarde ne sera effectuée. La réinitialisation supprimera définitivement toutes vos données actuelles et les remplacera par une base de données vide. Cette opération est irréversible.';

  @override
  String get migrationBelowFloorWipeFailedTitle =>
      'Échec de la réinitialisation';

  @override
  String get migrationBelowFloorWipeFailedBody =>
      'Le fichier de base de données n’a pas pu être supprimé. Vos données n’ont pas été modifiées. Essayez de fermer les autres applications susceptibles d’utiliser ce fichier, puis réessayez.';

  @override
  String get confirmDeleteTitle => 'Supprimer ?';

  @override
  String confirmDeleteBody(String itemLabel) {
    return '« $itemLabel » sera supprimé. Vous pouvez annuler cette action.';
  }

  @override
  String get colorEditHexLabel => 'Hex';

  @override
  String get settingsTitle => 'Paramètres';

  @override
  String get settingsGeneralTitle => 'Général';

  @override
  String get settingsAppearanceTitle => 'Apparence';

  @override
  String get settingsDialectTitle => 'Dialecte';

  @override
  String get settingsDefaultsTitle => 'Valeurs par défaut';

  @override
  String get settingsUpdatesTitle => 'Mises à jour';

  @override
  String get settingsDiagnosticsTitle => 'Diagnostic';

  @override
  String get settingsAboutTitle => 'À propos';

  @override
  String get commonSystemDefault => 'Défaut du système';

  @override
  String get commonComingSoon => 'Bientôt disponible';

  @override
  String get settingsLanguageRegionTitle => 'Langue et région';

  @override
  String get settingsRegionalFormatsHeader => 'Formats';

  @override
  String get settingsRegionalLanguageHeader => 'Langue';

  @override
  String get settingsDateFormatTitle => 'Format de date';

  @override
  String settingsDateFormatSubtitle(String example) {
    return 'Affichage des dates d’événements du programme. Exemple : $example';
  }

  @override
  String get settingsDateFormatYmd => 'Année-mois-jour (2026-07-15)';

  @override
  String get settingsDateFormatDmy => 'Jour/mois/année (15/07/2026)';

  @override
  String get settingsDateFormatMdy => 'Mois/jour/année (07/15/2026)';

  @override
  String get settingsDateFormatCustom => 'Personnalisé…';

  @override
  String get settingsDateFormatCustomPatternLabel =>
      'Format de date personnalisé';

  @override
  String get settingsDateFormatCustomPatternHint => 'MM.DD.YY';

  @override
  String get settingsDateFormatCustomLegend =>
      'Jetons : yyyy ou yy = année, MM = mois (MMM = nom abrégé, MMMM = nom complet), d ou dd = jour. Séparateurs : - / . , ou espace.';

  @override
  String get settingsDateFormatCustomInvalid =>
      'Format non reconnu — utilisation du format système par défaut jusqu\'à correction.';

  @override
  String get settingsFirstDayOfWeekTitle => 'Premier jour de la semaine';

  @override
  String get settingsFirstDayOfWeekSubtitle =>
      'Jour de début de la semaine dans les vues de date propres à l\'application, comme le bandeau « cette semaine » de la liste des programmes.';

  @override
  String get settingsFirstDayOfWeekSunday => 'Dimanche';

  @override
  String get settingsFirstDayOfWeekMonday => 'Lundi';

  @override
  String get settingsFirstDayOfWeekSaturday => 'Samedi';

  @override
  String get settingsAppLanguageTitle => 'Langue de l’application';

  @override
  String get settingsAppLanguageSubtitle =>
      'Choisissez la langue de l’interface de l’application.';

  @override
  String get settingsAboutHelpHeader => 'Aide';

  @override
  String get settingsAboutUserGuideTitle => 'Guide d’utilisation';

  @override
  String get settingsAboutUserGuideSubtitle =>
      'Consultez les guides intégrés : démarrage, dialectes, importation et plus encore. Fonctionne hors connexion.';

  @override
  String get settingsAboutLicenseHeader => 'Licence';

  @override
  String get settingsAboutLicenseBody =>
      'Caller\'s Compendium est un logiciel libre, publié sous la GNU Affero General Public License, version 3 (AGPL-3.0). Vous êtes libre de l’utiliser, de l’étudier, de le partager et de le modifier selon les termes de cette licence. Comme l’AGPL l’exige, le code source complet correspondant est proposé à toute personne utilisant l’application.';

  @override
  String get settingsAboutViewSourceTitle => 'Voir le code source sur GitHub';

  @override
  String get settingsAboutFontsHeader => 'Polices';

  @override
  String get settingsAboutFontsBody =>
      'Cette application inclut les polices suivantes sous la SIL Open Font License 1.1. Leurs textes de licence complets sont disponibles sous « Voir les licences » ci-dessous.';

  @override
  String get settingsAboutFontFrauncesSubtitle =>
      'SIL Open Font License 1.1 · © The Fraunces Project Authors — titres et affichage';

  @override
  String get settingsAboutFontAtkinsonSubtitle =>
      'SIL Open Font License 1.1 · © Braille Institute of America, Inc. — corps, UI et Perform';

  @override
  String get settingsAboutFontRobotoSubtitle =>
      'SIL Open Font License 1.1 · © The Roboto Project Authors — police de secours';

  @override
  String get settingsAboutThemesHeader => 'Thèmes';

  @override
  String get settingsAboutThemesBody =>
      'Plusieurs thèmes de couleur optionnels s’inspirent de palettes d’éditeurs de code populaires : One Dark, Dracula, Nord, Tokyo Night, Gruvbox et Catppuccin entre autres — revisitées et ajustées en contraste pour cette application. Les noms des thèmes servent uniquement à créditer cette inspiration.';

  @override
  String get settingsAboutDanceDataHeader => 'Données de danses';

  @override
  String get settingsAboutDanceDataBody =>
      'Les données de danses sont issues de The Caller\'s Box (Chris Page & Michael Dyck), dont la collection est publiée sous la licence Creative Commons Attribution-NonCommercial (CC BY-NC), avec gratitude.';

  @override
  String get settingsAboutLicensesHeader => 'Licences';

  @override
  String get settingsAboutViewLicensesTitle => 'Voir les licences';

  @override
  String get settingsAboutViewLicensesSubtitle =>
      'Textes complets des licences open source, y compris les polices incluses.';

  @override
  String get settingsAboutLegalese =>
      '© Les contributeurs de Caller\'s Compendium. Publié sous AGPL-3.0.';

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
  String get settingsUpdatesHeader => 'Mises à jour';

  @override
  String get settingsUpdatesCheckNowTitle => 'Rechercher des mises à jour';

  @override
  String settingsUpdatesStatusIdle(String version) {
    return 'Vous utilisez la version $version.';
  }

  @override
  String get settingsUpdatesStatusChecking => 'Vérification…';

  @override
  String settingsUpdatesStatusNoUpdate(String version) {
    return 'Aucune mise à jour disponible. Vous utilisez la version $version.';
  }

  @override
  String settingsUpdatesStatusAvailable(String version) {
    return 'La version $version est disponible. Consultez la bannière pour la voir.';
  }

  @override
  String get settingsUpdatesChannelHeader => 'Canal';

  @override
  String get settingsUpdatesBetaTitle => 'Canal bêta';

  @override
  String get settingsUpdatesBetaSubtitle =>
      'Recevoir les mises à jour bêta préliminaires. Désactivé : versions stables uniquement.';

  @override
  String get settingsUpdatesAutoHeader => 'Vérifications automatiques';

  @override
  String get settingsUpdatesAutoTitle => 'Vérifier automatiquement';

  @override
  String get settingsUpdatesAutoSubtitle =>
      'Vérifie la disponibilité d’une nouvelle version en arrière-plan au démarrage. Désactivé par défaut.';

  @override
  String get settingsUpdatesPrivacyNote =>
      'La vérification des mises à jour télécharge uniquement un petit fichier de version via HTTPS — aucune donnée vous concernant, concernant votre appareil ou votre utilisation n’est jamais envoyée. Rien n’est téléchargé ni installé automatiquement : vous choisissez quand télécharger une mise à jour, celle-ci est vérifiée avant d’être ouverte, et votre programme d’installation système effectue l’installation.';

  @override
  String get settingsUpdatesDownloadingTitle =>
      'Téléchargement de la mise à jour';

  @override
  String get settingsUpdatesDownloadingIndeterminate => 'Téléchargement…';

  @override
  String settingsUpdatesDownloadingPercent(int percent) {
    return 'Téléchargement… $percent %';
  }

  @override
  String get settingsUpdatesVerifyingTitle => 'Vérification du téléchargement';

  @override
  String get settingsUpdatesVerifyingSubtitle =>
      'Vérification de l’intégrité sha256 du téléchargement…';

  @override
  String get settingsUpdatesHandoffTitle =>
      'Préparation du programme d’installation';

  @override
  String get settingsUpdatesHandoffSubtitle =>
      'Transmission de la mise à jour vérifiée à votre système…';

  @override
  String get settingsUpdatesCompletedTitle => 'Mise à jour téléchargée';

  @override
  String get settingsUpdatesCompletedSubtitle =>
      'Suivez les instructions de votre programme d’installation pour terminer la mise à jour.';

  @override
  String get settingsUpdatesCompletedSubtitleRevealed =>
      'Vérifiée et affichée dans votre gestionnaire de fichiers — exécutez le programme d’installation pour terminer la mise à jour.';

  @override
  String get settingsUpdatesDownloadTitle =>
      'Télécharger et installer la mise à jour';

  @override
  String get settingsUpdatesDownloadError =>
      'Impossible de télécharger la mise à jour.';

  @override
  String settingsUpdatesDownloadSubtitle(String version) {
    return 'Téléchargez la version $version, vérifiez-la, puis lancez votre programme d’installation. L’application ne se remplace jamais elle-même directement.';
  }

  @override
  String get settingsDialectHeader => 'Dialectes';

  @override
  String get settingsDialectNewButton => 'Nouveau dialecte';

  @override
  String get settingsDialectNewDefaultName => 'Mon dialecte';

  @override
  String get settingsDialectCreateConfirm => 'Créer';

  @override
  String get settingsDialectDuplicateFrom => 'Dupliquer depuis…';

  @override
  String get settingsDialectRenameTitle => 'Renommer le dialecte';

  @override
  String get settingsDialectRename => 'Renommer';

  @override
  String get settingsDialectEditTerms => 'Modifier les termes';

  @override
  String get settingsDialectDuplicateToCustomize =>
      'Dupliquer pour personnaliser';

  @override
  String get settingsDialectDeleteTitle => 'Supprimer le dialecte ?';

  @override
  String settingsDialectDeleteConfirmBody(String name) {
    return '« $name » sera définitivement supprimé.';
  }

  @override
  String get settingsDialectActionsTooltip => 'Actions du dialecte';

  @override
  String get settingsDialectPresetBadge => 'Prédéfini';

  @override
  String get settingsDialectNameLabel => 'Nom';

  @override
  String get settingsAppearanceThemeHeader => 'Thème';

  @override
  String get settingsAppearanceCustomThemesHeader => 'Thèmes personnalisés';

  @override
  String get settingsAppearanceEasterEggsHeader => 'Easter eggs';

  @override
  String get settingsAppearanceSetListsHeader => 'Listes de sets';

  @override
  String get settingsAppearanceFormationColoursHeader =>
      'Couleurs de formation';

  @override
  String get settingsAppearanceColourDanceTitle =>
      'Les danses aux titres de couleur teintent le thème';

  @override
  String get settingsAppearanceColourDanceSubtitle =>
      'Une surprise ludique : lorsque vous ouvrez une danse dont le titre contient un nom de couleur — comme Baby Rose ou Blue Boy — sa vue est teintée de cette couleur. Désactivé par défaut, et mis de côté lorsqu’un thème à contraste élevé est actif, pour que la lisibilité prime toujours.';

  @override
  String get settingsAppearanceSetListColorTitle =>
      'Colorier les lignes de la liste de sets';

  @override
  String get settingsAppearanceSetListColorSubtitle =>
      'Teinter chaque ligne de danse selon sa famille de formation (contra, mixer, square…) — les danses marquées comme mixers reçoivent toujours la teinte mixer quelle que soit la formation. La formation est toujours affichée en texte également, donc les lignes restent lisibles sans couleur.';

  @override
  String get settingsAppearanceFormationColoursTitle =>
      'Couleurs des étiquettes de formation';

  @override
  String get settingsAppearanceFormationColoursSubtitle =>
      'Surlignez les formations individuelles dans vos propres couleurs — ex. Becket (CW) en jaune, Becket (CCW) en rose — sur les fiches de danse, le détail de la danse et l’en-tête Perform.';

  @override
  String get settingsAppearanceSelectedBadge => 'Sélectionné';

  @override
  String get settingsAppearancePreviewHeading => 'Aa Aperçu';

  @override
  String get settingsAppearancePreviewBody => 'Exemple de texte courant';

  @override
  String get settingsAppearanceNewThemeButton => 'Nouveau thème personnalisé';

  @override
  String get settingsAppearanceNewThemeDefaultName => 'Mon thème';

  @override
  String get settingsAppearanceCustomThemesEmpty =>
      'Copiez le thème actuel et ajustez n’importe quelle couleur. Les thèmes personnalisés sont enregistrés sur cet appareil.';

  @override
  String get settingsAppearanceDeleteThemeTitle => 'Supprimer le thème ?';

  @override
  String settingsAppearanceDeleteThemeBody(String name) {
    return '« $name » sera définitivement supprimé.';
  }

  @override
  String settingsAppearanceCustomThemeSemantic(String name) {
    return 'Thème personnalisé $name';
  }

  @override
  String get settingsAppearanceThemeActionsTooltip => 'Actions du thème';

  @override
  String get settingsDefaultsProgramHeader =>
      'Paramètres par défaut du programme';

  @override
  String get settingsDefaultsCallerLabel => 'Caller par défaut';

  @override
  String get settingsDefaultsPrefilledHelper =>
      'Prérempli dans les nouveaux programmes ; modifiable par programme.';

  @override
  String get settingsDefaultsBandLabel => 'Orchestre par défaut';

  @override
  String get settingsDefaultsDisplayHeader =>
      'Paramètres d’affichage par défaut';

  @override
  String get settingsDefaultsSortTitle => 'Ordre de tri de la collection';

  @override
  String get settingsDefaultsSortSubtitle =>
      'Ordre de tri de la collection à l’ouverture. Vous pouvez toujours modifier le tri pendant la navigation.';

  @override
  String get settingsDefaultsCanonicalTitle =>
      'Ouvrir les détails de la danse en termes canoniques';

  @override
  String get settingsDefaultsCanonicalSubtitle =>
      'Activé : une danse s’ouvre avec les noms de rôles et de mouvements canoniques plutôt que votre dialecte actif. Vous pouvez toujours changer de vue pendant que la danse est ouverte.';

  @override
  String get settingsDefaultsCollectionCardHeader =>
      'Champs de la carte de collection';

  @override
  String get settingsDefaultsCollectionCardSubtitle =>
      'Choisissez les détails qui apparaissent sur chaque ligne de danse. Tous les champs sont affichés par défaut.';

  @override
  String get settingsDefaultsCollectionCardAuthors => 'Auteurs';

  @override
  String get settingsDefaultsCollectionCardCalledCount => 'Nombre d’appels';

  @override
  String get settingsDefaultsCollectionCardFormation => 'Formation';

  @override
  String get settingsDefaultsCollectionCardStatus => 'Statut';

  @override
  String get settingsDefaultsCollectionCardLevel => 'Niveau';

  @override
  String get settingsDefaultsCollectionCardRating => 'Note';

  @override
  String get settingsDefaultsCollectionCardTags => 'Tags';

  @override
  String get settingsDefaultsCollectionCardCustomFields =>
      'Champs personnalisés';

  @override
  String get settingsDefaultsAuthoringHeader =>
      'Paramètres par défaut de création de danse';

  @override
  String get settingsDefaultsFreeTextEntryTitle => 'Saisie en texte libre';

  @override
  String get settingsDefaultsFreeTextEntrySubtitle =>
      'Activé : l’ajout d’une nouvelle figure vous permet de la saisir sur une seule ligne (ex. « neighbor balance & swing ») au lieu de la construire champ par champ. La ligne est analysée en figure(s) ; tout ce qui n’est pas reconnu est conservé comme figure personnalisée à corriger ultérieurement. La modification d’une figure existante utilise toujours l’éditeur complet.';

  @override
  String get settingsDefaultsAggressiveBeatsUpdateTitle =>
      'Recalculer agressivement les temps de la figure';

  @override
  String get settingsDefaultsAggressiveBeatsUpdateSubtitle =>
      'Lorsque cette option est activée, la modification du mouvement d\'une figure ou d\'un paramètre affectant le tempo recalcule immédiatement son nombre de temps — même en écrasant un nombre de temps que vous avez saisi manuellement. Lorsqu\'elle est désactivée (par défaut), un nombre de temps que vous avez modifié n\'est jamais changé automatiquement.';

  @override
  String get settingsDefaultsFigureShorthandsTitle => 'Abréviations de figures';

  @override
  String get settingsDefaultsFigureShorthandsEmptySubtitle =>
      'Associez des jetons courts à une ou plusieurs figures à insérer lors de la saisie en texte libre.';

  @override
  String settingsDefaultsFigureShorthandsCountSubtitle(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count abréviations définies.',
      one: '1 abréviation définie.',
    );
    return '$_temp0';
  }

  @override
  String get settingsDefaultsFormTitle => 'Forme';

  @override
  String get settingsDefaultsFormSubtitle =>
      'La forme de danse par défaut pour une nouvelle danse. Modifiable par danse.';

  @override
  String get settingsDefaultsFormationTitle => 'Formation';

  @override
  String get settingsDefaultsFormationSubtitle =>
      'La formation par défaut pour une nouvelle danse. Modifiable par danse.';

  @override
  String get settingsDefaultsProgressionTitle => 'Progression';

  @override
  String get settingsDefaultsProgressionSubtitle =>
      'La progression par défaut pour une nouvelle danse. Modifiable par danse.';

  @override
  String get settingsDefaultsPhraseLabel => 'Structure de phrase par défaut';

  @override
  String get settingsDefaultsPhraseHelper =>
      'Prérempli dans les nouvelles danses. Vide = standard 4×16 (A1 A2 B1 B2) ; sinon ex. 6*8*2.';

  @override
  String get settingsDefaultsStartingFiguresTitle => 'Figures initiales';

  @override
  String get settingsDefaultsStartingFiguresSubtitle =>
      'Les figures avec lesquelles une nouvelle danse commence. Par défaut : un simple stand still (8 temps) ; effacez pour une nouvelle danse vierge. Modifiable par danse.';

  @override
  String get settingsDefaultsMoveDefaultsTitle =>
      'Paramètres par défaut des mouvements';

  @override
  String get settingsDefaultsMoveDefaultsSubtitle =>
      'Valeurs de paramètres préférées appliquées lors de l’insertion d’un mouvement en saisissant une danse. Ces valeurs remplacent les paramètres intégrés du mouvement ; vous pouvez toujours modifier n’importe quel paramètre sur la figure par la suite. Les mouvements et paramètres non définis utilisent les paramètres intégrés.';

  @override
  String get settingsDefaultsAddMoveButton =>
      'Ajouter un paramètre par défaut de mouvement';

  @override
  String get settingsDefaultsRemoveMoveTooltip => 'Supprimer';

  @override
  String get settingsDefaultsMoveGone =>
      'Ce mouvement n’est plus dans la taxonomie.';

  @override
  String get settingsDefaultsMoveNoParams =>
      'Ce mouvement n’a aucun paramètre à configurer par défaut.';

  @override
  String get settingsFormationColoursTitle => 'Couleurs de formation';

  @override
  String get settingsFormationColoursIntro =>
      'Attribuez une couleur propre à une formation pour mettre en évidence son étiquette sur les fiches de danse, le détail de la danse et l’en-tête Perform. Seules les formations que vous personnalisez sont surlignées ; les autres affichent leur étiquette normalement. La formation est toujours affichée en texte également, donc les étiquettes restent lisibles sans couleur.';

  @override
  String get settingsFormationColoursListHeader => 'Formations';

  @override
  String get settingsFormationColoursCustom => 'Couleur personnalisée';

  @override
  String get settingsFormationColoursFamilyDefault =>
      'Couleur par défaut de la famille';

  @override
  String settingsFormationColoursResetTooltip(String label) {
    return 'Réinitialiser $label à la couleur par défaut de la famille';
  }

  @override
  String get settingsAppearanceTagColoursHeader => 'Couleurs des tags';

  @override
  String get settingsAppearanceTagColoursTitle => 'Couleurs des tags';

  @override
  String get settingsAppearanceTagColoursSubtitle =>
      'Donnez à un tag sa propre couleur pour qu’il ressorte sur les cartes de danse et dans le détail d’une danse. Le nom du tag est toujours affiché, donc les tags restent lisibles sans couleur.';

  @override
  String get settingsTagColoursTitle => 'Couleurs des tags';

  @override
  String get settingsTagColoursIntro =>
      'Donnez à un tag sa propre couleur pour qu’il ressorte partout où il apparaît. Seuls les tags que vous colorez changent ; les autres restent exactement comme maintenant. Le nom du tag est toujours affiché, donc les tags restent lisibles sans couleur.';

  @override
  String get settingsTagColoursListHeader => 'Tags';

  @override
  String get settingsTagColoursEmpty =>
      'Vous n’avez pas encore créé de tags. Ajoutez un tag à une danse et il apparaîtra ici.';

  @override
  String get settingsTagColoursCustom => 'Couleur personnalisée';

  @override
  String get settingsTagColoursNoColour => 'Aucune couleur';

  @override
  String settingsTagColoursResetTooltip(String label) {
    return 'Supprimer la couleur de $label';
  }

  @override
  String get settingsTagColoursSaveError =>
      'Impossible d’enregistrer cette couleur. Veuillez réessayer.';

  @override
  String get settingsTagColoursLoadError => 'Impossible de charger vos tags.';

  @override
  String get settingsGeneralLibraryHeader => 'Bibliothèque';

  @override
  String get settingsGeneralSortIgnoreArticlesTitle =>
      'Ignorer les articles en tête lors du tri';

  @override
  String get settingsGeneralSortIgnoreArticlesSubtitle =>
      'Activé : la liste de danses classe les titres alphabétiquement en ignorant les articles initiaux « the », « a » ou « an » — ainsi « The Nice Combination » est classé sous N. Désactivez pour trier par le titre littéral.';

  @override
  String get settingsGeneralVenuesHeader => 'Lieux';

  @override
  String get settingsGeneralVenueEntityModeTitle =>
      'Utiliser des fiches de lieu réutilisables';

  @override
  String get settingsGeneralVenueEntityModeSubtitle =>
      'Transformez les lieux en fiches réutilisables avec adresse, contacts et calendrier, partageables entre plusieurs programmes et modifiables en un seul endroit. Désactivé : le lieu d’un programme est un simple champ texte libre. Le changement est sans perte — votre texte saisi et toute fiche liée sont conservés.';

  @override
  String get settingsGeneralManageVenuesTitle => 'Gérer les lieux';

  @override
  String get settingsGeneralManageVenuesSubtitle =>
      'Parcourez, modifiez et supprimez vos fiches de lieu réutilisables.';

  @override
  String get settingsGeneralPerformanceHeader => 'Performance';

  @override
  String get settingsGeneralAutoSizePerformTitle =>
      'Dimensionnement automatique des fiches Perform';

  @override
  String get settingsGeneralAutoSizePerformSubtitle =>
      'Ajuste chaque fiche pour que la danse ou le créneau complet tienne à l’écran sans défilement. Désactivez pour régler la taille vous-même avec A- / A+.';

  @override
  String get settingsGeneralCallingHistoryHeader => 'Historique d’appel';

  @override
  String get settingsGeneralRequirePerformedForHistoryTitle =>
      'Exiger « marquer comme joué » pour l’historique d’appel';

  @override
  String get settingsGeneralRequirePerformedForHistorySubtitle =>
      'Activé : l’historique d’appel d’une danse ne liste que les programmes dont le créneau pour cette danse a été marqué comme joué. Désactivé : un programme apparaît dès qu’il contient la danse.';

  @override
  String get settingsGeneralTrackHistoryForAllCallersTitle =>
      'Suivre l’historique d’appel pour tous les callers';

  @override
  String get settingsGeneralTrackHistoryForAllCallersSubtitle =>
      'Lorsque cette option est désactivée et qu’un caller par défaut est défini, l’historique d’appel et les comptes incluent les programmes menés par ce caller ainsi que les programmes sans caller enregistré (considérés comme les vôtres). Lorsqu’elle est activée — ou qu’aucun caller par défaut n’est défini — chaque programme contenant la danse est suivi.';

  @override
  String get settingsGeneralAccessibilityHeader => 'Accessibilité';

  @override
  String get settingsGeneralReduceMotionTitle => 'Réduire les animations';

  @override
  String get settingsGeneralReduceMotionSubtitle =>
      'Atténue ou supprime les animations non essentielles, comme le défilement animé lors du passage entre les résultats de recherche ou les figures.';

  @override
  String get settingsGeneralVerboseFiguresTitle =>
      'Toujours afficher le texte détaillé des figures';

  @override
  String get settingsGeneralVerboseFiguresSubtitle =>
      'Affiche le texte complet des figures dans le style parlé à l’écran dans la vue de danse, pas seulement pour les lecteurs d’écran. Désactivez pour la notation concise.';

  @override
  String get settingsGeneralDecimalTurnsTitle =>
      'Afficher les tours en décimales';

  @override
  String get settingsGeneralDecimalTurnsSubtitle =>
      'Affiche les valeurs de tours et rotations en décimales (0,75) plutôt qu’en fractions (¾). Le texte pour les lecteurs d’écran n’est pas affecté.';

  @override
  String get settingsGeneralConfirmBeforeDeleteTitle =>
      'Confirmer avant de supprimer';

  @override
  String get settingsGeneralConfirmBeforeDeleteSubtitle =>
      'Demander une confirmation avant de supprimer une danse ou un programme. Les suppressions peuvent toujours être annulées ; cela ajoute simplement une confirmation explicite.';

  @override
  String get settingsGeneralDeletedItemsHeader => 'Éléments supprimés';

  @override
  String get settingsGeneralSoftDeleteRetentionTitle =>
      'Conserver les danses supprimées pendant';

  @override
  String get settingsGeneralSoftDeleteRetentionSubtitle =>
      'Les danses supprimées sont conservées pendant cette durée avant d’être définitivement supprimées au lancement de l’application. « Jamais » les conserve jusqu’à ce que vous les purgiez manuellement.';

  @override
  String settingsGeneralSoftDeleteRetentionDays(int days) {
    return '$days jours';
  }

  @override
  String get settingsGeneralSoftDeleteRetentionNever => 'Jamais';

  @override
  String get settingsGeneralImportHeader => 'Importation';

  @override
  String get settingsGeneralImportDancesSubtitle =>
      'Importez des danses dans votre collection depuis un fichier JSON Caller\'s Compendium. Vous passez en revue chaque danse et confirmez avant tout ajout.';

  @override
  String get settingsGeneralImportEllipsisAction => 'Importer…';

  @override
  String get settingsGeneralReparseCustomFiguresTitle =>
      'Revérifier les figures personnalisées';

  @override
  String get settingsGeneralReparseCustomFiguresSubtitle =>
      'Réanalysez les danses importées dont les figures ont été conservées comme personnalisées uniquement parce qu’elles ne pouvaient pas être reconnues à l’importation. L’analyse améliorée les met à jour sur place — vos tags, évaluations et notes sont préservés. Vous prévisualisez et confirmez avant tout changement.';

  @override
  String get settingsGeneralReparseCustomFiguresAction => 'Revérifier…';

  @override
  String get settingsGeneralBackupRestoreHeader => 'Sauvegarde et restauration';

  @override
  String get backupExported => 'Sauvegarde exportée.';

  @override
  String get backupExportFailed => 'Impossible d’exporter une sauvegarde.';

  @override
  String get backupRestoreIntegrityFailed =>
      'Cette sauvegarde a échoué au contrôle d’intégrité ; elle est peut-être corrompue ou a été modifiée après son exportation. La restauration a été annulée et vos données sont inchangées.';

  @override
  String get backupRestoreIncompatibleVersion =>
      'Cette sauvegarde contient des éléments que cette version de l’application ne peut pas lire (elle provient peut-être d’une version plus récente), donc la restauration a été annulée. Vos données sont inchangées.';

  @override
  String get backupRestoreInvalidFile =>
      'Impossible de restaurer : le fichier n’est pas une sauvegarde valide. Vos données sont inchangées.';

  @override
  String backupRestoreSkippedProblems(int count) {
    return 'Sauvegarde restaurée avec $count problème(s) ignoré(s).';
  }

  @override
  String get backupRestored => 'Sauvegarde restaurée.';

  @override
  String get backupRestoreFailed => 'Impossible de restaurer la sauvegarde.';

  @override
  String get backupRestoreSettingsFailed =>
      'Vos danses et programmes ont été restaurés, mais l’application de vos paramètres enregistrés a échoué. Votre contenu restauré est intact — vous pouvez réessayer d’appliquer les paramètres.';

  @override
  String get backupRestoreSettingsRetryAction => 'Réessayer les paramètres';

  @override
  String get backupRestoreSettingsRetried => 'Paramètres appliqués.';

  @override
  String get backupExportTitle => 'Exporter une sauvegarde';

  @override
  String get backupExportSubtitle =>
      'Enregistrez toute votre collection, vos programmes, champs personnalisés, dialectes, thèmes et paramètres dans un seul fichier JSON que vous pouvez conserver ou transférer vers un autre appareil.';

  @override
  String get backupExportAction => 'Exporter';

  @override
  String get backupRestoreTitle => 'Restaurer depuis une sauvegarde';

  @override
  String get backupRestoreSubtitle =>
      'Remplacez tout le contenu actuel de l’application par le contenu d’un fichier de sauvegarde. Cette action est irréversible.';

  @override
  String get backupRestoreAction => 'Restaurer';

  @override
  String get backupReminderTitle => 'Rappel de sauvegarde';

  @override
  String get backupLastBackupNever => 'Dernière sauvegarde : jamais';

  @override
  String backupLastBackupDate(String date) {
    return 'Dernière sauvegarde : $date';
  }

  @override
  String get backupReminderOff => 'Désactivé';

  @override
  String get backupReminderWeekly => 'Hebdomadaire';

  @override
  String get backupReminderMonthly => 'Mensuel';

  @override
  String get backupOverdueHint =>
      'Cela fait un moment que vous n’avez pas fait de sauvegarde — pensez à en exporter une maintenant.';

  @override
  String get backupRestoreDialogBody =>
      'La restauration remplace tout le contenu actuel de l’application — votre collection, programmes, dialectes, thèmes et paramètres — par le contenu de la sauvegarde. Cette action est irréversible.';

  @override
  String get backupChooseFileAction => 'Choisir un fichier…';

  @override
  String get backupPasteJsonLabel => 'Ou collez le JSON de sauvegarde';

  @override
  String get backupReplaceAllDataAction => 'Remplacer toutes les données';

  @override
  String get diagnosticsNoDiagnosticsToExport => 'Aucun diagnostic à exporter.';

  @override
  String get diagnosticsScrubbedExportUnavailable =>
      'Impossible de préparer un export sécurisé (nettoyé), rien n’a été enregistré. Réessayez, ou utilisez délibérément le détail complet.';

  @override
  String get diagnosticsLogExported => 'Journal de diagnostic exporté.';

  @override
  String get diagnosticsExportCancelled => 'Export annulé.';

  @override
  String get diagnosticsExportFailed =>
      'Impossible d’exporter le journal de diagnostic.';

  @override
  String get diagnosticsClearLogTitle => 'Effacer le journal de diagnostic ?';

  @override
  String get diagnosticsClearLogBody =>
      'Cette action supprime définitivement le journal local de cet appareil. Elle est irréversible.';

  @override
  String get diagnosticsClearAction => 'Effacer';

  @override
  String get diagnosticsLogCleared => 'Journal de diagnostic effacé.';

  @override
  String get diagnosticsHeader => 'Diagnostic';

  @override
  String get diagnosticsIntro =>
      'En cas de problème, l’application enregistre une note technique dans un journal local sur cet appareil pour faciliter le diagnostic. Elle n’est jamais envoyée nulle part — il n’y a pas de télémétrie. Vous pouvez l’exporter pour le joindre à un rapport de bogue, ou l’effacer à tout moment.';

  @override
  String get diagnosticsRecentEntriesHeader => 'Entrées récentes';

  @override
  String get diagnosticsReadFailedTitle =>
      'Impossible de lire le journal de diagnostic';

  @override
  String get diagnosticsReadFailedSubtitle =>
      'Le journal local est peut-être inaccessible sur cet appareil. Vous pouvez toujours essayer de l’exporter ou de l’effacer.';

  @override
  String get diagnosticsEmptyTitle => 'Aucune erreur enregistrée';

  @override
  String get diagnosticsEmptySubtitle =>
      'Rien n’a été capturé sur cet appareil.';

  @override
  String get diagnosticsExportHeader => 'Exporter';

  @override
  String get diagnosticsFullDetailTitle =>
      'Inclure le détail complet (peut contenir votre contenu)';

  @override
  String get diagnosticsFullDetailSubtitle =>
      'Désactivé par défaut. Désactivé : l’export supprime votre contenu, chemins de fichiers, adresses e-mail et numéros de téléphone.';

  @override
  String get diagnosticsExportShareLogTitle => 'Exporter / partager le journal';

  @override
  String get diagnosticsExportShareFullSubtitle =>
      'Partage le journal complet, non expurgé.';

  @override
  String get diagnosticsExportShareScrubbedSubtitle =>
      'Partage une copie nettoyée, sûre à joindre à un rapport de bogue.';

  @override
  String get diagnosticsClearLogRowTitle => 'Effacer le journal';

  @override
  String get diagnosticsClearLogRowSubtitle =>
      'Supprimer le journal local de cet appareil.';

  @override
  String get crashFallbackTitle => 'Une erreur s’est produite ici';

  @override
  String get crashFallbackBody =>
      'Cette partie de l’application a rencontré une erreur inattendue et a récupéré. Les détails ont été enregistrés dans un journal de diagnostic local (Paramètres ▸ Diagnostic) qui ne quitte jamais votre appareil.';

  @override
  String get crashFallbackCopied => 'Copié';

  @override
  String get crashFallbackCopyDetails => 'Copier les détails';

  @override
  String get commonCancel => 'Annuler';

  @override
  String get commonUndo => 'Annuler';

  @override
  String get commonRetry => 'Réessayer';

  @override
  String get commonDelete => 'Supprimer';

  @override
  String get commonDuplicate => 'Dupliquer';

  @override
  String commonDuplicateTitleSuffix(String title) {
    return '$title (copie)';
  }

  @override
  String get commonYes => 'Oui';

  @override
  String get commonNo => 'Non';

  @override
  String get commonOk => 'OK';

  @override
  String get commonApply => 'Appliquer';

  @override
  String get commonCouldntOpenLink => 'Impossible d’ouvrir le lien';

  @override
  String get commonProgression => 'Progression';

  @override
  String get commonDanceFormContra => 'Contra';

  @override
  String get commonDanceFormEcd => 'Anglaise (ECD)';

  @override
  String get commonDanceFormSquare => 'Square';

  @override
  String get commonProgressionNone => 'Sans progression';

  @override
  String get commonProgressionSingle => 'Simple';

  @override
  String get commonProgressionDouble => 'Double';

  @override
  String get commonProgressionTriple => 'Triple';

  @override
  String get commonProgressionQuadruple => 'Quadruple';

  @override
  String get commonProgressionOther => 'Autre';

  @override
  String get commonDanceStatusActive => 'Active';

  @override
  String get commonDanceStatusDeprecated => 'Désuète';

  @override
  String get commonDanceStatusBroken => 'Incorrecte';

  @override
  String get commonDanceLevelBeginner => 'Débutant';

  @override
  String get commonDanceLevelIntermediate => 'Intermédiaire';

  @override
  String get commonDanceLevelAdvanced => 'Avancé';

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
  String get commonFormationOther => 'Autre';

  @override
  String commonFormationWithDetail(String shape, String detail) {
    return '$shape — $detail';
  }

  @override
  String get commonMixedLevel => 'Niveau mixte';

  @override
  String get commonMixer => 'Mixer';

  @override
  String commonShowDancesTaggedTooltip(String tagName) {
    return 'Afficher les danses étiquetées « $tagName »';
  }

  @override
  String commonDeletedSnack(String title) {
    return '« $title » supprimé.';
  }

  @override
  String get importGapMessage =>
      'Impossible d’analyser cet appel — conservé tel quel comme figure personnalisée.';

  @override
  String get importGapDialogTitle => 'Figure non reconnue';

  @override
  String get importGapSemanticLabel =>
      'Figure non reconnue. Impossible d’analyser cet appel — conservé tel quel comme figure personnalisée.';

  @override
  String get collectionScreenTitle => 'Collection';

  @override
  String get collectionNewDance => 'Nouvelle danse';

  @override
  String get collectionSearchTooltip => 'Rechercher (Ctrl/Cmd-K)';

  @override
  String get collectionSelectDancesTooltip => 'Sélectionner des danses';

  @override
  String get collectionManageCustomFieldsTooltip =>
      'Gérer les champs personnalisés';

  @override
  String get collectionRecentlyDeletedTooltip => 'Récemment supprimées';

  @override
  String collectionSortByTooltip(String sortLabel) {
    return 'Trier par ($sortLabel)';
  }

  @override
  String get collectionSortRelevance => 'Meilleure correspondance';

  @override
  String get collectionSortTitle => 'Titre';

  @override
  String get collectionSortAuthor => 'Auteur';

  @override
  String get collectionSortRecentlyAdded => 'Récemment ajouté';

  @override
  String get collectionSortLastCalled => 'Dernier appel';

  @override
  String get collectionSortAscendingTooltip =>
      'Croissant (appuyez pour décroissant)';

  @override
  String get collectionSortDescendingTooltip =>
      'Décroissant (appuyez pour croissant)';

  @override
  String get collectionGroupByCategoryTooltip => 'Grouper par catégorie';

  @override
  String collectionGroupByCategoryActiveTooltip(String tag) {
    return 'Groupé par $tag';
  }

  @override
  String get collectionGroupByNone => 'Aucun regroupement';

  @override
  String get collectionGroupByHeader => 'Catégorie';

  @override
  String get collectionGroupOther => 'Autres';

  @override
  String collectionGroupSectionSemantics(String label, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count danses',
      one: '1 danse',
    );
    return '$label, $_temp0';
  }

  @override
  String get collectionExitSelectionTooltip => 'Quitter la sélection';

  @override
  String collectionSelectedCount(int count) {
    return '$count sélectionné(s)';
  }

  @override
  String get collectionAddTags => 'Ajouter des tags';

  @override
  String get collectionRemoveTags => 'Supprimer des tags';

  @override
  String get collectionSetLevel => 'Définir le niveau';

  @override
  String get collectionSearchFieldLabel => 'Rechercher des danses';

  @override
  String get collectionSearchFieldHint => 'Titres, auteurs, figures, notes…';

  @override
  String get collectionClearSearchTooltip =>
      'Effacer la recherche et les filtres';

  @override
  String get collectionLoadError => 'Impossible de charger la collection.';

  @override
  String collectionDuplicatedSnack(String title) {
    return 'Dupliqué sous le nom « $title ».';
  }

  @override
  String get collectionEmpty =>
      'Votre collection est vide. Ajoutez ou importez une danse pour commencer — ou activez la recherche en ligne ci-dessus pour importer depuis une source en ligne.';

  @override
  String get collectionFiltersTitle => 'Filtres';

  @override
  String collectionFiltersActive(int count) {
    return 'Filtres ($count actifs)';
  }

  @override
  String get collectionByPhraseTitle => 'Par phrase';

  @override
  String collectionByPhraseActive(int count) {
    return 'Par phrase ($count actif(s))';
  }

  @override
  String get collectionAdvancedTitle => 'Avancé';

  @override
  String get collectionUseAdvancedQuery => 'Utiliser la recherche avancée';

  @override
  String get collectionUseAdvancedQuerySubtitle =>
      'Combinez figures et séquences avec des groupes tout / l’un / aucun.';

  @override
  String collectionDanceCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count danses',
      one: '1 danse',
    );
    return '$_temp0';
  }

  @override
  String get collectionSearchError =>
      'Une erreur s’est produite lors de la recherche.';

  @override
  String get collectionNoResults =>
      'Aucune danse ne correspond à votre recherche.';

  @override
  String get collectionBatchNoChanges => 'Aucune modification';

  @override
  String collectionBatchTagged(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count danses étiquetées',
      one: '1 danse étiquetée',
    );
    return '$_temp0';
  }

  @override
  String collectionBatchUntagged(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Tags supprimés de $count danses',
      one: 'Tags supprimés de 1 danse',
    );
    return '$_temp0';
  }

  @override
  String collectionBatchLevelSet(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Niveau défini sur $count danses',
      one: 'Niveau défini sur 1 danse',
    );
    return '$_temp0';
  }

  @override
  String collectionBatchLevelCleared(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Niveau effacé sur $count danses',
      one: 'Niveau effacé sur 1 danse',
    );
    return '$_temp0';
  }

  @override
  String get collectionBatchMore => 'Plus d’actions par lot';

  @override
  String get collectionSetRating => 'Définir la note';

  @override
  String get collectionAddTunes => 'Ajouter des airs';

  @override
  String get collectionClearTunes => 'Effacer les airs';

  @override
  String get collectionEditCustomField => 'Modifier le champ personnalisé';

  @override
  String collectionBatchRatingSet(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Note définie sur $count danses',
      one: 'Note définie sur 1 danse',
    );
    return '$_temp0';
  }

  @override
  String collectionBatchRatingCleared(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Note effacée sur $count danses',
      one: 'Note effacée sur 1 danse',
    );
    return '$_temp0';
  }

  @override
  String collectionBatchTunesAdded(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Airs ajoutés à $count danses',
      one: 'Airs ajoutés à 1 danse',
    );
    return '$_temp0';
  }

  @override
  String collectionBatchTunesCleared(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Airs effacés de $count danses',
      one: 'Airs effacés de 1 danse',
    );
    return '$_temp0';
  }

  @override
  String collectionBatchCustomFieldSet(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Champ mis à jour sur $count danses',
      one: 'Champ mis à jour sur 1 danse',
    );
    return '$_temp0';
  }

  @override
  String collectionBatchCustomFieldCleared(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Champ effacé sur $count danses',
      one: 'Champ effacé sur 1 danse',
    );
    return '$_temp0';
  }

  @override
  String collectionSelectDanceLabel(String title) {
    return 'Sélectionner $title';
  }

  @override
  String collectionCalledBadge(int count) {
    return 'appelée ×$count';
  }

  @override
  String collectionCalledBadgeSemantic(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'appelée $count fois',
      one: 'appelée 1 fois',
    );
    return '$_temp0';
  }

  @override
  String collectionRatingSemantic(int rating) {
    return 'Note : $rating sur 5 étoiles';
  }

  @override
  String collectionRowActionsSemantic(String title) {
    return 'Actions pour $title';
  }

  @override
  String get collectionSplitEmptyTitle => 'Sélectionner une danse';

  @override
  String get collectionSplitEmptySubtitle =>
      'Choisissez une danse dans la liste pour afficher ses détails.';

  @override
  String get collectionFacetType => 'Type';

  @override
  String get collectionFacetFormation => 'Formation';

  @override
  String get collectionFacetStatus => 'Statut';

  @override
  String get collectionFacetLevel => 'Niveau';

  @override
  String get collectionFacetMinRating => 'Note minimale';

  @override
  String collectionFacetMinRatingChip(int min) {
    return '≥$min★';
  }

  @override
  String get collectionFacetTags => 'Tags';

  @override
  String get collectionFacetSource => 'Source';

  @override
  String get collectionFacetAuthor => 'Auteur';

  @override
  String get collectionFacetNone =>
      'Aucun filtre disponible pour cette collection pour l’instant.';

  @override
  String get collectionFacetClear => 'Effacer les filtres';

  @override
  String collectionFacetRemoveAuthor(String name) {
    return 'Supprimer $name';
  }

  @override
  String get collectionFacetAuthorSearchHint => 'Rechercher des auteurs…';

  @override
  String get collectionFacetOpContains => 'contient';

  @override
  String get collectionFacetOpEquals => 'égal à';

  @override
  String collectionFacetTextHint(String label) {
    return 'Filtrer par $label…';
  }

  @override
  String get collectionFacetNumOpEq => '=';

  @override
  String get collectionFacetNumOpLt => '<';

  @override
  String get collectionFacetNumOpGt => '>';

  @override
  String get collectionFacetNumOpBetween => 'entre';

  @override
  String get collectionFacetNumFrom => 'De';

  @override
  String get collectionFacetNumValue => 'Valeur';

  @override
  String get collectionFacetNumTo => 'À';

  @override
  String get collectionByPhraseOrdinalFirst => 'première phrase';

  @override
  String get collectionByPhraseOrdinalSecond => 'deuxième phrase';

  @override
  String get collectionByPhraseOrdinalThird => 'troisième phrase';

  @override
  String get collectionByPhraseOrdinalFourth => 'quatrième phrase';

  @override
  String collectionByPhraseOrdinalN(int number) {
    return 'phrase $number';
  }

  @override
  String collectionByPhraseCaption(String ordinal, String label) {
    return '$ordinal (généralement $label)';
  }

  @override
  String collectionByPhraseFieldMatch(String caption) {
    return '$caption, les figures correspondent';
  }

  @override
  String collectionByPhraseFieldExclude(String caption) {
    return '$caption, mais ne correspondent pas';
  }

  @override
  String collectionByPhraseRemoveMove(String move, String field) {
    return 'Supprimer $move de $field';
  }

  @override
  String get collectionQueryMatchLabel => 'Correspondance';

  @override
  String get collectionQueryGroupAll => 'Toutes';

  @override
  String get collectionQueryGroupAny => 'L’une de';

  @override
  String get collectionQueryGroupNone => 'Aucune de';

  @override
  String get collectionQueryTheseConditions => 'ces conditions';

  @override
  String get collectionQueryRemoveGroup => 'Supprimer le groupe';

  @override
  String get collectionQueryEmptyGroup =>
      'Aucune condition pour l’instant — ajoutez-en une ci-dessous.';

  @override
  String get collectionQueryAddCondition => 'Ajouter une condition';

  @override
  String get collectionQueryHasFigure => 'Contient une figure';

  @override
  String get collectionQuerySequenceThen => 'Séquence (puis)';

  @override
  String get collectionQueryConditionGroup => 'Groupe de conditions';

  @override
  String get collectionQueryAddButton => 'Ajouter';

  @override
  String get collectionQueryRemoveFigure => 'Supprimer la figure';

  @override
  String get collectionQueryThenFirst => 'D’abord';

  @override
  String get collectionQueryThenConnector => 'puis';

  @override
  String get collectionQueryThenLater => 'Plus tard';

  @override
  String get collectionQueryRemoveSequence => 'Supprimer la séquence';

  @override
  String get collectionQueryGroupFigures => 'Grouper les figures';

  @override
  String get collectionQueryFigureGroupMatch =>
      'Correspondance du groupe de figures';

  @override
  String get collectionQueryOfTheseFigures => 'de ces figures';

  @override
  String get collectionQuerySingleFigure => 'Figure unique';

  @override
  String get collectionQueryAddFigure => 'Ajouter une figure';

  @override
  String get collectionQueryRemoveFigureGroup =>
      'Supprimer le groupe de figures';

  @override
  String get collectionQueryMoveLabel => 'Mouvement';

  @override
  String get collectionQueryMoveHint => 'ex. swing';

  @override
  String get collectionQuerySectionLabel => 'Section';

  @override
  String get collectionQueryAnySection => 'N’importe quelle section';

  @override
  String collectionQueryAnyParam(String param) {
    return 'N’importe quel $param';
  }

  @override
  String get collectionBatchLevelUnspecified => 'Non spécifié (effacer)';

  @override
  String get collectionBatchLevelConfirm => 'Définir';

  @override
  String get collectionBatchTagEmptyAdd =>
      'Aucun tag pour l’instant. Créez-en un ci-dessous.';

  @override
  String get collectionBatchTagEmptyRemove =>
      'Les danses sélectionnées n’ont pas de tags à supprimer.';

  @override
  String get collectionCreateTagLabel => 'Créer un tag';

  @override
  String get collectionCreateTagButton => 'Créer le tag';

  @override
  String get collectionCreateTagError =>
      'Impossible de créer le tag. Réessayez.';

  @override
  String get collectionBatchTagAddConfirm => 'Ajouter';

  @override
  String get collectionBatchTagRemoveConfirm => 'Supprimer';

  @override
  String collectionBatchRatingStars(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count étoiles',
      one: '1 étoile',
    );
    return '$_temp0';
  }

  @override
  String get collectionBatchRatingUnrated => 'Non noté (effacer)';

  @override
  String get collectionBatchRatingConfirm => 'Définir';

  @override
  String get collectionBatchTunesFieldLabel => 'Ajouter un air';

  @override
  String get collectionBatchTunesAddButton => 'Ajouter l’air à la liste';

  @override
  String get collectionBatchTunesEmpty =>
      'Saisissez un nom d’air et ajoutez-le à la liste.';

  @override
  String collectionBatchTunesRemove(String tune) {
    return 'Supprimer $tune de la liste';
  }

  @override
  String get collectionBatchTunesConfirm => 'Ajouter';

  @override
  String get collectionBatchClearTunesConfirmTitle => 'Effacer les airs ?';

  @override
  String get collectionBatchClearTunesConfirmBody =>
      'Cette action supprime tous les airs des danses sélectionnées. Vous pouvez l’annuler ensuite.';

  @override
  String get collectionBatchClearTunesConfirmButton => 'Effacer les airs';

  @override
  String get collectionBatchCustomFieldKeyLabel => 'Champ';

  @override
  String get collectionBatchCustomFieldClearOption => 'Effacer ce champ';

  @override
  String get collectionBatchCustomFieldEmpty =>
      'Aucun champ personnalisé défini pour l’instant.';

  @override
  String get collectionBatchCustomFieldNumberInvalid => 'Saisissez un nombre';

  @override
  String get collectionBatchCustomFieldConfirm => 'Appliquer';

  @override
  String get danceFiguresEmpty => 'Aucune figure pour l’instant.';

  @override
  String danceFigureBeats(int beats) {
    String _temp0 = intl.Intl.pluralLogic(
      beats,
      locale: localeName,
      other: '$beats temps',
      one: '1 temps',
    );
    return '$_temp0';
  }

  @override
  String get danceFigureProgressionSemantic => 'progression';

  @override
  String danceFigureNote(String note) {
    return 'note : $note';
  }

  @override
  String get danceScreenTitle => 'Danse';

  @override
  String get danceNotFound => 'Danse introuvable.';

  @override
  String get danceEditFab => 'Modifier';

  @override
  String get danceDuplicateTooltip => 'Dupliquer la danse';

  @override
  String get danceDeleteTooltip => 'Supprimer la danse';

  @override
  String get danceMoreActions => 'Plus d’actions';

  @override
  String get danceSectionFigures => 'Figures';

  @override
  String get danceSectionCallingNotes => 'Notes d’appel';

  @override
  String get danceSectionWalkthrough => 'Déroulé';

  @override
  String get danceSectionTunes => 'Airs';

  @override
  String get danceSectionLinks => 'Liens';

  @override
  String get danceMissingRelated => '(danse manquante)';

  @override
  String get danceSectionPublishedSources => 'Sources publiées';

  @override
  String get danceSectionCustomFields => 'Champs personnalisés';

  @override
  String get danceSectionCallingHistory => 'Historique d’appel';

  @override
  String get danceCallingHistoryEmpty => 'Pas encore inclus dans un programme.';

  @override
  String get danceShowCanonicalTerms => 'Afficher les termes canoniques';

  @override
  String get danceCanonicalToggleLabel => 'Canonique';

  @override
  String danceProvenanceVia(String source) {
    return 'via $source';
  }

  @override
  String get danceProvenanceSourceManual => 'saisie manuelle';

  @override
  String get danceProvenanceSourceJson => 'import JSON';

  @override
  String get danceLinkKindVideo => 'vidéo';

  @override
  String get danceLinkKindSource => 'lien source';

  @override
  String get danceLinkKindLink => 'lien';

  @override
  String danceOpenLinkSemantic(String kind, String display) {
    return 'Ouvrir $kind : $display';
  }

  @override
  String danceOpenProgramSemantic(String title, String details) {
    return 'Ouvrir le programme : $title, $details';
  }

  @override
  String danceHalfStatsFirstHalf(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Appelée $count fois en première partie',
      one: 'Appelée 1 fois en première partie',
    );
    return '$_temp0';
  }

  @override
  String danceHalfStatsSecondHalf(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count fois en deuxième partie',
      one: '1 fois en deuxième partie',
    );
    return '$_temp0';
  }

  @override
  String danceHalfStatsOpened(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'a ouvert la première partie $count fois',
      one: 'a ouvert la première partie 1 fois',
    );
    return '$_temp0';
  }

  @override
  String danceHalfStatsClosed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'a clôturé la soirée (dernière danse de la deuxième partie) $count fois',
      one: 'a clôturé la soirée (dernière danse de la deuxième partie) 1 fois',
    );
    return '$_temp0';
  }

  @override
  String danceHalfStatsSemanticLabel(String description) {
    return 'Répartition par partie : $description';
  }

  @override
  String get danceSourceUnknown => '(source inconnue)';

  @override
  String danceSourcePage(String page) {
    return 'p. $page';
  }

  @override
  String danceSourceNumber(String number) {
    return 'n° $number';
  }

  @override
  String danceOpenSourceLinkSemantic(String title) {
    return 'Ouvrir le lien source : $title';
  }

  @override
  String danceSourceSemanticPrefix(String title) {
    return 'Source : $title';
  }

  @override
  String danceOpenDanceCrossRefSemantic(String title) {
    return 'Ouvrir la danse : $title';
  }

  @override
  String get commonAddToProgram => 'Ajouter au programme';

  @override
  String get programsEmptyTitle => 'Aucun programme pour l’instant';

  @override
  String get programsAddToProgramEmptyBody =>
      'Créez un programme pour commencer à construire une liste de sets.';

  @override
  String get programsCreateWithDance =>
      'Créer un nouveau programme avec cette danse';

  @override
  String programsAddDanceToProgramSemantic(
    String danceTitle,
    String programTitle,
    String details,
  ) {
    return 'Ajouter « $danceTitle » à $programTitle, $details';
  }

  @override
  String programsAddedToProgramSnack(String danceTitle, String programTitle) {
    return '« $danceTitle » ajouté à $programTitle.';
  }

  @override
  String get programsNewProgram => 'Nouveau programme';

  @override
  String programsCreatedProgramSnack(String programTitle, String danceTitle) {
    return '« $programTitle » créé avec « $danceTitle ».';
  }

  @override
  String get dancePerformTooltip => 'Exécuter cette danse';

  @override
  String get commonSwitchDialectTooltip => 'Changer de dialecte';

  @override
  String get programsStatusDraft => 'Brouillon';

  @override
  String get programsStatusFinalized => 'Finalisé';

  @override
  String get programsStatusPerformed => 'Joué';

  @override
  String get programsNoLongerExists => 'Ce programme n’existe plus.';

  @override
  String get programsFallbackTitle => 'Programme';

  @override
  String get programsUntitledDanceFallback => 'danse';

  @override
  String programsAddedDanceSnack(String title) {
    return '« $title » ajouté.';
  }

  @override
  String programsAddedDanceAnnounce(String title) {
    return '$title ajouté au programme.';
  }

  @override
  String get programsAddedNoteAnnounce => 'Note ajoutée au programme.';

  @override
  String get programsAddedBreakAnnounce => 'Pause ajoutée au programme.';

  @override
  String get programsMarkedAllPerformed =>
      'Toutes les danses marquées comme jouées.';

  @override
  String programsSavedSnack(String title) {
    return '« $title » enregistré.';
  }

  @override
  String get programsSaveError => 'Impossible d’enregistrer le programme.';

  @override
  String programsDuplicatedSnack(String title) {
    return 'Dupliqué sous le nom « $title ».';
  }

  @override
  String programsDeletedSnack(String title) {
    return '« $title » supprimé.';
  }

  @override
  String get programsDiscardTitle => 'Abandonner les modifications ?';

  @override
  String get programsDiscardBody =>
      'Vous avez des modifications non enregistrées dans ce programme.';

  @override
  String get programsKeepEditing => 'Continuer la modification';

  @override
  String get programsDiscard => 'Abandonner';

  @override
  String get programsDraftTitle => 'Brouillon non enregistré';

  @override
  String get programsDraftBody =>
      'Vous avez un brouillon non enregistré pour ce programme. Voulez-vous le restaurer ?';

  @override
  String get programsDraftRestore => 'Restaurer';

  @override
  String get programsDraftDiscard => 'Abandonner';

  @override
  String get programsBuildProgram => 'Construire le programme';

  @override
  String get programsBuildTab => 'Construire';

  @override
  String get programsMatrixTab => 'Matrice';

  @override
  String get programsPerformTooltip => 'Exécuter ce programme';

  @override
  String get programsMarkAllPerformedTooltip => 'Tout marquer comme joué';

  @override
  String get programsSaveDirty => 'Enregistrer *';

  @override
  String get commonSave => 'Enregistrer';

  @override
  String get programsLoading => 'Chargement du programme';

  @override
  String get programsLoadError => 'Impossible de charger le programme.';

  @override
  String get programsDeletedDanceFallback => '(danse supprimée)';

  @override
  String get programsSlotsLabel => 'Créneaux';

  @override
  String get programsAddDanceButton => 'Ajouter une danse';

  @override
  String get programsAddNoteBreakButton => 'Ajouter une note / pause';

  @override
  String get programsInsertBreakButton => 'Insérer une pause';

  @override
  String get programsAddADanceSheetTitle => 'Ajouter une danse';

  @override
  String get commonClose => 'Fermer';

  @override
  String get programsNoDateSet => 'Aucune date définie';

  @override
  String get programsTitleLabel => 'Titre';

  @override
  String get programsTitleHint => 'ex. Contra du vendredi soir';

  @override
  String get programsTitleRequired => 'Un titre est obligatoire.';

  @override
  String get programsEventDateLabel => 'Date de l’événement';

  @override
  String get programsSetDate => 'Définir la date';

  @override
  String get programsChangeDate => 'Modifier';

  @override
  String get programsClearEventDate => 'Effacer la date de l’événement';

  @override
  String get programsVenueLabel => 'Lieu';

  @override
  String get programsVenueHint => 'ex. Salle polyvalente';

  @override
  String programsVenueLinkedHint(String venueName) {
    return 'Également lié au lieu enregistré : $venueName. Activez les lieux réutilisables dans les Paramètres pour le consulter ou le modifier.';
  }

  @override
  String get programsVenueLinkedHintFallbackName => 'un lieu enregistré';

  @override
  String programsVenueLegacyTextHint(String venueText) {
    return 'Lieu saisi précédemment : « $venueText ». Liez un lieu enregistré ci-dessous pour utiliser des détails réutilisables — votre texte saisi est conservé.';
  }

  @override
  String get programsBandLabel => 'Orchestre';

  @override
  String get programsBandHint => 'ex. Les Violoneux';

  @override
  String get programsCallerLabel => 'Caller';

  @override
  String get programsCallerHint => 'Caller principal de l’événement';

  @override
  String get programsDancerLevelLabel => 'Niveau des danseurs';

  @override
  String get programsDancerLevelHint => 'ex. Tous niveaux, Expérimenté';

  @override
  String get programsNotesLabel => 'Notes';

  @override
  String get programsStatusFieldLabel => 'Statut';

  @override
  String get programsHideAlternatesTitle =>
      'Masquer les alternatives dans la liste de sets';

  @override
  String get programsHideAlternatesSubtitle =>
      'Omet les créneaux ALT du résumé, du PDF et de la liste de sets exportée. Le constructeur affiche toujours tous les créneaux.';

  @override
  String programsWarningCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count avertissements',
      one: '1 avertissement',
    );
    return '$_temp0';
  }

  @override
  String get programsAddNoteBreakDialogTitle => 'Ajouter une note ou une pause';

  @override
  String get programsFreeTextLabel => 'Texte';

  @override
  String get programsFreeTextHint => 'ex. Pause, valse, annonce';

  @override
  String get commonAdd => 'Ajouter';

  @override
  String get programsTitle => 'Programmes';

  @override
  String get programsSortTitle => 'Titre';

  @override
  String get programsSortRecentlyUpdated => 'Récemment mis à jour';

  @override
  String get programsSortEventDate => 'Date de l’événement';

  @override
  String programsSortByTooltip(String label) {
    return 'Trier par ($label)';
  }

  @override
  String get programsListLoadError => 'Impossible de charger vos programmes.';

  @override
  String get programsListEmptyBody =>
      'Créez des listes de sets pour vos événements ici. Créez votre premier programme pour commencer.';

  @override
  String programsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count programmes',
      one: '1 programme',
    );
    return '$_temp0';
  }

  @override
  String get programsSummaryTitle => 'Programme';

  @override
  String get programsEditProgram => 'Modifier le programme';

  @override
  String get programsSummaryUnavailable =>
      'Ce programme n’est plus disponible.';

  @override
  String get programsPerformDisabledTooltip =>
      'Ajoutez au moins un créneau pour exécuter ce programme';

  @override
  String programsSummaryBand(String band) {
    return 'Orchestre : $band';
  }

  @override
  String programsSummaryCaller(String caller) {
    return 'Caller : $caller';
  }

  @override
  String programsSummaryLevel(String level) {
    return 'Niveau : $level';
  }

  @override
  String programsSetListHeader(int count) {
    return 'Liste de sets ($count)';
  }

  @override
  String get programsSummaryEmptySetList =>
      'Aucun créneau pour l’instant — ouvrez le constructeur pour ajouter des danses.';

  @override
  String programsSummaryGuest(String caller) {
    return 'Invité : $caller';
  }

  @override
  String programsPlannedMinutes(int minutes) {
    return '$minutes min';
  }

  @override
  String get programsAltBadge => 'Alt';

  @override
  String get programsDanceUnavailable => 'Danse indisponible';

  @override
  String programsSummaryNote(String note) {
    return 'Note : $note';
  }

  @override
  String programsSummaryAlternateSemantic(String title) {
    return 'Alternative : $title';
  }

  @override
  String get programsPerformed => 'Joué';

  @override
  String programsSlotCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count créneaux',
      one: '1 créneau',
    );
    return '$_temp0';
  }

  @override
  String get programsSlotNoteFallback => 'Note';

  @override
  String get programsSlotEditorEmpty =>
      'Aucun créneau pour l’instant. Ajoutez une danse ou une note pour commencer.';

  @override
  String get programsSlotMoved => 'Créneau déplacé.';

  @override
  String get programsSlotMovedUp => 'Créneau déplacé vers le haut.';

  @override
  String get programsSlotMovedDown => 'Créneau déplacé vers le bas.';

  @override
  String programsSlotCutBanner(String name) {
    return '« $name » est coupé — appuyez sur Coller pour le placer.';
  }

  @override
  String get programsPasteBeforeFirst => 'Coller avant le premier créneau';

  @override
  String programsPasteAfter(String title) {
    return 'Coller après $title';
  }

  @override
  String get programsPasteHere => 'Coller ici';

  @override
  String get programsMarkedPrimary => 'Marqué comme principal.';

  @override
  String get programsMarkedAlternate => 'Marqué comme alternatif.';

  @override
  String get programsMarkedPerformed => 'Marqué comme joué.';

  @override
  String get programsPerformedCleared => 'Marque de joué effacée.';

  @override
  String programsRemovedSlot(String name) {
    return '« $name » supprimé.';
  }

  @override
  String get programsAltOrdinal => 'ALT';

  @override
  String programsDragToReorder(String title) {
    return 'Faire glisser pour réorganiser $title';
  }

  @override
  String programsMoveSlotUp(String title) {
    return 'Déplacer $title vers le haut';
  }

  @override
  String programsMoveSlotDown(String title) {
    return 'Déplacer $title vers le bas';
  }

  @override
  String programsCutSlot(String title) {
    return 'Couper $title';
  }

  @override
  String programsMoreActionsForSlot(String title) {
    return 'Plus d’actions pour $title';
  }

  @override
  String get programsEditSlotMenu => 'Modifier le créneau';

  @override
  String get programsMakePrimaryMenu => 'Définir comme principal';

  @override
  String get programsMarkAlternateMenu => 'Marquer comme alternatif';

  @override
  String get programsClearPerformedMenu => 'Effacer joué';

  @override
  String get programsMarkPerformedMenu => 'Marquer comme joué';

  @override
  String get programsRemoveSlotMenu => 'Supprimer le créneau';

  @override
  String get programsSlotTextRequiredError =>
      'Saisissez un texte pour ce créneau.';

  @override
  String get programsWholeNumberError => 'Saisissez un entier ≥ 0.';

  @override
  String get programsEditDanceSlotTitle => 'Modifier le créneau de danse';

  @override
  String get programsEditNoteTitle => 'Modifier la note';

  @override
  String get programsCallerNoteLabel => 'Note du caller (optionnelle)';

  @override
  String get programsCallerNoteHint => 'ex. enseigner le hey en premier';

  @override
  String get programsGuestCallerLabel => 'Caller invité (optionnel)';

  @override
  String get programsPlannedMinutesLabel => 'Minutes prévues (optionnel)';

  @override
  String get programsAlternateDanceTitle => 'Danse alternative';

  @override
  String get programsAlternateDanceSubtitle =>
      'Affichée en retrait sous le créneau qui la précède.';

  @override
  String get commonDone => 'Terminé';

  @override
  String programsMatrixSemanticLabel(int danceCount, int moveCount) {
    String _temp0 = intl.Intl.pluralLogic(
      moveCount,
      locale: localeName,
      other: '$moveCount mouvements',
      one: '1 mouvement',
    );
    return 'Matrice de programmation : $danceCount danses par $_temp0';
  }

  @override
  String programsMatrixOmittedCaption(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count créneaux texte libre',
      one: '1 créneau texte libre',
    );
    return '$_temp0 (pauses, notes) omis — la matrice affiche uniquement les danses.';
  }

  @override
  String programsMatrixMoveHeaderSemantic(String label) {
    return 'Mouvement : $label';
  }

  @override
  String programsMatrixHideColumnSemantic(String label) {
    return 'Masquer la colonne $label';
  }

  @override
  String get programsMatrixShowAllColumnsSemantic =>
      'Afficher toutes les colonnes';

  @override
  String programsMatrixRowHeaderSemantic(
    String title,
    String alt,
    String half,
  ) {
    String _temp0 = intl.Intl.selectLogic(half, {
      'first': 'Danse alternative : $title, première partie',
      'second': 'Danse alternative : $title, deuxième partie',
      'other': 'Danse alternative : $title',
    });
    String _temp1 = intl.Intl.selectLogic(half, {
      'first': 'Danse : $title, première partie',
      'second': 'Danse : $title, deuxième partie',
      'other': 'Danse : $title',
    });
    String _temp2 = intl.Intl.selectLogic(alt, {
      'yes': '$_temp0',
      'other': '$_temp1',
    });
    return '$_temp2';
  }

  @override
  String programsMatrixHalfShort(String half) {
    String _temp0 = intl.Intl.selectLogic(half, {
      'first': '1ère',
      'other': '2ème',
    });
    return '$_temp0';
  }

  @override
  String get programsMatrixFormationColumnHeader => 'Formation';

  @override
  String programsMatrixFormationSemantic(String dance, String label) {
    return '$dance, formation : $label';
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
      'yes': ', se répète dans la même phrase qu\'une danse voisine',
      'other': '',
    });
    String _temp1 = intl.Intl.selectLogic(debut, {
      'yes': ', introduit ici',
      'other': '',
    });
    String _temp2 = intl.Intl.selectLogic(first, {
      'yes': ', première figure de la danse',
      'other': '',
    });
    String _temp3 = intl.Intl.selectLogic(present, {
      'no': 'absent',
      'other': 'présent$_temp0$_temp1$_temp2',
    });
    return '$dance, $move : $_temp3';
  }

  @override
  String programsMatrixChipQualifiedTitle(
    String title,
    String alt,
    String half,
  ) {
    String _temp0 = intl.Intl.selectLogic(half, {
      'first': '$title (danse alternative, première partie)',
      'second': '$title (danse alternative, deuxième partie)',
      'other': '$title (danse alternative)',
    });
    String _temp1 = intl.Intl.selectLogic(half, {
      'first': '$title (première partie)',
      'second': '$title (deuxième partie)',
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
    return 'Mouvement : $label, utilisé dans $count danse(s) sur $total';
  }

  @override
  String programsMatrixNOfTotal(int count, int total) {
    return '$count sur $total';
  }

  @override
  String get programsMatrixNoComparableMoves =>
      'Aucune de ces danses n’a encore de figures structurées, il n’y a donc pas de mouvements à comparer.';

  @override
  String get programsMatrixRepeatedMovesHeader => 'Mouvements répétés';

  @override
  String get programsMatrixRepeatedMovesSubtitle =>
      'Mouvements partagés entre deux danses ou plus, les plus répétés en premier.';

  @override
  String get programsMatrixNoRepeatsNote =>
      'Aucun mouvement ne se répète dans ces danses — chaque mouvement ci-dessous est utilisé par une seule danse.';

  @override
  String get programsMatrixUsedOnceHeader => 'Utilisé une seule fois';

  @override
  String get programsMatrixLegendIntroduced => 'Introduit ici';

  @override
  String get programsMatrixLegendFirstFigure => 'Première figure de la danse';

  @override
  String get programsMatrixLegendPresent => 'Présent';

  @override
  String get programsMatrixLegendCollision =>
      'Même phrase qu\'une danse voisine';

  @override
  String get programsMatrixEmptyTitle => 'Pas encore de figures structurées';

  @override
  String get programsMatrixEmptyBody =>
      'La matrice se remplit automatiquement au fur et à mesure que les danses du programme acquièrent des figures structurées.';

  @override
  String get performTitle => 'Perform';

  @override
  String get performExitTooltip => 'Quitter la vue Perform';

  @override
  String get performExitTitle => 'Quitter Perform ?';

  @override
  String get performExitBody =>
      'Quitter la vue Perform ? Votre position et le chrono en cours sont conservés, vous pouvez reprendre là où vous en étiez.';

  @override
  String get performExitCancel => 'Continuer';

  @override
  String get performExitConfirm => 'Quitter';

  @override
  String get performTapTempo => 'Tap tempo';

  @override
  String performBpmReadout(int bpm) {
    return '$bpm BPM';
  }

  @override
  String get performTapToSetTempo => 'Appuyez pour définir le tempo';

  @override
  String performBpmSemantic(int bpm) {
    return '$bpm battements par minute';
  }

  @override
  String get performNoTempoSemantic =>
      'Aucun tempo défini. Appuyez sur la cible pour définir un tempo.';

  @override
  String get performRecordBeatHint => 'enregistrer un temps';

  @override
  String get performTapRefineHint =>
      'Continuez d’appuyer pour affiner · Réinitialiser pour recommencer';

  @override
  String get performTapTwiceHint => 'Appuyez au moins deux fois en rythme';

  @override
  String get performResetTempo => 'Réinitialiser';

  @override
  String get performUntitledSlot => 'Créneau sans titre';

  @override
  String performMarkedPerformedAnnounce(String label) {
    return '$label marqué comme joué';
  }

  @override
  String get performClearedPerformedAnnounce => 'Marque de joué effacée';

  @override
  String performMovedToPosition(String label, int position) {
    return '$label déplacé à la position $position';
  }

  @override
  String get performDanceFallback => 'danse';

  @override
  String performInsertedAnnounce(String title) {
    return '$title inséré';
  }

  @override
  String get performAddedNoteAnnounce => 'Note ajoutée';

  @override
  String get performInsertADance => 'Insérer une danse';

  @override
  String get performAdjustProgram => 'Ajuster le programme';

  @override
  String get performCurrentSlotSection => 'Créneau actuel';

  @override
  String get performPerformedTapToClear => 'Joué — appuyez pour effacer';

  @override
  String get performReorderSection => 'Réorganiser les créneaux suivants';

  @override
  String get performNoLaterSlots => 'Aucun créneau suivant à réorganiser.';

  @override
  String get performInsertDanceFromSearch =>
      'Insérer une danse depuis la recherche';

  @override
  String get performAdHocNoteLabel => 'Note / pause ad hoc';

  @override
  String get performAdHocNoteHint => 'ex. Valse, annonces';

  @override
  String get performAddNote => 'Ajouter une note';

  @override
  String performAlternatesCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count alternatives',
      one: '1 alternative',
    );
    return '$_temp0';
  }

  @override
  String performMoveLabelUp(String label) {
    return 'Déplacer « $label » vers le haut';
  }

  @override
  String performMoveLabelDown(String label) {
    return 'Déplacer « $label » vers le bas';
  }

  @override
  String performSlotPosition(int current, int total) {
    return 'Créneau $current sur $total';
  }

  @override
  String performShowingSlot(String label) {
    return 'Affichage de $label';
  }

  @override
  String get performAdjustmentUndone => 'Ajustement annulé';

  @override
  String get performProgramAdjustedSnack => 'Programme ajusté.';

  @override
  String get performProgramAdjustedAnnounce => 'Programme ajusté';

  @override
  String get performNoSlots => 'Ce programme n’a aucun créneau.';

  @override
  String get performJumpToSlot => 'Aller au créneau';

  @override
  String get performShowAlternate => 'Afficher l’alternative';

  @override
  String get performPreviousSlot => 'Créneau précédent';

  @override
  String get performNextSlot => 'Créneau suivant';

  @override
  String get performResumeTimers => 'Reprendre les chronomètres';

  @override
  String get performPauseTimers => 'Mettre en pause les chronomètres';

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
      other: '$planned minutes',
      one: '1 minute',
    );
    String _temp1 = intl.Intl.selectLogic(hasPlanned, {
      'yes': ', prévu $_temp0',
      'other': '',
    });
    String _temp2 = intl.Intl.selectLogic(over, {
      'yes': ', dépassement',
      'other': '',
    });
    String _temp3 = intl.Intl.selectLogic(paused, {
      'yes': ', en pause',
      'other': '',
    });
    return 'Temps du programme $programTime, temps du créneau $slotTime$_temp1$_temp2$_temp3';
  }

  @override
  String performPlannedMin(int planned) {
    return 'prévu $planned min';
  }

  @override
  String get performOverSuffix => ' dépassé';

  @override
  String get performCallingNotes => 'Notes d’appel';

  @override
  String get performWalkthrough => 'Déroulé';

  @override
  String get performShowWalkthrough => 'Afficher le déroulé';

  @override
  String get performWalkthroughEmpty => 'Aucun déroulé pour cette danse.';

  @override
  String get performNoFigures => 'Aucune figure pour l’instant.';

  @override
  String get performDecreaseTextSize => 'Réduire la taille du texte';

  @override
  String get performIncreaseTextSize => 'Augmenter la taille du texte';

  @override
  String get performShowCanonicalTerms => 'Afficher les termes canoniques';

  @override
  String get performMoreActions => 'Plus d’actions';

  @override
  String get performAutoSizeMenuLabel =>
      'Ajuster automatiquement le texte à l’écran';

  @override
  String get performAutoSizeOnTooltip =>
      'Ajustement automatique activé — appuyez pour la taille manuelle';

  @override
  String get performAutoSizeOffTooltip =>
      'Ajustement automatique désactivé — appuyez pour adapter le texte à l’écran';

  @override
  String get performStageThemeOnTooltip =>
      'Thème scène activé — appuyez pour utiliser le thème de l’application';

  @override
  String get performStageThemeOffTooltip =>
      'Thème scène désactivé — appuyez pour le thème sombre scène';

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
      other: '$beats temps',
      one: '1 temps',
    );
    String _temp3 = intl.Intl.selectLogic(hasNote, {
      'yes': ', note : $note',
      'other': '',
    });
    return '$main$_temp0$_temp1, $_temp2$_temp3';
  }

  @override
  String get programsSelectTitle => 'Sélectionner un programme';

  @override
  String get programsSelectBody =>
      'Choisissez un programme dans la liste ou créez-en un nouveau.';

  @override
  String get commonEdit => 'Modifier';

  @override
  String get commonChange => 'Modifier';

  @override
  String get commonTryAgain => 'Réessayer';

  @override
  String get exportTooltip => 'Exporter';

  @override
  String get exportShareDanceText => 'Partager la danse (texte)';

  @override
  String get exportCopyDance => 'Copier la danse';

  @override
  String get exportPrintPdf => 'Exporter / imprimer en PDF';

  @override
  String get exportDanceCopied => 'Danse copiée dans le presse-papiers.';

  @override
  String get exportShareDanceError => 'Impossible de partager cette danse';

  @override
  String get exportDanceError => 'Impossible d’exporter cette danse';

  @override
  String get exportShareSetListText => 'Partager la liste de sets (texte)';

  @override
  String get exportShareProgramBundle => 'Partager (programme + danses)';

  @override
  String get exportCopySetList => 'Copier la liste de sets';

  @override
  String get exportSetListCopied =>
      'Liste de sets copiée dans le presse-papiers.';

  @override
  String get exportShareSetListError =>
      'Impossible de partager cette liste de sets';

  @override
  String get exportShareProgramError => 'Impossible de partager ce programme';

  @override
  String get exportSetListError => 'Impossible d’exporter cette liste de sets';

  @override
  String get exportMatrixPdfTooltip => 'Exporter ou imprimer la matrice en PDF';

  @override
  String get exportMatrixPdfFilename => 'Matrice de programmation';

  @override
  String get exportLabelFormation => 'Formation';

  @override
  String get exportLabelLevel => 'Niveau';

  @override
  String get exportLabelMixer => 'Mixer';

  @override
  String get exportLabelStatus => 'Statut';

  @override
  String get exportLabelPhrase => 'Phrase';

  @override
  String get exportLabelFigures => 'Figures';

  @override
  String get exportLabelCallingNotes => 'Notes d’appel';

  @override
  String get exportLabelWalkthrough => 'Déroulé';

  @override
  String exportBeatsLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count temps',
      one: '1 temps',
    );
    return '$_temp0';
  }

  @override
  String get exportLevelMixedOnly => 'Mixte';

  @override
  String exportLevelWithMixed(String level) {
    return '$level (mixte)';
  }

  @override
  String get exportLabelBand => 'Orchestre';

  @override
  String get exportLabelCaller => 'Caller';

  @override
  String get exportLabelNotes => 'Notes';

  @override
  String get exportLabelAlt => 'ALT';

  @override
  String get exportLabelGuest => 'invité';

  @override
  String get exportLabelPerformed => 'joué';

  @override
  String get exportUnknownDanceLabel => 'Danse sans titre';

  @override
  String exportMinutesLabel(int count) {
    return '$count min';
  }

  @override
  String get exportLabelVenue => 'Lieu';

  @override
  String get exportLabelTime => 'Heure';

  @override
  String get exportLabelSchedule => 'Calendrier';

  @override
  String get exportLabelPrice => 'Tarif';

  @override
  String get exportLabelSponsor => 'Sponsor';

  @override
  String get exportMatrixDefaultTitle => 'Matrice de programmation';

  @override
  String get exportMatrixDanceColumn => 'Danse';

  @override
  String get exportMatrixFormationColumn => 'Formation';

  @override
  String get exportMatrixEmptyState =>
      'Pas encore de figures structurées — la matrice se remplit automatiquement au fur et à mesure que les danses du programme acquièrent des figures structurées.';

  @override
  String get exportMatrixLegendDebut => 'Introduit ici';

  @override
  String get exportMatrixLegendFirst => 'Première figure de la danse';

  @override
  String get exportMatrixLegendPresent => 'Présent';

  @override
  String get exportMatrixLegendCollision => 'Même phrase qu\'une danse voisine';

  @override
  String exportMatrixOmittedCaption(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count créneaux texte libre',
      one: '1 créneau texte libre',
    );
    return '$_temp0 (pauses, notes) omis — la matrice affiche uniquement les danses.';
  }

  @override
  String get exportVenueContactTitle =>
      'Inclure les coordonnées du lieu dans cet export ?';

  @override
  String get exportVenueContactBody =>
      'Ce sont des coordonnées personnelles du lieu. Elles sont exclues de cet export à moins que vous ne choisissiez de les inclure.';

  @override
  String get exportVenueContactConfirm => 'Continuer';

  @override
  String get exportVenueContact1Name => 'Nom du contact 1';

  @override
  String get exportVenueContact1Phone => 'Téléphone du contact 1';

  @override
  String get exportVenueContact1Email => 'E-mail du contact 1';

  @override
  String get exportVenueContact2Name => 'Nom du contact 2';

  @override
  String get exportVenueContact2Phone => 'Téléphone du contact 2';

  @override
  String get exportVenueContact2Email => 'E-mail du contact 2';

  @override
  String get onlineSearchToggleTitle => 'Recherche en ligne';

  @override
  String get onlineSearchToggleSubtitle =>
      'Recherchez et importez des danses directement en ligne (nécessite internet). Les filtres locaux ne s’appliquent pas.';

  @override
  String onlineSearchFieldLabel(String source) {
    return 'Rechercher sur $source';
  }

  @override
  String get onlineSearchFieldHint =>
      'Rechercher des danses en ligne par titre…';

  @override
  String onlineResultCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count résultats en ligne',
      one: '1 résultat en ligne',
    );
    return '$_temp0';
  }

  @override
  String onlineSearchHintByPhrase(String source) {
    return 'Saisissez un titre ou ajoutez des figures par phrase pour rechercher sur $source.';
  }

  @override
  String onlineSearchHintTitle(String source) {
    return 'Saisissez un titre pour rechercher sur $source.';
  }

  @override
  String onlineNoResults(String source) {
    return 'Aucune danse sur $source ne correspond à votre recherche.';
  }

  @override
  String onlineLoadError(String source) {
    return 'Impossible de charger cette danse depuis $source.';
  }

  @override
  String get onlineImportError => 'Impossible d’importer cette danse.';

  @override
  String onlineSearchFailed(String source) {
    return 'Impossible de rechercher dans $source. Veuillez réessayer.';
  }

  @override
  String onlineImportCreated(String title) {
    return '« $title » importé.';
  }

  @override
  String onlineImportAlreadyInCollection(String title) {
    return '« $title » est déjà dans votre collection.';
  }

  @override
  String onlineImportVariationDialogBody(String existingTitle) {
    return 'Le titre et le caller de cette danse correspondent à « $existingTitle », mais ses figures sont différentes. Comment voulez-vous l’importer ?';
  }

  @override
  String get onlineImportVariationDialogActionVariation =>
      'Importer comme variante';

  @override
  String get onlineImportVariationDialogActionLink =>
      'Même danse (mettre à jour l’existante)';

  @override
  String onlineImportVariationDialogLinkWarning(String existingTitle) {
    return 'Votre version de « $existingTitle » sera remplacée par l’enregistrement en ligne — y compris ses figures, ses notes d’appel, ses tags, sa note et ses champs personnalisés. Elle conserve sa place dans vos programmes et son historique d’appel.';
  }

  @override
  String get onlineImportCrossSourceDuplicateDialogTitle =>
      'Vous avez déjà cette danse';

  @override
  String onlineImportCrossSourceDuplicateDialogBody(String existingTitle) {
    return 'Votre collection contient déjà « $existingTitle » provenant d’une autre source. Les deux versions ont la même séquence de mouvements.';
  }

  @override
  String get onlineImportCrossSourceDuplicateDialogActionDuplicate =>
      'Importer une seconde copie';

  @override
  String get onlineAttributionCallersBox =>
      'Depuis The Caller\'s Box (en ligne)';

  @override
  String get onlineAttributionContraDb => 'Depuis ContraDB (en ligne)';

  @override
  String get importDances => 'Importer des danses';

  @override
  String get importAction => 'Importer';

  @override
  String get importProgramTooltip => 'Importer un programme';

  @override
  String get importFromTitleList => 'Depuis une liste de titres';

  @override
  String get importFromContraDb => 'Depuis ContraDB';

  @override
  String get importProgramTitleLabel => 'Titre du programme';

  @override
  String get importProgramCreateError =>
      'Impossible d’enregistrer le programme importé.';

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
      other: '$slots créneaux',
      one: '1 créneau',
    );
    String _temp1 = intl.Intl.pluralLogic(
      notes,
      locale: localeName,
      other: '$notes notes',
      one: '1 note',
    );
    return '« $title » importé — $_temp0 ($linked liés, $_temp1).';
  }

  @override
  String get importContraDbTitle => 'Importer depuis ContraDB';

  @override
  String get importContraDbPasteUrl => 'Coller l’URL';

  @override
  String get importContraDbSearchByName => 'Rechercher par nom';

  @override
  String get importContraDbUrlLabel => 'URL du programme ContraDB';

  @override
  String get importContraDbUrlHint => 'ex. https://contradb.com/programs/33';

  @override
  String get importContraDbFetching => 'Récupération…';

  @override
  String get importContraDbFetch => 'Récupérer le programme';

  @override
  String get importContraDbSearchLabel => 'Rechercher des programmes ContraDB';

  @override
  String get importContraDbSearchHint =>
      'Saisissez une partie du nom du programme';

  @override
  String get importContraDbListError =>
      'Impossible de charger la liste des programmes ContraDB.';

  @override
  String get importContraDbSearchPrompt =>
      'Saisissez une partie d’un nom de programme pour rechercher dans ContraDB.';

  @override
  String get importContraDbNoMatches => 'Aucun programme correspondant.';

  @override
  String get importContraDbMarkerImported => 'Importé';

  @override
  String importContraDbMarkerImportedTooltip(String date) {
    return 'Importé le $date';
  }

  @override
  String get importContraDbMarkerImportedTooltipNoDate =>
      'Déjà importé depuis ContraDB';

  @override
  String get importContraDbMarkerPossible => 'Peut-être importé';

  @override
  String get importContraDbMarkerPossibleTooltip =>
      'Un programme portant ce titre existe déjà';

  @override
  String importContraDbFetchError(String error) {
    return 'Impossible de récupérer ce programme.\n$error';
  }

  @override
  String get importContraDbFetchGenericError =>
      'Impossible de récupérer ce programme.';

  @override
  String get importContraDbPastePrompt =>
      'Collez une URL de programme ContraDB ci-dessus et appuyez sur « Récupérer le programme ».';

  @override
  String get importContraDbEmptyProgram =>
      'Aucune danse ni note trouvée sur cette page de programme.';

  @override
  String get importContraDbResolveError =>
      'Impossible d’importer le programme ContraDB.';

  @override
  String importContraDbActivityCount(int activities, int dances, int notes) {
    String _temp0 = intl.Intl.pluralLogic(
      activities,
      locale: localeName,
      other: '$activities activités',
      one: '1 activité',
    );
    String _temp1 = intl.Intl.pluralLogic(
      dances,
      locale: localeName,
      other: '$dances danses',
      one: '1 danse',
    );
    String _temp2 = intl.Intl.pluralLogic(
      notes,
      locale: localeName,
      other: '$notes notes',
      one: '1 note',
    );
    return '$_temp0 ($_temp1, $_temp2)';
  }

  @override
  String get importContraDbDanceFallback => 'Danse ContraDB';

  @override
  String get importEventDateNone => 'Aucune date définie';

  @override
  String get importEventDateLabel => 'Date de l’événement';

  @override
  String get importEventDateSet => 'Définir la date';

  @override
  String get importEventDateClear => 'Effacer la date de l’événement';

  @override
  String get importEventDateDetected =>
      'Date détectée depuis le titre — vérifiez-la avant d’importer.';

  @override
  String get importTitleListTitle => 'Importer depuis une liste de titres';

  @override
  String get importCollectionLoadError =>
      'Impossible de charger votre collection.';

  @override
  String get importTitleListDancesLabel => 'Titres de danses (un par ligne)';

  @override
  String get importTitleListDancesHint =>
      'Collez un titre de danse par ligne.\nLes lignes non reconnues sont conservées comme notes.';

  @override
  String get importTitleListEmptyHint =>
      'Collez une liste de titres de danses ci-dessus pour prévisualiser le programme.';

  @override
  String get importResolving => 'Recherche…';

  @override
  String get importResolveOnline => 'Résoudre les non-correspondances en ligne';

  @override
  String get importPlaintextImportedOnline => 'Importé depuis Caller\'s Box';

  @override
  String get importPlaintextLinked => 'Lié à la danse';

  @override
  String get importPlaintextAmbiguous =>
      'Plusieurs correspondances — ajouté comme note';

  @override
  String get importPlaintextUnmatched =>
      'Aucune correspondance — ajouté comme note';

  @override
  String get importPlaintextSearchError =>
      'Impossible de rechercher sur The Caller\'s Box.';

  @override
  String importPlaintextSlotCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count créneaux',
      one: '1 créneau',
    );
    return '$_temp0';
  }

  @override
  String importPlaintextResolvedNone(int remaining) {
    String _temp0 = intl.Intl.pluralLogic(
      remaining,
      locale: localeName,
      other: '$remaining titres conservés comme notes',
      one: '$remaining titre conservé comme note',
    );
    return 'Aucune correspondance Caller\'s Box trouvée — $_temp0.';
  }

  @override
  String importPlaintextResolvedLinked(int linked, int remaining) {
    String _temp0 = intl.Intl.pluralLogic(
      linked,
      locale: localeName,
      other: '$linked titres liés',
      one: '$linked titre lié',
    );
    String _temp1 = intl.Intl.pluralLogic(
      remaining,
      locale: localeName,
      other: ' ; $remaining encore comme notes.',
      one: ' ; $remaining encore comme note.',
      zero: '.',
    );
    return '$_temp0 depuis The Caller\'s Box$_temp1';
  }

  @override
  String get importReviewClose => 'Fermer l’import';

  @override
  String get importReviewSourceLabel => 'Source';

  @override
  String importReviewFromSource(String source) {
    return 'Importer depuis $source.';
  }

  @override
  String importReviewDancesFromSource(String source) {
    return 'Importer des danses depuis $source.';
  }

  @override
  String get importSourceLabelGenericJson =>
      'un fichier JSON Caller\'s Compendium';

  @override
  String get importSourceLabelCallersBox => 'The Caller\'s Box';

  @override
  String get importSourceLabelContraDb => 'ContraDB';

  @override
  String get importSourceLabelCallersCompanionUsr =>
      'un fichier .USR de Caller\'s Companion';

  @override
  String get importSourceLabelTitleList => 'une liste de titres';

  @override
  String get importReviewTitleListSubtitle =>
      'Collez un titre de danse par ligne. Chaque titre est listé pour vérification — ceux que vous avez déjà sont affichés mais jamais réimportés, et rien n’est ajouté à votre collection avant votre confirmation.';

  @override
  String get importReviewPasteTitles => 'Titres de danses, un par ligne';

  @override
  String importReviewTitleListCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count titres',
      one: '1 titre',
      zero: 'Aucun titre pour l’instant',
    );
    return '$_temp0';
  }

  @override
  String importReviewTitleListDuplicates(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count titres répétés ignorés',
      one: '1 titre répété ignoré',
    );
    return '$_temp0';
  }

  @override
  String importTitleListTooManyTitles(int count, int max) {
    return 'Cela fait $count titres. Importez-en jusqu’à $max à la fois.';
  }

  @override
  String get importTitleListTextTooLong =>
      'Ce texte collé est trop long pour être lu comme une liste de titres. Essayez de coller une liste plus courte.';

  @override
  String importReviewTitleListProgress(int done, int total) {
    return 'Recherche de $done sur $total…';
  }

  @override
  String importReviewTitleListPasted(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count titres collés',
      one: '1 titre collé',
    );
    return '$_temp0';
  }

  @override
  String importReviewTitleListToImport(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count à importer',
      one: '1 à importer',
    );
    return '$_temp0';
  }

  @override
  String importReviewTitleListOwned(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count déjà dans votre collection',
      one: '1 déjà dans votre collection',
    );
    return '$_temp0';
  }

  @override
  String importReviewTitleListNotFound(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count introuvables',
      one: '1 introuvable',
    );
    return '$_temp0';
  }

  @override
  String importReviewTitleListOwnedBy(String authors) {
    return 'Vous avez déjà cette danse, de $authors.';
  }

  @override
  String get importReviewTitleListOwnedUnknownAuthor =>
      'Vous avez déjà cette danse.';

  @override
  String importReviewTitleListOwnedMany(int count) {
    return 'Vous avez $count danses portant ce titre.';
  }

  @override
  String get importTitleListReasonNoResults =>
      'The Caller\'s Box n’a aucune danse de ce nom.';

  @override
  String get importTitleListReasonNoExactMatch =>
      'Seulement des correspondances approchantes — rien avec exactement ce titre.';

  @override
  String get importTitleListReasonMultipleExactMatches =>
      'Plusieurs danses portent exactement ce titre, on ne sait donc pas laquelle vous vouliez.';

  @override
  String get importTitleListReasonFetchError =>
      'Impossible d’atteindre The Caller\'s Box pour ce titre.';

  @override
  String get importTitleListReasonLineTooLong =>
      'Trop long pour un titre de danse, la recherche n’a donc pas été lancée.';

  @override
  String get importReviewTitleListNothingToImport =>
      'Rien à importer ici — chaque titre est soit déjà dans votre collection, soit introuvable.';

  @override
  String importReviewSummaryAlreadyOwned(int count) {
    return 'Déjà dans votre collection : $count';
  }

  @override
  String importReviewSummaryNotFound(int count) {
    return 'Introuvables : $count';
  }

  @override
  String get importErrorFileTooLarge =>
      'Ce fichier est trop volumineux pour être importé.';

  @override
  String get archiveIntakeRejectedTooLarge =>
      'Ce fichier est trop volumineux pour être importé.';

  @override
  String get archiveIntakeRejectedUnreadable =>
      'Impossible de lire le fichier partagé.';

  @override
  String get archiveIntakeRejectedEmpty => 'Ce fichier est vide.';

  @override
  String get archiveIntakeRejectedNotArchive =>
      'Ce fichier n\'est pas un fichier de partage Caller’s Compendium.';

  @override
  String get archiveIntakeRejectedNewerVersion =>
      'Ce fichier a été créé avec une version plus récente de l\'application. Mettez l\'application à jour pour l\'importer.';

  @override
  String get archiveIntakeRejectedNoContent =>
      'Ce fichier ne contenait aucune danse ni aucun programme.';

  @override
  String get importErrorInsecureScheme =>
      'Les importations doivent utiliser une URL https:// sécurisée.';

  @override
  String get importErrorBlockedHost =>
      'Cette URL pointe vers un emplacement réseau qui ne peut pas être importé.';

  @override
  String get importErrorInvalidUrl =>
      'Cela ne ressemble pas à une URL http(s) valide.';

  @override
  String get importErrorTooManyRedirects =>
      'Cette URL a effectué trop de redirections.';

  @override
  String get importErrorResponseTooLarge =>
      'Cette réponse est trop volumineuse pour être importée.';

  @override
  String get importErrorEmptyUrl => 'Saisissez une URL pour importer.';

  @override
  String importErrorTimeout(int seconds) {
    return 'La requête a expiré après $seconds s. Vérifiez l’URL et votre connexion, puis réessayez.';
  }

  @override
  String get importErrorUnreachable =>
      'Impossible d’atteindre cette URL. Vérifiez l’URL et votre connexion, puis réessayez.';

  @override
  String importErrorHttpStatus(int status) {
    return 'Le serveur a répondu avec HTTP $status.';
  }

  @override
  String get importErrorEmptyResponse => 'L’URL a renvoyé une réponse vide.';

  @override
  String get importErrorCallersBoxEmptyInput =>
      'Saisissez une URL ou un identifiant de danse Caller\'s Box pour importer.';

  @override
  String get importErrorCallersBoxInvalidUrl =>
      'Cela ne ressemble pas à une URL ou un identifiant numérique Caller\'s Box.';

  @override
  String get importErrorCallersBoxMissingId =>
      'Cette URL Caller\'s Box ne contient pas d’identifiant de danse (…dance.php?id=N).';

  @override
  String get importErrorCallersBoxUnsupportedHost =>
      'Ce lien n\'est pas un lien Caller\'s Box pris en charge. Collez un lien d\'ibiblio.org ou de www.ibiblio.org sous /contradance/thecallersbox/, ou saisissez l\'identifiant numérique de la danse.';

  @override
  String get importErrorCallersBoxEmptySearch =>
      'Saisissez un titre ou des figures par phrase pour rechercher sur The Caller\'s Box.';

  @override
  String importErrorSearchTimeout(int seconds) {
    return 'La recherche a expiré après $seconds s. Vérifiez votre connexion, puis réessayez.';
  }

  @override
  String get importErrorCallersBoxUnreachable =>
      'Impossible d’atteindre The Caller\'s Box. Vérifiez votre connexion, puis réessayez.';

  @override
  String importErrorCallersBoxHttpStatus(int status) {
    return 'The Caller\'s Box a répondu avec HTTP $status.';
  }

  @override
  String get importErrorCallersBoxEmptyPage =>
      'The Caller\'s Box a renvoyé une page vide.';

  @override
  String get importErrorCallersBoxNoDance =>
      'The Caller\'s Box n’a renvoyé aucune danse importable.';

  @override
  String get importErrorCallersBoxImportFailed =>
      'Impossible d’importer la danse Caller\'s Box.';

  @override
  String get importErrorContraDbEmptyTitle =>
      'Saisissez un titre pour rechercher dans ContraDB.';

  @override
  String get importErrorContraDbEmptyDanceInput =>
      'Saisissez une URL ou un identifiant de danse ContraDB pour importer.';

  @override
  String get importErrorContraDbInvalidDanceUrl =>
      'Cela ne ressemble pas à une URL ou un identifiant numérique de danse ContraDB.';

  @override
  String get importErrorContraDbMissingDanceId =>
      'Cette URL ContraDB ne contient pas d’identifiant de danse (…/dances/N).';

  @override
  String get importErrorContraDbEmptyProgramInput =>
      'Saisissez une URL ou un identifiant de programme ContraDB pour importer.';

  @override
  String get importErrorContraDbInvalidProgramUrl =>
      'Cela ne ressemble pas à une URL ou un identifiant numérique de programme ContraDB.';

  @override
  String get importErrorContraDbMissingProgramId =>
      'Cette URL ContraDB ne contient pas d’identifiant de programme (…/programs/N).';

  @override
  String get importErrorContraDbInvalidProgramLink =>
      'Cela ne ressemble pas à un lien de programme ContraDB.';

  @override
  String get importErrorContraDbUnsupportedHost =>
      'Ce lien ne provient pas d’un hébergeur ContraDB pris en charge. Collez un lien de contradb.com ou de www.contradb.com, ou saisissez l’identifiant numérique de la danse ou du programme.';

  @override
  String get importErrorContraDbUnreachable =>
      'Impossible d’atteindre ContraDB. Vérifiez votre connexion, puis réessayez.';

  @override
  String importErrorContraDbHttpStatus(int status) {
    return 'ContraDB a répondu avec HTTP $status.';
  }

  @override
  String get importErrorContraDbEmptyResponse =>
      'ContraDB a renvoyé une réponse vide.';

  @override
  String get importErrorContraDbNoDance =>
      'ContraDB n’a renvoyé aucune danse importable.';

  @override
  String get importErrorContraDbImportFailed =>
      'Impossible d’importer la danse ContraDB.';

  @override
  String get importIssueGeneric => 'Cet élément a été importé avec une note.';

  @override
  String get importIssueProgramEmptySlot =>
      'Un emplacement vide dans un programme a été ignoré.';

  @override
  String get importIssueProgramUnresolvedDance =>
      'Un programme référençait une danse non importée ; l\'emplacement a été conservé comme texte de substitution.';

  @override
  String get importIssueProgramUnresolvedVenue =>
      'Un programme référençait un lieu non importé ; le programme a été conservé sans lien vers un lieu.';

  @override
  String get importIssueArchiveReadError =>
      'Une entrée du fichier partagé n\'a pas pu être lue et a été ignorée.';

  @override
  String get importIssueArchiveReadWarning =>
      'Le fichier partagé a signalé un avertissement lors du décodage.';

  @override
  String get importIssueDirectionUnmapped =>
      'Une direction Becket n\'a pas été reconnue ; sens horaire par défaut.';

  @override
  String get importIssueFormationUnclassified =>
      'Une formation n\'a pas pu être reconnue ; conservée comme détail sur « other ».';

  @override
  String get importIssuePhraseStructureUnreadable =>
      'Une structure de phrase n\'a pas pu être lue ; une structure par défaut a été utilisée.';

  @override
  String get importIssueProgressionUnmapped =>
      'Une progression n\'a pas été reconnue ; enregistrée comme « other ».';

  @override
  String get importIssueMetadataOnlyStub =>
      'Cette danse n\'est disponible que sous forme de métadonnées (aucune figure) ; importée comme ébauche.';

  @override
  String importIssueDateAssumedMdy(String field) {
    return 'Une date $field ambiguë a été lue comme mois/jour (ordre américain) ; vérifiez-la si la source utilisait l\'ordre jour d\'abord.';
  }

  @override
  String importIssueDateReducedPrecision(int year, String field) {
    return 'Seule l\'année $year a pu être lue de la date $field ; aucun mois ni jour n\'était présent.';
  }

  @override
  String get importIssueMissingTitle =>
      'La danse n\'avait pas de titre ; un titre de substitution a été utilisé. Modifiez-le avant de valider.';

  @override
  String get importIssueProgramUnparsedDate =>
      'Une date d\'événement n\'a pas pu être lue ; non définie.';

  @override
  String get importIssueRatingOutOfRange =>
      'Une évaluation était hors de l\'échelle 1–5 ; non évaluée.';

  @override
  String get importIssueUnmappedFormation =>
      'Une formation n\'a pas été reconnue ; conservée comme détail en texte libre.';

  @override
  String get importIssueUnmappedLevel =>
      'Un niveau n\'a pas été reconnu ; non spécifié.';

  @override
  String get importIssueUnmappedProgression =>
      'Une progression n\'a pas été reconnue ; simple par défaut.';

  @override
  String get importIssueUnmappedType =>
      'Un type de danse n\'a pas été reconnu ; importé comme contra et conservé dans les notes.';

  @override
  String importIssueUnparsedDate(String field) {
    return 'La date $field n\'a pas pu être lue ; non définie.';
  }

  @override
  String get importIssueUnparsedRating =>
      'Une évaluation n\'a pas pu être lue ; non évaluée.';

  @override
  String get importIssueFiguresUnreadable =>
      'Les figures n\'ont pas pu être lues ; aucune figure importée.';

  @override
  String get importIssueBeatsUnreadable =>
      'Un nombre de temps n\'a pas pu être lu ; 0 utilisé.';

  @override
  String get importIssueNoFiguresTable =>
      'La page n\'avait aucune figure ; importée comme ébauche de métadonnées uniquement.';

  @override
  String get importIssueMoveFallback =>
      'Une figure n\'a pas pu être associée à un mouvement connu ; importée comme personnalisée.';

  @override
  String importIssueMoveFallbackAt(int position) {
    return 'La figure $position n\'a pas pu être associée à un mouvement connu ; importée comme personnalisée.';
  }

  @override
  String get importIssueParamUnmapped =>
      'Un paramètre de figure n\'a pas pu être associé ; une valeur par défaut de la taxonomie a été utilisée.';

  @override
  String importIssueParamValueUnmapped(String param) {
    return 'Le paramètre $param n\'a pas pu être converti ; une valeur par défaut de la taxonomie a été utilisée.';
  }

  @override
  String importIssueParamCountUnmapped(int provided, int mapped) {
    return 'Une figure avait $provided valeurs de paramètre mais seulement $mapped sont associées ; les valeurs en trop ont été ignorées.';
  }

  @override
  String get importIssueRelatedDanceUnresolved =>
      'Un lien vers une danse associée pointait vers une danse non importée ; le lien a été ignoré.';

  @override
  String get importDateFieldComposed => 'composée';

  @override
  String get importDateFieldRevised => 'révisée';

  @override
  String get importRecordErrorDiscover => 'Cet enregistrement est introuvable.';

  @override
  String get importRecordErrorFetch =>
      'Impossible de récupérer cet enregistrement.';

  @override
  String get importRecordErrorParse => 'Impossible de lire cet enregistrement.';

  @override
  String get importRecordErrorDedupe =>
      'Impossible de traiter cet enregistrement.';

  @override
  String get importRecordErrorCommit =>
      'Impossible d\'enregistrer cet enregistrement.';

  @override
  String get importReviewUsrSubtitle =>
      'Choisissez le fichier .USR de Caller\'s Companion pour migrer ses danses et son historique de programme. Rien n’est ajouté à votre collection tant que vous n’avez pas passé en revue et confirmé.';

  @override
  String get importReviewChooseUsr => 'Choisir un fichier .USR…';

  @override
  String importReviewFileReady(int bytes) {
    return 'Fichier prêt ($bytes octets).';
  }

  @override
  String get importReviewGenericSubtitle =>
      'Choisissez un fichier, collez son contenu ou récupérez-le depuis une URL. Rien n’est ajouté à votre collection tant que vous n’avez pas passé en revue et confirmé.';

  @override
  String get importReviewChooseFile => 'Choisir un fichier…';

  @override
  String get importReviewUrlLabel => 'URL ou identifiant de danse';

  @override
  String get importReviewUrlLabelGeneric => 'Importer depuis une URL';

  @override
  String get importReviewUrlHint =>
      'https://www.ibiblio.org/contradance/thecallersbox/dance.php?id=1  · ou · 1';

  @override
  String get importReviewUrlHintGeneric => 'https://…';

  @override
  String get importReviewFetch => 'Récupérer';

  @override
  String get importReviewPasteJson => 'Ou coller le JSON';

  @override
  String get importReviewReviewButton => 'Passer en revue l’import';

  @override
  String importReviewWillImport(int importable, int total) {
    return '$importable sur $total seront importés';
  }

  @override
  String importReviewWillImportPrograms(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count programs',
      one: '1 program',
    );
    return 'Also includes $_temp0.';
  }

  @override
  String get importReviewCouldNotRead => 'Impossible de lire l’import';

  @override
  String get importReviewNoDancesTitle => 'Aucune danse trouvée';

  @override
  String get importReviewNoDancesBody =>
      'Le fichier ne contient aucune danse à importer.';

  @override
  String get importReviewTryAnother => 'Essayer un autre fichier';

  @override
  String get importReviewImported => 'Importé';

  @override
  String importReviewStructured(int structured, int total) {
    return '$structured/$total structurées';
  }

  @override
  String get importReviewCustom => 'Personnalisée';

  @override
  String get importReviewOptionNewDance => 'Nouvelle danse';

  @override
  String get importReviewOptionSkip => 'Ignorer';

  @override
  String importReviewOptionReimport(String title) {
    return 'Ré-importer sur « $title »';
  }

  @override
  String get importReviewOptionDuplicate =>
      'Importer comme nouvelle danse (doublon)';

  @override
  String get importReviewPossibleMatch =>
      'Correspondance possible — choisissez la méthode d’import :';

  @override
  String importReviewOptionLink(String title, int percent) {
    return 'Lier à « $title » ($percent % de correspondance)';
  }

  @override
  String importReviewOverwriteWarning(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count danses existantes seront écrasées',
      one: '1 danse existante sera écrasée',
    );
    return '$_temp0';
  }

  @override
  String importReviewWarningPrefix(String message) {
    return 'Avertissement : $message';
  }

  @override
  String get importReviewComplete => 'Import terminé';

  @override
  String sharedImportSoftCapWarning(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          'Cet import contient $count éléments — plus que prévu pour un partage normal.',
      one:
          'Cet import contient 1 élément — plus que prévu pour un partage normal.',
    );
    return '$_temp0';
  }

  @override
  String sharedImportComplete(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count éléments importés.',
      one: '1 élément importé.',
      zero: 'Import terminé.',
    );
    return '$_temp0';
  }

  @override
  String sharedImportProgramsOnly(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Ce partage contient $count programmes et aucune danse.',
      one: 'Ce partage contient 1 programme et aucune danse.',
    );
    return '$_temp0';
  }

  @override
  String importReviewSummaryCreated(int count) {
    return 'Créés : $count';
  }

  @override
  String importReviewSummaryReimported(int count) {
    return 'Ré-importés : $count';
  }

  @override
  String importReviewSummaryLinked(int count) {
    return 'Liés : $count';
  }

  @override
  String importReviewSummaryDuplicated(int count) {
    return 'Dupliqués : $count';
  }

  @override
  String importReviewSummaryVariation(int count) {
    return 'Importé comme variante : $count';
  }

  @override
  String importReviewSummarySkipped(int count) {
    return 'Ignorés : $count';
  }

  @override
  String importReviewSummaryPrograms(int count) {
    return 'Programmes : $count';
  }

  @override
  String importReviewProgramsUpdated(int count) {
    return '$count mis à jour (ré-importés)';
  }

  @override
  String importReviewProgramNotes(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count note(s) de programme :',
      one: '$count note(s) de programme :',
    );
    return '$_temp0';
  }

  @override
  String importReviewRecordsFailed(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count enregistrement(s) n’ont pas pu être importés :',
      one: '$count enregistrement(s) n’a pas pu être importé :',
    );
    return '$_temp0';
  }

  @override
  String importReviewBatchErrors(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count enregistrement(s) n’ont pas pu être lus (les autres peuvent toujours être importés) :',
      one:
          '$count enregistrement(s) n’a pas pu être lu (les autres peuvent toujours être importés) :',
    );
    return '$_temp0';
  }

  @override
  String get importReviewUntitledProgram => 'Programme sans titre';

  @override
  String get importReviewUndoWithPrograms =>
      'Annuler (supprime les danses et programmes importés)';

  @override
  String get importReviewUndone => 'Import annulé.';

  @override
  String get importReviewEditError =>
      'Impossible d’importer cette danse à modifier.';

  @override
  String get importReviewImportError => 'Impossible de terminer l’import.';

  @override
  String importReviewVariationTitle(String title) {
    return 'Variante de « $title » ?';
  }

  @override
  String importReviewVariationBody(String title) {
    return 'Le titre et le caller de cette danse correspondent à « $title », mais les figures sont différentes. Consultez les différences, puis choisissez comment l\'importer.';
  }

  @override
  String importReviewOptionVariation(String title) {
    return 'Importer comme variante de « $title »';
  }

  @override
  String importReviewOptionSameDance(String title) {
    return 'Même danse que « $title » (lier/mettre à jour)';
  }

  @override
  String importReviewOptionLinkBack(String title) {
    return 'Aussi relier à « $title » comme danse associée';
  }

  @override
  String get importReviewVariationAdded => 'Ajoutées';

  @override
  String get importReviewVariationRemoved => 'Supprimées';

  @override
  String importReviewVariationMoreDifferences(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count différences supplémentaires non affichées',
      one: '1 différence supplémentaire non affichée',
    );
    return '$_temp0';
  }

  @override
  String get danceEditorDetailsSection => 'Détails';

  @override
  String get danceEditorTitleRequiredLabel => 'Titre *';

  @override
  String get danceEditorTitleRequired => 'Un titre est obligatoire';

  @override
  String get danceEditorAuthorsLabel => 'Auteurs';

  @override
  String get danceEditorFormationLabel => 'Formation';

  @override
  String get danceEditorFormationDetailLabel =>
      'Détail de formation (optionnel)';

  @override
  String get danceEditorPhraseStructureLabel => 'Structure de phrase';

  @override
  String get danceEditorPhraseStructureHint =>
      'Vide = standard A1 A2 B1 B2 ; sinon ex. 6*8*2';

  @override
  String get danceEditorFiguresSection => 'Figures';

  @override
  String get danceEditorFiguresHelp =>
      'Saisissez un mouvement (ex. « sw » → swing) et appuyez sur Entrée pour l’ajouter avec les paramètres par défaut ; le texte non reconnu devient une figure personnalisée.';

  @override
  String get danceEditorNotesSection => 'Notes';

  @override
  String get danceEditorCallingNotesLabel => 'Notes d’appel';

  @override
  String get danceEditorHookLabel => 'Accroche';

  @override
  String get danceEditorHookHint =>
      'Une ligne « pourquoi appeler cette danse »';

  @override
  String get danceEditorWalkthroughLabel => 'Déroulé';

  @override
  String get danceEditorWalkthroughHelper =>
      'Description étape par étape de la danse et de ses transitions';

  @override
  String get danceEditorAddWalkthroughStep => 'Ajouter une étape de déroulé';

  @override
  String get danceEditorWalkthroughStepLabel => 'Étape de déroulé (facultatif)';

  @override
  String get danceEditorWalkthroughStepHelper =>
      'Enregistré comme valeur par défaut pour cette figure et réutilisé partout où elle apparaît.';

  @override
  String get danceEditorSnippetDivergenceTitle =>
      'Mettre à jour votre extrait enregistré ?';

  @override
  String get danceEditorSnippetDivergenceBody =>
      'Ce texte diffère de l\'extrait de déroulé enregistré pour cette figure. Utiliser le nouveau texte partout, ou seulement dans cette danse ?';

  @override
  String get danceEditorSnippetUseEverywhere => 'Utiliser partout';

  @override
  String get danceEditorSnippetJustThisDance => 'Seulement cette danse';

  @override
  String get danceEditorFillWalkthroughFromSnippets =>
      'Remplir à partir des extraits';

  @override
  String get danceEditorFillWalkthroughReplaceTitle => 'Remplacer le déroulé ?';

  @override
  String get danceEditorFillWalkthroughReplaceBody =>
      'Cela remplace le déroulé actuel par un texte assemblé à partir de vos extraits de figures.';

  @override
  String get danceEditorFillWalkthroughReplaceConfirm => 'Remplacer';

  @override
  String get danceEditorFillWalkthroughEmpty =>
      'Aucune de ces figures n\'a encore d\'extrait de déroulé enregistré.';

  @override
  String get settingsWalkthroughSnippetsTitle => 'Extraits de déroulé';

  @override
  String get settingsWalkthroughSnippetsSubtitle =>
      'Vos descriptions d\'étapes enregistrées par figure';

  @override
  String get settingsWalkthroughSnippetsHeader =>
      'Extraits de déroulé enregistrés';

  @override
  String get settingsWalkthroughSnippetsDescription =>
      'Ces descriptions d\'étapes par figure préremplissent les déroulés lorsque vous modifiez une danse. En modifier une ici met à jour la valeur par défaut utilisée partout.';

  @override
  String get settingsWalkthroughSnippetsEmpty =>
      'Aucun extrait enregistré pour l\'instant. Ajoutez des descriptions d\'étapes de déroulé en modifiant les figures d\'une danse.';

  @override
  String settingsWalkthroughSnippetsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count extraits',
      one: '1 extrait',
    );
    return '$_temp0';
  }

  @override
  String get settingsWalkthroughSnippetDeleteTitle => 'Supprimer l\'extrait ?';

  @override
  String get settingsWalkthroughSnippetDeleteBody =>
      'Cela supprime la valeur par défaut enregistrée pour cette figure. Les danses conservent le texte de déroulé que vous avez déjà écrit.';

  @override
  String get settingsWalkthroughSnippetEditTitle => 'Modifier l\'extrait';

  @override
  String get danceEditorMoreDetailsTitle => 'Plus de détails';

  @override
  String get danceEditorStatusLabel => 'Statut';

  @override
  String get danceEditorMixedLevelSubtitle =>
      'Couvre toute l’échelle de difficulté';

  @override
  String get danceEditorMixerSubtitle =>
      'Les danseurs changent de partenaire à chaque passage';

  @override
  String get danceEditorComposedLabel => 'Composée';

  @override
  String get danceEditorComposedHelper =>
      'Quand la danse a été composée (année, ou ajoutez mois/jour)';

  @override
  String get danceEditorRevisedLabel => 'Révisée';

  @override
  String get danceEditorRevisedHelper =>
      'Quand la danse a été révisée pour la dernière fois par son auteur';

  @override
  String get danceEditorTagsLabel => 'Tags';

  @override
  String get danceEditorTunesLabel => 'Airs';

  @override
  String get danceEditorLinksLabel => 'Liens';

  @override
  String get danceEditorPublishedSourcesLabel => 'Sources publiées';

  @override
  String get danceEditorRelatedDancesLabel => 'Danses associées';

  @override
  String get danceEditorCustomFieldsLabel => 'Champs personnalisés';

  @override
  String get danceEditorRatingLabel => 'Note';

  @override
  String get danceEditorRatingUnrated => 'non noté';

  @override
  String danceEditorRatingValue(int rating, int max) {
    return '$rating sur $max étoiles';
  }

  @override
  String danceEditorSetRatingTooltip(int rating, int max) {
    return 'Définir la note à $rating sur $max étoiles';
  }

  @override
  String get danceEditorClearRating => 'Effacer la note';

  @override
  String get danceEditorLevelLabel => 'Niveau';

  @override
  String get danceEditorLevelUnspecified => 'Non spécifié';

  @override
  String get danceEditorYearLabel => 'Année';

  @override
  String get danceEditorYearHint => 'ex. 1989';

  @override
  String get danceEditorYearRangeError => '1–9999';

  @override
  String get danceEditorMonthLabel => 'Mois';

  @override
  String get danceEditorDayLabel => 'Jour';

  @override
  String get danceEditorMonthJan => 'Jan';

  @override
  String get danceEditorMonthFeb => 'Fév';

  @override
  String get danceEditorMonthMar => 'Mar';

  @override
  String get danceEditorMonthApr => 'Avr';

  @override
  String get danceEditorMonthMay => 'Mai';

  @override
  String get danceEditorMonthJun => 'Jun';

  @override
  String get danceEditorMonthJul => 'Jul';

  @override
  String get danceEditorMonthAug => 'Aoû';

  @override
  String get danceEditorMonthSep => 'Sep';

  @override
  String get danceEditorMonthOct => 'Oct';

  @override
  String get danceEditorMonthNov => 'Nov';

  @override
  String get danceEditorMonthDec => 'Déc';

  @override
  String get monthFullJanuary => 'Janvier';

  @override
  String get monthFullFebruary => 'Février';

  @override
  String get monthFullMarch => 'Mars';

  @override
  String get monthFullApril => 'Avril';

  @override
  String get monthFullMay => 'Mai';

  @override
  String get monthFullJune => 'Juin';

  @override
  String get monthFullJuly => 'Juillet';

  @override
  String get monthFullAugust => 'Août';

  @override
  String get monthFullSeptember => 'Septembre';

  @override
  String get monthFullOctober => 'Octobre';

  @override
  String get monthFullNovember => 'Novembre';

  @override
  String get monthFullDecember => 'Décembre';

  @override
  String get danceEditorAddTuneHint => 'Ajouter un air suggéré…';

  @override
  String get danceEditorAddTuneTooltip => 'Ajouter un air';

  @override
  String get danceEditorWarningsTitle => 'Avertissements';

  @override
  String validationPhraseBeatMismatch(int actual, int expected) {
    return 'Les figures totalisent $actual temps ; la structure de phrase en attend $expected.';
  }

  @override
  String get validationPhraseInvalid =>
      'Cette structure de phrase n\'est pas valide.';

  @override
  String validationOrphanedAlt(int position) {
    return 'L\'alternative à la position $position n\'a pas d\'emplacement principal précédent.';
  }

  @override
  String validationOrphanedAltNamed(int position, String text) {
    return 'L\'alternative à la position $position (« $text ») n\'a pas d\'emplacement principal précédent.';
  }

  @override
  String validationEmptySubstitution(String term) {
    return 'La substitution pour « $term » est vide.';
  }

  @override
  String validationDialectCollision(
    String source,
    String existing,
    String substitution,
  ) {
    return '« $source » et « $existing » correspondent tous deux à « $substitution » — l\'inversion serait ambiguë.';
  }

  @override
  String get validationGeneric =>
      'Cet élément présente un problème de validation.';

  @override
  String danceEditorDiscouragedTermSemantic(String term) {
    return 'Terme déconseillé : $term';
  }

  @override
  String danceEditorDiscouragedTermText(String term) {
    return 'Déconseillé : $term';
  }

  @override
  String get danceEditorLinkKindSource => 'Source';

  @override
  String get danceEditorLinkKindVideo => 'Vidéo';

  @override
  String get danceEditorLinkKindOther => 'Autre';

  @override
  String get danceEditorUrlLabel => 'URL';

  @override
  String get danceEditorLabelOptional => 'Étiquette (optionnelle)';

  @override
  String get danceEditorRemoveLinkTooltip => 'Supprimer le lien';

  @override
  String get danceEditorAddLink => 'Ajouter un lien';

  @override
  String get danceEditorMissingDance => '(danse manquante)';

  @override
  String get danceEditorNoteOptionalLabel => 'Note (optionnelle)';

  @override
  String get danceEditorRemoveRelatedDanceTooltip =>
      'Supprimer la danse associée';

  @override
  String get danceEditorAddRelatedDance => 'Ajouter une danse associée';

  @override
  String get danceEditorRelatedDanceLabel => 'Danse associée';

  @override
  String get danceEditorTypeToSearchHint => 'Tapez pour rechercher…';

  @override
  String danceEditorEditItemTooltip(String item) {
    return 'Modifier $item';
  }

  @override
  String get danceEditorTypeToAddOrCreateHint => 'Tapez pour ajouter ou créer…';

  @override
  String danceEditorCreateQuotedName(String name) {
    return 'Créer « $name »';
  }

  @override
  String get danceEditorUnknownSource => '(source inconnue)';

  @override
  String get danceEditorPageOptionalLabel => 'Page (optionnelle)';

  @override
  String get danceEditorNumberOptionalLabel => 'Numéro (optionnel)';

  @override
  String get danceEditorCiteSourceHint =>
      'Citer une source : tapez pour ajouter ou créer…';

  @override
  String get danceEditorSaveError => 'Impossible d’enregistrer la danse.';

  @override
  String get danceEditorFallbackDanceTitle => 'Danse';

  @override
  String get danceEditorUnsavedDraftTitle => 'Brouillon non enregistré';

  @override
  String get danceEditorUnsavedDraftMessage =>
      'Vous avez un brouillon non enregistré pour cette danse. Voulez-vous le restaurer ?';

  @override
  String get danceEditorDiscard => 'Abandonner';

  @override
  String get danceEditorRestore => 'Restaurer';

  @override
  String get danceEditorDiscardChangesTitle => 'Abandonner les modifications ?';

  @override
  String get danceEditorDiscardChangesMessage =>
      'Vous avez des modifications non enregistrées dans cette danse.';

  @override
  String get danceEditorKeepEditing => 'Continuer la modification';

  @override
  String get danceEditorNewDanceTitle => 'Nouvelle danse';

  @override
  String get danceEditorEditDanceTitle => 'Modifier la danse';

  @override
  String get danceEditorRedoLabel => 'Rétablir';

  @override
  String get danceEditorUndoShortcutTooltip => 'Annuler (Ctrl+Z)';

  @override
  String get danceEditorRedoShortcutTooltip => 'Rétablir (Ctrl+Shift+Z)';

  @override
  String get danceEditorDeleteDanceTooltip => 'Supprimer la danse';

  @override
  String get danceEditorLoadError => 'Impossible de charger la danse.';

  @override
  String get danceEditorChoreographerDetailsTitle => 'Détails du chorégraphe';

  @override
  String get danceEditorChoreographerDetailsIntro =>
      'Ces détails sont partagés entre toutes les danses créditées à cet auteur. L’e-mail et le lieu sont privés — stockés uniquement sur cet appareil, jamais partagés ni exportés.';

  @override
  String get danceEditorNameRequiredLabel => 'Nom *';

  @override
  String get danceEditorNameRequired => 'Un nom est obligatoire';

  @override
  String get danceEditorWebsiteLabel => 'Site web';

  @override
  String get danceEditorEmailPrivateLabel => 'E-mail (privé)';

  @override
  String get danceEditorLocationPrivateLabel => 'Lieu (privé)';

  @override
  String get danceEditorNotesLabel => 'Notes';

  @override
  String get danceEditorDeceasedLabel => 'Décédé(e)';

  @override
  String get danceEditorSourceDetailsTitle => 'Détails de la source';

  @override
  String get danceEditorSourceDetailsIntro =>
      'Ces détails sont partagés entre toutes les danses qui citent cette source. Les modifier ici met à jour la source partout où elle est référencée.';

  @override
  String get danceEditorSourceAuthorEditorLabel => 'Auteur / éditeur';

  @override
  String get danceEditorEnterWholeNumber => 'Saisissez un entier';

  @override
  String get danceEditorEnterPositiveYear => 'Saisissez une année positive';

  @override
  String danceEditorAddedFigureChooseMove(int count) {
    return 'Figure $count ajoutée. Choisissez un mouvement.';
  }

  @override
  String danceEditorFigurePastedAnnouncement(int position) {
    return 'Figure collée à la position $position.';
  }

  @override
  String danceEditorFigureMovedAnnouncement(int position, int total) {
    return 'Déplacée à la position $position sur $total.';
  }

  @override
  String danceEditorEditingFigureAnnouncement(int position, String name) {
    return 'Modification de la figure $position, $name.';
  }

  @override
  String danceEditorCollapsedFigureAnnouncement(int position) {
    return 'Figure $position réduite.';
  }

  @override
  String get danceEditorTypeFigureAnnouncement =>
      'Saisissez une figure et appuyez sur Entrée pour l’ajouter.';

  @override
  String danceEditorFreeTextFiguresAddedAnnouncement(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count figures ajoutées. Saisissez-en une autre ou appuyez sur Échap pour terminer.',
      one:
          '1 figure ajoutée. Saisissez-en une autre ou appuyez sur Échap pour terminer.',
    );
    return '$_temp0';
  }

  @override
  String danceEditorDeletedFigureAnnouncement(int position) {
    return 'Figure $position supprimée. Annulation disponible.';
  }

  @override
  String danceEditorDuplicatedFigureAnnouncement(int position) {
    return 'Figure $position dupliquée.';
  }

  @override
  String get danceEditorAddFirstFigure => 'Ajouter la première figure';

  @override
  String danceEditorCutBanner(String figure) {
    return '« $figure » est coupée — appuyez sur Coller pour la placer.';
  }

  @override
  String get danceEditorPasteBeforeFirstFigure =>
      'Coller avant la première figure';

  @override
  String danceEditorPasteAfterFigure(String figure) {
    return 'Coller après $figure';
  }

  @override
  String get danceEditorAddFigure => 'Ajouter une figure';

  @override
  String get danceEditorPasteAtEndOfFigureList =>
      'Coller à la fin de la liste des figures';

  @override
  String get danceEditorTypeFigureLabel => 'Saisir une figure';

  @override
  String get danceEditorTypeFigureHelper =>
      'ex. « neighbor balance & swing » ou « 16 circle left 3/4 ». Entrée l’ajoute ; le texte non reconnu est conservé comme figure personnalisée.';

  @override
  String get danceEditorPasteHere => 'Coller ici';

  @override
  String get danceEditorEmptyFigureName => 'Figure vide';

  @override
  String get danceEditorCustomFigureName => 'Figure personnalisée';

  @override
  String get danceEditorEmptyFigureSummary =>
      '(vide — choisissez un mouvement)';

  @override
  String get danceEditorEmptyFigureSemantic =>
      'figure vide, choisissez un mouvement';

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
      other: '$beats temps',
      one: '1 temps',
    );
    String _temp3 = intl.Intl.selectLogic(hasMove, {
      'yes': ', $_temp2',
      'other': '',
    });
    String _temp4 = intl.Intl.selectLogic(hasNote, {
      'yes': ', note : $note',
      'other': '',
    });
    return '$main$_temp0$_temp1$_temp3$_temp4. Figure $position sur $total.';
  }

  @override
  String get danceEditorActivateToEditHint => 'Activer pour modifier';

  @override
  String danceEditorDragToReorderFigure(String figure) {
    return 'Faire glisser pour réorganiser $figure';
  }

  @override
  String danceEditorFigureActionsTooltip(String figure) {
    return 'Actions pour $figure';
  }

  @override
  String get danceEditorMoveUp => 'Déplacer vers le haut';

  @override
  String get danceEditorMoveDown => 'Déplacer vers le bas';

  @override
  String get danceEditorCut => 'Couper';

  @override
  String get danceEditorClearProgression => 'Effacer la progression';

  @override
  String get danceEditorMarkProgression => 'Marquer la progression';

  @override
  String get danceEditorGroupWithNext =>
      'Grouper avec la suivante en simultané';

  @override
  String danceEditorMeanwhileGroupLabel(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Simultané ($count côtés)',
    );
    return '$_temp0';
  }

  @override
  String danceEditorMeanwhileGroupSemantic(int count, int beats) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count figures simultanées',
      one: '1 figure simultanée',
    );
    String _temp1 = intl.Intl.pluralLogic(
      beats,
      locale: localeName,
      other: '$beats temps partagés',
      one: '1 temps partagé',
    );
    return 'Groupe simultané, $_temp0, $_temp1.';
  }

  @override
  String danceEditorMeanwhileSideLabel(int number) {
    return 'Côté $number';
  }

  @override
  String danceEditorMeanwhileSideSemantic(int number, int total) {
    return 'Côté $number sur $total.';
  }

  @override
  String get danceEditorAddMeanwhileSide => 'Ajouter un côté';

  @override
  String get danceEditorRemoveMeanwhileSide => 'Supprimer ce côté';

  @override
  String danceEditorMeanwhileSidesCapReached(int max) {
    return 'Maximum de $max figures simultanées.';
  }

  @override
  String danceEditorUnrecognizedMoveReadOnly(String move) {
    return 'Mouvement non reconnu « $move » — absent de la taxonomie de cette version. Affiché en lecture seule pour préserver ses données ; il sera à nouveau modifiable si le mouvement devient connu. Vous pouvez toujours le réorganiser ou le supprimer.';
  }

  @override
  String get danceEditorFewerOptions => 'Moins d’options';

  @override
  String danceEditorMoreOptions(int count) {
    return 'Plus d’options ($count)';
  }

  @override
  String get danceEditorAddNote => 'Ajouter une note';

  @override
  String get danceEditorBoldTooltip => 'Gras (*texte*)';

  @override
  String get danceEditorUnderlineTooltip => 'Souligné (_texte_)';

  @override
  String get danceEditorCustomFigureTextLabel =>
      'Texte de la figure personnalisée';

  @override
  String get danceEditorLingoStylingHelper =>
      'Noms de mouvements soulignés en pointillés, termes de rôles soulignés, termes déconseillés barrés';

  @override
  String danceEditorBeatTotal(int total, int expected) {
    return 'Total : $total / $expected temps';
  }

  @override
  String danceEditorOverByBeats(int beats) {
    return 'Dépassement de $beats temps';
  }

  @override
  String danceEditorUnderByBeats(int beats) {
    return 'Manque de $beats temps';
  }

  @override
  String get danceEditorLessTooltip => 'Moins';

  @override
  String get danceEditorParamNotStated => 'non précisé';

  @override
  String get danceEditorParamClearTooltip => 'Effacer (non précisé)';

  @override
  String get danceEditorMoreTooltip => 'Plus';

  @override
  String danceEditorTurnCount(num count, String formatted) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$formatted tours',
      one: '$formatted tour',
    );
    return '$_temp0';
  }

  @override
  String get commonBack => 'Retour';

  @override
  String get commonRemove => 'Supprimer';

  @override
  String updateBannerDownloading(String appName, String version) {
    return 'Téléchargement de $appName $version…';
  }

  @override
  String updateBannerDownloadingPct(String appName, String version, int pct) {
    return 'Téléchargement de $appName $version… $pct %';
  }

  @override
  String updateBannerVerifying(String appName, String version) {
    return 'Vérification de $appName $version…';
  }

  @override
  String get updateBannerPreparingInstaller =>
      'Préparation du programme d’installation…';

  @override
  String updateBannerCompletedRevealed(String appName, String version) {
    return '$appName $version téléchargé et vérifié — le programme d’installation a été affiché dans votre gestionnaire de fichiers. Exécutez-le pour terminer la mise à jour.';
  }

  @override
  String updateBannerCompletedManual(String appName, String version) {
    return '$appName $version téléchargé — suivez le programme d’installation pour terminer la mise à jour.';
  }

  @override
  String get updateBannerDownloadFailed =>
      'Impossible de télécharger la mise à jour.';

  @override
  String updateBannerAvailable(String appName, String version) {
    return 'Une nouvelle version de $appName ($version) est disponible.';
  }

  @override
  String get updateBannerViewRelease => 'Voir la version';

  @override
  String get updateBannerDismiss => 'Ignorer';

  @override
  String get updateBannerDownloadInstall => 'Télécharger et installer';

  @override
  String get commandPaletteBarrierLabel => 'Recherche globale';

  @override
  String get commandPaletteSearchHint =>
      'Rechercher des danses et des programmes…';

  @override
  String get commandPaletteProgramSubtitle => 'Programme';

  @override
  String get commandPaletteEmptyInitial => 'Rien à rechercher pour l’instant.';

  @override
  String get commandPaletteNoMatches => 'Aucun résultat pour cette recherche.';

  @override
  String get commandPaletteGroupDances => 'Danses';

  @override
  String get commandPaletteGroupPrograms => 'Programmes';

  @override
  String get collectionPickerSearchLabel => 'Trouver une danse à ajouter';

  @override
  String collectionPickerFilters(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Filtres ($count actifs)',
      zero: 'Filtres',
    );
    return '$_temp0';
  }

  @override
  String collectionPickerByPhrase(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Par phrase ($count actif(s))',
      zero: 'Par phrase',
    );
    return '$_temp0';
  }

  @override
  String get collectionPickerAdvanced => 'Avancé';

  @override
  String get collectionPickerUseAdvancedQuery =>
      'Utiliser la recherche avancée';

  @override
  String get collectionPickerAdvancedQueryHelp =>
      'Combinez figures et séquences avec des groupes tout / l’un / aucun.';

  @override
  String collectionPickerAddSemantic(String title) {
    return 'Ajouter $title au programme';
  }

  @override
  String collectionPickerAddTooltip(String title) {
    return 'Ajouter $title';
  }

  @override
  String collectionPickerAddedTooltip(String title) {
    return '$title ajoutée';
  }

  @override
  String collectionPickerInProgramSemantic(String title) {
    return '$title est déjà dans le programme';
  }

  @override
  String collectionPickerInProgramCountSemantic(String title, int count) {
    return '$title est $count fois dans le programme';
  }

  @override
  String get userGuideTitle => 'Guide d’utilisation';

  @override
  String userGuideMissing(String label) {
    return 'Le guide « $label » n’est pas encore disponible.';
  }

  @override
  String get userGuideLoadError =>
      'Impossible de charger le guide d’utilisation.';

  @override
  String get userGuideOpenOnline => 'Ouvrir le guide en ligne';

  @override
  String get shorthandMappingsTitle => 'Abréviations de figures';

  @override
  String get shorthandMappingsIntro =>
      'Les abréviations vous permettent de saisir un jeton court lors d’une saisie en texte libre et de le développer en une ou plusieurs figures que vous avez configurées ici.';

  @override
  String get shorthandMappingsNew => 'Nouvelle abréviation';

  @override
  String get shorthandMappingsEmpty => 'Aucune abréviation pour l’instant.';

  @override
  String get shorthandMappingsDeleteTitle => 'Supprimer l’abréviation ?';

  @override
  String shorthandMappingsDeleteBody(String token) {
    return '« $token » sera définitivement supprimé.';
  }

  @override
  String get shorthandMappingsActionsTooltip => 'Actions de l’abréviation';

  @override
  String get shorthandEditorTitleNew => 'Nouvelle abréviation';

  @override
  String get shorthandEditorTitleEdit => 'Modifier l’abréviation';

  @override
  String get shorthandEditorTokenLabel => 'Abréviation';

  @override
  String get shorthandEditorTokenHelper =>
      'Saisissez cette ligne exacte lors d’une saisie en texte libre pour insérer les figures ci-dessous. Correspondance insensible à la casse.';

  @override
  String get shorthandEditorExpandsTo => 'Se développe en';

  @override
  String get shorthandEditorExpandsToHelp =>
      'La ou les figure(s) que cette abréviation insère, dans l’ordre. Construite exactement comme une figure normale, donc les paramètres et la validation sont les mêmes.';

  @override
  String get shorthandEditorErrorEmpty => 'Saisissez un jeton d’abréviation.';

  @override
  String shorthandEditorErrorTooLong(int max) {
    return 'L’abréviation est trop longue (max $max caractères).';
  }

  @override
  String shorthandEditorErrorDuplicate(String token) {
    return 'Une autre abréviation utilise déjà « $token » (les abréviations sont insensibles à la casse).';
  }

  @override
  String get shorthandEditorErrorNoFigures =>
      'Ajoutez au moins une figure que cette abréviation développera.';

  @override
  String get importShorthandSeedTitle => 'Créer des abréviations de figures';

  @override
  String get importShorthandSeedIntro =>
      'Les boutons d’appel de votre fichier Caller\'s Companion peuvent devenir des abréviations de figures. Choisissez ceux que vous voulez ; chacun se développe en les figures affichées. Rien n’est ajouté avant votre confirmation, et vos abréviations existantes ne sont jamais écrasées.';

  @override
  String get importShorthandSeedAvailableHeader => 'Depuis vos boutons d’appel';

  @override
  String get importShorthandSeedUsePrimary => 'Primaire';

  @override
  String get importShorthandSeedUseAlt => 'Alternative';

  @override
  String get importShorthandSeedConflictHeader => 'Déjà définie — ignorée';

  @override
  String importShorthandSeedConflictNote(String token) {
    return 'Une abréviation nommée « $token » existe déjà, donc ce bouton a été laissé tel quel.';
  }

  @override
  String get importShorthandSeedSkip => 'Ignorer';

  @override
  String importShorthandSeedConfirm(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'Créer $count abréviations',
      one: 'Créer 1 abréviation',
      zero: 'Créer des abréviations',
    );
    return '$_temp0';
  }

  @override
  String importShorthandSeedComplete(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count abréviations créées',
      one: '1 abréviation créée',
    );
    return '$_temp0';
  }

  @override
  String get themeEditorTitle => 'Modifier le thème';

  @override
  String get themeEditorNameLabel => 'Nom du thème';

  @override
  String get themeEditorContrastAllPass =>
      'Toutes les paires vérifiées satisfont le contraste WCAG AA.';

  @override
  String themeEditorContrastFailing(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other:
          '$count paires de contraste inférieures au WCAG AA. Vous pouvez quand même enregistrer, mais certains textes pourraient être difficiles à lire.',
      one:
          '1 paire de contraste inférieure au WCAG AA. Vous pouvez quand même enregistrer, mais certains textes pourraient être difficiles à lire.',
    );
    return '$_temp0';
  }

  @override
  String themeEditorRatioPass(String ratio) {
    return '$ratio:1 AA';
  }

  @override
  String themeEditorRatioFail(String ratio) {
    return '$ratio:1 échec';
  }

  @override
  String get themeEditorPreviewHeading => 'Aa Aperçu';

  @override
  String get themeEditorBodySample => 'Exemple de texte courant';

  @override
  String get themeEditorSwatchPrimary => 'Primaire';

  @override
  String get themeEditorSwatchSecondary => 'Secondaire';

  @override
  String get themeEditorSwatchTertiary => 'Tertiaire';

  @override
  String get themeEditorSwatchError => 'Erreur';

  @override
  String get reparseConfirmTitle =>
      'Mettre à niveau les figures personnalisées ?';

  @override
  String reparseConfirmBody(int figureCount, int danceCount) {
    String _temp0 = intl.Intl.pluralLogic(
      figureCount,
      locale: localeName,
      other: '$figureCount figures',
      one: '1 figure',
    );
    String _temp1 = intl.Intl.pluralLogic(
      danceCount,
      locale: localeName,
      other: '$danceCount danses',
      one: '1 danse',
    );
    return 'Cette action va réanalyser $_temp0 dans $_temp1. Vos tags, notes, évaluations et tout le reste sur chaque danse sont conservés exactement tels quels. Seules les figures reconnaissant désormais un mouvement connu sont remplacées.';
  }

  @override
  String get reparseConfirmUpgrade => 'Mettre à niveau';

  @override
  String get reparseFailed =>
      'Impossible de mettre à niveau les figures. Veuillez réessayer.';

  @override
  String get reparseNothingUpgradedSnack => 'Rien à mettre à niveau.';

  @override
  String reparseUpgradedSnack(int danceCount) {
    String _temp0 = intl.Intl.pluralLogic(
      danceCount,
      locale: localeName,
      other: '$danceCount danses',
      one: '1 danse',
    );
    return 'Figures personnalisées mises à niveau dans $_temp0.';
  }

  @override
  String get reparseScreenTitle => 'Revérifier les figures personnalisées';

  @override
  String reparseIntro(int figureCount, int danceCount) {
    String _temp0 = intl.Intl.pluralLogic(
      figureCount,
      locale: localeName,
      other: '$figureCount figures',
      one: '1 figure',
    );
    String _temp1 = intl.Intl.pluralLogic(
      danceCount,
      locale: localeName,
      other: '$danceCount danses',
      one: '1 danse',
    );
    return 'L’analyse améliorée des figures peut mettre à niveau $_temp0 dans $_temp1. Passez en revue ci-dessous, puis confirmez — rien ne change tant que vous ne le faites pas, et tous vos tags, évaluations et notes sont préservés.';
  }

  @override
  String reparsePreviewCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count figures',
      one: '1 figure',
    );
    return '$_temp0 à mettre à niveau';
  }

  @override
  String reparseUpgradeButton(int danceCount) {
    String _temp0 = intl.Intl.pluralLogic(
      danceCount,
      locale: localeName,
      other: '$danceCount danses',
      one: '1 danse',
    );
    return 'Mettre à niveau $_temp0';
  }

  @override
  String get reparseEmptyTitle => 'Rien à mettre à niveau';

  @override
  String get reparseEmptyBody =>
      'Aucune de vos figures personnalisées issues d’imports ne peut être reconnue comme mouvement connu pour l’instant. Revenez après une prochaine mise à jour améliorant l’analyse des figures.';

  @override
  String get reparseErrorTitle => 'Impossible de vérifier vos figures';

  @override
  String get reparseErrorBody =>
      'Une erreur s’est produite lors de l’analyse de votre collection. Rien n’a été modifié. Vous pouvez réessayer.';

  @override
  String get customFieldsDeleteTitle => 'Supprimer le champ personnalisé';

  @override
  String customFieldsDeleteBody(String label) {
    return 'Supprimer « $label » ? Cette action est irréversible.';
  }

  @override
  String customFieldsDeleteInUse(String label, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count danses',
      one: '1 danse',
    );
    return 'Impossible de supprimer « $label » : encore utilisé par $_temp0. Supprimez d’abord la valeur de toutes les danses.';
  }

  @override
  String customFieldsDeleteInUseUnknown(String label) {
    return 'Impossible de supprimer « $label » : encore utilisé par certaines danses. Supprimez d’abord la valeur de toutes les danses.';
  }

  @override
  String get customFieldsTitle => 'Champs personnalisés';

  @override
  String get customFieldsNewField => 'Nouveau champ';

  @override
  String get customFieldsLoadError =>
      'Impossible de charger les champs personnalisés.';

  @override
  String get customFieldsEmpty =>
      'Aucun champ personnalisé pour l’instant.\nAppuyez sur + pour en définir un.';

  @override
  String get customFieldsFlagInList => 'Dans la liste';

  @override
  String get customFieldsSearchable => 'Filtrable';

  @override
  String get customFieldsTypeText => 'Texte';

  @override
  String get customFieldsTypeNumber => 'Nombre';

  @override
  String get customFieldsTypeBoolean => 'Booléen';

  @override
  String get customFieldsTypeChoice => 'Choix';

  @override
  String get customFieldsValidatorMinChoice => 'Ajoutez au moins un choix';

  @override
  String customFieldsRemoveValueError(String value) {
    return 'Impossible de supprimer « $value » : défini sur au moins une danse.';
  }

  @override
  String get customFieldsEditorNewTitle => 'Nouveau champ personnalisé';

  @override
  String get customFieldsEditorEditTitle => 'Modifier le champ personnalisé';

  @override
  String get customFieldsLabelLabel => 'Étiquette *';

  @override
  String get customFieldsLabelRequired => 'Une étiquette est obligatoire';

  @override
  String get customFieldsKeyLabel => 'Clé *';

  @override
  String get customFieldsKeyHelper =>
      'Clé machine stable (lettres, chiffres, tirets bas ; doit commencer par une lettre ou un tiret bas)';

  @override
  String get customFieldsKeyLocked =>
      'Clé verrouillée — le champ est utilisé sur des danses';

  @override
  String get customFieldsKeyRequired => 'Une clé est obligatoire';

  @override
  String get customFieldsKeyInvalid =>
      'La clé doit commencer par une lettre ou un tiret bas et ne contenir que des lettres, chiffres et tirets bas';

  @override
  String get customFieldsTypeFieldLabel => 'Type';

  @override
  String get customFieldsTypeLocked =>
      'Type verrouillé — le champ a des valeurs sur des danses';

  @override
  String get customFieldsShowInList => 'Afficher dans la liste';

  @override
  String get customFieldsShowInListSubtitle =>
      'Afficher la valeur de ce champ dans la tuile de la liste des danses';

  @override
  String get customFieldsSearchableSubtitle =>
      'Exposer ce champ comme filtre dans le panneau de recherche';

  @override
  String get customFieldsChoicesLabel => 'Choix *';

  @override
  String get customFieldsChoiceInUseTooltip =>
      'Utilisé — ne peut pas être supprimé';

  @override
  String get customFieldsNewChoiceHint => 'Nouveau choix…';

  @override
  String get customFieldsAddChoiceTooltip => 'Ajouter un choix';

  @override
  String get customFieldsChoiceDuplicate => 'Cette option existe déjà.';

  @override
  String get customFieldsChoiceEmpty => 'Saisissez une option.';

  @override
  String customFieldsAddOptionTooltip(String label) {
    return 'Ajouter une option à $label';
  }

  @override
  String customFieldsAddOptionTitle(String label) {
    return 'Ajouter une option à $label';
  }

  @override
  String get customFieldsShareable => 'Inclure lors du partage';

  @override
  String get customFieldsShareableSubtitle =>
      'Les valeurs de ce champ accompagnent votre collection lorsque vous l’exportez ou la partagez';

  @override
  String get customFieldsSharingNoticeTitle =>
      'Les champs personnalisés accompagnent votre collection';

  @override
  String get customFieldsSharingNoticeBody =>
      'Le contenu de tout champ personnalisé que vous créez est inclus lorsque vous exportez ou partagez votre collection. Pour garder un champ privé, désactivez « Inclure lors du partage » dans les paramètres de ce champ.';

  @override
  String get customFieldsSharingNoticeOk => 'Compris';

  @override
  String dialectEditorTitle(String name) {
    return 'Modifier $name';
  }

  @override
  String get dialectEditorSectionRoleTerms => 'Termes de rôles';

  @override
  String get dialectEditorSectionMoveSubs => 'Substitutions de mouvements';

  @override
  String get dialectEditorSectionDancerSubs => 'Substitutions de danseurs';

  @override
  String get dialectEditorSectionDiscouraged => 'Termes déconseillés';

  @override
  String get dialectEditorSectionPreview => 'Aperçu';

  @override
  String get dialectEditorRole1 => 'Rôle 1';

  @override
  String get dialectEditorRole2 => 'Rôle 2';

  @override
  String get dialectEditorRolesHelp =>
      'Laissez un rôle vide pour utiliser le terme canonique. Le pluriel est dérivé s’il est omis.';

  @override
  String get dialectEditorSingular => 'Singulier';

  @override
  String get dialectEditorPlural => 'Pluriel';

  @override
  String get dialectEditorMoveSubsAdd =>
      'Ajouter des substitutions de mouvements';

  @override
  String dialectEditorMoveSubsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count substitutions de mouvements',
      one: '1 substitution de mouvement',
    );
    return '$_temp0';
  }

  @override
  String get dialectEditorMoveSubHint =>
      'substitution (utilisez %S pour la latéralité)';

  @override
  String get dialectEditorAddMove => 'Ajouter un mouvement…';

  @override
  String get dialectEditorDancerSubsAdd =>
      'Ajouter des substitutions de danseurs';

  @override
  String dialectEditorDancerSubsCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count substitutions de danseurs',
      one: '1 substitution de danseur',
    );
    return '$_temp0';
  }

  @override
  String get dialectEditorDancerSubHint => 'substitution';

  @override
  String get dialectEditorAddDancerTerm => 'Ajouter un terme de danseur…';

  @override
  String get dialectEditorDiscouragedHelp =>
      'Termes que l’éditeur de saisie signale (barrés) — jamais bloqués.';

  @override
  String get dialectEditorDiscouragedEmpty => 'Aucun terme déconseillé.';

  @override
  String get dialectEditorAddTermLabel => 'Ajouter un terme';

  @override
  String get dialectEditorAddTermTooltip => 'Ajouter le terme';

  @override
  String get dialectEditorRestoreDefaults => 'Restaurer les valeurs par défaut';

  @override
  String get dialectEditorPreviewHelp =>
      'Exemples de figures rendus avec ce dialecte. Mis à jour pendant la modification.';

  @override
  String get recentlyDeletedTitle => 'Récemment supprimées';

  @override
  String get recentlyDeletedDeleteTitle => 'Supprimer définitivement ?';

  @override
  String recentlyDeletedDeleteBody(String title) {
    return '« $title » sera supprimé immédiatement et ne pourra pas être récupéré.';
  }

  @override
  String get recentlyDeletedDeleteConfirm => 'Supprimer définitivement';

  @override
  String recentlyDeletedDeletedSnack(String title) {
    return '« $title » définitivement supprimé.';
  }

  @override
  String get recentlyDeletedRestore => 'Restaurer';

  @override
  String get recentlyDeletedPurgeKept =>
      'Conservé jusqu’à ce que vous le supprimiez';

  @override
  String recentlyDeletedPurgeCountdown(int days) {
    String _temp0 = intl.Intl.pluralLogic(
      days,
      locale: localeName,
      other: '$days jours',
      one: '1 jour',
    );
    return 'Suppression automatique dans $_temp0';
  }

  @override
  String get recentlyDeletedPurgeScheduled => 'Suppression planifiée';

  @override
  String get recentlyDeletedLoadingDances =>
      'Chargement des danses récemment supprimées';

  @override
  String get recentlyDeletedLoadingPrograms =>
      'Chargement des programmes récemment supprimés';

  @override
  String get recentlyDeletedEmptyDancesKept =>
      'La corbeille est vide. Les danses supprimées sont conservées ici jusqu’à ce que vous les supprimiez.';

  @override
  String recentlyDeletedEmptyDancesRetention(int days) {
    return 'La corbeille est vide. Les danses supprimées apparaissent ici pendant $days jours avant d’être supprimées.';
  }

  @override
  String recentlyDeletedEmptyProgramsRetention(int days) {
    return 'La corbeille est vide. Les programmes supprimés apparaissent ici pendant $days jours avant d’être supprimés.';
  }

  @override
  String recentlyDeletedRestoredDance(String title) {
    return '« $title » restauré dans votre collection.';
  }

  @override
  String recentlyDeletedRestoredProgram(String title) {
    return '« $title » restauré.';
  }

  @override
  String get venueNew => 'Nouveau lieu';

  @override
  String get venueLoadError => 'Impossible de charger les lieux.';

  @override
  String get venueManagerTitle => 'Lieux';

  @override
  String get venueManagerSearchHint => 'Rechercher des lieux…';

  @override
  String get venueManagerClearSearchTooltip => 'Effacer la recherche';

  @override
  String get venueManagerEmpty =>
      'Aucun lieu pour l’instant. Ajoutez-en un avec le bouton ci-dessous, ou depuis un programme lorsque les lieux réutilisables sont activés.';

  @override
  String get venueManagerNoMatches =>
      'Aucun lieu ne correspond à votre recherche.';

  @override
  String get venueManagerDeleteTitle => 'Supprimer le lieu ?';

  @override
  String venueManagerDeleteBody(String name) {
    return 'Supprimer définitivement « $name » ? Cette action est irréversible.';
  }

  @override
  String venueManagerDeletedSnack(String name) {
    return '« $name » supprimé';
  }

  @override
  String venueManagerDeleteBlocked(String name) {
    return 'Impossible de supprimer « $name » tant qu’il est encore lié à un programme. Changez ou supprimez d’abord le lieu sur ces programmes.';
  }

  @override
  String venueManagerDeleteTooltip(String name) {
    return 'Supprimer $name';
  }

  @override
  String get venueEditTitle => 'Modifier le lieu';

  @override
  String get venueEditorSharedNote =>
      'Un lieu est partagé entre tous les programmes qui y ont lieu ; les modifications de son adresse, contacts ou calendrier apparaissent sur tous.';

  @override
  String get venueEditorNameLabel => 'Nom *';

  @override
  String get venueEditorNameRequired => 'Un nom est obligatoire';

  @override
  String get venueEditorWebsiteLabel => 'Site web';

  @override
  String get venueEditorSponsorLabel => 'Sponsor / organisation organisatrice';

  @override
  String get venueEditorAddressSection => 'Adresse';

  @override
  String get venueEditorAddress1Label => 'Ligne d’adresse 1';

  @override
  String get venueEditorAddress2Label => 'Ligne d’adresse 2';

  @override
  String get venueEditorCityLabel => 'Ville';

  @override
  String get venueEditorStateLabel => 'État / province';

  @override
  String get venueEditorCountryLabel => 'Pays';

  @override
  String get venueEditorPostalLabel => 'Code postal';

  @override
  String get venueEditorPlus4Label => 'ZIP+4';

  @override
  String get venueEditorScheduleSection => 'Calendrier';

  @override
  String get venueEditorEventNameLabel => 'Nom de l’événement';

  @override
  String get venueEditorTimeLabel => 'Heure';

  @override
  String get venueEditorScheduleLabel => 'Calendrier (ex. « 2e samedis »)';

  @override
  String get venueEditorPriceLabel => 'Tarif';

  @override
  String get venueEditorContactsSection => 'Contacts';

  @override
  String get venueEditorContact1NameLabel => 'Nom du contact 1';

  @override
  String get venueEditorContact1PhoneLabel => 'Téléphone du contact 1';

  @override
  String get venueEditorContact1EmailLabel => 'E-mail du contact 1';

  @override
  String get venueEditorContact2NameLabel => 'Nom du contact 2';

  @override
  String get venueEditorContact2PhoneLabel => 'Téléphone du contact 2';

  @override
  String get venueEditorContact2EmailLabel => 'E-mail du contact 2';

  @override
  String get venueEditorNotesSection => 'Notes';

  @override
  String get venuePickerLoading => 'Chargement des lieux…';

  @override
  String get venuePickerUnlinkTooltip => 'Dissocier le lieu';

  @override
  String get venuePickerUnresolvedTitle => 'Lieu lié introuvable';

  @override
  String get venuePickerUnresolvedSubtitle => 'Il a peut-être été supprimé.';

  @override
  String get venuePickerClearLinkTooltip => 'Effacer le lien';

  @override
  String get venuePickerSearchHint => 'Rechercher ou ajouter un lieu…';

  @override
  String get venuePickerChangeHint => 'Changer de lieu…';

  @override
  String venuePickerCreateOption(String name) {
    return 'Ajouter un nouveau lieu « $name »';
  }
}
