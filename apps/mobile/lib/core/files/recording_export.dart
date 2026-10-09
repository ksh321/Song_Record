import 'package:flutter/services.dart';

import '../audio/local_audio.dart';
import '../database/account_store.dart';

const externalAudioCopyNotice = '내보낸 파일은 독립 사본이며 앱의 삭제·탈퇴로 회수되지 않습니다.';

String safeAudioFilename(String title, String artist) {
  String clean(String value) => value
      .replaceAll(RegExp(r'[\x00-\x1f\x7f/\\:*?"<>|]'), '_')
      .trim()
      .replaceAll(RegExp(r'[. ]+$'), '');
  final parts = [
    clean(title),
    clean(artist),
  ].where((s) => s.isNotEmpty).toList();
  var name = parts.isEmpty ? 'Song_Record' : parts.join(' - ');
  name = String.fromCharCodes(name.runes.take(48));
  if (RegExp(
    r'^(CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\.|$)',
    caseSensitive: false,
  ).hasMatch(name)) {
    name = '_$name';
  }
  return '$name.m4a';
}

abstract interface class AudioExportDestination {
  Future<bool> save({
    required String owner,
    required String environment,
    required String recordingId,
    required LocalAudioSource source,
    required String filename,
  });
}

final class AndroidAudioExport implements AudioExportDestination {
  const AndroidAudioExport();
  static const channel = MethodChannel('song_record/audio_export');
  @override
  Future<bool> save({
    required String owner,
    required String environment,
    required String recordingId,
    required LocalAudioSource source,
    required String filename,
  }) async =>
      await channel.invokeMethod<bool>('export', {
        'userId': owner,
        'environment': environment,
        'recordingId': recordingId,
        'path': source.path,
        'size': source.size,
        'checksum': source.checksum,
        'filename': filename,
      }) ??
      false;
}

/// Completed INPUT_PENDING is readable; export does not create metadata or mutate the source.
final class RecordingExport {
  RecordingExport(this.store, {AudioExportDestination? destination})
    : destination = destination ?? const AndroidAudioExport();
  final AccountStore store;
  final AudioExportDestination destination;
  bool _busy = false;
  Future<bool> export(
    String recordingId, {
    required String title,
    required String artist,
  }) async {
    if (_busy) throw StateError('Export already active');
    _busy = true;
    try {
      final source = await LocalAudioLookup(store).find(recordingId);
      store.requireActive();
      if (source == null) throw StateError('No verified completed local audio');
      final saved = await destination.save(
        owner: store.userId,
        environment: store.environment.name,
        recordingId: recordingId,
        source: source,
        filename: safeAudioFilename(title, artist),
      );
      store.requireActive();
      return saved;
    } finally {
      _busy = false;
    }
  }
}
