import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'backup_json.dart';
import 'export_data.dart';
import 'export_manifest.dart';
import 'export_zip.dart';

/// Private checkpoints contain sanitized business data, no credentials or URLs.
/// A corrupt/incomplete job is rejected; original audio and previous ZIP survive.
final class ExportJob {
  ExportJob({
    required this.owner,
    required this.id,
    required this.file,
    required this.requireCurrent,
    this.fileStates = const [],
  });
  final String owner, id;
  final ExportFile file;
  final void Function() requireCurrent;
  List<dynamic> fileStates;
  bool _saving = false;

  Future<void> _atomic(String name, List<int> bytes) async {
    requireCurrent();
    final part = await file('$name.part');
    await part.writeAsBytes(bytes, flush: true);
    requireCurrent();
    await part.rename((await file(name)).path);
  }

  Future<void> save(
    ExportData data,
    ExportManifest manifest, {
    ExportZip? zip,
    bool externallySaved = false,
  }) async {
    if (_saving) throw StateError('Checkpoint write already active');
    _saving = true;
    try {
      if (manifest.exportId != id ||
          manifest.sourceUserId != owner ||
          data.toJson()['export_id'] != id ||
          data.toJson()['source_user_id'] != owner ||
          data.metadataCount != manifest.metadataCount ||
          externallySaved && zip == null) {
        throw const FormatException('Checkpoint scope mismatch');
      }
      final dataBytes = utf8.encode(data.encode()),
          manifestBytes = utf8.encode(manifest.encode());
      if (zip != null &&
          (zip.dataHash != sha256.convert(dataBytes).toString() ||
              zip.manifestHash != sha256.convert(manifestBytes).toString())) {
        throw const FormatException('ZIP metadata mismatch');
      }
      await _atomic('data.json', dataBytes);
      await _atomic('manifest.json', manifestBytes);
      await _atomic(
        'checkpoint.json',
        utf8.encode(
          jsonEncode({
            'schema': 1,
            'owner': owner,
            'export_id': id,
            'data_sha256': sha256.convert(dataBytes).toString(),
            'manifest_sha256': sha256.convert(manifestBytes).toString(),
            'zip_sha256': zip?.checksum,
            'zip_size': zip?.size,
            'externally_saved': externallySaved,
            'file_states': fileStates
                .map(
                  (row) => {
                    for (final key in [
                      'recording_id',
                      'local_state',
                      'sha256',
                      'size_bytes',
                      'updated_at',
                    ])
                      if ((row as Map).containsKey(key)) key: row[key],
                  },
                )
                .toList(),
          }),
        ),
      );
    } finally {
      _saving = false;
    }
  }

  Future<
    ({
      ExportData data,
      ExportManifest manifest,
      ExportZip? zip,
      bool externallySaved,
    })
  >
  resume() async {
    requireCurrent();
    final checkpoint = decodeBackupJson(
      await (await file('checkpoint.json')).readAsString(),
    ) as Map;
    if (checkpoint['schema'] != 1 ||
        checkpoint['owner'] != owner ||
        checkpoint['export_id'] != id) {
      throw const FormatException('Checkpoint scope mismatch');
    }
    Future<String> verified(String name, Object? expected) async {
      final bytes = await (await file(name)).readAsBytes();
      requireCurrent();
      if (sha256.convert(bytes).toString() != expected) {
        throw const FormatException('Damaged export checkpoint');
      }
      return utf8.decode(bytes);
    }

    final data = ExportData.fromPrivateCheckpoint(
      await verified('data.json', checkpoint['data_sha256']),
    );
    final manifest = ExportManifest.decode(
      await verified('manifest.json', checkpoint['manifest_sha256']),
    );
    if (manifest.exportId != id ||
        manifest.sourceUserId != owner ||
        data.toJson()['export_id'] != id ||
        data.toJson()['source_user_id'] != owner ||
        data.metadataCount != manifest.metadataCount) {
      throw const FormatException('Checkpoint boundary mismatch');
    }
    for (final audio in manifest.files.where((f) => f.included)) {
      final source = await file(audio.relativePath!);
      if (await source.length() != audio.sizeBytes ||
          (await sha256.bind(source.openRead()).first).toString() !=
              audio.sha256) {
        throw const FormatException('Damaged staged audio');
      }
      requireCurrent();
    }
    ExportZip? zip;
    if (checkpoint['zip_sha256'] != null) {
      final source = await file('export.zip');
      if (await source.length() != checkpoint['zip_size'] ||
          (await sha256.bind(source.openRead()).first).toString() !=
              checkpoint['zip_sha256']) {
        throw const FormatException('Damaged export ZIP');
      }
      zip = ExportZip(
        source,
        await source.length(),
        checkpoint['zip_sha256'] as String,
        checkpoint['data_sha256'] as String,
        checkpoint['manifest_sha256'] as String,
      );
    }
    requireCurrent();
    fileStates = (checkpoint['file_states'] as List? ?? const []).map((row) {
      final map = Map<String, dynamic>.from(row as Map);
      if (map.keys.any(
        (key) => !{
          'recording_id',
          'local_state',
          'sha256',
          'size_bytes',
          'updated_at',
        }.contains(key),
      )) {
        throw const FormatException('Invalid private collection state');
      }
      return map;
    }).toList();
    return (
      data: data,
      manifest: manifest,
      zip: zip,
      externallySaved: checkpoint['externally_saved'] == true,
    );
  }
}
