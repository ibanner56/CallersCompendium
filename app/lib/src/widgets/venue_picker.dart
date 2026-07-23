import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../data/repositories_scope.dart';
import '../screens/venue_editor_sheet.dart';

/// A single-select picker over the reusable [Venue] records. Used by the
/// program editor's "enriched" venue mode to choose (or inline-create) the
/// venue a program links to via `Program.venueId`.
///
/// Loads `venues.listAll()` itself (ordered by name) so the host screen only
/// has to hold the selected id. Reports selection changes via [onChanged]
/// (`null` clears the link). "Add new venue…" opens [VenueEditorSheet], upserts
/// the result, then selects it. Follows the type-ahead + inline-create
/// conventions of `NamePicker`/`CollectionPicker`.
class VenuePicker extends StatefulWidget {
  const VenuePicker({
    super.key,
    required this.selectedVenueId,
    required this.onChanged,
  });

  /// The currently linked venue id, or `null` when no venue is linked.
  final String? selectedVenueId;

  /// Called with the newly selected venue id, or `null` when the link is
  /// cleared. The host persists the id onto the program.
  final ValueChanged<String?> onChanged;

  @override
  State<VenuePicker> createState() => _VenuePickerState();
}

class _VenuePickerState extends State<VenuePicker> {
  late CompendiumRepositories _repos;
  bool _started = false;
  bool _loading = true;
  List<Venue> _venues = const [];
  Object? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_started) {
      _started = true;
      _repos = RepositoriesScope.of(context);
      _load();
    }
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final venues = await _repos.venues.listAll();
      if (!mounted) return;
      setState(() {
        _venues = venues;
        _loading = false;
      });
    } catch (error, stackTrace) {
      debugPrint('Could not load venues: $error\n$stackTrace');
      if (!mounted) return;
      setState(() {
        _error = error;
        _loading = false;
      });
    }
  }

  Venue? get _selected {
    final id = widget.selectedVenueId;
    if (id == null) return null;
    for (final v in _venues) {
      if (v.id == id) return v;
    }
    return null;
  }

  Future<void> _createNew(String seedName) async {
    // Prefill the sheet's name with what the user typed so inline-create is one
    // step. The sheet returns the built venue (with a freshly minted id) or
    // null on cancel; we upsert it, reload, and select it.
    final created = await VenueEditorSheet.show(context, seedName: seedName);
    if (created == null || !mounted) return;
    await _repos.venues.upsert(created);
    if (!mounted) return;
    await _load();
    if (!mounted) return;
    widget.onChanged(created.id);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    if (_loading) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: 12),
            Text(l10n.venuePickerLoading),
          ],
        ),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Row(
          children: [
            Expanded(child: Text(l10n.venueLoadError)),
            TextButton(onPressed: _load, child: Text(l10n.commonRetry)),
          ],
        ),
      );
    }

    final selected = _selected;
    final unresolved = widget.selectedVenueId != null && selected == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (selected != null)
          Card(
            key: const ValueKey('venue-picker-selected'),
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.place_outlined),
              title: Text(selected.name),
              subtitle: selected.displayName == selected.name
                  ? null
                  : Text(selected.displayName),
              trailing: IconButton(
                key: const ValueKey('venue-picker-clear'),
                tooltip: l10n.venuePickerUnlinkTooltip,
                icon: const Icon(Icons.clear),
                onPressed: () => widget.onChanged(null),
              ),
            ),
          )
        else if (unresolved)
          // The linked venue id no longer resolves (e.g. it was deleted); offer
          // a clear affordance rather than silently dropping it.
          Card(
            key: const ValueKey('venue-picker-unresolved'),
            margin: EdgeInsets.zero,
            child: ListTile(
              leading: Icon(Icons.help_outline, color: theme.colorScheme.error),
              title: Text(l10n.venuePickerUnresolvedTitle),
              subtitle: Text(l10n.venuePickerUnresolvedSubtitle),
              trailing: IconButton(
                tooltip: l10n.venuePickerClearLinkTooltip,
                icon: const Icon(Icons.clear),
                onPressed: () => widget.onChanged(null),
              ),
            ),
          ),
        const SizedBox(height: 8),
        _VenueAutocomplete(
          venues: _venues,
          excludeId: widget.selectedVenueId,
          onSelect: widget.onChanged,
          onCreate: _createNew,
          hint: selected == null
              ? l10n.venuePickerSearchHint
              : l10n.venuePickerChangeHint,
        ),
      ],
    );
  }
}

class _VenueAutocomplete extends StatefulWidget {
  const _VenueAutocomplete({
    required this.venues,
    required this.excludeId,
    required this.onSelect,
    required this.onCreate,
    required this.hint,
  });

  final List<Venue> venues;
  final String? excludeId;
  final ValueChanged<String?> onSelect;
  final Future<void> Function(String seedName) onCreate;
  final String hint;

  @override
  State<_VenueAutocomplete> createState() => _VenueAutocompleteState();
}

class _VenueAutocompleteState extends State<_VenueAutocomplete> {
  final TextEditingController _controller = TextEditingController();
  final FocusNode _focusNode = FocusNode();

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Autocomplete<_VenueChoice>(
      key: const ValueKey('venue-picker-autocomplete'),
      textEditingController: _controller,
      focusNode: _focusNode,
      displayStringForOption: (choice) => choice.label,
      optionsBuilder: (value) {
        final q = value.text.trim();
        if (q.isEmpty) return const Iterable<_VenueChoice>.empty();
        final lower = q.toLowerCase();
        final matches = widget.venues
            .where(
              (v) =>
                  v.id != widget.excludeId &&
                  v.displayName.toLowerCase().contains(lower),
            )
            .map((v) => _VenueChoice.existing(v))
            .toList();
        // Offer inline-create unless the typed text exactly matches an
        // existing venue. Check BOTH name and displayName (and honor
        // excludeId like the filter above) so typing a venue's full display
        // name — which the search matches on — can't slip past and create a
        // duplicate.
        final exact = widget.venues.any(
          (v) =>
              v.id != widget.excludeId &&
              (v.name.toLowerCase() == lower ||
                  v.displayName.toLowerCase() == lower),
        );
        if (!exact) matches.add(_VenueChoice.create(q));
        return matches;
      },
      onSelected: (choice) async {
        if (choice.isCreate) {
          await widget.onCreate(choice.name);
          // The create flow is async (it opens the editor sheet); if this
          // picker was disposed while that was open (e.g. the route was
          // popped), don't touch the now-defunct controller/focus node.
          if (!mounted) return;
        } else {
          widget.onSelect(choice.venue!.id);
        }
        _controller.clear();
        _focusNode.unfocus();
      },
      fieldViewBuilder: (context, controller, focusNode, onSubmit) {
        return TextField(
          key: const ValueKey('venue-picker-input'),
          controller: controller,
          focusNode: focusNode,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            hintText: widget.hint,
            prefixIcon: const Icon(Icons.search),
            border: const OutlineInputBorder(),
            isDense: true,
          ),
          onSubmitted: (_) => onSubmit(),
        );
      },
      optionsViewBuilder: (context, onSelected, choices) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260, maxWidth: 420),
              child: ListView(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                children: [
                  for (final choice in choices)
                    ListTile(
                      key: ValueKey('venue-option-${choice.optionKey}'),
                      dense: true,
                      leading: Icon(
                        choice.isCreate ? Icons.add : Icons.place_outlined,
                        size: 18,
                      ),
                      title: Text(
                        choice.isCreate
                            ? l10n.venuePickerCreateOption(choice.name)
                            : choice.venue!.displayName,
                      ),
                      onTap: () => onSelected(choice),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _VenueChoice {
  _VenueChoice.existing(this.venue) : isCreate = false, name = venue!.name;
  _VenueChoice.create(this.name) : venue = null, isCreate = true;

  final Venue? venue;
  final String name;
  final bool isCreate;

  String get label => name;

  String get optionKey => isCreate ? 'create:$name' : venue!.id;
}
