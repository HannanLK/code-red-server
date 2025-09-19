-- Master migration runner to enforce execution order
-- Usage (psql):
--   \i 'D:/office/code-red/code-red-server/db/Migration/000_all_in_order.sql'

\echo 'Applying migrations in order...'
\i 'D:/office/code-red/code-red-server/db/Migration/001_create_users_and_authentication.sql'
\i 'D:/office/code-red/code-red-server/db/Migration/002_create_games_core.sql'
\i 'D:/office/code-red/code-red-server/db/Migration/003_create_dictionary_system.sql'
\i 'D:/office/code-red/code-red-server/db/Migration/004_create_bot_system.sql'
\i 'D:/office/code-red/code-red-server/db/Migration/005_create_statistics_and_analytics.sql'
\i 'D:/office/code-red/code-red-server/db/Migration/006_create_social_and_chat.sql'
\i 'D:/office/code-red/code-red-server/db/Migration/007_create_optimization_and_maintenance.sql'
\i 'D:/office/code-red/code-red-server/db/Migration/008_enhancements_and_partitions.sql'
\i 'D:/office/code-red/code-red-server/db/Migration/009_hotfix_idempotent_and_performance.sql'
\echo 'All migrations applied.'
