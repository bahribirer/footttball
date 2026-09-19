"""Skor tablosu uç noktaları."""

from fastapi import APIRouter, HTTPException, Query
from pydantic import BaseModel, Field

from app.realtime.protocol import GameMode
from app.services import daily_service, lives_service, score_service

router = APIRouter()

VALID_MODES = {"all", "daily", *(m.value for m in GameMode)}


class DailyScoreRequest(BaseModel):
    player_id: str = Field(min_length=8, max_length=64)
    name: str = Field(default="Oyuncu", max_length=32)
    date: str = Field(min_length=10, max_length=10)
    score: int = Field(ge=0, le=9)


@router.get("/leaderboard")
async def get_leaderboard(
    mode: str = Query(default="all"),
    limit: int = Query(default=50, ge=1, le=100),
    player_id: str | None = Query(default=None, max_length=64),
) -> dict:
    if mode not in VALID_MODES:
        raise HTTPException(status_code=400, detail="Bilinmeyen mod")
    payload: dict = {
        "mode": mode,
        "entries": score_service.leaderboard(mode, limit),
        "modes": ["all", *(m.value for m in GameMode), "daily"],
    }
    if player_id:
        payload["me"] = score_service.summary(player_id)
    return payload


@router.post("/leaderboard/daily")
async def post_daily_score(payload: DailyScoreRequest) -> dict:
    """Günün tahtası puanı. Yalnız bugünün (ya da dünün) tarihi kabul edilir."""
    allowed = daily_service.recent_dates(2)
    if payload.date not in allowed:
        raise HTTPException(status_code=400, detail="Bu tarih için puan girilemez")
    accepted = score_service.record_daily(payload.player_id, payload.name, payload.date, payload.score)
    return {"accepted": accepted, **score_service.summary(payload.player_id)}


@router.get("/lives")
async def get_lives(player_id: str = Query(min_length=8, max_length=64)) -> dict:
    """Cihazın kalan canı ve yenilenme zamanı."""
    return lives_service.status(player_id)
