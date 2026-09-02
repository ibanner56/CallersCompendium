import 'dart:typed_data';

/// A deliberately separate oracle for the checked-in W1 corpus.
///
/// Number spellings are literal RFC/golden values, not derived from the
/// production formatter. This keeps a formatter mutation observable.
String referenceJcsEncode(Object? value) {
  switch (value) {
    case null:
      return 'null';
    case final bool boolean:
      return boolean ? 'true' : 'false';
    case final num number:
      return _referenceNumber(number);
    case final String string:
      return _referenceString(string);
    case final List<Object?> list:
      return '[${list.map(referenceJcsEncode).join(',')}]';
    case final Map<Object?, Object?> map:
      final keys = map.keys.cast<String>().toList()..sort(_compareUtf16);
      return '{${keys.map((key) => '${_referenceString(key)}:'
          '${referenceJcsEncode(map[key])}').join(',')}}';
    default:
      throw StateError('Unsupported oracle value ${value.runtimeType}');
  }
}

String _referenceNumber(num value) {
  final double number = value.toDouble();
  if (!number.isFinite) throw StateError('Non-finite oracle number');
  if (number == 0) return '0';

  final bits = _bits(number);
  const values = <int, String>{
    0x0000000000000001: '5e-324',
    0x8000000000000001: '-5e-324',
    0x7fefffffffffffff: '1.7976931348623157e+308',
    0xffefffffffffffff: '-1.7976931348623157e+308',
    0x4340000000000000: '9007199254740992',
    0xc340000000000000: '-9007199254740992',
    0x4430000000000000: '295147905179352830000',
    0x44b52d02c7e14af5: '9.999999999999997e+22',
    0x44b52d02c7e14af6: '1e+23',
    0x44b52d02c7e14af7: '1.0000000000000001e+23',
    0x444b1ae4d6e2ef4e: '999999999999999700000',
    0x444b1ae4d6e2ef4f: '999999999999999900000',
    0x444b1ae4d6e2ef50: '1e+21',
    0x3eb0c6f7a0b5ed8c: '9.999999999999997e-7',
    0x3eb0c6f7a0b5ed8d: '0.000001',
    0x41b3de4355555553: '333333333.3333332',
    0x41b3de4355555554: '333333333.33333325',
    0x41b3de4355555555: '333333333.3333333',
    0x41b3de4355555556: '333333333.3333334',
    0x41b3de4355555557: '333333333.33333343',
    0xbecbf647612f3696: '-0.0000033333333333333333',
    0x43143ff3c1cb0959: '1424953923781206.2',
    0x4010000000000000: '4',
    0x3ff4000000000000: '1.25',
  };
  final expected = values[bits];
  if (expected == null) {
    throw StateError('Number missing from the independent oracle: $number');
  }
  return expected;
}

int _bits(double value) {
  final bytes = ByteData(8)..setFloat64(0, value, Endian.big);
  return bytes.getUint64(0, Endian.big);
}

String _referenceString(String value) {
  final output = StringBuffer('"');
  for (var index = 0; index < value.length; index++) {
    switch (value.codeUnitAt(index)) {
      case 0x08:
        output.write(r'\b');
      case 0x09:
        output.write(r'\t');
      case 0x0a:
        output.write(r'\n');
      case 0x0c:
        output.write(r'\f');
      case 0x0d:
        output.write(r'\r');
      case 0x22:
        output.write(r'\"');
      case 0x5c:
        output.write(r'\\');
      default:
        final codeUnit = value.codeUnitAt(index);
        if (codeUnit < 0x20) {
          output
            ..write(r'\u')
            ..write(codeUnit.toRadixString(16).padLeft(4, '0'));
        } else {
          output.writeCharCode(codeUnit);
        }
    }
  }
  output.write('"');
  return output.toString();
}

int _compareUtf16(String first, String second) {
  final length = first.length < second.length ? first.length : second.length;
  for (var index = 0; index < length; index++) {
    final difference = first.codeUnitAt(index) - second.codeUnitAt(index);
    if (difference != 0) return difference;
  }
  return first.length - second.length;
}
