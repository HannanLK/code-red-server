-- Migration: 002_create_games_core.sql
-- Description: Core game tables with performance optimizations

-- Ensure required extensions when running out of order
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Create custom types
CREATE TYPE game_status AS ENUM ('waiting', 'active', 'paused', 'completed', 'abandoned');
CREATE TYPE game_mode AS ENUM ('classic', 'timed', 'challenge', 'practice');
CREATE TYPE player_type AS ENUM ('human', 'bot');
CREATE TYPE game_result AS ENUM ('win', 'loss', 'draw', 'timeout', 'forfeit');

-- Main games table
CREATE TABLE games (
                       id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
                       room_code VARCHAR(10) UNIQUE,
                       status game_status DEFAULT 'waiting',
                       mode game_mode DEFAULT 'classic',
                       dictionary_id INTEGER NOT NULL,
                       board_size INTEGER DEFAULT 15,
                       time_control_seconds INTEGER DEFAULT 600, -- 10 minutes per player
                       is_rated BOOLEAN DEFAULT false,
                       winner_id UUID,
                       final_scores JSONB,
                       metadata JSONB DEFAULT '{}',
                       started_at TIMESTAMP WITH TIME ZONE,
                       ended_at TIMESTAMP WITH TIME ZONE,
                       created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
                       updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    -- Constraints
                       CONSTRAINT valid_board_size CHECK (board_size IN (11, 13, 15, 17)),
                       CONSTRAINT valid_time_control CHECK (time_control_seconds >= 60)
);

-- Indexes for games
CREATE INDEX idx_games_status ON games(status);
CREATE INDEX idx_games_status_active ON games(id) WHERE status IN ('active', 'waiting');
CREATE INDEX idx_games_room_code ON games(room_code) WHERE room_code IS NOT NULL;
CREATE INDEX idx_games_created_at ON games(created_at DESC);
CREATE INDEX idx_games_is_rated ON games(is_rated, status) WHERE is_rated = true;

-- Game players junction table
CREATE TABLE game_players (
                              id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
                              game_id UUID NOT NULL REFERENCES games(id) ON DELETE CASCADE,
                              user_id UUID REFERENCES users(id) ON DELETE SET NULL,
                              bot_id UUID,
                              player_type player_type NOT NULL,
                              player_order INTEGER NOT NULL CHECK (player_order IN (1, 2)),
                              rack_tiles JSONB DEFAULT '[]',
                              score INTEGER DEFAULT 0,
                              time_remaining_ms INTEGER,
                              is_current_turn BOOLEAN DEFAULT false,
                              result game_result,
                              rating_change INTEGER,
                              joined_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
                              last_action_at TIMESTAMP WITH TIME ZONE,

    -- Constraints
                              CONSTRAINT unique_game_player UNIQUE(game_id, player_order),
                              CONSTRAINT unique_game_user UNIQUE(game_id, user_id),
                              CONSTRAINT player_type_check CHECK (
                                  (player_type = 'human' AND user_id IS NOT NULL) OR
                                  (player_type = 'bot' AND bot_id IS NOT NULL)
                                  )
);

-- Indexes for game_players
CREATE INDEX idx_game_players_game_id ON game_players(game_id);
CREATE INDEX idx_game_players_user_id ON game_players(user_id);
CREATE INDEX idx_game_players_current_turn ON game_players(game_id, is_current_turn) WHERE is_current_turn = true;
CREATE INDEX idx_game_players_active_games ON game_players(user_id, joined_at DESC);

-- Game states table (stores complete game state snapshots)
CREATE TABLE game_states (
                             id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
                             game_id UUID NOT NULL REFERENCES games(id) ON DELETE CASCADE,
                             move_number INTEGER NOT NULL DEFAULT 0,
                             board_state JSONB NOT NULL, -- 2D array of tiles
                             tile_bag JSONB NOT NULL, -- Remaining tiles
                             player_racks JSONB NOT NULL, -- Array of player racks
                             scores JSONB NOT NULL, -- Current scores
                             current_player_id UUID,
                             consecutive_passes INTEGER DEFAULT 0,
                             last_played_word VARCHAR(255),
                             state_hash VARCHAR(64), -- For state validation
                             created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    -- Constraints
                             CONSTRAINT unique_game_move UNIQUE(game_id, move_number)
);

-- Indexes for game_states
CREATE INDEX idx_game_states_game_id ON game_states(game_id);
CREATE INDEX idx_game_states_latest ON game_states(game_id, move_number DESC);
-- GIN index for JSONB board state queries
CREATE INDEX idx_game_states_board_gin ON game_states USING gin (board_state);

-- Partitioned game moves table for scalability
CREATE TABLE game_moves (
                            id UUID DEFAULT uuid_generate_v4(),
                            game_id UUID NOT NULL,
                            player_id UUID NOT NULL,
                            move_number INTEGER NOT NULL,
                            move_type VARCHAR(20) NOT NULL, -- 'play', 'exchange', 'pass', 'challenge'
                            start_position VARCHAR(3), -- e.g., 'H8'
                            direction CHAR(1), -- 'H' or 'V'
                            word_played VARCHAR(255),
                            tiles_played JSONB, -- Array of {letter, position, isBlank}
                            tiles_exchanged JSONB, -- For exchange moves
                            score_earned INTEGER DEFAULT 0,
                            words_formed JSONB, -- All words formed by this move
                            is_bingo BOOLEAN DEFAULT false, -- Used all 7 tiles
                            time_taken_ms INTEGER,
                            challenge_result VARCHAR(20), -- 'successful', 'failed', null
                            move_notation VARCHAR(100), -- Standard Scrabble notation
                            created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

                            PRIMARY KEY (game_id, move_number, created_at)
) PARTITION BY RANGE (created_at);

-- Create monthly partitions for game_moves
CREATE TABLE game_moves_2024_01 PARTITION OF game_moves
    FOR VALUES FROM ('2024-01-01') TO ('2024-02-01');

-- Index for partitioned table
CREATE INDEX idx_game_moves_game_id ON game_moves(game_id);
CREATE INDEX idx_game_moves_player_id ON game_moves(player_id);
CREATE INDEX idx_game_moves_word ON game_moves(word_played) WHERE word_played IS NOT NULL;
CREATE INDEX idx_game_moves_bingo ON game_moves(game_id) WHERE is_bingo = true;

-- Game timers table (for accurate time tracking)
CREATE TABLE game_timers (
                             game_id UUID PRIMARY KEY REFERENCES games(id) ON DELETE CASCADE,
                             player1_time_ms INTEGER NOT NULL,
                             player2_time_ms INTEGER NOT NULL,
                             last_timer_update TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
                             timer_paused BOOLEAN DEFAULT false,
                             current_turn_started_at TIMESTAMP WITH TIME ZONE
);

CREATE INDEX idx_game_timers_active ON game_timers(game_id, timer_paused) WHERE timer_paused = false;

-- Lobby queue table
CREATE TABLE lobby_queue (
                             id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
                             user_id UUID REFERENCES users(id) ON DELETE CASCADE,
                             game_mode game_mode NOT NULL,
                             rating_range INT4RANGE,
                             preferred_time_control INTEGER,
                             joined_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
                             expires_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP + INTERVAL '5 minutes',
                             matched_game_id UUID REFERENCES games(id) ON DELETE SET NULL,
                             is_active BOOLEAN DEFAULT true
);

-- Indexes for lobby
CREATE INDEX idx_lobby_queue_active ON lobby_queue(game_mode, is_active, joined_at) WHERE is_active = true;
CREATE INDEX idx_lobby_queue_user ON lobby_queue(user_id) WHERE is_active = true;
CREATE INDEX idx_lobby_queue_expires ON lobby_queue(expires_at) WHERE is_active = true;

-- Function to generate room codes
CREATE OR REPLACE FUNCTION generate_room_code() RETURNS VARCHAR(10) AS $$
DECLARE
    chars TEXT := 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    result VARCHAR(10) := '';
    i INTEGER;
BEGIN
    FOR i IN 1..6 LOOP
            result := result || substr(chars, floor(random() * length(chars) + 1)::integer, 1);
        END LOOP;
    RETURN result;
END;
$$ LANGUAGE plpgsql;

-- Trigger to set room code
CREATE OR REPLACE FUNCTION set_room_code() RETURNS TRIGGER AS $$
BEGIN
    IF NEW.room_code IS NULL THEN
        NEW.room_code := generate_room_code();
    END IF;
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER set_game_room_code BEFORE INSERT ON games
    FOR EACH ROW EXECUTE FUNCTION set_room_code();

-- Comments
COMMENT ON TABLE games IS 'Main game instances table';
COMMENT ON TABLE game_players IS 'Players participating in games';
COMMENT ON TABLE game_states IS 'Complete game state snapshots for each move';
COMMENT ON TABLE game_moves IS 'Partitioned table storing all game moves';
COMMENT ON TABLE game_timers IS 'Accurate server-side game timers';
COMMENT ON TABLE lobby_queue IS 'Matchmaking queue for players';
COMMENT ON COLUMN game_states.state_hash IS 'SHA-256 hash of game state for validation';
COMMENT ON COLUMN game_moves.is_bingo IS 'True if player used all 7 tiles in one move';