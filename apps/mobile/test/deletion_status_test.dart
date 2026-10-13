import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/features/settings/account_deletion.dart';
import 'package:song_record/features/settings/account_deletion_screen.dart';
import 'package:song_record/features/settings/deletion_status.dart';

import 'account_deletion_test.dart' as fixture;

Map<String, dynamic> response(String state, {bool retrying = false}) => {
  'status': state,
  'retrying': retrying,
  'accepted_at': state == 'PREPARED' ? null : '2026-10-01T00:00:00Z',
  'service_deleted_at': {'BACKUP_CLEANUP', 'COMPLETED'}.contains(state)
      ? '2026-10-02T00:00:00Z'
      : null,
  'backup_purge_due_at': state == 'PREPARED' ? null : '2026-10-08T00:00:00Z',
  'completed_at': state == 'COMPLETED' ? '2026-10-03T00:00:00Z' : null,
  'expires_at': state == 'PREPARED'
      ? '2026-10-01T00:10:00Z'
      : '2026-10-31T00:00:00Z',
};

class StatusApi extends fixture.Api {
  StatusApi(fixture.MemoryReceipt vault) : super(vault, () {});
  Map<String, dynamic> reply = response('BACKUP_CLEANUP', retrying: true);
  @override
  Future<Map<String, dynamic>> call(
    String path, {
    Map<String, Object?>? body,
    String? operation,
    String? statusToken,
    bool statusOnly = false,
  }) async {
    if (statusOnly) return reply;
    return super.call(
      path,
      body: body,
      operation: operation,
      statusToken: statusToken,
      statusOnly: statusOnly,
    );
  }
}

void main() {
  test('five states distinguish service and backup completion and time never completes deletion', () {
    for (final state in [
      'PREPARED',
      'ACCEPTED',
      'DELETING',
      'BACKUP_CLEANUP',
      'COMPLETED',
    ]) {
      final status = DeletionStatus.parse(response(state));
      expect(status.state, state);
      expect(
        status.overdue(DateTime.utc(2026, 10, 13)),
        !{'PREPARED', 'COMPLETED'}.contains(state),
      );
      expect(
        status.message(DateTime.utc(2026, 10, 13)),
        isNot(contains('모든 사본')),
      );
    }
    final retry = DeletionStatus.parse(
      response('BACKUP_CLEANUP', retrying: true),
    );
    expect(retry.message(DateTime.utc(2026, 10, 13)), contains('재시도'));
    expect(retry.message(DateTime.utc(2026, 10, 13)), contains('기한을 초과'));
    expect(retry.state, 'BACKUP_CLEANUP');
  });
  test('missing or contradictory completion evidence and personal fields cannot display completion', () {
    final valid = response('COMPLETED');
    for (final value in [
      {...valid, 'service_deleted_at': null},
      {...valid, 'completed_at': null},
      {...valid, 'retrying': true},
      {...valid, 'email': 'private'},
      {...valid, 'completed_at': '2026-09-01T00:00:00Z'},
      {...valid, 'expires_at': 'unknown'},
      {...response('ACCEPTED'), 'completed_at': '2026-10-03T00:00:00Z'},
      {...response('PREPARED'), 'accepted_at': '2026-10-01T00:00:00Z'},
      {...valid, 'backup_purge_due_at': '2026-10-09T00:00:00Z'},
    ]) {
      expect(() => DeletionStatus.parse(value), throwsFormatException);
    }
  });
  testWidgets(
    'status-only recovery exposes dates, retry, overdue and copy limits without deletion controls',
    (tester) async {
      final vault = fixture.MemoryReceipt(), api = StatusApi(vault);
      final flow = AccountDeletionFlow('test:A', api, fixture.Proof(), vault);
      await flow.restore();
      await flow.prepare('GOOGLE');
      var callbacks = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: AccountDeletionScreen(
            flow: flow,
            statusOnly: true,
            onAccepted: () async {
              callbacks++;
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(callbacks, 1);
      expect(find.textContaining('운영 백업 정리 중'), findsOneWidget);
      expect(find.textContaining('재시도'), findsOneWidget);
      expect(find.textContaining('기한을 초과'), findsOneWidget);
      expect(find.textContaining('접수:'), findsOneWidget);
      expect(find.textContaining('운영 백업 정리 기한:'), findsOneWidget);
      expect(find.textContaining('앱 밖에 내보낸 ZIP·M4A'), findsOneWidget);
      expect(find.text('전체 계정 삭제 접수'), findsNothing);
      api.reply = response('COMPLETED');
      await tester.ensureVisible(find.text('확인증으로 접수 상태 확인'));
      await tester.tap(find.text('확인증으로 접수 상태 확인'));
      await tester.pumpAndSettle();
      expect(find.textContaining('운영 백업 정리가 확인'), findsOneWidget);
      expect(find.textContaining('기한을 초과'), findsNothing);
      expect(api.accepts, 0);
      api.reply = {...response('COMPLETED'), 'completed_at': null};
      await tester.ensureVisible(find.text('확인증으로 접수 상태 확인'));
      await tester.tap(find.text('확인증으로 접수 상태 확인'));
      await tester.pumpAndSettle();
      expect(find.textContaining('마지막 확인 결과를 유지'), findsOneWidget);
      expect(api.accepts, 0);
    },
  );
  testWidgets('initial unverified status cannot open final deletion consent', (
    tester,
  ) async {
    final vault = fixture.MemoryReceipt(), api = StatusApi(vault);
    final flow = AccountDeletionFlow('test:A', api, fixture.Proof(), vault);
    await flow.restore();
    await flow.prepare('GOOGLE');
    api.reply = {'status': 'COMPLETED', 'retrying': false};
    await tester.pumpWidget(
      MaterialApp(
        home: AccountDeletionScreen(flow: flow, onAccepted: () async {}),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('전체 계정 삭제 접수'), findsNothing);
    expect(find.byType(CheckboxListTile), findsNothing);
    expect(find.textContaining('처리를 확인하지 못했어요'), findsOneWidget);
    expect(api.accepts, 0);
  });
}
