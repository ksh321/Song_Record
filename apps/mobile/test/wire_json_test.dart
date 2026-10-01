import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/core/sync/wire_json.dart';

void main() {
  test('exact integral decimal/exponent spellings keep 64-bit identity', () {
    for (final entry in {
      '5.4E+2': 540,
      '1e3': 1000,
      '0.0100e2': 1,
      '-1.20e1': -12,
      '-0.000e999999': 0,
      '9.223372036854775807e18': 9223372036854775807,
      '-9.223372036854775808e18': -9223372036854775808,
      '9007199254740993.0': 9007199254740993,
    }.entries) {
      final value = decodeWireJson(entry.key);
      expect(value, isA<int>(), reason: entry.key);
      expect(value, entry.value, reason: entry.key);
    }
  });
  test('fractions and out-of-range values never become rounded integers', () {
    for (final value in [
      '1.0000000000000001',
      '1e-999',
      '1.5',
      '9.223372036854775808e18',
      '-9.223372036854775809e18',
      '1e99999',
    ]) {
      expect(decodeWireJson(value), isNot(isA<int>()), reason: value);
    }
  });
  test('strings and nested canonical hash bytes are preserved verbatim', () {
    final value = decodeWireJson(
      r'{"text":"5.4E+2 \\\"", "canonical":"{\"n\":1e3}","items":[1e3,true,null]}',
    ) as Map;
    expect(value['canonical'], r'{"n":1e3}');
    expect(value['text'], startsWith('5.4E+2'));
    expect(value['items'], [1000, true, null]);
  });
  test('normalization does not repair malformed JSON', () {
    for (final source in ['1.0.0', '[01]', '{"n":1e}', '[1.0,]', '1 2']) {
      expect(() => decodeWireJson(source), throwsFormatException);
    }
  });
}
