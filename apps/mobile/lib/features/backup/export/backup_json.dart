import 'dart:convert';

/// ZIP JSON is our own format, not Java's normalized API numeric wire.
/// Reject duplicate decoded keys before jsonDecode can discard an earlier value.
Object? decodeBackupJson(String source) {
  var index = 0;
  void invalid() => throw const FormatException('Invalid backup JSON');
  void whitespace() {
    while (index < source.length && ' \t\r\n'.contains(source[index])) {
      index++;
    }
  }

  String? string({bool key = false}) {
    final start = index;
    if (index >= source.length || source[index++] != '"') invalid();
    while (index < source.length) {
      final char = source[index++];
      if (char == r'\') {
        if (index >= source.length) invalid();
        index++;
      } else if (char == '"') {
        return key
            ? jsonDecode(source.substring(start, index)) as String
            : null;
      }
    }
    invalid();
    throw const FormatException('Invalid backup JSON');
  }

  void value(int depth) {
    if (depth > 64) invalid();
    whitespace();
    if (index >= source.length) invalid();
    final char = source[index];
    if (char == '"') {
      string();
      return;
    }
    if (char == '{') {
      index++;
      final names = <String>{};
      whitespace();
      if (index < source.length && source[index] == '}') {
        index++;
        return;
      }
      while (true) {
        whitespace();
        if (!names.add(string(key: true)!)) invalid();
        whitespace();
        if (index >= source.length || source[index++] != ':') invalid();
        value(depth + 1);
        whitespace();
        if (index >= source.length) invalid();
        final separator = source[index++];
        if (separator == '}') return;
        if (separator != ',') invalid();
      }
    }
    if (char == '[') {
      index++;
      whitespace();
      if (index < source.length && source[index] == ']') {
        index++;
        return;
      }
      while (true) {
        value(depth + 1);
        whitespace();
        if (index >= source.length) invalid();
        final separator = source[index++];
        if (separator == ']') return;
        if (separator != ',') invalid();
      }
    }
    final start = index;
    while (index < source.length && !' \t\r\n,]}'.contains(source[index])) {
      index++;
    }
    if (index == start) invalid();
  }

  try {
    value(0);
    whitespace();
    if (index != source.length) invalid();
    return jsonDecode(source);
  } on FormatException {
    throw const FormatException('Invalid backup JSON');
  }
}
