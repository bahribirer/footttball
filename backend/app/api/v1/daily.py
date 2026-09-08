"""Günlük meydan okuma uç noktaları.

Tahta tarihten türetiliyor; sunucu oyuncu başına bir şey saklamıyor.
Sonuç istemcide tutulur ve paylaşım metni buradan üretilir — böylece
hesap sistemi olmadan "herkes aynı bulmacayı çözüyor" etkisi elde edilir.
"""

from fastapi import APIRouter, HTTPException

from app.models.schemas import DailyBoardResponse, DailyShareRequest, DailyShareResponse
from app.services import daily_service

router = APIRouter(tags=["daily"])


@router.get("/daily", response_model=DailyBoardResponse)
async def daily_board() -> DailyBoardResponse:
    board = daily_service.board()
    return DailyBoardResponse(**board)


@router.post("/daily/share", response_model=DailyShareResponse)
async def daily_share(payload: DailyShareRequest) -> DailyShareResponse:
    if len(payload.results) != daily_service.BOARD_SIZE ** 2:
        raise HTTPException(status_code=422, detail="results 9 uzunlugunda olmali")
    return DailyShareResponse(
        text=daily_service.share_text(payload.number, payload.results),
        score=sum(1 for value in payload.results if value),
    )
