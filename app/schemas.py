from __future__ import annotations
from pydantic import BaseModel, Field
from typing import List, Literal, Optional, Tuple

Direction = Literal['H', 'V']

class Position(BaseModel):
    row: int
    col: int

class Tile(BaseModel):
    letter: Optional[str] = None
    points: int = 0
    isBlank: bool = False

class PlacedTile(BaseModel):
    row: int
    col: int
    tile: Tile

class Move(BaseModel):
    playerId: str = Field(..., alias='playerId')
    tiles: List[PlacedTile] = []
    formedWords: List[str] = []
    totalPoints: int = 0

class PlayerState(BaseModel):
    id: str
    name: str
    score: int = 0
    rack: List[Tile] = []
    isConnected: bool = True

GameStatus = Literal['waiting', 'active', 'paused', 'finished']

class GameState(BaseModel):
    id: str
    players: List[PlayerState]
    board: list
    currentTurnPlayerId: Optional[str] = None
    bagCount: int = 100
    status: GameStatus = 'waiting'
    lastMove: Optional[Move] = None

class TimerState(BaseModel):
    # milliseconds left per player
    player1Time: int
    player2Time: int
    currentPlayer: Literal['player1', 'player2']
    isPaused: bool = False

class Bot(BaseModel):
    id: str
    name: str
    difficulty: Literal['beginner', 'easy', 'medium']
    avatar: str
    description: str
    winRate: float

