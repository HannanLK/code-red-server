from __future__ import annotations
import asyncio
import time
from typing import Dict, Optional
from dataclasses import dataclass

from ..schemas import TimerState

SYNC_INTERVAL = 5.0  # seconds

@dataclass
class GameClock:
    player1_ms: int
    player2_ms: int
    current: str  # 'player1' | 'player2'
    paused: bool = False
    last_ts: float = 0.0  # epoch seconds when last switched or ticked

    def snapshot(self) -> TimerState:
        return TimerState(
            player1Time=max(0, self.player1_ms),
            player2Time=max(0, self.player2_ms),
            currentPlayer='player1' if self.current == 'player1' else 'player2',
            isPaused=self.paused,
        )

class TimerManager:
    def __init__(self, sio):
        self.sio = sio
        self._clocks: Dict[str, GameClock] = {}
        self._tasks: Dict[str, asyncio.Task] = {}

    def create_clock(self, game_id: str, total_minutes_per_player: int = 15):
        total_ms = total_minutes_per_player * 60 * 1000
        clock = GameClock(player1_ms=total_ms, player2_ms=total_ms, current='player1', paused=True, last_ts=time.time())
        self._clocks[game_id] = clock
        # launch background sync task
        if game_id not in self._tasks:
            self._tasks[game_id] = asyncio.create_task(self._run(game_id))
        return clock

    def start_turn(self, game_id: str, current: str):
        clock = self._clocks.get(game_id)
        if not clock:
            clock = self.create_clock(game_id)
        clock.current = current
        clock.paused = False
        clock.last_ts = time.time()

    def pause(self, game_id: str):
        clock = self._clocks.get(game_id)
        if not clock:
            return
        self._apply_elapsed(clock)
        clock.paused = True

    def switch_turn(self, game_id: str):
        clock = self._clocks.get(game_id)
        if not clock:
            return
        self._apply_elapsed(clock)
        clock.current = 'player2' if clock.current == 'player1' else 'player1'
        clock.last_ts = time.time()

    def on_disconnect(self, game_id: str):
        # Keep clock running; could pause if desired
        pass

    def _apply_elapsed(self, clock: GameClock):
        if clock.paused:
            return
        now = time.time()
        elapsed_ms = int((now - clock.last_ts) * 1000)
        if elapsed_ms <= 0:
            return
        if clock.current == 'player1':
            clock.player1_ms -= elapsed_ms
        else:
            clock.player2_ms -= elapsed_ms
        clock.last_ts = now

    async def _run(self, game_id: str):
        # Background loop: tick, emit sync, handle expiration
        try:
            while True:
                await asyncio.sleep(0.1)
                clock = self._clocks.get(game_id)
                if not clock:
                    continue
                # tick
                self._apply_elapsed(clock)
                # check expiration
                if clock.player1_ms <= 0 or clock.player2_ms <= 0:
                    loser = 'player1' if clock.player1_ms <= 0 else 'player2'
                    # pause to avoid negative counts racing
                    clock.paused = True
                    await self.sio.emit('timer-expired', loser, room=game_id)
                    # After expiration we can stop syncing; break loop
                    break
                # emit sync every SYNC_INTERVAL seconds
                # Use fractional modulo with last_ts to keep roughly every 5s based on wall clock
                # Simpler: a small countdown
                if not hasattr(clock, '_next_sync'):
                    clock._next_sync = time.time() + SYNC_INTERVAL  # type: ignore
                if time.time() >= clock._next_sync:  # type: ignore
                    await self.sio.emit('timer-sync', clock.snapshot().model_dump(by_alias=True), room=game_id)
                    clock._next_sync = time.time() + SYNC_INTERVAL  # type: ignore
        except asyncio.CancelledError:
            return

    def get_state(self, game_id: str) -> Optional[TimerState]:
        clock = self._clocks.get(game_id)
        if not clock:
            return None
        # Ensure elapsed applied for fresh snapshot
        self._apply_elapsed(clock)
        return clock.snapshot()
