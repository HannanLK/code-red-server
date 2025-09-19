-- Migration: 005_create_statistics_and_analytics.sql
-- Description: Player statistics, ratings, achievements, and analytics

-- Player ratings table (ELO system)
CREATE TABLE player_ratings (
                                id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
                                user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                                game_mode game_mode NOT NULL,
                                rating INTEGER DEFAULT 1200,
                                rating_deviation INTEGER DEFAULT 350, -- For Glicko rating system
                                peak_rating INTEGER DEFAULT 1200,
                                games_played INTEGER DEFAULT 0,
                                games_won INTEGER DEFAULT 0,
                                games_drawn INTEGER DEFAULT 0,
                                win_streak INTEGER DEFAULT 0,
                                best_win_streak INTEGER DEFAULT 0,
                                last_game_at TIMESTAMP WITH TIME ZONE,
                                created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
                                updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    -- Constraints
                                CONSTRAINT unique_user_mode_rating UNIQUE(user_id, game_mode),
                                CONSTRAINT valid_rating CHECK (rating >= 0 AND rating <= 4000)
);

-- Indexes for ratings
CREATE INDEX idx_player_ratings_user ON player_ratings(user_id);
CREATE INDEX idx_player_ratings_leaderboard ON player_ratings(game_mode, rating DESC);
CREATE INDEX idx_player_ratings_active ON player_ratings(game_mode, rating DESC)
    WHERE last_game_at > CURRENT_DATE - INTERVAL '30 days';

-- Player statistics table
CREATE TABLE player_statistics (
                                   user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
                                   total_games_played INTEGER DEFAULT 0,
                                   total_games_won INTEGER DEFAULT 0,
                                   total_games_drawn INTEGER DEFAULT 0,
                                   total_score_earned BIGINT DEFAULT 0,
                                   highest_game_score INTEGER DEFAULT 0,
                                   highest_word_score INTEGER DEFAULT 0,
                                   highest_word VARCHAR(15),
                                   total_words_played INTEGER DEFAULT 0,
                                   total_bingos INTEGER DEFAULT 0, -- 7-letter words
                                   total_exchanges INTEGER DEFAULT 0,
                                   total_challenges_made INTEGER DEFAULT 0,
                                   total_challenges_won INTEGER DEFAULT 0,
                                   avg_score_per_game DECIMAL(10,2) GENERATED ALWAYS AS (
                                       CASE WHEN total_games_played > 0
                                                THEN total_score_earned::DECIMAL / total_games_played
                                            ELSE 0 END
                                       ) STORED,
                                   avg_move_time_seconds INTEGER,
                                   fastest_game_time_seconds INTEGER,
                                   favorite_opening_word VARCHAR(15),
                                   unique_words_played INTEGER DEFAULT 0,
                                   total_time_played_seconds BIGINT DEFAULT 0,
                                   created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
                                   updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for statistics
CREATE INDEX idx_player_stats_score ON player_statistics(total_score_earned DESC);
CREATE INDEX idx_player_stats_games ON player_statistics(total_games_played DESC);
CREATE INDEX idx_player_stats_bingos ON player_statistics(total_bingos DESC);

-- Game statistics table (per-game analytics)
CREATE TABLE game_statistics (
                                 game_id UUID PRIMARY KEY REFERENCES games(id) ON DELETE CASCADE,
                                 total_moves INTEGER DEFAULT 0,
                                 total_score INTEGER DEFAULT 0,
                                 highest_move_score INTEGER DEFAULT 0,
                                 highest_move_word VARCHAR(15),
                                 total_bingos INTEGER DEFAULT 0,
                                 total_exchanges INTEGER DEFAULT 0,
                                 total_challenges INTEGER DEFAULT 0,
                                 tiles_remaining INTEGER DEFAULT 0,
                                 game_duration_seconds INTEGER,
                                 avg_move_time_seconds DECIMAL(10,2),
                                 first_move_word VARCHAR(15),
                                 final_board_coverage DECIMAL(5,2), -- Percentage of board filled
                                 created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Word statistics table (track popular/high-scoring words)
CREATE TABLE word_statistics (
                                 id BIGSERIAL PRIMARY KEY,
                                 word VARCHAR(15) NOT NULL,
                                 dictionary_id INTEGER REFERENCES dictionaries(id),
                                 times_played INTEGER DEFAULT 1,
                                 total_score_earned BIGINT DEFAULT 0,
                                 avg_score DECIMAL(10,2) GENERATED ALWAYS AS (
                                     CASE WHEN times_played > 0
                                              THEN total_score_earned::DECIMAL / times_played
                                          ELSE 0 END
                                     ) STORED,
                                 highest_score INTEGER DEFAULT 0,
                                 is_bingo BOOLEAN DEFAULT false,
                                 last_played_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    -- Constraints
                                 CONSTRAINT unique_word_dict UNIQUE(word, dictionary_id)
);

-- Indexes for word statistics
CREATE INDEX idx_word_stats_popular ON word_statistics(times_played DESC);
CREATE INDEX idx_word_stats_score ON word_statistics(avg_score DESC);
CREATE INDEX idx_word_stats_bingo ON word_statistics(is_bingo, times_played DESC) WHERE is_bingo = true;

-- Achievements definition table
CREATE TABLE achievements (
                              id SERIAL PRIMARY KEY,
                              code VARCHAR(50) UNIQUE NOT NULL,
                              name VARCHAR(100) NOT NULL,
                              description TEXT,
                              category VARCHAR(50), -- 'milestone', 'skill', 'special', 'daily'
                              icon_url VARCHAR(500),
                              points INTEGER DEFAULT 10,
                              requirement_type VARCHAR(50), -- 'games_won', 'score_threshold', 'word_played', etc.
                              requirement_value INTEGER,
                              requirement_data JSONB, -- Flexible additional requirements
                              is_hidden BOOLEAN DEFAULT false,
                              display_order INTEGER DEFAULT 0,
                              created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Insert sample achievements
INSERT INTO achievements (code, name, description, category, points, requirement_type, requirement_value) VALUES
                                                                                                              ('first_win', 'First Victory', 'Win your first game', 'milestone', 10, 'games_won', 1),
                                                                                                              ('win_10', 'Consistent Winner', 'Win 10 games', 'milestone', 25, 'games_won', 10),
                                                                                                              ('win_100', 'Century Club', 'Win 100 games', 'milestone', 100, 'games_won', 100),
                                                                                                              ('bingo_first', 'Bingo!', 'Play your first 7-letter word', 'skill', 20, 'bingos', 1),
                                                                                                              ('bingo_master', 'Bingo Master', 'Play 100 bingos', 'skill', 100, 'bingos', 100),
                                                                                                              ('high_score_300', 'High Scorer', 'Score 300+ points in a game', 'skill', 30, 'game_score', 300),
                                                                                                              ('high_score_500', 'Elite Scorer', 'Score 500+ points in a game', 'skill', 50, 'game_score', 500),
                                                                                                              ('word_value_50', 'Big Word', 'Play a word worth 50+ points', 'skill', 25, 'word_score', 50),
                                                                                                              ('word_value_100', 'Massive Word', 'Play a word worth 100+ points', 'skill', 50, 'word_score', 100),
                                                                                                              ('perfect_game', 'Perfectionist', 'Win a game without exchanging tiles', 'special', 40, 'perfect_game', 1),
                                                                                                              ('comeback_king', 'Comeback King', 'Win after being down by 100+ points', 'special', 50, 'comeback', 100),
                                                                                                              ('speed_demon', 'Speed Demon', 'Win a game in under 5 minutes', 'special', 30, 'fast_game', 300);

-- Player achievements junction table
CREATE TABLE player_achievements (
                                     id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
                                     user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                                     achievement_id INTEGER NOT NULL REFERENCES achievements(id),
                                     game_id UUID REFERENCES games(id), -- Which game unlocked it
                                     unlocked_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
                                     progress INTEGER DEFAULT 0, -- For progressive achievements

    -- Constraints
                                     CONSTRAINT unique_user_achievement UNIQUE(user_id, achievement_id)
);

-- Indexes for achievements
CREATE INDEX idx_player_achievements_user ON player_achievements(user_id, unlocked_at DESC);
CREATE INDEX idx_player_achievements_recent ON player_achievements(unlocked_at DESC);

-- Daily challenges table
CREATE TABLE daily_challenges (
                                  id SERIAL PRIMARY KEY,
                                  challenge_date DATE UNIQUE NOT NULL,
                                  board_setup JSONB NOT NULL, -- Pre-configured board state
                                  target_score INTEGER,
                                  rack_tiles JSONB NOT NULL,
                                  dictionary_id INTEGER REFERENCES dictionaries(id),
                                  solution_moves JSONB, -- Optimal solution
                                  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Daily challenge attempts
CREATE TABLE daily_challenge_attempts (
                                          id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
                                          challenge_id INTEGER NOT NULL REFERENCES daily_challenges(id),
                                          user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                                          score_achieved INTEGER NOT NULL,
                                          moves_made JSONB NOT NULL,
                                          time_taken_seconds INTEGER,
                                          completed_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    -- Constraints
                                          CONSTRAINT unique_daily_attempt UNIQUE(challenge_id, user_id)
);

-- Indexes for daily challenges
CREATE INDEX idx_daily_challenges_date ON daily_challenges(challenge_date DESC);
CREATE INDEX idx_challenge_attempts_user ON daily_challenge_attempts(user_id, challenge_id);
CREATE INDEX idx_challenge_attempts_score ON daily_challenge_attempts(challenge_id, score_achieved DESC);

-- Materialized view for leaderboards
CREATE MATERIALIZED VIEW mv_leaderboard AS
SELECT
    pr.user_id,
    u.username,
    u.display_name,
    u.avatar_url,
    pr.game_mode,
    pr.rating,
    pr.games_played,
    pr.games_won,
    ROUND((pr.games_won::DECIMAL / NULLIF(pr.games_played, 0) * 100), 2) as win_percentage,
    pr.best_win_streak,
    ps.highest_game_score,
    ps.total_bingos,
    ROW_NUMBER() OVER (PARTITION BY pr.game_mode ORDER BY pr.rating DESC) as rank
FROM player_ratings pr
         JOIN users u ON pr.user_id = u.id
         LEFT JOIN player_statistics ps ON pr.user_id = ps.user_id
WHERE pr.games_played >= 10 -- Minimum games for leaderboard
  AND pr.last_game_at > CURRENT_DATE - INTERVAL '30 days'; -- Active players only

-- Indexes for leaderboard
CREATE UNIQUE INDEX idx_mv_leaderboard_unique ON mv_leaderboard(user_id, game_mode);
CREATE INDEX idx_mv_leaderboard_rank ON mv_leaderboard(game_mode, rank);

-- Function to update player statistics after game
CREATE OR REPLACE FUNCTION update_player_statistics_after_game(
    p_game_id UUID
) RETURNS void AS $$
DECLARE
    v_game_record RECORD;
    v_player_record RECORD;
BEGIN
    -- Get game details
    SELECT * INTO v_game_record FROM games WHERE id = p_game_id;

    -- Update statistics for each player
    FOR v_player_record IN
        SELECT gp.*, g.status, g.winner_id
        FROM game_players gp
                 JOIN games g ON gp.game_id = g.id
        WHERE gp.game_id = p_game_id AND gp.user_id IS NOT NULL
        LOOP
            -- Update player statistics
            INSERT INTO player_statistics (user_id, total_games_played, total_games_won)
            VALUES (v_player_record.user_id, 1,
                    CASE WHEN v_player_record.user_id = v_game_record.winner_id THEN 1 ELSE 0 END)
            ON CONFLICT (user_id) DO UPDATE
                SET total_games_played = player_statistics.total_games_played + 1,
                    total_games_won = player_statistics.total_games_won +
                                      CASE WHEN v_player_record.user_id = v_game_record.winner_id THEN 1 ELSE 0 END,
                    total_score_earned = player_statistics.total_score_earned + v_player_record.score,
                    highest_game_score = GREATEST(player_statistics.highest_game_score, v_player_record.score),
                    updated_at = CURRENT_TIMESTAMP;

            -- Update ratings (simplified ELO calculation)
            PERFORM update_player_rating(
                    v_player_record.user_id,
                    v_game_record.mode,
                    v_player_record.result
                    );
        END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Function to check and award achievements
CREATE OR REPLACE FUNCTION check_achievements(
    p_user_id UUID,
    p_game_id UUID
) RETURNS TABLE(achievement_id INTEGER, achievement_name VARCHAR) AS $$
DECLARE
    v_achievement RECORD;
    v_stats RECORD;
BEGIN
    -- Get current player statistics
    SELECT * INTO v_stats FROM player_statistics WHERE user_id = p_user_id;

    -- Check each achievement
    FOR v_achievement IN SELECT * FROM achievements WHERE is_hidden = false
        LOOP
            -- Check if already unlocked
            IF NOT EXISTS (
                SELECT 1 FROM player_achievements
                WHERE user_id = p_user_id AND achievement_id = v_achievement.id
            ) THEN
                -- Check requirement based on type
                IF (v_achievement.requirement_type = 'games_won'
                    AND v_stats.total_games_won >= v_achievement.requirement_value) OR
                   (v_achievement.requirement_type = 'bingos'
                       AND v_stats.total_bingos >= v_achievement.requirement_value) THEN

                    -- Award achievement
                    INSERT INTO player_achievements (user_id, achievement_id, game_id)
                    VALUES (p_user_id, v_achievement.id, p_game_id);

                    RETURN QUERY SELECT v_achievement.id, v_achievement.name;
                END IF;
            END IF;
        END LOOP;
END;
$$ LANGUAGE plpgsql;

-- Scheduled refresh for materialized views
CREATE OR REPLACE FUNCTION refresh_materialized_views() RETURNS void AS $$
BEGIN
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_leaderboard;
    REFRESH MATERIALIZED VIEW CONCURRENTLY mv_two_letter_words;
END;
$$ LANGUAGE plpgsql;

-- Comments
COMMENT ON TABLE player_ratings IS 'ELO ratings for each game mode';
COMMENT ON TABLE player_statistics IS 'Cumulative player statistics';
COMMENT ON TABLE game_statistics IS 'Per-game statistical analysis';
COMMENT ON TABLE word_statistics IS 'Global word usage statistics';
COMMENT ON TABLE achievements IS 'Achievement definitions';
COMMENT ON TABLE player_achievements IS 'Unlocked achievements per player';
COMMENT ON TABLE daily_challenges IS 'Daily puzzle challenges';
COMMENT ON MATERIALIZED VIEW mv_leaderboard IS 'Cached leaderboard data';