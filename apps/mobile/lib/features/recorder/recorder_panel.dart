import 'dart:async';

import 'package:flutter/material.dart';
import 'package:song_record/features/recorder/recorder_gateway.dart';

class RecorderPanel extends StatefulWidget {
  const RecorderPanel({required this.gateway, super.key});

  final RecorderGateway gateway;

  @override
  State<RecorderPanel> createState() => _RecorderPanelState();
}

class _RecorderPanelState extends State<RecorderPanel> {
  RecorderStatus _status = const RecorderStatus.idle();
  RecorderPermissions? _permissions;
  StreamSubscription<RecorderStatus>? _subscription;
  String? _operationError;

  @override
  void initState() {
    super.initState();
    _subscription = widget.gateway.watchStatus().listen(
      _applyStatus,
      onError: (Object error) => _showError(error.toString()),
    );
    _restoreStatus();
  }

  Future<void> _restoreStatus() async {
    try {
      _applyStatus(await widget.gateway.getCurrentStatus());
    } on Object catch (error) {
      _showError(error.toString());
    }
  }

  void _applyStatus(RecorderStatus status) {
    if (!mounted) return;
    setState(() {
      _status = status;
      _operationError = null;
    });
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() => _operationError = message);
  }

  Future<void> _start() async {
    try {
      final permissions = await widget.gateway.requestPermissions();
      if (!mounted) return;
      setState(() => _permissions = permissions);

      if (!permissions.microphoneGranted) {
        _showError('마이크 권한이 필요합니다. 권한을 허용한 뒤 다시 시도하세요.');
        return;
      }
      await widget.gateway.start();
    } on Object catch (error) {
      _showError(error.toString());
    }
  }

  Future<void> _stop() async {
    try {
      await widget.gateway.stop();
    } on Object catch (error) {
      _showError(error.toString());
    }
  }

  Future<void> _playLatest() async {
    try {
      await widget.gateway.playLatest();
    } on Object catch (error) {
      _showError(error.toString());
    }
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final elapsed = Duration(milliseconds: _status.elapsedMs);
    final minutes = elapsed.inMinutes.toString().padLeft(2, '0');
    final seconds = (elapsed.inSeconds % 60).toString().padLeft(2, '0');

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
}
