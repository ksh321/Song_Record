import 'dart:convert';

import 'package:drift/drift.dart';

import '../domain/identifiers.dart';
import '../sync/change_feed_response.dart';
import '../sync/change_payload_validation.dart';
import 'account_database.dart';
import 'local_models.dart';
import 'snapshot_playlist_item_projection.dart';

typedef WriteMetadataCopy = Future<void> Function(
  String entity,
  String id,
  int revision,
  String payload,
  bool deleted,
);

/// A playlist operation carries a complete item set at one parent revision.
/// Caller owns the account transaction, including the final cursor/fence.
final class PlaylistChangeStore {
  PlaylistChangeStore(this.db, this.requireActive, this.writeCopy);
  final AccountDatabase db;
  final void Function() requireActive;
  final WriteMetadataCopy writeCopy;

  /// A header/receipt proves deletion of the parent, not an empty partial item
  /// list. Propagate it only to known server children; keep unsent creations.
  Future<void> applyParentDeletion(ChangeFeedEntry entry) async {
    requireActive();
    final payload = Map<String, dynamic>.of(entry.payload);
    if (payload.containsKey('user_id') && payload['user_id'] != db.userId) {
      throw const FormatException('Foreign playlist deletion');
    }
    payload.remove('user_id');
    if (payload.containsKey('status')) {
      validatePlaylistDeletion(payload);
      if (!entry.deleted) {
        throw const FormatException('Deletion receipt requires DELETE');
      }
    } else {
      validateChangePayload(LocalEntity.playlist, payload);
    }
    if (entry.entity != LocalEntity.playlist || payload['id'] != entry.id ||
        payload['revision'] != entry.revision || payload['deleted_at'] == null) {
      throw const FormatException('Invalid playlist deletion identity');
    }
    await _applyParentDeletion(entry.id, entry.revision, payload);
  }

  Future<void> _applyParentDeletion(
    String playlistId,
    int incomingRevision,
    Map<String, dynamic> payload,
  ) async {
    final parent = await db.customSelect(
      "SELECT server_revision,tombstone FROM metadata_copies WHERE entity_type='PLAYLIST' AND entity_id=?",
      variables: [Variable(playlistId)],
    ).getSingleOrNull();
    final revision = parent?.read<int>('server_revision') ?? 0;
    if (revision > incomingRevision) {
      return;
    }
    if (revision == incomingRevision && parent?.read<int>('tombstone') == 0) {
      throw StateError('Deletion did not advance playlist revision');
    }
    final children = await db.customSelect(
      "SELECT * FROM metadata_copies WHERE entity_type='PLAYLIST_ITEM' AND user_id=?",
      variables: [Variable(db.userId)],
    ).get();
    for (final row in children) {
      requireActive();
      final encoded = row.readNullable<String>('server_payload');
      if (encoded == null) {
        continue;
      }
      final saved = jsonDecode(encoded) as Map<String, dynamic>;
      if (saved['playlist_id'] != playlistId) {
        continue;
      }
      if (row.read<int>('server_revision') > incomingRevision) {
        throw StateError('Playlist deletion predates a known child');
      }
      if (row.read<int>('tombstone') == 1) {
        continue;
      }
      final id = row.read<String>('entity_id');
      await writeCopy('PLAYLIST_ITEM', id, incomingRevision, canonicalJson({
        'id': id, 'playlist_id': playlistId, 'revision': incomingRevision,
        'playlist_revision': incomingRevision, 'status': 'DELETED',
      }), true);
    }
    if (parent?.read<int>('tombstone') != 1) {
      await writeCopy('PLAYLIST', playlistId, incomingRevision,
          canonicalJson(payload), true);
    }
    requireActive();
  }

  Future<void> apply(ChangeFeedEntry entry) async {
    void require(bool value) {
      if (!value) {
        throw const FormatException('Invalid playlist aggregate change');
      }
    }

    Map<String, dynamic> owned(Map<String, dynamic> value) {
      require(!value.containsKey('user_id') || value['user_id'] == db.userId);
      return {...value, 'user_id': db.userId};
    }

    requireActive();
    final payload = entry.payload;
    require(
      payload.length == 2 &&
          payload['playlist'] is Map<String, dynamic> &&
          payload['items'] is List,
    );
    final parent = owned(payload['playlist'] as Map<String, dynamic>);
    final parentId = parent['id'];
    require(parentId is String && UuidValue(parentId).value == parentId);
    final projectedParent = Map<String, dynamic>.of(parent)..remove('user_id');
    validateChangePayload(LocalEntity.playlist, projectedParent);
    final playlistId = parentId as String;
    require(projectedParent['revision'] == entry.revision);
    if (entry.entity == LocalEntity.playlist) {
      require(entry.id == parentId);
      require(!entry.deleted || projectedParent['deleted_at'] != null);
    } else {
      require(entry.entity == LocalEntity.playlistItem);
    }
    final projectedItems = <String, Map<String, dynamic>>{};
    final keys = <String>{};
    for (final raw in payload['items'] as List) {
      require(raw is Map<String, dynamic>);
      final item = owned(raw as Map<String, dynamic>);
      require(item['id'] is String && item['playlist_id'] == parentId);
      Map<String, dynamic>? song;
      if (item['song_id'] != null) {
        require(item['song_id'] is String);
        final found = await db
            .customSelect(
              "SELECT server_payload,user_id FROM metadata_copies WHERE entity_type='SONG' AND entity_id=?",
              variables: [Variable(item['song_id'] as String)],
            )
            .getSingleOrNull();
        require(
          found != null &&
              found.read<String>('user_id') == db.userId &&
              found.readNullable<String>('server_payload') != null,
        );
        song = owned(
          jsonDecode(found!.read<String>('server_payload'))
              as Map<String, dynamic>,
        );
      }
      final projected = projectSnapshotPlaylistItem(
        item,
        owner: db.userId,
        id: item['id'] as String,
        playlist: parent,
        song: song,
      );
      require(!projectedItems.containsKey(projected['id']));
      require(keys.add(projected['entry_key'] as String));
      projectedItems[projected['id'] as String] = projected;
      requireActive();
    }
    if (entry.entity == LocalEntity.playlistItem) {
      require(
        entry.deleted
            ? !projectedItems.containsKey(entry.id)
            : projectedItems.containsKey(entry.id),
      );
    }
    final currentParent = await db
        .customSelect(
          "SELECT server_revision,server_payload,tombstone FROM metadata_copies WHERE entity_type='PLAYLIST' AND entity_id=?",
          variables: [Variable(playlistId)],
        )
        .getSingleOrNull();
    final parentTombstoned = currentParent?.read<int>('tombstone') == 1;
    final deletedParent = projectedParent['deleted_at'] != null;
    if ((currentParent?.read<int>('server_revision') ?? 0) > entry.revision ||
        parentTombstoned && !deletedParent) {
      return;
    }
    if (!parentTombstoned &&
        currentParent?.read<int>('server_revision') == entry.revision) {
      require(
        canonicalJson(
              jsonDecode(currentParent!.read<String>('server_payload'))
                  as Map<String, dynamic>,
            ) ==
            canonicalJson(projectedParent),
      );
    }
    final rows = await db
        .customSelect(
          "SELECT * FROM metadata_copies WHERE entity_type='PLAYLIST_ITEM'",
        )
        .get();
    final current = {
      for (final row in rows) row.read<String>('entity_id'): row,
    };
    for (final item in projectedItems.entries) {
      final previous = current[item.key];
      if (previous != null) {
        final local = previous.readNullable<String>('local_payload');
        if (local != null) {
          final draft = jsonDecode(local) as Map<String, dynamic>;
          require(
            !draft.containsKey('playlist_id') ||
                draft['playlist_id'] == parentId,
          );
        }
        final encoded = previous.readNullable<String>('server_payload');
        final saved = encoded == null
            ? null
            : jsonDecode(encoded) as Map<String, dynamic>;
        require(saved == null || saved['playlist_id'] == parentId);
        require(previous.read<int>('tombstone') == 0 || deletedParent);
        require(previous.read<int>('server_revision') <= entry.revision);
        if (previous.read<int>('server_revision') == entry.revision &&
            !(parentTombstoned && previous.read<int>('tombstone') == 1)) {
          require(canonicalJson(saved!) == canonicalJson(item.value));
        }
      }
    }
    if (parentTombstoned) {
      // Older receivers could store only the parent deletion. Validate the
      // aggregate first, then repair known children without replacing that
      // parent's deletion proof or creating server rows for unsent drafts.
      await _applyParentDeletion(playlistId, entry.revision, projectedParent);
      return;
    }
    for (final row in rows) {
      final encoded = row.readNullable<String>('server_payload');
      if (encoded == null) continue; // Never erase an unsent local creation.
      final saved = jsonDecode(encoded) as Map<String, dynamic>;
      if (saved['playlist_id'] != parentId ||
          projectedItems.containsKey(row.read<String>('entity_id')) ||
          row.read<int>('tombstone') == 1) {
        continue;
      }
      require(row.read<int>('server_revision') < entry.revision);
    }
    final removed = <String>{
      for (final row in rows)
        if (row.readNullable<String>('server_payload') != null &&
            (jsonDecode(row.read<String>('server_payload'))
                    as Map)['playlist_id'] ==
                parentId &&
            !projectedItems.containsKey(row.read<String>('entity_id')) &&
            row.read<int>('tombstone') == 0)
          row.read<String>('entity_id'),
      if (entry.entity == LocalEntity.playlistItem && entry.deleted) entry.id,
    };
    for (final id in removed) {
      final previous = current[id];
      if (previous?.readNullable<String>('local_payload')
          case final String local) {
        final draft = jsonDecode(local) as Map<String, dynamic>;
        require(
          !draft.containsKey('playlist_id') || draft['playlist_id'] == parentId,
        );
      }
      if (previous != null &&
          previous.readNullable<String>('server_payload') != null) {
        require(
          (jsonDecode(previous.read<String>('server_payload'))
                  as Map)['playlist_id'] ==
              parentId,
        );
        if (previous.read<int>('tombstone') == 1) continue;
      }
      await writeCopy(
        'PLAYLIST_ITEM',
        id,
        entry.revision,
        canonicalJson({
          'id': id,
          'playlist_id': parentId,
          'revision': entry.revision,
          'playlist_revision': entry.revision,
          'status': 'DELETED',
        }),
        true,
      );
    }
    await writeCopy(
      'PLAYLIST',
      playlistId,
      entry.revision,
      canonicalJson(projectedParent),
      deletedParent,
    );
    for (final item in projectedItems.entries) {
      await writeCopy(
        'PLAYLIST_ITEM',
        item.key,
        entry.revision,
        canonicalJson(item.value),
        deletedParent,
      );
    }
    requireActive();
  }
}
