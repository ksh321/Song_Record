import 'dart:typed_data';

import '../database/account_store.dart';
import '../domain/identifiers.dart';

/// Immutable identity from the authenticated server; no file path is accepted.
final class PreservationObject {
  PreservationObject({
    required String owner,
    required String recording,
    required String generation,
    required this.checksum,
    required this.size,
    required this.revision,
  }) : owner = UuidValue(owner).value,
       recording = UuidValue(recording).value,
       generation = UuidValue(generation).value {
    if (!RegExp(r'^[0-9a-f]{64}$').hasMatch(checksum) ||
        size < 1 ||
        size > 6291456 ||
        revision < 1) {
      throw const FormatException('Invalid server object');
    }
  }
  final String owner, recording, generation, checksum;
  final int size, revision;
  @override
  String toString() => 'PreservationObject[REDACTED]';
}

abstract interface class PreservationDownload {
  Future<Uint8List> download(
    PreservationObject object,
    Future<void> Function() guard,
  );
}

final class LocalPreservation {
  LocalPreservation(this.store, this.download);
  final AccountStore store;
  final PreservationDownload download;
  Future<void> verify(PreservationObject object) async {
    Future<void> guard() async {
      store.requireActive();
      if (store.userId != object.owner) {
        throw StateError('Preservation account mismatch');
      }
    }

    await guard();
    if (await store.verifyPreservedAudio(
      object.owner,
      object.recording,
      object.checksum,
      object.size,
    )) {
      return;
    }
    final bytes = await download.download(object, guard);
    await guard();
    await store.preserveDownloadedAudio(
      object.owner,
      object.recording,
      object.checksum,
      object.size,
      bytes,
    );
    await guard();
    if (!await store.verifyPreservedAudio(
      object.owner,
      object.recording,
      object.checksum,
      object.size,
    )) {
      throw StateError('No persistent matching copy');
    }
  }
}
