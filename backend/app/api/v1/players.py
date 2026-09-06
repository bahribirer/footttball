"""Oyuncu arama ve tahmin doğrulama uç noktaları."""

import asyncio

from fastapi import APIRouter, Query, Request

from app.models.schemas import PlayerInfo
from app.services import player_service
from app.services.country_service import get_iso_code

router = APIRouter(tags=["players"])


@router.post("/guess_player/")
async def guess_player(player_info: PlayerInfo) -> bool:
    return await asyncio.to_thread(
        player_service.verify_player,
        player_info.player_name,
        player_info.nationality,
        player_info.club,
    )


@router.get("/get_player_names")
async def get_player_names(request: Request, name: str = Query(min_length=0)) -> list[dict]:
    base_url = str(request.base_url).rstrip("/")
    return await asyncio.to_thread(player_service.search_players, name, base_url)


@router.get("/country_iso/{country_name}")
async def country_iso(country_name: str) -> dict:
    return {"countryISO": get_iso_code(country_name)}
