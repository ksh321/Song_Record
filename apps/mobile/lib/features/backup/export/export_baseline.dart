import 'dart:convert';

import '../../../core/database/account_store.dart';
import '../../../core/domain/identifiers.dart';
import '../../../core/sync/snapshot_response.dart';
import '../../../core/sync/snapshot_transport.dart';
import '../../../core/sync/wire_json.dart';
import '../../auth/auth_session.dart';

class ExportNotReady implements Exception {
  const ExportNotReady();
}

/// Frozen provenance. Later edits never enter an already captured baseline.
final class ExportBaseline {
  ExportBaseline({
    required this.id,
    required this.owner,
    required this.includeTrash,
    required this.manifest,
    required this.createdAt,
    required Map<String, Object?> local,
    required List<SnapshotEntry> entries,
  }) : _local = jsonEncode(local),
       entries = List.unmodifiable(entries) {
    UuidValue(id);
    UuidValue(owner);
    if (local['source_user_id'] != owner ||
        (manifest != null && manifest!.token != id)) {
      throw const FormatException('Export ownership or baseline mismatch');
    }
  }
  final String id, owner;
  final bool includeTrash;
  final SnapshotManifest? manifest;
  final DateTime createdAt;
  final String _local;
  final List<SnapshotEntry> entries;
  Map<String, dynamic> get local => jsonDecode(_local) as Map<String, dynamic>;
  bool get online => manifest != null;
  @override
  String toString() => 'ExportBaseline[REDACTED]';
}

final class ExportHandle {
  ExportHandle(String id, this.includeTrash) : id = UuidValue(id).value;
  final String id;
  final bool includeTrash;
  @override
  String toString() => 'ExportHandle[REDACTED]';
}

/// Reads the dedicated EXPORT snapshot without applying it to the sync DB.
final class ExportBaselineReader {
  ExportBaselineReader({
    required this.store,
    required this.transport,
    required this.session,
    required this.requireCurrent,
    DateTime Function()? clock,
  }) : clock = clock ?? (() => DateTime.now().toUtc());
  final AccountStore store;
  final SnapshotTransport transport;
  final Future<AuthSession> Function() session;
  final void Function() requireCurrent;
  final DateTime Function() clock;
  Future<SnapshotHttpResponse> send(SnapshotHttpRequest request) async {
    requireCurrent();
    final current = await session();
    requireCurrent();
    if (current.userId != store.userId) {
      throw const FormatException('Export account changed');
    }
    final result = await transport.send(request, current, requireCurrent);
    requireCurrent();
    return result;
  }

  Future<ExportHandle> request({
    required String operationId,
    required bool includeTrash,
  }) async {
    final response = await send(
      SnapshotHttpRequest.exportCreate(operationId, includeTrash),
    );
    if (response.status != 202) throw SnapshotTransportFailure(response.status);
    final value = decodeWireJson(response.body) as Map<String, dynamic>;
    if (value['status'] != 'BUILDING') {
      throw const FormatException('Invalid export submission');
    }
    final result = ExportHandle(value['export_id'] as String, includeTrash);
    UuidValue(value['operation_id'] as String);
    if (value['status_url'] != '/v1/exports/${result.id}/manifest') {
      throw const FormatException('Invalid export route');
    }
    return result;
  }

  Map<String, dynamic> unwrap(String body, ExportHandle handle) {
    final value = decodeWireJson(body) as Map<String, dynamic>;
    if (value.remove('export_id') != handle.id ||
        value.remove('source_user_id') != store.userId ||
        value.remove('include_trash') != handle.includeTrash) {
      throw const FormatException('Export provenance mismatch');
    }
    return value;
  }

  Future<ExportBaseline> freezeReady(ExportHandle handle) async {
    final status = await send(SnapshotHttpRequest.exportManifest(handle.id));
    if (status.status == 202) throw const ExportNotReady();
    if (status.status != 200) throw SnapshotTransportFailure(status.status);
    final manifest = SnapshotManifest.decode(
      jsonEncode(unwrap(status.body, handle)),
      expectedToken: handle.id,
      now: clock(),
    );
    final integrity = SnapshotIntegrity(manifest), entries = <SnapshotEntry>[];
    for (final entity in snapshotEntities) {
      String? cursor;
      var ordinal = 0;
      do {
        final response = await send(
          SnapshotHttpRequest.exportManifest(
            handle.id,
            entity: entity,
            cursor: cursor,
          ),
        );
        if (response.status != 200) {
          throw SnapshotTransportFailure(response.status);
        }
        final page = SnapshotPage.decode(
          jsonEncode(unwrap(response.body, handle)),
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
    final local = await store.captureExportLocal();
    requireCurrent();
    return ExportBaseline(
      id: handle.id,
      owner: store.userId,
      includeTrash: handle.includeTrash,
      manifest: manifest,
      createdAt: clock(),
      local: local,
      entries: entries,
    );
  }

  Future<ExportBaseline> offline({required bool includeTrash}) async {
    requireCurrent();
    final local = await store.captureExportLocal();
    requireCurrent();
    return ExportBaseline(
      id: UuidValue.random().value,
      owner: store.userId,
      includeTrash: includeTrash,
      manifest: null,
      createdAt: clock(),
      local: local,
      entries: const [],
    );
  }
}
