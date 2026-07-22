/// A pure-Dart reader for the FileMaker Pro 12 container format (`.fmp12`, and
/// the runtime-bound `.USR` variant Caller's Companion ships — structurally the
/// same fmp12 database).
///
/// The format is proprietary and officially undocumented; this reader is a
/// faithful port of the block/sector traversal, chunk byte-code decoder, path
/// stack, and table/column/record reconstruction described in the MIT-licensed
/// `fmptools` project (© 2020 Evan Miller) and its `HACKING` notes. Only the
/// fmp12/fp7 ("HBAM7", version ≥ 7) family is supported — the older fp3/fp5
/// layout is rejected up front, which Caller's Companion never uses.
///
/// **Validation:** the reader is checked against real FileMaker `.fmp12` files
/// (kept out of the repo for licensing) by asserting its table/column/record
/// output matches `fmptools`' own converters byte-for-byte. See the local
/// validation test.
///
/// **Parse-never-fails:** only a non-FileMaker/unsupported container throws
/// ([FmpFormatException]). Structural anomalies inside a valid file (a truncated
/// chunk, an unrecognised op-code, a bad sector chain) stop the offending block
/// and are recorded in [FmpDatabase.warnings]; whatever was recovered is
/// returned. This mirrors the import pipeline's degrade-don't-crash contract.
///
/// Pure `dart:typed_data` — no `package:flutter` — so it belongs in the core.
library;

import 'dart:typed_data';

import 'scsu.dart';

/// Thrown when [readFmp12] is handed bytes that are not a supported FileMaker
/// 12 (`HBAM7`) container at all. Content-level anomalies never throw (see the
/// library doc); they surface as [FmpDatabase.warnings].
class FmpFormatException implements Exception {
  const FmpFormatException(this.message);
  final String message;
  @override
  String toString() => 'FmpFormatException: $message';
}

/// Thrown when a structurally-valid FileMaker container exceeds a
/// [FmpReadLimits] bound (too many sectors, tables, or records).
///
/// **OWASP A04 Insecure Design / A05 Security Misconfiguration — uncontrolled
/// resource consumption.** [readFmp12] reconstructs each table with its own full
/// sector traversal, so the reader's cost is O(tables × sectors); a hostile
/// small-but-pathological `.USR` (e.g. thousands of fabricated table-name
/// entries) could otherwise force quadratic work even under a byte-size cap.
/// Bounding tables/sectors/records **fails closed** and converts the reader's
/// cost to linear in file size. Distinct from [FmpFormatException] (a
/// not-a-FileMaker-file error) so callers can surface a friendly "too large"
/// message; the [message] is safe to show to the user.
class FmpResourceLimitException implements Exception {
  const FmpResourceLimitException(this.message);
  final String message;
  @override
  String toString() => 'FmpResourceLimitException: $message';
}

/// Maximum number of body sectors ([FmpDatabase]) [readFmp12] will read.
///
/// ~32 MiB of 4 KiB sectors — a defense-in-depth ceiling **inside the core
/// reader itself** (independent of any app-layer byte cap), bounding the length
/// of every per-table traversal. The real ~20 MB Caller's Companion sample is
/// ~5000 sectors, well under this.
const int kMaxFmpSectors = 8192;

/// Maximum number of distinct tables [readFmp12] will reconstruct.
///
/// The reader does one full sector traversal *per table*, so this is the bound
/// that caps the O(tables × sectors) amplification. Real Caller's Companion
/// `.USR` files carry ~22 tables (the CC schema tables plus FileMaker's internal
/// ones); 256 is far above any legitimate file while refusing a file stuffed
/// with fabricated table-name entries.
const int kMaxFmpTables = 256;

/// Maximum number of records (rows), summed across all tables, [readFmp12] will
/// reconstruct. Bounds per-record allocation/decoding work. The real CC sample
/// holds a few hundred rows; 200k is far above any legitimate file.
const int kMaxFmpRecords = 200000;

/// Structural bounds enforced by [readFmp12], failing closed with a
/// [FmpResourceLimitException] once exceeded. Defaults mirror the module
/// constants; tests inject tiny values to exercise the guards hermetically
/// (mirroring `ArchiveIntakeService`'s injectable `maxBytes`).
class FmpReadLimits {
  const FmpReadLimits({
    this.maxSectors = kMaxFmpSectors,
    this.maxTables = kMaxFmpTables,
    this.maxRecords = kMaxFmpRecords,
  });

  final int maxSectors;
  final int maxTables;
  final int maxRecords;
}

/// A column definition recovered from a table's schema.
class FmpColumn {
  FmpColumn(this.index, this.name);
  final int index;
  final String name;
}

/// One record (row) of a table, its field values keyed by column index.
class FmpRecord {
  FmpRecord(this.id, this.valuesByColumnIndex);

  /// The FileMaker internal record id (stable within the file).
  final int id;

  /// Field values by 1-based column index. Absent columns are unset (not "").
  final Map<int, String> valuesByColumnIndex;
}

/// A table: its schema ([columns]) and reconstructed [records].
class FmpTable {
  FmpTable(this.index, this.name, this.columns, this.records);

  final int index;
  final String name;
  final List<FmpColumn> columns;
  final List<FmpRecord> records;

  late final Map<String, int> _indexByName = {
    for (final c in columns) c.name: c.index,
  };

  /// The 1-based index of the column named [name] (case-sensitive), or null.
  int? columnIndexOf(String name) => _indexByName[name];
}

/// The parsed contents of an fmp12 file.
class FmpDatabase {
  FmpDatabase({
    required this.versionNum,
    required this.creator,
    required this.tables,
    required this.warnings,
  });

  final int versionNum;

  /// The creating application string (e.g. "Pro 12.0"), best-effort.
  final String creator;
  final List<FmpTable> tables;

  /// Non-fatal anomalies encountered while parsing (parse-never-fails).
  final List<String> warnings;

  /// The table named [name] (case-sensitive), or null.
  FmpTable? tableNamed(String name) {
    for (final t in tables) {
      if (t.name == name) return t;
    }
    return null;
  }
}

// The 15-byte magic number common to all FileMaker files.
const List<int> _magic = <int>[
  0x00, 0x01, 0x00, 0x00, 0x00, 0x02, 0x00, 0x01, //
  0x00, 0x05, 0x00, 0x02, 0x00, 0x02, 0xC0,
];

const int _sectorSize = 4096;
const int _sectorHeadLen = 20;
const int _xorMask = 0x5A;

// Chunk kinds (subset of fmptools' fmp_chunk_type_t we act on).
const int _chunkPathPush = 0;
const int _chunkPathPop = 1;
const int _chunkDataSimple = 2;
const int _chunkFieldRefSimple = 3;
const int _chunkFieldRefLong = 4;
const int _chunkDataSegment = 5;

class _Chunk {
  int type = _chunkDataSimple;
  Uint8List? data;
  int refSimple = 0;
  int segmentIndex = 0;
}

class _Block {
  _Block(this.prevId, this.nextId, this.payload);
  final int prevId;
  final int nextId;
  final Uint8List payload;
  List<_Chunk>? chunks;
}

/// Reads a FileMaker 12 (`.fmp12`/`.USR`) container from [bytes].
///
/// Throws [FmpFormatException] when [bytes] is not a supported HBAM7 container,
/// and [FmpResourceLimitException] when the container exceeds a [limits] bound
/// (too many sectors, tables, or records — a fail-closed DoS guard). Everything
/// else degrades to partial results + warnings.
FmpDatabase readFmp12(
  Uint8List bytes, {
  FmpReadLimits limits = const FmpReadLimits(),
}) => _FmpReader(bytes, limits).read();

class _FmpReader {
  _FmpReader(this._bytes, this._limits);

  final Uint8List _bytes;
  final FmpReadLimits _limits;
  final List<String> _warnings = [];

  late final List<_Block> _blocks; // body sectors, 0-based
  int _versionNum = 12;
  String _creator = '';

  // Path stack, faithful to the reference: a pop only decrements [_level]
  // (leaving stale entries in place), a push writes at [_level] then increments.
  final List<Uint8List?> _path = <Uint8List?>[];
  int _level = 0;

  FmpDatabase read() {
    _readHeader();
    _readSectors();

    // Fail closed on an over-large sector chain before doing any per-table
    // traversal work (defense in depth; the app also caps raw file bytes).
    if (_blocks.length > _limits.maxSectors) {
      throw FmpResourceLimitException(
        'The file has too many sectors to import safely '
        '(${_blocks.length} > ${_limits.maxSectors}).',
      );
    }

    final tables = <FmpTable>[];
    final tableNames = _listTables(); // index -> name
    // The reader traverses every sector once per table, so an unbounded table
    // count makes the whole read O(tables × sectors). Reject before the loop.
    if (tableNames.length > _limits.maxTables) {
      throw FmpResourceLimitException(
        'The file has too many tables to import safely '
        '(${tableNames.length} > ${_limits.maxTables}).',
      );
    }
    var totalRecords = 0;
    for (final entry in tableNames.entries) {
      final columns = _listColumns(entry.key);
      final records = _readValues(entry.key, columns);
      totalRecords += records.length;
      if (totalRecords > _limits.maxRecords) {
        throw FmpResourceLimitException(
          'The file has too many records to import safely '
          '(> ${_limits.maxRecords}).',
        );
      }
      tables.add(FmpTable(entry.key, entry.value, columns, records));
    }
    tables.sort((a, b) => a.index.compareTo(b.index));

    return FmpDatabase(
      versionNum: _versionNum,
      creator: _creator,
      tables: tables,
      warnings: _warnings,
    );
  }

  void _readHeader() {
    if (_bytes.length < 1024) {
      throw const FmpFormatException('File too small to be a FileMaker file.');
    }
    for (var i = 0; i < _magic.length; i++) {
      if (_bytes[i] != _magic[i]) {
        throw const FmpFormatException('Bad FileMaker magic number.');
      }
    }
    // "HBAM7" at offset 15 marks the fp7/fmp12 family; anything else is the
    // unsupported fp3/fp5 layout.
    const hbam = <int>[0x48, 0x42, 0x41, 0x4D, 0x37];
    for (var i = 0; i < hbam.length; i++) {
      if (_bytes[15 + i] != hbam[i]) {
        throw const FmpFormatException(
          'Unsupported FileMaker format (only fmp12/.USR is supported).',
        );
      }
    }
    _versionNum = _bytes[521] == 0x1E ? 12 : 7;
    _creator = _readPascalString(541);
  }

  String _readPascalString(int offset) {
    if (offset >= _bytes.length) return '';
    final len = _bytes[offset];
    final end = (offset + 1 + len).clamp(0, _bytes.length);
    return String.fromCharCodes(_bytes.sublist(offset + 1, end));
  }

  void _readSectors() {
    // Body sectors start after the 4096-byte header sector; sector N (0-based)
    // lives at offset (N+1)*4096. blocks[0].nextId reports the body count.
    final firstOffset = _sectorSize;
    if (firstOffset + _sectorSize > _bytes.length) {
      _warnings.add('File has no body sectors.');
      _blocks = const [];
      return;
    }
    final first = _blockAt(firstOffset);
    final numBlocks = first.nextId;
    if (numBlocks <= 0) {
      _warnings.add('Sector count is zero or negative; nothing to read.');
      _blocks = [first];
      return;
    }
    final blocks = <_Block>[first];
    for (var index = 1; index < numBlocks; index++) {
      final offset = (index + 1) * _sectorSize;
      if (offset + _sectorSize > _bytes.length) {
        _warnings.add(
          'Sector chain claims $numBlocks sectors but the file ends early '
          'at sector $index; reading the ${blocks.length} available.',
        );
        break;
      }
      blocks.add(_blockAt(offset));
    }
    _blocks = blocks;
  }

  _Block _blockAt(int offset) {
    final prevId = _int32(offset + 4);
    final nextId = _int32(offset + 8);
    final payload = Uint8List.sublistView(
      _bytes,
      offset + _sectorHeadLen,
      offset + _sectorSize,
    );
    return _Block(prevId, nextId, payload);
  }

  int _int32(int offset) =>
      (_bytes[offset] << 24) |
      (_bytes[offset + 1] << 16) |
      (_bytes[offset + 2] << 8) |
      _bytes[offset + 3];

  // --- Chunk decoding (port of process_block_v7) ---

  List<_Chunk> _chunksOf(_Block block) {
    final cached = block.chunks;
    if (cached != null) return cached;
    final chunks = _decodeChunks(block.payload);
    block.chunks = chunks;
    return chunks;
  }

  List<_Chunk> _decodeChunks(Uint8List payload) {
    final chunks = <_Chunk>[];
    final end = payload.length;
    var p = 0;

    Uint8List slice(int start, int len) {
      final stop = start + len;
      if (start < 0 || stop > end) return Uint8List(0);
      return Uint8List.sublistView(payload, start, stop);
    }

    while (p < end) {
      final c = payload[p];
      final chunk = _Chunk();

      if (c == 0x00) {
        chunk.type = _chunkDataSimple;
        p++;
        if (p >= end || payload[p] == 0x00) break;
        chunk.data = slice(p, 1);
        p += 1;
      } else if (c <= 0x05) {
        chunk.type = _chunkFieldRefSimple;
        p++;
        if (p >= end) break;
        chunk.refSimple = payload[p++];
        final len = (c == 0x01 ? 1 : 0) + 2 * (c - 0x01);
        chunk.data = slice(p, len);
        p += len;
      } else if (c == 0x06) {
        chunk.type = _chunkFieldRefSimple;
        p++;
        if (p + 2 > end) break;
        chunk.refSimple = payload[p++];
        final len = payload[p++];
        chunk.data = slice(p, len);
        p += len;
      } else if (c == 0x07) {
        chunk.type = _chunkDataSegment;
        p++;
        if (p + 3 > end) break;
        chunk.segmentIndex = payload[p++];
        final len = _int16(payload, p);
        p += 2;
        chunk.data = slice(p, len);
        p += len;
      } else if (c == 0x08) {
        chunk.type = _chunkDataSimple;
        p++;
        chunk.data = slice(p, 2);
        p += 2;
      } else if (c == 0x0E && p + 1 < end && payload[p + 1] == 0xFF) {
        chunk.type = _chunkDataSimple;
        p++;
        chunk.data = slice(p, 6);
        p += 6;
      } else if (c <= 0x0D) {
        chunk.type = _chunkFieldRefSimple;
        p++;
        if (p + 2 > end) break;
        chunk.refSimple = _pathInt2(payload, p);
        p += 2;
        final len = (c == 0x09 ? 1 : 0) + 2 * (c - 0x09);
        chunk.data = slice(p, len);
        p += len;
      } else if (c == 0x0E) {
        chunk.type = _chunkFieldRefSimple;
        p++;
        if (p + 3 > end) break;
        chunk.refSimple = _pathInt2(payload, p);
        p += 2;
        final len = payload[p++];
        chunk.data = slice(p, len);
        p += len;
      } else if (c == 0x0F) {
        chunk.type = _chunkDataSegment;
        p++;
        if (p + 4 > end) break;
        chunk.segmentIndex = _pathInt2(payload, p);
        p += 2;
        final len = _int16(payload, p);
        p += 2;
        chunk.data = slice(p, len);
        p += len;
      } else if (c == 0x10) {
        chunk.type = _chunkDataSimple;
        p++;
        chunk.data = slice(p, 3);
        p += 3;
      } else if (c >= 0x11 && c <= 0x15) {
        chunk.type = _chunkDataSimple;
        p++;
        final len = 3 + (c == 0x11 ? 1 : 0) + 2 * (c - 0x11);
        chunk.data = slice(p, len);
        p += len;
      } else if (c == 0x16) {
        chunk.type = _chunkFieldRefLong;
        p += 4; // 1 code byte + 3 ref bytes (ref not needed for our paths)
        if (p >= end) break;
        final len = payload[p++];
        chunk.data = slice(p, len);
        p += len;
      } else if (c == 0x17) {
        chunk.type = _chunkFieldRefLong;
        p += 4;
        if (p + 2 > end) break;
        final len = _int16(payload, p);
        p += 2;
        chunk.data = slice(p, len);
        p += len;
      } else if (c >= 0x19 && c <= 0x1D) {
        chunk.type = _chunkDataSimple;
        p++;
        if (p >= end) break;
        final len = payload[p++];
        chunk.data = slice(p, len);
        p += len + (c == 0x19 ? 1 : 0) + 2 * (c - 0x19);
      } else if (c == 0x1E) {
        chunk.type = _chunkFieldRefLong;
        p++;
        if (p >= end) break;
        final keyLen = payload[p++];
        p += keyLen;
        if (p >= end) break;
        final len = payload[p++];
        chunk.data = slice(p, len);
        p += len;
      } else if (c == 0x1F) {
        chunk.type = _chunkFieldRefLong;
        p++;
        if (p >= end) break;
        final keyLen = payload[p++];
        p += keyLen;
        if (p + 2 > end) break;
        final len = _int16(payload, p);
        p += 2;
        chunk.data = slice(p, len);
        p += len;
      } else if (c == 0x20 || c == 0xE0) {
        chunk.type = _chunkPathPush;
        p++;
        if (p >= end) break;
        int len;
        if (payload[p] == 0xFE) {
          p++;
          len = 8;
        } else {
          len = 1;
        }
        chunk.data = slice(p, len);
        p += len;
      } else if (c == 0x23) {
        chunk.type = _chunkDataSimple;
        p++;
        if (p >= end) break;
        final len = payload[p++];
        chunk.data = slice(p, len);
        p += len;
      } else if (c == 0x28) {
        chunk.type = _chunkPathPush;
        p++;
        chunk.data = slice(p, 2);
        p += 2;
      } else if (c == 0x30) {
        chunk.type = _chunkPathPush;
        p++;
        chunk.data = slice(p, 3);
        p += 3;
      } else if (c == 0x38) {
        chunk.type = _chunkPathPush;
        p++;
        if (p >= end) break;
        final len = payload[p++];
        chunk.data = slice(p, len);
        p += len;
      } else if (c == 0x3D || c == 0x40) {
        chunk.type = _chunkPathPop;
        p++;
      } else if (c == 0x80) {
        p++;
        continue; // no-op
      } else {
        _warnings.add(
          'Unrecognised chunk op-code 0x${c.toRadixString(16)} at offset $p; '
          'stopping this sector.',
        );
        break;
      }

      if (p > end) {
        _warnings.add('Chunk data ran past the sector end; truncated.');
        break;
      }
      chunks.add(chunk);
    }
    return chunks;
  }

  int _int16(Uint8List b, int o) {
    if (o + 2 > b.length) return 0;
    return (b[o] << 8) + b[o + 1];
  }

  int _pathInt2(Uint8List b, int o) {
    if (o + 2 > b.length) return 0;
    return 0x80 + ((b[o] & 0x7F) << 8) + b[o + 1];
  }

  // --- Path traversal (port of process_blocks / process_chunk_chain) ---

  /// Walks the sector linked list (starting at block id 2, 1-based) and invokes
  /// [handle] for each chunk with the current path stack. [handle] returns
  /// whether to keep going within the current sector; a `false` skips the rest
  /// of the sector (the reference's CHUNK_DONE), continuing to the next.
  void _traverse(bool Function(_Chunk chunk) handle) {
    if (_blocks.isEmpty) return;
    final visited = List<bool>.filled(_blocks.length, false);
    var nextBlock = 2; // 1-based
    while (nextBlock != 0 &&
        nextBlock - 1 < _blocks.length &&
        !visited[nextBlock - 1]) {
      final block = _blocks[nextBlock - 1];
      visited[nextBlock - 1] = true;
      _level = 0;
      for (final chunk in _chunksOf(block)) {
        if (chunk.type == _chunkPathPop) {
          if (_level > 0) _level--;
          continue;
        }
        if (chunk.type == _chunkPathPush) {
          if (_level >= _path.length) {
            _path.add(chunk.data);
          } else {
            _path[_level] = chunk.data;
          }
          _level++;
          continue;
        }
        if (!handle(chunk)) break;
      }
      nextBlock = block.nextId;
    }
  }

  int _pathValue(int i) {
    if (i < 0 || i >= _level) return 0;
    final p = _path[i];
    if (p == null) return 0;
    if (p.length == 1) return p[0];
    if (p.length == 2) return 0x80 + ((p[0] & 0x7F) << 8) + p[1];
    if (p.length == 3) return 0x80 + (p[1] << 8) + p[2];
    return 0;
  }

  // table_path_depth for v7 is (level - 1).
  bool _matchStart1(int depth, int val) {
    if (_level - 1 != depth) return false;
    return _pathValue(0) >= 128 && _pathValue(1) == val;
  }

  bool _matchStart2(int depth, int val1, int val2) {
    if (_level - 1 != depth) return false;
    return _pathValue(0) >= 128 &&
        _pathValue(1) == val1 &&
        _pathValue(2) == val2;
  }

  String _decodeValue(Uint8List? data) {
    if (data == null || data.isEmpty) return '';
    // convert(): XOR every byte with 0x5A, strip leading spaces, then SCSU.
    final x = Uint8List(data.length);
    for (var i = 0; i < data.length; i++) {
      x[i] = data[i] ^ _xorMask;
    }
    var start = 0;
    while (start < x.length && x[start] == 0x20) {
      start++;
    }
    return decodeScsu(start == 0 ? x : Uint8List.sublistView(x, start));
  }

  // --- Table / column / value passes ---

  Map<int, String> _listTables() {
    final names = <int, String>{};
    _traverse((chunk) {
      // Table metadata lives under path[0]==3; once we're past it, this block
      // has no more table names (CHUNK_DONE — stop scanning this sector).
      if (_pathValue(0) > 3) return false;
      if (chunk.type != _chunkFieldRefSimple) return true;
      // [3].[16].[5].[128+X] with ref 16 => table name at index X.
      if (_pathValue(0) == 3 &&
          _pathValue(1) == 16 &&
          _pathValue(2) == 5 &&
          _pathValue(3) >= 128 &&
          chunk.refSimple == 16) {
        final tableIndex = _pathValue(_level - 1) - 128;
        names[tableIndex] = _decodeValue(chunk.data);
      }
      return true;
    });
    return names;
  }

  List<FmpColumn> _listColumns(int tableIndex) {
    final byIndex = <int, String>{};
    final target = tableIndex + 128;
    _traverse((chunk) {
      final p0 = _pathValue(0);
      if (p0 > target) return false; // CHUNK_DONE
      if (p0 < target) return true; // CHUNK_NEXT
      if (chunk.type != _chunkFieldRefSimple) return true;
      // [128+t].[3].[5].[colIndex] with ref 16 => column name.
      if (_matchStart2(3, 3, 5) && chunk.refSimple == 16) {
        final colIndex = _pathValue(_level - 1);
        byIndex[colIndex] = _decodeValue(chunk.data);
      }
      return true;
    });
    final columns = [for (final e in byIndex.entries) FmpColumn(e.key, e.value)]
      ..sort((a, b) => a.index.compareTo(b.index));
    return columns;
  }

  List<FmpRecord> _readValues(int tableIndex, List<FmpColumn> columns) {
    final target = tableIndex + 128;
    final numColumns = columns.fold<int>(
      0,
      (m, c) => c.index > m ? c.index : m,
    );
    if (numColumns == 0) return const [];

    // Records are grouped exactly as the reference does: a monotonically
    // increasing [currentRow] counter that advances whenever the FileMaker
    // record id ([pathRow], = path[2]) changes OR the column index goes
    // backwards. This keeps genuinely-distinct rows separate even in schema
    // tables where several rows share a path id. Each grouped row also records
    // its underlying FileMaker record id ([recordIds]) as the stable id.
    final rowValues = <int, Map<int, String>>{};
    final recordIds = <int, int>{};
    final longBuf = <int>[];
    var currentRow = 0;
    var lastRow = 0;
    var lastColumn = 0;

    void store(int row, int column, String value) {
      rowValues.putIfAbsent(row, () => <int, String>{})[column] = value;
    }

    void flushLong() {
      if (longBuf.isEmpty) return;
      store(currentRow, lastColumn, _decodeValue(Uint8List.fromList(longBuf)));
      longBuf.clear();
    }

    int pathRow() => _pathValue(2);

    bool isLongString() {
      if (!_matchStart1(3, 5)) return false;
      final colIndex = _pathValue(3);
      if (lastColumn == 0 || colIndex < lastColumn) {
        return pathRow() > lastRow;
      }
      return pathRow() == lastRow;
    }

    bool isTableData() => _matchStart1(2, 5);

    _traverse((chunk) {
      final p0 = _pathValue(0);
      if (p0 > target) return false; // CHUNK_DONE
      if (p0 < target) return true; // CHUNK_NEXT
      if (chunk.type != _chunkFieldRefSimple &&
          chunk.type != _chunkDataSegment) {
        return true;
      }
      // Skip the column-definition chunks ([128+t].[3].[5].[...]).
      if (_matchStart2(3, 3, 5)) return true;

      var columnIndex = 0;
      var longString = false;
      if (isLongString()) {
        if (chunk.type == _chunkFieldRefSimple && chunk.refSimple == 0) {
          return true; // rich-text formatting run, not content
        }
        longString = true;
        columnIndex = _pathValue(_level - 1);
      } else if (isTableData()) {
        if (chunk.type == _chunkFieldRefSimple &&
            chunk.refSimple <= numColumns &&
            chunk.refSimple != 252) {
          columnIndex = chunk.refSimple;
        } else if (chunk.type == _chunkDataSegment &&
            chunk.segmentIndex <= numColumns) {
          columnIndex = chunk.segmentIndex;
        }
      }
      if (columnIndex == 0 || columnIndex > numColumns) return true;

      final row = pathRow();
      // Flush any pending long string to its (row, column) before advancing.
      if (columnIndex != lastColumn) flushLong();
      if (row != lastRow || columnIndex < lastColumn) currentRow++;

      if (longString) {
        final data = chunk.data;
        if (data != null) longBuf.addAll(data);
      } else {
        store(currentRow, columnIndex, _decodeValue(chunk.data));
      }
      recordIds[currentRow] = row;
      lastRow = row;
      lastColumn = columnIndex;
      return true;
    });
    flushLong();

    final rows = rowValues.keys.toList()..sort();
    return [for (final r in rows) FmpRecord(recordIds[r] ?? r, rowValues[r]!)];
  }
}
