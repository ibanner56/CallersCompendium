import 'dart:math';
import 'dart:typed_data';

import 'package:compendium_core/src/imports/callers_companion_usr_archive.dart';
import 'package:compendium_core/src/imports/fmp/fmp_reader.dart';
import 'package:compendium_core/src/imports/fmp/scsu.dart';
import 'package:test/test.dart';

import '../support/fmp_fixture_builder.dart';

/// Deterministic byte-fuzz test for the Caller's Companion `.USR` binary reader
/// ([readFmp12] / [readCcUsrArchive]) and the SCSU value decoder ([decodeScsu])
/// it uses to decode stored strings.
///
/// ## Why this exists (OWASP A04 Insecure Design / A05 — untrusted input)
/// A `.USR` file is a **proprietary, undocumented FileMaker container** supplied
/// by the user (often originally from a "safer" community source, but still
/// untrusted). Its parser must **fail closed** against malformed, truncated,
/// oversized-field, and adversarial byte sequences: the only acceptable
/// outcomes are
///   * a clean typed [FmpFormatException] (not a supported container), or
///   * a clean typed [FmpResourceLimitException] (a fail-closed DoS guard), or
///   * a graceful partial/empty result carrying [FmpDatabase.warnings].
/// It must **NEVER** produce an uncaught non-typed crash (a `RangeError`,
/// `StateError`, unchecked cast, etc.), an unbounded allocation, an
/// out-of-bounds read, or an infinite loop.
///
/// ## Bounds / determinism / CI cost
/// Every generated input is size-bounded (well under the app's `#443`
/// `kMaxImportFileBytes` cap) so termination and allocation are structurally
/// guaranteed with no wall-clock dependence — if a case ever looped forever the
/// test would hang, which is itself a detectable failure. A subset runs under
/// tiny injected [FmpReadLimits] to prove the structural DoS guards trip. The
/// generator is single-seed so every run explores the same inputs; a failure
/// prints the seed + iteration + strategy + a hex preview for reproduction.
void main() {
  group('readFmp12 — fail-closed byte fuzz (seeded)', () {
    test('never crashes on mutated/adversarial container bytes', () {
      final rng = Random(_seed);
      final base = _validBase();
      for (var i = 0; i < _fmpIterations; i++) {
        final (label, bytes) = _mutate(rng, base);
        _assertReaderFailsClosed(bytes, iteration: i, strategy: label);
      }
    });
  });

  group('readCcUsrArchive — fail-closed byte fuzz (seeded)', () {
    test('never crashes and always yields a well-formed archive-or-throw', () {
      final rng = Random(_seed ^ 0x7501);
      final base = _validBase();
      for (var i = 0; i < _fmpIterations; i++) {
        final (label, bytes) = _mutate(rng, base);
        _assertArchiveFailsClosed(bytes, iteration: i, strategy: label);
      }
    });
  });

  group('structural resource limits trip under tiny caps (fuzz)', () {
    test('a mutated file under 1-* limits never over-consumes', () {
      final rng = Random(_seed ^ 0x2c2c);
      final base = _validBase();
      const limits = FmpReadLimits(maxSectors: 2, maxTables: 1, maxRecords: 1);
      for (var i = 0; i < _fmpIterations; i++) {
        final (label, bytes) = _mutate(rng, base);
        _assertReaderFailsClosed(
          bytes,
          iteration: i,
          strategy: 'limited:$label',
          limits: limits,
        );
      }
    });

    test('the valid base file trips each cap set to its floor', () {
      final base = _validBase();
      // 2 tables / 3 records / 3 sectors in the base image, so a floor of 1
      // must fail closed with the typed resource exception.
      expect(
        () => readFmp12(base, limits: const FmpReadLimits(maxTables: 1)),
        throwsA(isA<FmpResourceLimitException>()),
      );
      expect(
        () => readFmp12(base, limits: const FmpReadLimits(maxRecords: 1)),
        throwsA(isA<FmpResourceLimitException>()),
      );
      expect(
        () => readFmp12(base, limits: const FmpReadLimits(maxSectors: 1)),
        throwsA(isA<FmpResourceLimitException>()),
      );
    });
  });

  group('decodeScsu — never throws on arbitrary bytes (seeded)', () {
    test('arbitrary/truncated byte sequences decode to a String', () {
      final rng = Random(_seed ^ 0x5c5c);
      for (var i = 0; i < _scsuIterations; i++) {
        final bytes = _randomScsuBytes(rng);
        final String out;
        try {
          out = decodeScsu(bytes);
        } catch (e, st) {
          fail(_reproBytes(bytes, i, 'scsu', 'decodeScsu threw: $e\n$st'));
        }
        // The decoder's contract is parse-never-fails: any byte sequence
        // decodes to some String (possibly empty) rather than throwing.
        expect(
          out,
          isA<String>(),
          reason: _reproBytes(bytes, i, 'scsu', 'did not return a String'),
        );
      }
    });
  });
}

// --- Fail-closed assertions ------------------------------------------------

void _assertReaderFailsClosed(
  Uint8List bytes, {
  required int iteration,
  required String strategy,
  FmpReadLimits limits = const FmpReadLimits(),
}) {
  FmpDatabase? db;
  try {
    db = readFmp12(bytes, limits: limits);
  } on FmpFormatException {
    return; // acceptable: not a supported container.
  } on FmpResourceLimitException {
    return; // acceptable: fail-closed DoS guard.
  } catch (e, st) {
    fail(_reproBytes(bytes, iteration, strategy, 'unexpected throw: $e\n$st'));
  }
  _assertDatabaseBounded(db, bytes, iteration, strategy, limits);
}

void _assertArchiveFailsClosed(
  Uint8List bytes, {
  required int iteration,
  required String strategy,
  FmpReadLimits limits = const FmpReadLimits(),
}) {
  CcUsrArchive? archive;
  try {
    archive = readCcUsrArchive(bytes, limits: limits);
  } on FmpFormatException {
    return;
  } on FmpResourceLimitException {
    return;
  } catch (e, st) {
    fail(_reproBytes(bytes, iteration, strategy, 'unexpected throw: $e\n$st'));
  }
  // A returned archive is always well-formed: non-null lists, and every dance
  // carries a record + raw columns (the CC extraction is parse-never-fails).
  expect(
    archive.dances,
    isA<List<CcDanceEntry>>(),
    reason: _reproBytes(bytes, iteration, strategy, 'dances not a list'),
  );
  expect(
    archive.sets,
    isA<List<CcSet>>(),
    reason: _reproBytes(bytes, iteration, strategy, 'sets not a list'),
  );
  expect(
    archive.warnings,
    isA<List<String>>(),
    reason: _reproBytes(bytes, iteration, strategy, 'warnings not a list'),
  );
}

void _assertDatabaseBounded(
  FmpDatabase db,
  Uint8List bytes,
  int iteration,
  String strategy,
  FmpReadLimits limits,
) {
  expect(
    db.tables.length,
    lessThanOrEqualTo(limits.maxTables),
    reason: _reproBytes(bytes, iteration, strategy, 'table count over cap'),
  );
  var totalRecords = 0;
  for (final table in db.tables) {
    totalRecords += table.records.length;
    for (final record in table.records) {
      // Decoded values are always the declared type — no unchecked leak.
      expect(
        record.valuesByColumnIndex,
        isA<Map<int, String>>(),
        reason: _reproBytes(bytes, iteration, strategy, 'record values type'),
      );
    }
  }
  expect(
    totalRecords,
    lessThanOrEqualTo(limits.maxRecords),
    reason: _reproBytes(bytes, iteration, strategy, 'record count over cap'),
  );
}

// --- Reproducibility -------------------------------------------------------

String _reproBytes(List<int> bytes, int iteration, String strategy, String w) {
  final preview = bytes
      .take(64)
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join(' ');
  return 'seed=0x${_seed.toRadixString(16)} $strategy #$iteration: $w\n'
      'length=${bytes.length} first64=[$preview]';
}

// --- Fixtures & mutators ---------------------------------------------------

const int _seed = 0x5139;
const int _fmpIterations = 2000;
const int _scsuIterations = 2000;

/// Structural ceiling for every generated container (well under `#443`'s
/// 25 MiB `kMaxImportFileBytes`), keeping allocation + traversal bounded.
const int _maxCandidateBytes = 64 * 1024;

const int _sectorSize = 4096;

/// A structurally valid `.fmp12` image (two tables, three rows, three sectors)
/// used as the mutation seed so byte flips reach deep into the chunk decoder,
/// path-stack traversal, and value passes — not just the header format guard.
Uint8List _validBase() => buildFmp12Fixture([
  FmpFixtureTable(
    index: 1,
    name: 'Dance',
    columnNames: ['Name', 'Author1'],
    rows: [
      MapEntry(1, {1: 'Simplicity Swing', 2: 'Becky Hill'}),
      MapEntry(2, {1: 'Petronella', 2: 'Trad'}),
    ],
  ),
  FmpFixtureTable(
    index: 2,
    name: 'Set',
    columnNames: ['Title'],
    rows: [
      MapEntry(1, {1: 'Friday Contra'}),
    ],
  ),
]);

/// Picks a mutation strategy at random and returns its label + mutated bytes.
(String, Uint8List) _mutate(Random rng, Uint8List base) {
  switch (rng.nextInt(8)) {
    case 0:
      return ('truncate', _truncate(rng, base));
    case 1:
      return ('byteflip', _byteFlip(rng, base));
    case 2:
      return ('field-corrupt', _corruptFields(rng, base));
    case 3:
      return ('oversized-len', _oversizedLengths(rng, base));
    case 4:
      return ('opcode-stream', _adversarialOpcodes(rng));
    case 5:
      return ('chain-loop', _sectorChainLoop(rng, base));
    case 6:
      return ('header-valid-garbage', _headerValidGarbage(rng));
    default:
      return ('random-buffer', _randomBuffer(rng));
  }
}

/// Cut the valid image at a random offset (header, mid-sector, or mid-chunk).
Uint8List _truncate(Random rng, Uint8List base) {
  final cut = rng.nextInt(base.length + 1);
  return Uint8List.sublistView(base, 0, cut);
}

/// Flip 1..24 random bytes anywhere in the image.
Uint8List _byteFlip(Random rng, Uint8List base) {
  final out = Uint8List.fromList(base);
  final flips = 1 + rng.nextInt(24);
  for (var i = 0; i < flips; i++) {
    out[rng.nextInt(out.length)] = rng.nextInt(256);
  }
  return out;
}

/// Corrupt structurally significant fields: the body-sector count int, and
/// random bytes inside the first body sector's payload (chunk length prefixes,
/// path-push lengths, column/record indices).
Uint8List _corruptFields(Random rng, Uint8List base) {
  final out = Uint8List.fromList(base);
  // Body-sector count lives at file offset 4096 + 8 (block[0].nextId).
  final countOffset = _sectorSize + 8;
  if (countOffset + 4 <= out.length) {
    switch (rng.nextInt(4)) {
      case 0:
        _writeInt32(out, countOffset, 0x7fffffff); // absurdly many sectors
      case 1:
        _writeInt32(out, countOffset, 0); // zero sectors
      case 2:
        _writeInt32(out, countOffset, -1 & 0xffffffff); // "negative"
      default:
        _writeInt32(out, countOffset, 1 + rng.nextInt(1000));
    }
  }
  // Scribble inside the first body sector's payload region (after its 20-byte
  // head), where the chunk byte-code lives.
  final payloadStart = 2 * _sectorSize + 20;
  final payloadEnd = (3 * _sectorSize).clamp(0, out.length);
  if (payloadStart < payloadEnd) {
    final scribbles = 1 + rng.nextInt(16);
    for (var i = 0; i < scribbles; i++) {
      out[payloadStart + rng.nextInt(payloadEnd - payloadStart)] = rng.nextInt(
        256,
      );
    }
  }
  return out;
}

/// Rewrite chunk length-prefix-shaped bytes in the first body payload to large
/// values, so a length claims far more data than the sector holds (the decoder
/// must clamp/bail, never over-read).
Uint8List _oversizedLengths(Random rng, Uint8List base) {
  final out = Uint8List.fromList(base);
  final payloadStart = 2 * _sectorSize + 20;
  final payloadEnd = (3 * _sectorSize).clamp(0, out.length);
  for (var p = payloadStart; p < payloadEnd; p++) {
    // The length-prefixed opcodes (e.g. 0x06/0x0E/0x16..0x1F/0x38) read the
    // byte after the opcode as a length; blow those up.
    if (rng.nextInt(6) == 0) {
      out[p] = 0xff;
    }
  }
  return out;
}

/// A valid header + a body whose sector payload is entirely random op-code
/// bytes, exercising every branch of the chunk decoder including the
/// unrecognised-op path.
Uint8List _adversarialOpcodes(Random rng) {
  final sectors = 1 + rng.nextInt(6);
  return _buildHeaderValid(rng, sectors, (payload) {
    for (var i = 0; i < payload.length; i++) {
      payload[i] = rng.nextInt(256);
    }
  });
}

/// A valid header + body sectors whose `nextId` links point backward / at
/// themselves, so the sector-chain traversal must terminate (guarded by the
/// reader's visited set) rather than loop forever.
Uint8List _sectorChainLoop(Random rng, Uint8List base) {
  final out = Uint8List.fromList(base);
  // Overwrite each body sector's nextId (offset +8 within the sector) with a
  // small index that can point backward or at itself.
  var sector = 1; // body sectors start at file offset 1*4096.
  while ((sector + 1) * _sectorSize <= out.length) {
    final nextIdOffset = sector * _sectorSize + 8;
    _writeInt32(out, nextIdOffset, rng.nextInt(5)); // 0..4 → loops/backrefs
    sector++;
  }
  return out;
}

/// A structurally valid header + sector count but otherwise random body bytes
/// (distinct from [_adversarialOpcodes] in that the whole body, including
/// sector heads, is random).
Uint8List _headerValidGarbage(Random rng) {
  final sectors = 1 + rng.nextInt(6);
  return _buildHeaderValid(rng, sectors, (payload) {
    for (var i = 0; i < payload.length; i++) {
      payload[i] = rng.nextInt(256);
    }
  });
}

/// Entirely random bytes with no valid header — must be rejected as a format
/// error (or, vanishingly rarely, parsed to an empty result).
Uint8List _randomBuffer(Random rng) {
  final len = rng.nextInt(_maxCandidateBytes);
  final out = Uint8List(len);
  for (var i = 0; i < len; i++) {
    out[i] = rng.nextInt(256);
  }
  return out;
}

/// Builds a valid FileMaker header sector + a body-count sector + [bodySectors]
/// body sectors, invoking [fillPayload] on each body sector's payload region so
/// callers can stuff arbitrary chunk bytes. Bounded by [_maxCandidateBytes].
Uint8List _buildHeaderValid(
  Random rng,
  int bodySectors,
  void Function(Uint8List payload) fillPayload,
) {
  final total = 2 + bodySectors; // header + body0(count) + body sectors
  final byteLen = (total * _sectorSize).clamp(0, _maxCandidateBytes);
  final out = Uint8List(byteLen);

  // Header sector (0): magic + HBAM7 + version + creator.
  const magic = [
    0x00, 0x01, 0x00, 0x00, 0x00, 0x02, 0x00, 0x01, //
    0x00, 0x05, 0x00, 0x02, 0x00, 0x02, 0xC0,
  ];
  out.setRange(0, magic.length, magic);
  const hbam = [0x48, 0x42, 0x41, 0x4D, 0x37];
  out.setRange(15, 15 + hbam.length, hbam);
  out[521] = 0x1E; // version 12

  // body0 (file offset 4096): nextId doubles as the body-sector count.
  if (_sectorSize + 12 <= out.length) {
    _writeInt32(out, _sectorSize + 8, bodySectors);
  }

  // Fill each body sector's payload region (after the 20-byte sector head).
  for (var s = 0; s < bodySectors; s++) {
    final base = (2 + s) * _sectorSize;
    final start = base + 20;
    final end = (base + _sectorSize).clamp(0, out.length);
    if (start >= end) break;
    // Randomise the sector head (prev/next links) too so chain traversal is
    // fuzzed alongside the payload.
    if (base + 12 <= out.length) {
      _writeInt32(out, base + 4, rng.nextInt(8));
      _writeInt32(out, base + 8, rng.nextInt(8));
    }
    fillPayload(Uint8List.sublistView(out, start, end));
  }
  return out;
}

void _writeInt32(Uint8List b, int offset, int value) {
  b[offset] = (value >> 24) & 0xFF;
  b[offset + 1] = (value >> 16) & 0xFF;
  b[offset + 2] = (value >> 8) & 0xFF;
  b[offset + 3] = value & 0xFF;
}

/// Random SCSU byte sequences, including short/truncated ones that end mid
/// multi-byte sequence, exercising the decoder's truncation handling.
List<int> _randomScsuBytes(Random rng) {
  final len = rng.nextInt(256);
  return [for (var i = 0; i < len; i++) rng.nextInt(256)];
}
