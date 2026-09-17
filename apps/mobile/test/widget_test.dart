import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/app/song_record_app.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/network/health_client.dart';

void main() {
  final config = AppConfig(
    environment: AppEnvironment.dev,
    apiBaseUrl: Uri.parse('http://127.0.0.1:8080'),
  );

  testWidgets('서버 health 성공 응답을 표시한다', (tester) async {
    await tester.pumpWidget(
      SongRecordApp(
        config: config,
        healthLoader: () async => const HealthResponse(
          status: 'UP',
          rawBody: '{"status":"UP"}',
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('서버 연결 성공: UP'), findsOneWidget);
    expect(find.text('응답: {"status":"UP"}'), findsOneWidget);
    expect(find.textContaining('MySQL에 직접 접속하지 않고'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('서버 health 실패와 재시도 버튼을 표시한다', (tester) async {
    await tester.pumpWidget(
      SongRecordApp(
        config: config,
        healthLoader: () async {
          throw const HealthCheckException('테스트 연결 실패');
        },
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('서버 연결 실패'), findsOneWidget);
    expect(find.text('테스트 연결 실패'), findsOneWidget);
    expect(find.text('다시 확인'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
