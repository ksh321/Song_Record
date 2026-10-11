import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:song_record/config/app_config.dart';
import 'package:song_record/core/database/account_store.dart';
import 'package:song_record/core/sync/local_repository.dart';
import 'package:song_record/core/theme/app_theme.dart';
import 'package:song_record/features/playlists/playlist_library.dart';
import 'package:song_record/features/playlists/playlist_library_screen.dart';

import 'playlist_addition_fixture.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kDebugMode || appFlavor != 'searchVerification') {
    throw StateError('Isolated verification only');
  }
  final owner = playlistFixtureId(1909);
  await const MethodChannel(
    'song_record/account',
  ).invokeMethod<void>('setAccount', {'userId': owner, 'environment': 'dev'});
  final manager = AccountStoreManager(environment: AppEnvironment.dev),
      repo = LocalRepository(await manager.openAccount(owner));
  final fixture = PlaylistAdditionFixture(repo);
  await fixture.initialize();
  final library = PlaylistLibrary(repo);
  if ((await library.items(fixture.playlistId)).isEmpty &&
      (await library.load()).isNotEmpty) {
    await library.addRegisteredMany(fixture.playlistId, [
      playlistFixtureId(1910),
      playlistFixtureId(1911),
    ], afterEach: fixture.synchronize);
  }
  runApp(
    MaterialApp(
      theme: AppTheme.dark(),
      home: PlaylistLibraryScreen(
        library: library,
        afterSave: fixture.synchronize,
      ),
    ),
  );
}
