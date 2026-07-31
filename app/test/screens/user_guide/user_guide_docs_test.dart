import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/src/app_metadata.dart';
import 'package:compendium_app/src/screens/user_guide/user_guide_docs.dart';

void main() {
  // The bundled guide set used by the resolver tests. Mirrors what
  // sync_user_docs.py bundles today (README hub + three guides); perform.md and
  // backup-portability.md are intentionally absent to model "coming soon" docs.
  final docs = UserGuideDocs.forTest({
    'README.md',
    'getting-started.md',
    'dialects.md',
    'imports.md',
  });

  group('resolveLink', () {
    test('a bundled sibling guide navigates in-panel', () {
      final link = docs.resolveLink('README.md', 'getting-started.md');
      expect(link, isA<GuideInternalLink>());
      expect((link as GuideInternalLink).docId, 'getting-started.md');
      expect(link.fragment, isNull);
    });

    test('a ./-prefixed bundled guide navigates in-panel', () {
      final link = docs.resolveLink('imports.md', './getting-started.md');
      expect((link as GuideInternalLink).docId, 'getting-started.md');
    });

    test('a hub anchor resolves to the hub with its fragment', () {
      final link = docs.resolveLink(
        'getting-started.md',
        './README.md#glossary',
      );
      expect(link, isA<GuideInternalLink>());
      final internal = link as GuideInternalLink;
      expect(internal.docId, 'README.md');
      expect(internal.fragment, 'glossary');
    });

    test('a pure anchor stays on the current guide', () {
      final link = docs.resolveLink('README.md', '#looking-deeper');
      final internal = link as GuideInternalLink;
      expect(internal.docId, 'README.md');
      expect(internal.fragment, 'looking-deeper');
    });

    test('a not-yet-bundled guide is reported as missing with a label', () {
      final link = docs.resolveLink('getting-started.md', './perform.md');
      expect(link, isA<GuideMissingLink>());
      expect((link as GuideMissingLink).label, 'Perform');
    });

    test('a deliberately-excluded guide opens on GitHub, not "missing"', () {
      // style-guide.md exists in the repo but is intentionally not bundled
      // (contributor-only), so it should open externally rather than claim to
      // be a not-yet-written guide.
      final link = docs.resolveLink('README.md', 'style-guide.md');
      expect(link, isA<GuideExternalLink>());
      expect(
        (link as GuideExternalLink).url,
        '$kSourceRepoUrl/blob/main/docs/user/style-guide.md',
      );
    });

    test('a multi-word missing guide gets a readable label', () {
      final link = docs.resolveLink('imports.md', './backup-portability.md');
      expect((link as GuideMissingLink).label, 'Backup portability');
    });

    test('an http(s) link is external', () {
      final link = docs.resolveLink('README.md', 'https://example.com/x');
      expect(link, isA<GuideExternalLink>());
      expect((link as GuideExternalLink).url, 'https://example.com/x');
    });

    test('a repo file outside the bundle resolves to its GitHub URL', () {
      final link = docs.resolveLink('README.md', '../design/dialect.md');
      expect(link, isA<GuideExternalLink>());
      expect(
        (link as GuideExternalLink).url,
        '$kSourceRepoUrl/blob/main/docs/design/dialect.md',
      );
    });

    test('an escaping repo link keeps its fragment', () {
      final link = docs.resolveLink('README.md', '../../README.md#support');
      expect(
        (link as GuideExternalLink).url,
        '$kSourceRepoUrl/blob/main/README.md#support',
      );
    });
  });

  group('titleFromMarkdown', () {
    test('reads the guide\'s first level-one heading', () {
      expect(
        UserGuideDocs.titleFromMarkdown(
          '# FAQ & troubleshooting\n\nSome prose.\n\n# Later heading\n',
        ),
        'FAQ & troubleshooting',
      );
    });

    test('tolerates leading indent and a closing run of hashes', () {
      expect(
        UserGuideDocs.titleFromMarkdown('  # Getting started #\n'),
        'Getting started',
      );
    });

    test('ignores deeper headings', () {
      expect(
        UserGuideDocs.titleFromMarkdown('## Not the title\n\n# The title\n'),
        'The title',
      );
    });

    test('returns null when there is no level-one heading', () {
      expect(UserGuideDocs.titleFromMarkdown('Just prose.\n'), isNull);
    });
  });

  group('slugify', () {
    test('matches the anchors GitHub generates for guide headings', () {
      // Spot-checks against anchors the guides actually link to.
      expect(UserGuideDocs.slugify("The Caller's Box"), 'the-callers-box');
      expect(
        UserGuideDocs.slugify('Print, export, and email a program'),
        'print-export-and-email-a-program',
      );
      // GitHub drops `&` entirely, leaving the spaces on either side as
      // hyphens — so this really is a double hyphen, not a typo.
      expect(
        UserGuideDocs.slugify('Collection & search'),
        'collection--search',
      );
    });

    test('keeps hyphens and underscores, drops other punctuation', () {
      expect(
        UserGuideDocs.slugify('Re-check custom_figures (really!)'),
        're-check-custom_figures-really',
      );
    });
  });
}
