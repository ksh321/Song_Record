import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/database/local_models.dart';
import 'package:song_record/core/sync/conflict_resolution_plan.dart';
import 'package:song_record/core/sync/local_repository.dart';
import 'package:song_record/core/sync/mutation_request.dart';
import 'package:song_record/core/sync/mutation_transport.dart';
import 'package:song_record/features/auth/auth_session.dart';

import 'recording_save_dispatch_test.dart' show draft, body, fileSpec;
import 'recording_tier_dispatch_test.dart' show owner, rec;

String id(int n) => '00000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';

class ConflictTransport implements MutationTransport {
  final calls = <MutationRequest>[];
  @override
  Future<MutationResponse> send(
    MutationRequest request,
    AuthSession session,
    void Function() fence,
  ) async {
    fence();
    calls.add(request);
    if (request.method == 'POST') {
      return MutationResponse(201, jsonEncode(draft()));
    }
    final sent = jsonDecode(request.body) as Map<String, dynamic>;
    final snapshot = {
      ...draft(),
      'revision': 2,
      'note': 'remote',
      'tags': <Object?>[],
      'tag_ids': <String>[],
      'tier': null,
    };
    if (sent['base_revision'] == 1) {
      return MutationResponse(
        409,
        jsonEncode({
          'error': {
            'code': 'REVISION_CONFLICT',
            'details': {'current': snapshot, 'current_revision': 2},
          },
        }),
      );
    }
    if (sent['metadata_state'] == 'SAVED') {
      expect(sent['base_revision'], 3);
      return MutationResponse(
        200,
        jsonEncode({
          ...snapshot,
          'revision': 4,
          'metadata_state': 'SAVED',
          'file': fileSpec(),
          'note': 'local',
        }),
      );
    }
    expect(sent, {'base_revision': 2, 'note': 'local'});
    return MutationResponse(
      200,
      jsonEncode({...snapshot, 'revision': 3, 'note': 'local'}),
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'offline note conflict resolution stays before later offline save',
    () async {
      final dir = await Directory.systemTemp.createTemp(
        'sr-followup-conflict-',
      );
      final manager = AccountStoreManager(
        environment: AppEnvironment.dev,
        directory: () async => dir,
        temporaryDirectory: () async => dir,
      );
      var serial = 10;
      try {
        final store = await manager.openAccount(owner);
        final repo = LocalRepository(store, newId: () => id(serial++));
        final create = Map<String, Object?>.from(draft())
          ..removeWhere(
            (key, _) => {
              'revision',
              'updated_at',
              'origin_device_id',
              'link_revision',
              'lifecycle_state',
              'condition_name_snapshot',
            }.contains(key),
          );
        await repo.save(
          repo.prepareCreate(
            entity: LocalEntity.recording,
            entityId: rec,
            draft: draft(),
            changes: create,
          ),
        );
        await repo.save(
          repo.preparePatch(
            entity: LocalEntity.recording,
            entityId: rec,
            baseRevision: 0,
            draft: {...draft(), 'note': 'local'},
            changes: {'note': 'local'},
          ),
        );
        final save = body()..remove('base_revision');
        await repo.save(
          repo.preparePatch(
            entity: LocalEntity.recording,
            entityId: rec,
            baseRevision: 0,
            draft: {...draft(), ...save, 'note': 'local'},
            changes: save,
          ),
        );
        final transport = ConflictTransport();
        Future<AuthSession> session() async => AuthSession(
          userId: owner,
          deviceId: owner,
          accessToken: 'synthetic',
          refreshToken: 'unused',
          accessExpiresAt: DateTime.utc(2030),
          refreshExpiresAt: DateTime.utc(2030),
        );
        expect(await repo.dispatch(transport: transport, session: session), 1);
        final conflict = (await repo.pendingWork()).singleWhere(
          (m) => m.state == 'CONFLICT',
        );
        final review = await repo.review(conflict.opId);
        await repo.resolve(review, {'note': ConflictChoice.local});
        expect(await repo.dispatch(transport: transport, session: session), 2);
        expect(transport.calls, hasLength(4));
        expect(await repo.pendingWork(), isEmpty);
        final result = jsonDecode(
          (await repo.read(LocalEntity.recording, rec))!.localJson!,
        );
        expect(result['revision'], 4);
        expect(result['note'], 'local');
        expect(result['metadata_state'], 'SAVED');
      } finally {
        await manager.logout();
        await dir.delete(recursive: true);
      }
    },
  );
}
