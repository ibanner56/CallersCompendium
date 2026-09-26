import 'package:compendium_core/compendium_core.dart';

import 'package:compendium_app/src/data/collection_facets_scope.dart';
import 'package:compendium_app/src/search/collection_query.dart';

/// One selection per built-in filter section, with the getter that says it is
/// held. Kept table-driven so a section added to [CollectionFacetIds] without a
/// row here fails the coverage check below.
final builtInFacetSelections =
    <
      String,
      ({
        void Function(FacetSelections) select,
        bool Function(FacetSelections) held,
      })
    >{
      CollectionFacetIds.form: (
        select: (f) => f.forms.add(DanceForm.contra),
        held: (f) => f.forms.isNotEmpty,
      ),
      CollectionFacetIds.formation: (
        select: (f) => f.formations.add(FormationShape.becketCw),
        held: (f) => f.formations.isNotEmpty,
      ),
      CollectionFacetIds.progression: (
        select: (f) => f.progressions.add(Progression.single),
        held: (f) => f.progressions.isNotEmpty,
      ),
      CollectionFacetIds.status: (
        select: (f) => f.statuses.add(DanceStatus.draft),
        held: (f) => f.statuses.isNotEmpty,
      ),
      CollectionFacetIds.level: (
        select: (f) => f.levels.add('level-1'),
        held: (f) => f.levels.isNotEmpty,
      ),
      CollectionFacetIds.mixedLevel: (
        select: (f) => f.mixedLevel = false,
        held: (f) => f.mixedLevel != null,
      ),
      CollectionFacetIds.mixer: (
        select: (f) => f.mixer = true,
        held: (f) => f.mixer != null,
      ),
      CollectionFacetIds.minRating: (
        select: (f) => f.minRating = 3,
        held: (f) => f.minRating != null,
      ),
      CollectionFacetIds.callStatus: (
        select: (f) => f.callStatuses.add(false),
        held: (f) => f.callStatuses.isNotEmpty,
      ),
      CollectionFacetIds.author: (
        select: (f) => f.authorIds.add('a1'),
        held: (f) => f.authorIds.isNotEmpty,
      ),
      CollectionFacetIds.tags: (
        select: (f) => f.tagIds.add('t1'),
        held: (f) => f.tagIds.isNotEmpty,
      ),
      CollectionFacetIds.source: (
        select: (f) => f.sourceIds.add('s1'),
        held: (f) => f.sourceIds.isNotEmpty,
      ),
    };
