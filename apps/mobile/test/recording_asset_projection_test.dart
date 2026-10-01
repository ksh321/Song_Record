import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/core/sync/recording_asset_projection.dart';

const assetOwner = '11111111-1111-4111-8111-111111111111';
const assetRecording = '33333333-3333-4333-8333-333333333333';
const assetGeneration = '55555555-5555-4555-8555-555555555555';
Map<String, dynamic> assetSource({int revision = 3}) => {
  'recording_id': assetRecording,
  'user_id': assetOwner,
  'cloud_state': 'STORED',
  'blocked_reason': null,
  'generation': assetGeneration,
  'verified_size': 4,
  'sha256': 'a' * 64,
  'stored_at': '2026-10-01T00:00:00Z',
  'cloud_revision': revision,
  'created_at': '2026-09-30T00:00:00Z',
  'updated_at': '2026-10-01T00:00:00Z',
};

void main() {
  Map<String, dynamic> project(
    Map<String, dynamic> source, {
    bool snapshot = true,
  }) => projectRecordingAsset(
    source,
    owner: assetOwner,
    recordingId: assetRecording,
    revision: 3,
    snapshot: snapshot,
  );
  test(
    'asset identity and cloud revision stay distinct from recording version',
    () {
      final source = assetSource();
      final original = Map<String, dynamic>.of(source);
      final value = project(source);
      expect(value['id'], assetRecording);
      expect(value['revision'], 3);
      expect(value['cloud_revision'], 3);
      expect(value['generation'], assetGeneration);
      expect(value.containsKey('user_id'), isFalse);
      value['cloud_state'] = 'NONE';
      expect(source, original);
    },
  );
  for (final bad in <String, dynamic>{
    'recording_id': assetOwner,
    'user_id': assetRecording,
    'cloud_revision': 2,
    'generation': 123,
    'verified_size': 6291457,
    'sha256': 'bad',
    'cloud_state': 'SAVED',
    'blocked_reason': 'UNKNOWN',
    'updated_at': '2026-02-30T00:00:00Z',
    'object_key': 'must-not-be-exposed',
    'revision': 3,
  }.entries) {
    test('reject invalid or unexpected asset field ${bad.key}', () {
      expect(
        () => project({...assetSource(), bad.key: bad.value}),
        throwsFormatException,
      );
    });
  }
  test('snapshot requires owner, scoped delta can omit it', () {
    final source = assetSource()..remove('user_id');
    expect(() => project(source), throwsFormatException);
    expect(project(source, snapshot: false)['cloud_revision'], 3);
  });
  test('nil generation cannot be used as a real object generation', () {
    expect(
      () => project({
        ...assetSource(),
        'generation': '00000000-0000-0000-0000-000000000000',
      }),
      throwsFormatException,
    );
  });
  for (final state in ['STORED', 'DELETING']) {
    test('$state requires verified generation and file metadata', () {
      for (final field in [
        'generation',
        'verified_size',
        'sha256',
        'stored_at',
      ]) {
        expect(
          () => project({...assetSource(), 'cloud_state': state, field: null}),
          throwsFormatException,
        );
      }
    });
  }
  test(
    'NONE is server-copy absence only and permits nullable file metadata',
    () {
      final value = project({
        ...assetSource(),
        'cloud_state': 'NONE',
        'generation': null,
        'verified_size': null,
        'sha256': null,
        'stored_at': null,
      });
      expect(value['cloud_state'], 'NONE');
      expect(value.containsKey('lifecycle_state'), isFalse);
    },
  );
}
