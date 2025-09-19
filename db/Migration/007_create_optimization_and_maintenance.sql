-- Migration: 007_create_optimization_and_maintenance.sql
-- Description: Performance optimization, maintenance, and monitoring tables

-- Audit log table for important actions
CREATE TABLE audit_logs (
                            id BIGSERIAL,
                            user_id UUID REFERENCES users(id) ON DELETE SET NULL,
                            action VARCHAR(100) NOT NULL,
                            entity_type VARCHAR(50), -- 'game', 'user', 'tournament', etc.
                            entity_id UUID,
                            old_values JSONB,
                            new_values JSONB,
                            ip_address INET,
                            user_agent TEXT,
                            created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
                            PRIMARY KEY (id, created_at)
) PARTITION BY RANGE (created_at);

-- Create monthly partitions for audit logs
CREATE TABLE audit_logs_2024_01 PARTITION OF audit_logs
    FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');

-- Indexes for audit logs
CREATE INDEX idx_audit_logs_user ON audit_logs(user_id);
CREATE INDEX idx_audit_logs_entity ON audit_logs(entity_type, entity_id);
CREATE INDEX idx_audit_logs_created ON audit_logs(created_at DESC);

-- Performance metrics table
CREATE TABLE performance_metrics (
                                     id BIGSERIAL,
                                     metric_name VARCHAR(100) NOT NULL,
                                     metric_value DECIMAL(20,4),
                                     metric_unit VARCHAR(20),
                                     tags JSONB DEFAULT '{}',
                                     recorded_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
                                     PRIMARY KEY (id, recorded_at)
) PARTITION BY RANGE (recorded_at);

-- Create daily partitions for metrics
CREATE TABLE performance_metrics_2024_01_01 PARTITION OF performance_metrics
    FOR VALUES FROM ('2024-01-01') TO ('2024-01-02');

-- Indexes for metrics
CREATE INDEX idx_metrics_name ON performance_metrics(metric_name, recorded_at DESC);
CREATE INDEX idx_metrics_tags ON performance_metrics USING gin (tags);

-- Query performance tracking
CREATE TABLE slow_query_log (
                                id BIGSERIAL PRIMARY KEY,
                                query_hash VARCHAR(64),
                                query_text TEXT,
                                execution_time_ms INTEGER,
                                rows_affected INTEGER,
                                user_id UUID REFERENCES users(id) ON DELETE SET NULL,
                                endpoint VARCHAR(200),
                                created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Index for slow queries
CREATE INDEX idx_slow_queries_hash ON slow_query_log(query_hash, created_at DESC);
CREATE INDEX idx_slow_queries_time ON slow_query_log(execution_time_ms DESC);

-- Cache invalidation tracking
CREATE TABLE cache_invalidation (
                                    id BIGSERIAL PRIMARY KEY,
                                    cache_key VARCHAR(255) NOT NULL,
                                    cache_type VARCHAR(50), -- 'redis', 'materialized_view', 'application'
                                    invalidated_by UUID REFERENCES users(id) ON DELETE SET NULL,
                                    reason VARCHAR(200),
                                    invalidated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Index for cache invalidation
CREATE INDEX idx_cache_invalidation_key ON cache_invalidation(cache_key, invalidated_at DESC);

-- Archive tables for old data
CREATE TABLE games_archive (LIKE games INCLUDING ALL);
CREATE TABLE game_moves_archive (LIKE game_moves INCLUDING ALL);
CREATE TABLE game_chat_archive (LIKE game_chat INCLUDING ALL);

-- Add archive date column
ALTER TABLE games_archive ADD COLUMN archived_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP;
ALTER TABLE game_moves_archive ADD COLUMN archived_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP;
ALTER TABLE game_chat_archive ADD COLUMN archived_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP;

-- Function to archive old games
CREATE OR REPLACE FUNCTION archive_old_games() RETURNS void AS $$
DECLARE
    v_cutoff_date TIMESTAMP WITH TIME ZONE;
    v_archived_count INTEGER;
BEGIN
    v_cutoff_date := CURRENT_TIMESTAMP - INTERVAL '30 days';

    -- Archive games
    INSERT INTO games_archive
    SELECT *, CURRENT_TIMESTAMP as archived_at
    FROM games
    WHERE status = 'completed'
      AND ended_at < v_cutoff_date;

    GET DIAGNOSTICS v_archived_count = ROW_COUNT;

    -- Archive moves
    INSERT INTO game_moves_archive
    SELECT gm.*, CURRENT_TIMESTAMP as archived_at
    FROM game_moves gm
             JOIN games g ON gm.game_id = g.id
    WHERE g.status = 'completed'
      AND g.ended_at < v_cutoff_date;

    -- Archive chat
    INSERT INTO game_chat_archive
    SELECT gc.*, CURRENT_TIMESTAMP as archived_at
    FROM game_chat gc
             JOIN games g ON gc.game_id = g.id
    WHERE g.status = 'completed'
      AND g.ended_at < v_cutoff_date;

    -- Delete from main tables
    DELETE FROM games
    WHERE status = 'completed'
      AND ended_at < v_cutoff_date;

    -- Log the archive operation
    INSERT INTO audit_logs (action, entity_type, new_values)
    VALUES ('archive_games', 'system',
            jsonb_build_object('archived_count', v_archived_count, 'cutoff_date', v_cutoff_date));
END;
$$ LANGUAGE plpgsql;

-- Function to clean up expired data
CREATE OR REPLACE FUNCTION cleanup_expired_data() RETURNS void AS $$
BEGIN
    -- Clean expired sessions
    DELETE FROM user_sessions WHERE expires_at < CURRENT_TIMESTAMP;

    -- Clean expired guest users
    DELETE FROM guest_users WHERE expires_at < CURRENT_TIMESTAMP;

    -- Clean expired lobby queue entries
    DELETE FROM lobby_queue WHERE expires_at < CURRENT_TIMESTAMP AND is_active = true;

    -- Clean expired game invitations
    UPDATE game_invitations
    SET status = 'expired'
    WHERE expires_at < CURRENT_TIMESTAMP AND status = 'pending';

    -- Clean old notifications
    DELETE FROM notification_queue WHERE expires_at < CURRENT_TIMESTAMP;

    -- Clean old cache entries
    DELETE FROM word_validation_cache
    WHERE last_accessed < CURRENT_TIMESTAMP - INTERVAL '7 days';
END;
$$ LANGUAGE plpgsql;

-- Function to update statistics tables
CREATE OR REPLACE FUNCTION update_aggregate_statistics() RETURNS void AS $$
BEGIN
    -- Update word statistics
    INSERT INTO word_statistics (word, dictionary_id, times_played, total_score_earned, highest_score)
    SELECT
        word_played,
        1, -- Default dictionary
        COUNT(*),
        SUM(score_earned),
        MAX(score_earned)
    FROM game_moves
    WHERE created_at > CURRENT_TIMESTAMP - INTERVAL '1 day'
      AND word_played IS NOT NULL
    GROUP BY word_played
    ON CONFLICT (word, dictionary_id) DO UPDATE
        SET times_played = word_statistics.times_played + EXCLUDED.times_played,
            total_score_earned = word_statistics.total_score_earned + EXCLUDED.total_score_earned,
            highest_score = GREATEST(word_statistics.highest_score, EXCLUDED.highest_score),
            last_played_at = CURRENT_TIMESTAMP;
END;
$$ LANGUAGE plpgsql;

-- Function to calculate and update ELO ratings
CREATE OR REPLACE FUNCTION update_player_rating(
    p_user_id UUID,
    p_game_mode game_mode,
    p_result game_result
) RETURNS void AS $$
DECLARE
    v_current_rating INTEGER;
    v_opponent_rating INTEGER;
    v_k_factor INTEGER := 32; -- Standard K-factor
    v_expected_score DECIMAL;
    v_actual_score DECIMAL;
    v_new_rating INTEGER;
BEGIN
    -- Get current ratings
    SELECT rating INTO v_current_rating
    FROM player_ratings
    WHERE user_id = p_user_id AND game_mode = p_game_mode;

    IF NOT FOUND THEN
        -- Create initial rating
        INSERT INTO player_ratings (user_id, game_mode)
        VALUES (p_user_id, p_game_mode);
        v_current_rating := 1200;
    END IF;

    -- For simplicity, assume opponent rating (would be passed as parameter in production)
    v_opponent_rating := 1200;

    -- Calculate expected score
    v_expected_score := 1 / (1 + POWER(10, (v_opponent_rating - v_current_rating) / 400.0));

    -- Actual score
    v_actual_score := CASE
                          WHEN p_result = 'win' THEN 1.0
                          WHEN p_result = 'draw' THEN 0.5
                          ELSE 0.0
        END;

    -- Calculate new rating
    v_new_rating := v_current_rating + ROUND(v_k_factor * (v_actual_score - v_expected_score));

    -- Update rating
    UPDATE player_ratings
    SET rating = v_new_rating,
        games_played = games_played + 1,
        games_won = games_won + CASE WHEN p_result = 'win' THEN 1 ELSE 0 END,
        games_drawn = games_drawn + CASE WHEN p_result = 'draw' THEN 1 ELSE 0 END,
        peak_rating = GREATEST(peak_rating, v_new_rating),
        last_game_at = CURRENT_TIMESTAMP,
        updated_at = CURRENT_TIMESTAMP
    WHERE user_id = p_user_id AND game_mode = p_game_mode;
END;
$$ LANGUAGE plpgsql;

-- Database health check view
CREATE OR REPLACE VIEW v_database_health AS
SELECT
    'Active Games' as metric,
    COUNT(*) as value
FROM games WHERE status = 'active'
UNION ALL
SELECT
    'Online Users (last 5 min)',
    COUNT(DISTINCT user_id)
FROM user_sessions
WHERE last_activity > CURRENT_TIMESTAMP - INTERVAL '5 minutes'
UNION ALL
SELECT
    'Pending Notifications',
    COUNT(*)
FROM notification_queue WHERE is_sent = false
UNION ALL
SELECT
    'Cache Hit Rate',
    ROUND(AVG(lookup_count), 2)
FROM word_validation_cache
WHERE last_accessed > CURRENT_TIMESTAMP - INTERVAL '1 hour';

-- Create indexes for foreign keys (performance optimization)
CREATE INDEX IF NOT EXISTS idx_fk_game_players_game ON game_players(game_id);
CREATE INDEX IF NOT EXISTS idx_fk_game_players_user ON game_players(user_id);
CREATE INDEX IF NOT EXISTS idx_fk_game_moves_game ON game_moves(game_id);
CREATE INDEX IF NOT EXISTS idx_fk_game_moves_player ON game_moves(player_id);

-- Create compound indexes for common queries
CREATE INDEX idx_games_active_players ON game_players(user_id, game_id)
    WHERE user_id IS NOT NULL;
CREATE INDEX idx_games_recent_completed ON games(ended_at DESC)
    WHERE status = 'completed';
CREATE INDEX idx_player_recent_activity ON game_players(user_id, last_action_at DESC);

-- Partial indexes for performance
CREATE INDEX idx_games_waiting ON games(created_at) WHERE status = 'waiting';
CREATE INDEX idx_games_active_rated ON games(created_at) WHERE status = 'active' AND is_rated = true;

-- Function-based indexes
CREATE INDEX idx_users_lower_username ON users(LOWER(username));
CREATE INDEX idx_users_lower_email ON users(LOWER(email));

-- Create scheduled job table
CREATE TABLE scheduled_jobs (
                                id SERIAL PRIMARY KEY,
                                job_name VARCHAR(100) UNIQUE NOT NULL,
                                job_function VARCHAR(100) NOT NULL,
                                schedule VARCHAR(50) NOT NULL, -- Cron expression
                                is_active BOOLEAN DEFAULT true,
                                last_run_at TIMESTAMP WITH TIME ZONE,
                                next_run_at TIMESTAMP WITH TIME ZONE,
                                last_status VARCHAR(20),
                                last_error TEXT
);

-- Insert default scheduled jobs
INSERT INTO scheduled_jobs (job_name, job_function, schedule) VALUES
                                                                  ('archive_old_games', 'archive_old_games', '0 3 * * *'), -- Daily at 3 AM
                                                                  ('cleanup_expired_data', 'cleanup_expired_data', '*/30 * * * *'), -- Every 30 minutes
                                                                  ('refresh_materialized_views', 'refresh_materialized_views', '0 * * * *'), -- Every hour
                                                                  ('update_aggregate_statistics', 'update_aggregate_statistics', '*/10 * * * *'); -- Every 10 minutes

-- Comments
COMMENT ON TABLE audit_logs IS 'Audit trail for important system actions';
COMMENT ON TABLE performance_metrics IS 'System performance metrics tracking';
COMMENT ON TABLE slow_query_log IS 'Tracking slow database queries';
COMMENT ON TABLE cache_invalidation IS 'Cache invalidation tracking';
COMMENT ON TABLE games_archive IS 'Archived completed games';
COMMENT ON TABLE scheduled_jobs IS 'Cron-like scheduled database jobs';
COMMENT ON VIEW v_database_health IS 'Real-time database health metrics';