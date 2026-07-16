/// A pure-Dart decoder for the *Standard Compression Scheme for Unicode*
/// (SCSU, Unicode Technical Standard #6), the text encoding FileMaker Pro 12
/// uses for stored string values.
///
/// This is a faithful port of the reference C implementation in the
/// MIT-licensed `fmptools` project (`src/scsu.c`, © 2020 Evan Miller) — see
/// `docs/design/imports.md` §2 and the adapter that consumes it. It is kept
/// deliberately close to the original (same control-code handling, same
/// CR/VT/LF and tab normalisation) so its output matches `fmp2json`/`fmp2sqlite`
/// on real files, which is how the reader is validated.
///
/// Pure Dart (no `dart:convert` codec, no `package:flutter`) so it can live in
/// the Flutter-free core.
library;

const List<int> _staticWindowOffsets = <int>[
  0x0000, // Quoting tags
  0x0080, // Latin-1 Supplement
  0x0100, // Latin Extended-A
  0x0300, // Combining Diacritical Marks
  0x2000, // General Punctuation
  0x2080, // Currency Symbols
  0x2100, // Letterlike Symbols and Number Forms
  0x3000, // CJK Symbols and Punctuation
];

const List<int> _initialDynamicWindowOffsets = <int>[
  0x0080, // Latin-1 Supplement
  0x00C0, // partial Latin-1 Supplement + Latin Extended A
  0x0400, // Cyrillic
  0x0600, // Arabic
  0x0900, // Devanagari
  0x3040, // Hiragana
  0x30A0, // Katakana
  0xFF00, // Fullwidth ASCII
];

// Single-byte mode control codes.
const int _sq0 = 0x01, _sq7 = 0x08;
const int _sdx = 0x0B;
const int _squ = 0x0E;
const int _scu = 0x0F;
const int _sc0 = 0x10, _sc7 = 0x17;
const int _sd0 = 0x18, _sd7 = 0x1F;

// Unicode-mode control codes.
const int _uc0 = 0xE0, _uc7 = 0xE7;
const int _ud0 = 0xE8, _ud7 = 0xEF;
const int _uqu = 0xF0;
const int _udx = 0xF1;

int _offsetTable(int x) {
  if (x > 0 && x < 0x68) return x * 0x80;
  if (x < 0xA8) return x * 0x80 + 0xAC00;
  switch (x) {
    case 0xF9:
      return 0xC0;
    case 0xFA:
      return 0x0250;
    case 0xFB:
      return 0x0370;
    case 0xFC:
      return 0x0530;
    case 0xFD:
      return 0x3040;
    case 0xFE:
      return 0x30A0;
    case 0xFF:
      return 0xFF60;
    default:
      return 0; // Reserved
  }
}

int _extendedOffset(int hByte, int lByte) =>
    10000 + 80 * ((hByte & 0x1F) * 100 + lByte);

/// Decodes SCSU-encoded [src] bytes into a Dart string.
///
/// Mirrors `convert_scsu_to_utf8`: control bytes select static/dynamic windows
/// or Unicode mode; CR/LF/VT collapse to `\n`; tab becomes a space. Truncated
/// trailing sequences stop decoding gracefully (never throws) — consistent with
/// the parse-never-fails invariant.
String decodeScsu(List<int> src) {
  final dynamicWindowOffsets = List<int>.of(_initialDynamicWindowOffsets);
  final out = StringBuffer();

  var i = 0;
  var shift = 0;
  var unicode = false;
  var activeWindow = 0;
  var lastU = 0;

  while (i < src.length) {
    final c = src[i++];
    int u = 0;

    if (unicode) {
      if (c == _uqu) {
        if (i + 2 <= src.length) {
          u = (src[i] << 8) + src[i + 1];
          i += 2;
        } else {
          break;
        }
      } else if (c >= _uc0 && c <= _uc7) {
        activeWindow = c - _uc0;
        unicode = false;
        continue;
      } else if (c >= _ud0 && c <= _ud7) {
        if (i < src.length) {
          activeWindow = c - _ud0;
          dynamicWindowOffsets[activeWindow] = _offsetTable(src[i++]);
          unicode = false;
          continue;
        }
        break;
      } else if (c == _udx) {
        if (i + 2 <= src.length) {
          activeWindow = (c & 0xE0) >> 5;
          dynamicWindowOffsets[activeWindow] = _extendedOffset(
            src[i],
            src[i + 1],
          );
          i += 2;
          unicode = false;
          continue;
        }
        break;
      } else {
        if (i < src.length) {
          u = (c << 8) + src[i++];
        } else {
          break;
        }
      }
    } else if (shift != 0) {
      u = _staticWindowOffsets[shift - _sq0] + c;
      shift = 0;
    } else if (c == _scu) {
      unicode = true;
      continue;
    } else if (c == _squ) {
      if (i + 2 <= src.length) {
        u = (src[i] << 8) + src[i + 1];
        i += 2;
      } else {
        break;
      }
    } else if (c >= _sq0 && c <= _sq7) {
      shift = c;
      continue;
    } else if (c >= _sc0 && c <= _sc7) {
      activeWindow = c - _sc0;
      continue;
    } else if (c >= _sd0 && c <= _sd7) {
      if (i < src.length) {
        activeWindow = c - _sd0;
        dynamicWindowOffsets[activeWindow] = _offsetTable(src[i++]);
        continue;
      }
      break;
    } else if (c == _sdx) {
      if (i + 2 <= src.length) {
        activeWindow = (c & 0xE0) >> 5;
        dynamicWindowOffsets[activeWindow] = _extendedOffset(
          src[i],
          src[i + 1],
        );
        i += 2;
        continue;
      }
      break;
    } else if (c == 0x09) {
      u = 0x20; // Encode tab as space (matches reference).
    } else if (c == 0x0A && lastU == 0x0D) {
      lastU = c;
      continue; // Collapse CRLF to LF.
    } else if (c == 0x0A || c == 0x0B || c == 0x0D) {
      u = 0x0A; // CR, VT, LF → LF.
    } else if (c >= 0x20 && c <= 0x7F) {
      u = c; // ASCII pass-through.
    } else if (c >= 0x80) {
      u = dynamicWindowOffsets[activeWindow] + (c - 0x80);
    } else {
      u = 0xFFFD;
    }

    // High surrogate: the reference does not carry it across iterations, so a
    // lone surrogate is dropped rather than throwing. Replicated for parity.
    if (u >= 0xD800 && u <= 0xDBFF) {
      continue;
    }

    if (u > 0) {
      out.writeCharCode(u);
    }
    lastU = u;
  }

  return out.toString();
}
