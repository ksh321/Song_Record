import 'dart:convert';

import '../../features/auth/auth_session.dart';
import '../database/account_store.dart';
import '../database/local_models.dart';
import 'metadata_response.dart';
import 'mutation_request.dart';
import 'mutation_transport.dart';

/// One bounded pass; retry scheduling, rebasing and canonical mapping are later steps.
final class MetadataDispatcher {
  MetadataDispatcher(this.store, this.transport, this.session);
  final AccountStore store;
  final MutationTransport transport;
  final Future<AuthSession> Function() session;

  Future<int> dispatch({
    int limit = 50,
    void Function()? onAuthenticationBlocked,
  }) async {
    if (limit < 1 || limit > 500) throw ArgumentError('Invalid dispatch limit');
    var acknowledged = 0;
    for (var i = 0; i < limit; i++) {
      // Acquire credentials before claiming; an unavailable login does not consume an attempt.
      final auth = await session();
      store.requireActive();
      if (auth.userId != store.userId) {
        throw StateError('Session belongs to another account');
      }
      final request = await store.claimMutation();
      if (request == null) break;
      try {
        store.requireActive();
        final MutationResponse response;
        try {
          response = await transport.send(request, auth, store.requireActive);
        } on MutationBodyFailure catch (failure) {
          store.requireActive();
          await store.deferMutation(
            request,
            'RETRY',
            'RESPONSE_INVALID',
            status: failure.receivedStatus,
          );
          if (failure.receivedStatus == 401 || failure.receivedStatus == 403) {
            onAuthenticationBlocked?.call();
            break;
          }
          continue;
        } on MutationNetworkFailure catch (failure) {
          store.requireActive();
          final status = failure.receivedStatus;
          await store.deferMutation(
            request,
            'RETRY',
            status == null ? 'NETWORK_UNAVAILABLE' : 'RESPONSE_LOST',
            status: status,
          );
          if (status == 401 || status == 403) {
            onAuthenticationBlocked?.call();
            break;
          }
          continue;
        }
        store.requireActive();
        if (response.status == 200 || response.status == 201) {
          final snapshot = decodeMetadataSnapshot(request, response);
          if (snapshot['id'] != request.mutation.entityId) {
            await store.deferMutation(
              request,
              'CONFLICT',
              'CANONICAL_MAPPING_REQUIRED',
              status: response.status,
              serverSnapshot: snapshot,
            );
          } else if (request.mutation.operation == LocalOperation.create &&
              response.status == 200) {
            await store.deferMutation(
              request,
              'CONFLICT',
              'EXISTING_RESOURCE_REVIEW_REQUIRED',
              status: response.status,
              serverSnapshot: snapshot,
            );
          } else if (await store.acknowledgeMutation(request, snapshot)) {
            acknowledged++;
          }
        } else {
          final state = response.status == 409
              ? 'CONFLICT'
              : {400, 404, 405, 413, 422}.contains(response.status)
              ? 'FAILED'
              : 'RETRY';
          var reason = 'HTTP_${response.status}';
          Map<String, Object?>? current;
          try {
            final envelope = jsonDecode(response.body);
            final error = envelope is Map ? envelope['error'] : null;
            if (error is Map &&
                error['code'] is String &&
                RegExp(r'^[A-Z0-9_]{1,64}$')
                    .hasMatch(error['code'] as String)) {
              reason = error['code'] as String;
              final details = error['details'];
              if (response.status == 409 &&
                  details is Map &&
                  details['current'] is Map) {
                final parsed = decodeMetadataSnapshot(
                  request,
                  MutationResponse(409, jsonEncode(details['current'])),
                  conflict: true,
                );
                if (parsed['revision'] == details['current_revision']) {
                  current = parsed;
                }
              }
            }
          } catch (_) {
            /* Keep status and local input even for a malformed error. */
          }
          await store.deferMutation(
            request,
            state,
            reason,
            status: response.status,
            serverSnapshot: current,
          );
          if (response.status == 401 || response.status == 403) {
            onAuthenticationBlocked?.call();
            break;
          }
        }
      } on FormatException {
        // Malformed wire data is retained without automatic retries. Database
        // and programming errors propagate with SENDING intact for recovery.
        store.requireActive();
        await store.deferMutation(request, 'RETRY', 'RESPONSE_UNCONFIRMED');
      }
    }
    return acknowledged;
  }
}
