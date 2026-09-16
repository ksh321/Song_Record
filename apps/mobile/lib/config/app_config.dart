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
      _ => throw ArgumentError.value(value, 'APP_ENV', 'Use dev, staging, or prod'),
    };
  }
}

class AppConfig {
  const AppConfig({
    required this.environment,
    required this.apiBaseUrl,
  });

  factory AppConfig.fromEnvironment() {
    final environment = AppEnvironment.fromDefine();
    const overrideUrl = String.fromEnvironment('API_BASE_URL');

    final defaultUrl = switch (environment) {
      AppEnvironment.dev => 'http://10.0.2.2:8080',
      AppEnvironment.staging => 'https://staging-api.song-record.invalid',
      AppEnvironment.prod => 'https://api.song-record.invalid',
    };

    return AppConfig(
      environment: environment,
      apiBaseUrl: Uri.parse(overrideUrl.isEmpty ? defaultUrl : overrideUrl),
    );
  }

  final AppEnvironment environment;
  final Uri apiBaseUrl;
}
