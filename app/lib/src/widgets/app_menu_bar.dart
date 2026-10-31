import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/app_localizations.dart';
import 'app_shortcuts.dart';

/// The macOS menu bar (PLAT-8): the app menu with **Settings…**, a File menu
/// with **New Dance**, **Import Dances…** and **Close**, View with the system's
/// full-screen item, Window, and Help with the **User Guide**.
///
/// Each app item invokes the intent its key does ([appShortcuts]), from the
/// focused widget, so a menu item and its key always do the same thing,
/// including doing nothing in Perform.
///
/// Installing a [PlatformMenuBar] replaces the whole menu the app starts with
/// (`app/macos/Runner/Base.lproj/MainMenu.xib`). Flutter offers no system Edit
/// items, so **there is no Edit menu**: cut, copy, paste, undo and select all
/// keep working from the keyboard, and a right-click on selectable text offers
/// Copy and Select all, but the menu bar no longer lists them. The system items (About, Services,
/// Hide, Quit, Enter Full Screen, Minimize, Zoom) are titled by macOS and the
/// Flutter engine, not by the app's language setting.
///
/// The root app wraps its tree in this only when told to
/// (`CompendiumApp.installPlatformMenuBar`, set by `main` on macOS), so widget
/// tests, which have no platform menu channel, never install it.
class AppMenuBar extends StatelessWidget {
  const AppMenuBar({super.key, required this.child});

  final Widget child;

  /// The menus, built from the current [AppLocalizations].
  @visibleForTesting
  static List<PlatformMenuItem> menusFor(AppLocalizations l10n) => [
    PlatformMenu(
      label: l10n.appTitle,
      menus: [
        const PlatformMenuItemGroup(
          members: [
            PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.about),
          ],
        ),
        PlatformMenuItemGroup(
          members: [
            PlatformMenuItem(
              label: l10n.menuSettings,
              shortcut: const SingleActivator(
                LogicalKeyboardKey.comma,
                meta: true,
              ),
              onSelectedIntent: const OpenSettingsIntent(),
            ),
          ],
        ),
        const PlatformMenuItemGroup(
          members: [
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.servicesSubmenu,
            ),
          ],
        ),
        const PlatformMenuItemGroup(
          members: [
            PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.hide),
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.hideOtherApplications,
            ),
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.showAllApplications,
            ),
          ],
        ),
        const PlatformMenuItemGroup(
          members: [
            PlatformProvidedMenuItem(type: PlatformProvidedMenuItemType.quit),
          ],
        ),
      ],
    ),
    PlatformMenu(
      label: l10n.menuFile,
      menus: [
        PlatformMenuItemGroup(
          members: [
            PlatformMenuItem(
              label: l10n.menuNewDance,
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyN,
                meta: true,
              ),
              onSelectedIntent: const NewDanceIntent(),
            ),
            PlatformMenuItem(
              label: l10n.menuImportDances,
              onSelectedIntent: const ImportDancesIntent(),
            ),
          ],
        ),
        PlatformMenuItemGroup(
          members: [
            PlatformMenuItem(
              label: l10n.menuClose,
              shortcut: const SingleActivator(
                LogicalKeyboardKey.keyW,
                meta: true,
              ),
              onSelectedIntent: const GoBackIntent(),
            ),
          ],
        ),
      ],
    ),
    PlatformMenu(
      label: l10n.menuView,
      menus: const [
        // The system's own item, with its own Ctrl-Cmd-F key. Perform follows
        // the window's real state, so taking the window full screen from here
        // updates Perform's toolbar too; and the window service does not save
        // a full-screen frame as the window's size.
        PlatformProvidedMenuItem(
          type: PlatformProvidedMenuItemType.toggleFullScreen,
        ),
      ],
    ),
    PlatformMenu(
      label: l10n.menuWindow,
      menus: const [
        PlatformMenuItemGroup(
          members: [
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.minimizeWindow,
            ),
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.zoomWindow,
            ),
          ],
        ),
        PlatformMenuItemGroup(
          members: [
            PlatformProvidedMenuItem(
              type: PlatformProvidedMenuItemType.arrangeWindowsInFront,
            ),
          ],
        ),
      ],
    ),
    PlatformMenu(
      label: l10n.menuHelp,
      menus: [
        PlatformMenuItem(
          label: l10n.menuUserGuide,
          onSelectedIntent: const OpenGuideIntent(),
        ),
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) => PlatformMenuBar(
    menus: menusFor(AppLocalizations.of(context)),
    child: child,
  );
}
