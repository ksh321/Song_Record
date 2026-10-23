import '../trash/trash_workflow.dart';

enum CandidateRestoreResult { notReserved, cancelled, restored }

/// A catalog candidate does not create another Song while its number is reserved.
/// The existing durable trash command owns retries and the server owns linking.
Future<CandidateRestoreResult> restoreCandidateSong({
  required Map<String, dynamic>? reserved,
  required TrashActions? trash,
  required bool Function() isCurrent,
  required Future<bool> Function() confirm,
}) async {
  void checkCurrent() {
    if (!isCurrent()) throw const TrashFailure('계정이 바뀌었어요. 다시 열어 주세요.');
  }

  checkCurrent();
  if (reserved == null) return CandidateRestoreResult.notReserved;
  if (reserved['lifecycle_state'] == 'PURGE_PENDING') {
    throw const TrashFailure('영구 삭제 처리 중이에요. 완료 후 다시 확인해 주세요.');
  }
  if (trash == null ||
      reserved['pending_changes'] == true ||
      reserved['lifecycle_state'] != 'TRASHED' ||
      reserved['deleted_at'] == null) {
    throw const TrashFailure('동기화를 완료한 뒤 다시 시도해 주세요.');
  }
  if (await trash.pending() != null) {
    throw const TrashFailure('설정 → 휴지통에서 결과 미확인 요청을 먼저 확인해 주세요.');
  }
  checkCurrent();
  final deleted = serverTime(reserved['deleted_at'] as String);
  final id = reserved['id'] as String;
  String? cursor;
  final seen = <String>{};
  TrashBatch? selected;
  do {
    final page = await trash.page(cursor);
    checkCurrent();
    for (final raw in page['items'] as List) {
      final batch = TrashBatch.fromJson(Map<String, dynamic>.from(raw as Map));
      if (batch.deleted == deleted &&
          batch.items.any(
            (item) =>
                item['entity_type'] == 'SONG' &&
                item['id'] == id &&
                (item['state'] == 'TRASHED' ||
                    item['lifecycle_state'] == 'TRASHED'),
          )) {
        selected = batch;
        break;
      }
    }
    cursor = page['next_cursor'] as String?;
    if (cursor != null && !seen.add(cursor)) {
      throw const TrashFailure('휴지통 목록을 다시 확인해 주세요.');
    }
  } while (selected == null && cursor != null);
  if (selected == null) {
    throw const TrashFailure('복원할 곡의 상태가 바뀌었어요. 동기화 후 다시 확인해 주세요.');
  }
  if (!await confirm()) return CandidateRestoreResult.cancelled;
  checkCurrent();
  final result = await trash.mutate(selected, [id], false);
  checkCurrent();
  if (!(result['restored'] as List).any(
    (item) => item['entity_type'] == 'SONG' && item['value']?['id'] == id,
  )) {
    throw const TrashFailure('곡의 상태가 바뀌어 복원하지 못했어요. 다시 확인해 주세요.');
  }
  return CandidateRestoreResult.restored;
}
