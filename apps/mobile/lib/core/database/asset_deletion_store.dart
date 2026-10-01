import 'dart:convert';

import '../domain/identifiers.dart';
import 'account_database.dart';
import 'local_models.dart';

/// Durable generation proofs in the existing DELETION_LEDGER copy namespace.
/// The key is the globally unique generation, not the recording or ledger UUID.
/// Caller owns the account transaction and never deletes any local file.
final class AssetDeletionStore {
  AssetDeletionStore(this.db, this.requireActive, this.clock);
  final AccountDatabase db;
  final void Function() requireActive;
  final DateTime Function() clock;
  final Map<String, Map<String, dynamic>> _markers = {};

  Map<String, dynamic> parse(
    Map<String, dynamic> value, {
    required String recordingId,
    required int revision,
  }) {
    const fields = {
      'recording_id',
      'generation',
      'cloud_revision',
      'purged_at',
    };
    bool uuid(Object? v) => v is String && UuidValue(v).value == v;
    final time = value['purged_at'];
    if (value.length != fields.length ||
        !value.keys.every(fields.contains) ||
        !uuid(recordingId) ||
        value['recording_id'] != recordingId ||
        !uuid(value['generation']) ||
        value['generation'] == '00000000-0000-0000-0000-000000000000' ||
        revision < 1 ||
        revision > 9223372036854775807 ||
        value['cloud_revision'] is! int ||
        value['cloud_revision'] != revision ||
        time is! String ||
        !RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,3})?Z$')
            .hasMatch(time)) {
      throw const FormatException('Invalid asset deletion proof');
    }
    final parsed = DateTime.tryParse(time);
    if (parsed == null ||
        parsed.year < 1000 ||
        parsed.toUtc().toIso8601String().substring(0, 19) !=
            time.substring(0, 19)) {
      throw const FormatException('Invalid asset deletion time');
    }
    return {...value, 'purged_at': parsed.toUtc().toIso8601String()};
  }

  Map<String, dynamic> fromLedger(Map<String, dynamic> value) {
    const fields = {
      'id',
      'user_id',
      'entity_type',
      'entity_id',
      'object_generation',
      'revision',
      'purged_at',
    };
    if (value.length != fields.length ||
        !value.keys.every(fields.contains) ||
        value['id'] is! String ||
        UuidValue(value['id'] as String).value != value['id'] ||
        value['user_id'] != db.userId ||
        value['entity_type'] != 'RECORDING_ASSET' ||
        value['entity_id'] is! String ||
        value['revision'] is! int) {
      throw const FormatException('Invalid asset deletion ledger');
    }
    return parse(
      {
        'recording_id': value['entity_id'],
        'generation': value['object_generation'],
        'cloud_revision': value['revision'],
        'purged_at': value['purged_at'],
      },
      recordingId: value['entity_id'] as String,
      revision: value['revision'] as int,
    );
  }

  Future<void> load() async {
    final rows = await db
        .customSelect(
          "SELECT * FROM metadata_copies WHERE entity_type='DELETION_LEDGER'",
        )
        .get();
    for (final row in rows) {
      requireActive();
      final value = jsonDecode(row.read<String>('server_payload'));
      if (value is! Map<String, dynamic> ||
          value['recording_id'] is! String ||
          row.read<String>('user_id') != db.userId ||
          row.read<int>('tombstone') != 1) {
        throw const FormatException('Invalid retained asset deletion');
      }
      final proof = parse(
        value,
        recordingId: value['recording_id'] as String,
        revision: row.read<int>('server_revision'),
      );
      if (row.read<String>('entity_id') != proof['generation']) {
        throw const FormatException('Asset deletion generation changed');
      }
      _markers[proof['generation'] as String] = proof;
    }
  }

  Future<void> remember(Map<String, dynamic> proof) async {
    requireActive();
    final generation = proof['generation'] as String;
    final existing = _markers[generation];
    if (existing != null) {
      if (canonicalJson(existing) != canonicalJson(proof)) {
        throw StateError('Conflicting generation deletion proof');
      }
      return;
    }
    await db.customStatement(
      '''
      INSERT INTO metadata_copies(user_id,entity_type,entity_id,server_revision,
        server_payload,local_payload,tombstone,updated_at)
      VALUES(?,'DELETION_LEDGER',?,?,?,NULL,1,?)
    ''',
      [
        db.userId,
        generation,
        proof['cloud_revision'],
        canonicalJson(proof),
        clock().toUtc().millisecondsSinceEpoch,
      ],
    );
    _markers[generation] = proof;
    requireActive();
  }

  Map<String, dynamic> suppress(Map<String, dynamic> asset) {
    final proof = _markers[asset['generation']];
    if (proof == null) return asset;
    if (proof['recording_id'] != asset['recording_id'] ||
        (asset['cloud_revision'] as int) > (proof['cloud_revision'] as int)) {
      throw StateError('Deleted generation reappeared');
    }
    return {
      ...asset,
      'cloud_state': 'NONE',
      'blocked_reason': null,
      'generation': null,
      'verified_size': null,
      'sha256': null,
      'stored_at': null,
      'cloud_revision': proof['cloud_revision'],
      'revision': proof['cloud_revision'],
      'updated_at': proof['purged_at'],
    };
  }
}
