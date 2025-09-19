Code-Red Server (FastAPI + Socket.IO)

Overview
Authoritative Scrabble game server that manages matchmaking, game state, and a secure server‑side timer (10 minutes per player). Randomizes starting player and supports concurrent games. A simple bot is available for instant matchmaking.

Quick start
1) Create virtual env and install deps
   python -m venv .venv
   .venv\\Scripts\\activate
   pip install -r requirements.txt

2) Run the server (ASGI)
   uvicorn app.main:application --reload --host 0.0.0.0 --port 8000

Matchmaking & games
- Lobby: clients emit 'join-game' with a gameId (room). If two humans aren't present, the manager can attach a bot.
- Concurrency: each game is a room; state is kept per room in memory (dev only).
- Start: when the first player joins, the game is created; when the second joins, status changes to active; the server randomly selects the starting player and starts their clock.

Socket.IO events
Client -> Server
- 'join-game': (gameId: string)
- 'game:start': (roomId: string)
- 'make-move': (move: Move)
- 'pass-turn': ()
- 'ping': ()

Server -> Client
- 'game:state': (state: GameState)  // authoritative state broadcast
- 'move-made': (move: Move)
- 'turn-changed': (playerId: string)
- 'timer-sync': (times: TimerState)
- 'timer-expired': (player: 'player1' | 'player2')

Timer behavior (secure)
- The server is the source of truth. Each game has a GameClock with 10 minutes per player.
- On game start the active player's clock begins. Passing/valid moves switch clocks.
- Periodic 'timer-sync' messages keep clients visually aligned. On expiration the server emits 'timer-expired' with the losing side.

Bot (simple)
- A basic bot can be auto‑attached so players can always be matched.
- The bot makes a valid move within 30 seconds (simulated in current stub within 2–5s) and then the server switches turns.

Development notes
- In‑memory state only; persistence and authentication should be added for production.
- Event names follow 'game:state' (not 'game-state'). Ensure clients listen to the correct channel.

Database migrations
To apply SQL migrations in the correct order, use the master script in db/Migration:
1) Open psql connected to your database, then run:
   
   \\i 'D:/office/code-red/code-red-server/db/Migration/000_all_in_order.sql'

If running individually, always execute numbered files in ascending order. See inline notes in migrations for dependencies and partition keys.
