import 'package:song_record/core/domain/identifiers.dart';

enum InputField { title, artist, note, tag, condition, playlist }

final class InputValidationResult {
  const InputValidationResult({
    required this.value,
    required this.actual,
    required this.min,
    required this.max,
  });

  final String value;
  final int actual;
  final int min;
  final int max;

  bool get isValid => actual >= min && actual <= max;
}

InputValidationResult validateInput(InputField field, String raw) {
  final limits = switch (field) {
    InputField.title || InputField.artist => (1, 200, true),
    InputField.note => (0, 2000, false),
    InputField.tag || InputField.condition => (1, 50, true),
    InputField.playlist => (1, 100, true),
  };
  var value = field == InputField.note
      ? raw.replaceAll('\r\n', '\n').replaceAll('\r', '\n')
      : raw;
  if (limits.$3) value = trimContractWhitespace(value);
  return InputValidationResult(
    value: value,
    actual: value.runes.length,
    min: limits.$1,
    max: limits.$2,
  );
}
