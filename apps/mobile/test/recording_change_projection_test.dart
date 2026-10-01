import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/core/sync/recording_change_projection.dart';

void main() {
  Map<String, dynamic> saved() => {
    'id': 'recording-id',
    'revision': 2,
    'note': 'old',
    'file': <String, dynamic>{'sha256': 'synthetic'},
    'tier': 'A',
    'tag_ids': ['tag-id'],
    'tags': [
      {'id': 'tag-id', 'name_snapshot': 'old name'},
    ],
  };
  test('later editing snapshot keeps saved immutable file information', () {
    final before = saved();
    final result = projectRecordingChange(before, {
      'id': 'recording-id',
      'revision': 3,
      'note': 'new',
      'tier': null,
      'tag_ids': <String>[],
      'tags': <Object>[],
    });
    expect(result['file'], before['file']);
    expect(result['note'], 'new');
    expect(result['tier'], isNull);
    expect(result['tags'], isEmpty);
    expect(result['tag_ids'], isEmpty);
    expect(before['tier'], 'A');
  });
  test('saving response absence keeps existing tags and tier without guessing empty', () {
    final result = projectRecordingChange(saved(), {
      'id': 'recording-id',
      'revision': 3,
      'note': 'saved',
      'file': {'sha256': 'synthetic'},
    });
    expect(result['tier'], 'A');
    expect(result['tag_ids'], ['tag-id']);
    expect(result['tags'], [
      {'id': 'tag-id', 'name_snapshot': 'old name'},
    ]);
  });
  test('never invents unknown relations or aliases nested caller data', () {
    final incoming = <String, dynamic>{'id': 'recording-id', 'revision': 1};
    expect(projectRecordingChange(null, incoming), incoming);
    final before = saved();
    final result = projectRecordingChange(before, incoming);
    (result['file'] as Map)['sha256'] = 'changed';
    expect((before['file'] as Map)['sha256'], 'synthetic');
    expect(incoming.containsKey('file'), isFalse);
  });
  test(
    'refuses foreign recording and one-sided tags instead of silently merging',
    () {
      expect(
        () => projectRecordingChange(saved(), {'id': 'other'}),
        throwsFormatException,
      );
      expect(
        () => projectRecordingChange(saved(), {
          'id': 'recording-id',
          'tag_ids': <String>[],
        }),
        throwsFormatException,
      );
      expect(
        () => projectRecordingChange(saved(), {
          'id': 'recording-id',
          'file': null,
        }),
        throwsFormatException,
      );
      expect(
        () => projectRecordingChange(saved(), {
          'id': 'recording-id',
          'file': {'sha256': 'changed'},
        }),
        throwsFormatException,
      );
    },
  );
}
