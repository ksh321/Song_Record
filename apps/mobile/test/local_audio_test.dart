import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/audio/local_audio.dart';
import 'package:song_record/core/database/account_store.dart';

import '../tool/local_preservation_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'playback lookup proves disk bytes and account, never stale reports',
    () async {
      final root = await Directory.systemTemp.createTemp('local-audio-');
      final manager = AccountStoreManager(
        environment: AppEnvironment.dev,
        directory: () async => root,
        temporaryDirectory: () async => root,
      );
      final owner = preservationId(1), id = preservationId(2);
      final bytes = Uint8List.fromList([1, 2, 3, 4]);
      final hash = sha256.convert(bytes).toString();
      try {
        var store = await manager.openAccount(owner);
        var lookup = LocalAudioLookup(store);
        expect(await lookup.find(id), isNull);
        await store.preserveDownloadedAudio(
          owner,
          id,
          hash,
          bytes.length,
          bytes,
        );
        final source = (await lookup.find(id))!;
        expect(source.size, bytes.length);
        expect(source.checksum, hash);
        expect(await File(source.path).readAsBytes(), bytes);
        await File(source.path).writeAsBytes([4, 3, 2, 1], flush: true);
        expect(await lookup.find(id), isNull);
        expect(await File(source.path).readAsBytes(), [4, 3, 2, 1]);
        await File(source.path).delete();
        expect(await lookup.find(id), isNull);
        await store.preserveDownloadedAudio(
          owner,
          id,
          hash,
          bytes.length,
          bytes,
        );
        await manager.openAccount(preservationId(3));
        await expectLater(lookup.find(id), throwsStateError);
        store = await manager.openAccount(preservationId(3));
        expect(await LocalAudioLookup(store).find(id), isNull);
        store = await manager.openAccount(owner);
        lookup = LocalAudioLookup(store);
        expect((await lookup.find(id))!.checksum, hash);
      } finally {
        await manager.logout();
        await root.delete(recursive: true);
      }
    },
  );
}
