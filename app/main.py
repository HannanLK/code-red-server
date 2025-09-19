from __future__ import annotations
import asyncio
from typing import Dict

import socketio
from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from .schemas import PlayerState, Move, Bot
from .managers.game import GameManager

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

# Socket.IO Events
@sio.event
async def connect(sid, environ, auth):
    # Could validate auth here
    await sio.emit('pong', to=sid)

@sio.event
async def disconnect(sid):
    # Nothing special for now
    pass

@sio.on('ping')
async def on_ping(sid):
    await sio.emit('pong', to=sid)

@sio.on('join-game')
async def join_game(sid, game_id: str):
    await sio.save_session(sid, { 'game_id': game_id })
    await sio.enter_room(sid, game_id)
    # Add a placeholder player for this socket if not present
    player = PlayerState(id=sid, name=f"Player-{sid[:4]}")
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
