import 'dart:io';

/// Extensions as the platform picker should be told them.
///
/// `file_selector_linux` turns each extension into a GTK `*.<ext>` pattern and
/// GTK patterns are case-sensitive, so on Linux a bare `usr` hides the
/// CallersCompanion2.USR files Caller's Companion actually writes (#1823).
/// There we list the lower-case, UPPER-case and Capitalised spellings. macOS and
/// Windows match extensions case-insensitively, so they keep the bare list.
///
/// Our call: three spellings, not every case permutation (`ccshare` alone would
/// be 128 patterns) and not a GTK suffix filter (the plugin does not expose
/// one); a `.UsR` file can still be opened by typing its name in the dialog.
List<String> pickerExtensions(List<String> extensions, bool? isLinux) {
  if (!(isLinux ?? Platform.isLinux)) return extensions;
  String cap(String e) => e.isEmpty ? e : e[0].toUpperCase() + e.substring(1);
  return [
    for (final e in extensions) ...{e.toLowerCase(), e.toUpperCase(), cap(e)},
  ];
}
