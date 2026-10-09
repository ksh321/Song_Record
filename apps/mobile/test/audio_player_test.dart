import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/audio/audio_player.dart';
import 'package:song_record/core/audio/playback_ticket.dart';
import 'package:song_record/core/database/account_store.dart';

import '../tool/local_preservation_fixture.dart';

class PlayerFake implements AudioPlayerPort {
  final stream = StreamController<PlayerEvent>.broadcast(sync: true);
  final sources = <Map<String, Object>>[];
  bool fail = false;
  int plays = 0, pauses = 0, stops = 0;
  int? seekAt;
  Completer<int>? pending;
  @override
  Stream<PlayerEvent> get events => stream.stream;
  @override
  Future<int> load(Map<String, Object> source) async {
    sources.add(source);
    if (fail) throw StateError('fixture');
    return pending == null ? 10000 : pending!.future;
  }

  @override
  Future<void> play(int token) async {
    plays++;
  }

  @override
  Future<void> pause(int token) async {
    pauses++;
  }

  @override
  Future<void> seek(int token, int milliseconds) async {
    seekAt = milliseconds;
  }

  @override
  Future<void> stop() async {
    stops++;
  }
}

class UrlFake implements PlaybackUrlProvider {
  UrlFake(this.owner, this.now);
  final String owner;
  final DateTime Function() now;
  int calls = 0;
  bool fail = false, foreign = false;
  @override
  Future<PlaybackTicket> issue(String id, Future<void> Function() guard) async {
    calls++;
    await guard();
    if (fail) throw StateError('offline');
    return PlaybackTicket(
      owner: foreign ? preservationId(99) : owner,
      recording: id,
      generation: preservationId(3),
      checksum: 'a' * 64,
      size: 12,
      revision: 1,
      url: Uri.parse(
        'https://fixture.r2.cloudflarestorage.com/object?signature=synthetic',
      ),
      expiresAt: now().add(const Duration(minutes: 5)),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  late AccountStoreManager manager;
  late AccountStore store;
  late PlayerFake port;
  late UrlFake urls;
  late AudioPlayback flow;
  late DateTime now;
  final owner = preservationId(1), id = preservationId(2);
  final bytes = Uint8List.fromList([1, 2, 3, 4]);
  setUp(() async {
    root = await Directory.systemTemp.createTemp('audio-flow-');
    manager = AccountStoreManager(
      environment: AppEnvironment.dev,
      directory: () async => root,
      temporaryDirectory: () async => root,
    );
    store = await manager.openAccount(owner);
    now = DateTime.utc(2026, 10, 9);
    port = PlayerFake();
    urls = UrlFake(owner, () => now);
    flow = AudioPlayback(store, urls, port, clock: () => now);
  });
  tearDown(() async {
    flow.dispose();
    await port.stream.close();
    await manager.logout();
    await root.delete(recursive: true);
  });
  Future<void> local() async => store.preserveDownloadedAudio(
    owner,
    id,
    sha256.convert(bytes).toString(),
    bytes.length,
    bytes,
  );
  test(
    'offline local wins, pause resume seek and completion preserve file',
    () async {
      await local();
      urls.fail = true;
      await flow.start(id);
      expect(flow.phase, PlaybackPhase.playing);
      expect(urls.calls, 0);
      expect(port.sources.single['kind'], 'local');
      await flow.pause();
      expect(flow.phase, PlaybackPhase.paused);
      await flow.resume();
      expect(port.plays, 2);
      await flow.seek(999999);
      expect(port.seekAt, 10000);
      port.stream.add(
        const PlayerEvent(1, PlaybackPhase.completed, 10000, 10000),
      );
      expect(flow.phase, PlaybackPhase.completed);
      expect(await store.readLocalAudio(id), bytes);
    },
  );
  test(
    'remote expiry renews once and restores seek; repeated failure stops',
    () async {
      await flow.start(id);
      expect(urls.calls, 1);
      now = now.add(const Duration(minutes: 6));
      port.stream.add(const PlayerEvent(1, PlaybackPhase.failed, 3000, 10000));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(urls.calls, 2);
      expect(port.seekAt, 3000);
      expect(flow.phase, PlaybackPhase.playing);
      now = now.add(const Duration(minutes: 6));
      port.stream.add(const PlayerEvent(1, PlaybackPhase.failed, 4000, 10000));
      await Future<void>.delayed(Duration.zero);
      expect(urls.calls, 2);
      expect(flow.phase, PlaybackPhase.failed);
    },
  );
  test('paused expired URL obtains a fresh ticket on resume', () async {
    await flow.start(id);
    await flow.pause();
    now = now.add(const Duration(minutes: 6));
    await flow.resume();
    expect(urls.calls, 2);
    expect(flow.phase, PlaybackPhase.playing);
  });
  test('player failure leaves actual source intact', () async {
    await local();
    port.fail = true;
    await flow.start(id);
    expect(flow.phase, PlaybackPhase.failed);
    expect(await store.readLocalAudio(id), bytes);
    expect(urls.calls, 0);
  });
  test('foreign ticket never reaches native player', () async {
    urls.foreign = true;
    await flow.start(id);
    expect(port.sources, isEmpty);
    expect(flow.phase, PlaybackPhase.failed);
  });
  test('late load from previous account cannot play', () async {
    await local();
    port.pending = Completer<int>();
    final start = flow.start(id);
    while (port.sources.isEmpty) {
      await Future<void>.delayed(Duration.zero);
    }
    await manager.openAccount(preservationId(4));
    port.pending!.complete(10000);
    await start;
    expect(port.plays, 0);
    expect(flow.phase, PlaybackPhase.failed);
  });
  test('late old events cannot replace new recording state', () async {
    await flow.start(id);
    await flow.start(preservationId(8));
    port.stream.add(const PlayerEvent(1, PlaybackPhase.failed, 0, 0));
    expect(flow.phase, PlaybackPhase.playing);
  });
}
