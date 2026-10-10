-- D12: an in-flight/failed/latest attempt keeps the previous same-scope snapshot stale.
ALTER TABLE chart_publication
    ADD COLUMN collection_attempt_id BINARY(16) NULL,
    ADD COLUMN published_attempt_id BINARY(16) NULL;
-- Preserve any pre-existing published chart and initialize matching generation evidence.
UPDATE chart_publication SET collection_attempt_id=snapshot_id,published_attempt_id=snapshot_id
WHERE snapshot_id IS NOT NULL;
ALTER TABLE chart_publication ADD CONSTRAINT ck_chart_published_attempt CHECK
    ((snapshot_id IS NULL AND published_attempt_id IS NULL)
    OR (snapshot_id IS NOT NULL AND published_attempt_id IS NOT NULL));
