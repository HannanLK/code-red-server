-- Migration: 009_hotfix_idempotent_and_performance.sql
-- Purpose: Make schema re-runnable/idempotent and fix known blockers to allow clean migration runs.
-- Safe to run multiple times.

-- 0) Register in schema_migrations if exists
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.tables 
    WHERE table_schema = current_schema() AND table_name = 'schema_migrations'
  ) THEN
    IF NOT EXISTS (SELECT 1 FROM schema_migrations WHERE filename = '009_hotfix_idempotent_and_performance.sql') THEN
      INSERT INTO schema_migrations(filename) VALUES ('009_hotfix_idempotent_and_performance.sql');
    END IF;
  END IF;
END $$;

-- 1) Drop problematic partial index that uses a non-IMMUTABLE function in predicate
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
    WHERE c.relkind = 'i' AND c.relname = 'idx_player_ratings_active'
  ) THEN
    EXECUTE 'DROP INDEX IF EXISTS idx_player_ratings_active';
  END IF;
END $$;

-- 2) Fix performance_metrics PK on partitioned table (must include partition key recorded_at)
DO $$
BEGIN
  -- Check table exists
  IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'performance_metrics') THEN
    -- Check if primary key already includes recorded_at
    IF NOT EXISTS (
      SELECT 1 
      FROM information_schema.table_constraints tc
      JOIN information_schema.key_column_usage kcu
        ON tc.constraint_name = kcu.constraint_name
      WHERE tc.table_name = 'performance_metrics'
        AND tc.constraint_type = 'PRIMARY KEY'
        AND kcu.column_name = 'recorded_at'
    ) THEN
      -- Find current PK name
      PERFORM 1;
      -- Drop existing PK (name may vary)
      EXECUTE (
        SELECT 'ALTER TABLE performance_metrics DROP CONSTRAINT ' || quote_ident(tc.constraint_name)
        FROM information_schema.table_constraints tc
        WHERE tc.table_name = 'performance_metrics' AND tc.constraint_type = 'PRIMARY KEY'
        LIMIT 1
      );
      -- Add composite PK
      EXECUTE 'ALTER TABLE performance_metrics ADD PRIMARY KEY (id, recorded_at)';
    END IF;
  END IF;
END $$;

-- 3) Ensure mv_two_letter_words exists (skip creation if already present)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_matviews WHERE matviewname = 'mv_two_letter_words'
  ) THEN
    IF EXISTS (SELECT 1 FROM information_schema.tables WHERE table_name = 'dictionary_words') THEN
      EXECUTE 'CREATE MATERIALIZED VIEW mv_two_letter_words AS '
           || 'SELECT dictionary_id, word '
           || 'FROM dictionary_words '
           || 'WHERE word_length = 2 AND is_valid = true';
      EXECUTE 'CREATE INDEX IF NOT EXISTS idx_mv_two_letter ON mv_two_letter_words(dictionary_id, word)';
    END IF;
  END IF;
END $$;

-- 4) Idempotent seeds using ON CONFLICT DO NOTHING
-- Dictionaries
INSERT INTO dictionaries (name, language_code, description, version)
VALUES ('TWL', 'en', 'Tournament Word List (North American)', '2024')
ON CONFLICT (name) DO NOTHING;
INSERT INTO dictionaries (name, language_code, description, version)
VALUES ('SOWPODS', 'en', 'Combined TWL and OSW (International)', '2024')
ON CONFLICT (name) DO NOTHING;
INSERT INTO dictionaries (name, language_code, description, version)
VALUES ('ENABLE', 'en', 'Enhanced North American Benchmark Lexicon', '2024')
ON CONFLICT (name) DO NOTHING;
INSERT INTO dictionaries (name, language_code, description, version)
VALUES ('ODS', 'fr', 'Officiel du Scrabble (French)', '2024')
ON CONFLICT (name) DO NOTHING;

-- Tile distribution
INSERT INTO tile_distributions (name, language_code, total_tiles, distribution)
VALUES ('Standard English', 'en', 100, '{
  "A": {"count": 9, "points": 1},
  "B": {"count": 2, "points": 3},
  "C": {"count": 2, "points": 3},
  "D": {"count": 4, "points": 2},
  "E": {"count": 12, "points": 1},
  "F": {"count": 2, "points": 4},
  "G": {"count": 3, "points": 2},
  "H": {"count": 2, "points": 4},
  "I": {"count": 9, "points": 1},
  "J": {"count": 1, "points": 8},
  "K": {"count": 1, "points": 5},
  "L": {"count": 4, "points": 1},
  "M": {"count": 2, "points": 3},
  "N": {"count": 6, "points": 1},
  "O": {"count": 8, "points": 1},
  "P": {"count": 2, "points": 3},
  "Q": {"count": 1, "points": 10},
  "R": {"count": 6, "points": 1},
  "S": {"count": 4, "points": 1},
  "T": {"count": 6, "points": 1},
  "U": {"count": 4, "points": 1},
  "V": {"count": 2, "points": 4},
  "W": {"count": 2, "points": 4},
  "X": {"count": 1, "points": 8},
  "Y": {"count": 2, "points": 4},
  "Z": {"count": 1, "points": 10},
  "_": {"count": 2, "points": 0}
}')
ON CONFLICT (name) DO NOTHING;

-- Board configuration
INSERT INTO board_configurations (name, board_size, premium_squares, is_default)
VALUES ('Standard 15x15', 15, '{"8,8":"star"}', true)
ON CONFLICT (name) DO NOTHING;

-- Bots
INSERT INTO bots (name, difficulty, personality, elo_rating, think_time_ms, mistake_probability, vocabulary_size)
VALUES 
 ('Beginner Bot', 'beginner', 'teacher', 800, 2000, 0.30, 'small'),
 ('Casual Player', 'easy', 'balanced', 1000, 3000, 0.20, 'medium'),
 ('Club Player', 'medium', 'balanced', 1400, 5000, 0.10, 'large'),
 ('Tournament Player', 'hard', 'strategic', 1800, 8000, 0.05, 'complete'),
 ('Expert Bot', 'expert', 'aggressive', 2200, 10000, 0.02, 'complete'),
 ('Scrabble Master', 'master', 'strategic', 2500, 15000, 0.00, 'complete')
ON CONFLICT (name) DO NOTHING;

-- Bot availability for all bots
INSERT INTO bot_availability (bot_id, max_concurrent_games)
SELECT b.id,
       CASE WHEN b.difficulty IN ('beginner','easy') THEN 50
            WHEN b.difficulty IN ('medium','hard') THEN 20
            ELSE 10 END
FROM bots b
ON CONFLICT (bot_id) DO NOTHING;

-- Quick chat messages (minimal set)
INSERT INTO quick_chat_messages (category, message, emoji) VALUES
 ('greeting','Good luck!','🤞'),
 ('reaction','Nice move!','👏'),
 ('farewell','Good game!','🤝')
ON CONFLICT DO NOTHING;

-- Achievements (subset)
INSERT INTO achievements (code, name, description, category, points, requirement_type, requirement_value)
VALUES
 ('first_win','First Victory','Win your first game','milestone',10,'games_won',1),
 ('bingo_first','Bingo!','Play your first 7-letter word','skill',20,'bingos',1)
ON CONFLICT (code) DO NOTHING;

-- Scheduled jobs
INSERT INTO scheduled_jobs (job_name, job_function, schedule) VALUES
 ('archive_old_games','archive_old_games','0 3 * * *'),
 ('cleanup_expired_data','cleanup_expired_data','*/30 * * * *'),
 ('refresh_materialized_views','refresh_materialized_views','0 * * * *')
ON CONFLICT (job_name) DO NOTHING;

-- 5) Helpful indexes (idempotent)
CREATE INDEX IF NOT EXISTS idx_games_status_created_at ON games(status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_game_players_game_order ON game_players(game_id, player_order);
CREATE INDEX IF NOT EXISTS idx_game_moves_game_move ON game_moves(game_id, move_number);
