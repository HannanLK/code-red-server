-- Migration: 008_enhancements_and_partitions.sql
-- Description: Idempotent enhancements, missing FKs, schema tracking, and rolling partitions helpers

-- 1) Schema migrations registry (idempotent)
CREATE TABLE IF NOT EXISTS schema_migrations (
    id SERIAL PRIMARY KEY,
    filename TEXT UNIQUE NOT NULL,
    applied_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM schema_migrations WHERE filename = '008_enhancements_and_partitions.sql'
    ) THEN
        INSERT INTO schema_migrations(filename) VALUES ('008_enhancements_and_partitions.sql');
    END IF;
END $$;

-- 2) Add missing foreign keys and useful indexes (idempotent)
-- games.dictionary_id -> dictionaries(id)
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_constraint c
        JOIN pg_class t ON t.oid = c.conrelid
        WHERE t.relname = 'games' AND c.conname = 'fk_games_dictionary_id'
    ) THEN
        ALTER TABLE games
            ADD CONSTRAINT fk_games_dictionary_id
            FOREIGN KEY (dictionary_id)
            REFERENCES dictionaries(id)
            NOT VALID;
        -- Validate in a separate step to avoid long locks
        ALTER TABLE games VALIDATE CONSTRAINT fk_games_dictionary_id;
    END IF;
END $$;

-- Ensure helpful indexes exist for frequent queries
-- games(status, created_at DESC)
CREATE INDEX IF NOT EXISTS idx_games_status_created_at ON games(status, created_at DESC);
-- game_players(game_id, player_order)
CREATE INDEX IF NOT EXISTS idx_game_players_game_order ON game_players(game_id, player_order);
-- game_moves(game_id, move_number)
CREATE INDEX IF NOT EXISTS idx_game_moves_game_move ON game_moves(game_id, move_number);

-- 3) Updated-at trigger for tables that define updated_at but lack triggers
CREATE OR REPLACE FUNCTION update_updated_at_column()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

-- dictionaries.updated_at trigger
DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_trigger WHERE tgname = 'trg_dictionaries_updated_at'
    ) THEN
        CREATE TRIGGER trg_dictionaries_updated_at
        BEFORE UPDATE ON dictionaries
        FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();
    END IF;
END $$;

-- 4) Rolling partitions helpers (monthly + daily)
-- Helper to create monthly partition if not exists for a partitioned table by timestamp column
CREATE OR REPLACE FUNCTION ensure_month_partition(
    p_table REGCLASS,
    p_prefix TEXT,
    p_from DATE,
    p_to DATE
) RETURNS VOID AS $$
DECLARE
    v_child TEXT := format('%s_%s', p_prefix, to_char(p_from, 'YYYY_MM'));
    v_sql   TEXT;
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_class WHERE relname = v_child
    ) THEN
        v_sql := format('CREATE TABLE %I PARTITION OF %s FOR VALUES FROM (%L) TO (%L);',
                        v_child, p_table, p_from::timestamptz, p_to::timestamptz);
        EXECUTE v_sql;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Helper to create daily partition
CREATE OR REPLACE FUNCTION ensure_day_partition(
    p_table REGCLASS,
    p_prefix TEXT,
    p_from DATE,
    p_to DATE
) RETURNS VOID AS $$
DECLARE
    v_child TEXT := format('%s_%s', p_prefix, to_char(p_from, 'YYYY_MM_DD'));
    v_sql   TEXT;
BEGIN
    IF NOT EXISTS (
        SELECT 1 FROM pg_class WHERE relname = v_child
    ) THEN
        v_sql := format('CREATE TABLE %I PARTITION OF %s FOR VALUES FROM (%L) TO (%L);',
                        v_child, p_table, p_from::timestamptz, p_to::timestamptz);
        EXECUTE v_sql;
    END IF;
END;
$$ LANGUAGE plpgsql;

-- Seed current and next partitions for partitioned tables
DO $$
DECLARE
    v_first_of_month DATE := date_trunc('month', CURRENT_DATE)::date;
    v_next_month DATE := (date_trunc('month', CURRENT_DATE) + INTERVAL '1 month')::date;
    v_first_of_next_next DATE := (date_trunc('month', CURRENT_DATE) + INTERVAL '2 months')::date;
    v_today DATE := CURRENT_DATE;
    v_tomorrow DATE := CURRENT_DATE + INTERVAL '1 day';
BEGIN
    -- audit_logs by month (created_at)
    PERFORM ensure_month_partition('audit_logs'::regclass, 'audit_logs', v_first_of_month, v_next_month);
    PERFORM ensure_month_partition('audit_logs'::regclass, 'audit_logs', v_next_month, v_first_of_next_next);

    -- game_moves by month (created_at)
    PERFORM ensure_month_partition('game_moves'::regclass, 'game_moves', v_first_of_month, v_next_month);
    PERFORM ensure_month_partition('game_moves'::regclass, 'game_moves', v_next_month, v_first_of_next_next);

    -- performance_metrics by day (recorded_at)
    PERFORM ensure_day_partition('performance_metrics'::regclass, 'performance_metrics', v_today, v_tomorrow);
    PERFORM ensure_day_partition('performance_metrics'::regclass, 'performance_metrics', v_tomorrow, v_tomorrow + INTERVAL '1 day');
END $$;

-- 5) Safety: ensure required extensions are present (idempotent)
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS pg_trgm;

-- 6) Comments
COMMENT ON TABLE schema_migrations IS 'Tracks applied SQL migrations (filename-based)';
COMMENT ON FUNCTION ensure_month_partition(REGCLASS, TEXT, DATE, DATE) IS 'Ensures monthly partition exists for given range [from,to)';
COMMENT ON FUNCTION ensure_day_partition(REGCLASS, TEXT, DATE, DATE) IS 'Ensures daily partition exists for given range [from,to)';
