/// Runs the app's reload of its live preferences and controllers after a sync
/// pass wrote `settings` rows (#1828), so a preference changed on another
/// device shows here without a relaunch, and the next local edit of a
/// whole-collection setting does not write the stale collection back over the
/// peer's.
///
/// A reload only reads, so it is no local edit and schedules no pass of its
/// own. Requests that arrive while one runs are coalesced into one more run.
///
/// A local edit can race it: a controller sets its new value in memory, then
/// writes it, and a load whose read came before that write assigns the old
/// value over it — leaving memory stale while the database holds the edit.
/// The app reports every `settings` write through [noteSettingsWrite]; one
/// that lands while a run is in progress makes it run again. The [fence] read
/// that ends each run catches a write still queued when the loads finish: one
/// connection runs its statements in order, so that write completes before
/// the fence does, and Drift delivers its table-update event synchronously.
///
/// Re-runs for a race are bounded by [maxRacedRuns], so a load that one day
/// writes `settings` itself (the dialect library's one-time migration already
/// can) cannot spin. A run raced that many times in a row stops, leaving what
/// it raced to the next reload. A request is never dropped by that bound.
class SyncedSettingsReload {
  SyncedSettingsReload({
    required this._reload,
    required this._fence,
    this.maxRacedRuns = 3,
  });

  final Future<void> Function() _reload;
  final Future<void> Function() _fence;

  /// The most runs one call makes when only races, not requests, ask for more.
  final int maxRacedRuns;

  bool _running = false;
  bool _requested = false;
  bool _raced = false;

  /// Whether a run is in progress.
  bool get running => _running;

  /// Records a `settings` write seen on the change stream.
  void noteSettingsWrite() {
    if (_running) _raced = true;
  }

  /// Reloads, or, when a run is in progress, asks it for one more. The
  /// returned future completes when this call's runs are done; a coalesced
  /// request returns at once.
  Future<void> request() async {
    if (_running) {
      _requested = true;
      return;
    }
    _running = true;
    try {
      var runs = 0;
      do {
        _requested = false;
        _raced = false;
        await _reload();
        await _fence();
        runs++;
      } while (_requested || (_raced && runs < maxRacedRuns));
    } finally {
      _running = false;
    }
  }
}
