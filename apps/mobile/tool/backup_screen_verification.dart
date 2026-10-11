import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/sync/local_repository.dart';
import 'package:song_record/core/sync/snapshot_transport.dart';
import 'package:song_record/core/theme/app_theme.dart';
import 'package:song_record/features/backup/export/export_controller.dart';
import 'package:song_record/features/backup/export/export_screen.dart';
import 'package:song_record/features/recorder/recorder_gateway.dart';

// Native completed capture, real SQLite and official export screen; no personal
// account or synthetic server authentication. Offline mode is explicitly chosen.
const owner = '21212121-2121-4121-8121-212121212108';
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kDebugMode || appFlavor != 'searchVerification') {
    throw StateError('Verification only');
  }
  await const MethodChannel(
    'song_record/account',
  ).invokeMethod<void>('setAccount', {'userId': owner, 'environment': 'dev'});
  final manager = AccountStoreManager(environment: AppEnvironment.dev),
      store = await manager.openAccount(owner);
  final repository = LocalRepository(store);
  const recording = '21212121-2121-4121-8121-212121212118';
  if (!(await repository.pendingRecordings()).any(
        (row) => row['recording_id'] == recording,
      ) &&
      !await repository.hasRecordingMetadata(recording)) {
    final bytes = (await rootBundle.load(
      'assets/verification/playback-tone.m4a',
    )).buffer.asUint8List();
    await repository.importCompletedCapture(
      accountScope: 'dev/$owner',
      recordingId: recording,
      bytes: bytes,
      fileSpec: {
        'sha256': sha256.convert(bytes).toString(),
        'size_bytes': bytes.length,
        'duration_ms': 1000,
        'codec': 'AAC_LC',
        'sample_rate': 48000,
        'channels': 1,
        'capture_integrity': 'VALIDATED',
      },
      recordedAt: DateTime.now().toUtc(),
      timezoneId: 'Asia/Seoul',
      timezoneOffsetMinutes: 540,
    );
  }
  final controller = ExportController.forStore(
    store: store,
    recorder: const MethodChannelRecorderGateway(),
    transport: HttpSnapshotTransport(
      Uri.parse('http://127.0.0.1:8080'),
      allowLocalHttp: true,
    ),
    session: () async =>
        throw StateError('No server session in isolated verification'),
    base: Uri.parse('http://127.0.0.1:8080'),
    allowLocalHttp: true,
    requireCurrent: store.requireActive,
  );
  runApp(
    MaterialApp(
      theme: AppTheme.dark(),
      home: ExportScreen(controller: controller),
    ),
  );
}
