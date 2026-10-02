/// A tiny, from-scratch encoder for the FileMaker 12 (`.fmp12`/`.USR`) container
/// structures the core reader consumes, used *only* by app widget tests to build
/// a synthetic Caller's Companion `.USR` payload without shipping a real,
/// licensed FileMaker file.
///
/// This is a straight port of the core's test-only builder
/// (`packages/compendium_core/test/imports/support/fmp_fixture_builder.dart`).
/// The app test tree cannot import the core's `test/` sources, and this is pure
/// Dart with no dependencies, so it is copied here. If the container format the
/// reader expects ever changes, regenerate both from the core reader.
///
/// It is deliberately minimal — it emits just the header, the two body sectors,
/// and the exact chunk byte-code stream (path pushes/pops + field-reference
/// chunks) needed to describe tables with columns and rows. [buildFmp12Fixture]
/// fits everything in one body sector; [buildFmp12FixtureMultiSector] spreads
/// tables over many sectors, so a test can cut the bytes short the way an
/// incomplete copy of a real file is.
library;

import 'dart:typed_data';

const int _sectorSize = 4096;
const int _xorMask = 0x5A;

/// A single table to encode: [name], ordered [columnNames] (1-based indices),
/// and [rows] as `recordId -> {columnIndex: value}`.
class FmpFixtureTable {
  FmpFixtureTable({
    required this.index,
    required this.name,
    required this.columnNames,
    required this.rows,
    this.longColumns = const {},
  });

  final int index;
  final String name;
  final List<String> columnNames;
  final List<MapEntry<int, Map<int, String>>> rows;

  /// Columns whose cells [buildFmp12FixtureMultiSector] writes the way FileMaker
  /// stores long text (see the core builder). Only the multi-sector builder
  /// honours this.
  final Set<int> longColumns;
}

/// Builds a minimal but structurally real `.fmp12` byte image containing
/// [tables]. Every value byte is stored the way the reader expects to read it
/// back (XOR 0x5A over the SCSU/ASCII text).
Uint8List buildFmp12Fixture(List<FmpFixtureTable> tables) {
  final chunks = <int>[];

  void pushByte(int v) => chunks.addAll([0x20, v]);
  void pop() => chunks.add(0x40);
  void fieldRef(int ref, String text) {
    final encoded = [for (final u in text.codeUnits) u ^ _xorMask];
    chunks.addAll([0x06, ref, encoded.length, ...encoded]);
  }

  // Section 1: table names, under path [3, 16, 5, 128+index].
  for (final t in tables) {
    pushByte(3);
    pushByte(16);
    pushByte(5);
    pushByte(128 + t.index);
    fieldRef(16, t.name);
    pop();
    pop();
    pop();
    pop();
  }

  // Section 2: per-table column defs (path [128+i, 3, 5, col]) then row data
  // (path [128+i, 5, recordId]).
  for (final t in tables) {
    pushByte(128 + t.index);

    pushByte(3);
    pushByte(5);
    for (var col = 1; col <= t.columnNames.length; col++) {
      pushByte(col);
      fieldRef(16, t.columnNames[col - 1]);
      pop();
    }
    pop(); // 5
    pop(); // 3

    pushByte(5);
    for (final row in t.rows) {
      pushByte(row.key); // record id
      for (final cell in row.value.entries) {
        fieldRef(cell.key, cell.value);
      }
      pop(); // record id
    }
    pop(); // 5
    pop(); // 128+index
  }

  final body1 = Uint8List(_sectorSize);
  // Sector head is 20 bytes; nextId (offset +8) = 0 stops traversal.
  const bodyCapacity = _sectorSize - 20;
  if (chunks.length > bodyCapacity) {
    throw StateError(
      'FMP fixture chunk stream (${chunks.length} bytes) exceeds the single '
      'body sector capacity ($bodyCapacity bytes). Shrink the fixture (fewer '
      'tables/rows/shorter strings) or extend buildFmp12Fixture to emit '
      'additional body sectors.',
    );
  }
  body1.setRange(20, 20 + chunks.length, chunks);

  final header = Uint8List(_sectorSize);
  const magic = [
    0x00, 0x01, 0x00, 0x00, 0x00, 0x02, 0x00, 0x01, //
    0x00, 0x05, 0x00, 0x02, 0x00, 0x02, 0xC0,
  ];
  header.setRange(0, magic.length, magic);
  const hbam = [0x48, 0x42, 0x41, 0x4D, 0x37]; // "HBAM7"
  header.setRange(15, 15 + hbam.length, hbam);
  header[521] = 0x1E; // version 12
  // Creator pascal string at 541.
  const creator = 'Pro 12.0';
  header[541] = creator.length;
  header.setRange(542, 542 + creator.length, creator.codeUnits);

  final body0 = Uint8List(_sectorSize);
  // block[0].nextId (offset +8) doubles as the body-sector count (2 here).
  _writeInt32(body0, 8, 2);

  final out = BytesBuilder();
  out.add(header);
  out.add(body0);
  out.add(body1);
  return out.toBytes();
}

void _writeInt32(Uint8List b, int offset, int value) {
  b[offset] = (value >> 24) & 0xFF;
  b[offset + 1] = (value >> 16) & 0xFF;
  b[offset + 2] = (value >> 8) & 0xFF;
  b[offset + 3] = value & 0xFF;
}

/// Options for [buildFmp12FixtureMultiSector].
class FmpMultiSectorOptions {
  const FmpMultiSectorOptions({
    this.sectorBudget = 600,
    this.indexSectorsPerTable = 0,
    this.mediaSectors = 0,
    this.mixedSectors = false,
    this.badOpcodeSectors = 0,
  });

  /// Chunk bytes a sector may hold before the writer starts the next one (the
  /// real limit is 4076). Small values spread a table over many sectors and
  /// make rows span sector boundaries.
  final int sectorBudget;

  /// Index-like sectors per table: path `[128+t].[1].[col]`, which the reader's
  /// passes never consume (a real file's indexes live there).
  final int indexSectorsPerTable;

  /// Media-like sectors on a non-table path (`[31].[5]…`, as a real file's
  /// embedded images use).
  final int mediaSectors;

  /// Also emit sectors that switch top-level path *within* the sector: index or
  /// media chunks first, then a pop back to the root and a real table's
  /// records — and, for another table, records followed by index chunks. A
  /// classifier that trusts a sector's leading path gets these wrong.
  final bool mixedSectors;

  /// Trailing sectors whose first byte is an unrecognised op-code, so the
  /// decoder emits a warning and stops the sector.
  final int badOpcodeSectors;
}

/// Like [buildFmp12Fixture], but lays the tables out over many sectors the way
/// a real file does, optionally interleaved with sectors the reader must ignore
/// (see [FmpMultiSectorOptions]). Column indices must be below 128 and text
/// ASCII and free of leading spaces (the reader strips them).
Uint8List buildFmp12FixtureMultiSector(
  List<FmpFixtureTable> tables, {
  FmpMultiSectorOptions options = const FmpMultiSectorOptions(),
}) {
  final w = _SectorWriter(options.sectorBudget);

  List<int> junkSeg(int n) => [
    0x07,
    1,
    (n >> 8) & 0xFF,
    n & 0xFF,
    for (var i = 0; i < n; i++) (i * 37 + 11) & 0xFF,
  ];
  List<int> indexJunk(int tableIndex, int col) => [
    ..._push(128 + tableIndex),
    ..._push(1),
    ..._push(col),
    ...junkSeg(120),
    ..._pop,
    ..._pop,
    ..._pop,
  ];
  List<int> mediaJunk() => [
    ..._push(31),
    ..._push(5),
    ..._push(0x80 + 3),
    ...junkSeg(300),
    ..._pop,
    ..._pop,
    ..._pop,
  ];

  for (var i = 0; i < options.mediaSectors; i++) {
    w.startSector(mediaJunk());
  }

  // Catalog: table names under [3, 16, 5, 128+index].
  w.startSector([..._push(3), ..._push(16), ..._push(5)]);
  for (final t in tables) {
    w.add([..._push(128 + t.index), ..._field(16, t.name), ..._pop]);
  }

  var tableNo = 0;
  for (final t in tables) {
    for (var i = 0; i < options.indexSectorsPerTable; i++) {
      w.startSector(indexJunk(t.index, 1 + i));
    }

    // Column definitions: [128+t, 3, 5, col].
    final colPrefix = [..._push(128 + t.index), ..._push(3), ..._push(5)];
    w.startSector(colPrefix, prefix: colPrefix);
    for (var col = 1; col <= t.columnNames.length; col++) {
      w.add([..._push(col), ..._field(16, t.columnNames[col - 1]), ..._pop]);
    }

    // Records: [128+t, 5, recordId].
    final tablePrefix = [..._push(128 + t.index), ..._push(5)];
    final mixedKind = tableNo % 2; // 0: junk before records, 1: junk after
    final lead = options.mixedSectors && mixedKind == 0
        ? (tableNo % 4 == 0 ? indexJunk(t.index, 2) : mediaJunk())
        : const <int>[];
    w.startSector([...lead, ...tablePrefix], prefix: tablePrefix);
    for (final row in t.rows) {
      w.prefix = tablePrefix;
      w.add(_push(row.key));
      w.prefix = [...tablePrefix, ..._push(row.key)];
      final rowPrefix = [...tablePrefix, ..._push(row.key)];
      for (final cell in row.value.entries) {
        if (!t.longColumns.contains(cell.key)) {
          w.add(_field(cell.key, cell.value));
          continue;
        }
        // Long text: enter the column's own path level, stream the value in
        // small segments (so it spans sectors), then leave it again.
        w.add(_push(cell.key));
        w.prefix = [...rowPrefix, ..._push(cell.key)];
        final data = [for (final u in cell.value.codeUnits) u ^ _xorMask];
        for (var i = 0; i < data.length; i += 40) {
          final piece = data.sublist(
            i,
            i + 40 > data.length ? data.length : i + 40,
          );
          w.add([
            0x07,
            1,
            (piece.length >> 8) & 0xFF,
            piece.length & 0xFF,
            ...piece,
          ]);
        }
        w.add(_pop);
        w.prefix = rowPrefix;
      }
      w.add(_pop);
      w.prefix = tablePrefix;
    }
    if (options.mixedSectors && mixedKind == 1) {
      // Records, then back to the root and index chunks — same sector.
      w.add([..._pop, ..._pop, ...indexJunk(t.index, 3)]);
    }
    tableNo++;
  }

  for (var i = 0; i < options.badOpcodeSectors; i++) {
    w.startSector([0x87, 0x00, 0x00]);
  }
  w.flush();

  final header = Uint8List(_sectorSize);
  header.setRange(0, _magic.length, _magic);
  header.setRange(15, 20, const [0x48, 0x42, 0x41, 0x4D, 0x37]); // "HBAM7"
  header[521] = 0x1E; // version 12
  const creator = 'Pro 12.0';
  header[541] = creator.length;
  header.setRange(542, 542 + creator.length, creator.codeUnits);

  final count = w.sectors.length + 1; // + the root sector (block id 1)
  final root = Uint8List(_sectorSize);
  _writeInt32(root, 8, count);

  final out = BytesBuilder()
    ..add(header)
    ..add(root);
  for (var k = 0; k < w.sectors.length; k++) {
    final id = k + 2; // 1-based block id; the walk starts at 2
    final body = w.sectors[k];
    _writeInt32(body, 4, id - 1);
    _writeInt32(body, 8, id < count ? id + 1 : 0);
    out.add(body);
  }
  return out.toBytes();
}

const List<int> _magic = [
  0x00, 0x01, 0x00, 0x00, 0x00, 0x02, 0x00, 0x01, //
  0x00, 0x05, 0x00, 0x02, 0x00, 0x02, 0xC0,
];

const List<int> _pop = [0x40];

List<int> _push(int v) =>
    v < 0x80 ? [0x20, v] : [0x28, ((v - 0x80) >> 8) & 0x7F, (v - 0x80) & 0xFF];

List<int> _field(int col, String text) {
  assert(col < 0x80, 'fixture columns must be below 128');
  final data = [for (final u in text.codeUnits) u ^ _xorMask];
  if (data.length <= 0xFF) return [0x06, col, data.length, ...data];
  return [0x07, col, (data.length >> 8) & 0xFF, data.length & 0xFF, ...data];
}

/// Accumulates chunk bytes into 4 KiB sectors, re-opening the current path at
/// the top of each new sector (the reader resets its path stack per sector).
class _SectorWriter {
  _SectorWriter(this.budget);

  final int budget;
  final List<Uint8List> sectors = [];
  List<int> _cur = [];

  /// Bytes that re-establish the current path at the start of a continuation
  /// sector.
  List<int> prefix = const [];

  void startSector(List<int> initial, {List<int> prefix = const []}) {
    flush();
    this.prefix = prefix;
    _cur = [...initial];
  }

  void add(List<int> bytes) {
    if (_cur.length + bytes.length > budget && _cur.isNotEmpty) {
      flush();
      _cur = [...prefix];
    }
    _cur.addAll(bytes);
  }

  void flush() {
    if (_cur.isEmpty) return;
    final s = Uint8List(_sectorSize);
    assert(_cur.length <= _sectorSize - 20, 'sector overflow');
    s.setRange(20, 20 + _cur.length, _cur);
    sectors.add(s);
    _cur = [];
  }
}
