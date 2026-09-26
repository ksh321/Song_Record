-- H2 projection of V6 mutation_receipt. VARCHAR models the JDBC JSON text boundary.
CREATE TABLE mutation_receipt (
 user_id BINARY(16) NOT NULL, op_id BINARY(16) NOT NULL,
 request_hash CHAR(64) NOT NULL, response_status SMALLINT NOT NULL,
 response_body VARCHAR(1048576), created_at TIMESTAMP(3) NOT NULL, expires_at TIMESTAMP(3) NOT NULL,
 PRIMARY KEY(user_id,op_id), FOREIGN KEY(user_id) REFERENCES app_user(id),
 CHECK(response_status BETWEEN 200 AND 599),
 CHECK(response_status <> 204 OR response_body IS NULL)
);
CREATE TABLE mutation_effect(id INT PRIMARY KEY, value_count INT NOT NULL);
INSERT INTO mutation_effect VALUES(1,0);
