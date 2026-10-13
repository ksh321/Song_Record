import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

import '../../config/app_config.dart';
import '../domain/account_deletion_confirmation.dart';
import '../domain/identifiers.dart';

/// Durable, per-owner intent. Protected receipts and external exports live outside this tree.
final class AccountDeletionFiles {
  AccountDeletionFiles(this.support, this.environment, this.origin);
  final Directory support;
  final AppEnvironment environment;
  final Uri? origin;

  Future<Directory> _base() async {
    await support.create(recursive: true);
    var current = await support.resolveSymbolicLinks();
    for (final part in ['song_record', environment.name]) {
      current = p.join(current, part);
      await _directory(current);
    }
    return Directory(current);
  }

  Future<void> _directory(String target) async {
    final type = await FileSystemEntity.type(target, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      await Directory(target).create();
    } else if (type != FileSystemEntityType.directory) {
      throw StateError('Deletion storage was redirected');
    }
    if (!p.equals(await Directory(target).resolveSymbolicLinks(), target)) {
      throw StateError('Deletion storage escaped its root');
    }
  }

  Future<File> _marker(String user) async {
    final base = await _base(), id = UuidValue(user).value;
    final directory = p.join(base.path, 'account_deletion');
    await _directory(directory);
    final file = File(p.join(directory, '$id.json'));
    final type = await FileSystemEntity.type(file.path, followLinks: false);
    if (type != FileSystemEntityType.notFound &&
        type != FileSystemEntityType.file) {
      throw StateError('Deletion marker was redirected');
    }
    if (type == FileSystemEntityType.file &&
        !p.equals(await file.resolveSymbolicLinks(), file.path)) {
      throw StateError('Deletion marker escaped its root');
    }
    return file;
  }

  Future<bool> blocked(String user) async => (await _marker(user)).exists();
  Future<void> _write(File file, Map<String, dynamic> value) async {
    final pending = File('${file.path}.pending');
    if (await FileSystemEntity.type(pending.path, followLinks: false) ==
        FileSystemEntityType.link) {
      throw StateError('Deletion journal was redirected');
    }
    await pending.writeAsString(jsonEncode(value), flush: true);
    await pending.rename(file.path);
  }

  Future<void> confirm(AccountDeletionConfirmation proof) async {
    if (proof.userId == '00000000-0000-0000-0000-000000000000' ||
        origin != null && proof.origin != origin!.origin) {
      throw StateError('Deletion belongs to another server');
    }
    final file = await _marker(proof.userId);
    final value = {
      'version': 1,
      'environment': environment.name,
      'owner': proof.userId,
      'origin': proof.origin,
      'complete': false,
    };
    if (await file.exists()) {
      final old = jsonDecode(await file.readAsString());
      _valid(old, proof.userId);
      if (old['origin'] != proof.origin) {
        throw StateError('Deletion belongs to another server');
      }
    } else {
      await _write(file, value);
    }
    await _remove(proof.userId);
    await _write(file, {...value, 'complete': true});
  }

  void _valid(dynamic row, String id) {
    if (row is! Map ||
        row['version'] != 1 ||
        row['owner'] != id ||
        row['environment'] != environment.name ||
        row['origin'] is! String ||
        row['complete'] is! bool ||
        origin != null && row['origin'] != origin!.origin) {
      throw const FormatException('Invalid confirmed deletion journal');
    }
  }

  Future<void> recover() async {
    final base = await _base(),
        directory = p.join(base.path, 'account_deletion');
    await _directory(directory);
    await for (final entity in Directory(directory).list(followLinks: false)) {
      if (entity.path.endsWith('.pending')) {
        continue; // Only atomic committed intents authorize deletion.
      }
      if (entity is! File ||
          !RegExp(r'^[0-9a-f-]{36}\.json$').hasMatch(p.basename(entity.path))) {
        throw StateError('Unknown deletion journal');
      }
      final id = UuidValue(p.basenameWithoutExtension(entity.path)).value;
      final file = await _marker(id),
          value = jsonDecode(await file.readAsString());
      _valid(value, id);
      if (value['complete'] == false) {
        await _remove(id);
        await _write(file, {
          ...Map<String, dynamic>.from(value as Map),
          'complete': true,
        });
      }
    }
  }

  Future<void> _remove(String id) async {
    final base = await _base(), accounts = p.join(base.path, 'accounts');
    await _directory(accounts);
    final target = p.join(accounts, UuidValue(id).value);
    final type = await FileSystemEntity.type(target, followLinks: false);
    if (type == FileSystemEntityType.notFound) return;
    if (type != FileSystemEntityType.directory ||
        !p.equals(await Directory(target).resolveSymbolicLinks(), target) ||
        !p.isWithin(accounts, target)) {
      throw StateError('Account deletion target was redirected');
    }
    final entries = <FileSystemEntity>[];
    Future<void> inspect(Directory directory) async {
      await for (final entity in directory.list(followLinks: false)) {
        if (entity is Link ||
            !p.isWithin(target, entity.path) ||
            !p.equals(await entity.resolveSymbolicLinks(), entity.path)) {
          throw StateError('Account deletion encountered a redirected file');
        }
        if (entity is Directory) {
          await inspect(entity);
        } else if (entity is! File) {
          throw StateError('Unknown account deletion entry');
        }
        entries.add(entity);
      }
    }

    await inspect(
      Directory(target),
    ); // Validate the complete scope before removing anything.
    for (final entry in entries) {
      if (!p.equals(await Directory(target).resolveSymbolicLinks(), target) ||
          !p.equals(await entry.resolveSymbolicLinks(), entry.path)) {
        throw StateError('Account deletion target changed');
      }
      await entry.delete(); // Post-order, no recursive traversal and no link following.
    }
    await Directory(target).delete();
  }
}
