import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/domain/account_deletion_confirmation.dart';
import 'package:song_record/core/domain/identifiers.dart';

void main() {
  late Directory root;
  final server = Uri.parse('https://example.invalid');
  late AccountStoreManager manager;
  late String owner, other;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('song-record-p23-owned-');
    owner = UuidValue.random().value;
    other = UuidValue.random().value;
    manager = AccountStoreManager(
      environment: AppEnvironment.dev,
      origin: server,
      directory: () async => root,
      temporaryDirectory: () async => root,
    );
  });
  tearDown(() async {
    await manager.logout();
    if (await root.exists()) {
      final resolved = await root.resolveSymbolicLinks();
      expect(p.equals(resolved, root.absolute.path), isTrue);
      expect(p.isWithin(Directory.systemTemp.absolute.path, resolved), isTrue);
      await root.delete(
        recursive: true,
      ); // Only the verified, freshly created test fixture.
    }
  });
  String directory(String id) =>
      p.join(root.path, 'song_record', 'dev', 'accounts', id);
  AccountDeletionConfirmation proof(String id) =>
      AccountDeletionConfirmation.device(id, server, {
        'deletion_confirmed': true,
      });
  test('confirmed owner DB and private audio are removed; active other account and external export survive', () async {
    final a = await manager.openAccount(owner);
    final audio = File(
      p.join(directory(owner), 'audio', '${UuidValue.random().value}.m4a'),
    );
    await audio.writeAsString('synthetic A');
    final external = File(p.join(root.path, 'external.zip'));
    await external.writeAsString('external copy');
    final b = await manager.openAccount(other);
    final bAudio = File(
      p.join(directory(other), 'audio', '${UuidValue.random().value}.m4a'),
    );
    await bAudio.writeAsString('synthetic B');
    await manager.applyConfirmedDeletion(proof(owner));
    expect(await Directory(directory(owner)).exists(), isFalse);
    expect(
      await File(p.join(directory(other), 'account.sqlite')).exists(),
      isTrue,
    );
    expect(await bAudio.readAsString(), 'synthetic B');
    expect(await external.readAsString(), 'external copy');
    b.requireActive();
    expect(a.requireActive, throwsStateError);
    await manager.logout();
    await expectLater(manager.openAccount(owner), throwsStateError);
    final restarted = AccountStoreManager(
      environment: AppEnvironment.dev,
      origin: server,
      directory: () async => root,
      temporaryDirectory: () async => root,
    );
    await restarted.recoverConfirmedDeletions();
    await expectLater(restarted.openAccount(owner), throwsStateError);
    final reopenedB = await restarted.openAccount(other);
    reopenedB.requireActive();
    await restarted.logout();
  });
  test('foreign server or non-confirmation cannot invalidate or erase current account', () async {
    final active = await manager.openAccount(owner);
    expect(
      () => AccountDeletionConfirmation.device(owner, server, {
        'deletion_confirmed': false,
      }),
      throwsFormatException,
    );
    expect(
      () => AccountDeletionConfirmation.device(owner, server, {
        'deletion_confirmed': true,
        'user_id': other,
      }),
      throwsFormatException,
    );
    final wrong = AccountDeletionConfirmation.device(
      owner,
      Uri.parse('https://different.invalid'),
      {'deletion_confirmed': true},
    );
    await expectLater(manager.applyConfirmedDeletion(wrong), throwsStateError);
    active.requireActive();
    expect(
      await File(p.join(directory(owner), 'account.sqlite')).exists(),
      isTrue,
    );
  });
  test('committed interrupted intent resumes without deleting another owner or needing normal login', () async {
    await manager.openAccount(owner);
    await manager.openAccount(other);
    await manager.logout();
    final journal = Directory(
      p.join(root.path, 'song_record', 'dev', 'account_deletion'),
    );
    await journal.create(recursive: true);
    await File(p.join(journal.path, '$owner.json')).writeAsString(
      jsonEncode({
        'version': 1,
        'environment': 'dev',
        'owner': owner,
        'origin': server.origin,
        'complete': false,
      }),
      flush: true,
    );
    await manager.recoverConfirmedDeletions();
    expect(await Directory(directory(owner)).exists(), isFalse);
    expect(
      await File(p.join(directory(other), 'account.sqlite')).exists(),
      isTrue,
    );
    final value = jsonDecode(
      await File(p.join(journal.path, '$owner.json')).readAsString(),
    );
    expect(value['complete'], true);
    await expectLater(manager.openAccount(owner), throwsStateError);
    (await manager.openAccount(other)).requireActive();
  });
  test(
    'late A deletion does not supersede an already requested B account opening',
    () async {
      await manager.openAccount(owner);
      final opening = manager.openAccount(other);
      final removing = manager.applyConfirmedDeletion(proof(owner));
      final b = await opening;
      await removing;
      b.requireActive();
      expect(await Directory(directory(owner)).exists(), isFalse);
      expect(
        await File(p.join(directory(other), 'account.sqlite')).exists(),
        isTrue,
      );
    },
  );
}
