import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import '../audio/local_audio.dart';
import '../audio/playback_ticket.dart';
import '../database/account_store.dart';
import 'local_preservation.dart';

abstract interface class SignedAudioDownload {
  Future<Uint8List> fetch(PlaybackTicket ticket, Future<void> Function() guard);
}

final class HttpSignedAudioDownload implements SignedAudioDownload {
  const HttpSignedAudioDownload({this.timeout = const Duration(seconds: 30)});
  final Duration timeout;
  @override
  Future<Uint8List> fetch(
    PlaybackTicket ticket,
    Future<void> Function() guard,
  ) async {
    final client = HttpClient()
      ..connectionTimeout = timeout
      ..autoUncompress = false;
    try {
      return await (() async {
        await guard();
        if (!ticket.expiresAt.isAfter(DateTime.now().toUtc())) {
          throw StateError('Download ticket expired');
        }
        final request = await client.getUrl(ticket.url);
        request.followRedirects = false;
        // Deliberately no API authentication headers on object storage requests.
        final response = await request.close();
        if (response.statusCode != 200 ||
            response.contentLength > ticket.size) {
          throw StateError('Audio download failed');
        }
        final buffer = BytesBuilder(copy: false);
        var size = 0;
        await for (final chunk in response) {
          size += chunk.length;
          if (size > ticket.size) throw StateError('Audio size mismatch');
          buffer.add(chunk);
        }
        await guard();
        if (size != ticket.size) throw StateError('Audio size mismatch');
        return buffer.takeBytes();
      })().timeout(timeout);
    } catch (_) {
      throw StateError('Audio download failed');
    } finally {
      client.close(force: true);
    }
  }
}

final class _TicketDownload implements PreservationDownload {
  _TicketDownload(this.ticket, this.fetch);
  final PlaybackTicket ticket;
  final SignedAudioDownload fetch;
  @override
  Future<Uint8List> download(
    PreservationObject object,
    Future<void> Function() guard,
  ) => fetch.fetch(ticket, guard);
}

/// Same recording identity. This flow never creates or changes recording metadata.
final class RecordingDownload {
  RecordingDownload(this.store, this.urls, {SignedAudioDownload? fetch})
    : fetch = fetch ?? const HttpSignedAudioDownload();
  final AccountStore store;
  final PlaybackUrlProvider urls;
  final SignedAudioDownload fetch;
  Future<LocalAudioSource> download(String recording) async {
    Future<void> guard() async {
      store.requireActive();
    }

    await guard();
    final existing = await LocalAudioLookup(store).find(recording);
    await guard();
    if (existing != null) return existing;
    final ticket = await urls.issue(recording, guard);
    await guard();
    final now = DateTime.now().toUtc();
    if (ticket.owner != store.userId ||
        ticket.recording != recording ||
        !ticket.expiresAt.isAfter(now) ||
        ticket.expiresAt.difference(now) >
            const Duration(minutes: 5, seconds: 15)) {
      throw StateError('Download identity mismatch');
    }
    final object = PreservationObject(
      owner: ticket.owner,
      recording: ticket.recording,
      generation: ticket.generation,
      checksum: ticket.checksum,
      size: ticket.size,
      revision: ticket.revision,
    );
    await LocalPreservation(
      store,
      _TicketDownload(ticket, fetch),
    ).verify(object);
    await guard();
    final source = await LocalAudioLookup(store).find(recording);
    await guard();
    if (source == null) throw StateError('Persistent download unavailable');
    return source;
  }
}
