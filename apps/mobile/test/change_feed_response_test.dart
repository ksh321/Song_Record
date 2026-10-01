import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/core/database/local_models.dart';
import 'package:song_record/core/sync/change_feed_response.dart';

void main() {
  const owner = '11111111-1111-4111-8111-111111111111';
  const id = '22222222-2222-4222-8222-222222222222';
  Map<String, dynamic> page() => {
    'after_seq': 3,
    'next_seq': 4,
    'head_seq': 4,
    'has_more': false,
    'changes': [
      <String, dynamic>{
        'change_seq': 4,
        'entity_type': 'CONDITION',
        'entity_id': id,
        'revision': 2,
        'operation': 'UPSERT',
        'payload': <String, dynamic>{
          'id': id,
          'user_id': owner,
          'name': 'synthetic-private',
        },
      },
    ],
  };
  ChangeFeedPage decode(Map<String, dynamic> value, {int limit = 50}) =>
      ChangeFeedPage.decode(
        jsonEncode(value),
        owner: owner,
        expectedAfter: 3,
        limit: limit,
      );
  test('maps condition code explicitly and preserves detached payload', () {
    final result = decode(page());
    expect(result.owner, owner);
    expect(result.entries.single.entity, LocalEntity.recordingCondition);
    result.entries.single.payload['name'] = 'changed';
    expect(result.entries.single.payload['name'], 'synthetic-private');
    expect(() => result.entries.clear(), throwsUnsupportedError);
    expect(result.toString(), isNot(contains('synthetic-private')));
    expect(
      result.entries.single.toString(),
      isNot(contains('synthetic-private')),
    );
  });
  test('empty caught-up and Long maximum cursors do not invent progress', () {
    for (final seq in [0, 9223372036854775807]) {
      final result = ChangeFeedPage.decode(
        jsonEncode({
          'after_seq': seq,
          'next_seq': seq,
          'head_seq': seq,
          'has_more': false,
          'changes': <Object?>[],
        }),
        owner: owner,
        expectedAfter: seq,
      );
      expect(result.nextSequence, seq);
      expect(result.entries, isEmpty);
    }
  });
  test('rejects cursor jump, wrong origin, gap and inconsistent has-more', () {
    for (final field in ['after_seq', 'next_seq', 'head_seq']) {
      final value = page();
      value[field] = 2;
      expect(() => decode(value), throwsFormatException);
    }
    final gap = page();
    gap['changes'][0]['change_seq'] = 5;
    expect(() => decode(gap), throwsFormatException);
    final more = page();
    more['has_more'] = true;
    expect(() => decode(more), throwsFormatException);
    final hidden = page();
    hidden['head_seq'] = 5;
    expect(() => decode(hidden), throwsFormatException);
    hidden['has_more'] = true;
    expect(decode(hidden, limit: 1).hasMore, isTrue);
  });
  test('rejects duplicate rows and unknown fields or entity without partial acceptance', () {
    final duplicate = page();
    duplicate['changes'].add(duplicate['changes'][0]);
    expect(() => decode(duplicate), throwsFormatException);
    final unknown = page();
    unknown['changes'][0]['entity_type'] = 'NEW_KIND';
    expect(() => decode(unknown), throwsFormatException);
    final extra = page();
    extra['unexpected'] = true;
    expect(() => decode(extra), throwsFormatException);
  });
  test(
    'foreign owner and mismatched payload identity cannot enter account data',
    () {
      final foreign = page();
      foreign['changes'][0]['payload']['user_id'] = id;
      expect(() => decode(foreign), throwsFormatException);
      final mismatch = page();
      mismatch['changes'][0]['payload']['id'] = owner;
      expect(() => decode(mismatch), throwsFormatException);
      final wrongRevision = page();
      wrongRevision['changes'][0]['payload']['revision'] = 3;
      expect(() => decode(wrongRevision), throwsFormatException);
    },
  );
  test(
    'deletion is retained without deleting files or reinterpreting payload',
    () {
      final value = page();
      value['changes'][0]['operation'] = 'DELETE';
      value['changes'][0]['payload'] = {'deleted_at': '2026-10-01T00:00:00Z'};
      final result = decode(value);
      expect(result.entries.single.deleted, isTrue);
      expect(result.entries.single.revision, 2);
      expect(result.entries.single.payload, {
        'deleted_at': '2026-10-01T00:00:00Z',
      });
    },
  );
  test('refuses numeric coercion and scalar payload', () {
    for (final bad in [0, 2.0, '2', null]) {
      final value = page();
      value['changes'][0]['revision'] = bad;
      expect(() => decode(value), throwsFormatException);
    }
    final value = page();
    value['changes'][0]['payload'] = <Object?>[];
    expect(() => decode(value), throwsFormatException);
  });
  test(
    'shared API schema fixtures are accepted or refused by the app contract',
    () {
      final cases = jsonDecode(
        File('../../fixtures/contracts/api-schema-cases.json')
            .readAsStringSync(),
      ) as List;
      final changes = cases
          .where((c) => c['schema'] == 'ChangeFeedPage')
          .toList();
      expect(changes.length, 7);
      for (final item in changes) {
        ChangeFeedPage run() => ChangeFeedPage.decode(
          jsonEncode(item['value']),
          owner: owner,
          expectedAfter: item['value']['after_seq'] as int,
        );
        if (item['valid'] == true) {
          expect(run, returnsNormally);
        } else {
          expect(run, throwsFormatException);
        }
      }
    },
  );
}
