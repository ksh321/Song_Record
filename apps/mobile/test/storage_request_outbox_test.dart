import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:song_record/features/settings/settings_api.dart';
import 'package:song_record/features/settings/storage_request_outbox.dart';

class MemoryVault implements DemandVault {
  String? raw;
  bool fail = false;
  @override
  Future<String?> read() async => raw;
  @override
  Future<void> write(String value) async {
    if (fail) throw StateError('disk');
    raw = value;
  }
}

Map<String, Object?> receipt(Map<String, Object?> body) => {
  ...body,
  'status': 'RECEIVED',
  'revision': 1,
  'received_at': '2026-10-12T00:00:00Z',
};
void main() {
  test('offline intents survive restart; lost replies and resend preserve IDs without recounting', () async {
    final vault = MemoryVault(),
        calls = <(String, String)>[],
        accepted = <String, Map<String, Object?>>{};
    var online = false, lose = false;
    Future<dynamic> send(Map<String, Object?> body, String op) async {
      calls.add((body['id'] as String, op));
      if (!online) throw const SettingsUnavailable(status: 503);
      accepted.putIfAbsent(body['id'] as String, () => receipt(body));
      if (lose) {
        lose = false;
        throw TimeoutException('lost reply');
      }
      return accepted[body['id']];
    }

    var box = StorageRequestOutbox(
      scope: 'owner-A',
      vault: vault,
      send: send,
      requireCurrent: () {},
    );
    await box.initialize();
    await box.submit({'PIN_LIMIT'});
    await box.submit({'PIN_LIMIT', 'STORAGE_QUOTA'});
    final ids = box.items.map((i) => (i['id'], i['op'])).toList();
    expect(ids, hasLength(2));
    expect(ids[0], isNot(ids[1]));
    box.dispose();
    box = StorageRequestOutbox(
      scope: 'owner-A',
      vault: vault,
      send: send,
      requireCurrent: () {},
    );
    await box.initialize();
    expect(box.items.map((i) => (i['id'], i['op'])).toList(), ids);
    online = true;
    lose = true;
    await box.flush();
    expect(accepted, hasLength(1));
    expect(box.items, hasLength(2));
    await box.flush();
    expect(accepted, hasLength(2));
    expect(box.items, isEmpty);
    expect(calls.where((c) => c.$1 == ids[0].$1).map((c) => c.$2).toSet(), {
      ids[0].$2,
    });
    await box.submit({'PIN_LIMIT'});
    expect(accepted, hasLength(3));
    expect(box.message, '요청이 접수됐어요. 현재 보관 한도는 그대로 유지됩니다.');
    box.dispose();
  });
  test('unknown vault write result blocks new writes until reread; corrupt data is not reset', () async {
    final vault = MemoryVault();
    var sent = 0;
    final box = StorageRequestOutbox(
      scope: 'A',
      vault: vault,
      send: (_, _) async {
        sent++;
        throw const SettingsUnavailable(status: 503);
      },
      requireCurrent: () {},
    );
    await box.initialize();
    await box.submit({'PIN_LIMIT'});
    final old = vault.raw;
    vault.fail = true;
    await box.submit({'STORAGE_QUOTA'});
    expect(box.ready, isFalse);
    expect(vault.raw, old);
    expect(sent, 1);
    vault.fail = false;
    await box.initialize();
    expect(box.items, hasLength(1));
    box.dispose();
    vault.raw = '{broken';
    final bad = StorageRequestOutbox(
      scope: 'A',
      vault: vault,
      send: (_, _) async {
        sent++;
      },
      requireCurrent: () {},
    );
    await bad.initialize();
    await bad.submit({'PIN_LIMIT'});
    expect(bad.ready, isFalse);
    expect(vault.raw, '{broken');
    bad.dispose();
  });
  test('owner change hides queue and rejects old receipt without removing the durable intent', () async {
    final vault = MemoryVault(),
        n = ChangeNotifier(),
        response = Completer<dynamic>();
    var active = true;
    final box = StorageRequestOutbox(
      scope: 'A',
      vault: vault,
      send: (_, _) => response.future,
      requireCurrent: () {
        if (!active) throw StateError('changed');
      },
      accountChanges: n,
    );
    await box.initialize();
    final sending = box.submit({'PIN_LIMIT'});
    await Future<void>.delayed(Duration.zero);
    final persisted = jsonDecode(vault.raw!) as Map;
    active = false;
    n.notifyListeners();
    expect(box.items, isEmpty);
    response.complete(
      receipt({
        'id': (persisted['items'] as List).single['id'],
        'types': ['PIN_LIMIT'],
      }),
    );
    await sending;
    expect((jsonDecode(vault.raw!) as Map)['items'], hasLength(1));
    box.dispose();
    n.dispose();
    final other = StorageRequestOutbox(
      scope: 'B',
      vault: vault,
      send: (_, _) async => throw StateError('must not send A as B'),
      requireCurrent: () {},
    );
    await other.initialize();
    expect(other.ready, isFalse);
    expect((jsonDecode(vault.raw!) as Map)['scope'], 'A');
    other.dispose();
  });
  test('expired IDs are retained as blocked; only an explicit new submission gets a new ID', () async {
    final vault = MemoryVault(), ids = <String>[];
    var expired = true;
    final box = StorageRequestOutbox(
      scope: 'A',
      vault: vault,
      send: (body, _) async {
        ids.add(body['id'] as String);
        if (expired) {
          throw const SettingsUnavailable(
            status: 409,
            code: 'STORAGE_REQUEST_EXPIRED',
          );
        }
        return receipt(body);
      },
      requireCurrent: () {},
    );
    await box.initialize();
    await box.submit({'PIN_LIMIT'});
    expect(box.items.single['state'], 'BLOCKED');
    await box.flush();
    expect(ids, hasLength(1));
    expired = false;
    await box.submit({'PIN_LIMIT'});
    expect(ids, hasLength(2));
    expect(ids[0], isNot(ids[1]));
    expect(box.items.single['error'], 'STORAGE_REQUEST_EXPIRED');
    box.dispose();
  });
}
