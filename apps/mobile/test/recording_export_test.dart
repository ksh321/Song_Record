import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/audio/local_audio.dart';
import 'package:song_record/core/database/account_paths.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/database/local_models.dart';
import 'package:song_record/core/files/recording_export.dart';

import '../tool/local_preservation_fixture.dart';

class Destination implements AudioExportDestination {
  int calls = 0;
  bool saved = true;
  Future<void> Function()? after;
  String? name;
  @override
  Future<bool> save({
    required String owner,
    required String environment,
    required String recordingId,
    required LocalAudioSource source,
    required String filename,
  }) async {
    calls++;
    name = filename;
    await after?.call();
    return saved;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('safe filename removes traversal/control characters, bounds Unicode, preserves m4a', () {
    expect(safeAudioFilename('../곡/명', '가수\\이름'), '.._곡_명 - 가수_이름.m4a');
    expect(safeAudioFilename('', ''), 'Song_Record.m4a');
    expect(safeAudioFilename('CON', ''), '_CON.m4a');
    expect(safeAudioFilename('😀' * 200, '').runes.length, 52);
  });
  test('completed input pending exports, cancellation/source/metadata remain, wrong account refuses', () async {
    final root = await Directory.systemTemp.createTemp('audio-export-');
    final manager = AccountStoreManager(
      environment: AppEnvironment.dev,
      directory: () async => root,
      temporaryDirectory: () async => root,
    );
    final owner = preservationId(1), id = preservationId(2);
    try {
      final store = await manager.openAccount(owner);
      final paths = await AccountPaths.create(root, owner, AppEnvironment.dev);
      final bytes = Uint8List.fromList([1, 2, 3, 4]);
      final file = await paths.checkedFile(paths.audioPath(id));
      await file.writeAsBytes(bytes);
      await store.recordFileAndJournal(
        recordingId: id,
        operationId: preservationId(3),
        state: FilePresence.inputPending,
        phase: JournalPhase.verified,
        pending: false,
        checksum: sha256.convert(bytes).toString(),
        sizeBytes: bytes.length,
        recovery: {'synthetic': true},
      );
      final journal = await store.readJournal(id);
      final destination = Destination();
      final export = RecordingExport(store, destination: destination);
      expect(await export.export(id, title: '곡', artist: '가수'), isTrue);
      destination.saved = false;
      expect(await export.export(id, title: '곡', artist: '가수'), isFalse);
      expect(await file.readAsBytes(), bytes);
      expect(await store.readMetadata(LocalEntity.recording, id), isNull);
      expect(await store.readJournal(id), journal);
      await file.writeAsBytes([4, 3, 2, 1]);
      await expectLater(
        export.export(id, title: '', artist: ''),
        throwsStateError,
      );
      expect(destination.calls, 2);
      await manager.openAccount(preservationId(4));
      await expectLater(
        export.export(id, title: '', artist: ''),
        throwsStateError,
      );
    } finally {
      await manager.logout();
      await root.delete(recursive: true);
    }
  });
}
