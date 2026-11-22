/// A dance as a link, and as a QR code to show in person (#2334).
///
/// The link carries exactly what a shared dance file carries: the output of
/// `buildDanceShareBundle`, compressed with raw DEFLATE, Base64url-encoded
/// without padding, behind `ccdance://<version>/`. This file never builds or
/// filters that JSON; whatever privacy filtering `buildDanceShareBundle`
/// applies is therefore inherited, and there is no second serialiser.
///
/// The payload lives in the URL *path*, never the host: an operating system
/// lowercases a URL's host, and Base64url is case-sensitive.
///
/// Two halves:
///
/// * [encodeDanceLink] and [planDanceCode]: what to show. The plan picks the
///   strongest error-correction level at which the link fits, and says whether
///   the brand mark may sit in the middle of the code.
/// * [decodeDanceLink]: the inverse, for the receiving side (#2335). It treats
///   its input as hostile and answers with a [DanceLinkException], never an
///   `Error`: it refuses a link past [kMaxDanceLinkLength], anything that is
///   not a version-1 dance link, a payload that inflates past
///   [kMaxDanceInflatedBytes], and one that inflates to nothing, to bytes that
///   are not UTF-8, or to text that is not a JSON object. A truncated raw
///   DEFLATE stream is *not* an error to `dart:io`: it returns whatever it
///   has, possibly nothing. What turns that into a refusal is the JSON-object
///   check, since no proper prefix of a JSON object is itself one. Bytes after
///   the end of the DEFLATE stream are ignored. Whether the JSON is a
///   well-formed archive is the importer's question, not this file's.
///
/// No network is involved in either half.
library;

import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:barcode/barcode.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

/// The text every dance link starts with, scheme and format version.
const String danceLinkPrefix = 'ccdance://1/';

/// The only format version [decodeDanceLink] reads.
const int danceLinkVersion = 1;

const String _danceLinkScheme = 'ccdance://';

/// The largest QR version (1 to 40, 4 modules wider each step) the app will
/// draw. 40 is the QR maximum, so this adds no restriction yet.
///
/// PROVISIONAL: the intended value comes from scanning real codes on real
/// phones, which has not been done. A code near version 40 (177 by 177
/// modules) is hard to scan from a phone screen. The seed dance already needs
/// version 31 at level H, so a value below 31 would stop it showing the mark.
const int kMaxDanceCodeVersion = 40;

/// The longest link [decodeDanceLink] reads, in characters. A code holds at
/// most 2,953 bytes, so no link this app shows is longer than that plus the
/// prefix; the margin is for a link pasted with other text around it.
const int kMaxDanceLinkLength = 4096;

/// The most a payload may inflate to, in bytes. A real dance's bundle is a few
/// KiB, and a link of [kMaxDanceLinkLength] characters carries about 3 KiB of
/// compressed data. The cap bounds more than the inflated bytes: validating
/// them parses the JSON, which costs tens of times their size in memory when
/// it is deeply nested (an 8 MiB payload cost about 370 MiB). Far below the
/// 25 MiB an opened file may be (`kMaxIncomingArchiveBytes`).
const int kMaxDanceInflatedBytes = 512 * 1024;

/// QR error-correction levels, strongest first, with how many bytes a version
/// 40 code holds in byte mode at that level (ISO/IEC 18004).
enum DanceCodeLevel {
  /// Recovers about 30% of the code: the only level safe to put the brand
  /// mark over.
  high(BarcodeQRCorrectionLevel.high, 1273),
  quartile(BarcodeQRCorrectionLevel.quartile, 1663),
  medium(BarcodeQRCorrectionLevel.medium, 2331),
  low(BarcodeQRCorrectionLevel.low, 2953);

  const DanceCodeLevel(this._barcodeLevel, this.byteCapacity);

  final BarcodeQRCorrectionLevel _barcodeLevel;

  /// Bytes a version 40 code holds at this level.
  final int byteCapacity;
}

/// Turns a share bundle's JSON into a dance link.
String encodeDanceLink(String shareBundleJson) {
  final inflated = utf8.encode(shareBundleJson);
  final deflated = ZLibCodec(raw: true, level: 9).encode(inflated);
  final payload = base64Url.encode(deflated).replaceAll('=', '');
  return '$danceLinkPrefix$payload';
}

/// What to show for one dance.
sealed class DanceCodePlan {
  const DanceCodePlan();
}

/// A code that can be shown.
final class DanceCodeShown extends DanceCodePlan {
  DanceCodeShown({
    required this.link,
    required this.level,
    required this.version,
    required this.moduleCount,
    required this.modules,
  });

  /// The link the code holds.
  final String link;

  final DanceCodeLevel level;

  /// QR version, 1 to 40.
  final int version;

  /// Modules per side: `version * 4 + 17`.
  final int moduleCount;

  /// Row-major, [moduleCount] squared entries; 1 is a dark module.
  final Uint8List modules;

  /// Whether the brand mark may cover the middle of the code. Only at level H.
  bool get withMark => level == DanceCodeLevel.high;

  bool isDark(int row, int column) => modules[row * moduleCount + column] == 1;
}

/// The dance does not fit a code at any level within the version limit.
final class DanceCodeTooLong extends DanceCodePlan {
  const DanceCodeTooLong({required this.linkBytes});

  /// How long the link would have been.
  final int linkBytes;
}

/// Picks how to show [shareBundleJson] as a code.
///
/// Tries level H, then Q, M and L, and takes the first that fits within
/// [maxVersion]; only H carries the mark ([DanceCodeShown.withMark]). When
/// none fits the result is [DanceCodeTooLong].
DanceCodePlan planDanceCode(
  String shareBundleJson, {
  int maxVersion = kMaxDanceCodeVersion,
}) => planDanceLink(encodeDanceLink(shareBundleJson), maxVersion: maxVersion);

/// [planDanceCode] for a link already built. Separate so a test can offer a
/// link of an exact length, which compression makes hard to reach from JSON.
@visibleForTesting
DanceCodePlan planDanceLink(
  String link, {
  int maxVersion = kMaxDanceCodeVersion,
}) {
  RangeError.checkValueInInterval(maxVersion, 1, 40, 'maxVersion');
  // A fresh list, not a view: `barcode` reads the whole backing buffer on one
  // of its code paths.
  final bytes = Uint8List.fromList(ascii.encode(link));
  for (final level in DanceCodeLevel.values) {
    // The encoder throws on input past a version-40 code, and `barcode` does
    // not export the exception, so a link that cannot fit is never offered.
    if (bytes.length > level.byteCapacity) continue;
    final (moduleCount, modules) = _encode(bytes, level);
    final version = (moduleCount - 17) ~/ 4;
    if (version > maxVersion) continue;
    return DanceCodeShown(
      link: link,
      level: level,
      version: version,
      moduleCount: moduleCount,
      modules: modules,
    );
  }
  return DanceCodeTooLong(linkBytes: bytes.length);
}

/// `barcode` exposes a QR code only as drawing rectangles. Draw it on a 1000
/// unit square, read the module count off the height of one row, and rebuild
/// the grid from the dark rectangles.
(int, Uint8List) _encode(Uint8List bytes, DanceCodeLevel level) {
  const canvas = 1000.0;
  final bars = Barcode.qrCode(
    errorCorrectLevel: level._barcodeLevel,
  ).makeBytes(bytes, width: canvas, height: canvas).whereType<BarcodeBar>();
  final list = bars.toList();
  if (list.isEmpty) throw StateError('QR encoder produced no modules');
  final n = (canvas / list.first.height).round();
  if (n < 21 || n > 177 || (n - 17) % 4 != 0) {
    throw StateError('QR encoder produced an impossible size: $n modules');
  }
  final modules = Uint8List(n * n);
  for (final bar in list) {
    if (!bar.black) continue;
    final row = (bar.top * n / canvas).round();
    final first = (bar.left * n / canvas).round();
    final count = (bar.width * n / canvas).round();
    for (var c = first; c < first + count; c++) {
      modules[row * n + c] = 1;
    }
  }
  // The three finder patterns start with a dark corner module. A wrong module
  // count would not leave all three in place.
  if (modules[0] != 1 || modules[n - 1] != 1 || modules[(n - 1) * n] != 1) {
    throw StateError('QR encoder output is not a QR grid');
  }
  return (n, modules);
}

/// Why a link was refused.
enum DanceLinkFailure {
  /// Longer than the length limit, which is checked before anything else.
  tooLong,

  /// Not `ccdance://<version>/<payload>`.
  notADanceLink,

  /// A dance link, but not a version this build reads.
  unknownVersion,

  /// The payload is not unpadded Base64url.
  malformedBase64,

  /// The payload is not a valid DEFLATE stream.
  inflateFailed,

  /// The payload inflates past the cap.
  tooLarge,

  /// The payload inflates to nothing. Includes a stream cut short: `dart:io`
  /// does not report truncation.
  empty,

  /// The inflated bytes are not UTF-8.
  notUtf8,

  /// The inflated text is not a JSON object. Includes a stream cut short.
  notAJsonObject,
}

class DanceLinkException implements Exception {
  const DanceLinkException(this.failure);

  final DanceLinkFailure failure;

  @override
  String toString() => 'DanceLinkException: $failure';
}

/// Whether every character of [text] is in the Base64url alphabet. A loop,
/// not a regular expression: the VM's regular expression engine overflows its
/// stack on a payload of several million characters.
bool _isBase64Url(String text) {
  for (var i = 0; i < text.length; i++) {
    final c = text.codeUnitAt(i);
    final ok =
        (c >= 0x41 && c <= 0x5A) || // A-Z
        (c >= 0x61 && c <= 0x7A) || // a-z
        (c >= 0x30 && c <= 0x39) || // 0-9
        c == 0x2D || // -
        c == 0x5F; // _
    if (!ok) return false;
  }
  return true;
}

/// Reads the share bundle JSON out of [link]: byte for byte what
/// [encodeDanceLink] was given. Throws [DanceLinkException] for anything else.
///
/// A link longer than [maxLinkLength] is refused before it is looked at. The
/// payload may inflate to at most [maxInflatedBytes]; the stream is read in
/// chunks and abandoned at the cap, so a small link cannot make a large
/// allocation. [onInflated] is told the running total after each chunk, for
/// tests that must show the bound held.
String decodeDanceLink(
  String link, {
  int maxLinkLength = kMaxDanceLinkLength,
  int maxInflatedBytes = kMaxDanceInflatedBytes,
  @visibleForTesting void Function(int inflatedBytes)? onInflated,
}) {
  if (link.length > maxLinkLength) {
    throw const DanceLinkException(DanceLinkFailure.tooLong);
  }
  if (link.length < _danceLinkScheme.length ||
      link.substring(0, _danceLinkScheme.length).toLowerCase() !=
          _danceLinkScheme) {
    throw const DanceLinkException(DanceLinkFailure.notADanceLink);
  }
  final rest = link.substring(_danceLinkScheme.length);
  final slash = rest.indexOf('/');
  if (slash <= 0) {
    throw const DanceLinkException(DanceLinkFailure.notADanceLink);
  }
  if (rest.substring(0, slash) != '$danceLinkVersion') {
    throw const DanceLinkException(DanceLinkFailure.unknownVersion);
  }
  final payload = rest.substring(slash + 1);
  if (payload.isEmpty) {
    throw const DanceLinkException(DanceLinkFailure.empty);
  }
  if (!_isBase64Url(payload) || payload.length % 4 == 1) {
    throw const DanceLinkException(DanceLinkFailure.malformedBase64);
  }
  final Uint8List deflated;
  try {
    deflated = base64Url.decode(base64Url.normalize(payload));
  } on FormatException {
    // diagnostics: silent — hostile input is refused by returning a typed
    // failure to the caller, which owns what to tell the user.
    throw const DanceLinkException(DanceLinkFailure.malformedBase64);
  }

  final sink = _CappedSink(maxInflatedBytes, onInflated);
  try {
    final conversion = ZLibDecoder(raw: true).startChunkedConversion(sink);
    conversion.add(deflated);
    conversion.close();
  } on _InflateCapExceeded {
    // diagnostics: silent — see above.
    throw const DanceLinkException(DanceLinkFailure.tooLarge);
  } on FormatException {
    // diagnostics: silent — see above.
    throw const DanceLinkException(DanceLinkFailure.inflateFailed);
  }
  final inflated = sink.takeBytes();
  if (inflated.isEmpty) {
    throw const DanceLinkException(DanceLinkFailure.empty);
  }
  // `utf8.decode` drops a leading byte-order mark, which would make the result
  // differ from what was encoded. A bundle never starts with one, and JSON
  // may not.
  if (inflated.length >= 3 &&
      inflated[0] == 0xEF &&
      inflated[1] == 0xBB &&
      inflated[2] == 0xBF) {
    throw const DanceLinkException(DanceLinkFailure.notAJsonObject);
  }
  final String text;
  try {
    text = utf8.decode(inflated);
  } on FormatException {
    // diagnostics: silent — see above.
    throw const DanceLinkException(DanceLinkFailure.notUtf8);
  }
  try {
    if (jsonDecode(text) is! Map) {
      throw const DanceLinkException(DanceLinkFailure.notAJsonObject);
    }
  } on FormatException {
    // diagnostics: silent — see above.
    throw const DanceLinkException(DanceLinkFailure.notAJsonObject);
  }
  return text;
}

class _InflateCapExceeded implements Exception {
  const _InflateCapExceeded();
}

class _CappedSink implements Sink<List<int>> {
  _CappedSink(this._cap, this._onInflated);

  final int _cap;
  final void Function(int)? _onInflated;
  final BytesBuilder _bytes = BytesBuilder();
  int _total = 0;

  @override
  void add(List<int> chunk) {
    _total += chunk.length;
    _onInflated?.call(_total);
    if (_total > _cap) throw const _InflateCapExceeded();
    _bytes.add(chunk);
  }

  @override
  void close() {}

  Uint8List takeBytes() => _bytes.takeBytes();
}
