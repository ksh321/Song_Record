import 'dart:async';

import 'package:flutter/services.dart';

enum RecorderPhase { idle, starting, recording, stopping, completed, error }

enum RecorderLimitWarning { none, thirtySeconds, tenSeconds }

enum RecorderLocalState { none, capturing, inputPending, saved, interrupted, corrupt }

class RecorderPermissions {
  const RecorderPermissions({
    required this.microphoneGranted,
    required this.notificationsGranted,
  });

  factory RecorderPermissions.fromMap(Map<Object?, Object?> map) {
    return RecorderPermissions(
      microphoneGranted: map['microphoneGranted'] == true,
      notificationsGranted: map['notificationsGranted'] == true,
    );
  }

  final bool microphoneGranted;
  final bool notificationsGranted;
}

class RecorderStatus {
  const RecorderStatus({
    required this.phase,
    this.recordingId,
    this.outputPath,
    this.elapsedMs = 0,
    this.remainingMs,
    this.limitWarning = RecorderLimitWarning.none,
    this.stopReason,
    this.sizeBytes,
    this.durationMs,
    this.sha256,
    this.recovered = false,
    this.recoveryState,
    this.actualMime,
    this.actualSampleRate,
    this.actualChannels,
    this.actualAacProfile,
    this.errorCode,
    this.errorMessage,
    this.localState = RecorderLocalState.none,
    this.interruptionReason,
  });

  const RecorderStatus.idle() : this(phase: RecorderPhase.idle);

  factory RecorderStatus.fromMap(Map<Object?, Object?> map) {
    final phaseName = map['phase']?.toString() ?? 'idle';
    final phase = RecorderPhase.values.firstWhere(
      (candidate) => candidate.name == phaseName,
      orElse: () => RecorderPhase.error,
    );
    final warning = switch (map['limitWarning']?.toString()) {
      'thirty_seconds' => RecorderLimitWarning.thirtySeconds,
      'ten_seconds' => RecorderLimitWarning.tenSeconds,
      _ => RecorderLimitWarning.none,
    };
    final localState = switch (map['localState']?.toString()) {
      'CAPTURING' => RecorderLocalState.capturing,
      'INPUT_PENDING' => RecorderLocalState.inputPending,
      'SAVED' => RecorderLocalState.saved,
      'INTERRUPTED' => RecorderLocalState.interrupted,
      'CORRUPT' => RecorderLocalState.corrupt,
      _ => RecorderLocalState.none,
    };

    return RecorderStatus(
      phase: phase,
      recordingId: map['recordingId']?.toString(),
      outputPath: map['outputPath']?.toString(),
      elapsedMs: (map['elapsedMs'] as num?)?.toInt() ?? 0,
      remainingMs: (map['remainingMs'] as num?)?.toInt(),
      limitWarning: warning,
      stopReason: map['stopReason']?.toString(),
      sizeBytes: (map['sizeBytes'] as num?)?.toInt(),
      durationMs: (map['durationMs'] as num?)?.toInt(),
      sha256: map['sha256']?.toString(),
      recovered: map['recovered'] == true,
      recoveryState: map['recoveryState']?.toString(),
      actualMime: map['actualMime']?.toString(),
      actualSampleRate: (map['actualSampleRate'] as num?)?.toInt(),
      actualChannels: (map['actualChannels'] as num?)?.toInt(),
      actualAacProfile: (map['actualAacProfile'] as num?)?.toInt(),
      errorCode: map['errorCode']?.toString(),
      errorMessage: map['errorMessage']?.toString(),
      localState: localState,
      interruptionReason: map['interruptionReason']?.toString(),
    );
  }

  final RecorderPhase phase;
  final String? recordingId;
  final String? outputPath;
  final int elapsedMs;
  final int? remainingMs;
  final RecorderLimitWarning limitWarning;
  final String? stopReason;
  final int? sizeBytes;
  final int? durationMs;
  final String? sha256;
  final bool recovered;
  final String? recoveryState;
  final String? actualMime;
  final int? actualSampleRate;
  final int? actualChannels;
  final int? actualAacProfile;
  final String? errorCode;
  final String? errorMessage;
  final RecorderLocalState localState;
  final String? interruptionReason;

  bool get isRecording =>
      phase == RecorderPhase.starting ||
      phase == RecorderPhase.recording ||
      phase == RecorderPhase.stopping;
}

abstract interface class RecorderGateway {
  Stream<RecorderStatus> watchStatus();

  Future<RecorderStatus> getCurrentStatus();

  Future<RecorderPermissions> requestPermissions();

  Future<void> start();

  Future<void> stop();

  Future<void> playLatest();
}

class MethodChannelRecorderGateway implements RecorderGateway {
  const MethodChannelRecorderGateway();

  static const _commands = MethodChannel(
    'com.ksh321.songrecord/recorder_commands',
  );
  static const _events = EventChannel(
    'com.ksh321.songrecord/recorder_events',
  );

  @override
  Stream<RecorderStatus> watchStatus() {
    return _events.receiveBroadcastStream().map((event) {
      return RecorderStatus.fromMap(
        Map<Object?, Object?>.from(event as Map),
      );
    });
  }

  @override
  Future<RecorderStatus> getCurrentStatus() async {
    final response = await _commands.invokeMapMethod<Object?, Object?>(
      'getStatus',
    );
    return RecorderStatus.fromMap(response ?? const {});
  }

  @override
  Future<RecorderPermissions> requestPermissions() async {
    final response = await _commands.invokeMapMethod<Object?, Object?>(
      'requestPermissions',
    );
    return RecorderPermissions.fromMap(response ?? const {});
  }

  @override
  Future<void> start() => _commands.invokeMethod<void>('start');

  @override
  Future<void> stop() => _commands.invokeMethod<void>('stop');

  @override
  Future<void> playLatest() => _commands.invokeMethod<void>('playLatest');
}
