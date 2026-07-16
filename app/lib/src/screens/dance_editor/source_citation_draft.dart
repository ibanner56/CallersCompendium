import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/widgets.dart';

/// Mutable editing state for a single [SourceCitation] (which source, plus the
/// freeform page/number the dance appears at). Mirrors `LinkDraft`: the
/// [pageController]/[numberController] survive rebuilds and are read into an
/// immutable [SourceCitation] on capture/save.
class SourceCitationDraft {
  SourceCitationDraft({
    required this.sourceId,
    required this.pageController,
    required this.numberController,
  });

  factory SourceCitationDraft.forSource(String sourceId) => SourceCitationDraft(
    sourceId: sourceId,
    pageController: TextEditingController(),
    numberController: TextEditingController(),
  );

  factory SourceCitationDraft.fromCitation(SourceCitation c) =>
      SourceCitationDraft(
        sourceId: c.sourceId,
        pageController: TextEditingController(text: c.page ?? ''),
        numberController: TextEditingController(text: c.number ?? ''),
      );

  final String sourceId;
  final TextEditingController pageController;
  final TextEditingController numberController;

  /// Builds the immutable citation. [SourceCitation] normalizes empty/blank
  /// page/number to `null` itself.
  SourceCitation toCitation() => SourceCitation(
    sourceId: sourceId,
    page: pageController.text,
    number: numberController.text,
  );

  void dispose() {
    pageController.dispose();
    numberController.dispose();
  }
}
