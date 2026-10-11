import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/sync/local_repository.dart';
import 'package:song_record/core/theme/app_theme.dart';
import 'package:song_record/features/playlists/playlist_library.dart';
import 'package:song_record/features/playlists/playlist_library_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kDebugMode || appFlavor != 'searchVerification') {
    throw StateError('Isolated verification only');
  }
  const owner = '00000000-0000-4000-8000-000000001901';
  await const MethodChannel(
    'song_record/account',
  ).invokeMethod<void>('setAccount', {'userId': owner, 'environment': 'dev'});
  final manager = AccountStoreManager(environment: AppEnvironment.dev);
  final repository = LocalRepository(await manager.openAccount(owner));
  runApp(
    MaterialApp(
      theme: AppTheme.dark(),
      home: PlaylistLibraryScreen(library: PlaylistLibrary(repository)),
    ),
  );
}
