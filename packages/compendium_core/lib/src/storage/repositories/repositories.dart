import '../../taxonomy/taxonomy.dart';
import '../database.dart';
import 'choreographer_repository.dart';
import 'custom_field_repository.dart';
import 'dance_repository.dart';
import 'program_repository.dart';
import 'settings_repository.dart';
import 'snapshot_repository.dart';
import 'tag_repository.dart';

/// Bundles every repository over a single [CompendiumDatabase], so app code
/// wires up storage once (`CompendiumRepositories(db, taxonomy)`) instead of
/// constructing each repository individually.
class CompendiumRepositories {
  CompendiumRepositories(this.db, Taxonomy taxonomy)
    : dances = DanceRepository(db, taxonomy),
      choreographers = ChoreographerRepository(db),
      tags = TagRepository(db),
      customFieldDefs = CustomFieldDefRepository(db),
      programs = ProgramRepository(db),
      settings = SettingsRepository(db),
      snapshots = SnapshotRepository(db);

  final CompendiumDatabase db;
  final DanceRepository dances;
  final ChoreographerRepository choreographers;
  final TagRepository tags;
  final CustomFieldDefRepository customFieldDefs;
  final ProgramRepository programs;
  final SettingsRepository settings;
  final SnapshotRepository snapshots;
}
