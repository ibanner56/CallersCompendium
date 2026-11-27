import 'dart:async';

import 'package:compendium_core/compendium_core.dart' show VenueKey;
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../data/date_format_scope.dart';
import '../data/regional_formats.dart';
import '../diagnostics/error_log.dart';
import '../search/called_venue_choices.dart';
import '../search/collection_query.dart';
import '../theme/app_motion.dart';
import '../theme/app_spacing.dart';
import 'app_date_picker.dart';

/// The two controls under the Filters panel's Called / Not called chips:
/// **At venue** and **Within** (`docs/design/history-filters.md`, N1-H2).
///
/// They write [FacetSelections.historyVenue], [FacetSelections.historyMonths]
/// and [FacetSelections.historySince]; they act only while exactly one of
/// Called / Not called is chosen ([FacetSelections.scopesApply]). Without a
/// polarity they stay editable but show a hint saying why nothing changes.
///
/// [venues] is where the venue chooser reads its rows. Null (a host with no
/// repositories) leaves the venue row out and keeps **Within**.
///
/// **Within** offers 1, 3 and 6 months. A window of any other number of
/// months can only come in with a given panel state (a saved search keeps the
/// months, `docs/design/search.md`); it shows as one more selected chip,
/// "12 months", or "12 months, saved" when [fromSavedSearch], so a window that
/// is narrowing the list is never invisible. Choosing another window replaces
/// it, as for the presets.
class CallingHistoryScopes extends StatefulWidget {
  const CallingHistoryScopes({
    super.key,
    required this.facets,
    required this.venues,
    this.fromSavedSearch = false,
    required this.onChanged,
  });

  final FacetSelections facets;
  final VenueChoiceSource? venues;

  /// Whether the panel state came from a saved search.
  final bool fromSavedSearch;
  final VoidCallback onChanged;

  /// The **Within** presets.
  static const presetMonths = [1, 3, 6];

  @override
  State<CallingHistoryScopes> createState() => _CallingHistoryScopesState();
}

class _CallingHistoryScopesState extends State<CallingHistoryScopes> {
  StreamSubscription<List<VenueChoice>>? _sub;
  List<VenueChoice>? _choices;
  StreamSubscription<Map<String, String>>? _namesSub;

  /// Every venue record's name by id, for a chosen venue [_choices] does not
  /// list.
  Map<String, String> _venueNames = const {};

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(CallingHistoryScopes oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.venues != widget.venues) _subscribe();
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    unawaited(_namesSub?.cancel());
    super.dispose();
  }

  void _subscribe() {
    unawaited(_sub?.cancel());
    unawaited(_namesSub?.cancel());
    _sub = null;
    _namesSub = null;
    final source = widget.venues;
    if (source == null) {
      _choices = null;
      _venueNames = const {};
      return;
    }
    _namesSub = source.watchNames().listen(
      (names) {
        if (mounted) setState(() => _venueNames = names);
      },
      onError: (Object error, StackTrace stackTrace) {
        // The chip falls back to the label it was chosen with.
        logCaughtError(
          error,
          stackTrace,
          source: 'calling_history_scopes.venueNames',
        );
      },
    );
    _sub = source.watch().listen(
      (choices) {
        if (mounted) setState(() => _choices = choices);
      },
      onError: (Object error, StackTrace stackTrace) {
        // The venue row just stays as it was; the rest of the section works.
        logCaughtError(
          error,
          stackTrace,
          source: 'calling_history_scopes.venues',
        );
      },
    );
  }

  void _pickMonths(int? months) {
    widget.facets.setHistoryMonths(months);
    widget.onChanged();
  }

  Future<void> _pickSince() async {
    final now = DateTime.now();
    final current = widget.facets.historySince;
    final picked = await showAppDatePicker(
      context: context,
      initialDate: current == null
          ? now
          : DateTime(current.year, current.month, current.day),
      firstDate: DateTime(now.year - 30),
      lastDate: DateTime(now.year + 10),
    );
    if (picked == null || !mounted) return;
    widget.facets.setHistorySince(picked);
    widget.onChanged();
  }

  Future<void> _pickVenue() async {
    final chosen = await showModalBottomSheet<_VenuePick>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _VenueSheet(
        choices: _choices ?? const [],
        selected: widget.facets.historyVenue,
      ),
      sheetAnimationStyle: AppMotion.styleFor(context),
    );
    if (chosen == null || !mounted) return;
    widget.facets.setHistoryVenue(
      chosen.choice?.key,
      label: chosen.choice?.label,
    );
    widget.onChanged();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final facets = widget.facets;
    final venue = facets.historyVenue;
    // The catalogue's current name beats the label stored when it was chosen,
    // so a renamed venue reads right. A venue record the chooser does not
    // list (no counted call now; a saved search keeps no label) is named from
    // the record.
    final venueId = venue?.venueId;
    final venueLabel =
        _choices?.where((c) => c.key == venue).firstOrNull?.label ??
        (venueId == null ? null : _venueNames[venueId]) ??
        facets.historyVenueLabel;
    final showVenue = venue != null || (_choices?.isNotEmpty ?? false);
    final noWindow =
        facets.historyMonths == null && facets.historySince == null;
    final since = facets.historySince;
    // "Never called" is true only without a venue; at a venue it would mean
    // "never called there", which the neutral label does not promise.
    final neverCalled =
        facets.scopesApply &&
        facets.callStatuses.single == false &&
        venue == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!facets.scopesApply)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
            child: Text(
              l10n.collectionFacetHistoryInert,
              key: const ValueKey('facet-history-inert-hint'),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        if (showVenue)
          Wrap(
            crossAxisAlignment: WrapCrossAlignment.center,
            spacing: 8,
            runSpacing: 4,
            children: [
              Text(
                l10n.collectionFacetVenue,
                style: theme.textTheme.labelLarge,
              ),
              InputChip(
                key: const ValueKey('facet-history-venue'),
                avatar: const Icon(Icons.place_outlined, size: 18),
                label: Text(
                  venue == null
                      ? l10n.collectionFacetVenueAny
                      : (venueLabel?.isNotEmpty ?? false)
                      ? venueLabel!
                      : l10n.collectionFacetVenueUnnamed,
                ),
                selected: venue != null,
                showCheckmark: false,
                onPressed: _pickVenue,
                onDeleted: venue == null
                    ? null
                    : () {
                        facets.setHistoryVenue(null);
                        widget.onChanged();
                      },
                deleteButtonTooltipMessage: l10n.collectionFacetVenueClear,
              ),
            ],
          ),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          runSpacing: 4,
          children: [
            Text(l10n.collectionFacetWithin, style: theme.textTheme.labelLarge),
            ChoiceChip(
              key: const ValueKey('facet-history-within-none'),
              label: Text(
                neverCalled
                    ? l10n.collectionFacetWithinNever
                    : l10n.collectionFacetWithinAnyTime,
              ),
              selected: noWindow,
              onSelected: (_) => _pickMonths(null),
            ),
            for (final months in CallingHistoryScopes.presetMonths)
              ChoiceChip(
                key: ValueKey('facet-history-within-$months'),
                label: Text(l10n.collectionFacetWithinMonths(months)),
                selected: facets.historyMonths == months,
                onSelected: (_) => _pickMonths(months),
              ),
            if (facets.historyMonths case final months?
                when !CallingHistoryScopes.presetMonths.contains(months))
              ChoiceChip(
                key: const ValueKey('facet-history-within-other'),
                label: Text(
                  widget.fromSavedSearch
                      ? l10n.collectionFacetWithinMonthsSaved(months)
                      : l10n.collectionFacetWithinMonths(months),
                ),
                selected: true,
                // Already the window; another chip replaces it.
                onSelected: (_) {},
              ),
            ChoiceChip(
              key: const ValueKey('facet-history-within-since'),
              label: Text(
                since == null
                    ? l10n.collectionFacetWithinSince
                    : l10n.collectionFacetWithinSinceDate(
                        formatEventDate(
                          since,
                          DateFormatScope.of(context),
                          MaterialLocalizations.of(context),
                          l10n,
                        ),
                      ),
              ),
              selected: since != null,
              onSelected: (_) => unawaited(_pickSince()),
            ),
          ],
        ),
      ],
    );
  }
}

/// What the venue sheet returns: a venue, or null for "Any venue".
class _VenuePick {
  const _VenuePick(this.choice);
  final VenueChoice? choice;
}

class _VenueSheet extends StatelessWidget {
  const _VenueSheet({required this.choices, required this.selected});

  final List<VenueChoice> choices;
  final VenueKey? selected;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.md,
              0,
              AppSpacing.md,
              AppSpacing.xs,
            ),
            child: Text(
              l10n.collectionFacetVenueSheetTitle,
              style: Theme.of(context).textTheme.titleMedium,
            ),
          ),
          ListTile(
            key: const ValueKey('facet-history-venue-any'),
            title: Text(l10n.collectionFacetVenueAny),
            selected: selected == null,
            trailing: selected == null ? const Icon(Icons.check) : null,
            onTap: () => Navigator.of(context).pop(const _VenuePick(null)),
          ),
          for (final choice in choices)
            ListTile(
              key: ValueKey('facet-history-venue-${choice.key.storageKey}'),
              title: Text(
                choice.label.isEmpty
                    ? l10n.collectionFacetVenueUnnamed
                    : choice.label,
              ),
              subtitle: Text(
                choice.typed
                    ? '${l10n.collectionFacetVenuePrograms(choice.programCount)}'
                          ' · ${l10n.collectionFacetVenueTyped}'
                    : l10n.collectionFacetVenuePrograms(choice.programCount),
              ),
              selected: selected == choice.key,
              trailing: selected == choice.key ? const Icon(Icons.check) : null,
              onTap: () => Navigator.of(context).pop(_VenuePick(choice)),
            ),
        ],
      ),
    );
  }
}
