-- Migration: 006_create_social_and_chat.sql
-- Description: Social features, chat, friends, and game replays

-- Friend relationships
CREATE TABLE friendships (
                             id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
                             requester_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                             addressee_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                             status VARCHAR(20) DEFAULT 'pending', -- 'pending', 'accepted', 'declined', 'blocked'
                             created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
                             updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    -- Constraints
                             CONSTRAINT unique_friendship UNIQUE(requester_id, addressee_id),
                             CONSTRAINT no_self_friend CHECK (requester_id != addressee_id)
);

-- Indexes for friendships
CREATE INDEX idx_friendships_requester ON friendships(requester_id, status);
CREATE INDEX idx_friendships_addressee ON friendships(addressee_id, status);
CREATE INDEX idx_friendships_accepted ON friendships(requester_id, addressee_id) WHERE status = 'accepted';

-- In-game chat messages
CREATE TABLE game_chat (
                           id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
                           game_id UUID NOT NULL REFERENCES games(id) ON DELETE CASCADE,
                           sender_id UUID NOT NULL REFERENCES users(id) ON DELETE SET NULL,
                           message TEXT NOT NULL,
                           message_type VARCHAR(20) DEFAULT 'text', -- 'text', 'emoji', 'system'
                           is_edited BOOLEAN DEFAULT false,
                           is_deleted BOOLEAN DEFAULT false,
                           created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
                           edited_at TIMESTAMP WITH TIME ZONE,

    -- Constraints
                           CONSTRAINT message_length CHECK (LENGTH(message) <= 500)
);

-- Indexes for chat
CREATE INDEX idx_game_chat_game ON game_chat(game_id, created_at);
CREATE INDEX idx_game_chat_sender ON game_chat(sender_id);
CREATE INDEX idx_game_chat_active ON game_chat(game_id, created_at) WHERE is_deleted = false;

-- Pre-defined chat messages (for quick chat)
CREATE TABLE quick_chat_messages (
                                     id SERIAL PRIMARY KEY,
                                     category VARCHAR(50), -- 'greeting', 'reaction', 'strategy', 'farewell'
                                     message TEXT NOT NULL,
                                     emoji VARCHAR(10),
                                     language_code VARCHAR(5) DEFAULT 'en',
                                     usage_count INTEGER DEFAULT 0,
                                     is_active BOOLEAN DEFAULT true
);

-- Insert default quick chat messages
INSERT INTO quick_chat_messages (category, message, emoji) VALUES
                                                               ('greeting', 'Good luck!', '🤞'),
                                                               ('greeting', 'Hi there!', '👋'),
                                                               ('greeting', 'Let''s play!', '🎮'),
                                                               ('reaction', 'Nice move!', '👏'),
                                                               ('reaction', 'Well played!', '👍'),
                                                               ('reaction', 'Wow!', '😮'),
                                                               ('reaction', 'Good word!', '💯'),
                                                               ('strategy', 'Interesting...', '🤔'),
                                                               ('strategy', 'I need to think...', '💭'),
                                                               ('farewell', 'Good game!', '🤝'),
                                                               ('farewell', 'Thanks for playing!', '😊'),
                                                               ('farewell', 'Rematch?', '🔄');

-- Game replays storage
CREATE TABLE game_replays (
                              game_id UUID PRIMARY KEY REFERENCES games(id) ON DELETE CASCADE,
                              replay_data JSONB NOT NULL, -- Complete move-by-move replay data
                              compressed_data BYTEA, -- Compressed version for storage efficiency
                              final_board_state JSONB NOT NULL,
                              total_moves INTEGER NOT NULL,
                              replay_version VARCHAR(10) DEFAULT '1.0',
                              is_public BOOLEAN DEFAULT true,
                              view_count INTEGER DEFAULT 0,
                              created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Indexes for replays
CREATE INDEX idx_game_replays_public ON game_replays(created_at DESC) WHERE is_public = true;
CREATE INDEX idx_game_replays_views ON game_replays(view_count DESC) WHERE is_public = true;

-- Spectator tracking
CREATE TABLE game_spectators (
                                 id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
                                 game_id UUID NOT NULL REFERENCES games(id) ON DELETE CASCADE,
                                 user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                                 joined_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
                                 left_at TIMESTAMP WITH TIME ZONE,
                                 is_active BOOLEAN DEFAULT true,

    -- Constraints
                                 CONSTRAINT unique_spectator UNIQUE(game_id, user_id)
);

-- Indexes for spectators
CREATE INDEX idx_spectators_game ON game_spectators(game_id) WHERE is_active = true;
CREATE INDEX idx_spectators_user ON game_spectators(user_id) WHERE is_active = true;

-- Player notes (private notes about opponents)
CREATE TABLE player_notes (
                              id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
                              user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                              target_user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                              note TEXT,
                              color_tag VARCHAR(20), -- For visual organization
                              created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
                              updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    -- Constraints
                              CONSTRAINT unique_note UNIQUE(user_id, target_user_id),
                              CONSTRAINT no_self_note CHECK (user_id != target_user_id)
);

-- Indexes for notes
CREATE INDEX idx_player_notes_user ON player_notes(user_id);
CREATE INDEX idx_player_notes_target ON player_notes(target_user_id);

-- Game invitations
CREATE TABLE game_invitations (
                                  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
                                  inviter_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                                  invitee_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                                  game_mode game_mode NOT NULL,
                                  time_control_seconds INTEGER,
                                  dictionary_id INTEGER REFERENCES dictionaries(id),
                                  message TEXT,
                                  status VARCHAR(20) DEFAULT 'pending', -- 'pending', 'accepted', 'declined', 'expired'
                                  game_id UUID REFERENCES games(id), -- Set when accepted
                                  created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
                                  expires_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP + INTERVAL '1 hour',

    -- Constraints
                                  CONSTRAINT no_self_invite CHECK (inviter_id != invitee_id)
);

-- Indexes for invitations
CREATE INDEX idx_invitations_invitee ON game_invitations(invitee_id, status) WHERE status = 'pending';
CREATE INDEX idx_invitations_inviter ON game_invitations(inviter_id, created_at DESC);
CREATE INDEX idx_invitations_expires ON game_invitations(expires_at) WHERE status = 'pending';

-- Tournament tables (for future tournament support)
CREATE TABLE tournaments (
                             id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
                             name VARCHAR(200) NOT NULL,
                             description TEXT,
                             tournament_type VARCHAR(50) DEFAULT 'single_elimination', -- 'round_robin', 'swiss', etc.
                             max_players INTEGER NOT NULL,
                             current_players INTEGER DEFAULT 0,
                             entry_fee INTEGER DEFAULT 0,
                             prize_pool JSONB,
                             dictionary_id INTEGER REFERENCES dictionaries(id),
                             time_control_seconds INTEGER DEFAULT 600,
                             starts_at TIMESTAMP WITH TIME ZONE NOT NULL,
                             ends_at TIMESTAMP WITH TIME ZONE,
                             status VARCHAR(20) DEFAULT 'upcoming', -- 'upcoming', 'active', 'completed', 'cancelled'
                             created_by UUID REFERENCES users(id),
                             created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    -- Constraints
                             CONSTRAINT valid_player_count CHECK (max_players >= 2 AND max_players <= 256)
);

-- Tournament participants
CREATE TABLE tournament_participants (
                                         id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
                                         tournament_id UUID NOT NULL REFERENCES tournaments(id) ON DELETE CASCADE,
                                         user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                                         seed INTEGER,
                                         current_round INTEGER DEFAULT 1,
                                         is_eliminated BOOLEAN DEFAULT false,
                                         final_position INTEGER,
                                         games_played INTEGER DEFAULT 0,
                                         games_won INTEGER DEFAULT 0,
                                         total_score INTEGER DEFAULT 0,
                                         joined_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    -- Constraints
                                         CONSTRAINT unique_tournament_player UNIQUE(tournament_id, user_id)
);

-- Indexes for tournaments
CREATE INDEX idx_tournaments_status ON tournaments(status, starts_at);
CREATE INDEX idx_tournament_participants ON tournament_participants(tournament_id, is_eliminated);

-- Club/Team system
CREATE TABLE clubs (
                       id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
                       name VARCHAR(100) UNIQUE NOT NULL,
                       tag VARCHAR(10) UNIQUE, -- Short identifier
                       description TEXT,
                       avatar_url VARCHAR(500),
                       banner_url VARCHAR(500),
                       is_public BOOLEAN DEFAULT true,
                       require_approval BOOLEAN DEFAULT true,
                       max_members INTEGER DEFAULT 100,
                       current_members INTEGER DEFAULT 0,
                       total_games_played INTEGER DEFAULT 0,
                       total_score BIGINT DEFAULT 0,
                       founded_by UUID REFERENCES users(id),
                       created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    -- Constraints
                       CONSTRAINT valid_member_count CHECK (max_members >= 2 AND max_members <= 1000)
);

-- Club members
CREATE TABLE club_members (
                              id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
                              club_id UUID NOT NULL REFERENCES clubs(id) ON DELETE CASCADE,
                              user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                              role VARCHAR(20) DEFAULT 'member', -- 'owner', 'admin', 'member'
                              contribution_points INTEGER DEFAULT 0,
                              joined_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,

    -- Constraints
                              CONSTRAINT unique_club_member UNIQUE(club_id, user_id)
);

-- Indexes for clubs
CREATE INDEX idx_clubs_public ON clubs(created_at DESC) WHERE is_public = true;
CREATE INDEX idx_club_members_user ON club_members(user_id);
CREATE INDEX idx_club_members_club ON club_members(club_id, role);

-- Notification preferences
CREATE TABLE notification_preferences (
                                          user_id UUID PRIMARY KEY REFERENCES users(id) ON DELETE CASCADE,
                                          game_invites BOOLEAN DEFAULT true,
                                          friend_requests BOOLEAN DEFAULT true,
                                          turn_reminders BOOLEAN DEFAULT true,
                                          achievement_unlocks BOOLEAN DEFAULT true,
                                          tournament_updates BOOLEAN DEFAULT true,
                                          club_activity BOOLEAN DEFAULT true,
                                          email_notifications BOOLEAN DEFAULT false,
                                          push_notifications BOOLEAN DEFAULT true,
                                          quiet_hours_start TIME,
                                          quiet_hours_end TIME,
                                          created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
                                          updated_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP
);

-- Notification queue
CREATE TABLE notification_queue (
                                    id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
                                    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
                                    notification_type VARCHAR(50) NOT NULL,
                                    title VARCHAR(200),
                                    message TEXT NOT NULL,
                                    data JSONB, -- Additional context data
                                    is_read BOOLEAN DEFAULT false,
                                    is_sent BOOLEAN DEFAULT false,
                                    sent_via VARCHAR(20), -- 'in_app', 'email', 'push'
                                    created_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP,
                                    sent_at TIMESTAMP WITH TIME ZONE,
                                    read_at TIMESTAMP WITH TIME ZONE,
                                    expires_at TIMESTAMP WITH TIME ZONE DEFAULT CURRENT_TIMESTAMP + INTERVAL '30 days'
);

-- Indexes for notifications
CREATE INDEX idx_notifications_user_unread ON notification_queue(user_id, created_at DESC)
    WHERE is_read = false;
CREATE INDEX idx_notifications_unsent ON notification_queue(created_at)
    WHERE is_sent = false;
CREATE INDEX idx_notifications_expires ON notification_queue(expires_at);

-- Function to get mutual friends
CREATE OR REPLACE FUNCTION get_mutual_friends(
    p_user1_id UUID,
    p_user2_id UUID
) RETURNS TABLE(friend_id UUID, username VARCHAR) AS $
BEGIN
RETURN QUERY
SELECT DISTINCT u.id, u.username
FROM users u
WHERE u.id IN (
    -- Friends of user1
    SELECT CASE
               WHEN requester_id = p_user1_id THEN addressee_id
               ELSE requester_id
               END
    FROM friendships
    WHERE (requester_id = p_user1_id OR addressee_id = p_user1_id)
      AND status = 'accepted'
)
  AND u.id IN (
    -- Friends of user2
    SELECT CASE
               WHEN requester_id = p_user2_id THEN addressee_id
               ELSE requester_id
               END
    FROM friendships
    WHERE (requester_id = p_user2_id OR addressee_id = p_user2_id)
      AND status = 'accepted'
)
  AND u.id NOT IN (p_user1_id, p_user2_id);
END;
$ LANGUAGE plpgsql;

-- Function to create notification
CREATE OR REPLACE FUNCTION create_notification(
    p_user_id UUID,
    p_type VARCHAR,
    p_title VARCHAR,
    p_message TEXT,
    p_data JSONB DEFAULT '{}'
) RETURNS UUID AS $
DECLARE
    v_notification_id UUID;
v_prefs RECORD;
BEGIN
    -- Check user preferences
SELECT * INTO v_prefs FROM notification_preferences WHERE user_id = p_user_id;

-- Check if this type of notification is enabled
IF (p_type = 'game_invite' AND v_prefs.game_invites = false) OR
(p_type = 'friend_request' AND v_prefs.friend_requests = false) OR
(p_type = 'achievement' AND v_prefs.achievement_unlocks = false) THEN
        RETURN NULL;
END IF;

-- Create notification
INSERT INTO notification_queue (user_id, notification_type, title, message, data)
VALUES (p_user_id, p_type, p_title, p_message, p_data)
RETURNING id INTO v_notification_id;

RETURN v_notification_id;
END;
$ LANGUAGE plpgsql;

-- Trigger to update club member count
CREATE OR REPLACE FUNCTION update_club_member_count() RETURNS TRIGGER AS $
BEGIN
IF TG_OP = 'INSERT' THEN
UPDATE clubs SET current_members = current_members + 1 WHERE id = NEW.club_id;
ELSIF TG_OP = 'DELETE' THEN
UPDATE clubs SET current_members = current_members - 1 WHERE id = OLD.club_id;
END IF;
RETURN NULL;
END;
$ LANGUAGE plpgsql;

CREATE TRIGGER update_club_members_count
    AFTER INSERT OR DELETE ON club_members
    FOR EACH ROW EXECUTE FUNCTION update_club_member_count();

-- Comments
COMMENT ON TABLE friendships IS 'Friend relationships between users';
COMMENT ON TABLE game_chat IS 'In-game chat messages';
COMMENT ON TABLE quick_chat_messages IS 'Pre-defined chat messages for quick communication';
COMMENT ON TABLE game_replays IS 'Stored game replays for viewing';
COMMENT ON TABLE game_spectators IS 'Users watching live games';
COMMENT ON TABLE player_notes IS 'Private notes about other players';
COMMENT ON TABLE game_invitations IS 'Direct game invitations between players';
COMMENT ON TABLE tournaments IS 'Tournament definitions and settings';
COMMENT ON TABLE clubs IS 'Player clubs/teams';
COMMENT ON TABLE notification_queue IS 'Pending notifications for users';