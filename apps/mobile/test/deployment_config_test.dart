import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/config/app_config.dart';

void main() {
  test('deployment cannot silently use an unset or insecure endpoint', () {
    for (final env in [AppEnvironment.staging, AppEnvironment.prod]) {
      for (final endpoint in [
        '',
        'http://api.example.com',
        'https://api.song-record.invalid',
        'https://user:secret@api.example.com',
        'https://api.example.com?token=secret',
        'https://api.example.com/path',
        'https://api.example.com#fragment',
      ]) {
        expect(
          () => AppConfig.forEnvironment(env, endpoint),
          throwsArgumentError,
        );
      }
    }
  });
  test(
    'validation and production data namespaces keep explicit HTTPS origins',
    () {
      final stage = AppConfig.forEnvironment(
        AppEnvironment.staging,
        'https://localhost:18443',
      );
      final prod = AppConfig.forEnvironment(
        AppEnvironment.prod,
        'https://api.example.com',
      );
      expect(stage.environment, AppEnvironment.staging);
      expect(prod.environment, AppEnvironment.prod);
      expect(stage.apiBaseUrl, isNot(prod.apiBaseUrl));
      expect(
        () =>
            AppConfig.forEnvironment(AppEnvironment.prod, 'https://localhost'),
        throwsArgumentError,
      );
      expect(
        AppConfig.forEnvironment(AppEnvironment.dev, '').apiBaseUrl.scheme,
        'http',
      );
    },
  );
}
