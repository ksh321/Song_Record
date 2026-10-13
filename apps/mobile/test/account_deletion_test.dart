import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/features/auth/identity_link.dart';
import 'package:song_record/features/settings/account_deletion.dart';

const prep = '11111111-1111-4111-8111-111111111111';
const challenge = '22222222-2222-4222-8222-222222222222';

class MemoryReceipt implements DeletionReceiptVault {
  String? value;
  bool fail = false;
  int writes = 0;
  @override
  Future<String?> read(String scope) async => value;
  @override
  Future<void> write(String scope, String value) async {
    if (fail) throw StateError('Locked');
    this.value = value;
    writes++;
  }
}

class Proof implements IdentityLinkProofSource {
  int calls = 0;
  @override
  Future<String> linkProof(String p, String n) async {
    calls++;
    return 'synthetic-provider-proof';
  }
}

class Api extends AccountDeletionApi {
  Api(this.vault, void Function() guard)
    : super(
        Uri.parse('https://example.invalid'),
        () => throw StateError('Unused test session'),
        guard,
      );
  final MemoryReceipt vault;
  int accepts = 0, prepareCalls = 0;
  bool lost = false;
  String state = 'PREPARED';
  String? op;
  @override
  Future<Map<String, dynamic>> call(
    String path, {
    Map<String, Object?>? body,
    String? operation,
    String? statusToken,
    bool statusOnly = false,
  }) async {
    if (!statusOnly) guard();
    if (path.endsWith('reauth-challenges')) {
      return {'challenge_id': challenge, 'nonce': 'synthetic-nonce'};
    }
    if (path.endsWith('status-preparations')) {
      prepareCalls++;
      return {
        'preparation_id': prep,
        'status_token': 'a' * 43,
        'reauth_proof': challenge,
        'base_revision': 1,
        'prepare_expires_at': '2026-10-12T12:00:00Z',
      };
    }
    if (path.endsWith('deletion-requests')) {
      final protected = DeletionReceipt.decode(vault.value!, 'test:A');
      expect(protected.operation, operation);
      expect(protected.token, statusToken);
      expect(body, protected.command);
      accepts++;
      op = operation;
      state = 'ACCEPTED';
      if (lost) throw StateError('Lost reply');
      return {'operation_id': operation};
    }
    expect(statusOnly, isTrue);
    return {
      'status': state,
      'retrying': false,
      'accepted_at': state == 'PREPARED' ? null : '2026-10-12T11:00:00Z',
      'service_deleted_at': null,
      'backup_purge_due_at': state == 'PREPARED'
          ? null
          : '2026-10-19T11:00:00Z',
      'completed_at': null,
      'expires_at': state == 'PREPARED'
          ? '2026-10-12T11:10:00Z'
          : '2026-11-11T11:00:00Z',
    };
  }
}

void main() {
  test('protected confirmation is saved before consent, loss and restart recover acceptance without a new request', () async {
    final vault = MemoryReceipt(), proof = Proof(), api = Api(vault, () {});
    final flow = AccountDeletionFlow('test:A', api, proof, vault);
    await flow.restore();
    await flow.prepare('GOOGLE');
    expect(vault.writes, 1);
    expect(api.accepts, 0);
    await expectLater(flow.accept(confirmed: false), throwsStateError);
    expect(api.accepts, 0);
    api.lost = true;
    expect((await flow.accept(confirmed: true))['status'], 'ACCEPTED');
    expect(api.accepts, 1);
    final restored = AccountDeletionFlow('test:A', api, proof, vault);
    await restored.restore();
    expect(restored.receipt!.operation, api.op);
    expect((await restored.status())['status'], 'ACCEPTED');
    expect(api.accepts, 1);
    expect(proof.calls, 1);
    expect(restored.receipt.toString(), isNot(contains('a' * 43)));
  });
  test('failed secure save and corrupt or foreign protected record cannot enable submission or overwrite old receipt', () async {
    final vault = MemoryReceipt()..fail = true,
        proof = Proof(),
        api = Api(vault, () {});
    final flow = AccountDeletionFlow('test:A', api, proof, vault);
    await flow.restore();
    await expectLater(flow.prepare('GOOGLE'), throwsStateError);
    expect(flow.receipt, isNull);
    expect(api.accepts, 0);
    vault.fail = false;
    vault.value = 'corrupt';
    final blocked = AccountDeletionFlow('test:A', api, proof, vault);
    await expectLater(blocked.restore(), throwsFormatException);
    await expectLater(blocked.prepare('GOOGLE'), throwsStateError);
    expect(vault.value, 'corrupt');
    vault.value = jsonEncode(
      DeletionReceipt(
        'test:B',
        prep,
        'a' * 43,
        challenge,
        1,
        DateTime.utc(2026, 10, 12),
        challenge,
      ).toJson(),
    );
    await expectLater(blocked.restore(), throwsFormatException);
    expect(blocked.loaded, isFalse);
    expect(api.accepts, 0);
  });
  test('account guard rejects confirmation after account switch without sending a deletion command', () async {
    bool active = true;
    void guard() {
      if (!active) throw StateError('Account changed');
    }

    final vault = MemoryReceipt(), proof = Proof(), api = Api(vault, guard);
    final flow = AccountDeletionFlow('test:A', api, proof, vault);
    await flow.restore();
    await flow.prepare('GOOGLE');
    final previous = vault.value;
    active = false;
    await expectLater(flow.accept(confirmed: true), throwsStateError);
    expect(api.accepts, 0);
    expect(vault.value, previous);
  });
}
