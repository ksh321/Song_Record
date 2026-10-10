import 'dart:async';

import 'package:flutter/material.dart';
import 'package:song_record/core/theme/app_theme.dart';
import 'package:song_record/core/theme/app_tokens.dart';
import 'package:song_record/features/recorder/recorder_gateway.dart';

class RecorderPanel extends StatefulWidget {
  const RecorderPanel({
    required this.gateway,
    this.diagnostics = true,
    super.key,
  });

  final RecorderGateway gateway;

  /// The P02 diagnostic view is only for verification; AppShell uses the product view.
  final bool diagnostics;

  @override
  State<RecorderPanel> createState() => _RecorderPanelState();
}

class _RecorderPanelState extends State<RecorderPanel>
    with WidgetsBindingObserver {
  static const _statusPollInterval = Duration(seconds: 1);
  static const _startGracePeriod = Duration(seconds: 5);

  RecorderStatus _status = const RecorderStatus.idle();
  RecorderPermissions? _permissions;
  RecorderDeviceInfo? _deviceInfo;
  StreamSubscription<RecorderStatus>? _subscription;
  Timer? _statusPoller;
  DateTime? _startGraceDeadline;
  bool _statusRefreshInProgress = false;
  bool _commandPending = false;
  bool _statusLoaded = false;
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
    if (widget.diagnostics) unawaited(_refreshDeviceInfo());
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

  Future<void> _refreshDeviceInfo() async {
    try {
      final deviceInfo = await widget.gateway.getDeviceInfo();
      if (!mounted) return;
      setState(() => _deviceInfo = deviceInfo);
    } on Object catch (error) {
      _showError(error.toString());
    }
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
    final isStaleIdle =
        status.phase == RecorderPhase.idle &&
        deadline != null &&
        DateTime.now().isBefore(deadline);

    if (isStaleIdle) return;
    _startGraceDeadline = null;
    _applyStatus(status);
  }

  void _applyStatus(RecorderStatus status) {
    if (!mounted) return;
    setState(() {
      _status = status;
      _statusLoaded = true;
    });
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
    if (_commandPending || _status.isRecording) return;
    setState(() => _commandPending = true);
    _clearOperationError();

    try {
      final permissions = await widget.gateway.requestPermissions();
      if (!mounted) return;
      setState(() => _permissions = permissions);

      if (!permissions.microphoneGranted) {
        _showError('마이크 권한이 필요합니다. 아래 버튼으로 다시 요청하세요.');
        return;
      }

      _startGraceDeadline = DateTime.now().add(_startGracePeriod);
      _applyStatus(const RecorderStatus(phase: RecorderPhase.starting));
      // A permission dialog can outlive this screen or return in the background.
      if (WidgetsBinding.instance.lifecycleState != null &&
          WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
        _startGraceDeadline = null;
        await _refreshStatus();
        _showError('녹음 화면으로 돌아온 뒤 시작해 주세요.');
        return;
      }
      await widget.gateway.start();
      await Future<void>.delayed(const Duration(milliseconds: 250));
      await _refreshStatus(reportErrors: true);
    } on Object catch (error) {
      _startGraceDeadline = null;
      unawaited(_refreshStatus());
      _showError(error.toString());
    } finally {
      if (mounted) setState(() => _commandPending = false);
    }
  }

  Future<void> _openAppSettings() async {
    _clearOperationError();
    try {
      await widget.gateway.openAppSettings();
    } on Object catch (error) {
      _showError(error.toString());
    }
  }

  Future<void> _stop() async {
    if (_commandPending || _status.phase != RecorderPhase.recording) return;
    setState(() => _commandPending = true);
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
    } finally {
      if (mounted) setState(() => _commandPending = false);
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

  Widget _buildProduct(BuildContext context) {
    final recording = _status.phase == RecorderPhase.recording;
    final completed = _status.phase == RecorderPhase.completed;
    final busy =
        _commandPending ||
        _status.phase == RecorderPhase.starting ||
        _status.phase == RecorderPhase.stopping;
    // Display only the native service's monotonic-clock observation. Polling
    // refreshes it; Flutter never advances the elapsed value independently.
    final seconds = _status.elapsedMs.clamp(0, 360000) ~/ 1000;
    final time =
        '${(seconds ~/ 60).toString().padLeft(2, '0')}:${(seconds % 60).toString().padLeft(2, '0')}';
    final warning = switch (_status.limitWarning) {
      RecorderLimitWarning.thirtySeconds => '30초 뒤 녹음이 자동으로 완료돼요.',
      RecorderLimitWarning.tenSeconds => '10초 뒤 녹음이 자동으로 완료돼요.',
      RecorderLimitWarning.none => null,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Text('최대 녹음 시간 6분', textAlign: TextAlign.center),
        const SizedBox(height: AppSpacing.lg),
        Text(
          completed
              ? '녹음이 완료됐어요'
              : recording
              ? '녹음 중'
              : busy
              ? '녹음 준비·마무리 중'
              : '오늘의 목소리를 남겨요',
          style: Theme.of(context).textTheme.titleLarge,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: AppSpacing.md),
        Text(
          time,
          key: const ValueKey('recorder-service-time'),
          style: const TextStyle(fontSize: 42),
          textAlign: TextAlign.center,
        ),
        if (warning != null)
          Semantics(
            liveRegion: true,
            child: Text(warning, textAlign: TextAlign.center),
          ),
        if (recording)
          const Text('진행 알림에서도 녹음을 완료할 수 있어요.', textAlign: TextAlign.center),
        if (completed) ...[
          Text(
            _status.stopReason == 'time_limit'
                ? '6분에 도달해 자동으로 완료했어요.'
                : '완료 파일은 이 기기에 보관돼요.',
            textAlign: TextAlign.center,
          ),
          const Text('녹음 정보 입력 대기', textAlign: TextAlign.center),
          if (_status.recovered)
            const Text('앱을 닫기 전의 녹음을 찾았어요.', textAlign: TextAlign.center),
        ],
        if (!_statusLoaded)
          const Text('녹음 상태 확인 중', textAlign: TextAlign.center),
        if (_operationError != null || _status.phase == RecorderPhase.error)
          const Text(
            '녹음 상태를 확인하지 못했어요. 권한·기기 공간·로그인 상태를 확인하고 다시 시도해 주세요.',
            textAlign: TextAlign.center,
          ),
        if (_operationError != null)
          TextButton(
            onPressed: _commandPending
                ? null
                : () async {
                    _clearOperationError();
                    await _refreshStatus(reportErrors: true);
                  },
            child: const Text('녹음 상태 다시 확인'),
          ),
        if (_permissions?.microphoneGranted == false) ...[
          const Text('녹음하려면 마이크 권한이 필요해요.', textAlign: TextAlign.center),
          TextButton(
            onPressed: _commandPending
                ? null
                : _permissions!.microphoneCanAskAgain
                ? _start
                : _openAppSettings,
            child: Text(
              _permissions!.microphoneCanAskAgain
                  ? '마이크 권한 다시 요청'
                  : '앱 권한 설정 열기',
            ),
          ),
        ],
        if (_permissions?.notificationsGranted == false)
          const Text(
            '알림 권한이 꺼져 있어요. 녹음은 계속되며 진행 알림은 보이지 않을 수 있어요.',
            textAlign: TextAlign.center,
          ),
        const SizedBox(height: AppSpacing.lg),
        if (!completed)
          Center(
            child: TextButton(
              key: const ValueKey('recorder-control'),
              onPressed: !_statusLoaded || busy
                  ? null
                  : recording
                  ? _stop
                  : _start,
              style: TextButton.styleFrom(
                foregroundColor: AppColors.text,
                minimumSize: const Size(116, 116),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 82,
                    height: 82,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.muted, width: 3),
                    ),
                    alignment: Alignment.center,
                    child: Container(
                      key: ValueKey(
                        recording
                            ? 'recorder-stop-square'
                            : 'recorder-start-circle',
                      ),
                      width: recording ? 32 : 64,
                      height: recording ? 32 : 64,
                      decoration: BoxDecoration(
                        color: AppColors.recording,
                        borderRadius: BorderRadius.circular(recording ? 6 : 32),
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Text(recording ? '녹음 완료' : '녹음 시작'),
                ],
              ),
            ),
          ),
        if (completed)
          TextButton(onPressed: _playLatest, child: const Text('완료 녹음 듣기')),
      ],
    );
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
    if (!widget.diagnostics) return _buildProduct(context);
    final elapsed = Duration(milliseconds: _status.elapsedMs);
    final minutes = elapsed.inMinutes.toString().padLeft(2, '0');
    final seconds = (elapsed.inSeconds % 60).toString().padLeft(2, '0');
    final limitMessage = _limitMessage(_status);
    final classificationMessage = _classificationMessage(_status);

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
            if (_deviceInfo != null)
              Text(
                '검증 기기: ${_deviceInfo!.manufacturer} '
                '${_deviceInfo!.model} · Android '
                '${_deviceInfo!.androidVersion} (SDK ${_deviceInfo!.sdkInt})',
              ),
            const SizedBox(height: 12),
            Text('상태: ${_phaseLabel(_status.phase)}'),
            if (_status.localState != RecorderLocalState.none)
              Text('로컬 상태: ${_localStateLabel(_status.localState)}'),
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
            if (_status.phase == RecorderPhase.completed && _status.recovered)
              const Text('이전 실행에서 완료된 녹음 파일을 복구했습니다.'),
            if (classificationMessage != null) Text(classificationMessage),
            if (_status.recordingId != null)
              SelectableText('녹음 ID: ${_status.recordingId}'),
            if (_status.outputPath != null)
              SelectableText('파일: ${_status.outputPath}'),
            if (_status.sizeBytes != null)
              Text('파일 크기: ${_status.sizeBytes} bytes'),
            if (_status.durationMs != null)
              Text('확인된 길이: ${_formatDuration(_status.durationMs!)}'),
            if (_status.sha256 != null)
              SelectableText('SHA-256: ${_status.sha256}'),
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
            if (_permissions != null && !_permissions!.microphoneGranted) ...[
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _permissions!.microphoneCanAskAgain
                    ? _start
                    : _openAppSettings,
                icon: const Icon(Icons.mic_none),
                label: Text(
                  _permissions!.microphoneCanAskAgain
                      ? '마이크 권한 다시 요청'
                      : '마이크 권한 설정 열기',
                ),
              ),
            ],
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _status.isRecording ? null : _start,
                    style: AppTheme.recordingFilledButtonStyle,
                    icon: const Icon(Icons.mic),
                    label: const Text('녹음 시작'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _status.isRecording ? _stop : null,
                    style: AppTheme.recordingOutlinedButtonStyle,
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

  String _formatDuration(int milliseconds) {
    final duration = Duration(milliseconds: milliseconds);
    final minutes = duration.inMinutes.toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  String _phaseLabel(RecorderPhase phase) => switch (phase) {
    RecorderPhase.idle => '대기',
    RecorderPhase.starting => '시작 중',
    RecorderPhase.recording => '녹음 중',
    RecorderPhase.stopping => '종료 중',
    RecorderPhase.completed => '파일 생성 완료',
    RecorderPhase.error => '오류',
  };

  String _localStateLabel(RecorderLocalState state) => switch (state) {
    RecorderLocalState.none => '분류 전',
    RecorderLocalState.capturing => '녹음 중',
    RecorderLocalState.inputPending => '곡 정보 입력 대기',
    RecorderLocalState.saved => '로컬 저장 완료',
    RecorderLocalState.interrupted => '녹음 중단',
    RecorderLocalState.corrupt => '재생 불가',
  };

  String? _classificationMessage(RecorderStatus status) {
    if (status.localState == RecorderLocalState.inputPending) {
      return status.recovered
          ? '복구된 파일의 검증이 끝났습니다. 곡 정보 입력을 기다리고 있습니다.'
          : '녹음 파일 검증이 끝났습니다. 곡 정보 입력을 기다리고 있습니다.';
    }
    if (status.localState == RecorderLocalState.corrupt) {
      return '파일 검증에 실패해 재생할 수 없는 녹음으로 분류했습니다.';
    }
    if (status.localState != RecorderLocalState.interrupted) return null;
    return switch (status.interruptionReason) {
      'phone_or_communication' => '통화 또는 음성 통신 때문에 녹음이 시작되지 않았습니다.',
      'other_app' => '마이크 입력을 시작하지 못했습니다. 다른 앱의 사용 여부는 확인되지 않았습니다.',
      'permission_denied' => '앱의 마이크 권한을 확인해 주세요.',
      'recorder_start_failed' => '녹음 시작에 실패했습니다. 아래 오류 정보를 확인해 주세요.',
      'storage_low' => '저장 공간이 부족해 녹음을 시작하지 못했습니다.',
      'write_failed' => '녹음 파일을 저장하지 못했습니다.',
      'process_terminated' => '앱 작업이 중단되어 녹음을 완료하지 못했습니다.',
      _ => '녹음이 중단되어 파일을 완료하지 못했습니다.',
    };
  }

  String? _limitMessage(RecorderStatus status) {
    if (status.phase != RecorderPhase.recording ||
        status.limitWarning == RecorderLimitWarning.none) {
      return null;
    }

    final fallbackRemainingMs = 360000 - status.elapsedMs;
    final remainingMs =
        status.remainingMs ??
        (fallbackRemainingMs < 0 ? 0 : fallbackRemainingMs);
    final remainingSeconds = (remainingMs + 999) ~/ 1000;
    return '녹음 종료 임박: $remainingSeconds초 후 자동 종료됩니다.';
  }
}
