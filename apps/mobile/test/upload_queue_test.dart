import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_store.dart';

import '../tool/deleted_song_verification.dart';
import '../tool/upload_verification_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('completion authentication failure blocks followup without claiming a stored file', () async {
    final root = await Directory.systemTemp.createTemp('sr-complete-auth-');
    final f = UploadFixture(root);
    try {
      await f.open();
      await f.seed(10);
      f.transport.completionStatus = 401;
      var blocked = false;
      await f.dispatcher.dispatch(
        onAuthenticationBlocked: () => blocked = true,
      );
      expect(blocked, isTrue);
      expect(
        (await f.store.uploadStatus()).single['reason'],
        'COMPLETION_AUTH',
      );
      expect(await f.store.nextUploadAt(), isNull);
      expect(await f.preserved(10), isTrue);
    } finally {
      await f.manager.logout();
      await root.delete(recursive: true);
    }
  });
  test('completion retries after restart without resending bytes and never claims verification as stored', () async {
    final root = await Directory.systemTemp.createTemp('sr-complete-');
    final f = UploadFixture(root);
    try {
      await f.open();
      await f.seed(10);
      f.transport.completionStatus = 503;
      expect(await f.dispatcher.dispatch(), 1);
      expect(f.transport.putCount, 1);
      expect(
        (await f.store.uploadStatus()).single['reason'],
        'COMPLETION_RETRY',
      );
      expect(
        await f.store.nextUploadAt(),
        f.now.add(const Duration(minutes: 1)),
      );
      await f.reopen();
      f.now = f.now.add(const Duration(minutes: 1));
      f.transport.completionStatus = 202;
      await f.dispatcher.dispatch();
      expect(f.transport.putCount, 1);
      expect(f.transport.completionCount, 2);
      final status = (await f.store.uploadStatus()).single;
      expect(status['phase'], 'UPLOADED');
      expect(status['reason'], 'VERIFICATION_ACCEPTED');
      final accepted = f.now;
      for (final seconds in [5, 30, 120]) {
        expect(
          await f.store.nextUploadAt(),
          accepted.add(Duration(seconds: seconds)),
        );
        f.now = accepted.add(Duration(seconds: seconds));
        await f.dispatcher.dispatch();
        await f.reopen();
      }
      expect(await f.store.nextUploadAt(), isNull);
      expect(f.transport.putCount, 1);
      expect(f.transport.completionCount, 2);
      expect(await f.preserved(10), isTrue);
    } finally {
      await f.manager.logout();
      await root.delete(recursive: true);
    }
  });
  test(
    'only matching canonical stored asset ends verification followups',
    () async {
      final root = await Directory.systemTemp.createTemp('sr-verify-followup-');
      final f = UploadFixture(root);
      try {
        await f.open();
        await f.seed(10);
        await f.dispatcher.dispatch();
        final id = uploadFixtureId(10);
        Future<void> asset(String state, String hash) => f.sql(
          "INSERT OR REPLACE INTO metadata_copies(user_id,entity_type,entity_id,server_revision,server_payload,updated_at) VALUES(?,'RECORDING_ASSET',?,1,?,?)",
          [
            f.owner,
            id,
            jsonEncode({
              'recording_id': id,
              'cloud_state': state,
              'verified_size': f.bytes.length,
              'sha256': hash,
            }),
            f.now.millisecondsSinceEpoch,
          ],
        );
        final hash = sha256.convert(f.bytes).toString();
        await asset('VERIFYING', hash);
        expect(await f.store.nextUploadAt(), isNotNull);
        expect((await f.store.uploadStatus()).single['phase'], 'UPLOADED');
        await asset('STORED', 'f' * 64);
        expect(await f.store.nextUploadAt(), isNotNull);
        await asset('STORED', hash);
        expect(await f.store.nextUploadAt(), isNull);
        expect((await f.store.uploadStatus()).single['phase'], 'STORED');
        await f.dispatcher.dispatch();
        expect(f.transport.putCount, 1);
        expect(f.transport.completionCount, 1);
        expect(await f.preserved(10), isTrue);
      } finally {
        await f.manager.logout();
        await root.delete(recursive: true);
      }
    },
  );
  test(
    'completion uses the existing bounded retry budget and keeps the original',
    () async {
      final root = await Directory.systemTemp.createTemp('sr-complete-budget-');
      final f = UploadFixture(root);
      try {
        await f.open();
        await f.seed(10);
        f.transport.completionStatus = 503;
        await f.dispatcher.dispatch();
        for (var i = 0; i < 3; i++) {
          f.now = f.now.add(const Duration(hours: 1));
          await f.dispatcher.dispatch();
        }
        expect(f.transport.completionCount, 4);
        expect(f.transport.putCount, 1);
        expect(await f.store.nextUploadAt(), isNull);
        expect(await f.preserved(10), isTrue);
      } finally {
        await f.manager.logout();
        await root.delete(recursive: true);
      }
    },
  );
  test(
    'lost completion claim is recovered without reupload after process restart',
    () async {
      final root = await Directory.systemTemp.createTemp('sr-complete-claim-');
      final f = UploadFixture(root);
      try {
        await f.open();
        await f.seed(10);
        await f.store.discoverUploads();
        final w = (await f.store.claimUpload())!;
        await f.store.saveUploadTicket(w, uploadFixtureId(900));
        await f.store.settleUpload(w, 'UPLOADED', null);
        final c = (await f.store.claimUploadCompletion())!;
        expect(await f.store.claimUploadCompletion(), isNull);
        await f.reopen();
        expect(await f.store.uploadCompletionCurrent(c), isFalse);
        await f.dispatcher.dispatch();
        expect(f.transport.putCount, 0);
        expect(f.transport.completionCount, 1);
        expect(await f.preserved(10), isTrue);
      } finally {
        await f.manager.logout();
        await root.delete(recursive: true);
      }
    },
  );
  test('durable account upload queue keeps originals across every transfer outcome', () async {
    final root = await Directory.systemTemp.createTemp('sr-upload-check-');
    try {
      final result = await verifyUploadQueue(root);
      expect(result.length, 7);
      for (final r in result.entries) {
        expect(r.value, isTrue, reason: r.key);
      }
    } finally {
      await root.delete(recursive: true);
    }
  });
  test(
    'resolved offline recording history does not block the acknowledged file',
    () async {
      final root = await Directory.systemTemp.createTemp('sr-upload-history-');
      try {
        final original = await verifyDeletedSong(root);
        expect(original.values.every((v) => v), isTrue);
        final run =
            (await root.list().where((f) => f is Directory).toList()).single
                as Directory;
        final manager = AccountStoreManager(
          environment: AppEnvironment.dev,
          directory: () async => run,
          temporaryDirectory: () async => run,
        );
        try {
          final store = await manager.openAccount(uploadFixtureId(1));
          await store.discoverImportUploads({});
          expect(await store.uploadStatus(), isEmpty);
          await store.discoverImportUploads({uploadFixtureId(999)});
          expect(await store.uploadStatus(), isEmpty);
          await store.discoverUploads();
          expect((await store.uploadStatus()).length, 1);
          final recording =
              (await store.uploadStatus()).single['recording_id'] as String;
          expect(
            (await store.recordingStorageEvidence(recording))['draft'],
            isFalse,
          );
          expect(await store.claimUpload(), isNotNull);
        } finally {
          await manager.logout();
        }
      } finally {
        await root.delete(recursive: true);
      }
    },
  );
}
