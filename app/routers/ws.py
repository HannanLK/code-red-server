from fastapi import APIRouter, WebSocket, WebSocketDisconnect
from app.game_logic import GameState

router = APIRouter()
connections = {}  # {game_id: [WebSocket, WebSocket]}
games = {}        # {game_id: GameState}

@router.websocket("/{game_id}/{player_id}")
async def websocket_endpoint(websocket: WebSocket, game_id: str, player_id: str):
    await websocket.accept()

    if game_id not in games:
        games[game_id] = GameState()
    game = games[game_id]

    if game_id not in connections:
        connections[game_id] = []
    connections[game_id].append(websocket)

    # Send initial state to player
    await websocket.send_json({
        "type": "init",
        "board": game.board,
        "rack": game.racks[player_id],
        "scores": game.scores,
        "your_turn": game.current_turn == player_id
    })

    try:
        while True:
            data = await websocket.receive_json()
            if data["type"] == "move" and game.current_turn == player_id:
                game.apply_move(player_id, data["tiles"])
                # Broadcast update
                for conn in connections[game_id]:
                    await conn.send_json({
                        "type": "update",
                        "board": game.board,
                        "racks": game.racks,
                        "scores": game.scores,
                        "current_turn": game.current_turn
                    })
    except WebSocketDisconnect:
        connections[game_id].remove(websocket)
