import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/audio/audio_player.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/database/local_models.dart';
import 'package:song_record/core/domain/identifiers.dart';
import 'package:song_record/core/sync/snapshot_transport.dart';
import 'package:song_record/core/theme/app_theme.dart';
import 'package:song_record/features/auth/auth_session.dart';
import 'package:song_record/features/backup/export/export_baseline.dart';
import 'package:song_record/features/backup/export/export_data.dart';
import 'package:song_record/features/backup/export/export_manifest.dart';
import 'package:song_record/features/backup/export/export_zip.dart';
import 'package:song_record/features/backup/import/import_candidates.dart';
import 'package:song_record/features/backup/import/import_conflicts.dart';
import 'package:song_record/features/backup/import/import_decision.dart';
import 'package:song_record/features/backup/import/import_identity.dart';
import 'package:song_record/features/backup/import/import_outcome.dart';
import 'package:song_record/features/backup/import/import_preflight.dart';
import 'package:song_record/features/backup/import/import_roles.dart';
import 'package:song_record/features/backup/import/import_validation.dart';
import 'package:song_record/features/backup/import/import_zip.dart';

import 'import_validation_verification.dart' as audio;
import 'p22_fixture.dart';

String id(int n) => '00000000-0000-4000-8000-${n.toString().padLeft(12, '0')}';
const owner = '11111111-1111-4111-8111-111111111111';

class FixtureTransport implements SnapshotTransport {
  FixtureTransport() {
    final ready = DateTime.fromMillisecondsSinceEpoch(
      DateTime.now().millisecondsSinceEpoch,
      isUtc: true,
    );
    // Keep exact protocol lifetime, independent of build/installation delay.
    final stamp = ready.toIso8601String();
    final expiry = ready.add(const Duration(minutes: 30)).toIso8601String();
    fixture['manifest']['captured_at'] = stamp;
    fixture['manifest']['ready_at'] = stamp;
    fixture['manifest']['expires_at'] = expiry;
    for (final page in fixture['pages'] as List) {
      page['expires_at'] = expiry;
    }
  }

  final fixture = jsonDecode(p22Fixture) as Map<String, dynamic>;
  void replace(String entity, List<Map<String, dynamic>> values) {
    final page = (fixture['pages'] as List).singleWhere(
      (dynamic p) => p['entity'] == entity,
    );
    page['entries'] = [
      for (var i = 0; i < values.length; i++)
        {
          'ordinal': i + 1,
          'resource_id': values[i]['id'],
          'payload': values[i],
          'canonical_payload': canonicalJson(values[i]),
        },
    ];
    fixture['manifest']['entity_counts'][entity] = values.length;
    final bytes = BytesBuilder();
    void number(int value, int size) {
      final b = ByteData(size);
      if (size == 8) {
        b.setInt64(0, value);
      } else {
        b.setInt32(0, value);
      }
      bytes.add(b.buffer.asUint8List());
    }

    bytes.add(ascii.encode('SongRecord:snapshot-manifest:1'));
    number(fixture['manifest']['snapshot_cursor'] as int, 8);
    for (final p in fixture['pages'] as List) {
      for (final e in p['entries'] as List) {
        final n = ascii.encode(p['entity'] as String),
            raw = utf8.encode(e['canonical_payload'] as String);
        number(n.length, 4);
        bytes.add(n);
        number(e['ordinal'] as int, 8);
        bytes.add(UuidValue(e['resource_id'] as String).bytes);
        number(raw.length, 4);
        bytes.add(raw);
      }
    }
    fixture['manifest']['manifest_hash'] = sha256
        .convert(bytes.takeBytes())
        .toString();
  }

  @override
  Future<SnapshotHttpResponse> send(
    SnapshotHttpRequest r,
    AuthSession s,
    void Function() guard,
  ) async {
    guard();
    if (s.userId != owner) throw StateError('owner');
    final entity = r.query['entity'];
    return SnapshotHttpResponse(
      200,
      jsonEncode(
        entity == null
            ? fixture['manifest']
            : (fixture['pages'] as List).singleWhere(
                (dynamic p) => p['entity'] == entity,
              ),
      ),
    );
  }
}

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(MaterialApp(theme: AppTheme.dark(), home: const TransferCheck()));
}

class TransferCheck extends StatefulWidget {
  const TransferCheck({super.key});
  @override
  State<TransferCheck> createState() => _State();
}

class _State extends State<TransferCheck> {
  String status = '합성 계정 · 실제 서비스 로그인 아님';
  bool busy = false;
  void show(String s) {
    if (mounted) setState(() => status = s);
  }

  Future<void> source() async {
    setState(() => busy = true);
    try {
      final cache = await getTemporaryDirectory(),
          support = await getApplicationSupportDirectory();
      final folder = await cache.createTemp('p22-source-');
      Future<File> file(String name) async {
        final f = File('${folder.path}/$name');
        await f.parent.create(recursive: true);
        return f;
      }

      final bytes = base64Decode(audio.tone),
          tone = await file('audio/${id(1002)}.m4a');
      await tone.writeAsBytes(bytes, flush: true);
      final actual = await AndroidImportAudioProbe().inspect(tone);
      final spec = {
        'sha256': sha256.convert(bytes).toString(),
        'size_bytes': bytes.length,
        'duration_ms': actual['duration_ms'],
        'codec': 'AAC_LC',
        'sample_rate': 48000,
        'channels': 1,
        'capture_integrity': 'VALIDATED',
      };
      final song = {
        'id': id(1001),
        'source_type': 'MANUAL',
        'tj_number': null,
        'title': '이전 기기 곡',
        'artist': '합성 가수',
        'version_code': 'LIVE',
        'note': '옮길 메모',
        'lifecycle_state': 'ACTIVE',
      };
      final recording = {
        'id': id(1002),
        'song_id': id(1001),
        'metadata_state': 'SAVED',
        'title_snapshot': '당시 제목',
        'artist_snapshot': '당시 가수',
        'version_code': 'LIVE',
        'key_mode': 'MALE',
        'key_shift': 2,
        'note': '녹음 메모',
        'tier': 'A',
        'recorded_at': '2026-10-12T00:00:00.000Z',
        'timezone_id': 'Asia/Seoul',
        'timezone_offset_minutes': 540,
        'lifecycle_state': 'ACTIVE',
        'file': spec,
      };
      final rows = [
        {'entity': 'SONG', 'payload': song},
        {'entity': 'RECORDING', 'payload': recording},
        {
          'entity': 'RECORDING',
          'payload': {
            ...recording,
            'id': id(1006),
            'title_snapshot': '파일 없는 녹음',
            'note': '정보만 복원',
          },
        },
        {
          'entity': 'PLAYLIST',
          'payload': {'id': id(1003), 'name': '이전 목록'},
        },
      ];
      final now = DateTime.now().toUtc();
      final baseline = ExportBaseline(
        id: id(1101),
        owner: owner,
        includeTrash: false,
        manifest: null,
        createdAt: now,
        entries: const [],
        local: {
          'source_user_id': owner,
          'local_cutoff_at': now.toIso8601String(),
          'baseline': [
            {
              'baseline_complete': 0,
              'last_change_seq': null,
              'updated_at': null,
            },
          ],
          'copies': [
            for (final r in rows)
              {
                'entity_type': r['entity'],
                'entity_id': (r['payload'] as Map)['id'],
                'server_revision': 0,
                'tombstone': 0,
                'server_payload': null,
                'local_payload': jsonEncode(r['payload']),
              },
          ],
          'changes': <Object?>[],
          'recording_inputs': <Object?>[],
        },
      );
      final data = ExportData.fromBaseline(baseline),
          manifest = ExportManifest.fromBaseline(
            baseline,
            metadataCount: data.metadataCount,
            files: [
              ExportAudioEntry(
                recordingId: id(1002),
                selected: true,
                included: true,
                missingReason: null,
                sha256: spec['sha256'] as String,
                sizeBytes: bytes.length,
                durationMs: spec['duration_ms'] as int,
              ),
              ExportAudioEntry(
                recordingId: id(1006),
                selected: true,
                included: false,
                missingReason: ExportMissingReason.fileNotOnDevice,
                sha256: null,
                sizeBytes: null,
                durationMs: null,
              ),
            ],
          );
      final zip = await ExportZipWriter(
        file: file,
        requireCurrent: () {},
      ).write(data, manifest);
      await zip.file.copy('${support.path}/p22-transfer.zip');
      show('SOURCE_READY · 정보4 · 실제 AAC1 · 누락1 · 합성 ZIP 생성');
    } catch (e) {
      show('SOURCE_FAIL ${e.runtimeType}: $e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> target() async {
    setState(() => busy = true);
    final manager = AccountStoreManager(environment: AppEnvironment.dev);
    ImportDecision? decision;
    try {
      final support = await getApplicationSupportDirectory(),
          cache = await getTemporaryDirectory();
      final archive = File('${support.path}/p22-inbound.zip');
      final staged = await ImportZipReader(
        requireCurrent: () {},
        availableBytes: () async => 1000000000,
      ).unpack(archive, cache);
      decision = ImportDecision(
        requireCurrent: () {},
        validate: (guard) => ImportValidator(
          owner: owner,
          requireCurrent: guard,
          audio: AndroidImportAudioProbe(),
        ).verify(staged),
      );
      await decision.check();
      if (!decision.canApproveWhole) {
        if (decision.source == null) {
          await ImportValidator(
            owner: owner,
            requireCurrent: () {},
            audio: AndroidImportAudioProbe(),
          ).verify(staged);
        }
        throw StateError(
          'validation ${decision.phase.name}: ${decision.source?.issues.map((e) => e.code).join(',')}',
        );
      }
      final consent = decision.approveWhole();
      var store = await manager.openAccount(owner);
      final transport = FixtureTransport();
      Future<ImportServerBaseline> current() => ImportPreflight(
        store: store,
        transport: transport,
        session: () async => AuthSession(
          userId: owner,
          deviceId: id(1200),
          accessToken: 'synthetic',
          refreshToken: 'synthetic',
          accessExpiresAt: DateTime.now().add(const Duration(hours: 1)),
          refreshExpiresAt: DateTime.now().add(const Duration(days: 1)),
        ),
        requireCurrent: () {},
        clock: DateTime.now,
      ).readReady(transport.fixture['manifest']['snapshot_token'] as String);
      final remote = await current();
      final identities = planImportIdentities(
        consent: consent,
        server: remote,
        requireCurrent: () {},
      );
      final candidates = planImportCandidates(
        identities,
        requireCurrent: () {},
      );
      final preview = await previewImportConflicts(
        consent: consent,
        candidates: candidates,
        server: remote,
        store: store,
        requireCurrent: () {},
      );
      final roles = planImportRoles(
        consent: consent,
        preview: preview,
        server: remote,
        requireCurrent: () {},
      );
      if (preview.requiresChoice ||
          identities.blocked.isNotEmpty ||
          identities.held.isNotEmpty) {
        throw StateError('unexpected hold');
      }
      final jobs = <Map<String, dynamic>>[];
      for (final r in roles.records) {
        final p = Map<String, dynamic>.from(r['payload'] as Map),
            entity = r['entity'] as String,
            rid = r['resource_id'] as String;
        final operation = id(20000 + int.parse(rid.split('-').last));
        Map<String, dynamic> edit(
          String op,
          String mode,
          int revision,
          Map<String, dynamic> draft,
          Map<String, dynamic> changes, {
          String? predecessor,
        }) => {
          'entity': entity,
          'id': rid,
          'op_id': op,
          'operation': mode,
          'base_revision': revision,
          'draft': draft,
          'changes': changes,
          'predecessor': ?predecessor,
        };
        final edits = <Map<String, dynamic>>[];
        if (entity == 'SONG') {
          edits.add(
            edit(operation, 'CREATE', 0, p, {
              for (final k in [
                'id',
                'source_type',
                'title',
                'artist',
                'version_code',
                'note',
              ])
                k: p[k],
              'manual_reason': 'TJ_NOT_FOUND',
            }),
          );
        } else if (entity == 'PLAYLIST') {
          edits.add(
            edit(operation, 'CREATE', 0, p, {'id': rid, 'name': p['name']}),
          );
        } else if (entity == 'RECORDING') {
          final draft = {...p, 'metadata_state': 'DRAFT'};
          edits.add(
            edit(operation, 'CREATE', 0, draft, {
              for (final k in [
                'id',
                'song_id',
                'title_snapshot',
                'artist_snapshot',
                'version_code',
                'key_mode',
                'key_shift',
                'note',
                'recorded_at',
                'timezone_id',
                'timezone_offset_minutes',
              ])
                k: p[k],
              'metadata_state': 'DRAFT',
            }),
          );
          edits.add(
            edit(id(40000 + int.parse(rid.split('-').last)), 'PATCH', 0, p, {
              'base_revision': 0,
              'metadata_state': 'SAVED',
              'file': p['file'],
              for (final k in [
                'title_snapshot',
                'artist_snapshot',
                'version_code',
                'key_mode',
                'key_shift',
                'note',
              ])
                k: p[k],
            }, predecessor: operation),
          );
          edits.add(
            edit(id(50000 + int.parse(rid.split('-').last)), 'PATCH', 0, p, {
              'base_revision': 0,
              'tier': p['tier'],
            }, predecessor: id(40000 + int.parse(rid.split('-').last))),
          );
        } else {
          throw StateError('unsupported row');
        }
        final kind = LocalEntity.values.singleWhere((e) => e.code == entity);
        if (await store.readMetadata(kind, rid) != null) edits.clear();
        jobs.add({
          'resource_id': rid,
          'edits': edits,
          'file': entity == 'RECORDING' && preview.fileIds.contains(rid)
              ? p['file']
              : null,
        });
      }
      final job = consent.source.manifest.exportId;
      final stage = await store.privateExportFile(job, 'audio/${id(1002)}.m4a');
      if (!await stage.exists()) {
        await consent.source.staging
            .file('audio/${id(1002)}.m4a')
            .copy(stage.path);
      }
      final sourceDigest = (await sha256.bind(archive.openRead()).first)
          .toString();
      if (!await store.importJobMatches(job, sourceDigest)) {
        await store.prepareImportApply(
          jobId: job,
          manifestHash: sourceDigest,
          items: jobs,
        );
      }
      bool interrupted = false;
      try {
        while (await store.applyImportNext(
          job,
          () {},
          faultProbe: (phase) async {
            if (phase == 'FILE_VERIFIED' && !interrupted) {
              interrupted = true;
              throw StateError('planned interruption');
            }
          },
        )) {}
      } on StateError {
        if (!interrupted) rethrow;
      }
      await manager.logout();
      store = await manager.openAccount(owner);
      while (await store.applyImportNext(job, () {})) {}
      final before = (await store.pendingMutations()).length;
      if (!await store.importJobMatches(job, sourceDigest)) {
        throw StateError('source changed');
      }
      if (await store.applyImportNext(job, () {}) ||
          (await store.pendingMutations()).length != before) {
        throw StateError('duplicate');
      }
      final restored = await store.readMetadata(
        LocalEntity.recording,
        id(1002),
      );
      final value = jsonDecode(restored!.localJson!) as Map;
      if (value['version_code'] != 'LIVE' ||
          value['key_shift'] != 2 ||
          value['note'] != '녹음 메모' ||
          value['tier'] != 'A' ||
          value['metadata_state'] != 'SAVED' ||
          value['title_snapshot'] != '당시 제목' ||
          value['artist_snapshot'] != '당시 가수' ||
          value['timezone_id'] != 'Asia/Seoul' ||
          value['timezone_offset_minutes'] != 540) {
        throw StateError('information lost');
      }
      final list = await store.readMetadata(LocalEntity.playlist, id(1003));
      if (jsonDecode(list!.localJson!)['name'] != '이전 목록' ||
          await store.findPlayableLocalAudio(id(1006)) != null) {
        throw StateError('playlist or missing-file state');
      }
      final report = await readImportOutcome(
        store: store,
        consent: consent,
        jobId: job,
        plannedRecords: roles.records,
        held: 0,
        conflicts: 0,
        refreshPolicy: current,
        requireCurrent: () {},
      );
      if (report.information != 4 ||
          report.files != 1 ||
          report.missingFiles != 1 ||
          report.complete ||
          report.uploadCandidates.isNotEmpty) {
        throw StateError('counts');
      }
      // Actual Android runtime checks use synthetic server rows; none apply DB writes.
      Future<ImportConsent> variant(Map<String, dynamic> data) async {
        final manifest = ExportManifest.decode(
          jsonEncode({
            ...consent.source.manifest.toJson(),
            'metadata_count': (data['records'] as List).length,
          }),
        );
        final d = ImportDecision(
          requireCurrent: () {},
          validate: (_) async => ValidatedImport(
            staged,
            manifest,
            ImportData.decode(jsonEncode(data), manifest),
            const [],
          ),
        );
        try {
          await d.check();
          return d.approveWhole();
        } finally {
          d.dispose();
        }
      }

      final tj = consent.source.data.toJson();
      for (final r in tj['records'] as List) {
        if (r['entity'] == 'SONG') {
          r['payload']['source_type'] = 'TJ';
          r['payload']['tj_number'] = '00123';
        }
      }
      for (final r in tj['local_copies'] as List) {
        if (r['entity'] == 'SONG') {
          r['local']['source_type'] = 'TJ';
          r['local']['tj_number'] = '00123';
        }
      }
      final tjConsent = await variant(tj);
      for (final life in ['ACTIVE', 'TRASHED', 'PURGE_PENDING']) {
        transport.replace('SONG', [
          {
            'id': id(2001),
            'user_id': owner,
            'source_type': 'TJ',
            'tj_number': '00123',
            'lifecycle_state': life,
            'revision': 2,
            'note': '최신 서버 메모',
            'version_code': 'NORMAL',
          },
        ]);
        final mapped = planImportIdentities(
          consent: tjConsent,
          server: await current(),
          requireCurrent: () {},
        );
        if (life == 'ACTIVE') {
          final r = mapped.records.singleWhere(
            (r) => r['entity'] == 'RECORDING' && r['resource_id'] == id(1002),
          );
          if (mapped.songIds[id(1001)] != id(2001) ||
              (r['payload'] as Map)['song_id'] != id(2001) ||
              (r['payload'] as Map)['version_code'] != 'LIVE' ||
              (r['payload'] as Map)['note'] != '녹음 메모') {
            throw StateError('TJ mapping');
          }
        } else if (!mapped.held.any((r) => r.entity == 'SONG')) {
          throw StateError('lifecycle hold');
        }
      }
      transport.replace('SONG', [
        {
          'id': id(2001),
          'user_id': owner,
          'source_type': 'TJ',
          'tj_number': '00123',
          'lifecycle_state': 'ACTIVE',
          'revision': 2,
        },
      ]);
      transport.replace('DELETION_LEDGER', [
        {
          'id': id(3001),
          'user_id': owner,
          'entity_type': 'SONG',
          'entity_id': id(1001),
          'revision': 3,
        },
      ]);
      final deleted = planImportIdentities(
        consent: tjConsent,
        server: await current(),
        requireCurrent: () {},
      );
      if (!deleted.blocked.any((r) => r.id == id(1001)) ||
          deleted.songIds.containsKey(id(1001))) {
        throw StateError('deletion first');
      }
      transport.replace('SONG', []);
      transport.replace('DELETION_LEDGER', []);
      final ky = consent.source.data.toJson();
      for (final brand in ['KY', 'TJ']) {
        final key = id(brand == 'KY' ? 1801 : 1802),
            payload = {
              'id': key,
              'playlist_id': id(1003),
              'song_id': null,
              'candidate_brand': brand,
              'candidate_number': '00123',
              'candidate_snapshot': {
                'brand': brand,
                'number': '00123',
                'title': '합성 후보',
                'artist': '합성 가수',
              },
            };
        (ky['records'] as List).add({
          'entity': 'PLAYLIST_ITEM',
          'resource_id': key,
          'tombstone': false,
          'payload': payload,
        });
        (ky['local_copies'] as List).add({
          'entity': 'PLAYLIST_ITEM',
          'resource_id': key,
          'server_revision': 0,
          'tombstone': false,
          'server': null,
          'local': payload,
        });
      }
      final kyConsent = await variant(ky);
      final kyPlan = planImportCandidates(
        planImportIdentities(
          consent: kyConsent,
          server: await current(),
          requireCurrent: () {},
        ),
        requireCurrent: () {},
      );
      if (kyPlan.held.length != 1 ||
          kyPlan.held.single.itemId != id(1801) ||
          !kyPlan.records.any((r) => r['resource_id'] == id(1802)) ||
          kyPlan.fileIds.length != 1) {
        throw StateError('KY isolation');
      }
      bool ownerRejected = false;
      try {
        await ImportValidator(
          owner: id(9999),
          requireCurrent: () {},
          audio: AndroidImportAudioProbe(),
        ).verify(staged);
      } on FormatException {
        ownerRejected = true;
      }
      if (!ownerRejected) throw StateError('owner mismatch');
      final badParent = await cache.createTemp('p22-bad-owned-'),
          bad = File('${badParent.path}/bad.zip');
      final bytes = List<int>.from(await archive.readAsBytes()),
          needle = ascii.encode('recordings.csv'),
          escape = ascii.encode('../escapes.txt');
      if (needle.length != escape.length) throw StateError('fixture path');
      for (var i = 0; i <= bytes.length - needle.length; i++) {
        if (List.generate(
          needle.length,
          (j) => bytes[i + j] == needle[j],
        ).every((b) => b)) {
          bytes.setRange(i, i + needle.length, escape);
        }
      }
      await bad.writeAsBytes(bytes);
      bool pathRejected = false;
      try {
        await ImportZipReader(
          requireCurrent: () {},
          availableBytes: () async => 1000000000,
        ).unpack(bad, badParent);
      } on ImportZipFailure {
        pathRejected = true;
      }
      if (!pathRejected ||
          await File('${badParent.path}/escapes.txt').exists()) {
        throw StateError('traversal');
      }
      await const MethodChannel('song_record/account').invokeMethod<void>(
        'setAccount',
        {'userId': owner, 'environment': 'dev'},
      );
      final local = await store.findPlayableLocalAudio(id(1002));
      if (local == null) throw StateError('local');
      final player = AndroidAudioPlayer(), completed = Completer<void>();
      final subscription = player.events.listen((e) {
        if (e.phase == PlaybackPhase.completed && !completed.isCompleted) {
          completed.complete();
        }
      });
      try {
        final duration = await player.load({
          'token': 1,
          'userId': owner,
          'environment': 'dev',
          'recordingId': id(1002),
          'kind': 'local',
          'path': local.path,
          'size': local.size,
          'sha256': local.checksum,
        });
        if (duration < 1) throw StateError('duration');
        await player.play(1);
        await completed.future.timeout(const Duration(seconds: 12));
      } finally {
        await player.stop();
        await subscription.cancel();
      }
      show(
        'TARGET_PASS · 정보4 · 파일1 · 누락1 (전체 복원 완료 아님) · LIVE/키/메모/티어 · 중단재개 · 재가져오기 · 실제 재생 · TJ/삭제우선/KY/계정/경로 검사\n합성 계정/빈 서버 정책. 실제 서비스 로그인·목록 항목·두 물리 기기 검증은 포함하지 않음',
      );
    } catch (e) {
      show('TARGET_FAIL ${e.runtimeType}: $e');
    } finally {
      decision?.dispose();
      await manager.logout();
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext c) => Scaffold(
    appBar: AppBar(title: const Text('P22 폰 → 새 에뮬레이터')),
    body: SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(status),
          FilledButton(
            onPressed: busy ? null : source,
            child: const Text('백업 만들기 (폰)'),
          ),
          FilledButton(
            onPressed: busy ? null : target,
            child: const Text('옮긴 ZIP 복원'),
          ),
        ],
      ),
    ),
  );
}
