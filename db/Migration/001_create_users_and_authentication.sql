-- Migration: 001_create_users_and_authentication.sql
-- Description: User management and authentication tables

-- Enable required extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";
CREATE EXTENSION IF NOT EXISTS "pgcrypto";
CREATE EXTENSION IF NOT EXISTS "citext";

-- Create custom types
CREATE TYPE user_status AS ENUM ('active', 'inactive', 'banned', 'suspended');
CREATE TYPE auth_provider AS ENUM ('local', 'google', 'facebook', 'guest');

-- Users table
CREATE TABLE users (
                       id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
                       username CITEXT UNIQUE NOT NULL,
                       email CITEXT UNIQUE NOT NULL,
                       password_hash VARCHAR(255),
                       display_name VARCHAR(100) NOT NULL,
                       avatar_url VARCHAR(500),
                       auth_provider auth_provider DEFAULT 'local',
                       status user_status DEFAULT 'active',
                       last_seen_at TIMESTAMP WITH TIME ZONE,
                       created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
                       updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    -- Constraints
                       CONSTRAINT username_length CHECK (LENGTH(username) BETWEEN 3 AND 30),
                       CONSTRAINT email_valid CHECK (email ~* '^[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}$')
);

-- Indexes for users
CREATE INDEX idx_users_username ON users(username);
CREATE INDEX idx_users_email ON users(email);
CREATE INDEX idx_users_status ON users(status) WHERE status = 'active';
CREATE INDEX idx_users_last_seen ON users(last_seen_at DESC);

-- User sessions table
CREATE TABLE user_sessions (
                               id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
                               user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                               token_hash VARCHAR(255) UNIQUE NOT NULL,
                               ip_address INET,
                               user_agent TEXT,
                               expires_at TIMESTAMP WITH TIME ZONE NOT NULL,
                               created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
                               last_activity TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
                               is_active BOOLEAN DEFAULT true
);

-- Indexes for sessions
CREATE INDEX idx_sessions_user_id ON user_sessions(user_id);
CREATE INDEX idx_sessions_token ON user_sessions(token_hash);
CREATE INDEX idx_sessions_expires ON user_sessions(expires_at) WHERE is_active = true;
CREATE INDEX idx_sessions_active_user ON user_sessions(user_id, is_active) WHERE is_active = true;

-- User preferences table
CREATE TABLE user_preferences (
                                  user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
                                  theme VARCHAR(20) DEFAULT 'light',
                                  sound_enabled BOOLEAN DEFAULT true,
                                  notifications_enabled BOOLEAN DEFAULT true,
                                  auto_sort_tiles BOOLEAN DEFAULT false,
                                  show_word_definitions BOOLEAN DEFAULT true,
                                  preferred_dictionary VARCHAR(20) DEFAULT 'TWL',
                                  preferred_time_control INTEGER DEFAULT 600, -- seconds
                                  language_code VARCHAR(5) DEFAULT 'en',
                                  settings JSONB DEFAULT '{}', -- Additional flexible settings
                                  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
                                  updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Guest users table (for anonymous play)
CREATE TABLE guest_users (
                             id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
                             session_id VARCHAR(255) UNIQUE NOT NULL,
                             display_name VARCHAR(100),
                             ip_address INET,
                             created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
                             expires_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP + INTERVAL '24 hours'
);

CREATE INDEX idx_guest_users_session ON guest_users(session_id);
CREATE INDEX idx_guest_users_expires ON guest_users(expires_at);

-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION update_updated_at_column()
    RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = CURRENT_TIMESTAMP;
    RETURN NEW;
END;
$$ language 'plpgsql';

-- Triggers for updated_at
CREATE TRIGGER update_users_updated_at BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

CREATE TRIGGER update_user_preferences_updated_at BEFORE UPDATE ON user_preferences
    FOR EACH ROW EXECUTE FUNCTION update_updated_at_column();

-- Function to clean expired sessions
CREATE OR REPLACE FUNCTION clean_expired_sessions() RETURNS void AS $$
BEGIN
    DELETE FROM user_sessions WHERE expires_at < CURRENT_TIMESTAMP;
    DELETE FROM guest_users WHERE expires_at < CURRENT_TIMESTAMP;
END;
$$ LANGUAGE plpgsql;

-- Comments
COMMENT ON TABLE users IS 'Main user accounts table';
COMMENT ON TABLE user_sessions IS 'Active user sessions for authentication';
COMMENT ON TABLE user_preferences IS 'User game preferences and settings';
COMMENT ON TABLE guest_users IS 'Temporary guest user sessions';
COMMENT ON COLUMN users.password_hash IS 'Bcrypt hashed password for local auth';
COMMENT ON COLUMN user_preferences.settings IS 'Flexible JSONB field for additional settings';