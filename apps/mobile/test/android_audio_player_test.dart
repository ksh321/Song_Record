import 'dart:async';

import 'package:crypto/crypto.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/core/audio/audio_player.dart';
import 'package:song_record/core/audio/playback_ticket.dart';
import 'package:song_record/core/files/recording_download.dart';

class DownloadFake implements SignedAudioDownload {
  DownloadFake(this.bytes);
  final Uint8List bytes;
  int calls = 0;
  Completer<void>? waiting;
  @override
  Future<Uint8List> fetch(
    PlaybackTicket ticket,
    Future<void> Function() guard,
  ) async {
    calls++;
    await guard();
    if (waiting != null) await waiting!.future;
    await guard();
    return bytes;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final bytes = Uint8List.fromList([1, 2, 3, 4]);
  PlaybackTicket ticket() => PlaybackTicket(
    owner: 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa',
    recording: 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb',
    generation: 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
    checksum: sha256.convert(bytes).toString(),
    size: bytes.length,
    revision: 1,
    url: Uri.parse(
      'https://fixture.r2.cloudflarestorage.com/object?signature=synthetic',
    ),
    expiresAt: DateTime.now().toUtc().add(const Duration(minutes: 5)),
  );
  Map<String, Object> source() {
    final t = ticket();
    return {
      'token': 1,
      'userId': t.owner,
      'environment': 'staging',
      'recordingId': t.recording,
      'kind': 'remote',
      'url': t.url.toString(),
      'allowLocalHttp': false,
      'ticket': t,
    };
  }

  final calls = <MethodCall>[];
  setUp(() {
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AndroidAudioPlayer.commands, (call) async {
          calls.add(call);
          return call.method == 'load'
              ? {'duration': 10000, 'waveform': List.filled(120, .5)}
              : null;
        });
  });
  tearDown(
    () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(AndroidAudioPlayer.commands, null),
  );

  test('remote playback uses one verified memory payload without URL or persistent path', () async {
    final fetch = DownloadFake(bytes);
    final player = AndroidAudioPlayer(download: fetch);
    expect(await player.load(source()), 10000);
    expect(player.preparedWaveform, List.filled(120, .5));
    expect(fetch.calls, 1);
    final args = calls.single.arguments as Map;
    expect(args['kind'], 'memory');
    expect(args['bytes'], bytes);
    expect(args['sha256'], sha256.convert(bytes).toString());
    expect(args['size'], 4);
    expect(args.keys, isNot(contains('url')));
    expect(args.keys, isNot(contains('path')));
    expect(args.keys, isNot(contains('ticket')));
  });
  test(
    'native load cannot complete with a missing or malformed waveform',
    () async {
      for (final peaks in [
        <double>[],
        [double.nan],
        List.filled(120, 2.0),
      ]) {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(
              AndroidAudioPlayer.commands,
              (call) async => call.method == 'load'
                  ? {'duration': 10000, 'waveform': peaks}
                  : null,
            );
        await expectLater(
          AndroidAudioPlayer(download: DownloadFake(bytes)).load(source()),
          throwsStateError,
        );
      }
    },
  );
  test(
    'wrong bytes or size cannot reach native playback or waveform',
    () async {
      for (final invalid in [
        Uint8List.fromList([4, 3, 2, 1]),
        Uint8List(5),
      ]) {
        await expectLater(
          AndroidAudioPlayer(download: DownloadFake(invalid)).load(source()),
          throwsStateError,
        );
      }
      expect(calls, isEmpty);
    },
  );
  test('ticket for another account cannot start a download', () async {
    final fetch = DownloadFake(bytes);
    final foreign = source()
      ..['userId'] = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd';
    await expectLater(
      AndroidAudioPlayer(download: fetch).load(foreign),
      throwsStateError,
    );
    expect(fetch.calls, 0);
    expect(calls, isEmpty);
  });
  test('stop/account change during download rejects late load', () async {
    final fetch = DownloadFake(bytes)..waiting = Completer<void>();
    final player = AndroidAudioPlayer(download: fetch);
    final load = player.load(source());
    final rejected = expectLater(load, throwsStateError);
    await player.stop();
    fetch.waiting!.complete();
    await rejected;
    expect(calls.map((c) => c.method), ['stop']);
  });
  test('new local source supersedes in-flight remote bytes', () async {
    final fetch = DownloadFake(bytes)..waiting = Completer<void>();
    final player = AndroidAudioPlayer(download: fetch);
    final old = player.load(source());
    final rejected = expectLater(old, throwsStateError);
    await player.load({
      'kind': 'local',
      'token': 2,
      'path': '/synthetic/private.m4a',
    });
    fetch.waiting!.complete();
    await rejected;
    expect(calls.length, 1);
    expect((calls.single.arguments as Map)['kind'], 'local');
  });
}
