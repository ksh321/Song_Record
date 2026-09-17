import 'dart:convert';

class ApiError {
  const ApiError({
    required this.code,
    required this.message,
    required this.retryable,
    required this.requestId,
    required this.details,
  });

  final String code;
  final String message;
  final bool retryable;
  final String requestId;
  final Map<String, dynamic> details;

  factory ApiError.fromBody(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map<String, dynamic>) {
      throw const FormatException('API error body must be an object.');
    }

    final error = decoded['error'];
    if (error is! Map<String, dynamic> ||
        error['code'] is! String ||
        error['message'] is! String ||
        error['retryable'] is! bool ||
        error['request_id'] is! String) {
      throw const FormatException('API error contract is invalid.');
    }

    final detailsValue = error['details'];
    final details = detailsValue is Map
        ? Map<String, dynamic>.from(detailsValue)
        : <String, dynamic>{};

    return ApiError(
      code: error['code'] as String,
      message: error['message'] as String,
      retryable: error['retryable'] as bool,
      requestId: error['request_id'] as String,
      details: details,
    );
  }
}

class ApiRequestException implements Exception {
  const ApiRequestException(this.error);

  final ApiError error;

  @override
  String toString() =>
      '${error.message}\n오류 코드: ${error.code}\n요청 ID: ${error.requestId}';
}
