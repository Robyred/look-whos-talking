from pathlib import Path

from fastapi import FastAPI
from fastapi.responses import FileResponse
from fastapi.staticfiles import StaticFiles

from backend.routes import router

FRONTEND_DIR = Path(__file__).parent.parent / "frontend"

app = FastAPI(title="Look Who's Talking", version="0.1.0")
app.include_router(router, prefix="/api")
app.mount("/static", StaticFiles(directory=FRONTEND_DIR), name="static")


@app.get("/")
async def serve_ui() -> FileResponse:
    return FileResponse(FRONTEND_DIR / "index.html")
