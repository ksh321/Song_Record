import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/core/sync/three_way_merge.dart';

void main() {
  const id = '22222222-2222-4222-8222-222222222222';
  Map<String, dynamic> baseline() => {
    'id': id,
    'revision': 1,
    'title': 'old',
    'memo': null,
    'mode': 'ORIGINAL',
    'shift': 0,
  };
  ThreeWayComparison compare(
    Map<String, dynamic> local,
    Map<String, dynamic> remote, {
    Map<String, dynamic>? base,
    bool missing = false,
    List<Set<String>> groups = const [],
  }) => compareThreeWayPatch(
    base: missing ? null : (base ?? baseline()),
    localChanges: local,
    server: {...baseline(), 'revision': 2, ...remote},
    editableFields: {'title', 'memo', 'mode', 'shift'},
    atomicGroups: groups,
  );

  test(
    'disjoint field edits keep remote change and reapply only local change',
    () {
      final result = compare({'title': 'local'}, {'memo': 'remote'});
      expect(result.safePatch, {'title': 'local'});
      expect(result.requiresChoice, isFalse);
    },
  );
  test(
    'same field conflict preserves no winner while independent edit is safe',
    () {
      final result = compare(
        {'title': 'local', 'memo': 'note'},
        {'title': 'remote'},
      );
      expect(result.safePatch, {'memo': 'note'});
      expect(result.conflicts, [
        {'title'},
      ]);
      expect(result.requiresChoice, isTrue);
    },
  );
  test('unchanged local and identical concurrent result produce no patch', () {
    expect(compare({'title': 'old'}, {'title': 'remote'}).safePatch, isEmpty);
    final same = compare({'title': 'new'}, {'title': 'new'});
    expect(same.safePatch, isEmpty);
    expect(same.conflicts, isEmpty);
  });
  test(
    'explicit null is a real edit but omitted local fields stay untouched',
    () {
      final base = {...baseline(), 'memo': 'before'};
      expect(
        compare({'memo': null}, {'memo': 'before'}, base: base).safePatch,
        {'memo': null},
      );
      expect(compare({}, {'memo': 'remote'}, base: base).safePatch, isEmpty);
    },
  );
  test('missing baseline is unknown except an explicit equal remote value', () {
    expect(compare({'memo': 'new'}, {}, missing: true).conflicts, [
      {'memo'},
    ]);
    expect(compare({'memo': null}, {}, missing: true).conflicts, isEmpty);
    final base = baseline()..remove('memo');
    expect(compare({'memo': 'new'}, {}, base: base).conflicts, [
      {'memo'},
    ]);
  });
  test('missing server field is never treated as null', () {
    final result = compareThreeWayPatch(
      base: baseline(),
      localChanges: {'memo': null},
      server: {...baseline()}..remove('memo'),
      editableFields: {'memo'},
    );
    expect(result.conflicts, [
      {'memo'},
    ]);
  });
  test(
    'atomic pair prevents individually safe edits creating invalid combination',
    () {
      final result = compare(
        {'shift': 2},
        {'mode': 'CUSTOM'},
        groups: [
          {'mode', 'shift'},
        ],
      );
      expect(result.safePatch, isEmpty);
      expect(result.conflicts, [
        {'mode', 'shift'},
      ]);
      expect(
        compare(
          {'shift': 2},
          {},
          groups: [
            {'mode', 'shift'},
          ],
        ).safePatch,
        {'mode': 'ORIGINAL', 'shift': 2},
      );
    },
  );
  test('unknown atomic group requires every local value for equal no-op', () {
    expect(
      compare(
        {'shift': 0},
        {},
        missing: true,
        groups: [
          {'mode', 'shift'},
        ],
      ).requiresChoice,
      isTrue,
    );
    expect(
      compare(
        {'shift': 0, 'mode': 'ORIGINAL'},
        {},
        missing: true,
        groups: [
          {'mode', 'shift'},
        ],
      ).requiresChoice,
      isFalse,
    );
  });
  test('identity owner and revision mismatch are rejected', () {
    for (final remote in <Map<String, dynamic>>[
      {'id': 'bad'},
      {'id': '33333333-3333-4333-8333-333333333333'},
      {'revision': 0},
      {'revision': 1.5},
    ]) {
      expect(() => compare({'title': 'new'}, remote), throwsFormatException);
    }
    expect(
      () => compare({'title': 'new'}, {}, base: {...baseline(), 'revision': 3}),
      throwsFormatException,
    );
    expect(
      () => compare(
        {'title': 'new'},
        {'user_id': 'other'},
        base: {...baseline(), 'user_id': 'owner'},
      ),
      throwsFormatException,
    );
  });
  test(
    'reserved fields unexpected patches and overlapping groups rejected',
    () {
      expect(() => compare({'revision': 2}, {}), throwsFormatException);
      expect(
        () => compareThreeWayPatch(
          base: baseline(),
          localChanges: {},
          server: baseline(),
          editableFields: {'id'},
        ),
        throwsFormatException,
      );
      expect(
        () => compare(
          {},
          {},
          groups: [
            {'title', 'memo'},
            {'memo', 'shift'},
          ],
        ),
        throwsArgumentError,
      );
      expect(
        () => compare(
          {},
          {},
          groups: [
            {'title'},
          ],
        ),
        throwsArgumentError,
      );
    },
  );
  test(
    'nested object order is equivalent but array order remains significant',
    () {
      final base = {
        ...baseline(),
        'memo': {
          'a': 1,
          'b': [1, 2],
        },
      };
      expect(
        compare(
          {
            'memo': {
              'b': [1, 2],
              'a': 1,
            },
          },
          {'memo': 'remote'},
          base: base,
        ).safePatch,
        isEmpty,
      );
      expect(
        compare(
          {
            'memo': {
              'b': [2, 1],
              'a': 1,
            },
          },
          {'memo': 'remote'},
          base: base,
        ).requiresChoice,
        isTrue,
      );
    },
  );
  test(
    'outputs are detached and conflict sets immutable without changing inputs',
    () {
      final local = <String, dynamic>{
        'memo': [1, 2],
        'title': 'mine',
      };
      final remote = <String, dynamic>{'title': 'theirs'};
      final result = compare(local, remote);
      (local['memo'] as List<int>).add(3);
      final output = result.safePatch;
      (output['memo'] as List<dynamic>).clear();
      expect(result.safePatch, {
        'memo': [1, 2],
      });
      expect(() => result.conflicts.first.add('memo'), throwsUnsupportedError);
      expect(() => result.conflicts.clear(), throwsUnsupportedError);
      expect(remote, {'title': 'theirs'});
      expect(result.toString(), isNot(contains('mine')));
    },
  );
}
