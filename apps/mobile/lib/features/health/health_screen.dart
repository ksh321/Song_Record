import 'package:flutter/material.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/network/health_client.dart';

class HealthScreen extends StatefulWidget {
  const HealthScreen({
    required this.config,
    required this.healthLoader,
    super.key,
  });

  final AppConfig config;
  final HealthLoader healthLoader;

  @override
  State<HealthScreen> createState() => _HealthScreenState();
}

class _HealthScreenState extends State<HealthScreen> {
  HealthResponse? _response;
  String? _errorMessage;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _checkHealth();
  }

  Future<void> _checkHealth({bool showLoading = false}) async {
    if (showLoading) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    }

    try {
      final response = await widget.healthLoader();
      if (!mounted) {
        return;
      }

      setState(() {
        _response = response;
        _errorMessage = null;
        _isLoading = false;
      });
    } on Object catch (error) {
      if (!mounted) {
        return;
      }

      setState(() {
        _response = null;
        _errorMessage = error.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final response = _response;

    return Scaffold(
      appBar: AppBar(title: const Text('노래 기록')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                '서버 연결 확인',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 12),
              Text('환경: ${widget.config.environment.name}'),
              Text('API: ${widget.config.apiBaseUrl}'),
              const SizedBox(height: 24),
              if (_isLoading) ...[
                const Center(child: CircularProgressIndicator()),
                const SizedBox(height: 12),
                const Center(child: Text('Spring Boot health 확인 중...')),
              ] else if (response != null) ...[
                const Icon(
                  Icons.check_circle,
                  color: Colors.green,
                  size: 48,
                ),
                const SizedBox(height: 12),
                Text(
                  '서버 연결 성공: ${response.status}',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                SelectableText(
                  '응답: ${response.rawBody}',
                  textAlign: TextAlign.center,
                ),
              ] else ...[
                const Icon(
                  Icons.error_outline,
                  color: Colors.red,
                  size: 48,
                ),
                const SizedBox(height: 12),
                Text(
                  '서버 연결 실패',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  _errorMessage ?? '알 수 없는 오류',
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: () => _checkHealth(showLoading: true),
                  child: const Text('다시 확인'),
                ),
              ],
              const Spacer(),
              const Text(
                '앱은 MySQL에 직접 접속하지 않고 Spring Boot API만 호출합니다.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
