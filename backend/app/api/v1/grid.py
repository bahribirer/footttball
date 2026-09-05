"""Tiki Taka Toe tahtası uç noktaları."""

import asyncio

from fastapi import APIRouter, HTTPException

from app.models.schemas import GridResponse
from app.services import grid_service

router = APIRouter(tags=["grid"])


async def _build(league_id: str) -> GridResponse:
    try:
        nations, clubs = await asyncio.to_thread(grid_service.build_grid, league_id)
    except ValueError as exc:
        raise HTTPException(status_code=404, detail=str(exc)) from exc
    return GridResponse(nations=nations, clubs=clubs)


@router.get("/final_grid/{league_id}", response_model=GridResponse)
async def final_grid(league_id: str) -> GridResponse:
    return await _build(league_id)


@router.get("/replay_data/{league_id}", response_model=GridResponse)
async def replay_data(league_id: str) -> GridResponse:
    return await _build(league_id)
