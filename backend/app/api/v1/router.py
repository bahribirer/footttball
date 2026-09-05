"""v1 API yönlendiricisi."""

from fastapi import APIRouter

from app.api.v1 import categories, grid, logos, players, rooms

api_router = APIRouter()
api_router.include_router(grid.router)
api_router.include_router(players.router)
api_router.include_router(logos.router)
api_router.include_router(rooms.router)
api_router.include_router(categories.router)
