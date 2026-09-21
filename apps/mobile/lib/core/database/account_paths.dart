import 'dart:io';

import 'package:path/path.dart' as p;

import '../../config/app_config.dart';
import '../domain/identifiers.dart';

/// App-private storage only. Never interpret an object key/URL as a local path.
final class AccountPaths {
  AccountPaths._(this.directory, this.userId, this.environment);

  final Directory directory;
  final String userId;
  final AppEnvironment environment;

  static Future<AccountPaths> create(
    Directory applicationSupport,
    String rawUserId,
    AppEnvironment environment,
  ) async {
    final userId = UuidValue(rawUserId).value;
    if (userId == '00000000-0000-0000-0000-000000000000') {
      throw ArgumentError('An authenticated account ID is required');
    }
    await applicationSupport.create(recursive: true);
    final base = await applicationSupport.resolveSymbolicLinks();
    var current = base;
    for (final segment in [
      'song_record',
      environment.name,
      'accounts',
      userId,
    ]) {
      current = p.join(current, segment);
      await _ensureDirectory(current);
    }
    final result = AccountPaths._(Directory(current), userId, environment);
    for (final folder in ['audio', 'pending', 'imports']) {
      await _ensureDirectory(p.join(current, folder));
    }
    return result;
  }

  static Future<void> _ensureDirectory(String path) async {
    final type = await FileSystemEntity.type(path, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      await Directory(path).create();
    } else if (type != FileSystemEntityType.directory) {
      throw StateError('Account storage cannot traverse links or files');
    }
    final resolved = await Directory(path).resolveSymbolicLinks();
    if (!p.equals(resolved, path)) {
      throw StateError('Account storage directory escaped its private root');
    }
  }

  String audioPath(String recordingId) =>
      'audio/${UuidValue(recordingId).value}.m4a';
  String pendingPath(String recordingId) =>
      'pending/${UuidValue(recordingId).value}.m4a.part';
  String importPath(String jobId) => 'imports/${UuidValue(jobId).value}.zip';

  Future<File> databaseFile() async {
    for (final suffix in ['', '-wal', '-shm', '-journal']) {
      await checkedFile('account.sqlite$suffix', database: true);
    }
    return File(p.join(directory.path, 'account.sqlite'));
  }

  /// Internal storage primitive. AccountStore rechecks its session around I/O.
  Future<File> checkedFile(String relativePath, {bool database = false}) async {
    final valid = database
        ? RegExp(r'^account\.sqlite(?:-wal|-shm|-journal)?$')
              .hasMatch(relativePath)
        : RegExp(
            r'^(?:audio/[0-9a-f-]{36}\.m4a|pending/[0-9a-f-]{36}\.m4a\.part|imports/[0-9a-f-]{36}\.zip)$',
          ).hasMatch(relativePath);
    if (!valid || relativePath.contains('..') || relativePath.contains('\\')) {
      throw ArgumentError('Not an account-relative storage path');
    }
    final root = directory.path;
    if (!p.equals(await directory.resolveSymbolicLinks(), root)) {
      throw StateError('Account storage was redirected');
    }
    final segments = relativePath.split('/');
    var current = root;
    for (var index = 0; index < segments.length; index++) {
      current = p.join(current, segments[index]);
      final type = await FileSystemEntity.type(current, followLinks: false);
      if (type == FileSystemEntityType.link ||
          (index < segments.length - 1 &&
              type != FileSystemEntityType.directory) ||
          (index == segments.length - 1 &&
              type != FileSystemEntityType.file &&
              type != FileSystemEntityType.notFound)) {
        throw StateError(
          'Account file path is missing, redirected, or not a file',
        );
      }
      if (type != FileSystemEntityType.notFound) {
        final resolved = index == segments.length - 1
            ? await File(current).resolveSymbolicLinks()
            : await Directory(current).resolveSymbolicLinks();
        if (!p.equals(resolved, current) || !p.isWithin(root, resolved)) {
          throw StateError('Account file escaped its private directory');
        }
      }
    }
    return File(current);
  }
}
