import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/network/api_error.dart';

void main() {
  test('공통 API 오류 응답을 파싱한다', () {
    final error = ApiError.fromBody(
      '{"error":{"code":"VALIDATION_FAILED","message":"요청 값이 올바르지 않습니다.",'
      '"retryable":false,"request_id":"request-123","details":{"field":"title"}}}',
    );

    expect(error.code, 'VALIDATION_FAILED');
    expect(error.message, '요청 값이 올바르지 않습니다.');
    expect(error.retryable, isFalse);
    expect(error.requestId, 'request-123');
    expect(error.details['field'], 'title');
    expect(
      ApiRequestException(error).toString(),
      contains('요청 ID: request-123'),
    );
  });

  test('계약에 없는 오류 본문을 거부한다', () {
    expect(
      () => ApiError.fromBody('{"message":"legacy"}'),
      throwsFormatException,
    );
  });
}
