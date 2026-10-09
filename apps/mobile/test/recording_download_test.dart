import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/audio/playback_ticket.dart';
import 'package:song_record/core/database/account_paths.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/database/local_models.dart';
import 'package:song_record/core/files/recording_download.dart';

import '../tool/local_preservation_fixture.dart';

class Tickets implements PlaybackUrlProvider {
  Tickets(this.owner, this.bytes);
  final String owner;
  final Uint8List bytes;
  int count = 0;
  bool foreign = false;
  @override
  Future<PlaybackTicket> issue(String id, Future<void> Function() guard) async {
    await guard();
    count++;
    return PlaybackTicket(
      owner: foreign ? preservationId(9) : owner,
      recording: id,
      generation: preservationId(3),
      checksum: sha256.convert(bytes).toString(),
      size: bytes.length,
      revision: 1,
      url: Uri.parse('https://fixture.r2.cloudflarestorage.com/audio'),
      expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 5)),
    );
  }
}

class Fetch implements SignedAudioDownload {
  Fetch(this.bytes);
  Uint8List bytes;
  Future<void> Function()? before;
  int count = 0;
  @override
  Future<Uint8List> fetch(
    PlaybackTicket ticket,
    Future<void> Function() guard,
  ) async {
    count++;
    await before?.call();
    await guard();
    return bytes;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late AccountStoreManager manager;
  late AccountStore store;
  late Tickets tickets;
  late Fetch fetch;
  final id = preservationId(2), owner = preservationId(1);
  final bytes = Uint8List.fromList([1, 2, 3, 4]);
  setUp(() async {
    root = await Directory.systemTemp.createTemp('record-download-');
    manager = AccountStoreManager(
      environment: AppEnvironment.dev,
      directory: () async => root,
      temporaryDirectory: () async => root,
    );
    store = await manager.openAccount(owner);
    tickets = Tickets(owner, bytes);
    fetch = Fetch(bytes);
  });
  tearDown(() async {
    await manager.logout();
    await root.delete(recursive: true);
  });
  test('same UUID persistent download, no metadata creation, idempotent offline copy', () async {
    final flow = RecordingDownload(store, tickets, fetch: fetch);
    final source = await flow.download(id);
    expect(source.size, 4);
    expect(await store.readLocalAudio(id), bytes);
    expect(await store.readMetadata(LocalEntity.recording, id), isNull);
    expect(await store.readJournal(id), isNull);
    tickets.foreign = true;
    await flow.download(id);
    expect(tickets.count, 1);
    expect(fetch.count, 1);
  });
  test('wrong hash and owner preserve original and leave no registered or temporary copy', () async {
    fetch.bytes = Uint8List.fromList([4, 3, 2, 1]);
    final flow = RecordingDownload(store, tickets, fetch: fetch);
    await expectLater(flow.download(id), throwsFormatException);
    final paths = await AccountPaths.create(root, owner, AppEnvironment.dev);
    expect(
      await (await paths.checkedFile(paths.audioPath(id))).exists(),
      false,
    );
    expect(await Directory('${paths.directory.path}/pending').list().length, 0);
    tickets.foreign = true;
    await expectLater(flow.download(id), throwsStateError);
    expect(fetch.count, 1);
  });
  test(
    'account changes during network request cannot persist to either account',
    () async {
      fetch.before = () async {
        await manager.openAccount(preservationId(9));
      };
      await expectLater(
        RecordingDownload(store, tickets, fetch: fetch).download(id),
        throwsStateError,
      );
      final paths = await AccountPaths.create(root, owner, AppEnvironment.dev);
      expect(
        await (await paths.checkedFile(paths.audioPath(id))).exists(),
        false,
      );
    },
  );
}
