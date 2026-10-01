import 'dart:math';
import 'dart:typed_data';

final class SongId implements Comparable<SongId> {
  SongId(String value) : _uuid = UuidValue(value);
  SongId.fromBytes(Uint8List bytes) : _uuid = UuidValue.fromBytes(bytes);

  final UuidValue _uuid;
  String get value => _uuid.value;
  Uint8List get bytes => _uuid.bytes;

  @override
  int compareTo(SongId other) => _uuid.compareTo(other._uuid);

  @override
  bool operator ==(Object other) => other is SongId && value == other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

final class RecordingId implements Comparable<RecordingId> {
  RecordingId(String value) : _uuid = UuidValue(value);
  RecordingId.fromBytes(Uint8List bytes) : _uuid = UuidValue.fromBytes(bytes);

  final UuidValue _uuid;
  String get value => _uuid.value;
  Uint8List get bytes => _uuid.bytes;

  @override
  int compareTo(RecordingId other) => _uuid.compareTo(other._uuid);

  @override
  bool operator ==(Object other) =>
      other is RecordingId && value == other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

final class TjNumber {
  TjNumber(String raw) : value = _validate(raw);

  final String value;

  static String _validate(String raw) {
    final value = trimContractWhitespace(raw);
    if (value.isEmpty ||
        value.length > 20 ||
        !RegExp(r'^\d+$').hasMatch(value)) {
      throw const FormatException('TJ 번호는 1~20자리 숫자여야 합니다.');
    }
    return value;
  }

  @override
  bool operator ==(Object other) => other is TjNumber && value == other.value;

  @override
  int get hashCode => value.hashCode;

  @override
  String toString() => value;
}

final class UuidValue implements Comparable<UuidValue> {
  UuidValue(String raw) : value = _canonical(raw);

  UuidValue.fromBytes(Uint8List bytes) : value = _fromBytes(bytes);

  factory UuidValue.random() {
    final random = Random.secure();
    final bytes = Uint8List.fromList(
      List.generate(16, (_) => random.nextInt(256)),
    );
    bytes[6] = (bytes[6] & 0x0f) | 0x40;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    return UuidValue.fromBytes(bytes);
  }

  static final _pattern = RegExp(
    r'^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$',
  );

  final String value;

  static String _canonical(String raw) {
    if (!_pattern.hasMatch(raw)) {
      throw const FormatException('UUID 형식이 올바르지 않습니다.');
    }
    return raw.toLowerCase();
  }

  static String _fromBytes(Uint8List bytes) {
    if (bytes.length != 16) {
      throw ArgumentError.value(
        bytes.length,
        'bytes.length',
        'UUID는 16바이트여야 합니다.',
      );
    }
    final hex = bytes
        .map((byte) => byte.toRadixString(16).padLeft(2, '0'))
        .join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-'
        '${hex.substring(12, 16)}-${hex.substring(16, 20)}-'
        '${hex.substring(20)}';
  }

  Uint8List get bytes {
    final hex = value.replaceAll('-', '');
    return Uint8List.fromList([
      for (var index = 0; index < hex.length; index += 2)
        int.parse(hex.substring(index, index + 2), radix: 16),
    ]);
  }

  @override
  int compareTo(UuidValue other) {
    final left = bytes;
    final right = other.bytes;
    for (var index = 0; index < left.length; index += 1) {
      final compared = left[index].compareTo(right[index]);
      if (compared != 0) return compared;
    }
    return 0;
  }
}

String trimContractWhitespace(String value) {
  var start = 0;
  var end = value.length;
  while (start < end && _isContractWhitespace(value.codeUnitAt(start))) {
    start += 1;
  }
  while (end > start && _isContractWhitespace(value.codeUnitAt(end - 1))) {
    end -= 1;
  }
  return value.substring(start, end);
}

bool _isContractWhitespace(int codePoint) =>
    (codePoint >= 0x0009 && codePoint <= 0x000d) ||
    codePoint == 0x0020 ||
    codePoint == 0x0085 ||
    codePoint == 0x00a0 ||
    codePoint == 0x1680 ||
    (codePoint >= 0x2000 && codePoint <= 0x200a) ||
    codePoint == 0x2028 ||
    codePoint == 0x2029 ||
    codePoint == 0x202f ||
    codePoint == 0x205f ||
    codePoint == 0x3000;
