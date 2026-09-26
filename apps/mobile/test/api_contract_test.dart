import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/core/domain/song_types.dart';
import 'package:song_record/core/domain/state_types.dart';
import 'package:song_record/features/auth/auth_session.dart';
import 'package:song_record/features/auth/identity_link.dart';

void main() {
  final fixture = jsonDecode(
    File('../../fixtures/contracts/api-wire.json').readAsStringSync(),
  ) as Map<String, dynamic>;

  test('server session example round-trips through the real app DTO', () {
    final data = fixture['authSession'] as Map<String, dynamic>;
    final session = AuthSession.fromJson(data);
    final encoded = session.toJson();
    expect(encoded.keys.toSet(), data.keys.toSet());
    for (final key in ['userId', 'deviceId', 'accessToken', 'refreshToken']) {
      expect(encoded[key], data[key]);
    }
    for (final key in ['accessExpiresAt', 'refreshExpiresAt']) {
      expect(
        DateTime.parse(encoded[key] as String),
        DateTime.parse(data[key] as String),
      );
    }
    expect(session.accessExpiresAt.isUtc, isTrue);
    expect(session.refreshExpiresAt.isUtc, isTrue);
    expect(session.toString(), isNot(contains(session.accessToken)));
  });

  test('server challenge example is accepted by the app decoder', () {
    final data = fixture['linkChallenge'] as Map<String, dynamic>;
    final challenge = LinkChallenge.fromJson(data);
    expect(challenge.id, data['challengeId']);
    expect(challenge.nonce, data['nonce']);
  });

  test('app enum wire spellings agree with Java and OpenAPI', () {
    final enums = fixture['enums'] as Map<String, dynamic>;
    final values = <String, List<Enum>>{
      'VersionCode': VersionCode.values,
      'KeyMode': KeyMode.values,
      'SongTier': SongTier.values,
      'RecordingTier': RecordingTier.values,
      'MetadataState': MetadataState.values,
      'CloudState': CloudState.values,
      'BlockedReason': BlockedReason.values,
      'LifecycleState': LifecycleState.values,
    };
    for (final entry in values.entries) {
      final names = entry.value
          .map(
            (value) => value.name
                .replaceAllMapped(RegExp('[A-Z]'), (match) => '_${match[0]}')
                .toUpperCase(),
          )
          .toList();
      expect(names, enums[entry.key], reason: entry.key);
    }
  });
}
