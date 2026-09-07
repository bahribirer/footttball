"""Oyun modu kataloğu.

İstemci mod listesini buradan alır. Böylece bir mod, yeni uygulama sürümü
çıkarmadan açılıp kapatılabilir.
"""

from fastapi import APIRouter

from app.models.schemas import ModeResponse
from app.services import mode_service

router = APIRouter(tags=["modes"])


@router.get("/modes", response_model=list[ModeResponse])
async def modes(include_disabled: bool = False) -> list[ModeResponse]:
    return [
        ModeResponse(
            id=info.id,
            label=info.label,
            enabled=info.enabled,
            min_client_version=info.min_client_version,
        )
        for info in mode_service.catalog()
        if include_disabled or info.enabled
    ]
