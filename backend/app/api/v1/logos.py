"""Kulüp logosu uç noktaları."""

import asyncio

from fastapi import APIRouter, HTTPException, Request
from fastapi.responses import FileResponse

from app.services import logo_service

router = APIRouter(tags=["logos"])

CACHE_HEADERS = {"Cache-Control": "public, max-age=604800"}


@router.get("/logo_image/{club_name}")
async def logo_image(club_name: str) -> FileResponse:
    path = await asyncio.to_thread(logo_service.resolve_logo, club_name)
    if not path:
        raise HTTPException(status_code=404, detail=f"{club_name} için logo bulunamadı")
    return FileResponse(path, media_type="image/png", headers=CACHE_HEADERS)


@router.get("/club_logo/{league_id}/{club_name}")
async def club_logo(league_id: str, club_name: str, request: Request) -> dict:
    """Logonun kendisini değil, proxy URL'sini döndürür (eski istemci uyumu)."""
    base_url = str(request.base_url).rstrip("/")
    return {"logoURL": f"{base_url}/api/v1/logo_image/{club_name}"}
