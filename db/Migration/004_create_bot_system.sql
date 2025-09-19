-- Migration: 004_create_bot_system.sql
-- Description: Bot players and AI strategy configuration

-- Bot difficulty levels
CREATE TYPE bot_difficulty AS ENUM ('beginner', 'easy', 'medium', 'hard', 'expert', 'master');

-- Bot personalities for varied play styles
CREATE TYPE bot_personality AS ENUM (
    'aggressive',    -- High-scoring moves
    'defensive',     -- Blocks opponent opportunities
    'balanced',      -- Mix of offense and defense
    'teacher',       -- Plays good but not optimal moves
    'speedster',     -- Fast moves, less optimization
    'strategic'      -- Long-term planning
    );

-- Bots configuration table
CREATE TABLE bots (
                      id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
                      name VARCHAR(100) UNIQUE NOT NULL,
                      avatar_url VARCHAR(500),
                      difficulty bot_difficulty NOT NULL,
                      personality bot_personality DEFAULT 'balanced',
                      elo_rating INTEGER DEFAULT 1200,
                      think_time_ms INTEGER DEFAULT 3000, -- Base thinking time
                      mistake_probability DECIMAL(3,2) DEFAULT 0.00, -- 0-1 probability of suboptimal move
                      vocabulary_size VARCHAR(20), -- 'small', 'medium', 'large', 'complete'
                      is_active BOOLEAN DEFAULT true,
                      games_played INTEGER DEFAULT 0,
                      games_won INTEGER DEFAULT 0,
                      total_score_earned BIGINT DEFAULT 0,
                      avg_move_time_ms INTEGER,
                      created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
                      updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    -- Constraints
                      CONSTRAINT valid_mistake_prob CHECK (mistake_probability >= 0 AND mistake_probability <= 1),
                      CONSTRAINT valid_think_time CHECK (think_time_ms BETWEEN 500 AND 30000)
);

-- Insert default bots
INSERT INTO bots (name, difficulty, personality, elo_rating, think_time_ms, mistake_probability, vocabulary_size) VALUES
                                                                                                                      ('Beginner Bot', 'beginner', 'teacher', 800, 2000, 0.30, 'small'),
                                                                                                                      ('Casual Player', 'easy', 'balanced', 1000, 3000, 0.20, 'medium'),
                                                                                                                      ('Club Player', 'medium', 'balanced', 1400, 5000, 0.10, 'large'),
                                                                                                                      ('Tournament Player', 'hard', 'strategic', 1800, 8000, 0.05, 'complete'),
                                                                                                                      ('Expert Bot', 'expert', 'aggressive', 2200, 10000, 0.02, 'complete'),
                                                                                                                      ('Scrabble Master', 'master', 'strategic', 2500, 15000, 0.00, 'complete');

-- Bot strategy parameters
CREATE TABLE bot_strategies (
                                id SERIAL PRIMARY KEY,
                                bot_id UUID NOT NULL REFERENCES bots(id) ON DELETE CASCADE,
                                parameter_name VARCHAR(50) NOT NULL,
                                parameter_value DECIMAL(10,4),
                                description TEXT,

    -- Constraints
                                CONSTRAINT unique_bot_param UNIQUE(bot_id, parameter_name)
);

-- Default strategy parameters for bots
INSERT INTO bot_strategies (bot_id, parameter_name, parameter_value, description)
SELECT
    b.id,
    p.param_name,
    CASE
        WHEN b.difficulty = 'beginner' THEN p.beginner_value
        WHEN b.difficulty = 'easy' THEN p.easy_value
        WHEN b.difficulty = 'medium' THEN p.medium_value
        WHEN b.difficulty = 'hard' THEN p.hard_value
        WHEN b.difficulty = 'expert' THEN p.expert_value
        ELSE p.master_value
        END,
    p.description
FROM bots b
         CROSS JOIN (
    VALUES
        ('score_weight', 1.0, 2.0, 3.0, 4.0, 5.0, 5.0, 'Weight for immediate score'),
        ('rack_leave_weight', 0.0, 0.5, 1.0, 2.0, 3.0, 4.0, 'Weight for rack leave quality'),
        ('board_position_weight', 0.0, 0.5, 1.0, 2.0, 3.0, 4.0, 'Weight for board positioning'),
        ('blocking_weight', 0.0, 0.0, 1.0, 2.0, 3.0, 3.0, 'Weight for blocking opponent'),
        ('bingo_setup_weight', 0.0, 0.0, 1.0, 2.0, 3.0, 4.0, 'Weight for 7-letter word setup'),
        ('endgame_weight', 1.0, 1.0, 2.0, 3.0, 4.0, 5.0, 'Weight adjustment for endgame'),
        ('volatility_preference', 0.5, 0.4, 0.3, 0.2, 0.1, 0.0, 'Preference for safe vs risky plays'),
        ('exchange_threshold', 0.0, 10.0, 15.0, 20.0, 25.0, 30.0, 'Min point deficit to consider exchange'),
        ('lookahead_depth', 0, 0, 1, 2, 2, 3, 'Number of moves to look ahead')
) AS p(param_name, beginner_value, easy_value, medium_value, hard_value, expert_value, master_value, description);

-- Bot vocabulary restrictions (which words bots can use)
CREATE TABLE bot_vocabularies (
                                  id SERIAL PRIMARY KEY,
                                  bot_id UUID NOT NULL REFERENCES bots(id) ON DELETE CASCADE,
                                  dictionary_id INTEGER NOT NULL REFERENCES dictionaries(id),
                                  max_word_length INTEGER,
                                  min_word_frequency INTEGER, -- Only use common words for easier bots
                                  excluded_words TEXT[], -- Words this bot won't use
                                  included_words TEXT[], -- Additional words this bot knows

    -- Constraints
                                  CONSTRAINT unique_bot_dictionary UNIQUE(bot_id, dictionary_id)
);

-- Bot move evaluation history (for learning/debugging)
CREATE TABLE bot_move_evaluations (
                                      id BIGSERIAL PRIMARY KEY,
                                      game_id UUID NOT NULL,
                                      bot_id UUID NOT NULL REFERENCES bots(id),
                                      move_number INTEGER NOT NULL,
                                      evaluated_moves JSONB NOT NULL, -- Array of possible moves with scores
                                      selected_move JSONB NOT NULL, -- The chosen move
                                      evaluation_time_ms INTEGER,
                                      was_optimal BOOLEAN,
                                      created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for bot move evaluations
CREATE INDEX idx_bot_evaluations_game ON bot_move_evaluations(game_id);
CREATE INDEX idx_bot_evaluations_bot ON bot_move_evaluations(bot_id, created_at DESC);
CREATE INDEX idx_bot_evaluations_optimal ON bot_move_evaluations(bot_id, was_optimal) WHERE was_optimal = false;

-- Bot availability tracker (for concurrent games)
CREATE TABLE bot_availability (
                                  bot_id UUID PRIMARY KEY REFERENCES bots(id) ON DELETE CASCADE,
                                  current_games INTEGER DEFAULT 0,
                                  max_concurrent_games INTEGER DEFAULT 10,
                                  is_available BOOLEAN GENERATED ALWAYS AS (current_games < max_concurrent_games) STORED,
                                  last_game_started TIMESTAMP WITH TIME ZONE,
                                  updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Insert availability records for all bots
INSERT INTO bot_availability (bot_id, max_concurrent_games)
SELECT id,
       CASE
           WHEN difficulty IN ('beginner', 'easy') THEN 50
           WHEN difficulty IN ('medium', 'hard') THEN 20
           ELSE 10
           END
FROM bots;

-- Indexes for bot availability
CREATE INDEX idx_bot_availability ON bot_availability(is_available, bot_id) WHERE is_available = true;

-- Bot opening book (pre-computed good opening moves)
CREATE TABLE bot_opening_book (
                                  id SERIAL PRIMARY KEY,
                                  dictionary_id INTEGER NOT NULL REFERENCES dictionaries(id),
                                  board_pattern_hash VARCHAR(64) NOT NULL, -- Hash of board state
                                  recommended_moves JSONB NOT NULL, -- Array of good moves
                                  move_scores JSONB NOT NULL, -- Evaluation scores
                                  usage_count INTEGER DEFAULT 0,
                                  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    -- Constraints
                                  CONSTRAINT unique_opening UNIQUE(dictionary_id, board_pattern_hash)
);

-- Indexes for opening book
CREATE INDEX idx_opening_book_hash ON bot_opening_book(dictionary_id, board_pattern_hash);
CREATE INDEX idx_opening_book_usage ON bot_opening_book(usage_count DESC);

-- Bot endgame tablebase (pre-computed endgame positions)
CREATE TABLE bot_endgame_tablebase (
                                       id SERIAL UNIQUE,
                                       position_hash VARCHAR(64) PRIMARY KEY,
                                       tiles_remaining INTEGER NOT NULL,
                                       best_move JSONB NOT NULL,
                                       evaluation_score INTEGER NOT NULL,
                                       is_winning BOOLEAN,
                                       created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Index for endgame lookups
CREATE INDEX idx_endgame_tiles ON bot_endgame_tablebase(tiles_remaining);
CREATE INDEX idx_endgame_winning ON bot_endgame_tablebase(is_winning, tiles_remaining);

-- Function to get available bot for matchmaking
CREATE OR REPLACE FUNCTION get_available_bot(
    p_difficulty bot_difficulty DEFAULT NULL,
    p_personality bot_personality DEFAULT NULL
) RETURNS UUID AS $$
DECLARE
    v_bot_id UUID;
BEGIN
    -- Update availability based on completed games
    UPDATE bot_availability ba
    SET current_games = (
        SELECT COUNT(*)
        FROM game_players gp
                 JOIN games g ON gp.game_id = g.id
        WHERE gp.bot_id = ba.bot_id
          AND g.status IN ('waiting', 'active')
    );

    -- Select available bot
    SELECT b.id INTO v_bot_id
    FROM bots b
             JOIN bot_availability ba ON b.id = ba.bot_id
    WHERE b.is_active = true
      AND ba.is_available = true
      AND (p_difficulty IS NULL OR b.difficulty = p_difficulty)
      AND (p_personality IS NULL OR b.personality = p_personality)
    ORDER BY ba.current_games ASC, RANDOM()
    LIMIT 1;

    IF v_bot_id IS NOT NULL THEN
        -- Increment current games count
        UPDATE bot_availability
        SET current_games = current_games + 1,
            last_game_started = CURRENT_TIMESTAMP
        WHERE bot_id = v_bot_id;
    END IF;

    RETURN v_bot_id;
END;
$$ LANGUAGE plpgsql;

-- Function to calculate bot move with strategy parameters
CREATE OR REPLACE FUNCTION calculate_bot_move(
    p_bot_id UUID,
    p_game_state JSONB,
    p_time_limit_ms INTEGER DEFAULT 30000
) RETURNS JSONB AS $$
DECLARE
    v_strategy RECORD;
    v_move JSONB;
BEGIN
    -- Get bot strategy parameters
    SELECT
        MAX(CASE WHEN parameter_name = 'score_weight' THEN parameter_value END) as score_weight,
        MAX(CASE WHEN parameter_name = 'rack_leave_weight' THEN parameter_value END) as rack_weight,
        MAX(CASE WHEN parameter_name = 'board_position_weight' THEN parameter_value END) as position_weight,
        MAX(CASE WHEN parameter_name = 'blocking_weight' THEN parameter_value END) as blocking_weight
    INTO v_strategy
    FROM bot_strategies
    WHERE bot_id = p_bot_id;

    -- Complex move calculation logic would go here
    -- This is a placeholder for the actual implementation
    v_move := jsonb_build_object(
            'move_type', 'play',
            'word', 'EXAMPLE',
            'position', 'H8',
            'direction', 'H',
            'score', 24
              );

    RETURN v_move;
END;
$$ LANGUAGE plpgsql;

-- Comments
COMMENT ON TABLE bots IS 'AI bot players with different difficulties and personalities';
COMMENT ON TABLE bot_strategies IS 'Configurable strategy parameters for each bot';
COMMENT ON TABLE bot_vocabularies IS 'Word restrictions for different bot difficulties';
COMMENT ON TABLE bot_move_evaluations IS 'History of bot move evaluations for analysis';
COMMENT ON TABLE bot_availability IS 'Tracks bot availability for concurrent games';
COMMENT ON TABLE bot_opening_book IS 'Pre-computed opening moves for faster bot response';
COMMENT ON TABLE bot_endgame_tablebase IS 'Pre-computed endgame positions';
COMMENT ON FUNCTION get_available_bot IS 'Get an available bot for matchmaking';
COMMENT ON FUNCTION calculate_bot_move IS 'Calculate optimal move for bot player';