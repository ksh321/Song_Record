import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/app/song_record_app.dart';
import 'package:song_record/config/app_config.dart';

void main() {
  testWidgets('초기 경로에서 빈 앱이 실행된다', (tester) async {
    await tester.pumpWidget(
      SongRecordApp(
        config: AppConfig(
          environment: AppEnvironment.dev,
          apiBaseUrl: Uri.parse('http://10.0.2.2:8080'),
        ),
      ),
    );

    expect(find.text('노래 기록'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
