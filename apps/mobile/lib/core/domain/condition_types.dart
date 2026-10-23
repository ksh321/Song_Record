import 'identifiers.dart';

const defaultConditionNames = <String, String>{
  'VERY_GOOD': '매우 좋음',
  'GOOD': '좋음',
  'NORMAL': '보통',
  'BAD': '안 좋음',
};

bool validConditionCode(Object? value) {
  if (value is! String) return false;
  if (defaultConditionNames.containsKey(value)) return true;
  try {
    return UuidValue(value).value == value;
  } catch (_) {
    return false;
  }
}
