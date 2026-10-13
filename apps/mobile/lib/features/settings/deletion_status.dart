/// Restricted deletion proof response. Time passing never manufactures completion.
class DeletionStatus {
  DeletionStatus._(this.state, this.retrying, this.times);
  final String state;
  final bool retrying;
  final Map<String, DateTime?> times;

  static const labels = {
    'accepted_at': '접수',
    'service_deleted_at': '서비스 데이터 삭제 확인',
    'backup_purge_due_at': '운영 백업 정리 기한',
    'completed_at': '삭제 완료 확인',
    'expires_at': '확인증 만료',
  };

  factory DeletionStatus.parse(Map<String, dynamic> value) {
    const states = {
      'PREPARED',
      'ACCEPTED',
      'DELETING',
      'BACKUP_CLEANUP',
      'COMPLETED',
    };
    if (!states.contains(value['status']) ||
        value['retrying'] is! bool ||
        value.keys.any(
          (k) => !{'status', 'retrying', ...labels.keys}.contains(k),
        )) {
      throw const FormatException('Invalid restricted deletion status');
    }
    final times = <String, DateTime?>{};
    for (final key in labels.keys) {
      final raw = value[key];
      if (raw != null && (raw is! String || !raw.endsWith('Z'))) {
        throw const FormatException('Invalid deletion timestamp');
      }
      times[key] = raw == null ? null : DateTime.parse(raw as String).toUtc();
    }
    final state = value['status'] as String;
    final accepted = times['accepted_at'],
        service = times['service_deleted_at'];
    final due = times['backup_purge_due_at'], completed = times['completed_at'];
    final expiry = times['expires_at'];
    if (expiry == null ||
        (state == 'PREPARED' &&
            (accepted != null ||
                service != null ||
                due != null ||
                completed != null)) ||
        (state != 'PREPARED' &&
            (accepted == null ||
                due == null ||
                !due.isAfter(accepted) ||
                !expiry.isAfter(accepted) ||
                due.isAfter(accepted.add(const Duration(days: 7))))) ||
        (service != null && (accepted == null || service.isBefore(accepted))) ||
        ({'BACKUP_CLEANUP', 'COMPLETED'}.contains(state) && service == null) ||
        (state == 'COMPLETED' &&
            (completed == null ||
                completed.isBefore(service!) ||
                value['retrying'] == true)) ||
        (state != 'COMPLETED' && completed != null)) {
      throw const FormatException('Inconsistent deletion progress');
    }
    return DeletionStatus._(state, value['retrying'] as bool, times);
  }

  bool overdue(DateTime now) =>
      state != 'PREPARED' &&
      state != 'COMPLETED' &&
      times['backup_purge_due_at']!.isBefore(now.toUtc());

  String message(DateTime now) {
    final text = switch (state) {
      'PREPARED' => '아직 탈퇴 접수 전이에요. 준비는 10분 동안 유효하며 일반 이용은 차단되지 않았어요.',
      'ACCEPTED' => '탈퇴가 접수됐어요. 일반 이용은 차단됐고 삭제 작업이 대기 중이에요.',
      'DELETING' => '서비스 DB와 보관 음원을 삭제하고 있어요. 아직 삭제 완료가 아닙니다.',
      'BACKUP_CLEANUP' => '서비스 데이터 삭제가 확인됐고 운영 백업 정리 중이에요. 아직 전체 삭제 완료가 아닙니다.',
      _ =>
        '서비스 데이터와 관련 운영 백업 정리가 확인됐어요. 필요한 최소 상태 기록·삭제 방지 원장은 별도 정책에 따라 유지됩니다.',
    };
    return '$text${retrying ? '\n장애로 재시도 중이에요. 시간 경과만으로 완료 처리하지 않습니다.' : ''}'
        '${overdue(now) ? '\n운영 백업 정리 기한을 초과했어요. 운영 확인·복구가 필요하며 완료로 표시하지 않습니다.' : ''}';
  }
}
