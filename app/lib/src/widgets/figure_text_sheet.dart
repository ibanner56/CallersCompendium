import 'dart:typed_data';

import 'package:compendium_core/compendium_core.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../diagnostics/error_log.dart';
import '../data/photo_capture.dart';
import '../data/text_recognition.dart';
import '../editor/figure_draft.dart';
import '../theme/app_motion.dart';
import '../theme/app_spacing.dart';
import 'confirm_discard_changes.dart';

/// What one line of the **Add figures from text** sheet becomes.
class FigureTextLineReading {
  const FigureTextLineReading({
    required this.line,
    required this.drafts,
    required this.unrecognized,
  });

  /// The line as the parser read it, without any phrase label it dropped.
  final FigureTextLine line;

  /// The rows the line inserts, in order: one per figure, or one for a
  /// compound or own-figure shorthand.
  final List<FigureDraft> drafts;

  /// Whether any of [drafts] is a figure the parser did not recognise, kept
  /// as an unrecognized figure carrying the text.
  final bool unrecognized;
}

/// What the text in the **Add figures from text** sheet becomes: a reading
/// per line, or why the text was refused.
class FigureTextReading {
  const FigureTextReading({required this.lines}) : refusal = null;

  const FigureTextReading.refused(FigureTextRefusal this.refusal)
    : lines = const [];

  final List<FigureTextLineReading> lines;

  /// Set when the text was over a cap. Nothing is offered for insertion.
  final FigureTextRefusal? refusal;

  /// Every row the text inserts, line by line.
  List<FigureDraft> get drafts => [for (final line in lines) ...line.drafts];

  int get unrecognizedLines => lines.where((line) => line.unrecognized).length;
}

/// The dance editor's **Add figures from text** sheet (#2326): a multi-line
/// text box where each non-empty line is read as one figure line, as typing it
/// in the Move box with Free-text entry on would read it. A live preview says
/// how many figures each line gives and marks the lines kept as unrecognized
/// figures. **Add figures** closes the sheet with the rows to insert; Cancel
/// closes it with nothing.
///
/// Typed text is never lost (#2219): while the box holds text, Back, Escape
/// and a tap outside ask before discarding it ([DiscardChangesGuard]), and an
/// empty sheet closes as usual. The sheet cannot be swiped down: a swipe pops
/// the route directly, past that guard, so [show] turns dragging off and
/// shows no drag handle.
///
/// The sheet does no reading of its own: [read] turns the text into rows, so
/// the host reads lines with the dance's taxonomy, dialect, shorthands,
/// formation and meter, as its Move box does.
class FigureTextSheet extends StatefulWidget {
  const FigureTextSheet({
    super.key,
    required this.read,
    required this.dropsPhraseLabels,
  });

  /// Reads the sheet's text. Called on every change, so it must not change
  /// the dance.
  final FigureTextReading Function(String text) read;

  /// Whether [read] drops a leading `A1`…`C2` phrase label (contra dances),
  /// which the help text then says.
  final bool dropsPhraseLabels;

  /// Opens the sheet and resolves to the rows to insert, or null when the
  /// user closed it without adding any.
  static Future<List<FigureDraft>?> show(
    BuildContext context, {
    required FigureTextReading Function(String text) read,
    required bool dropsPhraseLabels,
  }) {
    return showModalBottomSheet<List<FigureDraft>>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      // A swipe or the drag handle would close the sheet without asking about
      // the typed text; see the class comment.
      enableDrag: false,
      builder: (_) =>
          FigureTextSheet(read: read, dropsPhraseLabels: dropsPhraseLabels),
      sheetAnimationStyle: AppMotion.styleFor(context),
    );
  }

  @override
  State<FigureTextSheet> createState() => _FigureTextSheetState();
}

class _FigureTextSheetState extends State<FigureTextSheet> {
  final _textController = TextEditingController();
  FigureTextReading _reading = const FigureTextReading(lines: []);

  @override
  void initState() {
    super.initState();
    _textController.addListener(_reread);
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  /// The text [_reading] was read from. The controller also notifies on a
  /// caret or selection move, which must not re-read the whole text.
  String _readText = '';

  void _reread() {
    final text = _textController.text;
    if (text == _readText) return;
    _readText = text;
    final reading = widget.read(text);
    setState(() => _reading = reading);
  }

  void _add() {
    final drafts = _reading.drafts;
    if (_reading.refusal != null || drafts.isEmpty) return;
    Navigator.of(context).pop(drafts);
  }

  String? _refusalMessage(AppLocalizations l10n) => switch (_reading.refusal) {
    FigureTextRefusal.tooLong => l10n.figureTextSheetTooLong(
      maxFigureTextLength,
    ),
    FigureTextRefusal.tooManyLines => l10n.figureTextSheetTooManyLines(
      maxFigureTextLines,
    ),
    FigureTextRefusal.lineTooLong => l10n.figureTextSheetLineTooLong(
      maxFreeTextEntryLength,
    ),
    null => null,
  };

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final media = MediaQuery.of(context);
    final refusal = _refusalMessage(l10n);
    final figureCount = _reading.drafts.length;
    final canAdd = refusal == null && figureCount > 0;
    // Rebuilt by [_reread]'s setState on every change to the text.
    return DiscardChangesGuard(
      dirty: _textController.text.isNotEmpty,
      child: Padding(
        // The route does not lift a sheet above the keyboard.
        padding: EdgeInsets.only(bottom: media.viewInsets.bottom),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: media.size.height * 0.9),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Flexible(
                // At most [maxFigureTextLines] preview rows, so building them
                // all is cheap, and none goes missing from the semantics tree.
                child: SingleChildScrollView(
                  // Top space the drag handle used to give, as the venue
                  // sheet has: neither sheet has a handle (see [show]).
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.lg,
                    AppSpacing.md,
                    0,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Text(
                        l10n.figureTextSheetTitle,
                        style: theme.textTheme.titleLarge,
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      Text(
                        widget.dropsPhraseLabels
                            ? l10n.figureTextSheetHelpDropsLabels
                            : l10n.figureTextSheetHelp,
                        style: theme.textTheme.bodyMedium,
                      ),
                      if (TextRecognitionScope.of(context) case final service?)
                        _FromImage(
                          service: service,
                          pickImage: TextRecognitionScope.pickerOf(context),
                          camera: PhotoCaptureScope.of(context),
                          onText: (text) => _textController.text = text,
                        ),
                      const SizedBox(height: AppSpacing.md),
                      TextField(
                        key: const ValueKey('figure-text-sheet-field'),
                        controller: _textController,
                        autofocus: true,
                        minLines: 5,
                        maxLines: 12,
                        keyboardType: TextInputType.multiline,
                        textInputAction: TextInputAction.newline,
                        decoration: InputDecoration(
                          labelText: l10n.figureTextSheetFieldLabel,
                          alignLabelWithHint: true,
                          border: const OutlineInputBorder(),
                          errorText: refusal,
                          errorMaxLines: 4,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      if (refusal == null) ...[
                        // Not a live region: it changes on almost every keystroke.
                        Text(
                          key: const ValueKey('figure-text-sheet-summary'),
                          l10n.figureTextSheetSummary(figureCount),
                          style: theme.textTheme.titleSmall,
                        ),
                        if (_reading.unrecognizedLines > 0)
                          Text(
                            key: const ValueKey(
                              'figure-text-sheet-unrecognized',
                            ),
                            l10n.figureTextSheetUnrecognizedSummary(
                              _reading.unrecognizedLines,
                            ),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.error,
                            ),
                          ),
                        for (final (index, line) in _reading.lines.indexed)
                          _LinePreview(
                            key: ValueKey('figure-text-sheet-line-$index'),
                            reading: line,
                          ),
                      ],
                      const SizedBox(height: AppSpacing.sm),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.md,
                  0,
                  AppSpacing.md,
                  AppSpacing.md,
                ),
                child: OverflowBar(
                  alignment: MainAxisAlignment.end,
                  spacing: AppSpacing.sm,
                  overflowAlignment: OverflowBarAlignment.end,
                  children: [
                    TextButton(
                      key: const ValueKey('figure-text-sheet-cancel'),
                      onPressed: () => Navigator.of(context).pop(),
                      child: Text(l10n.commonCancel),
                    ),
                    FilledButton(
                      key: const ValueKey('figure-text-sheet-add'),
                      onPressed: canAdd ? _add : null,
                      child: Text(l10n.figureTextSheetAdd),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// **From an image…** (#2327) and, where there is a camera, **Take a photo**
/// (#2328): reads a chosen picture's or a new photo's text on the device and
/// puts it in the sheet's text box, replacing what is there, for the user to
/// correct. The picture is read once and released.
class _FromImage extends StatefulWidget {
  const _FromImage({
    required this.service,
    required this.pickImage,
    required this.camera,
    required this.onText,
  });

  final TextRecognitionService service;
  final Future<PickedRecognitionImage?> Function() pickImage;

  /// Null hides **Take a photo**.
  final PhotoCaptureService? camera;
  final ValueChanged<String> onText;

  @override
  State<_FromImage> createState() => _FromImageState();
}

class _FromImageState extends State<_FromImage> {
  /// Null until the device answers which languages it reads.
  TextRecognitionAvailability? _availability;
  List<String> _wanted = const [];

  /// The source being read, or null when none is.
  _ImageSource? _busy;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final wanted = recognitionLanguagesFor(Localizations.localeOf(context));
    if (wanted.join(',') == _wanted.join(',')) return;
    _wanted = wanted;
    _availability = null;
    widget.service
        .availability(wanted)
        .onError<Object>((error, stack) {
          logCaughtErrorTypeOnly(
            error,
            stack,
            source: 'figure_text_sheet.availability',
          );
          return TextRecognitionAvailability.none;
        })
        .then((availability) {
          if (mounted && wanted == _wanted) {
            setState(() => _availability = availability);
          }
        });
  }

  /// The encoded picture from [source], or null when the user cancelled.
  Future<Uint8List?> _bytesFrom(_ImageSource source) async {
    switch (source) {
      case _ImageSource.file:
        return (await widget.pickImage())?.bytes;
      case _ImageSource.camera:
        try {
          return await widget.camera?.takePhoto(
            maxBytes: kMaxRecognitionImageBytes,
          );
        } on PhotoCaptureException catch (e) {
          // diagnostics: silent — an expected refusal, shown inline below
          switch (e.reason) {
            case PhotoCaptureFailure.tooLarge:
              throw const TextRecognitionException(
                TextRecognitionFailure.tooLarge,
              );
            case PhotoCaptureFailure.accessDenied:
              throw const _CameraOff();
            case PhotoCaptureFailure.noCamera:
              // As before the camera knew this failure: reading failed.
              throw const TextRecognitionException(
                TextRecognitionFailure.failed,
              );
          }
        }
    }
  }

  Future<void> _read(_ImageSource source) async {
    final availability = _availability;
    if (_busy != null || availability == null || !availability.isAvailable) {
      return;
    }
    setState(() {
      _busy = source;
      _error = null;
    });
    TextRecognitionFailure? failure;
    var cameraOff = false;
    try {
      final bytes = await _bytesFrom(source);
      if (bytes == null) return;
      await checkRecognitionImage(bytes);
      final text = await widget.service.recognize(
        bytes,
        languages: availability.languages,
      );
      if (!mounted) return;
      widget.onText(text);
    } on TextRecognitionException catch (e) {
      // diagnostics: silent — an expected refusal (size, no text, unreadable), shown inline below
      failure = e.reason;
    } on _CameraOff {
      // diagnostics: silent — camera access is off by the user's choice, shown inline below
      cameraOff = true;
    } on Object catch (e, stack) {
      // The picker, the file read or the engine failed in a way none of the
      // refusals above names: say reading failed rather than nothing.
      logCaughtErrorTypeOnly(e, stack, source: 'figure_text_sheet._read');
      failure = TextRecognitionFailure.failed;
    } finally {
      if (mounted) {
        setState(() {
          _busy = null;
          _error = cameraOff
              ? AppLocalizations.of(context).figureTextSheetCameraOff
              : failure == null
              ? null
              : _message(failure);
        });
      }
    }
  }

  String _message(TextRecognitionFailure reason) {
    final l10n = AppLocalizations.of(context);
    return switch (reason) {
      TextRecognitionFailure.tooLarge => l10n.figureTextSheetImageTooLarge(
        kMaxRecognitionImageBytes ~/ (1024 * 1024),
      ),
      TextRecognitionFailure.tooManyPixels =>
        l10n.figureTextSheetImageTooManyPixels,
      TextRecognitionFailure.unreadable => l10n.figureTextSheetImageUnreadable,
      TextRecognitionFailure.noText => l10n.figureTextSheetImageNoText,
      TextRecognitionFailure.failed => l10n.figureTextSheetImageFailed,
    };
  }

  Widget _sourceButton({
    required Key key,
    required _ImageSource source,
    required bool enabled,
    required IconData icon,
    required String label,
    required String busyLabel,
  }) {
    final busy = _busy == source;
    return OutlinedButton.icon(
      key: key,
      onPressed: enabled && _busy == null ? () => _read(source) : null,
      icon: busy
          ? const SizedBox.square(
              dimension: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Icon(icon),
      label: Text(busy ? busyLabel : label),
    );
  }

  @override
  Widget build(BuildContext context) {
    final availability = _availability;
    if (availability == null) return const SizedBox.shrink();
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final note = !availability.isAvailable
        ? l10n.figureTextSheetImageUnavailable
        : availability.languages.contains(_wanted.first)
        ? null
        : l10n.figureTextSheetImageEnglishOnly;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.xs,
            children: [
              if (widget.camera != null)
                _sourceButton(
                  key: const ValueKey('figure-text-sheet-take-photo'),
                  source: _ImageSource.camera,
                  enabled: availability.isAvailable,
                  icon: Icons.photo_camera_outlined,
                  label: l10n.figureTextSheetTakePhoto,
                  busyLabel: l10n.figureTextSheetReadingImage,
                ),
              _sourceButton(
                key: const ValueKey('figure-text-sheet-from-image'),
                source: _ImageSource.file,
                enabled: availability.isAvailable,
                icon: Icons.image_outlined,
                label: l10n.figureTextSheetFromImage,
                busyLabel: l10n.figureTextSheetReadingImage,
              ),
            ],
          ),
          if (note != null)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Text(
                key: const ValueKey('figure-text-sheet-image-note'),
                note,
                style: theme.textTheme.bodySmall,
              ),
            ),
          if (_error case final error?)
            Padding(
              padding: const EdgeInsets.only(top: AppSpacing.xs),
              child: Semantics(
                liveRegion: true,
                child: Text(
                  key: const ValueKey('figure-text-sheet-image-error'),
                  error,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Where a picture comes from.
enum _ImageSource { file, camera }

/// Camera access is off for the app, so no photo was taken.
class _CameraOff implements Exception {
  const _CameraOff();
}

/// One line of the preview: the text as read, and what it gives.
class _LinePreview extends StatelessWidget {
  const _LinePreview({super.key, required this.reading});

  final FigureTextLineReading reading;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final count = reading.drafts.length;
    final outcome = reading.unrecognized
        ? l10n.figureTextSheetLineUnrecognized
        : l10n.figureTextSheetLineFigures(count);
    return MergeSemantics(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.only(end: AppSpacing.sm),
              child: Icon(
                reading.unrecognized
                    ? Icons.help_outline
                    : Icons.check_circle_outline,
                size: 18,
                color: reading.unrecognized
                    ? theme.colorScheme.error
                    : theme.colorScheme.primary,
              ),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(reading.line.text, style: theme.textTheme.bodyMedium),
                  Text(
                    outcome,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: reading.unrecognized
                          ? theme.colorScheme.error
                          : theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
