import '../../../core/database/account_store.dart';
import '../../../core/domain/identifiers.dart';
import '../../../core/sync/snapshot_response.dart';
import '../../../core/sync/snapshot_transport.dart';
import '../../../core/sync/wire_json.dart';
import '../../auth/auth_session.dart';
import '../export/export_manifest.dart';

final class ImportNotReady implements Exception {
  const ImportNotReady();
}

/// A fully verified server read view. It never applies untrusted ZIP data.
final class ImportServerBaseline {
  ImportServerBaseline._(this.owner, this.manifest, List<SnapshotEntry> entries)
    : entries = List.unmodifiable(entries);
  final String owner;
  final SnapshotManifest manifest;
  final List<SnapshotEntry> entries;
  @override
  String toString() => 'ImportServerBaseline[REDACTED]';
}

final class ImportPreflight {
  ImportPreflight({
    required this.store,
    required this.transport,
    required this.session,
    required this.requireCurrent,
    required this.clock,
  });
  final AccountStore store;
  final SnapshotTransport transport;
  final Future<AuthSession> Function() session;
  final void Function() requireCurrent;
  final DateTime Function() clock;

  Future<SnapshotHttpResponse> _send(SnapshotHttpRequest request) async {
    requireCurrent();
    store.requireActive();
    final authenticated = await session();
    requireCurrent();
    store.requireActive();
    if (authenticated.userId != store.userId) {
      throw StateError('Import account changed');
    }
    final result = await transport.send(request, authenticated, requireCurrent);
    requireCurrent();
    store.requireActive();
    return result;
  }

  Future<String> request(ExportManifest backup, String operationId) async {
    requireCurrent();
    store.requireActive();
    if (backup.sourceUserId != store.userId) {
      throw const FormatException('Import account mismatch');
    }
    final response = await _send(
      SnapshotHttpRequest.importPreflight(operationId, backup.sourceUserId),
    );
    if (response.status != 202) throw SnapshotTransportFailure(response.status);
    final value = decodeWireJson(response.body);
    if (value is! Map<String, dynamic> ||
        value.length != 4 ||
        value['status'] != 'BUILDING' ||
        value['snapshot_token'] is! String ||
        value['operation_id'] is! String) {
      throw const FormatException('Invalid import preflight response');
    }
    final token = UuidValue(value['snapshot_token'] as String).value;
    UuidValue(value['operation_id'] as String);
    if (value['status_url'] != '/v1/sync/snapshots/$token') {
      throw const FormatException('Invalid import status path');
    }
    return token;
  }

  Future<ImportServerBaseline> readReady(String token) async {
    final status = await _send(SnapshotHttpRequest.status(token));
    if (status.status == 202) throw const ImportNotReady();
    if (status.status != 200) throw SnapshotTransportFailure(status.status);
    final manifest = SnapshotManifest.decode(
      status.body,
      expectedToken: token,
      now: clock(),
    );
    final integrity = SnapshotIntegrity(manifest), entries = <SnapshotEntry>[];
    for (final entity in snapshotEntities) {
      String? cursor;
      var ordinal = 0;
      do {
        final response = await _send(
          SnapshotHttpRequest.page(token, entity, cursor: cursor),
        );
        if (response.status != 200) {
          throw SnapshotTransportFailure(response.status);
        }
        final page = SnapshotPage.decode(
          response.body,
          manifest: manifest,
          entity: entity,
          owner: store.userId,
          afterOrdinal: ordinal,
          now: clock(),
        );
        for (final entry in page.entries) {
          integrity.add(entry);
          entries.add(entry);
          ordinal = entry.ordinal;
        }
        cursor = page.nextCursor;
      } while (cursor != null);
    }
    integrity.finish(now: clock());
    requireCurrent();
    store.requireActive();
    return ImportServerBaseline._(store.userId, manifest, entries);
  }
}
