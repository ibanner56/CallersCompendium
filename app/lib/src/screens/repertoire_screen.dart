import 'package:clock/clock.dart';
import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../data/active_dialect_scope.dart';
import '../data/app_theme_scope.dart';
import '../data/calling_history_caller_filter.dart';
import '../data/calling_history_tracking_scope.dart';
import '../data/default_program_caller_scope.dart';
import '../data/repositories_scope.dart';
import '../data/require_event_date_for_history_scope.dart';
import '../data/require_performed_for_history_scope.dart';
import '../data/track_history_for_all_callers_scope.dart';
import '../diagnostics/error_log.dart';
import '../search/facet_labels.dart';
import '../search/repertoire_drill_down.dart';
import '../theme/app_shapes.dart';
import '../theme/app_spacing.dart';
import '../widgets/app_date_picker.dart';
import '../widgets/load_error_view.dart';
import '../widgets/section_header.dart';
import 'dance_detail_screen.dart';

/// The Repertoire page (#2357, Experimental): a read-only summary of the
/// collection and its calling history, reached from Collection's More actions
/// menu.
///
/// Every number is counted the way the rest of the app counts it, under the
/// Calling history settings ([RepertoireRepository]). A row that stands for a
/// set of dances pops this page with a [RepertoireDrillDown], which Collection
/// applies as its search; a row that stands for one dance opens that dance.
///
/// The period and dance type are session state: they reset when the page is
/// opened again.
class RepertoireScreen extends StatefulWidget {
  const RepertoireScreen({super.key});

  /// How many rows a ranked list shows before "Show all".
  static const int collapsedRows = 10;

  @override
  State<RepertoireScreen> createState() => _RepertoireScreenState();
}

class _RepertoireScreenState extends State<RepertoireScreen> {
  RepertoirePeriod _period = const RepertoirePeriod.allTime();
  DanceForm? _form;

  RepertoireStats? _stats;
  Map<String, String> _venueNames = const {};
  Object? _error;
  int _loadSeq = 0;

  /// The calling-history settings the last load ran under; a change reloads.
  ({
    bool performedOnly,
    bool requireEventDate,
    bool trackAll,
    String? defaultCaller,
    CallingHistoryTracking tracking,
  })?
  _settings;

  /// Figure lists the user expanded, by dance type.
  final Set<DanceForm> _expandedFigures = {};
  bool _authorsExpanded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final settings = (
      performedOnly: RequirePerformedForHistoryScope.of(context),
      requireEventDate: RequireEventDateForHistoryScope.of(context),
      trackAll: TrackHistoryForAllCallersScope.of(context),
      defaultCaller: DefaultProgramCallerScope.maybeOf(context),
      tracking: callingHistoryTrackingOf(context),
    );
    if (settings != _settings) {
      _settings = settings;
      _load();
    }
  }

  Future<void> _load() async {
    final seq = ++_loadSeq;
    final settings = _settings!;
    final repos = RepositoriesScope.of(context);
    final now = clock.now();
    final today = DateTime.utc(now.year, now.month, now.day);
    try {
      final callerFilter = await resolveCallingHistoryCallerFilter(
        repos.settings,
        trackAllCallers: settings.trackAll,
        defaultCaller: settings.defaultCaller,
      );
      final stats = await repos.repertoire.load(
        RepertoireScope(
          performedOnly: settings.performedOnly,
          requireEventDate: settings.requireEventDate,
          callerFilter: callerFilter,
          tracking: settings.tracking,
          since: _period.cutoff(today),
          form: _form,
        ),
      );
      final venues = await repos.venues.listAll();
      if (!mounted || seq != _loadSeq) return;
      setState(() {
        _stats = stats;
        _venueNames = {for (final v in venues) v.id: v.name};
        _error = null;
      });
    } catch (error, stackTrace) {
      logCaughtError(error, stackTrace, source: 'repertoire_screen._load');
      if (mounted && seq == _loadSeq) setState(() => _error = error);
    }
  }

  void _setPeriod(RepertoirePeriod period) {
    if (period == _period) return;
    setState(() => _period = period);
    _load();
  }

  void _setForm(DanceForm? form) {
    if (form == _form) return;
    setState(() => _form = form);
    _load();
  }

  Future<void> _pickSinceDate() async {
    final now = clock.now();
    final picked = await showAppDatePicker(
      context: context,
      initialDate: _period.since ?? DateTime(now.year, now.month, now.day),
      firstDate: DateTime(1900),
      lastDate: DateTime(now.year, now.month, now.day),
    );
    if (picked != null) _setPeriod(RepertoirePeriod.since(picked));
  }

  void _drill(RepertoireDrillDown drillDown) =>
      Navigator.of(context).pop(drillDown);

  void _openDance(String danceId) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => DanceDetailScreen(danceId: danceId),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final stats = _stats;
    final Widget body;
    if (_error != null) {
      body = LoadErrorView(message: l10n.repertoireLoadError, onRetry: _load);
    } else if (stats == null) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      body = ListView(
        key: const ValueKey('repertoire-list'),
        padding: const EdgeInsets.only(bottom: AppSpacing.xl),
        children: [
          _controls(l10n, stats),
          ..._calledSections(l10n, stats),
          ..._neverCalledSection(l10n, stats),
          ..._figureSection(l10n, stats),
          ..._authorSection(l10n, stats),
          ..._formationSection(l10n, stats),
          ..._venueSection(l10n, stats),
        ],
      );
    }
    return Scaffold(
      appBar: AppBar(title: Text(l10n.repertoireTitle)),
      body: body,
    );
  }

  Widget _controls(AppLocalizations l10n, RepertoireStats stats) {
    final material = MaterialLocalizations.of(context);
    final since = _period.since;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _ChipGroup(
            label: l10n.repertoirePeriodLabel,
            children: [
              ChoiceChip(
                key: const ValueKey('repertoire-period-all'),
                label: Text(l10n.repertoirePeriodAllTime),
                selected: _period.isAllTime,
                onSelected: (_) => _setPeriod(const RepertoirePeriod.allTime()),
              ),
              for (final months in RepertoirePeriod.monthPresets)
                ChoiceChip(
                  key: ValueKey('repertoire-period-$months'),
                  label: Text(l10n.repertoirePeriodMonths(months)),
                  selected: _period.months == months,
                  onSelected: (_) =>
                      _setPeriod(RepertoirePeriod.months(months)),
                ),
              ChoiceChip(
                key: const ValueKey('repertoire-period-since'),
                label: Text(
                  since == null
                      ? l10n.repertoirePeriodSinceDate
                      : l10n.repertoirePeriodSince(
                          material.formatMediumDate(since),
                        ),
                ),
                selected: since != null,
                onSelected: (_) => _pickSinceDate(),
              ),
            ],
          ),
          if (stats.formsPresent.length > 1) ...[
            const SizedBox(height: AppSpacing.xs),
            _ChipGroup(
              label: l10n.repertoireTypeLabel,
              children: [
                ChoiceChip(
                  key: const ValueKey('repertoire-type-all'),
                  label: Text(l10n.repertoireTypeAll),
                  selected: _form == null,
                  onSelected: (_) => _setForm(null),
                ),
                for (final form in DanceForm.values)
                  if (stats.formsPresent.contains(form))
                    ChoiceChip(
                      key: ValueKey('repertoire-type-${form.name}'),
                      label: Text(danceFormLabel(l10n, form)),
                      selected: _form == form,
                      onSelected: (_) => _setForm(form),
                    ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.xs),
          Text(
            l10n.repertoireSummary(
              stats.totalCalls,
              stats.calledDanceCount,
              stats.danceCount,
            ),
            key: const ValueKey('repertoire-summary'),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }

  List<Widget> _calledSections(AppLocalizations l10n, RepertoireStats stats) {
    final max = stats.mostCalled.isEmpty ? 0 : stats.mostCalled.first.count;
    Widget danceRow(RepertoireDanceCount d, String keyPrefix) => StatRow(
      key: ValueKey('$keyPrefix-${d.danceId}'),
      label: d.title,
      value: l10n.repertoireDanceCalls(d.count),
      semanticsLabel: l10n.repertoireDanceSemantics(d.title, d.count),
      fraction: max == 0 ? null : d.count / max,
      onTap: () => _openDance(d.danceId),
    );
    return [
      SectionHeader(title: l10n.repertoireMostCalledHeader),
      if (stats.mostCalled.isEmpty)
        _Note(l10n.repertoireNoCalls)
      else
        for (final d in stats.mostCalled) danceRow(d, 'repertoire-most'),
      SectionHeader(title: l10n.repertoireLeastCalledHeader),
      if (stats.mostCalled.isEmpty)
        _Note(l10n.repertoireNoCalls)
      else if (stats.leastCalled.isEmpty)
        _Note(l10n.repertoireLeastCalledAllShown)
      else
        for (final d in stats.leastCalled) danceRow(d, 'repertoire-least'),
    ];
  }

  List<Widget> _neverCalledSection(
    AppLocalizations l10n,
    RepertoireStats stats,
  ) {
    final total = stats.danceCount;
    final notInWindow = stats.notCalledInWindowCount;
    return [
      SectionHeader(title: l10n.repertoireNeverCalledHeader),
      StatRow(
        key: const ValueKey('repertoire-never-called'),
        label: l10n.repertoireNeverCalledLabel,
        value: l10n.repertoireOfDances(stats.neverCalledCount, total),
        semanticsLabel: l10n.repertoireNeverCalledSemantics(
          stats.neverCalledCount,
          total,
        ),
        fraction: total == 0 ? null : stats.neverCalledCount / total,
        onTap: () => _drill(RepertoireDrillDown.neverCalled(form: _form)),
      ),
      for (final d in stats.neverCalledSample)
        StatRow(
          key: ValueKey('repertoire-never-${d.danceId}'),
          label: d.title,
          semanticsLabel: l10n.repertoireNeverCalledDanceSemantics(d.title),
          indent: true,
          onTap: () => _openDance(d.danceId),
        ),
      if (notInWindow != null)
        StatRow(
          key: const ValueKey('repertoire-not-called-in-period'),
          label: l10n.repertoireNotCalledInPeriodLabel,
          value: l10n.repertoireOfDances(notInWindow, total),
          semanticsLabel: l10n.repertoireNotCalledInPeriodSemantics(
            notInWindow,
            total,
          ),
          fraction: total == 0 ? null : notInWindow / total,
          onTap: () =>
              _drill(RepertoireDrillDown.notCalledIn(_period, form: _form)),
        ),
    ];
  }

  List<Widget> _figureSection(AppLocalizations l10n, RepertoireStats stats) {
    final dialects = ActiveDialectScope.maybeOf(context);
    final byForm = <DanceForm, List<RepertoireFigureCount>>{};
    for (final f in stats.figures) {
      (byForm[f.form] ??= []).add(f);
    }
    final widgets = <Widget>[SectionHeader(title: l10n.repertoireFigureHeader)];
    if (byForm.isEmpty) {
      widgets.add(_Note(l10n.repertoireNoFigures));
      return widgets;
    }
    for (final MapEntry(key: form, value: figures) in byForm.entries) {
      final total = stats.danceCountsByForm[form] ?? 0;
      final taxonomy = shippedTaxonomies.forForm(form);
      final renderer = FigureRenderer(taxonomy);
      final dialect = dialects?.forForm(form) ?? Dialect.larksRobins;
      String label(String move) => taxonomy.resolve(move) == null
          ? move
          : renderer.displayMoveName(move, dialect);
      final expanded = _expandedFigures.contains(form);
      final shown = expanded
          ? figures
          : figures.take(RepertoireScreen.collapsedRows);
      if (byForm.length > 1) {
        widgets.add(_SubHeader(danceFormLabel(l10n, form)));
      }
      for (final f in shown) {
        final percent = total == 0 ? 0 : (f.danceCount * 100 / total).round();
        final name = label(f.move);
        widgets.add(
          StatRow(
            key: ValueKey('repertoire-figure-${form.name}-${f.move}'),
            label: name,
            value: l10n.repertoireFigureValue(
              f.danceCount,
              total,
              percent,
              f.callCount,
            ),
            semanticsLabel: l10n.repertoireFigureSemantics(
              name,
              f.danceCount,
              total,
              percent,
              f.callCount,
            ),
            fraction: total == 0 ? null : f.danceCount / total,
            onTap: () => _drill(RepertoireDrillDown.figure(f.move, form: form)),
          ),
        );
      }
      if (figures.length > RepertoireScreen.collapsedRows) {
        widgets.add(
          _ShowMore(
            key: ValueKey('repertoire-figures-more-${form.name}'),
            expanded: expanded,
            count: figures.length,
            onPressed: () => setState(() {
              if (!_expandedFigures.remove(form)) _expandedFigures.add(form);
            }),
          ),
        );
      }
    }
    return widgets;
  }

  List<Widget> _authorSection(AppLocalizations l10n, RepertoireStats stats) {
    final total = stats.totalCalls;
    final shown = _authorsExpanded
        ? stats.authors
        : stats.authors.take(RepertoireScreen.collapsedRows);
    return [
      SectionHeader(title: l10n.repertoireAuthorsHeader),
      _Note(l10n.repertoireAuthorsSummary(stats.authorCount)),
      for (final a in shown)
        _shareRow(
          l10n,
          key: ValueKey('repertoire-author-${a.choreographerId}'),
          label: a.name,
          calls: a.callCount,
          total: total,
          onTap: () => _drill(
            RepertoireDrillDown.author(a.choreographerId, _period, form: _form),
          ),
        ),
      if (stats.authors.length > RepertoireScreen.collapsedRows)
        _ShowMore(
          key: const ValueKey('repertoire-authors-more'),
          expanded: _authorsExpanded,
          count: stats.authors.length,
          onPressed: () => setState(() => _authorsExpanded = !_authorsExpanded),
        ),
    ];
  }

  List<Widget> _formationSection(AppLocalizations l10n, RepertoireStats stats) {
    final total = stats.totalCalls;
    return [
      SectionHeader(title: l10n.repertoireFormationHeader),
      if (stats.formations.isEmpty) _Note(l10n.repertoireNoCalls),
      for (final f in stats.formations)
        _shareRow(
          l10n,
          key: ValueKey('repertoire-formation-${f.shape.name}'),
          label: formationShapeLabel(l10n, f.shape),
          calls: f.callCount,
          total: total,
          onTap: () => _drill(
            RepertoireDrillDown.formation(f.shape, _period, form: _form),
          ),
        ),
    ];
  }

  List<Widget> _venueSection(AppLocalizations l10n, RepertoireStats stats) {
    final withRepeats = [
      for (final v in stats.venues)
        if (v.repeats.isNotEmpty) v,
    ];
    final widgets = <Widget>[SectionHeader(title: l10n.repertoireVenuesHeader)];
    if (withRepeats.isEmpty) {
      widgets.add(_Note(l10n.repertoireNoRepeats));
      return widgets;
    }
    for (final v in withRepeats) {
      final label =
          (v.key.venueId == null ? null : _venueNames[v.key.venueId]) ??
          v.latestVenueText ??
          l10n.repertoireVenueUnnamed;
      widgets.add(
        StatRow(
          key: ValueKey('repertoire-venue-${v.key.storageKey}'),
          label: label,
          value: l10n.repertoireVenueRepeats(v.repeats.length),
          semanticsLabel: l10n.repertoireVenueSemantics(
            label,
            v.repeats.length,
          ),
          onTap: () => _drill(
            RepertoireDrillDown.venue(
              v.key,
              _period,
              label: label,
              form: _form,
            ),
          ),
        ),
      );
      final max = v.repeats.first.count;
      for (final d in v.repeats) {
        widgets.add(
          StatRow(
            key: ValueKey('repertoire-venue-${v.key.storageKey}-${d.danceId}'),
            label: d.title,
            value: l10n.repertoireDanceCalls(d.count),
            semanticsLabel: l10n.repertoireDanceSemantics(d.title, d.count),
            fraction: d.count / max,
            indent: true,
            onTap: () => _openDance(d.danceId),
          ),
        );
      }
    }
    return widgets;
  }

  Widget _shareRow(
    AppLocalizations l10n, {
    required Key key,
    required String label,
    required int calls,
    required int total,
    required VoidCallback onTap,
  }) {
    final percent = total == 0 ? 0 : (calls * 100 / total).round();
    return StatRow(
      key: key,
      label: label,
      value: l10n.repertoireShareValue(calls, percent),
      semanticsLabel: l10n.repertoireShareSemantics(label, calls, percent),
      fraction: total == 0 ? null : calls / total,
      onTap: onTap,
    );
  }
}

/// One row of a Repertoire list: a label, its number as text, and an optional
/// bar in proportion.
///
/// The row is one semantics node read as [semanticsLabel], a sentence that
/// carries the number; the bar is decoration and is excluded. The row grows
/// with the text size (no fixed height), is focusable, and activates [onTap]
/// with Enter.
class StatRow extends StatelessWidget {
  const StatRow({
    super.key,
    required this.label,
    required this.semanticsLabel,
    this.value,
    this.fraction,
    this.indent = false,
    this.onTap,
  });

  final String label;
  final String? value;
  final String semanticsLabel;

  /// The bar's length as a share of the row, 0 to 1, or null for no bar.
  final double? fraction;
  final bool indent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final value = this.value;
    final fraction = this.fraction;
    final start = indent ? AppSpacing.xl : AppSpacing.md;
    return Semantics(
      container: true,
      button: onTap != null,
      label: semanticsLabel,
      excludeSemantics: true,
      onTap: onTap,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsetsDirectional.fromSTEB(
            start,
            AppSpacing.xs,
            AppSpacing.md,
            AppSpacing.xs,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Wrap(
                alignment: WrapAlignment.spaceBetween,
                spacing: AppSpacing.sm,
                children: [
                  Text(label, style: theme.textTheme.bodyLarge),
                  if (value != null)
                    Text(
                      value,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
              if (fraction != null) ...[
                const SizedBox(height: AppSpacing.xxs),
                ProportionBar(fraction: fraction),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A plain-widget bar [fraction] of the row long. Decoration only: excluded
/// from semantics, since its row's label says the number. Takes theme colours,
/// and in the High contrast theme gets the outline other surfaces get there.
class ProportionBar extends StatelessWidget {
  const ProportionBar({super.key, required this.fraction});

  final double fraction;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final highContrast =
        (AppThemeScope.maybeOf(context)?.isHighContrast ?? false) ||
        MediaQuery.highContrastOf(context);
    return ExcludeSemantics(
      child: Container(
        height: 8,
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest,
          border: highContrast
              ? Border.all(color: scheme.outline, width: 1.5)
              : null,
          borderRadius: AppShapes.borderRadiusSmall,
        ),
        clipBehavior: Clip.antiAlias,
        alignment: AlignmentDirectional.centerStart,
        child: FractionallySizedBox(
          widthFactor: fraction.clamp(0.0, 1.0),
          heightFactor: 1,
          child: ColoredBox(color: scheme.primary),
        ),
      ),
    );
  }
}

class _ChipGroup extends StatelessWidget {
  const _ChipGroup({required this.label, required this.children});

  final String label;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Semantics(
    container: true,
    label: label,
    child: Wrap(
      spacing: AppSpacing.xs,
      runSpacing: AppSpacing.xxs,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        ExcludeSemantics(
          child: Text(label, style: Theme.of(context).textTheme.labelLarge),
        ),
        ...children,
      ],
    ),
  );
}

class _SubHeader extends StatelessWidget {
  const _SubHeader(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Semantics(
    header: true,
    child: Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        AppSpacing.md,
        AppSpacing.sm,
        AppSpacing.md,
        AppSpacing.xxs,
      ),
      child: Text(text, style: Theme.of(context).textTheme.titleSmall),
    ),
  );
}

class _Note extends StatelessWidget {
  const _Note(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(
      horizontal: AppSpacing.md,
      vertical: AppSpacing.xs,
    ),
    child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
  );
}

class _ShowMore extends StatelessWidget {
  const _ShowMore({
    super.key,
    required this.expanded,
    required this.count,
    required this.onPressed,
  });

  final bool expanded;
  final int count;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        child: TextButton(
          onPressed: onPressed,
          child: Text(
            expanded ? l10n.repertoireShowFewer : l10n.repertoireShowAll(count),
          ),
        ),
      ),
    );
  }
}
