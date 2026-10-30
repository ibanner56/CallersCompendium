import 'dart:async';

import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/foundation.dart';

/// One row of the Calling history section's venue chooser: a venue with at
/// least one counted call (`docs/design/history-filters.md`, N1-H2).
@immutable
class VenueChoice {
  const VenueChoice({
    required this.key,
    required this.label,
    required this.programCount,
  });

  /// The `CalledFilter.venue` this row selects.
  final VenueKey key;

  /// What the row says: the linked record's name, else the most recent typed
  /// text. Empty only for a record key whose record is gone and whose programs
  /// carry no typed text; the chooser shows a placeholder then.
  final String label;

  /// How many programs at this venue have a counted call.
  final int programCount;

  /// Whether this is a typed venue with no linked record. Typed "Grange" and a
  /// saved "Grange" are separate venues until the old programs are linked
  /// (N1-1), so the chooser marks the typed one.
  bool get typed => key.typedVenue != null;

  @override
  bool operator ==(Object other) =>
      other is VenueChoice &&
      other.key == key &&
      other.label == label &&
      other.programCount == programCount;

  @override
  int get hashCode => Object.hash(key, label, programCount);
}

/// Where the venue chooser reads its rows: the venues with a counted call
/// under one calling-history scope. Value-equal when it would read the same
/// rows, so a host can build a fresh one on every rebuild and the chooser
/// resubscribes only when the scope really changed.
@immutable
class VenueChoiceSource {
  const VenueChoiceSource({
    required this.repos,
    this.callerFilter,
    this.performedOnly = false,
    this.requireEventDate = false,
  });

  final CompendiumRepositories repos;

  /// The Collection's resolved caller scope, as `CollectionData.callerFilter`.
  final String? callerFilter;
  final bool performedOnly;
  final bool requireEventDate;

  /// The venues with a counted call, newest call first, live: it re-emits
  /// when programs, slots or venues change. The scope arguments are exactly
  /// what the `CalledFilter` of the same search gets, so a row here is a venue
  /// the filter can match.
  Stream<List<VenueChoice>> watch() {
    late final StreamController<List<VenueChoice>> controller;
    StreamSubscription<List<CalledVenue>>? calledSub;
    StreamSubscription<List<Venue>>? venuesSub;
    List<CalledVenue>? called;
    Map<String, String>? names;

    void emit() {
      final rows = called;
      final byId = names;
      if (rows == null || byId == null || controller.isClosed) return;
      controller.add([
        for (final venue in rows)
          VenueChoice(
            key: venue.key,
            label:
                (venue.key.venueId == null ? null : byId[venue.key.venueId]) ??
                venue.latestVenueText ??
                '',
            programCount: venue.programCount,
          ),
      ]);
    }

    controller = StreamController<List<VenueChoice>>(
      onListen: () {
        calledSub = repos.programs
            .watchCalledVenues(
              performedOnly: performedOnly,
              requireEventDate: requireEventDate,
              callerFilter: callerFilter,
            )
            .listen((rows) {
              called = rows;
              emit();
            }, onError: controller.addError);
        venuesSub = repos.venues.watchAll().listen((venues) {
          names = {for (final v in venues) v.id: v.name};
          emit();
        }, onError: controller.addError);
      },
      onCancel: () async {
        await Future.wait([?calledSub?.cancel(), ?venuesSub?.cancel()]);
      },
    );
    return controller.stream;
  }

  @override
  bool operator ==(Object other) =>
      other is VenueChoiceSource &&
      identical(other.repos, repos) &&
      other.callerFilter == callerFilter &&
      other.performedOnly == performedOnly &&
      other.requireEventDate == requireEventDate;

  @override
  int get hashCode => Object.hash(
    identityHashCode(repos),
    callerFilter,
    performedOnly,
    requireEventDate,
  );
}
