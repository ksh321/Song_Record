import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/domain/identifiers.dart';
import 'settings_api.dart';

abstract interface class DemandVault {
  Future<String?> read();
  Future<void> write(String value);
}

class SecureDemandVault implements DemandVault {
  SecureDemandVault(String scope)
    : key = 'storage_demand_${sha256.convert(utf8.encode(scope))}';
  final String key;
  final storage = const FlutterSecureStorage();
  @override
  Future<String?> read() => storage.read(key: key);
  @override
  Future<void> write(String value) => storage.write(key: key, value: value);
  Future<void> clear() => storage.delete(key: key);
}

/// One encrypted queue per installation/environment/origin/account.
/// IDs and packets survive retries and account-store lease replacement.
class StorageRequestOutbox extends ChangeNotifier {
  StorageRequestOutbox({
    required this.scope,
    required this.vault,
    required this.send,
    required this.requireCurrent,
    this.accountChanges,
  }) {
    accountChanges?.addListener(scopeChanged);
  }
  final String scope;
  final DemandVault vault;
  final Future<dynamic> Function(Map<String, Object?> body, String op) send;
  final VoidCallback requireCurrent;
  final Listenable? accountChanges;
  void scopeChanged() {
    try {
      guard();
    } catch (_) {
      if (!_closed) {
        ready = false;
        _items = [];
        message = '로그인 상태가 바뀌었어요. 설정을 다시 열어 주세요.';
        notifyListeners();
      }
    }
  }

  static final _locks = <String, Future<void>>{};
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> get items => [
    for (final item in _items)
      Map.unmodifiable({
        ...item,
        'types': List<String>.unmodifiable(
          (item['types'] as List).cast<String>(),
        ),
      }),
  ];
  bool ready = false, working = false, _closed = false;
  String? message;
  void guard() {
    if (_closed) throw StateError('Outbox closed');
    requireCurrent();
  }

  Future<T> exclusive<T>(Future<T> Function() action) {
    final previous = _locks[scope] ?? Future<void>.value();
    final done = Completer<void>(), result = Completer<T>();
    _locks[scope] = done.future;
    () async {
      await previous;
      try {
        guard();
        result.complete(await action());
      } catch (e, s) {
        result.completeError(e, s);
      } finally {
        done.complete();
        if (identical(_locks[scope], done.future)) _locks.remove(scope);
      }
    }();
    return result.future;
  }

  Future<void> persist(List<Map<String, dynamic>> next) async {
    guard();
    try {
      await vault.write(
        jsonEncode({'version': 1, 'scope': scope, 'items': next}),
      );
    } catch (_) {
      ready = false;
      rethrow;
    }
    guard();
    _items = next;
    notifyListeners();
  }

  Future<void> initialize() async {
    try {
      await exclusive(() async {
        final raw = await vault.read();
        guard();
        if (raw != null) {
          final record = jsonDecode(raw) as Map<String, dynamic>;
          if (record['version'] != 1 || record['scope'] != scope) {
            throw const FormatException('Queue scope mismatch');
          }
          final rows = (record['items'] as List).cast<Map<String, dynamic>>(),
              ids = <String>{},
              ops = <String>{};
          for (final row in rows) {
            UuidValue(row['id'] as String);
            UuidValue(row['op'] as String);
            final types = (row['types'] as List).cast<String>();
            if (!ids.add(row['id'] as String) ||
                !ops.add(row['op'] as String) ||
                types.isEmpty ||
                types.toSet().length != types.length ||
                !types.every({'PIN_LIMIT', 'STORAGE_QUOTA'}.contains) ||
                !{'PENDING', 'BLOCKED'}.contains(row['state'])) {
              throw const FormatException('Invalid demand queue');
            }
          }
          _items = rows;
        } else {
          _items = [];
        }
        ready = true;
        notifyListeners();
      });
      await flush();
    } catch (_) {
      if (!_closed) {
        ready = false;
        message = '요청 기록을 확인하지 못했어요. 자동 초기화하지 않습니다.';
        notifyListeners();
      }
    }
  }

  Future<void> submit(Set<String> types) async {
    if (!ready || working) return;
    if (types.isEmpty ||
        !types.every({'PIN_LIMIT', 'STORAGE_QUOTA'}.contains)) {
      throw ArgumentError('Invalid demand types');
    }
    final sorted = types.toList()..sort();
    working = true;
    notifyListeners();
    try {
      await exclusive(() async {
        await persist([
          ..._items,
          {
            'id': UuidValue.random().value,
            'op': UuidValue.random().value,
            'types': sorted,
            'state': 'PENDING',
          },
        ]);
        message = '전송 대기';
        await drain();
      });
    } catch (_) {
      if (!_closed) message = '요청 저장·접수 결과를 확인하지 못했어요. 기록을 다시 읽은 뒤 이어갑니다.';
    } finally {
      if (!_closed) {
        working = false;
        notifyListeners();
      }
    }
  }

  Future<void> flush() async {
    if (!ready || working || _closed) return;
    working = true;
    notifyListeners();
    try {
      await exclusive(drain);
    } catch (_) {
      if (!_closed) message = '전송 대기 · 연결과 로그인 상태를 확인해 주세요.';
    } finally {
      if (!_closed) {
        working = false;
        notifyListeners();
      }
    }
  }

  Future<void> drain() async {
    for (final packet in List<Map<String, dynamic>>.of(
      _items,
    ).where((r) => r['state'] == 'PENDING')) {
      guard();
      try {
        final result = await send(
          Map.unmodifiable({
            'id': packet['id'],
            'types': List<String>.unmodifiable(
              (packet['types'] as List).cast<String>(),
            ),
          }),
          packet['op'] as String,
        );
        guard();
        if (result is! Map ||
            result['id'] != packet['id'] ||
            result['status'] != 'RECEIVED' ||
            result['revision'] != 1 ||
            result['types'] is! List ||
            !setEquals(
              (result['types'] as List).toSet(),
              (packet['types'] as List).toSet(),
            ) ||
            DateTime.tryParse(result['received_at'] as String? ?? '') == null) {
          throw const FormatException('Unverified demand receipt');
        }
        await persist(_items.where((p) => p['id'] != packet['id']).toList());
        message = '요청이 접수됐어요. 현재 보관 한도는 그대로 유지됩니다.';
      } catch (e) {
        guard();
        if (e is SettingsUnavailable &&
            e.status != null &&
            e.status! >= 400 &&
            e.status! < 500 &&
            !{401, 408, 429}.contains(e.status)) {
          await persist([
            for (final p in _items)
              if (p['id'] == packet['id'])
                {
                  ...p,
                  'state': 'BLOCKED',
                  'error': e.code ?? 'REQUEST_REJECTED',
                }
              else
                p,
          ]);
          message = e.code == 'STORAGE_REQUEST_EXPIRED'
              ? '요청 번호가 만료됐어요. 새로 제출해야 별도 요청으로 접수됩니다.'
              : '요청이 거절됐어요. 기존 번호와 선택은 유지합니다.';
        } else {
          message = '전송 대기 · 같은 요청 번호로 다시 전송합니다.';
          break;
        }
      }
    }
  }

  @override
  void dispose() {
    accountChanges?.removeListener(scopeChanged);
    _closed = true;
    super.dispose();
  }
}
