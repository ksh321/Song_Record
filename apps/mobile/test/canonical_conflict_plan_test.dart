import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/core/sync/canonical_conflict_plan.dart';
import 'package:song_record/core/sync/conflict_resolution_plan.dart';
import '../tool/sync_verification_fixture.dart' show fixtureId, fixtureSong;

void main() {
  final server = Map<String, dynamic>.from(fixtureSong(fixtureId(21), 2));
  test('different identities require explicit server or local choice', () {
    expect(prepareCanonicalPatch(server, {'note': 'mine'}, ConflictChoice.server), isNull);
    expect(jsonDecode(prepareCanonicalPatch(server, {'note': 'mine'}, ConflictChoice.local)!),
      {'base_revision': 2, 'note': 'mine'});
    expect(prepareCanonicalPatch(server, {'note': server['note']}, ConflictChoice.local), isNull);
  });
  test('identity fields and deleted targets never become a PATCH', () {
    expect(() => prepareCanonicalPatch(server, {'id': fixtureId(20)}, ConflictChoice.local), throwsStateError);
    expect(() => prepareCanonicalPatch({...server, 'lifecycle_state': 'TRASHED'}, {'note': 'mine'}, ConflictChoice.server), throwsA(anyOf(isA<StateError>(), isA<FormatException>())));
  });
  test('key mode and shift travel together', () {
    final patch = jsonDecode(prepareCanonicalPatch(server, {
      'representative_key_mode': 'ORIGINAL', 'representative_key_shift': 0,
    }, ConflictChoice.local)!);
    expect(patch['representative_key_mode'], 'ORIGINAL');
    expect(patch['representative_key_shift'], 0);
  });
}
