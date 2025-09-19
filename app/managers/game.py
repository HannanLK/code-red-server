from __future__ import annotations
import asyncio
import random
from typing import Dict, List, Optional

from ..schemas import GameState, PlayerState, Move, TimerState
from .timer import TimerManager

class Game:
    def __init__(self, game_id: str, sio, timer: TimerManager):
        self.id = game_id
        self.sio = sio
        self.timer = timer
        self.players: List[PlayerState] = []
        self.current_idx: int = 0
        self.status: str = 'waiting'
        self.board = [[None for _ in range(15)] for _ in range(15)]
        self.bagCount = 100
        self.bot: Optional[dict] = None
        self._bot_task: Optional[asyncio.Task] = None

    @property
    def current_player(self) -> Optional[PlayerState]:
        if not self.players:
            return None
        return self.players[self.current_idx % len(self.players)]

    def to_state(self) -> GameState:
        return GameState(
            id=self.id,
            board=self.board,
            players=self.players,
            currentTurnPlayerId=self.current_player.id if self.current_player else None,
            bagCount=self.bagCount,
            status=self.status,  # type: ignore
        )

    async def start(self):
        if len(self.players) >= 1:
            self.status = 'active'
            # everyone joins room self.id handled outside
            # Randomize starting player and start timer accordingly
            if len(self.players) >= 2:
                self.current_idx = random.randint(0, 1)
            else:
                self.current_idx = 0
            # Initialize game clock with default settings
            self.timer.create_clock(self.id)
            self.timer.start_turn(self.id, 'player1' if self.current_idx == 0 else 'player2')
            await self.sio.emit('game:state', self.to_state().model_dump(by_alias=True), room=self.id)

    async def make_move(self, move: Move):
        # In this stub, we just accept and switch turn
        await self.sio.emit('move-made', move.model_dump(by_alias=True), room=self.id)
        await self.pass_turn()

    async def pass_turn(self):
        # Switch current player and notify
        self.current_idx = (self.current_idx + 1) % len(self.players)
        # Switch timer turn
        self.timer.switch_turn(self.id)
        await self.sio.emit('turn-changed', self.current_player.id if self.current_player else None, room=self.id)
        # If bot turn, schedule bot move
        await self._maybe_schedule_bot_move()

    async def _maybe_schedule_bot_move(self):
        if self.bot and self.current_player and self.current_player.id == self.bot['id']:
            delay = self._bot_delay(self.bot.get('difficulty', 'beginner'))
            if self._bot_task and not self._bot_task.done():
                self._bot_task.cancel()
            self._bot_task = asyncio.create_task(self._bot_move_after(delay))

    def _bot_delay(self, difficulty: str) -> float:
        if difficulty == 'beginner':
            return random.uniform(2.0, 3.0)
        if difficulty == 'easy':
            return random.uniform(2.5, 4.0)
        return random.uniform(3.0, 5.0)

    async def _bot_move_after(self, delay: float):
        await asyncio.sleep(delay)
        # emit a dummy bot move
        move = Move(playerId=self.bot['id'], tiles=[], formedWords=[], totalPoints=0)
        await self.make_move(move)

class GameManager:
    def __init__(self, sio):
        self.sio = sio
        self.timer = TimerManager(sio)
        self.games: Dict[str, Game] = {}
        # simple user socket mapping
        self.user_rooms: Dict[str, str] = {}

    def get_or_create(self, game_id: str) -> Game:
        if game_id not in self.games:
            self.games[game_id] = Game(game_id, self.sio, self.timer)
        return self.games[game_id]

    async def add_player(self, game_id: str, player: PlayerState):
        game = self.get_or_create(game_id)
        # prevent duplicates
        if not any(p.id == player.id for p in game.players):
            game.players.append(player)
        await self.sio.emit('game:state', game.to_state().model_dump(by_alias=True), room=game_id)

    async def start_game(self, game_id: str):
        game = self.get_or_create(game_id)
        await game.start()

    async def make_move(self, game_id: str, move: Move):
        game = self.get_or_create(game_id)
        await game.make_move(move)

    async def pass_turn(self, game_id: str):
        game = self.get_or_create(game_id)
        await game.pass_turn()

    def get_timer_state(self, game_id: str) -> Optional[TimerState]:
        return self.timer.get_state(game_id)

    def set_bot(self, game_id: str, bot_info: dict):
        game = self.get_or_create(game_id)
        game.bot = bot_info
