import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/features/playlists/restore_candidate_song.dart';
import 'package:song_record/features/trash/trash_workflow.dart';

String id(int n) => '00000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';
Map<String, dynamic> reserved() => {
  'id': id(1),
  'lifecycle_state': 'TRASHED',
  'deleted_at': '2026-10-23T00:00:00Z',
  'pending_changes': false,
};
Map<String, dynamic> batch({bool old = false}) => {
  'batch_id': id(old ? 10 : 11),
  'revision': 4,
  'mode': 'SONG_AND_RECORDINGS',
  'deleted_at': old ? '2026-10-20T00:00:00Z' : '2026-10-23T00:00:00Z',
  'purge_after': old ? '2026-10-27T00:00:00Z' : '2026-10-30T00:00:00Z',
  'items': [
    {'id': id(1), 'entity_type': 'SONG', 'lifecycle_state': 'TRASHED'},
    {'id': id(2), 'entity_type': 'RECORDING', 'lifecycle_state': 'TRASHED'},
  ],
};

class FakeTrash implements TrashActions {
  int writes = 0;
  List<String?> cursors = [];
  Map<String, dynamic>? unresolved;
  bool skipSong = false;
  @override
  Future<Map<String, dynamic>?> pending() async => unresolved;
  @override
  Future<Map<String, dynamic>> page(String? cursor) async {
    cursors.add(cursor);
    return {
      'items': [batch(old: cursor == null)],
      'next_cursor': cursor == null ? id(10) : null,
    };
  }

  @override
  Future<Map<String, dynamic>> mutate(
    TrashBatch b,
    List<String>? ids,
    bool purge,
  ) async {
    expect(b.id, id(11));
    expect(b.revision, 4);
    expect(ids, [id(1)]);
    expect(purge, isFalse);
    writes++;
    return {
      'restored': skipSong
          ? <Map<String, dynamic>>[]
          : [
              {
                'entity_type': 'SONG',
                'value': {'id': id(1)},
              },
            ],
    };
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  test(
    'cancel does not write, matching deletion batch selects song only',
    () async {
      final trash = FakeTrash();
      expect(
        await restoreCandidateSong(
          reserved: reserved(),
          trash: trash,
          isCurrent: () => true,
          confirm: () async => false,
        ),
        CandidateRestoreResult.cancelled,
      );
      expect(trash.writes, 0);
      expect(
        await restoreCandidateSong(
          reserved: reserved(),
          trash: trash,
          isCurrent: () => true,
          confirm: () async => true,
        ),
        CandidateRestoreResult.restored,
      );
      expect(trash.writes, 1);
      expect(trash.cursors, [null, id(10), null, id(10)]);
    },
  );
  test('account change during confirmation cannot restore', () async {
    final trash = FakeTrash();
    var current = true;
    await expectLater(
      restoreCandidateSong(
        reserved: reserved(),
        trash: trash,
        isCurrent: () => current,
        confirm: () async {
          current = false;
          return true;
        },
      ),
      throwsA(isA<TrashFailure>()),
    );
    expect(trash.writes, 0);
  });
  test(
    'pending deletion, unsent edit and unresolved command do not restore',
    () async {
      for (final value in [
        reserved()..['lifecycle_state'] = 'PURGE_PENDING',
        reserved()..['pending_changes'] = true,
        reserved()..['deleted_at'] = null,
      ]) {
        final trash = FakeTrash();
        await expectLater(
          restoreCandidateSong(
            reserved: value,
            trash: trash,
            isCurrent: () => true,
            confirm: () async => throw StateError('No confirmation expected'),
          ),
          throwsA(isA<TrashFailure>()),
        );
        expect(trash.writes, 0);
      }
      final trash = FakeTrash()..unresolved = {'path': 'existing'};
      await expectLater(
        restoreCandidateSong(
          reserved: reserved(),
          trash: trash,
          isCurrent: () => true,
          confirm: () async => true,
        ),
        throwsA(isA<TrashFailure>()),
      );
      expect(trash.writes, 0);
    },
  );
  test('absent reservation continues normal registration; skipped song is not success', () async {
    final trash = FakeTrash()..skipSong = true;
    expect(
      await restoreCandidateSong(
        reserved: null,
        trash: trash,
        isCurrent: () => true,
        confirm: () async => true,
      ),
      CandidateRestoreResult.notReserved,
    );
    await expectLater(
      restoreCandidateSong(
        reserved: reserved(),
        trash: trash,
        isCurrent: () => true,
        confirm: () async => true,
      ),
      throwsA(isA<TrashFailure>()),
    );
  });
}
