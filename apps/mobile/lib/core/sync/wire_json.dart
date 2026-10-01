import 'dart:convert';

final _number = RegExp(r'-?(?:0|[1-9][0-9]*)(?:\.[0-9]+)?(?:[eE][+-]?[0-9]+)?');
final _parts = RegExp(r'^(-?)([0-9]+)(?:\.([0-9]+))?(?:[eE]([+-]?[0-9]+))?$');
final _min = BigInt.parse('-9223372036854775808');
final _max = BigInt.parse('9223372036854775807');

/// Decode incoming JSON with exact integral numeric spelling normalized first.
/// Java canonical responses use e.g. 5.4E+2 for 540. Never round a double to
/// decide whether an integer was sent, or rewrite JSON inside strings (hashes).
/// Outgoing frozen requests and canonical snapshot byte strings are untouched.
Object? decodeWireJson(String source) {
  // Normalization must never repair malformed JSON (e.g. 1.0.0 -> 1.0).
  jsonDecode(source);
  final result = StringBuffer();
  var quoted = false, escaped = false;
  var position = 0;
  while (position < source.length) {
    final c = source[position];
    if (quoted) {
      result.write(c);
      if (escaped) {
        escaped = false;
      } else if (c == r'\') {
        escaped = true;
      } else if (c == '"') {
        quoted = false;
      }
      position++;
      continue;
    }
    if (c == '"') {
      quoted = true;
    } else if (c == '-' || c.codeUnitAt(0) >= 48 && c.codeUnitAt(0) <= 57) {
      final match = _number.matchAsPrefix(source, position);
      if (match != null) {
        result.write(_integerSpelling(match.group(0)!));
        position = match.end;
        continue;
      }
    }
    result.write(c);
    position++;
  }
  return jsonDecode(result.toString());
}

String _integerSpelling(String original) {
  if (!original.contains(RegExp(r'[.eE]'))) return original;
  final match = _parts.firstMatch(original)!;
  final fraction = match.group(3) ?? '';
  var digits = '${match.group(2)}$fraction'.replaceFirst(RegExp(r'^0+'), '');
  if (digits.isEmpty) return '0';
  final exponent = int.tryParse(match.group(4) ?? '0');
  if (exponent == null) return original;
  // Bounds avoid overflow and allocating zeros for attacker-controlled exponents.
  if (exponent > fraction.length + 19 || exponent < -digits.length) {
    return original;
  }
  final shift = exponent - fraction.length;
  if (shift < 0) {
    final removed = -shift;
    if (removed > digits.length ||
        digits.substring(digits.length - removed).contains(RegExp('[1-9]'))) {
      return original;
    }
    digits = digits.substring(0, digits.length - removed);
  } else {
    if (digits.length + shift > 19) return original;
    digits += '0' * shift;
  }
  if (digits.length > 19) return original;
  final integer = BigInt.parse('${match.group(1)}$digits');
  return integer >= _min && integer <= _max ? integer.toString() : original;
}
