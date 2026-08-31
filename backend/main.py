import logging
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI
from fastapi.responses import FileResponse, JSONResponse
from fastapi.staticfiles import StaticFiles

from backend.routes import router

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

FRONTEND_DIR = Path(__file__).parent.parent / "frontend"


@asynccontextmanager
async def lifespan(app: FastAPI):
    import asyncio
    from diarization.embedder import warmup
    logger.info("Pre-warming diarization model…")
    await asyncio.to_thread(warmup)
    logger.info("Model warm-up complete — ready to accept jobs")
    yield


app = FastAPI(title="Look Who's Talking", version="0.1.0", lifespan=lifespan)
app.include_router(router, prefix="/api")
app.mount("/static", StaticFiles(directory=FRONTEND_DIR), name="static")


@app.get("/health")
async def health() -> JSONResponse:
    return JSONResponse({"status": "ok"})


@app.get("/")
async def serve_ui() -> FileResponse:
    return FileResponse(FRONTEND_DIR / "index.html")
