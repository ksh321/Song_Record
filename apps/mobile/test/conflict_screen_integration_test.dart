import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/database/local_models.dart';
import 'package:song_record/core/sync/conflict_resolution_plan.dart';
import 'package:song_record/core/sync/conflict_review.dart';
import 'package:song_record/core/sync/local_repository.dart';
import 'package:song_record/features/sync/conflict_screen.dart';
import 'package:song_record/features/sync/sync_controller.dart';

import 'metadata_dispatcher_test.dart' show id, tag, FakeTransport;

// Observes completion only: all reads and writes use the real repository.
class ObservedActions implements ConflictActions {
  ObservedActions(this.repository, this.ioZone)
    : loaded = ioZone.run(() => Completer<void>()),
      saved = ioZone.run(() => Completer<void>());
  final Zone ioZone;
  final LocalRepository repository;
  final Completer<void> loaded;
  final Completer<void> saved;
  @override
  Future<ConflictReview> review(String opId) => ioZone.run(() async {
    try {
      return await repository.review(opId);
    } finally {
      loaded.complete();
    }
  });

  @override
  Future<void> resolve(
    ConflictReview review,
    Map<String, ConflictChoice> choices,
  ) => ioZone.run(() async {
    try {
      await repository.resolve(review, choices);
    } finally {
      saved.complete();
    }
  });
}

void main() {
  for (final selection in ['local', 'server', 'accountChanged', 'pendingLocal', 'pendingServer']) {
    testWidgets(
      'real conflict screen persists $selection choice without losing original request',
      (tester) async {
        late Directory root;
        late Zone ioZone;
        late AccountStoreManager manager;
        late AccountStore store;
        late LocalRepository repository;
        late QueuedMutation original;
        late String originalDraft;
        await tester.runAsync(() async {
          ioZone = Zone.current;
          root = await Directory.systemTemp.createTemp(
            'sr-conflict-ui-integration-',
          );
          manager = AccountStoreManager(
            environment: AppEnvironment.dev,
            directory: () async => root,
            temporaryDirectory: () async => root,
          );
          store = await manager.openAccount(id(1));
          repository = LocalRepository(store);
          await repository.save(
            repository.prepareCreate(
              entity: LocalEntity.tag,
              entityId: id(10),
              draft: {'name': 'tag'},
              changes: {'name': 'tag'},
            ),
          );
          await store.acknowledgeMutation(
            (await store.claimMutation())!,
            tag(id(10)),
          );
          await repository.save(
            repository.preparePatch(
              entity: LocalEntity.tag,
              entityId: id(10),
              baseRevision: 1,
              draft: tag(id(10), name: 'local'),
              changes: {'name': 'local'},
            ),
          );
          await store.deferMutation(
            (await store.claimMutation())!,
            'CONFLICT',
            'REVISION_CONFLICT',
            status: 409,
            serverSnapshot: tag(id(10), name: 'remote', revision: 2),
          );
          original = (await store.pendingMutations()).single;
          if (selection.startsWith('pending')) {
            final younger = repository.preparePatch(entity: LocalEntity.tag,
              entityId: id(10), baseRevision: 1,
              draft: tag(id(10), name: 'local'), changes: {'name': 'local'});
            await repository.save(younger);
            await repository.resolve(await repository.review(original.opId), {'name': ConflictChoice.server});
            original = (await store.pendingMutations()).singleWhere((m) => m.opId == younger.opId);
            expect(original.state, 'PENDING');
            expect(original.serverResponse, isNull);
            expect(await store.claimMutation(), isNull);
            final backend = RepositorySyncBackend(repository,
              FakeTransport((_) async => throw StateError('read must not send')),
              () async => throw StateError('read must not authenticate'));
            expect((await backend.load()).single.pendingReview, isTrue);
          }
          originalDraft = (await store.readMetadata(
            LocalEntity.tag,
            id(10),
          ))!.localJson!;
        });
        try {
          final actions = ObservedActions(repository, ioZone);
          await tester.pumpWidget(
            MaterialApp(
              home: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    child: const Text('열기'),
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => ConflictScreen(
                          actions: actions,
                          opId: original.opId,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.runAsync(() async {
            await tester.tap(find.text('열기'));
            await tester.pump();
            await actions.loaded.future.timeout(const Duration(seconds: 10));
          });
          await tester.pumpAndSettle();
          expect(find.text('태그 이름: local'), findsOneWidget);
          expect(find.text('태그 이름: remote'), findsOneWidget);
          if (selection == 'accountChanged') {
            await tester.runAsync(() async {
              await manager.logout();
              final other = await manager.openAccount(id(2));
              expect(await other.pendingMutations(), isEmpty);
            });
          }
          final button = find.text(
            selection == 'server' || selection == 'pendingServer' ? '서버 값 사용' : '이 기기 입력 사용',
          );
          await tester.ensureVisible(button);
          await tester.runAsync(() async {
            await tester.tap(button);
            await actions.saved.future.timeout(const Duration(seconds: 10));
          });
          await tester.pumpAndSettle();
          if (selection == 'accountChanged') {
            expect(find.textContaining('정보가 바뀌었거나'), findsOneWidget);
          } else {
            expect(find.text('열기'), findsOneWidget);
          }
          await tester.runAsync(() async {
            await manager.logout();
            store = await manager.openAccount(id(1));
            final all = await store.pendingMutations();
            final retained = all.singleWhere((m) => m.opId == original.opId);
            expect(retained.payload, original.payload);
            expect(retained.basePayload, original.basePayload);
            expect(retained.baseRevision, original.baseRevision);
            expect(retained.serverResponse, original.serverResponse);
            expect(retained.attemptCount, original.attemptCount);
            final remaining = await store.pendingWorkMutations();
            final copy = (await store.readMetadata(LocalEntity.tag, id(10)))!;
            if (selection == 'accountChanged') {
              expect(remaining.single.opId, original.opId);
              expect(copy.localJson, originalDraft);
              await manager.logout();
              final other = await manager.openAccount(id(2));
              expect(await other.pendingMutations(), isEmpty);
              expect(await other.readMetadata(LocalEntity.tag, id(10)), isNull);
            } else if (selection == 'server' || selection == 'pendingServer') {
              expect(remaining, isEmpty);
              expect(jsonDecode(copy.localJson!)['name'], 'remote');
              expect(jsonDecode(copy.serverJson!)['name'], 'remote');
            } else {
              expect(remaining, hasLength(1));
              expect(remaining.single.opId, isNot(original.opId));
              expect(remaining.single.baseRevision, 2);
              expect(jsonDecode(remaining.single.payload)['name'], 'local');
              expect(jsonDecode(copy.localJson!)['name'], 'local');
            }
          });
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          await tester.runAsync(() async {
            await manager.logout();
            expect(
              root.path.split(Platform.pathSeparator).last,
              startsWith('sr-conflict-ui-integration-'),
            );
            await root.delete(recursive: true);
          });
        }
      },
    );
  }
}
