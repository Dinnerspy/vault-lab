SELECT 'CREATE DATABASE appdb'
WHERE NOT EXISTS (
    SELECT FROM pg_database WHERE datname = 'appdb'
)\gexec

\connect appdb;

-- Base schema for the demo application.
CREATE TABLE IF NOT EXISTS app_secrets (
    id SERIAL PRIMARY KEY,
    secret_value TEXT NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

INSERT INTO app_secrets (secret_value)
VALUES ('initial-seed');
