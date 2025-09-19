-- Migration: 003_create_dictionary_system.sql
-- Description: Dictionary and word validation system with optimized lookups

-- Dictionaries metadata table
CREATE TABLE dictionaries (
                              id SERIAL PRIMARY KEY,
                              name VARCHAR(50) UNIQUE NOT NULL,
                              language_code VARCHAR(5) NOT NULL,
                              description TEXT,
                              word_count INTEGER DEFAULT 0,
                              version VARCHAR(20),
                              is_active BOOLEAN DEFAULT true,
                              created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
                              updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Insert default dictionaries
INSERT INTO dictionaries (name, language_code, description, version) VALUES
                                                                         ('TWL', 'en', 'Tournament Word List (North American)', '2024'),
                                                                         ('SOWPODS', 'en', 'Combined TWL and OSW (International)', '2024'),
                                                                         ('ENABLE', 'en', 'Enhanced North American Benchmark Lexicon', '2024'),
                                                                         ('ODS', 'fr', 'Officiel du Scrabble (French)', '2024');

-- Dictionary words table with optimized structure
CREATE TABLE dictionary_words (
                                  id BIGSERIAL PRIMARY KEY,
                                  dictionary_id INTEGER NOT NULL REFERENCES dictionaries(id) ON DELETE CASCADE,
                                  word VARCHAR(15) NOT NULL,
                                  word_length SMALLINT GENERATED ALWAYS AS (LENGTH(word)) STORED,
                                  word_pattern VARCHAR(15), -- Pattern for blank tiles (e.g., 'C*T' for CAT with blank)
                                  letter_frequency JSONB, -- {"A": 1, "C": 1, "T": 1}
                                  points_value SMALLINT, -- Base word value without multipliers
                                  is_valid BOOLEAN DEFAULT true,
                                  definition TEXT,

    -- Constraints
                                  CONSTRAINT unique_dictionary_word UNIQUE(dictionary_id, word),
                                  CONSTRAINT word_uppercase CHECK (word = UPPER(word)),
                                  CONSTRAINT valid_word_length CHECK (word_length BETWEEN 2 AND 15)
);

-- Highly optimized indexes for word lookups
CREATE INDEX idx_dictionary_words_lookup ON dictionary_words(dictionary_id, word);
CREATE INDEX idx_dictionary_words_length ON dictionary_words(dictionary_id, word_length);
CREATE INDEX idx_dictionary_words_pattern ON dictionary_words(dictionary_id, word_pattern) WHERE word_pattern IS NOT NULL;
-- Trigram index for partial matching
CREATE EXTENSION IF NOT EXISTS pg_trgm;
CREATE INDEX idx_dictionary_words_trgm ON dictionary_words USING gin (word gin_trgm_ops);
-- For prefix/suffix searches
CREATE INDEX idx_dictionary_words_prefix ON dictionary_words(dictionary_id, word text_pattern_ops);

-- Tile distributions table
CREATE TABLE tile_distributions (
                                    id SERIAL PRIMARY KEY,
                                    name VARCHAR(50) UNIQUE NOT NULL,
                                    language_code VARCHAR(5) NOT NULL,
                                    total_tiles INTEGER NOT NULL,
                                    distribution JSONB NOT NULL, -- {"A": {"count": 9, "points": 1}, ...}
                                    blank_tiles INTEGER DEFAULT 2,
                                    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Insert standard English tile distribution
INSERT INTO tile_distributions (name, language_code, total_tiles, distribution) VALUES
    ('Standard English', 'en', 100, '{
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
    }');

-- Common words cache for faster validation
CREATE TABLE word_validation_cache (
                                       id BIGSERIAL PRIMARY KEY,
                                       dictionary_id INTEGER NOT NULL REFERENCES dictionaries(id) ON DELETE CASCADE,
                                       word_hash VARCHAR(64) NOT NULL, -- SHA-256 of word for fast lookup
                                       word VARCHAR(15) NOT NULL,
                                       is_valid BOOLEAN NOT NULL,
                                       lookup_count INTEGER DEFAULT 1,
                                       last_accessed TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

                                       CONSTRAINT unique_cache_entry UNIQUE(dictionary_id, word_hash)
);

-- Indexes for cache
CREATE INDEX idx_word_cache_hash ON word_validation_cache(dictionary_id, word_hash);
CREATE INDEX idx_word_cache_frequent ON word_validation_cache(dictionary_id, lookup_count DESC);
CREATE INDEX idx_word_cache_lru ON word_validation_cache(last_accessed);

-- Board configuration table
CREATE TABLE board_configurations (
                                      id SERIAL PRIMARY KEY,
                                      name VARCHAR(50) UNIQUE NOT NULL,
                                      board_size INTEGER NOT NULL,
                                      premium_squares JSONB NOT NULL, -- {"8,8": "star", "1,1": "3W", ...}
                                      is_default BOOLEAN DEFAULT false,
                                      created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Insert standard 15x15 board configuration
INSERT INTO board_configurations (name, board_size, premium_squares, is_default) VALUES
    ('Standard 15x15', 15, '{
      "8,8": "star",
      "1,1": "3W", "1,8": "3W", "1,15": "3W",
      "8,1": "3W", "8,15": "3W",
      "15,1": "3W", "15,8": "3W", "15,15": "3W",
      "2,2": "2W", "3,3": "2W", "4,4": "2W", "5,5": "2W",
      "2,14": "2W", "3,13": "2W", "4,12": "2W", "5,11": "2W",
      "14,2": "2W", "13,3": "2W", "12,4": "2W", "11,5": "2W",
      "14,14": "2W", "13,13": "2W", "12,12": "2W", "11,11": "2W",
      "1,4": "2L", "1,12": "2L", "3,7": "2L", "3,9": "2L",
      "4,1": "2L", "4,8": "2L", "4,15": "2L",
      "7,3": "2L", "7,7": "2L", "7,9": "2L", "7,13": "2L",
      "8,4": "2L", "8,12": "2L", "9,3": "2L", "9,7": "2L", "9,9": "2L", "9,13": "2L",
      "12,1": "2L", "12,8": "2L", "12,15": "2L",
      "13,7": "2L", "13,9": "2L", "15,4": "2L", "15,12": "2L",
      "2,6": "3L", "2,10": "3L", "6,2": "3L", "6,6": "3L", "6,10": "3L", "6,14": "3L",
      "10,2": "3L", "10,6": "3L", "10,10": "3L", "10,14": "3L",
      "14,6": "3L", "14,10": "3L"
    }', true);

-- Function to validate words using Trie structure (stored procedure for performance)
CREATE OR REPLACE FUNCTION validate_word(
    p_word VARCHAR,
    p_dictionary_id INTEGER
) RETURNS BOOLEAN AS $$
DECLARE
    v_is_valid BOOLEAN;
    v_word_upper VARCHAR;
    v_hash VARCHAR;
BEGIN
    v_word_upper := UPPER(p_word);
    v_hash := encode(digest(v_word_upper, 'sha256'), 'hex');

    -- Check cache first
    SELECT is_valid INTO v_is_valid
    FROM word_validation_cache
    WHERE dictionary_id = p_dictionary_id AND word_hash = v_hash;

    IF FOUND THEN
        -- Update cache hit count
        UPDATE word_validation_cache
        SET lookup_count = lookup_count + 1,
            last_accessed = CURRENT_TIMESTAMP
        WHERE dictionary_id = p_dictionary_id AND word_hash = v_hash;
        RETURN v_is_valid;
    END IF;

    -- Not in cache, check main dictionary
    SELECT EXISTS(
        SELECT 1 FROM dictionary_words
        WHERE dictionary_id = p_dictionary_id
          AND word = v_word_upper
          AND is_valid = true
    ) INTO v_is_valid;

    -- Add to cache
    INSERT INTO word_validation_cache (dictionary_id, word_hash, word, is_valid)
    VALUES (p_dictionary_id, v_hash, v_word_upper, v_is_valid)
    ON CONFLICT (dictionary_id, word_hash) DO NOTHING;

    RETURN v_is_valid;
END;
$$ LANGUAGE plpgsql;

-- Function to find all valid words from a rack
CREATE OR REPLACE FUNCTION find_possible_words(
    p_rack VARCHAR[],
    p_dictionary_id INTEGER,
    p_min_length INTEGER DEFAULT 2
) RETURNS TABLE(word VARCHAR, points INTEGER) AS $$
BEGIN
    -- Implementation would use recursive CTE or custom algorithm
    -- This is a placeholder for the complex word generation logic
    RETURN QUERY
        SELECT dw.word, dw.points_value
        FROM dictionary_words dw
        WHERE dw.dictionary_id = p_dictionary_id
          AND dw.word_length >= p_min_length
        -- Complex matching logic here
        LIMIT 100;
END;
$$ LANGUAGE plpgsql;

-- Materialized view for common 2-letter words (for cross-word validation)
CREATE MATERIALIZED VIEW mv_two_letter_words AS
SELECT dictionary_id, word
FROM dictionary_words
WHERE word_length = 2 AND is_valid = true;

CREATE INDEX idx_mv_two_letter ON mv_two_letter_words(dictionary_id, word);

-- Comments
COMMENT ON TABLE dictionaries IS 'Available word dictionaries for different game modes';
COMMENT ON TABLE dictionary_words IS 'Complete word list for each dictionary';
COMMENT ON TABLE tile_distributions IS 'Tile sets for different languages';
COMMENT ON TABLE word_validation_cache IS 'LRU cache for frequent word lookups';
COMMENT ON TABLE board_configurations IS 'Different board layouts and premium squares';
COMMENT ON FUNCTION validate_word IS 'Fast word validation with caching';