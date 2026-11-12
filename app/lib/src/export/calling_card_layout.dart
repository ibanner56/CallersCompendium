/// The calling-card layout language and the calling-card print settings.
///
/// A calling card is a small card (3 × 5 inches by default) carrying one
/// dance, laid out for a caller to hold while calling. The card design — the
/// title with the formation and authors beside it over a rule, then the
/// phrase / beats / figure table — follows Yona Appletree's `contra-card`
/// tool (github.com/Yona-Appletree/contra-card). No code is taken from it:
/// that tool writes SVG from Rust, and this is a fresh implementation over the
/// app's own figure model and PDF stack.
///
/// The layout is a short text the user edits in Settings › Experimental. Each
/// non-blank line is one row of the card, top to bottom:
///
/// ```text
/// # A line starting with # is a comment.
/// title size=16 bold width=3 | formation size=8 right width=2
/// rule color=#b64545
/// figures size=10
/// notes size=8 lines=4
/// ```
///
/// `|` puts blocks side by side in one row. A block is a name followed by
/// options: a flag (`bold`) or `name=value`, where a value with spaces is
/// written in double quotes (`label="Calling notes"`). [CallingCardLayout.parse]
/// never throws: a line it cannot read is reported as a
/// [CallingCardLayoutIssue] and left off the card, so a typo costs one line,
/// not the print.
library;

import 'dart:math' as math;

/// What a block prints.
enum CallingCardBlockKind {
  title,
  authors,
  formation,
  level,
  meta,
  figures,
  notes,
  walkthrough,
  hook,
  tunes,
  sources,
  program,
  number,
  text,
  rule,
  space,
  card;

  /// The name the layout language spells this block with.
  String get keyword => name;
}

/// Horizontal alignment of a text block within its share of the row.
enum CallingCardAlign { left, center, right }

/// Why a layout line was not (fully) understood. The UI resolves each kind to
/// a localized sentence; [CallingCardLayoutIssue.subject] carries the word the
/// sentence quotes.
enum CallingCardIssueKind {
  /// [CallingCardLayoutIssue.subject] is not a block name.
  unknownBlock,

  /// [CallingCardLayoutIssue.subject] is not an option this block takes.
  unknownOption,

  /// The value given to option [CallingCardLayoutIssue.subject] is not one it
  /// accepts; [CallingCardLayoutIssue.value] is what was written.
  badValue,

  /// A `"` was opened and never closed.
  unclosedQuote,

  /// A `text` block has no quoted words to print.
  missingText,

  /// A `card` line shares its row with other blocks; it sets the whole card,
  /// so it must be alone on its line.
  cardNotAlone,

  /// A `|` with nothing on one side of it.
  emptyBlock,
}

/// One problem found on one line of a layout.
class CallingCardLayoutIssue {
  const CallingCardLayoutIssue({
    required this.line,
    required this.kind,
    this.subject = '',
    this.value = '',
  });

  /// 1-based line number in the layout source.
  final int line;
  final CallingCardIssueKind kind;

  /// The block or option name the issue is about, as written.
  final String subject;

  /// For [CallingCardIssueKind.badValue], the rejected value as written.
  final String value;

  @override
  bool operator ==(Object other) =>
      other is CallingCardLayoutIssue &&
      other.line == line &&
      other.kind == kind &&
      other.subject == subject &&
      other.value == value;

  @override
  int get hashCode => Object.hash(line, kind, subject, value);

  @override
  String toString() =>
      'CallingCardLayoutIssue(line $line, ${kind.name}, "$subject", "$value")';
}

/// One block of a row, with every option resolved to a value (defaults
/// filled in), so the PDF builder never re-reads the source.
class CallingCardBlock {
  const CallingCardBlock({
    required this.kind,
    required this.size,
    this.bold = false,
    this.italic = false,
    this.align = CallingCardAlign.left,
    this.color,
    this.maxLines,
    this.label,
    this.width = 1,
    this.text = '',
    this.beats = true,
    this.figureNotes = true,
    this.phrases = true,
    this.dividers = true,
    this.highlight = false,
    this.thickness = 1,
    this.space = 0,
  });

  final CallingCardBlockKind kind;

  /// Font size in points, before the card shrinks to fit.
  final double size;
  final bool bold;
  final bool italic;
  final CallingCardAlign align;

  /// An `0xRRGGBB` color, or `null` for the default ink.
  final int? color;

  /// The most lines a text block may take; `null` for no limit.
  final int? maxLines;

  /// The label printed before the text, or `null` for the block's default
  /// (the field's own label for notes, walkthrough, hook, tunes and sources;
  /// none for the rest). An empty string prints no label.
  final String? label;

  /// The block's relative width within its row.
  final int width;

  /// The words a `text` block prints.
  final String text;

  /// `figures` only: print each figure's beat count.
  final bool beats;

  /// `figures` only: print each figure's own note beneath it.
  final bool figureNotes;

  /// `figures` only: print the A1 / A2 / B1 / B2 phrase column.
  final bool phrases;

  /// `figures` only: draw a thin line between phrases.
  final bool dividers;

  /// `figures` only: set the moves, the dancers and the amounts apart in
  /// each figure line (see `calling_card_highlight.dart`).
  final bool highlight;

  /// `rule` only: line thickness in points.
  final double thickness;

  /// `space` only: the gap in points.
  final double space;
}

/// A parsed layout: the rows to print, the card margin, and what could not be
/// read.
class CallingCardLayout {
  const CallingCardLayout({
    required this.rows,
    this.margin = defaultMargin,
    this.issues = const [],
  });

  /// The margin when the layout sets none: a quarter inch, inside what most
  /// printers can reach.
  static const double defaultMargin = 18;

  /// Each row's blocks, left to right. Rows are never empty.
  final List<List<CallingCardBlock>> rows;

  /// The space in points between the card's edge and its content.
  final double margin;
  final List<CallingCardLayoutIssue> issues;

  /// Parses [source]. Never throws; see the library comment.
  static CallingCardLayout parse(String source) => _Parser(source).run();
}

/// The layout a user starts from, and returns to with Reset.
const String kDefaultCallingCardLayout = '''
# Each line is one row of the card, from top to bottom.
# Put | between blocks to place them side by side.
title size=16 bold width=3 | formation size=8 right width=2
authors size=8 | level size=8 right
rule color=#b64545 thickness=1.5
figures size=10 highlight
space 4
notes size=8 lines=4
''';

/// Ready-made layouts the editor offers beside its help, by stable id. The
/// default is first. Their names are localized in the app; the layouts
/// themselves are the language, which is not translated.
const Map<String, String> kCallingCardLayoutExamples = {
  'classic': kDefaultCallingCardLayout,
  'bigPrint': '''
# Large type for a dim hall: just the title and the figures.
title size=18 bold
rule
figures size=14 notes=off
''',
  'program': '''
# For printing a program: each card shows its place in the evening.
number size=14 bold width=1 | program size=8 right width=4
title size=16 bold | formation size=8 right
rule color=#b64545
figures size=10
notes size=8 lines=3
''',
  'teaching': '''
# A teaching card, with the walkthrough under the figures.
title size=14 bold | level size=8 right
meta size=7
rule
figures size=9 dividers=off
walkthrough size=8 lines=6
notes size=8 italic label="Calling notes: "
''',
};

/// The default font size of each block, in points, for a 3 × 5 card.
double _defaultSize(CallingCardBlockKind kind) => switch (kind) {
  CallingCardBlockKind.title => 16,
  CallingCardBlockKind.figures => 10,
  CallingCardBlockKind.text => 9,
  _ => 8,
};

const _textOptions = {
  'size',
  'bold',
  'italic',
  'left',
  'center',
  'right',
  'color',
  'lines',
  'label',
  'width',
};

Set<String> _optionsFor(CallingCardBlockKind kind) => switch (kind) {
  CallingCardBlockKind.figures => const {
    'size',
    'bold',
    'italic',
    'color',
    'width',
    'beats',
    'notes',
    'phrases',
    'dividers',
    'highlight',
  },
  CallingCardBlockKind.rule => const {'color', 'thickness', 'width'},
  CallingCardBlockKind.space => const {'size'},
  CallingCardBlockKind.card => const {'margin'},
  _ => _textOptions,
};

/// The smallest and largest font size a layout may ask for.
const double _minFontSize = 4;
const double _maxFontSize = 72;

class _Token {
  const _Token(this.text, {required this.quoted});
  final String text;
  final bool quoted;
}

class _Parser {
  _Parser(this.source);

  final String source;
  final _issues = <CallingCardLayoutIssue>[];
  final _rows = <List<CallingCardBlock>>[];
  double _margin = CallingCardLayout.defaultMargin;

  CallingCardLayout run() {
    final lines = source.split('\n');
    for (var i = 0; i < lines.length; i++) {
      _line(i + 1, lines[i].trim());
    }
    return CallingCardLayout(
      rows: List.unmodifiable(_rows),
      margin: _margin,
      issues: List.unmodifiable(_issues),
    );
  }

  void _issue(
    int line,
    CallingCardIssueKind kind, [
    String subject = '',
    String value = '',
  ]) => _issues.add(
    CallingCardLayoutIssue(
      line: line,
      kind: kind,
      subject: subject,
      value: value,
    ),
  );

  void _line(int line, String text) {
    if (text.isEmpty || text.startsWith('#')) return;
    final segments = _splitBlocks(line, text);
    if (segments == null) return;
    final row = <CallingCardBlock>[];
    for (final tokens in segments) {
      if (tokens.isEmpty) {
        _issue(line, CallingCardIssueKind.emptyBlock);
        continue;
      }
      final head = tokens.first;
      final kind = head.quoted ? null : _kindNamed(head.text);
      if (kind == null) {
        _issue(line, CallingCardIssueKind.unknownBlock, head.text);
        continue;
      }
      if (kind == CallingCardBlockKind.card) {
        if (segments.length > 1) {
          _issue(line, CallingCardIssueKind.cardNotAlone, head.text);
          continue;
        }
        _card(line, tokens.skip(1));
        continue;
      }
      final block = _block(line, kind, tokens.skip(1).toList());
      if (block != null) row.add(block);
    }
    if (row.isNotEmpty) _rows.add(List.unmodifiable(row));
  }

  static CallingCardBlockKind? _kindNamed(String name) {
    final lower = name.toLowerCase();
    for (final kind in CallingCardBlockKind.values) {
      if (kind.keyword == lower) return kind;
    }
    return null;
  }

  /// Splits [text] into `|`-separated blocks of tokens. A quoted run is one
  /// token and may hold spaces, `|` and `#`. Returns `null`, after reporting
  /// it, for a quote left open.
  List<List<_Token>>? _splitBlocks(int line, String text) {
    final blocks = <List<_Token>>[[]];
    final buf = StringBuffer();
    var inQuote = false;
    var quotedPart = false;

    void flush() {
      if (buf.isNotEmpty || quotedPart) {
        blocks.last.add(_Token(buf.toString(), quoted: quotedPart));
      }
      buf.clear();
      quotedPart = false;
    }

    // Curly quotes count as straight ones: a phone keyboard or a paste can
    // turn one into the other.
    bool isQuote(String ch) => ch == '"' || ch == '\u201C' || ch == '\u201D';
    for (final ch in text.split('')) {
      if (inQuote) {
        if (isQuote(ch)) {
          inQuote = false;
        } else {
          buf.write(ch);
        }
      } else if (isQuote(ch)) {
        inQuote = true;
        // Only a token that *starts* with a quote is a bare quoted value;
        // `label="Notes: "` stays one `name=value` token.
        if (buf.isEmpty) quotedPart = true;
      } else if (ch == '|') {
        flush();
        blocks.add([]);
      } else if (ch.trim().isEmpty) {
        // Any space, a pasted no-break space included.
        flush();
      } else {
        buf.write(ch);
      }
    }
    if (inQuote) {
      _issue(line, CallingCardIssueKind.unclosedQuote);
      return null;
    }
    flush();
    return blocks;
  }

  void _card(int line, Iterable<_Token> options) {
    for (final token in options) {
      final (name, value) = _option(token);
      if (name != 'margin') {
        _issue(line, CallingCardIssueKind.unknownOption, name);
        continue;
      }
      final margin = _number(value, min: 0, max: 72);
      if (margin == null) {
        _issue(line, CallingCardIssueKind.badValue, name, value ?? '');
        continue;
      }
      _margin = margin;
    }
  }

  /// `name=value` → (name, value); a bare flag → (name, null). A quoted token
  /// is a value with no name: (`''`, text).
  static (String, String?) _option(_Token token) {
    if (token.quoted) return ('', token.text);
    final eq = token.text.indexOf('=');
    if (eq < 0) return (token.text.toLowerCase(), null);
    return (
      token.text.substring(0, eq).toLowerCase(),
      token.text.substring(eq + 1),
    );
  }

  CallingCardBlock? _block(
    int line,
    CallingCardBlockKind kind,
    List<_Token> tokens,
  ) {
    final allowed = _optionsFor(kind);
    var size = _defaultSize(kind);
    var bold = false;
    var italic = false;
    var align = CallingCardAlign.left;
    int? color;
    int? maxLines;
    String? label;
    var width = 1;
    String? text;
    var beats = true;
    var figureNotes = true;
    var phrases = true;
    var dividers = true;
    var highlight = false;
    double thickness = 1;
    double? space;

    for (final (name, value) in tokens.map(_option)) {
      // A positional value — quoted words, or a bare number — is the words
      // of `text` or the gap of `space`.
      if (name.isEmpty || (value == null && double.tryParse(name) != null)) {
        final raw = name.isEmpty ? value! : name;
        if (kind == CallingCardBlockKind.text && name.isEmpty) {
          text = raw;
        } else if (kind == CallingCardBlockKind.space) {
          final gap = _number(raw, min: 0, max: 144);
          if (gap == null) {
            _issue(line, CallingCardIssueKind.badValue, kind.keyword, raw);
          } else {
            space = gap;
          }
        } else {
          _issue(line, CallingCardIssueKind.unknownOption, raw);
        }
        continue;
      }
      if (!allowed.contains(name)) {
        _issue(line, CallingCardIssueKind.unknownOption, name);
        continue;
      }
      void bad() =>
          _issue(line, CallingCardIssueKind.badValue, name, value ?? '');
      switch (name) {
        case 'size':
          final n = kind == CallingCardBlockKind.space
              ? _number(value, min: 0, max: 144)
              : _number(value, min: _minFontSize, max: _maxFontSize);
          if (n == null) {
            bad();
          } else if (kind == CallingCardBlockKind.space) {
            space = n;
          } else {
            size = n;
          }
        case 'bold' || 'italic':
          final flag = _flag(value);
          if (flag == null) {
            bad();
          } else if (name == 'bold') {
            bold = flag;
          } else {
            italic = flag;
          }
        case 'left' || 'center' || 'right':
          if (value != null) {
            bad();
          } else {
            align = CallingCardAlign.values.byName(name);
          }
        case 'color':
          final c = _color(value);
          if (c == null) {
            bad();
          } else {
            color = c;
          }
        case 'lines':
          final n = _int(value, min: 1, max: 99);
          if (n == null) {
            bad();
          } else {
            maxLines = n;
          }
        case 'label':
          if (value == null) {
            bad();
          } else {
            label = value;
          }
        case 'width':
          final n = _int(value, min: 1, max: 12);
          if (n == null) {
            bad();
          } else {
            width = n;
          }
        case 'thickness':
          final n = _number(value, min: 0.25, max: 12);
          if (n == null) {
            bad();
          } else {
            thickness = n;
          }
        case 'beats' || 'notes' || 'phrases' || 'dividers' || 'highlight':
          final flag = _flag(value);
          if (flag == null) {
            bad();
            continue;
          }
          switch (name) {
            case 'beats':
              beats = flag;
            case 'notes':
              figureNotes = flag;
            case 'phrases':
              phrases = flag;
            case 'highlight':
              highlight = flag;
            default:
              dividers = flag;
          }
      }
    }

    if (kind == CallingCardBlockKind.text && (text == null || text.isEmpty)) {
      _issue(line, CallingCardIssueKind.missingText, kind.keyword);
      return null;
    }
    return CallingCardBlock(
      kind: kind,
      size: size,
      bold: bold,
      italic: italic,
      align: align,
      color: color,
      maxLines: maxLines,
      label: label,
      width: width,
      text: text ?? '',
      beats: beats,
      figureNotes: figureNotes,
      phrases: phrases,
      dividers: dividers,
      highlight: highlight,
      thickness: thickness,
      space: space ?? 6,
    );
  }

  /// A bare flag is on; `=on`/`=yes`/`=true` and `=off`/`=no`/`=false` set it.
  static bool? _flag(String? value) => switch (value?.toLowerCase()) {
    null || 'on' || 'yes' || 'true' => true,
    'off' || 'no' || 'false' => false,
    _ => null,
  };

  static double? _number(
    String? value, {
    required double min,
    required double max,
  }) {
    if (value == null) return null;
    final n = double.tryParse(value.trim());
    if (n == null || !n.isFinite || n < min || n > max) return null;
    return n;
  }

  static int? _int(String? value, {required int min, required int max}) {
    if (value == null) return null;
    final n = int.tryParse(value.trim());
    if (n == null || n < min || n > max) return null;
    return n;
  }

  static final _hex = RegExp(r'^#?([0-9a-fA-F]{6}|[0-9a-fA-F]{3})$');

  static int? _color(String? value) {
    final match = value == null ? null : _hex.firstMatch(value.trim());
    if (match == null) return null;
    var hex = match.group(1)!;
    if (hex.length == 3) hex = hex.split('').map((c) => '$c$c').join();
    return int.parse(hex, radix: 16);
  }
}

/// Units a card size is written in.
enum CallingCardUnit {
  inch('in', 72),
  millimetre('mm', 72 / 25.4);

  const CallingCardUnit(this.token, this.points);

  /// The stored spelling.
  final String token;

  /// Points per unit.
  final double points;

  static CallingCardUnit? fromToken(Object? token) {
    for (final unit in values) {
      if (unit.token == token) return unit;
    }
    return null;
  }
}

/// A card's size: [width] across and [height] down, in [unit].
class CallingCardSize {
  const CallingCardSize(this.width, this.height, this.unit);

  final double width;
  final double height;
  final CallingCardUnit unit;

  /// The smallest and largest side accepted, in points (1 inch and 14 inches):
  /// a smaller card has no room for a dance, and a larger one is a sheet, not
  /// a card.
  static const double minSidePoints = 72;
  static const double maxSidePoints = 1008;

  double get widthPoints => width * unit.points;
  double get heightPoints => height * unit.points;
  bool get isLandscape => width >= height;

  /// Whether both sides are within [minSidePoints]..[maxSidePoints].
  bool get isValid =>
      width.isFinite &&
      height.isFinite &&
      widthPoints >= minSidePoints - 1e-6 &&
      heightPoints >= minSidePoints - 1e-6 &&
      widthPoints <= maxSidePoints + 1e-6 &&
      heightPoints <= maxSidePoints + 1e-6;

  /// The same card turned the other way when [landscape] differs from
  /// [isLandscape].
  CallingCardSize oriented({required bool landscape}) =>
      landscape == isLandscape ? this : CallingCardSize(height, width, unit);

  /// The same size with sides in either order: a preset matches a card in
  /// either orientation.
  bool sameCardAs(CallingCardSize other) =>
      unit == other.unit &&
      math.min(width, height) == math.min(other.width, other.height) &&
      math.max(width, height) == math.max(other.width, other.height);

  @override
  bool operator ==(Object other) =>
      other is CallingCardSize &&
      other.width == width &&
      other.height == height &&
      other.unit == unit;

  @override
  int get hashCode => Object.hash(width, height, unit);

  @override
  String toString() => '${width}x$height${unit.token}';
}

/// Card sizes offered by name, in landscape. The ids are stable; the app
/// localizes their labels.
const Map<String, CallingCardSize> kCallingCardSizePresets = {
  'index3x5': CallingCardSize(5, 3, CallingCardUnit.inch),
  'index4x6': CallingCardSize(6, 4, CallingCardUnit.inch),
  'index5x8': CallingCardSize(8, 5, CallingCardUnit.inch),
  'a6': CallingCardSize(148, 105, CallingCardUnit.millimetre),
  'a7': CallingCardSize(105, 74, CallingCardUnit.millimetre),
};

/// The size a card prints at until the user picks another.
const CallingCardSize kDefaultCallingCardSize = CallingCardSize(
  5,
  3,
  CallingCardUnit.inch,
);

/// Everything Settings › Experimental › Calling cards stores, under one
/// settings key as a JSON object.
class CallingCardSettings {
  const CallingCardSettings({
    this.enabled = false,
    this.size = kDefaultCallingCardSize,
    this.layout,
    this.onSheets = false,
  });

  /// Whether the Export menus offer calling cards.
  final bool enabled;
  final CallingCardSize size;

  /// Whether cards print several to a page on the paper the print dialog
  /// chooses, with marks to cut along, instead of one per page at the card's
  /// own size.
  final bool onSheets;

  /// The user's layout, or `null` for [kDefaultCallingCardLayout]. Kept `null`
  /// until the user changes it, so a better default reaches everyone who never
  /// edited theirs.
  final String? layout;

  static const CallingCardSettings defaults = CallingCardSettings();

  /// The layout text in effect.
  String get layoutSource => layout ?? kDefaultCallingCardLayout;

  CallingCardSettings copyWith({
    bool? enabled,
    CallingCardSize? size,
    String? Function()? layout,
    bool? onSheets,
  }) => CallingCardSettings(
    enabled: enabled ?? this.enabled,
    size: size ?? this.size,
    layout: layout == null ? this.layout : layout(),
    onSheets: onSheets ?? this.onSheets,
  );

  /// The stored JSON object. A layout identical to the default is stored as
  /// absent.
  Map<String, Object?> toJson() => {
    'enabled': enabled,
    'width': size.width,
    'height': size.height,
    'unit': size.unit.token,
    if (layout case final text? when text != kDefaultCallingCardLayout)
      'layout': text,
    'sheets': onSheets,
  };

  /// Reads a stored value. Stored values are untrusted: anything missing,
  /// wrong-typed or out of range falls back to its default, field by field.
  static CallingCardSettings fromJson(Object? stored) {
    if (stored is! Map) return defaults;
    final enabled = stored['enabled'];
    final width = stored['width'];
    final height = stored['height'];
    final unit = CallingCardUnit.fromToken(stored['unit']);
    var size = kDefaultCallingCardSize;
    if (width is num && height is num && unit != null) {
      final candidate = CallingCardSize(
        width.toDouble(),
        height.toDouble(),
        unit,
      );
      if (candidate.isValid) size = candidate;
    }
    final layout = stored['layout'];
    final sheets = stored['sheets'];
    return CallingCardSettings(
      enabled: enabled is bool && enabled,
      size: size,
      layout: layout is String && layout != kDefaultCallingCardLayout
          ? layout
          : null,
      onSheets: sheets is bool && sheets,
    );
  }

  /// Whether [stored] is a value [fromJson] reads without falling back on any
  /// field: the backup restore's check.
  static bool isWellFormed(Object? stored) {
    if (stored is! Map) return false;
    final width = stored['width'];
    final height = stored['height'];
    final unit = CallingCardUnit.fromToken(stored['unit']);
    final layout = stored['layout'];
    final sheets = stored['sheets'];
    return stored['enabled'] is bool &&
        // Absent in values stored before the setting existed.
        (sheets == null || sheets is bool) &&
        width is num &&
        height is num &&
        unit != null &&
        CallingCardSize(width.toDouble(), height.toDouble(), unit).isValid &&
        (layout == null || layout is String);
  }

  @override
  bool operator ==(Object other) =>
      other is CallingCardSettings &&
      other.enabled == enabled &&
      other.size == size &&
      other.layout == layout &&
      other.onSheets == onSheets;

  @override
  int get hashCode => Object.hash(enabled, size, layout, onSheets);
}
