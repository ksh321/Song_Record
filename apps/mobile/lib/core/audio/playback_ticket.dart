import '../domain/identifiers.dart';

final class PlaybackTicket {
  PlaybackTicket({
    required String owner,
    required String recording,
    required String generation,
    required this.checksum,
    required this.size,
    required this.revision,
    required this.url,
    required this.expiresAt,
    this.allowLocalHttp = false,
  }) : owner = UuidValue(owner).value,
       recording = UuidValue(recording).value,
       generation = UuidValue(generation).value {
    final local =
        allowLocalHttp &&
        url.scheme == 'http' &&
        {'localhost', '127.0.0.1', '10.0.2.2'}.contains(url.host);
    if ((!local &&
            !(url.scheme == 'https' &&
                url.host.endsWith('.r2.cloudflarestorage.com'))) ||
        url.userInfo.isNotEmpty ||
        url.hasFragment ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(checksum) ||
        size < 1 ||
        size > 6291456 ||
        revision < 1) {
      throw const FormatException('Invalid playback ticket');
    }
  }
  final String owner, recording, generation, checksum;
  final int size, revision;
  final Uri url;
  final DateTime expiresAt;
  final bool allowLocalHttp;
  @override
  String toString() => 'PlaybackTicket[REDACTED]';
}

abstract interface class PlaybackUrlProvider {
  Future<PlaybackTicket> issue(String recording, Future<void> Function() guard);
}
