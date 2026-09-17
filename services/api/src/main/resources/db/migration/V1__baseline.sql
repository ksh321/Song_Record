-- P01-05: establish Flyway ownership of the application schema.
-- Domain tables are added by later versioned migrations.
CREATE TABLE app_schema_metadata (
    schema_key VARCHAR(64) NOT NULL,
    schema_value VARCHAR(255) NOT NULL,
    created_at DATETIME(3) NOT NULL DEFAULT CURRENT_TIMESTAMP(3),
    PRIMARY KEY (schema_key)
) ENGINE=InnoDB
  DEFAULT CHARACTER SET utf8mb4
  COLLATE utf8mb4_0900_ai_ci;

INSERT INTO app_schema_metadata (schema_key, schema_value)
VALUES ('schema_contract', '1');
