import '../domain/identifiers.dart';

/// An account-lifetime UUID marker; never confused with an asset generation.
Map<String, dynamic> permanentDeletionPayload(
  Map<String, dynamic> ledger, {
  required String owner,
  required String entity,
  required String id,
}) {
  const fields = {
    'id',
    'user_id',
    'entity_type',
    'entity_id',
    'object_generation',
    'revision',
    'purged_at',
  };
  final revision = ledger['revision'], purged = ledger['purged_at'];
  bool uuid(Object? value) =>
      value is String && UuidValue(value).value == value;
  if (ledger.length != fields.length ||
      !ledger.keys.every(fields.contains) ||
      !uuid(ledger['id']) ||
      !uuid(owner) ||
      !uuid(id) ||
      ledger['user_id'] != owner ||
      ledger['entity_id'] != id ||
      ledger['entity_type'] != entity ||
      ledger['object_generation'] != null ||
      !{'SONG', 'RECORDING', 'TAG'}.contains(entity) ||
      revision is! int ||
      revision < 1 ||
      revision > 9223372036854775807 ||
      purged is! String ||
      !RegExp(r'^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,3})?Z$')
          .hasMatch(purged)) {
    throw const FormatException('Invalid permanent deletion marker');
  }
  final date = DateTime.tryParse(purged);
  if (date == null ||
      date.year < 1000 ||
      date.toUtc().toIso8601String().substring(0, 19) !=
          purged.substring(0, 19)) {
    throw const FormatException('Invalid permanent deletion time');
  }
  return {
    'id': id,
    'entity_type': entity,
    'revision': revision,
    'status': 'DELETED',
    'deleted_at': purged,
  };
}
