enum LocalState { capturing, inputPending, saved, interrupted, corrupt }

enum MetadataState { draft, saved }

enum SyncState { pending, syncing, synced, conflict }

enum CloudState { none, queued, uploading, verifying, stored, deleting }

enum BlockedReason {
  fileMissing,
  quota,
  pinLimit,
  budget,
  auth,
  network,
  fileInvalid,
}

enum LifecycleState { active, trashed, purgePending, purged }
