"""FastAPI uygulaması."""

import asyncio
import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware

from app.api.v1.router import api_router
from app.core.config import settings
from app.core.observability import setup_error_reporting
from app.realtime import gateway, legacy
from app.realtime.hub import hub

logging.basicConfig(
    level=logging.DEBUG if settings.DEBUG else logging.INFO,
    format="%(asctime)s %(levelname)-8s %(name)s: %(message)s",
)
logger = logging.getLogger(__name__)

# SENTRY_DSN verilmemisse sessizce atlanir; gelistirme ve CI hesap istemez.
setup_error_reporting(settings.ENVIRONMENT, release=settings.RELEASE)


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


def _job_statuses() -> dict:
    """Zamanlanmış işlerin son sonuçları.

    `infra/run_job.sh` her koşudan sonra durum dosyası yazıyor. Cron'lar
    sessizce koşup sessizce başarısız oluyordu; buradan okunabilir olmaları
    dışarıdan izlenebilmelerini sağlıyor.
    """
    import json
    from pathlib import Path

    jobs_dir = Path(settings.DB_PATH).parent / "jobs"
    if not jobs_dir.is_dir():
        return {}

    result: dict = {}
    for path in sorted(jobs_dir.glob("*.json")):
        try:
            result[path.stem] = json.loads(path.read_text())
        except Exception:
            result[path.stem] = {"ok": False, "error": "durum dosyasi okunamadi"}
    return result


@app.get("/status", tags=["health"])
async def status() -> dict:
    """Dışarıya açık, detaysız sağlık sinyali.

    `/health` oyuncu sayısı, katman durumu ve cron sonuçlarını döndürdüğü
    için nginx'te özel ağa kısıtlı. Dışarıdan yoklama yapan izleme buna
    erişemiyordu; burası yalnızca "ok" ya da "degraded" der, ayrıntı
    vermez.
    """
    detail = await health()
    return {"status": detail.get("status", "degraded")}


@app.get("/health", tags=["health"])
async def health() -> dict:
    """Konteyner sağlık kontrolü: veritabanı erişimi, katmanlar ve cron'lar."""
    from app.db.database import fetch_one
    from app.services import player_service

    try:
        row = fetch_one("SELECT COUNT(*) AS total FROM players LIMIT 1")
        jobs = _job_statuses()
        # Bir cron işi başarısızsa servis ayakta ama veri eskiyor demektir;
        # bunu "ok" diye göstermek sorunun fark edilmesini geciktirir.
        failed = [name for name, info in jobs.items() if info.get("ok") is False]
        return {
            "status": "degraded" if failed else "ok",
            "players": row["total"] if row else 0,
            "layers": {
                "squad_updates": player_service.has_squad_layer(),
                "club_history": player_service.has_history_layer(),
                "name_tokens": player_service.has_token_index(),
            },
            "jobs": jobs,
            "failed_jobs": failed,
        }
    except Exception as exc:
        logger.exception("Sağlık kontrolü başarısız")
        return {"status": "degraded", "error": str(exc)}
