from fastapi import FastAPI
from app.routers import ws

app = FastAPI(title="Scrabble Backend")

app.include_router(ws.router, prefix="/ws", tags=["websocket"])

@app.get("/")
async def root():
    return {"message": "Scrabble backend is running"}
