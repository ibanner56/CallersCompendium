import '../../l10n/app_localizations.dart';
import 'app_theme_scope.dart';
import 'custom_theme.dart';

/// Localized presentation of the theme gallery and the custom-theme editor.
///
/// [AppThemeGroup], [AppThemeSelection] and [CustomThemeRoles] are plain data
/// (the selections are persisted by enum name and the role keys are the
/// custom-theme JSON contract), so their English `label` fields are only a
/// stable fallback and the gallery's sort key. Everything a user reads or a
/// screen reader announces goes through these resolvers instead, mirroring
/// `danceLevelLabel` and `danceExportLabels`.
///
/// Brand palette names (Catppuccin, Nord, Dracula, …) are proper nouns and are
/// returned literally; only the generic built-in names are translated. A
/// user-authored custom theme name is user data and never passes through here.

/// Section heading for [group] in the theme gallery.
String appThemeGroupLabel(AppLocalizations l10n, AppThemeGroup group) =>
    switch (group) {
      AppThemeGroup.system => l10n.appThemeGroupSystem,
      AppThemeGroup.defaultHearth => l10n.appThemeGroupDefault,
      AppThemeGroup.light => l10n.appThemeGroupLight,
      AppThemeGroup.dark => l10n.appThemeGroupDark,
    };

/// Visible name of [selection] on its gallery card.
String appThemeLabel(AppLocalizations l10n, AppThemeSelection selection) =>
    switch (selection) {
      AppThemeSelection.system => l10n.appThemeLabelSystem,
      AppThemeSelection.light => l10n.appThemeLabelLight,
      AppThemeSelection.dark => l10n.appThemeLabelDark,
      AppThemeSelection.softDark => l10n.appThemeLabelSoftDark,
      AppThemeSelection.highContrast => l10n.appThemeLabelHighContrast,
      _ => selection.label,
    };

/// One-line description of [selection]. Not shown on screen: it is the
/// second half of the card's screen-reader label.
String appThemeDescription(
  AppLocalizations l10n,
  AppThemeSelection selection,
) => switch (selection) {
  AppThemeSelection.system => l10n.appThemeDescriptionSystem,
  AppThemeSelection.light => l10n.appThemeDescriptionLight,
  AppThemeSelection.dark => l10n.appThemeDescriptionDark,
  AppThemeSelection.softDark => l10n.appThemeDescriptionSoftDark,
  AppThemeSelection.highContrast => l10n.appThemeDescriptionHighContrast,
  AppThemeSelection.blulocoLight => l10n.appThemeDescriptionBlulocoLight,
  AppThemeSelection.oneDarkPro => l10n.appThemeDescriptionOneDarkPro,
  AppThemeSelection.monokai => l10n.appThemeDescriptionMonokai,
  AppThemeSelection.noctis => l10n.appThemeDescriptionNoctis,
  AppThemeSelection.githubLight => l10n.appThemeDescriptionGithubLight,
  AppThemeSelection.catppuccinLatte => l10n.appThemeDescriptionCatppuccinLatte,
  AppThemeSelection.gruvboxLight => l10n.appThemeDescriptionGruvboxLight,
  AppThemeSelection.everforestLight => l10n.appThemeDescriptionEverforestLight,
  AppThemeSelection.rosePineDawn => l10n.appThemeDescriptionRosePineDawn,
  AppThemeSelection.ayuLight => l10n.appThemeDescriptionAyuLight,
  AppThemeSelection.tokyoNightLight => l10n.appThemeDescriptionTokyoNightLight,
  AppThemeSelection.nordLight => l10n.appThemeDescriptionNordLight,
  AppThemeSelection.kanagawaLotus => l10n.appThemeDescriptionKanagawaLotus,
  AppThemeSelection.dracula => l10n.appThemeDescriptionDracula,
  AppThemeSelection.nord => l10n.appThemeDescriptionNord,
  AppThemeSelection.tokyoNight => l10n.appThemeDescriptionTokyoNight,
  AppThemeSelection.gruvboxDark => l10n.appThemeDescriptionGruvboxDark,
  AppThemeSelection.catppuccinMocha => l10n.appThemeDescriptionCatppuccinMocha,
  AppThemeSelection.githubDark => l10n.appThemeDescriptionGithubDark,
  AppThemeSelection.everforestDark => l10n.appThemeDescriptionEverforestDark,
  AppThemeSelection.rosePine => l10n.appThemeDescriptionRosePine,
  AppThemeSelection.ayuMirage => l10n.appThemeDescriptionAyuMirage,
  AppThemeSelection.cutiePro => l10n.appThemeDescriptionCutiePro,
  AppThemeSelection.pinkAsHeck => l10n.appThemeDescriptionPinkAsHeck,
  AppThemeSelection.vitesseLight => l10n.appThemeDescriptionVitesseLight,
  AppThemeSelection.zenburn => l10n.appThemeDescriptionZenburn,
  AppThemeSelection.shadesOfPurple => l10n.appThemeDescriptionShadesOfPurple,
  AppThemeSelection.catppuccinFrappe =>
    l10n.appThemeDescriptionCatppuccinFrappe,
  AppThemeSelection.synthwave84 => l10n.appThemeDescriptionSynthwave84,
  AppThemeSelection.noctisLilac => l10n.appThemeDescriptionNoctisLilac,
};

/// Heading of [group] in the custom-theme editor. Resolved by the group's
/// stable English [RoleGroup.label]; an unknown group falls back to it.
String themeEditorGroupLabel(AppLocalizations l10n, RoleGroup group) =>
    switch (group.label) {
      'Primary' => l10n.themeEditorGroupPrimary,
      'Secondary' => l10n.themeEditorGroupSecondary,
      'Tertiary' => l10n.themeEditorGroupTertiary,
      'Error' => l10n.themeEditorGroupError,
      'Surface & text' => l10n.themeEditorGroupSurfaceText,
      'Surface containers' => l10n.themeEditorGroupSurfaceContainers,
      'Outline & effects' => l10n.themeEditorGroupOutlineEffects,
      _ => group.label,
    };

/// Label of [role] in the custom-theme editor, resolved by its JSON
/// [ColorRole.key]; an unknown key falls back to the English [ColorRole.label].
String themeEditorRoleLabel(AppLocalizations l10n, ColorRole role) =>
    switch (role.key) {
      'primary' => l10n.themeEditorRolePrimary,
      'onPrimary' => l10n.themeEditorRoleOnPrimary,
      'primaryContainer' => l10n.themeEditorRolePrimaryContainer,
      'onPrimaryContainer' => l10n.themeEditorRoleOnPrimaryContainer,
      'secondary' => l10n.themeEditorRoleSecondary,
      'onSecondary' => l10n.themeEditorRoleOnSecondary,
      'secondaryContainer' => l10n.themeEditorRoleSecondaryContainer,
      'onSecondaryContainer' => l10n.themeEditorRoleOnSecondaryContainer,
      'tertiary' => l10n.themeEditorRoleTertiary,
      'onTertiary' => l10n.themeEditorRoleOnTertiary,
      'tertiaryContainer' => l10n.themeEditorRoleTertiaryContainer,
      'onTertiaryContainer' => l10n.themeEditorRoleOnTertiaryContainer,
      'error' => l10n.themeEditorRoleError,
      'onError' => l10n.themeEditorRoleOnError,
      'errorContainer' => l10n.themeEditorRoleErrorContainer,
      'onErrorContainer' => l10n.themeEditorRoleOnErrorContainer,
      'surface' => l10n.themeEditorRoleSurface,
      'onSurface' => l10n.themeEditorRoleOnSurface,
      'onSurfaceVariant' => l10n.themeEditorRoleOnSurfaceVariant,
      'inverseSurface' => l10n.themeEditorRoleInverseSurface,
      'onInverseSurface' => l10n.themeEditorRoleOnInverseSurface,
      'inversePrimary' => l10n.themeEditorRoleInversePrimary,
      'surfaceContainerLowest' => l10n.themeEditorRoleSurfaceContainerLowest,
      'surfaceContainerLow' => l10n.themeEditorRoleSurfaceContainerLow,
      'surfaceContainer' => l10n.themeEditorRoleSurfaceContainer,
      'surfaceContainerHigh' => l10n.themeEditorRoleSurfaceContainerHigh,
      'surfaceContainerHighest' => l10n.themeEditorRoleSurfaceContainerHighest,
      'outline' => l10n.themeEditorRoleOutline,
      'outlineVariant' => l10n.themeEditorRoleOutlineVariant,
      'surfaceTint' => l10n.themeEditorRoleSurfaceTint,
      'shadow' => l10n.themeEditorRoleShadow,
      'scrim' => l10n.themeEditorRoleScrim,
      _ => role.label,
    };

/// Label of the contrast badge for [pair], resolved by its (unique)
/// [ContrastPair.foreground] role; an unknown pair falls back to the English
/// [ContrastPair.label].
String themeEditorPairLabel(AppLocalizations l10n, ContrastPair pair) =>
    switch (pair.foreground) {
      'onPrimary' => l10n.themeEditorPairOnPrimary,
      'onPrimaryContainer' => l10n.themeEditorPairOnPrimaryContainer,
      'onSecondary' => l10n.themeEditorPairOnSecondary,
      'onSecondaryContainer' => l10n.themeEditorPairOnSecondaryContainer,
      'onTertiary' => l10n.themeEditorPairOnTertiary,
      'onTertiaryContainer' => l10n.themeEditorPairOnTertiaryContainer,
      'onError' => l10n.themeEditorPairOnError,
      'onErrorContainer' => l10n.themeEditorPairOnErrorContainer,
      'onSurface' => l10n.themeEditorPairOnSurface,
      'onSurfaceVariant' => l10n.themeEditorPairOnSurfaceVariant,
      'onInverseSurface' => l10n.themeEditorPairOnInverseSurface,
      'outline' => l10n.themeEditorPairOutline,
      _ => pair.label,
    };
