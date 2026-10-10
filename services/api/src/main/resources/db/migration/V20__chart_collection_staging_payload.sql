-- D12/P16-02: complete bounded payload before validation/publication.
-- Default/production collection remains disabled until storage terms are confirmed.
CREATE TABLE chart_collection_payload (
    snapshot_id BINARY(16) NOT NULL,
    payload LONGBLOB NOT NULL,
    PRIMARY KEY (snapshot_id),
    CONSTRAINT fk_chart_payload_snapshot FOREIGN KEY (snapshot_id) REFERENCES chart_snapshot(id) ON DELETE CASCADE,
    CONSTRAINT ck_chart_payload_size CHECK (OCTET_LENGTH(payload) BETWEEN 1 AND 2097152)
) ENGINE=InnoDB;
