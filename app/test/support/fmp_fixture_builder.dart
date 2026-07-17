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
/// chunks) needed to describe tables with columns and rows.
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
  });

  final int index;
  final String name;
  final List<String> columnNames;
  final List<MapEntry<int, Map<int, String>>> rows;
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
