"""Kategori Yarışı ve Oyuncu Tahmin için içerik uç noktaları."""

import asyncio

from fastapi import APIRouter, Query

from app.models.schemas import CategoryResponse, GridResponse
from app.services import category_service, pool_service

router = APIRouter(tags=["content"])


@router.get("/categories", response_model=list[CategoryResponse])
async def categories(count: int = Query(default=3, ge=1, le=10)) -> list[CategoryResponse]:
    """Oyun öncesi gösterilecek rastgele kategoriler."""
    chosen = await asyncio.to_thread(category_service.random_categories, count)
    return [CategoryResponse(id=c.id, label=c.label, difficulty=c.difficulty)
            for c in chosen]


@router.get("/duel_board", response_model=GridResponse)
async def duel_board() -> GridResponse:
    """Oyuncu Tahmin modundaki 5 millet + 5 kulüp tahtası (önizleme amaçlı)."""
    nations, clubs = await asyncio.to_thread(pool_service.build_duel_board)
    return GridResponse(nations=nations, clubs=clubs)
