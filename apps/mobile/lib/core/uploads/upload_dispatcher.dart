import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import '../../features/auth/auth_session.dart';
import '../database/account_store.dart';
import '../domain/identifiers.dart';
import 'upload_transport.dart';

final class UploadCancelled implements Exception {
  const UploadCancelled();
}

/// Bounded foreground transfer pass. PUT success awaits P12-06 verification, never marks an asset STORED.
final class UploadDispatcher {
  UploadDispatcher(
    this.store,
    this.transport,
    this.session, {
    DateTime Function()? clock,
  }) : clock = clock ?? DateTime.now;
  final AccountStore store;
  final UploadTransport transport;
  final Future<AuthSession> Function() session;
  final DateTime Function() clock;
  Future<DateTime?> nextAttempt() => store.nextUploadAt();
  Future<int> dispatch({
    int limit = 2,
    void Function()? onAuthenticationBlocked,
  }) async {
    if (limit < 1 || limit > 20) {
      throw ArgumentError('Invalid upload pass limit');
    }
    await store.discoverUploads();
    var uploaded = 0;
    for (var i = 0; i < limit; i++) {
      final auth = await session();
      store.requireActive();
      if (auth.userId != store.userId) {
        throw StateError('Upload account mismatch');
      }
      final work = await store.claimUpload();
      if (work == null) break;
      Future<void> guard() async {
        store.requireActive();
        if (!await store.uploadCurrent(work)) throw const UploadCancelled();
      }

      try {
        final bytes = await store.readLocalAudio(work.recordingId);
        await guard();
        if (bytes.length != work.size ||
            sha256.convert(bytes).toString() != work.sha256) {
          throw const FormatException('Local upload specification changed');
        }
        final response = work.attemptId == null
            ? await transport.authorize(work, auth, guard)
            : await transport.renew(work, auth, guard);
        await guard();
        if (response.status == 401 || response.status == 403) {
          await store.settleUpload(work, 'BLOCKED', 'AUTH');
          onAuthenticationBlocked?.call();
          break;
        }
        if (response.status != 200 && response.status != 201) {
          final retry = response.status >= 500;
          await store.settleUpload(
            work,
            retry ? 'RETRY' : 'BLOCKED',
            'HTTP_${response.status}',
            retry: retry,
          );
          continue;
        }
        final body = jsonDecode(response.body);
        if (body is! Map<String, dynamic>) {
          throw const FormatException('Invalid upload response');
        }
        if (body['state'] == 'STORED') {
          await store.settleUpload(work, 'STORED', null);
          continue;
        }
        final attempt = UuidValue(body['attempt_id'] as String).value;
        if (work.attemptId != null && work.attemptId != attempt) {
          throw const FormatException('Upload attempt changed');
        }
        final expiry = DateTime.parse(body['expires_at'] as String),
            deadline = DateTime.parse(body['attempt_expires_at'] as String);
        if (body['state'] != 'UPLOADING' || expiry.isAfter(deadline)) {
          throw const FormatException('Invalid upload lifetime');
        }
        final url = Uri.parse(body['put_url'] as String);
        final headers = <String, List<String>>{};
        for (final e in (body['headers'] as Map<String, dynamic>).entries) {
          headers[e.key] = (e.value as List).cast<String>();
        }
        if (!await store.saveUploadTicket(work, attempt)) {
          throw const UploadCancelled();
        }
        if (!expiry.isAfter(clock().toUtc())) {
          await store.settleUpload(work, 'RETRY', 'URL_EXPIRED', retry: true);
          continue;
        }
        final status = await transport.put(url, headers, bytes, guard);
        await guard();
        if (status >= 200 && status < 300) {
          await store.settleUpload(work, 'UPLOADED', null);
          uploaded++;
        } else {
          final retry = status == 403 || status >= 500;
          await store.settleUpload(
            work,
            retry ? 'RETRY' : 'BLOCKED',
            'PUT_$status',
            retry: retry,
          );
        }
      } on UploadCancelled {
        /* Cancellation already persisted; never remove original or metadata. */
      } on UploadNetworkFailure {
        await store.settleUpload(work, 'RETRY', 'NETWORK', retry: true);
      } on FileSystemException {
        await store.settleUpload(work, 'BLOCKED', 'FILE_MISSING');
      } on FormatException {
        await store.settleUpload(work, 'BLOCKED', 'INVALID_RESPONSE_OR_FILE');
      } on TypeError {
        await store.settleUpload(work, 'BLOCKED', 'INVALID_RESPONSE');
      } on StateError {
        store.requireActive();
        await store.settleUpload(work, 'BLOCKED', 'FILE_OR_STATE_CHANGED');
      }
    }
    return uploaded;
  }
}
