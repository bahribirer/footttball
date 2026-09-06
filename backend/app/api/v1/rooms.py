"""Oda oluşturma ve durum sorgulama."""

from fastapi import APIRouter, HTTPException

from app.core.config import settings
from app.models.schemas import CreateRoomRequest, CreateRoomResponse, RoomStatusResponse
from app.realtime.hub import hub
from app.realtime.protocol import GameMode

router = APIRouter(tags=["rooms"])


@router.post("/rooms", response_model=CreateRoomResponse)
async def create_room(payload: CreateRoomRequest) -> CreateRoomResponse:
    """Oda kodunu sunucu üretir; iki istemcinin aynı kodu seçmesi engellenir."""
    room_settings: dict = {}

    if payload.mode == GameMode.TIKI_TAKA_TOE:
        room_settings["league_id"] = payload.league_id or "RANDOM"
        room_settings["round_count"] = payload.round_count or 1
    elif payload.mode == GameMode.PLAYER_GUESS:
        room_settings["round_count"] = payload.round_count or settings.PG_ROUNDS
    else:
        room_settings["clock_seconds"] = payload.clock_seconds or settings.CLOCK_SECONDS
        room_settings["penalty"] = settings.WRONG_ANSWER_PENALTY
        if payload.category_id:
            room_settings["category_id"] = payload.category_id

    room = await hub.reserve(payload.mode, room_settings)
    return CreateRoomResponse(code=room.code, mode=room.mode, settings=room.settings)


@router.patch("/rooms/{code}", response_model=CreateRoomResponse)
async def update_room(code: str, payload: CreateRoomRequest) -> CreateRoomResponse:
    """Oda ayarlarını günceller.

    Oda kodu, kurucu lig/tur seçimini yapmadan önce üretilip ekranda gösterilir.
    Seçim tamamlandığında ayarlar bu uçla odaya işlenir; aksi halde oyun,
    rezervasyon anındaki varsayılanlarla başlıyordu.
    """
    room = hub.get(code)
    if room is None:
        raise HTTPException(status_code=404, detail="Oda bulunamadı")
    if room.engine is not None:
        raise HTTPException(status_code=409, detail="Oyun başladıktan sonra ayar değişmez")

    if payload.league_id is not None:
        room.settings["league_id"] = payload.league_id
    if payload.round_count is not None:
        room.settings["round_count"] = payload.round_count
    if payload.clock_seconds is not None:
        room.settings["clock_seconds"] = payload.clock_seconds
    if payload.category_id is not None:
        room.settings["category_id"] = payload.category_id

    return CreateRoomResponse(code=room.code, mode=room.mode, settings=room.settings)


@router.get("/rooms/{code}", response_model=RoomStatusResponse)
async def room_status(code: str) -> RoomStatusResponse:
    status = hub.room_status(code)
    return RoomStatusResponse(**{
        "room_exists": status["room_exists"],
        "is_joinable": status["is_joinable"],
        "mode": status.get("mode"),
        "players": status.get("players", 0),
    })
