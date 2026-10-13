import 'identifiers.dart';

/// Created after a verified, same-server device proof or protected receipt query.
/// A generic 401, timeout, missing file or user-supplied UUID is not confirmation.
final class AccountDeletionConfirmation {
  AccountDeletionConfirmation._(this.userId, this.origin);
  final String userId;
  final String origin;
  factory AccountDeletionConfirmation.device(
    String userId,
    Uri server,
    Map<String, dynamic> reply,
  ) {
    if (reply.length != 1 || reply['deletion_confirmed'] != true) {
      throw const FormatException('Deletion was not confirmed');
    }
    return AccountDeletionConfirmation._(
      UuidValue(userId).value,
      server.origin,
    );
  }
  factory AccountDeletionConfirmation.receipt(
    String userId,
    Uri server,
    String verifiedState,
  ) {
    if (!{
      'ACCEPTED',
      'DELETING',
      'BACKUP_CLEANUP',
      'COMPLETED',
    }.contains(verifiedState)) {
      throw const FormatException('Deletion was not accepted');
    }
    return AccountDeletionConfirmation._(
      UuidValue(userId).value,
      server.origin,
    );
  }
}
