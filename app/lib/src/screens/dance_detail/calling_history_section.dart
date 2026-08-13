import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../data/calling_history_caller_filter.dart';
import '../../data/venue_label.dart';
import '../../theme/app_spacing.dart';

/// The dance-detail screen's **Calling history** section: the programs that
/// include this dance, its first/second-half calling stats, and the empty state
/// when it has never been called.
///
/// ## This is the app-side reference implementation for issue #768
///
/// It is the first `StreamBuilder` in the app. Everything it renders is derived
/// from `program_slots` + `programs` — data no dance-side write touches and
/// every program-side write changes — so before this it went stale unless a
/// mutation site remembered to broadcast `ProgramsRefreshScope`, which is the
/// defect class #768 catalogues seven instances of. It now reads
/// [ProgramRepository.watchCallingHistoryForDance], whose doc comment states the
/// repository-side half of the pattern (in particular why `readsFrom` is the
/// silent-failure mode to design against). The widget-side rules it
/// demonstrates, for the screens converted after it:
///
/// 1. **The stream is a `State` field, created once** — in
///    [State.didChangeDependencies], and again only when an argument that
///    changes the query changes ([State.didUpdateWidget]). Building it inside
///    `build` would re-subscribe and re-query on every frame.
/// 2. **The section owns its own subscription**, so a rebuild of the screen
///    around it — a dance edit, a theme change — neither drops nor duplicates
///    it, and the screen's own load no longer fetches this data at all.
/// 3. **One stream, one rebuild.** The half-stats arrive inside
///    [DanceCallingHistory] rather than from a second stream, so a program write
///    rebuilds this section once. Over-firing is issue #340's failure and pulls
///    opposite to staleness; both have to be held at once.
/// 4. **The read set is the consumer's, not the query's** (issue #944).
///    This section renders a venue label per row, so it opts into `venues` —
///    while the Collection list, which renders no venue, does not. The same
///    repository method therefore serves two different watched sets, because
///    "what does this query select?" and "what does this screen render?" are
///    different questions and only the second one is the correct read set.
///
///    It was originally written the other way: `venues` deliberately excluded,
///    with a note that a rename would keep the old label until the screen was
///    reopened. Stating the gap did not stop it being a defect.
/// 4a. **A cache in front of a stream can defeat its read set.** Widening the
///    set was necessary and not sufficient here: [_withVenueLabels] re-read the
///    catalogue only when a record linked an id it could not resolve, and a
///    rename leaves the id resolvable. The stream fired, this consumer re-ran,
///    and it declined to re-read something it believed it already knew. The
///    read set can make a consumer re-run; it cannot make it re-read. See
///    [_venuesDirty].
/// 5. **The screen drops its `ProgramsRefreshScope` listener in the same
///    change.** Keeping it would reload the whole screen on top of this stream's
///    emit: one write, two rebuilds. The scope itself stays — the screens not
///    yet converted still depend on it.
///
/// Rendered only for a saved dance; calling history is a collection-only
/// concept, so the online-preview detail view omits this section entirely.
class CallingHistorySection extends StatefulWidget {
  const CallingHistorySection({
    super.key,
    required this.repositories,
    required this.danceId,
    required this.performedOnly,
    required this.trackAllCallers,
    required this.onOpenProgram,
  });

  final CompendiumRepositories repositories;
  final String danceId;

  /// "Require mark-performed for calling history" (ROADMAP G.2). Changing it
  /// changes the query, so the stream is rebuilt.
  final bool performedOnly;

  /// "Track calling history for all callers" (issue #583). Resolves to the
  /// caller filter passed to the query, so a change rebuilds the stream.
  final bool trackAllCallers;

  /// Opens the program summary for a tapped history row.
  final ValueChanged<String> onOpenProgram;

  @override
  State<CallingHistorySection> createState() => _CallingHistorySectionState();
}

class _CallingHistorySectionState extends State<CallingHistorySection> {
  /// The live query. Held in the State — never built in [build] — and replaced
  /// only when an argument that changes the query changes.
  Stream<DanceCallingHistory>? _history;

  /// Whether the stream has delivered a value yet — see [_venuesDirty].
  bool _seenFirstEmit = false;

  /// Venue display names by id, for the linked venues seen so far.
  ///
  /// `venues` IS in this stream's declared tables now (issue #944), so an emit
  /// can carry a venue change — but the cache in front of it would still serve
  /// the old name, which is what [_venuesDirty] exists to prevent.
  Map<String, Venue> _venuesById = const {};

  /// Whether [_venuesById] may be out of date.
  ///
  /// Set on every emit after the first, because the stream watches `venues` for
  /// this consumer and an emit is therefore the only signal available that one
  /// may have changed — the rows themselves carry ids, which a rename does not
  /// alter. Cleared when the catalogue is re-read.
  ///
  /// The cost of being conservative is one `venues.listAll()` per emit that
  /// resolves at least one linked venue; the cost of being clever would be a
  /// rename that never appears. That trade is why this is a flag and not a
  /// comparison.
  bool _venuesDirty = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _history ??= _watch();
  }

  @override
  void didUpdateWidget(CallingHistorySection oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.repositories != widget.repositories) {
      // The cache is keyed by venue id, which is only meaningful within one
      // database. Carrying it across a swap would let a stale entry answer for
      // an id that exists in both, and the "already resolved" check would then
      // skip the reload that would have corrected it — so the row would render
      // the OLD database's venue name. Clear it rather than trust the id.
      _venuesById = const {};
    }
    if (oldWidget.danceId != widget.danceId ||
        oldWidget.performedOnly != widget.performedOnly ||
        oldWidget.trackAllCallers != widget.trackAllCallers ||
        oldWidget.repositories != widget.repositories) {
      setState(() => _history = _watch());
    }
  }

  /// Builds the query stream for the current arguments.
  ///
  /// The caller filter is a settings read, so the stream is preceded by one
  /// future; `asyncExpand` keeps that off the widget tree rather than nesting a
  /// [FutureBuilder] around a [StreamBuilder]. A settings *change* arrives as a
  /// new [CallingHistorySection.trackAllCallers], which rebuilds this stream —
  /// settings are not part of the watched table set, and do not need to be.
  Stream<DanceCallingHistory> _watch() =>
      Stream.fromFuture(
        resolveCallingHistoryCallerFilter(
          widget.repositories.settings,
          trackAllCallers: widget.trackAllCallers,
        ),
      ).asyncExpand(
        (callerFilter) => widget.repositories.programs
            .watchCallingHistoryForDance(
              widget.danceId,
              performedOnly: widget.performedOnly,
              callerFilter: callerFilter,
            )
            .map((history) {
              // First emit populates the cache via the unresolved-id path; from
              // then on, any emit may be carrying a venue write.
              if (_seenFirstEmit) _venuesDirty = true;
              _seenFirstEmit = true;
              return history;
            })
            .asyncMap(_withVenueLabels),
      );

  /// Ensures [_venuesById] can resolve every linked venue in [history], then
  /// passes the history through unchanged.
  ///
  /// The catalogue is read only when a record links a venue the cache cannot
  /// already resolve, so a dance with no calling history — or one whose
  /// programs carry only free-text venues — costs no query at all. That gating
  /// is inherited, not invented: the one-shot load this replaced paid for the
  /// catalogue only when `callingHistory.any((r) => r.venueId != null)`, and
  /// dropping it would have added a `venues.listAll()` to opening any dance.
  ///
  /// Running inside `asyncMap` rather than beside the stream is what makes the
  /// labels arrive with the rows they belong to, and removes any need to guard
  /// against a stale load landing late: `asyncMap` will not deliver the next
  /// value until this one resolves.
  ///
  /// A failure here must not take out the whole section — the rows fall back to
  /// their own free-text venue, which is what they render without a catalogue.
  Future<DanceCallingHistory> _withVenueLabels(
    DanceCallingHistory history,
  ) async {
    // ## Why an id-resolvability check is not enough (issue #944)
    //
    // This cache used to re-read only when a record linked a venue it could
    // not resolve. A **rename** leaves the id perfectly resolvable, so the
    // check was false and the cache was never refreshed — the section rendered
    // the old name indefinitely, and no read set could have fixed it: the
    // stream fired, the consumer re-ran, and it declined to re-read something
    // it believed it already knew.
    //
    // So a re-read is forced when the emit could have carried a venue change.
    // `_venuesDirty` is set by the subscription on every emit after the first,
    // which is exactly when a venue write may have occurred — the stream now
    // watches `venues` for this consumer, so an emit is the signal.
    //
    // The unresolved-id check is kept as well, because it covers the other
    // case: a program that gained a link to a venue this cache has never seen.
    // Neither condition implies the other.
    // The cost gate above still applies to both conditions: a history whose
    // programs all carry free text links no venue, so the catalogue cannot
    // change what it renders and is not read however dirty the cache is.
    //
    // The flag is cleared only when a read *succeeds* — not merely when one is
    // attempted — so neither skipping here nor a throwing read loses the
    // signal: a later emit whose records do link a venue still re-reads.
    // ("A read happens" and "a read succeeds" differing is what the review
    // finding on this method was about; see the note inside the `try`.)
    final linksAnyVenue = history.records.any((r) => r.venueId != null);
    final hasUnresolved = history.records.any(
      (r) => r.venueId != null && !_venuesById.containsKey(r.venueId),
    );
    if (linksAnyVenue && (hasUnresolved || _venuesDirty)) {
      try {
        final venues = await widget.repositories.venues.listAll();
        _venuesById = {for (final v in venues) v.id: v};
        // Cleared only on success. Raised in review as a lost-retry bug if
        // cleared up front; it is not one, and the reason is worth writing
        // down because it is a coupling between two methods rather than a
        // property of either.
        //
        // Clearing eagerly would be **behaviourally identical**: the flag is
        // re-armed by the subscription on *every* emit after the first, so a
        // failed read cannot strand it — the next emit sets it again. And when
        // no next emit arrives, both orderings leave the label stale, because
        // this method only runs on an emit at all. Verified by mutation: with
        // the eager clear restored and a transient failure confirmed injected,
        // the retry test still passes.
        //
        // It is written this way anyway, so that the correctness of the error
        // path does not depend on the re-arming happening in a different
        // method. A future change that armed the flag only on a venue-table
        // update — a reasonable optimisation — would make the eager clear a
        // real bug, silently.
        //
        // Safe to write after an `await` because `asyncMap` holds the
        // subscription until this future completes, so no second emit can
        // interleave and set the flag between the read and the clear.
        _venuesDirty = false;
      } catch (_) {
        // Keep whatever the cache holds; rows fall back to free text, and
        // `_venuesDirty` stays set so the next emit retries.
      }
    }
    return history;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);

    return StreamBuilder<DanceCallingHistory>(
      stream: _history,
      builder: (context, snapshot) {
        // A failed query must not render the empty state: "not yet included in
        // any program" is a claim about the data, and saying it when the read
        // failed tells the user this dance has never been called. Only when
        // there is no value to fall back on — a later failure keeps showing the
        // last good history, which is still true of the database.
        final failed = snapshot.hasError && !snapshot.hasData;
        // Before the first value arrives, render the section's own empty state
        // rather than a spinner: this section sits inside an already-loaded
        // screen, and the first emit is one local query away.
        final history = snapshot.data ?? DanceCallingHistory.empty;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: AppSpacing.lg),
            Text(
              l10n.danceSectionCallingHistory,
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.xxs),
            if (failed)
              Padding(
                key: const ValueKey('calling-history-error'),
                // intentional: 2px optical inset, below the 4px AppSpacing grid
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  l10n.danceCallingHistoryError,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              )
            else if (history.records.isEmpty)
              Padding(
                key: const ValueKey('calling-history-empty'),
                // intentional: 2px optical inset, below the 4px AppSpacing grid
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Text(
                  l10n.danceCallingHistoryEmpty,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              )
            else
              for (final record in history.records)
                CallingHistoryRow(
                  key: ValueKey('calling-history-${record.slotId}'),
                  record: record,
                  venueLabel: resolveVenueLabelParts(
                    record.venueId,
                    record.venue,
                    _venuesById,
                  ),
                  onTap: () => widget.onOpenProgram(record.programId),
                ),
            if (history.halfStats.hasAny) ...[
              const SizedBox(height: AppSpacing.xs),
              HalfStatsSummary(
                key: const ValueKey('half-calling-stats'),
                stats: history.halfStats,
              ),
            ],
          ],
        );
      },
    );
  }
}

/// One program in the dance's calling history: its title, the date it was
/// called (or scheduled) and its venue, tappable to open the program.
class CallingHistoryRow extends StatelessWidget {
  const CallingHistoryRow({
    super.key,
    required this.record,
    this.venueLabel,
    this.onTap,
  });

  final DanceCallingRecord record;

  /// The venue label to display: the linked [Venue]'s display name when the
  /// program's `venueId` resolves, otherwise the free-text `venue`. Null falls
  /// back to the record's own free-text `venue`, so this row still renders
  /// correctly before the venue catalogue has loaded.
  final String? venueLabel;

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final localizations = MaterialLocalizations.of(context);
    // Programs appear as soon as they include the dance, so `performedAt` is
    // often null; `effectiveDate` falls back to the program's event date, then
    // its last-updated time, so a date always shows. These are stored UTC
    // values rendered directly (matching the other date labels on this screen).
    final date = localizations.formatMediumDate(record.effectiveDate);
    final venue = (venueLabel ?? record.venue)?.trim();
    final subtitleParts = <String>[
      date,
      if (venue != null && venue.isNotEmpty) venue,
    ];
    final subtitle = subtitleParts.join(' · ');

    return MergeSemantics(
      child: Semantics(
        button: true,
        label: l10n.danceOpenProgramSemantic(
          record.programTitle,
          subtitleParts.join(', '),
        ),
        child: InkWell(
          onTap: onTap,
          child: ExcludeSemantics(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
              child: Row(
                children: [
                  const Icon(Icons.event_note_outlined, size: 16),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          record.programTitle,
                          style: theme.textTheme.bodyLarge,
                        ),
                        if (subtitle.isNotEmpty)
                          Text(
                            subtitle,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const Icon(Icons.chevron_right, size: 16),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A compact, screen-reader-friendly summary of the dance's first/second-half
/// calling stats (issue #378), shown under the calling-history list when any
/// half-attributed occurrence exists. Uses icon + text (never colour or a
/// glyph alone; matrix WCAG 1.4.1 rule) and a single explicit [Semantics]
/// label so assistive tech announces the whole breakdown as one phrase.
class HalfStatsSummary extends StatelessWidget {
  const HalfStatsSummary({super.key, required this.stats});

  final HalfCallingStats stats;

  /// Builds the human phrasing shared by the visible text and the semantics
  /// label, so they never drift apart.
  String _describe(AppLocalizations l10n) {
    final parts = <String>[
      l10n.danceHalfStatsFirstHalf(stats.firstHalfCount),
      l10n.danceHalfStatsSecondHalf(stats.secondHalfCount),
    ];
    if (stats.openedFirstHalfCount > 0) {
      parts.add(l10n.danceHalfStatsOpened(stats.openedFirstHalfCount));
    }
    if (stats.closedSecondHalfCount > 0) {
      parts.add(l10n.danceHalfStatsClosed(stats.closedSecondHalfCount));
    }
    return '${parts.join('; ')}.';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final description = _describe(l10n);
    return Semantics(
      label: l10n.danceHalfStatsSemanticLabel(description),
      container: true,
      child: ExcludeSemantics(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxs),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                Icons.balance_outlined,
                size: 16,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  description,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
