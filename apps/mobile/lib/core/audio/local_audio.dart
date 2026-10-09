import '../database/account_store.dart';

/// A verified current-device source. Server/device reports cannot construct it.
final class LocalAudioSource {
  LocalAudioSource._(this.path, this.size, this.checksum);
  final String path;
  final int size;
  final String checksum;
  @override
  String toString() => 'LocalAudioSource[REDACTED]';
}

/// Playback callers ask locally first, before obtaining any server URL.
final class LocalAudioLookup {
  LocalAudioLookup(this.store);
  final AccountStore store;
  Future<LocalAudioSource?> find(String recordingId) async {
    final file = await store.findPlayableLocalAudio(recordingId);
    store.requireActive();
    return file == null
        ? null
        : LocalAudioSource._(file.path, file.size, file.checksum);
  }
}
