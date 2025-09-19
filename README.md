Code-Red Server (FastAPI + Socket.IO)

This server provides a minimal backend to support the client features for Stage 2 (Secure Game Clock) and basic Stage 3 bot scaffolding.

Quick start
1) Install dependencies
   pip install -r requirements.txt

2) Run the server (ASGI)
   uvicorn app.main:application --reload --host 0.0.0.0 --port 8000

Socket.IO events (subset)
Client -> Server
- 'join-game': (gameId: string) => void
- 'game:start': (roomId: string) => void
- 'make-move': (move: Move) => void
- 'pass-turn': () => void
- 'ping': () => void

Server -> Client
- 'game-state': (state: GameState) => void
- 'move-made': (move: Move) => void
- 'turn-changed': (playerId: string) => void
- 'timer-sync': (times: TimerState) => void
- 'timer-expired': (player: 'player1' | 'player2') => void

Timer behavior
- Server is the authority. Timers tick in the background loop and emit 'timer-sync' roughly every 5 seconds.
- On expiration the server emits 'timer-expired' with the losing timer ('player1'|'player2').
- Changing turns switches the active timer. Use 'pass-turn' or make a move to switch.

Bots
- GET /bots returns a list of basic bots (beginner/easy/medium)
- POST /games/{gameId}/bot/{botId} attaches a bot to the game. When it is the bot's turn, the server simulates thinking for 2–5 seconds and then emits a placeholder 'move-made' followed by switching the turn.

Notes
- This implementation maintains in-memory game state and is suitable for development only.
- Add persistence, authentication, and validation for production.
