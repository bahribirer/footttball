"""Yönetim paneli uç noktaları. Hepsi `X-Admin-Token` ister."""

from fastapi import APIRouter, Depends, Header, HTTPException
from pydantic import BaseModel, Field

from app.core.config import BASE_DIR
from app.services import admin_service, score_service

router = APIRouter()

ADMIN_HTML = BASE_DIR / "static" / "admin" / "index.html"


def _auth(
    x_admin_token: str | None = Header(default=None),
    authorization: str | None = Header(default=None),
) -> None:
    if not admin_service.enabled():
        raise HTTPException(status_code=503, detail="Yönetim paneli kapalı (ADMIN_PASSWORD yok)")
    token = x_admin_token
    if not token and authorization and authorization.lower().startswith("bearer "):
        token = authorization[7:].strip()
    if not admin_service.check_token(token):
        raise HTTPException(status_code=401, detail="Oturum geçersiz ya da süresi dolmuş")


class LoginRequest(BaseModel):
    username: str = Field(min_length=1, max_length=64)
    password: str = Field(min_length=1, max_length=256)


class LivesRequest(BaseModel):
    lives: int | None = Field(default=None, ge=0, le=10)


@router.post("/admin/login")
async def admin_login(payload: LoginRequest) -> dict:
    if not admin_service.enabled():
        raise HTTPException(status_code=503, detail="Yönetim paneli kapalı (ADMIN_PASSWORD yok)")
    token = admin_service.login(payload.username, payload.password)
    if not token:
        raise HTTPException(status_code=401, detail="Kullanıcı adı ya da parola yanlış")
    return {"token": token, "user": payload.username.strip(),
            "expires_in": 3600 * admin_service.settings.ADMIN_SESSION_HOURS}


@router.get("/admin/me", dependencies=[Depends(_auth)])
async def admin_me() -> dict:
    return {"user": admin_service.settings.ADMIN_USER}


class NotifyRequest(BaseModel):
    title: str = Field(default="Duyuru", max_length=60)
    message: str = Field(min_length=1, max_length=400)
    target: str = Field(default="all", max_length=16)
    ttl_seconds: int = Field(default=3600, ge=60, le=7 * 86400)


class CloseRequest(BaseModel):
    reason: str = Field(default="Oda yönetici tarafından kapatıldı.", max_length=200)


@router.get("/notice")
async def public_notice() -> dict:
    """Herkese açık: menüdeki oyuncu açılışta okur."""
    return {"notice": admin_service.current_notice()}


@router.get("/admin/overview", dependencies=[Depends(_auth)])
async def overview() -> dict:
    return await admin_service.overview()


@router.get("/admin/rooms", dependencies=[Depends(_auth)])
async def rooms() -> dict:
    return {"rooms": admin_service.rooms_view()}


@router.get("/admin/leaderboard", dependencies=[Depends(_auth)])
async def leaderboard(mode: str = "all") -> dict:
    return {"entries": score_service.leaderboard(mode, 100)}


@router.get("/admin/players", dependencies=[Depends(_auth)])
async def admin_players(q: str = "", page: int = 1, size: int = 50) -> dict:
    size = max(1, min(200, size))
    return admin_service.players_page(q, max(1, page), size)


@router.get("/admin/players/{player_id}", dependencies=[Depends(_auth)])
async def admin_player(player_id: str) -> dict:
    detail = admin_service.player_detail(player_id)
    if detail is None:
        raise HTTPException(status_code=404, detail="Oyuncu bulunamadı")
    return detail


@router.post("/admin/players/{player_id}/lives", dependencies=[Depends(_auth)])
async def admin_grant_lives(player_id: str, payload: LivesRequest | None = None) -> dict:
    from app.services import lives_service
    return lives_service.grant(player_id, payload.lives if payload else None)


@router.get("/admin/system", dependencies=[Depends(_auth)])
async def admin_system() -> dict:
    return admin_service.system_info()


@router.post("/admin/notify", dependencies=[Depends(_auth)])
async def notify(payload: NotifyRequest) -> dict:
    try:
        return await admin_service.notify(payload.title, payload.message, payload.target, payload.ttl_seconds)
    except KeyError:
        raise HTTPException(status_code=404, detail="Oda bulunamadı")


@router.post("/admin/notice/clear", dependencies=[Depends(_auth)])
async def clear_notice() -> dict:
    admin_service.clear_notice()
    return {"ok": True}


@router.post("/admin/rooms/{code}/close", dependencies=[Depends(_auth)])
async def close_room(code: str, payload: CloseRequest | None = None) -> dict:
    reason = payload.reason if payload else CloseRequest().reason
    if not await admin_service.close_room(code, reason):
        raise HTTPException(status_code=404, detail="Oda bulunamadı")
    return {"closed": code}
