import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_test/flutter_test.dart';

import 'package:compendium_app/l10n/app_localizations_de.dart';
import 'package:compendium_app/src/screens/user_guide/user_guide_doc_view.dart';
import 'package:compendium_app/src/screens/user_guide/user_guide_screen.dart';

import '../../support/l10n_harness.dart';

const _notice = ValueKey('user-guide-english-only');

Future<void> _pump(WidgetTester tester, Locale locale, Widget body) async {
  await tester.pumpWidget(
    MaterialApp(
      locale: locale,
      localizationsDelegates: testLocalizationsDelegates,
      supportedLocales: testSupportedLocales,
      home: Scaffold(body: body),
    ),
  );
  await tester.pumpAndSettle();
}

Widget _docView() => UserGuideDocView(
  docId: 'x.md',
  data: '# Hello\n\nBody.',
  onTapLink: (_) {},
);

void main() {
  // See user_guide_screen_test.dart: the cached-synchronous bundle path stalls
  // the guide's FutureBuilders on every test after the first.
  setUp(rootBundle.clear);

  // PLAT-13: the bundled guide is English only; a non-English UI says so on
  // every guide page, including one a help link opens directly.
  group('English-only notice', () {
    testWidgets('a non-English UI shows the localized notice above the guide', (
      tester,
    ) async {
      await _pump(tester, const Locale('de'), _docView());
      expect(find.byKey(_notice), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(_notice)).data,
        AppLocalizationsDe().userGuideEnglishOnly,
      );
    });

    testWidgets('an English UI shows no notice', (tester) async {
      await _pump(tester, const Locale('en'), _docView());
      expect(find.byKey(_notice), findsNothing);
    });

    testWidgets('a regional English locale shows no notice', (tester) async {
      await _pump(tester, const Locale('en', 'GB'), _docView());
      expect(find.byKey(_notice), findsNothing);
    });

    testWidgets('the guide hub shows the notice in a non-English UI', (
      tester,
    ) async {
      await _pump(tester, const Locale('ja'), const UserGuideScreen());
      expect(find.byKey(_notice), findsOneWidget);
    });

    testWidgets('a guide opened directly (help link) shows it too', (
      tester,
    ) async {
      await _pump(
        tester,
        const Locale('fr'),
        const UserGuideScreen(initialDoc: 'faq.md'),
      );
      expect(find.byKey(_notice), findsOneWidget);
    });
  });
}
