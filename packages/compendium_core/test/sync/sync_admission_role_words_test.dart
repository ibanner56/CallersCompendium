// Dialect role canonicalisation is an input-side transform: the editor and the
// import scrub apply it before a value is stored. Device Sync admission must
// never re-run it, so a body that carries role words in any spelling — a
// verbatim "Larks", a verb "lead", the move name "mad robin", or an older
// client's `role1` — is admitted byte-for-byte. Changing the canonicaliser
// therefore needs no sync wire-version bump (sync-spec §4.1 reserves `v` for
// the JSON canonicalisation).
import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

import '../storage/fixtures.dart';

void main() {
  test('admission does not canonicalise role words in figure text', () {
    final dance = sampleDance(
      id: 'd1',
      figures: [
        Figure(
          move: 'custom',
          params: const {'text': 'Larks chain wide'},
          note: 'Ones lead down the hall',
        ),
        Figure(move: 'custom', params: const {'text': 'Mad robin twice'}),
        Figure(move: 'custom', params: const {'text': 'Ones role1 down'}),
        Figure(move: 'swing', note: 'follows wait'),
      ],
    );
    final stamp = dance.updatedAt;
    final body = syncBodyForEntity(SyncRecordKind.dance, dance);
    final admission = admitSyncInboundCandidate(
      SyncMergeCandidate(
        blob: SyncRecordBlob(
          kind: SyncRecordKind.dance,
          id: 'd1',
          updatedAt: stamp,
          deletedAt: null,
          existenceAt: stamp,
          body: body,
        ),
        peerId: 'peer-a',
      ),
    );
    expect(admission.report, isNull);
    expect(canonicalJson(admission.candidate!.blob.body), canonicalJson(body));
  });
}
