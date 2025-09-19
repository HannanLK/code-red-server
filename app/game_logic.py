import random

class GameState:
    def __init__(self):
        self.board = [["" for _ in range(15)] for _ in range(15)]
        self.tile_bag = self.generate_tile_bag()
        self.racks = {"player1": [], "player2": []}
        self.scores = {"player1": 0, "player2": 0}
        self.current_turn = random.choice(["player1", "player2"])
        self.draw_initial_tiles()

    def generate_tile_bag(self):
        tiles = (
            ['A']*9 + ['B']*2 + ['C']*2 + ['D']*4 + ['E']*12 +
            ['F']*2 + ['G']*3 + ['H']*2 + ['I']*9 + ['J']*1 +
            ['K']*1 + ['L']*4 + ['M']*2 + ['N']*6 + ['O']*8 +
            ['P']*2 + ['Q']*1 + ['R']*6 + ['S']*4 + ['T']*6 +
            ['U']*4 + ['V']*2 + ['W']*2 + ['X']*1 + ['Y']*2 + ['Z']*1
        )
        random.shuffle(tiles)
        return tiles

    def draw_initial_tiles(self):
        for player in self.racks:
            while len(self.racks[player]) < 7 and self.tile_bag:
                self.racks[player].append(self.tile_bag.pop())

    def apply_move(self, player_id, tiles):
        # tiles = [{"x": int, "y": int, "letter": str}, ...]
        for t in tiles:
            self.board[t["y"]][t["x"]] = t["letter"]
            self.racks[player_id].remove(t["letter"])
        self.scores[player_id] += len(tiles)  # simplified scoring
        self.current_turn = "player1" if player_id=="player2" else "player2"
