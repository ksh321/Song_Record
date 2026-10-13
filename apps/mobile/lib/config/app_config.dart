enum AppEnvironment {
  dev,
  staging,
  prod;

  static AppEnvironment fromDefine() {
    const value = String.fromEnvironment('APP_ENV', defaultValue: 'dev');

    return switch (value) {
      'dev' => AppEnvironment.dev,
      'staging' => AppEnvironment.staging,
      'prod' => AppEnvironment.prod,
      _ => throw ArgumentError.value(
        value,
        'APP_ENV',
        'Use dev, staging, or prod',
      ),
    };
  }
}

class AppConfig {
  const AppConfig({required this.environment, required this.apiBaseUrl});

  factory AppConfig.fromEnvironment() {
    final environment = AppEnvironment.fromDefine();
    const overrideUrl = String.fromEnvironment('API_BASE_URL');

    return AppConfig.forEnvironment(environment, overrideUrl);
  }

  factory AppConfig.forEnvironment(
    AppEnvironment environment,
    String overrideUrl,
  ) {
    final defaultUrl = switch (environment) {
      AppEnvironment.dev => 'http://10.0.2.2:8080',
      AppEnvironment.staging => 'https://staging-api.song-record.invalid',
      AppEnvironment.prod => 'https://api.song-record.invalid',
    };

    final uri = Uri.parse(overrideUrl.isEmpty ? defaultUrl : overrideUrl);
    if (uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        !['', '/'].contains(uri.path) ||
        !['http', 'https'].contains(uri.scheme) ||
        (environment != AppEnvironment.dev &&
            (uri.scheme != 'https' ||
                uri.host.endsWith('.invalid') ||
                overrideUrl.isEmpty)) ||
        (environment == AppEnvironment.prod &&
            ['localhost', '127.0.0.1', '::1'].contains(uri.host))) {
      throw ArgumentError('앱 환경에 맞는 HTTPS 서버 주소를 명시해야 합니다.');
    }
    return AppConfig(environment: environment, apiBaseUrl: uri);
  }

  final AppEnvironment environment;
  final Uri apiBaseUrl;
}
