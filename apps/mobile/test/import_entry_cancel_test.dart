import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/database/local_models.dart';
import 'package:song_record/core/sync/snapshot_transport.dart';
import 'package:song_record/features/auth/auth_session.dart';
import 'package:song_record/features/backup/import/import_entry_screen.dart';

class _NoTransport implements SnapshotTransport {
  int calls = 0;
  @override
  Future<SnapshotHttpResponse> send(
    SnapshotHttpRequest request,
    AuthSession session,
    void Function() requireCurrent,
  ) async {
    calls++;
    throw StateError('Selection cancellation must not contact the server');
  }
}

void main() {
  testWidgets(
    'account switch invalidates late native selection without old screen updates',
    (tester) async {
      final prepared = await tester.runAsync(() async {
        final root = await Directory.systemTemp.createTemp(
          'p23-import-switch-',
        );
        final manager = AccountStoreManager(
          environment: AppEnvironment.dev,
          directory: () async => root,
          temporaryDirectory: () async => root,
        );
        final store = await manager.openAccount(
          '11111111-1111-4111-8111-111111111111',
        );
        return (root, manager, store);
      });
      final (root, manager, store) = prepared!;
      final selection = Completer<String?>(),
          notifier = ChangeNotifier(),
          transport = _NoTransport();
      var active = true, sessions = 0;
      const channel = MethodChannel('song_record/backup_import');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        (_) => selection.future,
      );
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: ImportEntryScreen(
              store: store,
              accountChanges: notifier,
              transport: transport,
              requireCurrent: () {
                store.requireActive();
                if (!active) throw StateError('Account switched');
              },
              session: () async {
                sessions++;
                throw StateError('No session expected');
              },
            ),
          ),
        );
        await tester.tap(find.text('파일 선택'));
        await tester.pump();
        active = false;
        notifier.notifyListeners();
        await tester.pump();
        selection.complete(null);
        await tester.pumpAndSettle();
        expect(
          find.text('계정이 바뀌었습니다. 현재 계정에서 백업을 다시 선택해 주세요.'),
          findsOneWidget,
        );
        expect(find.byType(LinearProgressIndicator), findsNothing);
        expect(transport.calls, 0);
        expect(sessions, 0);
      } finally {
        await tester.pumpWidget(const SizedBox());
        notifier.dispose();
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        );
        await tester.runAsync(() async {
          await manager.logout();
          await root.delete(recursive: true);
        });
      }
    },
  );
  testWidgets(
    'SAF cancel leaves account data unchanged and makes no server request',
    (tester) async {
      final prepared = await tester.runAsync(() async {
        final root = await Directory.systemTemp.createTemp(
          'p23-import-cancel-',
        );
        final manager = AccountStoreManager(
          environment: AppEnvironment.dev,
          directory: () async => root,
          temporaryDirectory: () async => root,
          clock: () => DateTime.utc(2026, 10, 12),
        );
        final store = await manager.openAccount(
          '11111111-1111-4111-8111-111111111111',
        );
        const id = '00000000-0000-4000-8000-000000001001';
        await store.saveEdit(
          LocalEdit(
            opId: '00000000-0000-4000-8000-000000002001',
            entity: LocalEntity.tag,
            entityId: id,
            operation: LocalOperation.create,
            baseRevision: 0,
            draft: const {'id': id, 'name': '보존할 기존 태그'},
            changes: const {'id': id, 'name': '보존할 기존 태그'},
          ),
        );
        return (root, manager, store, await store.captureExportLocal());
      });
      final (root, manager, store, before) = prepared!;
      final transport = _NoTransport();
      var sessions = 0;
      const channel = MethodChannel('song_record/backup_import');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        expect(call.method, 'pickZip');
        return null;
      });
      try {
        await tester.pumpWidget(
          MaterialApp(
            home: ImportEntryScreen(
              store: store,
              transport: transport,
              requireCurrent: store.requireActive,
              session: () async {
                sessions++;
                throw StateError('No session lookup expected');
              },
            ),
          ),
        );
        await tester.tap(find.text('파일 선택'));
        await tester.pumpAndSettle();
        final after = (await tester.runAsync(store.captureExportLocal))!;
        // This is a newly generated read timestamp, not a stored data field.
        expect(DateTime.parse(after['local_cutoff_at'] as String).isUtc, true);
        expect(
          {...after}..remove('local_cutoff_at'),
          {...before}..remove('local_cutoff_at'),
        );
        expect(transport.calls, 0);
        expect(sessions, 0);
        expect(find.byType(LinearProgressIndicator), findsNothing);
      } finally {
        await tester.pumpWidget(const SizedBox());
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        );
        await tester.runAsync(() async {
          await manager.logout();
          await root.delete(recursive: true);
        });
      }
    },
  );
}
