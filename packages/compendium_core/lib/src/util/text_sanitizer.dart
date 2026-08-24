/// OWASP input-hygiene sanitizer for imported text.
///
/// Caller's Compendium ingests dance/figure text from external sources (the
/// generic JSON/`.ccshare` archive, ContraDB HTML, The Caller's Box, Caller's
/// Companion). There is **no XSS path** — imported data is never rendered as
/// HTML or in a WebView (see issue #444) — so this module does *not* do HTML
/// escaping. Its job is narrower and orthogonal: strip invisible/deceptive
/// Unicode that enables *display spoofing* (e.g. a right-to-left override that
/// visually reverses a title, or a control/format character smuggled into a
/// name) before the text is persisted.
///
/// Sanitizing at **ingress** (not merely at display) is deliberate: the stored
/// value is the source of truth every screen, export, search index and share
/// file reads, so scrubbing once on the way in protects all of them and follows
/// the OWASP "fail safe — strip rather than trust" guidance.
///
/// Deliberately **out of scope**: homoglyph/confusable folding. A robust
/// confusable check needs the Unicode confusables table, which is large and
/// would bloat the app for a low-severity, display-only concern (issue #444
/// scopes it as optional). We strip the machinery of spoofing (bidi + invisible
/// format characters) without shipping a heavy lookup table.
library;

/// Returns [input] with disallowed control, bidi-control and invisible/format
/// characters removed.
///
/// Removed characters:
/// - **C0 controls** `U+0000–U+001F` and **C1 controls** `U+0080–U+009F`, plus
///   `U+007F` (DEL). When [allowLineBreaks] is true (the default) the ordinary
///   whitespace controls tab (`U+0009`), line feed (`U+000A`) and carriage
///   return (`U+000D`) are preserved so multi-line fields (notes, calling
///   notes) keep their structure; when false, they are stripped too (useful for
///   strictly single-line fields).
/// - **Bidirectional controls**: the embeddings/overrides `U+202A–U+202E`, the
///   isolates `U+2066–U+2069`, the marks `U+200E`/`U+200F` (LRM/RLM) and
///   `U+061C` (Arabic letter mark) — the characters used for RTL-override
///   spoofing.
/// - **Invisible / default-ignorable format characters** used to hide or
///   fragment text: the zero-width space `U+200B`, the word-joiner /
///   invisible-operator block `U+2060–U+2064`, deprecated format controls
///   `U+206A–U+206F`, the byte-order mark `U+FEFF`, `U+180E`, the interlinear
///   annotation anchors `U+FFF9–U+FFFB`, the tag block `U+E0000–U+E007F`, and a
///   handful of script-specific format controls (Kaithi, Egyptian hieroglyph,
///   Duployan, musical).
/// - **Line/paragraph separators** `U+2028`/`U+2029` (spoofing/log-injection
///   risk; distinct from the newline preserved above).
/// - **Noncharacters** `U+FDD0–U+FDEF` and the `U+xxFFFE`/`U+xxFFFF` pair in
///   every plane.
/// - **Unpaired UTF-16 surrogates** `U+D800–U+DFFF`. Valid surrogate pairs are
///   decoded by [String.runes] as one astral code point and are preserved.
///
/// Legitimate content is preserved: ordinary letters/marks/punctuation in any
/// script, emoji (including emoji *ZWJ sequences* such as family/profession
/// glyphs) and variation selectors (`U+FE00–U+FE0F`, `U+E0100–U+E01EF`).
///
/// **Joiners are preserved.** The zero-width joiner (`U+200D`, ZWJ) and
/// non-joiner (`U+200C`, ZWNJ) are *shaping* controls, not bidi-reordering
/// ones: emoji ZWJ sequences and several scripts (Arabic, Persian, a number of
/// Indic scripts) require them for correct rendering, and — unlike bidi
/// overrides — they do not visually reorder surrounding text, so they are not a
/// display-spoofing vector. Stripping them would corrupt legitimate data, so we
/// keep them. (Confusable/homoglyph folding — the tool that would treat
/// joiner-based look-alikes — is intentionally out of scope; see below.) Note
/// the neighbouring bidi marks `U+200E`/`U+200F` (LRM/RLM) and the zero-width
/// space `U+200B` *are* stripped: those are spoofing/hiding vectors with no
/// shaping role.
///
/// The function is a pure, idempotent transform, so applying it more than once
/// (e.g. at both an adapter and a shared chokepoint) is safe. When nothing is
/// stripped the original instance is returned unchanged.
String sanitizeImportedText(String input, {bool allowLineBreaks = true}) {
  if (input.isEmpty) return input;

  // Fast path: leave clean input (the overwhelmingly common case) untouched so
  // we neither allocate nor perturb the archive round-trip identity property.
  var dirty = false;
  for (final rune in input.runes) {
    if (_isDisallowed(rune, allowLineBreaks)) {
      dirty = true;
      break;
    }
  }
  if (!dirty) return input;

  final buffer = StringBuffer();
  for (final rune in input.runes) {
    if (!_isDisallowed(rune, allowLineBreaks)) {
      buffer.writeCharCode(rune);
    }
  }
  return buffer.toString();
}

/// Whether [input] contains any character [sanitizeImportedText] would strip.
///
/// Useful for callers that want to *flag* (rather than silently clean) suspect
/// imported text — e.g. surfacing an import warning while still storing the
/// sanitized value.
bool containsDisallowedText(String input, {bool allowLineBreaks = true}) {
  for (final rune in input.runes) {
    if (_isDisallowed(rune, allowLineBreaks)) return true;
  }
  return false;
}

bool _isDisallowed(int cp, bool allowLineBreaks) {
  // `String.runes` exposes an unpaired UTF-16 code unit as its surrogate value,
  // while a valid pair is exposed as one astral code point and cannot match
  // this range.
  if (cp >= 0xD800 && cp <= 0xDFFF) return true;

  // Ordinary whitespace controls are legitimate structure in most fields.
  if (cp == 0x09 || cp == 0x0A || cp == 0x0D) return !allowLineBreaks;

  // C0 controls (U+0000–U+001F), DEL (U+007F) and C1 controls (U+0080–U+009F).
  if (cp <= 0x1F) return true;
  if (cp == 0x7F) return true;
  if (cp >= 0x80 && cp <= 0x9F) return true;

  // Arabic letter mark (bidi).
  if (cp == 0x061C) return true;

  // Mongolian vowel separator (invisible format).
  if (cp == 0x180E) return true;

  // Zero-width space and bidi marks (spoofing/hiding vectors). The zero-width
  // joiner U+200D (ZWJ) and non-joiner U+200C (ZWNJ) that sit between are
  // deliberately NOT stripped: they are shaping controls required by emoji ZWJ
  // sequences and Arabic/Persian/Indic scripts, and they do not reorder text,
  // so they are not a display-spoofing vector (see the library dartdoc).
  if (cp == 0x200B) return true; // ZWSP (zero-width space)
  if (cp == 0x200E || cp == 0x200F) return true; // LRM / RLM (bidi marks)
  if (cp >= 0x202A && cp <= 0x202E) return true; // LRE..RLO
  if (cp == 0x2028 || cp == 0x2029) return true; // line/paragraph separators
  if (cp >= 0x2060 && cp <= 0x2064) return true; // word joiner..invisible plus
  if (cp >= 0x206A && cp <= 0x206F) return true; // deprecated format controls
  if (cp >= 0x2066 && cp <= 0x2069) return true; // LRI..PDI (bidi isolates)

  // Byte-order mark / zero-width no-break space.
  if (cp == 0xFEFF) return true;

  // Interlinear annotation anchors.
  if (cp >= 0xFFF9 && cp <= 0xFFFB) return true;

  // Arabic-script noncharacters and the per-plane U+xxFFFE/U+xxFFFF pair.
  if (cp >= 0xFDD0 && cp <= 0xFDEF) return true;
  if ((cp & 0xFFFE) == 0xFFFE) return true;

  // Script-specific format controls (kept explicit and bounded).
  if (cp == 0x110BD || cp == 0x110CD) return true; // Kaithi number sign
  if (cp >= 0x13430 && cp <= 0x1343F) return true; // Egyptian hieroglyph format
  if (cp >= 0x1BCA0 && cp <= 0x1BCA3) return true; // Duployan shorthand format
  if (cp >= 0x1D173 && cp <= 0x1D17A) return true; // Musical symbol format

  // Tags block (incl. the deprecated language tag) — pure spoofing surface.
  if (cp >= 0xE0000 && cp <= 0xE007F) return true;

  return false;
}
