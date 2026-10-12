import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/features/backup/import/import_role_selection.dart';
import 'package:song_record/features/backup/import/import_roles.dart';

String id(int n) => '00000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';
void main() {
  final owner = id(1), song = id(2), recording = id(3);
  Map<String, dynamic> row(String entity, String id, Map<String, dynamic> p) =>
      {
        'entity': entity,
        'resource_id': id,
        'payload': {'id': id, ...p},
      };
  Map<String, dynamic> rec({
    String state = 'SAVED',
    String life = 'ACTIVE',
    String? parent,
  }) => row('RECORDING', recording, {
    'metadata_state': state,
    'lifecycle_state': life,
    'song_id': parent ?? song,
  });
  Map<String, dynamic> entitlement(int count) =>
      row('USER_ENTITLEMENT', owner, {'user_id': owner, 'pinned_limit': count});
  Map<String, dynamic> pin(int slot, {String? current, String? pending}) =>
      row('PIN_SLOT', owner, {
        'slot_no': slot,
        'current_recording_id': current,
        'pending_recording_id': pending,
      });
  ImportRolePlan plan({
    List<Map<String, dynamic>>? incoming,
    List<Map<String, dynamic>>? remote,
    List<Map<String, dynamic>>? history,
  }) => compareImportRoles(
    owner: owner,
    rows:
        incoming ??
        [
          row('SONG', song, {
            'lifecycle_state': 'ACTIVE',
            'representative_recording_id': recording,
          }),
          rec(),
        ],
    historicalRows: history ?? [pin(1, current: recording)],
    serverRows: remote ?? [entitlement(10)],
  );
  test('latest representative including an explicit release is preserved', () {
    for (final choice in [null, id(4)]) {
      final p = plan(
        remote: [
          entitlement(10),
          row('SONG', song, {
            'user_id': owner,
            'representative_recording_id': choice,
          }),
        ],
      );
      expect(p.records.first['payload']['representative_recording_id'], choice);
    }
  });
  test(
    'new representative needs active same-owner same-song saved recording',
    () {
      expect(
        plan().records.first['payload']['representative_recording_id'],
        recording,
      );
      for (final r in [
        rec(state: 'INPUT_PENDING'),
        rec(life: 'TRASHED'),
        rec(parent: id(5)),
      ]) {
        final p = plan(
          incoming: [
            row('SONG', song, {
              'lifecycle_state': 'ACTIVE',
              'representative_recording_id': recording,
            }),
            r,
          ],
        );
        expect(
          p.records.first['payload']['representative_recording_id'],
          isNull,
        );
        expect(p.heldRepresentatives, {song});
      }
    },
  );
  test(
    'released historical pin is offered without restoring a slot automatically',
    () {
      final p = plan(
        incoming: [
          rec(),
          pin(1, current: recording),
        ],
      );
      expect(p.pinCandidates, {recording});
      expect(p.records.any((r) => r['entity'] == 'PIN_SLOT'), false);
      expect(p.selectPins({}, () {}), isEmpty);
      expect(p.selectPins({recording}, () {}), {recording});
    },
  );
  test('current and pending pins occupy one slot and existing choices are not repeated', () {
    final p = plan(
      remote: [
        entitlement(10),
        {
          ...pin(1, current: recording, pending: id(4)),
          'payload': {
            ...(pin(1, current: recording, pending: id(4))['payload']
                as Map<String, dynamic>),
            'user_id': owner,
          },
        },
        {
          ...pin(2),
          'payload': {
            ...(pin(2)['payload'] as Map<String, dynamic>),
            'user_id': owner,
          },
        },
      ],
    );
    expect(p.availablePinSlots, 9);
    expect(p.pinCandidates, isEmpty);
  });
  test(
    'current entitlement and hard ten limit constrain explicit selection',
    () {
      expect(plan(remote: [entitlement(50)]).availablePinSlots, 10);
      final p = plan(remote: [entitlement(0)]);
      expect(() => p.selectPins({recording}, () {}), throwsStateError);
      expect(plan(remote: []).availablePinSlots, 0);
      expect(() => plan().selectPins({id(99)}, () {}), throwsStateError);
    },
  );
  test('server-owned role and state rows cannot be restored from old ZIP', () {
    final p = plan(
      incoming: [
        rec(),
        row('SONG_CLOUD_SELECTION', song, {}),
        row('USER_ENTITLEMENT', owner, {'pinned_limit': 99}),
        row('RECORDING_ASSET', recording, {}),
      ],
    );
    expect(p.records.map((r) => r['entity']), ['RECORDING']);
  });
  test(
    'foreign ownership is rejected and proposal selection rechecks guard',
    () {
      expect(
        () => plan(
          remote: [
            row('SONG', song, {'user_id': id(99)}),
          ],
        ),
        throwsFormatException,
      );
      expect(
        () => plan(
          incoming: [
            row('SONG', song, {'user_id': id(99)}),
          ],
        ),
        throwsFormatException,
      );
      expect(
        () => plan().selectPins({}, () => throw StateError('expired')),
        throwsStateError,
      );
    },
  );
  testWidgets('historical pins start unchecked and need explicit selection', (
    tester,
  ) async {
    Set<String>? chosen;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ImportRoleSelection(
            plan: plan(),
            requireCurrent: () {},
            onSelected: (value) => chosen = value,
          ),
        ),
      ),
    );
    expect(
      tester.widget<CheckboxListTile>(find.byType(CheckboxListTile)).value,
      false,
    );
    await tester.tap(find.byType(FilledButton));
    expect(chosen, isEmpty);
    await tester.tap(find.byType(CheckboxListTile));
    await tester.pump();
    await tester.tap(find.byType(FilledButton));
    expect(chosen, {recording});
  });
  test('comparison does not mutate historical rows or current baseline', () {
    final source = [
      rec(),
      row('SONG', song, {
        'lifecycle_state': 'ACTIVE',
        'representative_recording_id': recording,
      }),
    ];
    final p = plan(incoming: source);
    p.records.first['payload']['note'] = 'external';
    expect(source.first['payload'].containsKey('note'), false);
    expect(p.records.first['payload'].containsKey('note'), false);
  });
}
