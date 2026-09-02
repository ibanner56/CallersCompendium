<!-- generated-by: packages/compendium_core/tool/generate_data_classification_doc.dart
     source: packages/compendium_core/lib/src/privacy/field_registry.dart
     The field-catalogue table below is generated; the surrounding prose is
     hand-written. Read the registry, not this rendering. -->

# Data classification catalogue

Every field Caller's Compendium persists, classified by what kind of data it is,
whose data it is, and whether it may leave the device.

This exists to answer one question mechanically: **may this field be
transmitted?** Before it, the answer lived in prose — a doc comment on
`Choreographer` said its `email` and `location` "MUST NOT be emitted in any
shareable export", nothing enforced it, and the same question had no answer at
all for the 22 columns of `venues`.

## The registry is the source of truth

The catalogue lives in [`field_registry.dart`][registry], not in this file. This
document is **generated** from it. Code that decides whether a field may be
transmitted reads [`EgressClass`][types] from the registry rather than carrying
its own allow-list, so there is exactly one place to change and no second list
to drift out of sync.

[registry]: ../../packages/compendium_core/lib/src/privacy/field_registry.dart
[types]: ../../packages/compendium_core/lib/src/privacy/data_classification.dart

## If you are adding a field

**Any new column, settings key, or data-entry surface must be classified in the
same pull request that introduces it.** This is not optional and it is not a
follow-up: `data_classification_coverage_test.dart` fails on an unclassified
column, and CI will stop you.

1. Add the column as usual.
2. Add an entry to `fieldClassifications`, keyed `table.column` using the **SQL**
   names. For a settings key built at runtime from a prefix rather than
   declared as an exact `const String kSomethingKey`, add the prefix to
   `settingsPrefixClassifications` instead (see `kDanceEditorDraftKeyPrefix`
   for the pattern) — `classifySettingsKey` resolves the longest matching
   prefix.
3. Pick the three axes (below). If it is a close call, say why in the `note` —
   a reviewer should never have to guess why a personal-data field is
   `shareable`.
4. Regenerate this document:

   ```sh
   fvm dart run \
     packages/compendium_core/tool/generate_data_classification_doc.dart
   ```

5. Run the guards:

   ```sh
   (cd packages/compendium_core && fvm dart test test/privacy/)
   ```

If you are adding a whole new *table* — including a raw/virtual one that drift
does not type — declare it in `untypedTables` in the coverage test, or its
columns escape classification silently.

## The three axes

Each field carries three independent classifications. Keeping them independent
is deliberate: a field can be personal data *and* still be shareable, and the
catalogue should record that as a decision with a reason rather than imply it.

### 1. Category — what kind of data

W3C **Data Privacy Vocabulary (DPV) v2.3**, pinned. See [Vocabulary](#vocabulary).

### 2. Subject — whose data it is

| Value | Meaning |
| --- | --- |
| `none` | Not about a person: a dance's title, a figure's beat count |
| `appUser` | About the person using the app |
| `thirdParty` | About someone who does not use the app and has no relationship with it — a venue's contact, a choreographer, a caller billed on a program |

**No published taxonomy supplies this axis, and it is the one that matters most
here.** DPV, GDPR and both app-store vocabularies assume the data subject is the
person using the app. In this app the sensitive data is overwhelmingly about
people who have never touched it and cannot consent to a transfer they do not
know exists.

### 3. Egress — whether it may leave, and how

| Value | Meaning |
| --- | --- |
| `shareable` | May travel by any route the user chooses, including project-operated infrastructure: file export, share sheet, device sync |
| `deviceLocal` | Must never reach project-operated infrastructure. Leaves only by a transfer the user deliberately initiates between their own devices, or in a local backup file they control |
| `deviceScoped` | Never transmitted **by any route at all**, because the value is meaningless or actively wrong on another device — a window position, a per-device marker, a per-installation key. Distinct from `deviceLocal`: that is withheld for what it *contains*, this for what it *means*. |
| `protocolIdentifier` | May travel as opaque protocol metadata to the configured endpoint, but carries no user data and is never adopted from a peer — here, the per-installation sync device ID |
| `accessControlData` | May travel only as the authorization for the configured endpoint, but is never recoverably retained, logged, or adopted — here, the sync ID bearer credential |
| `derived` | Never transmitted at all. Rebuildable from other fields on arrival, so sending it would be redundant as well as an extra copy to protect |

## Vocabulary

Categories use the [W3C Data Privacy Vocabulary][dpv] (DPV) **v2.3**, pinned to
that version. Namespaces:

- `pd:` — <https://w3id.org/dpv/pd#>, personal data categories
- `dpv:` — <https://w3id.org/dpv#>, core vocabulary
- `cc:` — house terms, defined here, for the two things DPV has no word for

[dpv]: https://w3c-cg.github.io/dpv/2.3/dpv/

DPV is a W3C Community Group Report published under the [W3C Software and
Document License 2023][w3c-license], which permits copying, modifying and
distributing its material without fee, with attribution. Portions of this
catalogue's category names and definitions derive from DPV v2.3, © the
respective W3C Community Group participants.

[w3c-license]: https://www.w3.org/copyright/software-license-2023/

### Path rendering

DPV's top-level buckets are omitted when a path is rendered here. `Tracking`
sits above `Contact`, and `External` above `Identifying` — container names that
mislead a reader of these docs more than they inform. An app whose headline
promise is that it does no tracking should not print a table filing a venue's
city under `Tracking`. Leaf terms and their meaningful ancestors are kept
verbatim, so the mapping back to DPV stays exact.

### House terms

DPV v2.3 has no term for either of these; both were checked against all 235
`pd:` terms in the published vocabulary.

| Term | Meaning |
| --- | --- |
| `cc:DeceasedFlag` | Whether a person is deceased. Ordinary personal data under GDPR Art. 4(1), not an Art. 9 special category — but about someone who cannot exercise any rights over it |
| `cc:WebsiteUrl` | A website URL. Names an organisation's public page far more often than an individual's, so it is **not** treated as personal data |

DPV explicitly sanctions this: its personal-data extension is published
separately so that adopters may use other vocabularies or define their own.

## Why DPV, and not the alternatives

Recorded because the first choice was reversed, and the reasoning should outlive
the people who were in the room.

**ISO/IEC 19944-1:2020** was chosen first and rejected. Its abstract does confirm
it "provides foundational concepts, including a data taxonomy" — but the
category names could not be obtained from any public source: not ISO's Online
Browsing Platform (a JavaScript shell), not the EU Cloud Code of Conduct or
SWIPO (both domains defunct), not ITU-T, ETSI or CEN, not any national body
preview, and not any accessible paper. It is also framed, in its own words, as
"applicable primarily to cloud service providers, cloud service customers and
cloud service users" — a taxonomy for data a provider processes on a customer's
behalf, which is structurally backwards for a local-first app. The deciding
argument was neither of those: **we ask outside contributors to tag every field
they add, and a vocabulary nobody can read without buying it is a rule nobody
can check.**

**App-store categories** (Apple's privacy nutrition labels, Google Play Data
Safety) were rejected as the primary vocabulary because they classify
*collection*, and Apple defines collection as transmission: "'Collect' refers to
transmitting data off the device in a way that allows you and/or your
third-party partners to access it for a period longer than what is necessary to
service the transmitted request in real time." Nothing leaves the device today,
so every field would be tagged "Not collected" — one constant value across the
whole catalogue. Worth revisiting as an *additional* column if sync ships, at
which point the catalogue and the store declarations become one artefact.

**GDPR Art. 4(1) / Art. 9** was rejected as the primary vocabulary because it
collapses to two values, and every field we care about lands in the same one.
None of our fields is an Art. 9 special category. It remains the right citation
for the legal line, and for the `cc:DeceasedFlag` note above.

**NIST Privacy Framework** classifies activities rather than data types, so it
supplies no vocabulary for this table.

## Decisions on record

Contested classifications, and who made the call. Recorded so a later reader can
tell an approved decision from an assumed one.

| Decision | Ruled by | Reasoning |
| --- | --- | --- |
| Performer names (`programs.caller`, `programs.band`, `program_slots.guest_caller`) are shareable | Maintainer | A program without its caller and band is useless, and event billing is already public |
| All notes fields are shareable, including those on person and place records | Maintainer | They are the user's own words about their own collection |
| `custom_field_values.value_text` is shareable | Maintainer | Custom fields are core collection data. Two obligations attached: (1) creating a custom field shows a one-time disclosure that its contents travel with exports — shipped in #780; (2) per-field exclusion from sharing via `custom_field_defs.shareable` — also shipped in #780; the archive encoder omits non-shareable defs and their values entirely |
| `venues.sponsor` is shareable | Maintainer | A sponsor is an organisation by intent and part of the venue's public identity |
| Venue identity (`name`, `website`, `event_name`, schedule, time, price) is shareable while the address block and contacts are device-local | Agent, ratified by maintainer | Lets a program stay readable after a transfer without moving the address book |
| `provenance.raw_payload` and `program_provenance.raw_payload` were **dropped** at schema v21 | Maintainer | Classified device-local when this catalogue was written, then removed entirely (#781). Nothing ever read either column; the program-side one was never even written. For an HTML import the dance-side column stored the whole source page — 7,492 bytes for this repo's own ContraDB fixture — per dance, round-tripping through every backup. Dropping deletes data irreversibly, which was the explicit trade accepted: unreadable data is not worth carrying forever |
| DPV top-level buckets are omitted from rendered paths | Maintainer ruled on `Tracking`; agent extended it to `External` | Same reasoning — an uninformative bucket name. The `External` extension is reversible |
| `choreographers.name` stays **third-party personal data** rather than being reclassified as published attribution metadata | Maintainer | Challenged directly: does every library treat every author name as personal data about a third party? Not every library has published an analysis, but the ones that have all land this way, and none of them get there by denying the data is personal. The National Library of Scotland's [privacy notice for catalogue records](https://www.nls.uk/privacy/catalogue-records/) states that bibliographic and NACO name-authority records contain personal data about authors, claims a lawful basis of "a task carried out in the public interest", grants the author a **right of objection**, and discloses the onward transfer to the Library of Congress. GDPR has no public-availability exemption, so publication is a lawful-basis question, not a classification one. Keeping `thirdParty` costs no behaviour — `egress` is already `shareable` — and it is what keeps `email` and `location` on the same person coherent. Narrow exclusions that genuinely are not personal data: a deceased author (GDPR Recital 27), and a name that identifies no natural person, such as a band or an untraceable pseudonym |

## Known limitations

- **Settings values are classified at the column, not the key.** `settings` is a
  key/value store, so `settings.value_json` is marked device-local at this layer
  to make a blanket sync of the settings table impossible by accident. Per-key
  classification is a separate registry in `packages/compendium_core`
  (`settings_registry.dart`), covering both keys declared as an exact constant
  and keys built at runtime from a declared prefix (`editor_draft:<id>`).
- **The catalogue classifies storage, not display.** A field marked
  `deviceLocal` can still be rendered on screen, printed, or copied by the user.
  This is a transmission boundary, not an access-control system.
- **Freeform fields are classified by intent, not by content.** A user who types
  a phone number into a dance's calling notes has put contact data into a
  `shareable` field, and nothing detects that. The rulings above accept this
  knowingly.

<!-- BEGIN GENERATED: field-catalogue -->

_Generated from `lib/src/privacy/field_registry.dart` and
`lib/src/privacy/settings_registry.dart`. Do not edit this block
by hand — run:_

```sh
fvm dart run packages/compendium_core/tool/generate_data_classification_doc.dart
```

### Database columns

**210 columns**: 139 shareable, 21 device-local, 25 device-scoped, 25 derived. 26 personal data by category.

| Table | Column | Category | Path | Subject | Egress | Why |
| --- | --- | --- | --- | --- | --- | --- |
| `baseline_entries` | `body_hash` | `dpv:NonPersonalData` | NonPersonalData | — | device-scoped | Device Sync bookkeeping; never exported or synchronized. |
| `baseline_entries` | `kind` | `dpv:NonPersonalData` | NonPersonalData | — | device-scoped | Device Sync bookkeeping; never exported or synchronized. |
| `baseline_entries` | `record_id` | `dpv:NonPersonalData` | NonPersonalData | — | device-scoped | Device Sync bookkeeping; never exported or synchronized. |
| `baseline_entries` | `wire_hash` | `dpv:NonPersonalData` | NonPersonalData | — | device-scoped | Device Sync bookkeeping; never exported or synchronized. |
| `baseline_state` | `epoch` | `dpv:NonPersonalData` | NonPersonalData | — | device-scoped | Device Sync bookkeeping; never exported or synchronized. |
| `baseline_state` | `id` | `dpv:NonPersonalData` | NonPersonalData | — | device-scoped | Device Sync bookkeeping; never exported or synchronized. |
| `choreographers` | `deceased` | `cc:DeceasedFlag` | DeceasedFlag | third party | **device-local** | Personal data about someone who cannot exercise any rights over it. |
| `choreographers` | `deleted_at` | `dpv:NonPersonalData` | NonPersonalData | — | shareable | Soft-delete tombstone; see dances.deleted_at. Must travel, or a peer that has not synced recently resurrects a deleted record. Added to this kind in #898. |
| `choreographers` | `email` | `pd:EmailAddress` | Contact → EmailAddress | third party | **device-local** | Private contact data for someone who does not use this app. This registry replaces the prose rule that lived on Choreographer.email. |
| `choreographers` | `existence_at` | `dpv:NonPersonalData` | NonPersonalData | — | shareable | Existence-transition stamp. A bare timestamp with no data subject; must travel or a receiver cannot decide which of two disagreeing copies is the later existence decision, and deletions resurrect. Added in #898. |
| `choreographers` | `id` | `dpv:NonPersonalData` | NonPersonalData | — | shareable | Opaque identifier; meaningless alone, required for relational integrity across a transfer. |
| `choreographers` | `location` | `pd:Locality` | Contact → PhysicalAddress → Locality | third party | **device-local** | Freeform locality, e.g. "Portland, OR". |
| `choreographers` | `name` | `pd:Name` | Identifying → Name | third party | shareable | Personal data about a third party, shareable deliberately: authorship credit is the reason the field exists, and it is already published wherever the dance is published. Publication is why we may carry it, not a reason it stops being personal data — the same position library catalogues take on author names. See "Decisions on record" in docs/dev/data-classification.md for the citation. |
| `choreographers` | `notes` | `dpv:PersonalData` | PersonalData | third party | shareable | Unbounded freeform text attached to a person, place or source. Personal data by category, shareable by decision (maintainer ruling: this is the user's own commentary on their own collection). May incidentally contain contact details the user typed there. |
| `choreographers` | `updated_at` | `dpv:NonPersonalData` | NonPersonalData | — | shareable | Record stamp, not author-supplied. Required for ordering across devices. |
| `choreographers` | `website` | `cc:WebsiteUrl` | WebsiteUrl | third party | shareable | A public page the author chose to publish. |
| `collection_import_events` | `archive_digest` | `dpv:NonPersonalData` | NonPersonalData | app user | **device-local** | The digest identifies the specific published archive the app user imported and is retained only as local import history. |
| `collection_import_events` | `collection_id` | `dpv:NonPersonalData` | NonPersonalData | app user | **device-local** | Published collection import history reveals the app user’s interests; it is not collection content and must remain on this device. |
| `collection_import_events` | `imported_at` | `dpv:NonPersonalData` | NonPersonalData | app user | **device-local** | The timestamp records the app user’s import activity and is retained only as local import history. |
| `collection_import_events` | `version` | `dpv:NonPersonalData` | NonPersonalData | app user | **device-local** | Published collection import history reveals the app user’s interests; it is not collection content and must remain on this device. |
| `custom_field_defs` | `choices_json` | `dpv:NonPersonalData` | NonPersonalData | — | shareable |  |
| `custom_field_defs` | `deleted_at` | `dpv:NonPersonalData` | NonPersonalData | — | shareable | Soft-delete tombstone; see dances.deleted_at. Must travel, or a peer that has not synced recently resurrects a deleted record. Added to this kind in #898. |
| `custom_field_defs` | `existence_at` | `dpv:NonPersonalData` | NonPersonalData | — | shareable | Existence-transition stamp. A bare timestamp with no data subject; must travel or a receiver cannot decide which of two disagreeing copies is the later existence decision, and deletions resurrect. Added in #898. |
| `custom_field_defs` | `id` | `dpv:NonPersonalData` | NonPersonalData | — | shareable | Opaque identifier; meaningless alone, required for relational integrity across a transfer. |
| `custom_field_defs` | `key` | `dpv:NonPersonalData` | NonPersonalData | — | shareable |  |
| `custom_field_defs` | `label` | `dpv:NonPersonalData` | NonPersonalData | — | shareable |  |
| `custom_field_defs` | `searchable` | `dpv:NonPersonalData` | NonPersonalData | — | shareable |  |
| `custom_field_defs` | `shareable` | `dpv:NonPersonalData` | NonPersonalData | — | shareable | Per-field flag: whether this field and its values may travel in a shared archive. Classified shareable because the flag is carried on the defs that *are* emitted in share mode and is preserved in the owner's full-fidelity backup mode. Share mode omits definitions whose flag is false and their values; backup mode includes both so restore can reproduce the setting. This is the only field that directly controls egress of another field (custom_field_values.value_text). Added in #780; backup preservation fixed in #1037. |
| `custom_field_defs` | `show_in_list` | `dpv:NonPersonalData` | NonPersonalData | — | shareable |  |
| `custom_field_defs` | `type` | `dpv:NonPersonalData` | NonPersonalData | — | shareable |  |
| `custom_field_defs` | `updated_at` | `dpv:NonPersonalData` | NonPersonalData | — | shareable | Record stamp, not author-supplied. Required for ordering across devices. |
| `custom_field_values` | `dance_id` | `dpv:NonPersonalData` | NonPersonalData | — | shareable | Opaque identifier; meaningless alone, required for relational integrity across a transfer. |
| `custom_field_values` | `field_id` | `dpv:NonPersonalData` | NonPersonalData | — | shareable | Opaque identifier; meaningless alone, required for relational integrity across a transfer. |
| `custom_field_values` | `value_num` | `dpv:NonPersonalData` | NonPersonalData | — | shareable |  |
| `custom_field_values` | `value_text` | `dpv:NonPersonalData` | NonPersonalData | — | shareable | Holds either unbounded free text or a user-defined choice value, for a field the user invented and named. Shareable by maintainer ruling: custom fields are core collection data. Egress in share mode is conditional on the field definition's shareable flag (custom_field_defs.shareable, added in #780): when shareable = false, neither this field def nor its values are emitted. Full-fidelity backup mode preserves the field and values regardless of that flag so restore does not lose owner data (fixed in #1037). The one-time disclosure notice on field creation (obligation 1) and the per-field exclusion control (obligation 2) were both implemented in #780. |
| `dance_authors` | `choreographer_id` | `dpv:NonPersonalData` | NonPersonalData | — | shareable | Opaque identifier; meaningless alone, required for relational integrity across a transfer. |
| `dance_authors` | `dance_id` | `dpv:NonPersonalData` | NonPersonalData | — | shareable | Opaque identifier; meaningless alone, required for relational integrity across a transfer. |
| `dance_authors` | `position` | `dpv:NonPersonalData` | NonPersonalData | — | shareable |  |
| `dance_figures` | `beats` | `dpv:NonPersonalData` | NonPersonalData | — | derived | Rebuilt from authoritative columns on write; recomputed on arrival. |
| `dance_figures` | `canonical_text` | `dpv:NonPersonalData` | NonPersonalData | — | derived | Rebuilt from authoritative columns on write; recomputed on arrival. |
| `dance_figures` | `dance_id` | `dpv:NonPersonalData` | NonPersonalData | — | derived | Rebuilt from authoritative columns on write; recomputed on arrival. |
| `dance_figures` | `group_idx` | `dpv:NonPersonalData` | NonPersonalData | — | derived | Rebuilt from authoritative columns on write; recomputed on arrival. |
| `dance_figures` | `idx` | `dpv:NonPersonalData` | NonPersonalData | — | derived | Rebuilt from authoritative columns on write; recomputed on arrival. |
| `dance_figures` | `move` | `dpv:NonPersonalData` | NonPersonalData | — | derived | Rebuilt from authoritative columns on write; recomputed on arrival. |
| `dance_figures` | `params_json` | `dpv:NonPersonalData` | NonPersonalData | — | derived | Rebuilt from authoritative columns on write; recomputed on arrival. |
| `dance_figures` | `progression` | `dpv:NonPersonalData` | NonPersonalData | — | derived | Rebuilt from authoritative columns on write; recomputed on arrival. |
| `dance_figures` | `section` | `dpv:NonPersonalData` | NonPersonalData | — | derived | Rebuilt from authoritative columns on write; recomputed on arrival. |
| `dance_fts` | `authors` | `dpv:NonPersonalData` | NonPersonalData | — | derived | Rebuilt from authoritative columns on write; recomputed on arrival. |
| `dance_fts` | `custom_values` | `dpv:NonPersonalData` | NonPersonalData | — | derived | Rebuilt from authoritative columns on write; recomputed on arrival. |
| `dance_fts` | `dance_id` | `dpv:NonPersonalData` | NonPersonalData | — | derived | Rebuilt from authoritative columns on write; recomputed on arrival. |
| `dance_fts` | `figures_text` | `dpv:NonPersonalData` | NonPersonalData | — | derived | Rebuilt from authoritative columns on write; recomputed on arrival. |
| `dance_fts` | `hook` | `dpv:NonPersonalData` | NonPersonalData | — | derived | Rebuilt from authoritative columns on write; recomputed on arrival. |
| `dance_fts` | `notes` | `dpv:NonPersonalData` | NonPersonalData | — | derived | Rebuilt from authoritative columns on write; recomputed on arrival. |
| `dance_fts` | `sources` | `dpv:NonPersonalData` | NonPersonalData | — | derived | Rebuilt from authoritative columns on write; recomputed on arrival. |
| `dance_fts` | `title` | `dpv:NonPersonalData` | NonPersonalData | — | derived | Rebuilt from authoritative columns on write; recomputed on arrival. |
| `dance_links` | `dance_id` | `dpv:NonPersonalData` | NonPersonalData | — | shareable | Opaque identifier; meaningless alone, required for relational integrity across a transfer. |
| `dance_links` | `id` | `dpv:NonPersonalData` | NonPersonalData | — | shareable | Opaque identifier; meaningless alone, required for relational integrity across a transfer. |
| `dance_links` | `kind` | `dpv:NonPersonalData` | NonPersonalData | — | shareable |  |
| `dance_links` | `label` | `dpv:NonPersonalData` | NonPersonalData | — | shareable |  |
| `dance_links` | `target_dance_id` | `dpv:NonPersonalData` | NonPersonalData | — | shareable | Opaque identifier; meaningless alone, required for relational integrity across a transfer. |
| `dance_links` | `transitive` | `dpv:NonPersonalData` | NonPersonalData | — | shareable |  |
| `dance_links` | `url` | `cc:WebsiteUrl` | WebsiteUrl | — | shareable | Citation or video link attached to a dance. |
| `dance_sources` | `dance_id` | `dpv:NonPersonalData` | NonPersonalData | — | shareable | Opaque identifier; meaningless alone, required for relational integrity across a transfer. |
| `dance_sources` | `number` | `dpv:NonPersonalData` | NonPersonalData | — | shareable |  |
| `dance_sources` | `page` | `dpv:NonPersonalData` | NonPersonalData | — | shareable |  |
| `dance_sources` | `position` | `dpv:NonPersonalData` | NonPersonalData | — | shareable |  |
| `dance_sources` | `source_id` | `dpv:NonPersonalData` | NonPersonalData | — | shareable | Opaque identifier; meaningless alone, required for relational integrity across a transfer. |
| `dance_substring_fts` | `authors` | `dpv:NonPersonalData` | NonPersonalData | — | derived | Rebuilt from authoritative columns on write; recomputed on arrival. |
| `dance_substring_fts` | `custom_values` | `dpv:NonPersonalData` | NonPersonalData | — | derived | Rebuilt from authoritative columns on write; recomputed on arrival. |
| `dance_substring_fts` | `dance_id` | `dpv:NonPersonalData` | NonPersonalData | — | derived | Rebuilt from authoritative columns on write; recomputed on arrival. |
| `dance_substring_fts` | `figures_text` | `dpv:NonPersonalData` | NonPersonalData | — | derived | Rebuilt from authoritative columns on write; recomputed on arrival. |
| `dance_substring_fts` | `hook` | `dpv:NonPersonalData` | NonPersonalData | — | derived | Rebuilt from authoritative columns on write; recomputed on arrival. |
| `dance_substring_fts` | `notes` | `dpv:NonPersonalData` | NonPersonalData | — | derived | Rebuilt from authoritative columns on write; recomputed on arrival. |
| `dance_substring_fts` | `sources` | `dpv:NonPersonalData` | NonPersonalData | — | derived | Rebuilt from authoritative columns on write; recomputed on arrival. |
| `dance_substring_fts` | `title` | `dpv:NonPersonalData` | NonPersonalData | — | derived | Rebuilt from authoritative columns on write; recomputed on arrival. |
| `dance_tags` | `dance_id` | `dpv:NonPersonalData` | NonPersonalData | — | shareable | Opaque identifier; meaningless alone, required for relational integrity across a transfer. |
| `dance_tags` | `tag_id` | `dpv:NonPersonalData` | NonPersonalData | — | shareable | Opaque identifier; meaningless alone, required for relational integrity across a transfer. |
| `dances` | `calling_notes` | `dpv:NonPersonalData` | NonPersonalData | — | shareable |  |
| `dances` | `composed_on` | `dpv:NonPersonalData` | NonPersonalData | — | shareable |  |
| `dances` | `created_at` | `dpv:NonPersonalData` | NonPersonalData | — | shareable | Record stamp, not author-supplied. Required for ordering across devices. |
| `dances` | `deleted_at` | `dpv:NonPersonalData` | NonPersonalData | — | shareable | Soft-delete tombstone. Must travel, or a device that has not synced recently will resurrect a dance the user deleted elsewhere. |
| `dances` | `existence_at` | `dpv:NonPersonalData` | NonPersonalData | — | shareable | Existence-transition stamp. A bare timestamp with no data subject; must travel or a receiver cannot decide which of two disagreeing copies is the later existence decision, and deletions resurrect. Added in #898. |
| `dances` | `figures_json` | `dpv:NonPersonalData` | NonPersonalData | — | shareable |  |
| `dances` | `form` | `dpv:NonPersonalData` | NonPersonalData | — | shareable |  |
| `dances` | `formation_detail` | `dpv:NonPersonalData` | NonPersonalData | — | shareable |  |
| `dances` | `formation_shape` | `dpv:NonPersonalData` | NonPersonalData | — | shareable |  |
| `dances` | `hook` | `dpv:NonPersonalData` | NonPersonalData | — | shareable |  |
| `dances` | `id` | `dpv:NonPersonalData` | NonPersonalData | — | shareable | Opaque identifier; meaningless alone, required for relational integrity across a transfer. |
| `dances` | `level` | `dpv:NonPersonalData` | NonPersonalData | — | shareable |  |
| `dances` | `mixed_level` | `dpv:NonPersonalData` | NonPersonalData | — | shareable |  |
| `dances` | `mixer` | `dpv:NonPersonalData` | NonPersonalData | — | shareable |  |
| `dances` | `phrase_structure` | `dpv:NonPersonalData` | NonPersonalData | — | shareable |  |
| `dances` | `progression` | `dpv:NonPersonalData` | NonPersonalData | — | shareable |  |
| `dances` | `rating` | `dpv:NonPersonalData` | NonPersonalData | — | shareable |  |
| `dances` | `revised_on` | `dpv:NonPersonalData` | NonPersonalData | — | shareable |  |
| `dances` | `status` | `dpv:NonPersonalData` | NonPersonalData | — | shareable |  |
| `dances` | `title` | `dpv:NonPersonalData` | NonPersonalData | — | shareable |  |
| `dances` | `tunes_json` | `dpv:NonPersonalData` | NonPersonalData | — | shareable |  |
| `dances` | `updated_at` | `dpv:NonPersonalData` | NonPersonalData | — | shareable | Record stamp, not author-supplied. Required for ordering across devices. |
| `dances` | `walkthrough` | `dpv:NonPersonalData` | NonPersonalData | — | shareable |  |
| `id_aliases` | `kind` | `dpv:NonPersonalData` | NonPersonalData | — | device-scoped | Device Sync bookkeeping; never exported or synchronized. |
| `id_aliases` | `losing_id` | `dpv:NonPersonalData` | NonPersonalData | — | device-scoped | Device Sync bookkeeping; never exported or synchronized. |
| `id_aliases` | `surviving_id` | `dpv:NonPersonalData` | NonPersonalData | — | device-scoped | Device Sync bookkeeping; never exported or synchronized. |
| `normalisation_skips` | `column_name` | `dpv:NonPersonalData` | NonPersonalData | — | device-scoped | Local collision-repair bookkeeping; never exported or synchronized. |
| `normalisation_skips` | `record_id` | `dpv:NonPersonalData` | NonPersonalData | — | device-scoped | Local collision-repair bookkeeping; never exported or synchronized. |
| `normalisation_skips` | `table_name` | `dpv:NonPersonalData` | NonPersonalData | — | device-scoped | Local collision-repair bookkeeping; never exported or synchronized. |
| `pending_deletions` | `kind` | `dpv:NonPersonalData` | NonPersonalData | — | device-scoped | Device Sync bookkeeping; never exported or synchronized. |
| `pending_deletions` | `record_id` | `dpv:NonPersonalData` | NonPersonalData | — | device-scoped | Device Sync bookkeeping; never exported or synchronized. |
| `pending_deletions` | `tombstone_blob` | `dpv:PersonalData` | PersonalData | third party | shareable | Opaque serialized tombstone may contain third-party record content; shareable because pending deletion retransmits it to sync peers. |
| `pending_deletions` | `tombstone_hash` | `dpv:NonPersonalData` | NonPersonalData | — | device-scoped | Device Sync bookkeeping; never exported or synchronized. |
| `pending_deletions` | `tombstoned_at` | `dpv:NonPersonalData` | NonPersonalData | — | device-scoped | Device Sync bookkeeping; never exported or synchronized. |
| `program_provenance` | `external_id` | `dpv:NonPersonalData` | NonPersonalData | — | shareable |  |
| `program_provenance` | `imported_at` | `dpv:NonPersonalData` | NonPersonalData | — | shareable | Record stamp, not author-supplied. Required for ordering across devices. |
| `program_provenance` | `license` | `dpv:NonPersonalData` | NonPersonalData | — | shareable |  |
| `program_provenance` | `permission` | `dpv:NonPersonalData` | NonPersonalData | — | shareable |  |
| `program_provenance` | `program_id` | `dpv:NonPersonalData` | NonPersonalData | — | shareable | Opaque identifier; meaningless alone, required for relational integrity across a transfer. |
| `program_provenance` | `source` | `dpv:NonPersonalData` | NonPersonalData | — | shareable |  |
| `program_provenance` | `source_version` | `dpv:NonPersonalData` | NonPersonalData | — | shareable |  |
| `program_slots` | `dance_id` | `dpv:NonPersonalData` | NonPersonalData | — | shareable | Opaque identifier; meaningless alone, required for relational integrity across a transfer. |
| `program_slots` | `guest_caller` | `pd:Name` | Identifying → Name | third party | shareable | Performer credit for a public event. CONTESTED — see the performer-names section of docs/dev/data-classification.md. |
| `program_slots` | `id` | `dpv:NonPersonalData` | NonPersonalData | — | shareable | Opaque identifier; meaningless alone, required for relational integrity across a transfer. |
| `program_slots` | `is_alt` | `dpv:NonPersonalData` | NonPersonalData | — | shareable |  |
| `program_slots` | `performed_at` | `dpv:NonPersonalData` | NonPersonalData | — | shareable |  |
| `program_slots` | `planned_minutes` | `dpv:NonPersonalData` | NonPersonalData | — | shareable |  |
| `program_slots` | `position` | `dpv:NonPersonalData` | NonPersonalData | — | shareable |  |
| `program_slots` | `program_id` | `dpv:NonPersonalData` | NonPersonalData | — | shareable | Opaque identifier; meaningless alone, required for relational integrity across a transfer. |
| `program_slots` | `text` | `dpv:NonPersonalData` | NonPersonalData | — | shareable |  |
| `programs` | `band` | `pd:Name` | Identifying → Name | third party | shareable | Performer credit for a public event. CONTESTED — see the performer-names section of docs/dev/data-classification.md. |
| `programs` | `caller` | `pd:Name` | Identifying → Name | third party | shareable | Performer credit for a public event. CONTESTED — see the performer-names section of docs/dev/data-classification.md. |
| `programs` | `created_at` | `dpv:NonPersonalData` | NonPersonalData | — | shareable | Record stamp, not author-supplied. Required for ordering across devices. |
| `programs` | `dancer_level` | `dpv:NonPersonalData` | NonPersonalData | — | shareable |  |
| `programs` | `deleted_at` | `dpv:NonPersonalData` | NonPersonalData | — | shareable | Soft-delete tombstone; see dances.deleted_at. |
| `programs` | `event_date` | `dpv:NonPersonalData` | NonPersonalData | — | shareable |  |
| `programs` | `existence_at` | `dpv:NonPersonalData` | NonPersonalData | — | shareable | Existence-transition stamp. A bare timestamp with no data subject; must travel or a receiver cannot decide which of two disagreeing copies is the later existence decision, and deletions resurrect. Added in #898. |
| `programs` | `hide_alternates` | `dpv:NonPersonalData` | NonPersonalData | — | shareable |  |
| `programs` | `id` | `dpv:NonPersonalData` | NonPersonalData | — | shareable | Opaque identifier; meaningless alone, required for relational integrity across a transfer. |
| `programs` | `notes` | `dpv:NonPersonalData` | NonPersonalData | — | shareable |  |
| `programs` | `status` | `dpv:NonPersonalData` | NonPersonalData | — | shareable |  |
| `programs` | `title` | `dpv:NonPersonalData` | NonPersonalData | — | shareable |  |
| `programs` | `updated_at` | `dpv:NonPersonalData` | NonPersonalData | — | shareable | Record stamp, not author-supplied. Required for ordering across devices. |
| `programs` | `venue` | `dpv:NonPersonalData` | NonPersonalData | — | shareable | Free-text venue label, not an address. Coexists with venue_id. |
| `programs` | `venue_id` | `dpv:NonPersonalData` | NonPersonalData | — | shareable | Opaque identifier; meaningless alone, required for relational integrity across a transfer. |
| `provenance` | `dance_id` | `dpv:NonPersonalData` | NonPersonalData | — | shareable | Opaque identifier; meaningless alone, required for relational integrity across a transfer. |
| `provenance` | `external_id` | `dpv:NonPersonalData` | NonPersonalData | — | shareable |  |
| `provenance` | `imported_at` | `dpv:NonPersonalData` | NonPersonalData | — | shareable | Record stamp, not author-supplied. Required for ordering across devices. |
| `provenance` | `license` | `dpv:NonPersonalData` | NonPersonalData | — | shareable |  |
| `provenance` | `permission` | `dpv:NonPersonalData` | NonPersonalData | — | shareable |  |
| `provenance` | `source` | `dpv:NonPersonalData` | NonPersonalData | — | shareable |  |
| `provenance` | `source_version` | `dpv:NonPersonalData` | NonPersonalData | — | shareable |  |
| `published_records` | `kind` | `dpv:NonPersonalData` | NonPersonalData | — | device-scoped | Device Sync bookkeeping; never exported or synchronized. |
| `published_records` | `record_id` | `dpv:NonPersonalData` | NonPersonalData | — | device-scoped | Device Sync bookkeeping; never exported or synchronized. |
| `published_sources` | `author` | `pd:Name` | Identifying → Name | third party | shareable | Published authorship credit; public by definition. |
| `published_sources` | `deleted_at` | `dpv:NonPersonalData` | NonPersonalData | — | shareable | Soft-delete tombstone; see dances.deleted_at. Must travel, or a peer that has not synced recently resurrects a deleted record. Added to this kind in #898. |
| `published_sources` | `existence_at` | `dpv:NonPersonalData` | NonPersonalData | — | shareable | Existence-transition stamp. A bare timestamp with no data subject; must travel or a receiver cannot decide which of two disagreeing copies is the later existence decision, and deletions resurrect. Added in #898. |
| `published_sources` | `id` | `dpv:NonPersonalData` | NonPersonalData | — | shareable | Opaque identifier; meaningless alone, required for relational integrity across a transfer. |
| `published_sources` | `notes` | `dpv:PersonalData` | PersonalData | third party | shareable | Unbounded freeform text attached to a person, place or source. Personal data by category, shareable by decision (maintainer ruling: this is the user's own commentary on their own collection). May incidentally contain contact details the user typed there. |
| `published_sources` | `title` | `dpv:NonPersonalData` | NonPersonalData | — | shareable |  |
| `published_sources` | `updated_at` | `dpv:NonPersonalData` | NonPersonalData | — | shareable | Record stamp, not author-supplied. Required for ordering across devices. |
| `published_sources` | `url` | `cc:WebsiteUrl` | WebsiteUrl | — | shareable |  |
| `published_sources` | `year` | `dpv:NonPersonalData` | NonPersonalData | — | shareable |  |
| `review_queue` | `candidate_blob` | `dpv:PersonalData` | PersonalData | third party | device-scoped | Opaque serialized sync candidate may contain third-party record content; held locally until review and never synchronized as queue state. |
| `review_queue` | `candidate_hash` | `dpv:NonPersonalData` | NonPersonalData | — | device-scoped | Device Sync bookkeeping; never exported or synchronized. |
| `review_queue` | `counterpart_id` | `dpv:NonPersonalData` | NonPersonalData | — | device-scoped | Device Sync bookkeeping; never exported or synchronized. |
| `review_queue` | `kind` | `dpv:NonPersonalData` | NonPersonalData | — | device-scoped | Device Sync bookkeeping; never exported or synchronized. |
| `review_queue` | `queued_at` | `dpv:NonPersonalData` | NonPersonalData | — | device-scoped | Device Sync bookkeeping; never exported or synchronized. |
| `review_queue` | `reason` | `dpv:NonPersonalData` | NonPersonalData | — | device-scoped | Device Sync bookkeeping; never exported or synchronized. |
| `review_queue` | `record_id` | `dpv:NonPersonalData` | NonPersonalData | — | device-scoped | Device Sync bookkeeping; never exported or synchronized. |
| `settings` | `deleted_at` | `dpv:NonPersonalData` | NonPersonalData | — | shareable | Soft-delete tombstone; see dances.deleted_at. Must travel, or a peer that has not synced recently resurrects a deleted record. Added to this kind in #898. |
| `settings` | `existence_at` | `dpv:NonPersonalData` | NonPersonalData | — | shareable | Existence-transition stamp. A bare timestamp with no data subject; must travel or a receiver cannot decide which of two disagreeing copies is the later existence decision, and deletions resurrect. Added in #898. |
| `settings` | `key` | `dpv:NonPersonalData` | NonPersonalData | — | shareable | The settings table is a key/value store; classifying the column says nothing about an individual preference. Per-key classification lives in the app package. |
| `settings` | `updated_at` | `dpv:NonPersonalData` | NonPersonalData | — | shareable | Record stamp, not author-supplied. Required for ordering across devices. |
| `settings` | `value_json` | `dpv:NonPersonalData` | NonPersonalData | app user | **device-local** | Opaque JSON whose meaning depends on the key. Device-local at this layer so a blanket sync of the settings table cannot happen by accident; per-key rules decide what actually travels. |
| `tags` | `color` | `dpv:NonPersonalData` | NonPersonalData | — | shareable |  |
| `tags` | `deleted_at` | `dpv:NonPersonalData` | NonPersonalData | — | shareable | Soft-delete tombstone; see dances.deleted_at. Must travel, or a peer that has not synced recently resurrects a deleted record. Added to this kind in #898. |
| `tags` | `existence_at` | `dpv:NonPersonalData` | NonPersonalData | — | shareable | Existence-transition stamp. A bare timestamp with no data subject; must travel or a receiver cannot decide which of two disagreeing copies is the later existence decision, and deletions resurrect. Added in #898. |
| `tags` | `id` | `dpv:NonPersonalData` | NonPersonalData | — | shareable | Opaque identifier; meaningless alone, required for relational integrity across a transfer. |
| `tags` | `name` | `dpv:NonPersonalData` | NonPersonalData | — | shareable |  |
| `tags` | `updated_at` | `dpv:NonPersonalData` | NonPersonalData | — | shareable | Record stamp, not author-supplied. Required for ordering across devices. |
| `venue_provenance` | `external_id` | `dpv:NonPersonalData` | NonPersonalData | — | shareable |  |
| `venue_provenance` | `imported_at` | `dpv:NonPersonalData` | NonPersonalData | — | shareable | Record stamp, not author-supplied. Required for ordering across devices. |
| `venue_provenance` | `license` | `dpv:NonPersonalData` | NonPersonalData | — | shareable |  |
| `venue_provenance` | `permission` | `dpv:NonPersonalData` | NonPersonalData | — | shareable |  |
| `venue_provenance` | `source` | `dpv:NonPersonalData` | NonPersonalData | — | shareable |  |
| `venue_provenance` | `source_version` | `dpv:NonPersonalData` | NonPersonalData | — | shareable |  |
| `venue_provenance` | `venue_id` | `dpv:NonPersonalData` | NonPersonalData | — | shareable | Opaque identifier; meaningless alone, required for relational integrity across a transfer. |
| `venues` | `address1` | `pd:Street` | Contact → PhysicalAddress → Street | third party | **device-local** |  |
| `venues` | `address2` | `pd:Street` | Contact → PhysicalAddress → Street | third party | **device-local** |  |
| `venues` | `city` | `pd:City` | Contact → PhysicalAddress → City | third party | **device-local** |  |
| `venues` | `contact1_email` | `pd:EmailAddress` | Contact → EmailAddress | third party | **device-local** |  |
| `venues` | `contact1_name` | `pd:Name` | Identifying → Name | third party | **device-local** |  |
| `venues` | `contact1_phone` | `pd:TelephoneNumber` | Contact → TelephoneNumber | third party | **device-local** |  |
| `venues` | `contact2_email` | `pd:EmailAddress` | Contact → EmailAddress | third party | **device-local** |  |
| `venues` | `contact2_name` | `pd:Name` | Identifying → Name | third party | **device-local** |  |
| `venues` | `contact2_phone` | `pd:TelephoneNumber` | Contact → TelephoneNumber | third party | **device-local** |  |
| `venues` | `country` | `pd:Country` | Location → Country | third party | **device-local** |  |
| `venues` | `deleted_at` | `dpv:NonPersonalData` | NonPersonalData | — | shareable | Soft-delete tombstone; see dances.deleted_at. Must travel, or a peer that has not synced recently resurrects a deleted record. Added to this kind in #898. |
| `venues` | `event_name` | `dpv:NonPersonalData` | NonPersonalData | — | shareable |  |
| `venues` | `existence_at` | `dpv:NonPersonalData` | NonPersonalData | — | shareable | Existence-transition stamp. A bare timestamp with no data subject; must travel or a receiver cannot decide which of two disagreeing copies is the later existence decision, and deletions resurrect. Added in #898. |
| `venues` | `generic_schedule` | `dpv:NonPersonalData` | NonPersonalData | — | shareable |  |
| `venues` | `id` | `dpv:NonPersonalData` | NonPersonalData | — | shareable | Opaque identifier; meaningless alone, required for relational integrity across a transfer. |
| `venues` | `name` | `dpv:NonPersonalData` | NonPersonalData | — | shareable | A hall or grange — an organisation, not a person. Shareable so a program keeps a readable venue after a transfer. |
| `venues` | `notes` | `dpv:PersonalData` | PersonalData | third party | shareable | Unbounded freeform text attached to a person, place or source. Personal data by category, shareable by decision (maintainer ruling: this is the user's own commentary on their own collection). May incidentally contain contact details the user typed there. |
| `venues` | `plus4` | `pd:PostalCode` | Contact → PhysicalAddress → PostalCode | third party | **device-local** |  |
| `venues` | `postal_code` | `pd:PostalCode` | Contact → PhysicalAddress → PostalCode | third party | **device-local** |  |
| `venues` | `price` | `dpv:NonPersonalData` | NonPersonalData | — | shareable |  |
| `venues` | `sponsor` | `dpv:NonPersonalData` | NonPersonalData | — | shareable | An organisation underwriting a series — part of the venue's public identity (maintainer ruling). Free text, so it can hold a personal name, but unlike a custom field its meaning is fixed and known. |
| `venues` | `state_prov` | `pd:Region` | Contact → PhysicalAddress → Region | third party | **device-local** |  |
| `venues` | `time` | `dpv:NonPersonalData` | NonPersonalData | — | shareable |  |
| `venues` | `updated_at` | `dpv:NonPersonalData` | NonPersonalData | — | shareable | Record stamp, not author-supplied. Required for ordering across devices. |
| `venues` | `website` | `cc:WebsiteUrl` | WebsiteUrl | — | shareable | The venue's own public page. |

### Settings keys

Declared in `app/lib`; classified here so the catalogue has one source of truth. `settings.value_json` is `deviceLocal` at the column level so a blanket sync cannot happen by accident — these entries decide what actually travels.

**60 settings keys**: 49 shareable, 7 device-local, 2 device-scoped, 1 protocol-identifier, 1 access-control-data. 3 personal data by category.

| Key | Category | Subject | Egress | Why |
| --- | --- | --- | --- | --- |
| `__shareable_text_normalisation_scope__` | `dpv:NonPersonalData` | — | **device-local** | Non-shareable installation state intentionally retained in a user-controlled local backup, but not sent to project infrastructure. |
| `active_custom_theme` | `dpv:NonPersonalData` | app user | shareable |  |
| `active_dialect` | `dpv:NonPersonalData` | app user | shareable |  |
| `active_dialect_ref` | `dpv:NonPersonalData` | app user | shareable |  |
| `aggressive_beats_update` | `dpv:NonPersonalData` | app user | shareable |  |
| `app_locale` | `dpv:NonPersonalData` | app user | shareable |  |
| `auto_commit_program_changes` | `dpv:NonPersonalData` | app user | shareable |  |
| `auto_size_perform_cards` | `dpv:NonPersonalData` | app user | shareable |  |
| `backup_reminder_cadence` | `dpv:NonPersonalData` | app user | shareable |  |
| `collection_tile_visible_fields` | `dpv:NonPersonalData` | app user | shareable |  |
| `colour_dance_theme` | `dpv:NonPersonalData` | app user | shareable |  |
| `confirm_before_delete` | `dpv:NonPersonalData` | app user | shareable |  |
| `custom_dialects` | `dpv:NonPersonalData` | app user | shareable |  |
| `custom_fields.sharing.disclosed` | `dpv:NonPersonalData` | — | **device-local** | Non-shareable installation state intentionally retained in a user-controlled local backup, but not sent to project infrastructure. |
| `custom_themes` | `dpv:NonPersonalData` | app user | shareable |  |
| `date_format` | `dpv:NonPersonalData` | app user | shareable |  |
| `date_format_custom` | `dpv:NonPersonalData` | app user | shareable |  |
| `decimal_turns` | `dpv:NonPersonalData` | app user | shareable |  |
| `default_collection_sort` | `dpv:NonPersonalData` | app user | shareable |  |
| `default_dance_detail_rendering` | `dpv:NonPersonalData` | app user | shareable |  |
| `default_dance_figures_template` | `dpv:NonPersonalData` | app user | shareable |  |
| `default_dance_form` | `dpv:NonPersonalData` | app user | shareable |  |
| `default_dance_formation_shape` | `dpv:NonPersonalData` | app user | shareable |  |
| `default_dance_phrase_structure` | `dpv:NonPersonalData` | app user | shareable |  |
| `default_dance_progression` | `dpv:NonPersonalData` | app user | shareable |  |
| `default_move_param_overrides` | `dpv:NonPersonalData` | app user | shareable |  |
| `default_program_band` | `pd:Name` | app user | shareable | A performer name the user pre-fills onto new programs — most often their own band. Personal data, shareable for the same reason as programs.band. |
| `default_program_caller` | `pd:Name` | app user | shareable | A performer name the user pre-fills onto new programs — most often themselves. Personal data, shareable for the same reason as programs.caller. |
| `default_program_sort` | `dpv:NonPersonalData` | app user | shareable |  |
| `first_day_of_week` | `dpv:NonPersonalData` | app user | shareable |  |
| `formation_color_overrides` | `dpv:NonPersonalData` | app user | shareable |  |
| `free_text_entry` | `dpv:NonPersonalData` | app user | shareable |  |
| `last_backup_at` | `dpv:NonPersonalData` | — | device-scoped | Belongs to this installation, not the user. Applying it on another device would be wrong rather than merely useless. |
| `last_used_collection_sort` | `dpv:NonPersonalData` | app user | shareable |  |
| `last_used_collection_sort_direction` | `dpv:NonPersonalData` | app user | shareable |  |
| `last_used_program_sort` | `dpv:NonPersonalData` | app user | shareable |  |
| `last_used_program_sort_direction` | `dpv:NonPersonalData` | app user | shareable |  |
| `matrix_exact_beat_collision` | `dpv:NonPersonalData` | app user | shareable |  |
| `perform_canonical_view` | `dpv:NonPersonalData` | app user | shareable |  |
| `perform_stage_mode` | `dpv:NonPersonalData` | app user | shareable |  |
| `perform_text_scale` | `dpv:NonPersonalData` | app user | **device-local** | Tuned to the screen it was set on. A scale chosen for a phone held at arm's length is wrong on a laptop driving a projector, but it may travel in a user-controlled local backup. |
| `program_matrix_columns` | `dpv:NonPersonalData` | app user | shareable |  |
| `reduce_motion` | `dpv:NonPersonalData` | app user | shareable |  |
| `require_performed_for_history` | `dpv:NonPersonalData` | app user | shareable |  |
| `seed.initialCollection.completed` | `dpv:NonPersonalData` | — | **device-local** | Non-shareable installation state intentionally retained in a user-controlled local backup, but not sent to project infrastructure. |
| `set_list_color_coding` | `dpv:NonPersonalData` | app user | shareable |  |
| `shorthand_mappings` | `dpv:NonPersonalData` | app user | shareable |  |
| `soft_delete_retention_days` | `dpv:NonPersonalData` | app user | shareable |  |
| `sort_ignore_articles` | `dpv:NonPersonalData` | app user | shareable |  |
| `sync_device_id` | `dpv:NonPersonalData` | — | **protocol-identifier** | Opaque per-installation routing identifier. It must travel in protocol metadata but must never be adopted from another device or restored from a backup. |
| `sync_id` | `dpv:PersonalData` | app user | **access-control-data** | User-entered bearer credential. It may contain personal information, travels only in Authorization to the configured sync origin, and is never recoverably retained or logged. |
| `theme_mode` | `dpv:NonPersonalData` | app user | shareable |  |
| `track_history_for_all_callers` | `dpv:NonPersonalData` | app user | shareable |  |
| `update_auto_check` | `dpv:NonPersonalData` | — | **device-local** | Non-shareable installation state intentionally retained in a user-controlled local backup, but not sent to project infrastructure. |
| `update_beta_channel` | `dpv:NonPersonalData` | — | **device-local** | Non-shareable installation state intentionally retained in a user-controlled local backup, but not sent to project infrastructure. |
| `update_dismissed_version` | `dpv:NonPersonalData` | — | **device-local** | Non-shareable installation state intentionally retained in a user-controlled local backup, but not sent to project infrastructure. |
| `venue_entity_mode` | `dpv:NonPersonalData` | app user | shareable |  |
| `verbose_figure_rendering` | `dpv:NonPersonalData` | app user | shareable |  |
| `walkthrough_snippets` | `dpv:NonPersonalData` | app user | shareable |  |
| `window_frame` | `dpv:NonPersonalData` | — | device-scoped | Belongs to this installation, not the user. Applying it on another device would be wrong rather than merely useless. |

### Settings key prefixes

Some settings-table keys are built at runtime from a per-entity suffix rather than declared as an exact key (`editor_draft:<id>`), so they cannot appear in the table above. Each prefix below classifies every key it matches; `classifySettingsKey` resolves the longest matching prefix.

**2 settings key prefixes**: 2 device-scoped. 0 personal data by category.

| Key prefix | Category | Subject | Egress | Why |
| --- | --- | --- | --- | --- |
| `editor_draft:` | `dpv:NonPersonalData` | app user | device-scoped | Transient dance-editor autosave draft, keyed per dance (editor_draft:<id>). Unsaved user-authored choreography text that must never leave this device by any route, including a local backup file — see backup_service.dart. |
| `program_editor_draft:` | `dpv:NonPersonalData` | app user | device-scoped | Transient program-editor autosave draft, keyed per program (program_editor_draft:<id>). Same rationale as editor_draft:. |

<!-- END GENERATED: field-catalogue -->
