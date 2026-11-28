import 'package:compendium_app/src/widgets/empty_state.dart';
import 'package:compendium_app/src/widgets/load_error_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/l10n_harness.dart';
import 'support/source_scan.dart';

Widget _app(Widget child) => MaterialApp(
  localizationsDelegates: testLocalizationsDelegates,
  supportedLocales: testSupportedLocales,
  home: Scaffold(body: child),
);

void main() {
  group('EmptyState', () {
    testWidgets('its title is a heading for screen readers', (tester) async {
      final handle = tester.ensureSemantics();
      await tester.pumpWidget(
        _app(
          EmptyState(
            icon: const Icon(Icons.add),
            title: 'No things yet',
            body: 'Choose New thing to add one.',
            actions: [FilledButton(onPressed: () {}, child: const Text('Go'))],
          ),
        ),
      );
      final title = tester.getSemantics(find.text('No things yet'));
      expect(
        title.flagsCollection.isHeader,
        isTrue,
        reason: 'the title must be reachable by heading navigation',
      );
      expect(find.bySemanticsLabel('Choose New thing to add one.'), findsOne);
      handle.dispose();
    });

    testWidgets('inline lays out inside a list with other content', (
      tester,
    ) async {
      await tester.pumpWidget(
        _app(
          ListView(
            children: const [
              Text('intro'),
              EmptyState(inline: true, icon: Icon(Icons.add), title: 'Empty'),
              Text('after'),
            ],
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      expect(find.text('Empty'), findsOneWidget);
      expect(find.text('after'), findsOneWidget);
    });
  });

  group('LoadErrorView', () {
    testWidgets('a retryable failure offers Retry and no Back', (tester) async {
      await tester.pumpWidget(
        _app(LoadErrorView(message: 'Could not load.', onRetry: () {})),
      );
      expect(find.text('Try again'), findsOneWidget);
      expect(find.text('Back'), findsNothing);
    });

    testWidgets('a failure that cannot be retried offers Back instead', (
      tester,
    ) async {
      var left = false;
      await tester.pumpWidget(
        _app(
          LoadErrorView(
            message: 'Gone.',
            body: 'It was removed.',
            onRetry: null,
            onBack: () => left = true,
          ),
        ),
      );
      expect(find.text('Try again'), findsNothing);
      expect(find.text('It was removed.'), findsOneWidget);
      await tester.tap(find.text('Back'));
      expect(left, isTrue);
    });

    testWidgets('with neither action it shows Retry, disabled', (tester) async {
      await tester.pumpWidget(
        _app(const LoadErrorView(message: 'Loading.', onRetry: null)),
      );
      final button = tester.widget<FilledButton>(find.byType(FilledButton));
      expect(button.onPressed, isNull);
    });
  });

  test('only the shared widget draws the whole-screen error glyph', () {
    // A whole-screen load failure uses LoadErrorView, which carries the one
    // Retry/Back wording; a hand-built column drifts from it.
    final offenders = <String>[
      for (final (path, source) in dartSources('lib/src'))
        if (!path.endsWith('widgets/load_error_view.dart'))
          for (final line in handBuiltErrorGlyphLines(source)) '$path:$line',
    ];
    expect(offenders, isEmpty);
  });

  test('the error glyph scan reads the Icon call, not a line of it', () {
    expect(handBuiltErrorGlyphLines('Icon(Icons.error_outline, size: 48)'), [
      1,
    ]);
    // Arguments in another order, across lines, or a nearby size.
    expect(
      handBuiltErrorGlyphLines(
        'x\nconst Icon(\n  Icons.error_outline,\n  color: c,\n  size: 56,\n)',
      ),
      [2],
    );
    expect(
      handBuiltErrorGlyphLines('Icon(size: 48.0, Icons.error_outline_rounded)'),
      [1],
    );
    // An inline glyph, another icon, or prose is not the whole-screen glyph.
    expect(
      handBuiltErrorGlyphLines(
        'Icon(Icons.error_outline, size: 18, color: c)\n'
        'Icon(Icons.error_outline)\n'
        'Icon(Icons.info_outline, size: 48)\n'
        '// Icon(Icons.error_outline, size: 48)\n'
        "Text('Icon(Icons.error_outline, size: 48)')\n",
      ),
      isEmpty,
    );
  });
}

final RegExp _iconCall = RegExp(r'(?<![\w.])Icon\s*\(');
final RegExp _errorIcon = RegExp(
  r'^Icons\s*\.\s*error_outline(?:_rounded|_outlined|_sharp)?$',
);

/// The 1-based lines of [source] that build the whole-screen error glyph by
/// hand: an `Icon` of `Icons.error_outline` (or a variant) at a size of 32 or
/// more, its arguments in any order and on any number of lines. The inline
/// error glyphs beside a message are 16 to 24 px.
List<int> handBuiltErrorGlyphLines(String source) {
  final code = codeOnly(source);
  return [
    for (final m in _iconCall.allMatches(code))
      if (_isLargeErrorGlyph(callArgs(source, m.end - 1, code: code)))
        lineAt(source, m.start),
  ];
}

bool _isLargeErrorGlyph(List<CallArg> args) {
  final icon = args.where((a) => a.name == null).firstOrNull;
  if (icon == null || !_errorIcon.hasMatch(icon.text)) return false;
  final size = args.where((a) => a.name == 'size').firstOrNull;
  final value = size == null ? null : double.tryParse(size.text);
  return value != null && value >= 32;
}
