import 'package:compendium_core/compendium_core.dart';
import 'package:test/test.dart';

CustomFieldDef _def(CustomFieldType type, {List<String>? choices}) =>
    CustomFieldDef(
      id: 'f1',
      key: 'field',
      label: 'Field',
      type: type,
      choices: choices,
    );

void main() {
  group('RatingFilter validation', () {
    test('accepts a minimum rating in the 1..5 range', () {
      expect(RatingFilter(1).minRating, 1);
      expect(RatingFilter(5).minRating, 5);
    });

    test('rejects an out-of-range minimum rating', () {
      expect(() => RatingFilter(0), throwsArgumentError);
      expect(() => RatingFilter(6), throwsArgumentError);
    });
  });

  group('FigureLeaf param key validation', () {
    test('accepts well-formed identifier keys', () {
      expect(
        () => FigureLeaf('swing', params: const {'who': 'partners', '_x1': 1}),
        returnsNormally,
      );
    });

    test('rejects a key with illegal characters', () {
      expect(
        () => FigureLeaf('swing', params: const {'wh o': 1}),
        throwsArgumentError,
      );
    });

    test('rejects a key starting with a digit', () {
      expect(
        () => FigureLeaf('swing', params: const {'1who': 1}),
        throwsArgumentError,
      );
    });

    test('rejects a key with a JSON-path escape attempt', () {
      expect(
        () => FigureLeaf('swing', params: const {"x'] --": 1}),
        throwsArgumentError,
      );
    });

    test('snapshots params so post-construction mutation cannot inject', () {
      final mutable = <String, Object?>{'who': 'partners'};
      final leaf = FigureLeaf('swing', params: mutable);
      mutable["evil'] --"] = 1;
      // The leaf kept its own copy; the injected key is not present.
      expect(leaf.params.keys, ['who']);
      expect(() => leaf.params['x'] = 1, throwsUnsupportedError);
    });
  });

  group('CustomFieldFilter value snapshot', () {
    test(
      'snapshots list values so later mutation cannot change the filter',
      () {
        final def = CustomFieldDef(
          id: 'f',
          key: 'mood',
          label: 'Mood',
          type: CustomFieldType.choice,
          choices: ['a', 'b', 'c'],
        );
        final mutable = ['a', 'b'];
        final filter = CustomFieldFilter(def, CustomFieldOp.in_, mutable);
        mutable.add('c');
        expect(filter.value, ['a', 'b']);
        expect(() => (filter.value as List).add('x'), throwsUnsupportedError);
      },
    );
  });

  group('CustomFieldFilter op/type pairing', () {
    test('text accepts contains and equals', () {
      final def = _def(CustomFieldType.text);
      expect(
        () => CustomFieldFilter(def, CustomFieldOp.contains, 'a'),
        returnsNormally,
      );
      expect(
        () => CustomFieldFilter(def, CustomFieldOp.equals, 'a'),
        returnsNormally,
      );
    });

    test('text rejects a numeric operator', () {
      final def = _def(CustomFieldType.text);
      expect(
        () => CustomFieldFilter(def, CustomFieldOp.lt, 3),
        throwsArgumentError,
      );
    });

    test('number accepts eq/lt/gt/between', () {
      final def = _def(CustomFieldType.number);
      expect(
        () => CustomFieldFilter(def, CustomFieldOp.eq, 3),
        returnsNormally,
      );
      expect(
        () => CustomFieldFilter(def, CustomFieldOp.between, [1, 5]),
        returnsNormally,
      );
    });

    test('number rejects contains', () {
      final def = _def(CustomFieldType.number);
      expect(
        () => CustomFieldFilter(def, CustomFieldOp.contains, 'a'),
        throwsArgumentError,
      );
    });

    test('boolean accepts is with a bool', () {
      final def = _def(CustomFieldType.boolean);
      expect(
        () => CustomFieldFilter(def, CustomFieldOp.is_, true),
        returnsNormally,
      );
    });

    test('boolean rejects is with a non-bool value', () {
      final def = _def(CustomFieldType.boolean);
      expect(
        () => CustomFieldFilter(def, CustomFieldOp.is_, 'yes'),
        throwsArgumentError,
      );
    });

    test('choice accepts is and in', () {
      final def = _def(CustomFieldType.choice, choices: ['a', 'b']);
      expect(
        () => CustomFieldFilter(def, CustomFieldOp.is_, 'a'),
        returnsNormally,
      );
      expect(
        () => CustomFieldFilter(def, CustomFieldOp.in_, ['a', 'b']),
        returnsNormally,
      );
    });

    test('choice rejects between', () {
      final def = _def(CustomFieldType.choice, choices: ['a']);
      expect(
        () => CustomFieldFilter(def, CustomFieldOp.between, [1, 2]),
        throwsArgumentError,
      );
    });
  });

  group('CustomFieldFilter value-shape validation', () {
    test('between requires a two-element numeric list', () {
      final def = _def(CustomFieldType.number);
      expect(
        () => CustomFieldFilter(def, CustomFieldOp.between, [1]),
        throwsArgumentError,
      );
      expect(
        () => CustomFieldFilter(def, CustomFieldOp.between, ['a', 'b']),
        throwsArgumentError,
      );
    });

    test('in requires a non-empty string list', () {
      final def = _def(CustomFieldType.choice, choices: ['a']);
      expect(
        () => CustomFieldFilter(def, CustomFieldOp.in_, <String>[]),
        throwsArgumentError,
      );
      expect(
        () => CustomFieldFilter(def, CustomFieldOp.in_, [1, 2]),
        throwsArgumentError,
      );
    });

    test('eq requires a number', () {
      final def = _def(CustomFieldType.number);
      expect(
        () => CustomFieldFilter(def, CustomFieldOp.eq, 'x'),
        throwsArgumentError,
      );
    });

    test('contains requires a String', () {
      final def = _def(CustomFieldType.text);
      expect(
        () => CustomFieldFilter(def, CustomFieldOp.contains, 3),
        throwsArgumentError,
      );
    });
  });
}
