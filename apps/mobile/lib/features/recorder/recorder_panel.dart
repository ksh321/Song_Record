import 'dart:async';

import 'package:flutter/material.dart';
import 'package:song_record/features/recorder/recorder_gateway.dart';

class RecorderPanel extends StatefulWidget {
  const RecorderPanel({required this.gateway, super.key});

  final RecorderGateway gateway;

  @override
  State<RecorderPanel> createState() => _RecorderPanelState();
}

class _RecorderPanelState extends State<RecorderPanel>
    with WidgetsBindingObserver {
  static const _statusPollInterval = Duration(seconds: 1);
  static const _startGracePeriod = Duration(seconds: 5);

  RecorderStatus _status = const RecorderStatus.idle();
  RecorderPermissions? _permissions;
  StreamSubscription<RecorderStatus>? _subscription;
  Timer? _statusPoller;
  DateTime? _startGraceDeadline;
  bool _statusRefreshInProgress = false;
  String? _operationError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _subscription = widget.gateway.watchStatus().listen(
      _handleStatus,
      onError: (Object error) => _showError(error.toString()),
    );
    _startStatusPolling();
    unawaited(_refreshStatus(reportErrors: true));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _startStatusPolling();
      unawaited(_refreshStatus());
      return;
    }

    _statusPoller?.cancel();
    _statusPoller = null;
  }

  void _startStatusPolling() {
    _statusPoller?.cancel();
    _statusPoller = Timer.periodic(_statusPollInterval, (_) {
      unawaited(_refreshStatus());
    });
  }

  Future<void> _refreshStatus({bool reportErrors = false}) async {
    if (_statusRefreshInProgress) return;
    _statusRefreshInProgress = true;

    try {
      _handleStatus(await widget.gateway.getCurrentStatus());
    } on Object catch (error) {
      if (reportErrors) {
        _showError(error.toString());
      }
    } finally {
      _statusRefreshInProgress = false;
    }
  }

  void _handleStatus(RecorderStatus status) {
    final deadline = _startGraceDeadline;
    final isStaleIdle = status.phase == RecorderPhase.idle &&
        deadline != null &&
        DateTime.now().isBefore(deadline);

    if (isStaleIdle) return;
    _startGraceDeadline = null;
    _applyStatus(status);
  }

  void _applyStatus(RecorderStatus status) {
    if (!mounted) return;
    setState(() => _status = status);
  }

  void _clearOperationError() {
    if (!mounted || _operationError == null) return;
    setState(() => _operationError = null);
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() => _operationError = message);
  }

  Future<void> _start() async {
    _clearOperationError();

    try {
      final permissions = await widget.gateway.requestPermissions();
      if (!mounted) return;
      setState(() => _permissions = permissions);

      if (!permissions.microphoneGranted) {
        _showError('마이크 권한이 필요합니다. 권한을 허용한 뒤 다시 시도하세요.');
        return;
      }

      _startGraceDeadline = DateTime.now().add(_startGracePeriod);
      _applyStatus(const RecorderStatus(phase: RecorderPhase.starting));
      await widget.gateway.start();
      await Future<void>.delayed(const Duration(milliseconds: 250));
      await _refreshStatus(reportErrors: true);
    } on Object catch (error) {
      _startGraceDeadline = null;
      unawaited(_refreshStatus());
      _showError(error.toString());
    }
  }

  Future<void> _stop() async {
    _clearOperationError();
    _startGraceDeadline = null;
    _applyStatus(
      RecorderStatus(
        phase: RecorderPhase.stopping,
        recordingId: _status.recordingId,
        outputPath: _status.outputPath,
        elapsedMs: _status.elapsedMs,
      ),
    );

    try {
      await widget.gateway.stop();
      await Future<void>.delayed(const Duration(milliseconds: 250));
      await _refreshStatus(reportErrors: true);
    } on Object catch (error) {
      unawaited(_refreshStatus());
      _showError(error.toString());
    }
  }

  Future<void> _playLatest() async {
    _clearOperationError();

    try {
      await widget.gateway.playLatest();
    } on Object catch (error) {
      _showError(error.toString());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _statusPoller?.cancel();
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final elapsed = Duration(milliseconds: _status.elapsedMs);
    final minutes = elapsed.inMinutes.toString().padLeft(2, '0');
    final seconds = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
    final limitMessage = _limitMessage(_status);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('녹음 시제품', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 8),
            const Text('최대 녹음 시간 6분'),
            const Text('AAC-LC · 96kbps · 48kHz · 모노 · M4A'),
            const SizedBox(height: 12),
            Text('상태: ${_phaseLabel(_status.phase)}'),
            Text('경과 시간: $minutes:$seconds'),
            if (limitMessage != null)
              Text(
                limitMessage,
                style: TextStyle(
                  color: Theme.of(context).colorScheme.tertiary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            if (_status.phase == RecorderPhase.completed &&
                _status.stopReason == 'time_limit')
              const Text('6분 제한에 도달해 자동 종료되었습니다.'),
            if (_status.recordingId != null)
              SelectableText('녹음 ID: ${_status.recordingId}'),
            if (_status.outputPath != null)
              SelectableText('파일: ${_status.outputPath}'),
            if (_status.sizeBytes != null)
              Text('파일 크기: ${_status.sizeBytes} bytes'),
            if (_status.actualMime != null)
              Text('실제 코덱: ${_status.actualMime}'),
            if (_status.actualSampleRate != null)
              Text('실제 샘플링: ${_status.actualSampleRate}Hz'),
            if (_status.actualChannels != null)
              Text('실제 채널: ${_status.actualChannels}'),
            if (_status.actualAacProfile != null)
              Text('AAC 프로파일: ${_status.actualAacProfile} (2=LC)'),
            if (_permissions != null && !_permissions!.notificationsGranted)
              const Text('알림 권한이 꺼져 있어 진행 알림이 제한될 수 있습니다.'),
            if (_operationError != null) ...[
              const SizedBox(height: 8),
              Text(
                _operationError!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            if (_status.errorMessage != null) ...[
              const SizedBox(height: 8),
              Text(
                '${_status.errorCode ?? 'RECORDER_ERROR'}: '
                '${_status.errorMessage}',
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _status.isRecording ? null : _start,
                    icon: const Icon(Icons.mic),
                    label: const Text('녹음 시작'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _status.isRecording ? _stop : null,
                    icon: const Icon(Icons.stop),
                    label: const Text('녹음 종료'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: _status.phase == RecorderPhase.completed
                  ? _playLatest
                  : null,
              icon: const Icon(Icons.play_arrow),
              label: const Text('녹음 파일 재생 확인'),
            ),
          ],
        ),
      ),
    );
  }

  String _phaseLabel(RecorderPhase phase) => switch (phase) {
    RecorderPhase.idle => '대기',
    RecorderPhase.starting => '시작 중',
    RecorderPhase.recording => '녹음 중',
    RecorderPhase.stopping => '종료 중',
    RecorderPhase.completed => '파일 생성 완료',
    RecorderPhase.error => '오류',
  };

  String? _limitMessage(RecorderStatus status) {
    if (status.phase != RecorderPhase.recording ||
        status.limitWarning == RecorderLimitWarning.none) {
      return null;
    }

    final fallbackRemainingMs = 360000 - status.elapsedMs;
    final remainingMs = status.remainingMs ??
        (fallbackRemainingMs < 0 ? 0 : fallbackRemainingMs);
    final remainingSeconds = (remainingMs + 999) ~/ 1000;
    return '녹음 종료 임박: $remainingSeconds초 후 자동 종료됩니다.';
  }
}
