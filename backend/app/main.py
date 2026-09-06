"""FastAPI uygulaması."""

import asyncio
import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.v1.router import api_router
from app.core.config import settings
from app.realtime import gateway, legacy
from app.realtime.hub import hub

logging.basicConfig(
    level=logging.DEBUG if settings.DEBUG else logging.INFO,
    format="%(asctime)s %(levelname)-8s %(name)s: %(message)s",
)
logger = logging.getLogger(__name__)


@asynccontextmanager
async def lifespan(app: FastAPI):
    cleanup_task = asyncio.create_task(hub.cleanup_loop())
    logger.info("Tiki Taka Toe API başladı (%s)", settings.ENVIRONMENT)
    try:
        yield
    finally:
        cleanup_task.cancel()
        try:
            await cleanup_task
        except asyncio.CancelledError:
            pass


app = FastAPI(
    title="Tiki Taka Toe API",
    version="2.0.0",
    lifespan=lifespan,
)

# Mobil istemci farklı origin'den geldiği için açık; tarayıcı istemcisi
# eklenirse buradaki liste daraltılmalı.
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=False,
    allow_methods=["GET", "POST"],
    allow_headers=["*"],
)

app.include_router(api_router, prefix="/api/v1")
app.include_router(gateway.router)
app.include_router(legacy.router)


@app.get("/ping", tags=["health"])
async def ping() -> dict:
    return {"status": "ok", "message": "Backend is reachable"}


@app.get("/health", tags=["health"])
async def health() -> dict:
    """Konteyner sağlık kontrolü: veritabanı erişimi dahil."""
    from app.db.database import fetch_one

    try:
        row = fetch_one("SELECT COUNT(*) AS total FROM players LIMIT 1")
        return {"status": "ok", "players": row["total"] if row else 0}
    except Exception as exc:
        logger.exception("Sağlık kontrolü başarısız")
        return {"status": "degraded", "error": str(exc)}
