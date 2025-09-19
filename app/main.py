from __future__ import annotations
import asyncio
from typing import Dict

import socketio
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .schemas import PlayerState, Move, Bot
from .managers.game import GameManager
from .dictionary import service as dict_service

# Socket.IO server (ASGI)
sio = socketio.AsyncServer(async_mode='asgi', cors_allowed_origins='*')
app = FastAPI(title="Code-Red Server", version="0.1.0")

# Mount Socket.IO ASGI application
asgi_app = socketio.ASGIApp(sio, other_asgi_app=app)

# CORS for REST
app.add_middleware(
    CORSMiddleware,
    allow_origins=['*'],
    allow_credentials=True,
    allow_methods=['*'],
    allow_headers=['*'],
)

games = GameManager(sio)

# In-memory lobby rooms for simple 2-player matchmaking
# Structure: { room_id: { 'id': str, 'name': str, 'players': set[sid], 'maxPlayers': 2, 'status': 'open'|'in-game'|'full' } }
lobby_rooms: dict[str, dict] = {
    'room-1': { 'id': 'room-1', 'name': 'Room 1', 'players': set(), 'maxPlayers': 2, 'status': 'open' },
    'room-2': { 'id': 'room-2', 'name': 'Room 2', 'players': set(), 'maxPlayers': 2, 'status': 'open' },
}

AVAILABLE_BOTS = [
    {
        'id': 'bot-beginner',
        'name': 'Robo Rookie',
        'difficulty': 'beginner',
        'avatar': '🤖',
        'description': 'Takes it slow and steady.',
        'winRate': 0.35,
    },
    {
        'id': 'bot-easy',
        'name': 'Clevertron',
        'difficulty': 'easy',
        'avatar': '🛠️',
        'description': 'Makes simple but solid moves.',
        'winRate': 0.45,
    },
    {
        'id': 'bot-medium',
        'name': 'LexiBot',
        'difficulty': 'medium',
        'avatar': '📚',
        'description': 'Thinks a bit deeper and blocks occasionally.',
        'winRate': 0.55,
    },
]

# REST Endpoints
@app.get('/bots')
async def list_bots() -> Dict[str, list]:
    return { 'bots': AVAILABLE_BOTS }

@app.post('/games/{game_id}/bot/{bot_id}')
async def add_bot(game_id: str, bot_id: str):
    bot = next((b for b in AVAILABLE_BOTS if b['id'] == bot_id), None)
    if not bot:
        return { 'ok': False, 'error': 'Bot not found' }
    games.set_bot(game_id, bot)
    return { 'ok': True }

# Dictionary validation REST endpoint
@app.get('/dict/validate')
async def validate_word(word: str):
    valid = dict_service.is_valid(word)
    definition = dict_service.definition(word) if valid else None
    return { 'word': word.upper(), 'valid': valid, 'definition': definition }

# Socket.IO Events
@sio.event
async def connect(sid, environ, auth):
    # Save username from auth token (client uses token as username)
    username = None
    if isinstance(auth, dict):
        token = auth.get('token')
        if isinstance(token, str) and token.strip():
            username = token.strip()
    await sio.save_session(sid, { 'name': username })
    await sio.emit('pong', to=sid)

@sio.event
async def disconnect(sid):
    # Remove from any lobby room
    for room in lobby_rooms.values():
        if sid in room['players']:
            room['players'].remove(sid)
            # Update room status
            if len(room['players']) == 0:
                room['status'] = 'open'
            elif len(room['players']) < room['maxPlayers']:
                room['status'] = 'open'
            await _broadcast_lobby_list()
            break

@sio.on('ping')
async def on_ping(sid):
    await sio.emit('pong', to=sid)

def _serialize_rooms():
    def to_room(room: dict):
        status = room['status']
        if len(room['players']) >= room['maxPlayers']:
            status = 'full'
        return {
            'id': room['id'],
            'name': room['name'],
            'players': len(room['players']),
            'maxPlayers': room['maxPlayers'],
            'status': status,
        }
    return [to_room(r) for r in lobby_rooms.values()]

async def _broadcast_lobby_list():
    await sio.emit('lobby:list', _serialize_rooms())

@sio.on('lobby:list')
async def lobby_list(sid):
    await sio.emit('lobby:list', _serialize_rooms(), to=sid)

@sio.on('lobby:join')
async def lobby_join(sid, room_id: str):
    room = lobby_rooms.get(room_id)
    if not room:
        return
    # add to room if space
    if len(room['players']) >= room['maxPlayers']:
        return
    room['players'].add(sid)
    await sio.enter_room(sid, room_id)

    # Save game_id and ensure player exists in game state with username
    sess = await sio.get_session(sid) or {}
    name = sess.get('name') or f"Player-{sid[:4]}"
    await sio.save_session(sid, { **sess, 'game_id': room_id })

    # Add player to game
    player = PlayerState(id=sid, name=name)
    await games.add_player(room_id, player)

    # update room status
    room['status'] = 'in-game' if len(room['players']) == 2 else 'open'
    await _broadcast_lobby_list()

    # Auto-start when two players joined
    if len(room['players']) == 2:
        await games.start_game(room_id)

@sio.on('lobby:leave')
async def lobby_leave(sid, room_id: str):
    room = lobby_rooms.get(room_id)
    if not room:
        return
    if sid in room['players']:
        room['players'].remove(sid)
    await sio.leave_room(sid, room_id)
    room['status'] = 'open'
    await _broadcast_lobby_list()

@sio.on('join-game')
async def join_game(sid, game_id: str):
    # Keep compatibility: join-game also joins Socket.IO room and adds player if needed
    await sio.enter_room(sid, game_id)
    sess = await sio.get_session(sid) or {}
    name = sess.get('name') or f"Player-{sid[:4]}"
    await sio.save_session(sid, { **sess, 'game_id': game_id })
    player = PlayerState(id=sid, name=name)
    await games.add_player(game_id, player)
    # Send immediate timer state
    ts = games.get_timer_state(game_id)
    if ts:
        await sio.emit('timer-sync', ts.model_dump(by_alias=True), room=game_id)

@sio.on('game:start')
async def game_start(sid, room_id: str):
    await games.start_game(room_id)

@sio.on('make-move')
async def make_move(sid, payload):
    sess = await sio.get_session(sid)
    game_id = sess.get('game_id') if sess else None
    if not game_id:
        return
    move = Move.model_validate(payload)
    # Validate formed words if provided
    all_words = move.formedWords or []
    is_valid = all(dict_service.is_valid(w) for w in all_words) if all_words else True
    result = {
        'isValid': is_valid,
        'reason': None if is_valid else 'One or more words are invalid',
        'score': move.totalPoints,
        'words': [w.upper() for w in all_words] if all_words else [],
    }
    # Emit validation result back to the sender only
    await sio.emit('game:moveValidated', result, to=sid)
    # For now, accept the move regardless to keep gameplay flowing
    await games.make_move(game_id, move)

@sio.on('pass-turn')
async def pass_turn(sid):
    sess = await sio.get_session(sid)
    game_id = sess.get('game_id') if sess else None
    if not game_id:
        return
    await games.pass_turn(game_id)

# Aliases from client types to maintain compatibility
@sio.on('game:placeTiles')
async def place_tiles_alias(sid, payload):
    await make_move(sid, payload)

@sio.on('game:pass')
async def pass_alias(sid):
    await pass_turn(sid)

# Export ASGI app for uvicorn
application = asgi_app

# For local running: uvicorn app.main:application --reload --host 0.0.0.0 --port 8000
