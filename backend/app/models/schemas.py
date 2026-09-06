"""İstek/yanıt şemaları."""

from pydantic import BaseModel, Field

from app.realtime.protocol import GameMode


class PlayerInfo(BaseModel):
    """Tiki Taka Toe tahmin doğrulaması (eski istemcilerle uyumlu)."""
    player_name: str
    nationality: str
    club: str


class GridResponse(BaseModel):
    nations: list[str]
    clubs: list[str]


class CreateRoomRequest(BaseModel):
    mode: GameMode = GameMode.TIKI_TAKA_TOE
    league_id: str | None = None
    round_count: int | None = Field(default=None, ge=1, le=9)
    clock_seconds: int | None = Field(default=None, ge=10, le=300)
    category_id: str | None = None


class CreateRoomResponse(BaseModel):
    code: str
    mode: GameMode
    settings: dict


class RoomStatusResponse(BaseModel):
    room_exists: bool
    is_joinable: bool
    mode: str | None = None
    players: int = 0


class CategoryResponse(BaseModel):
    id: str
    label: str
    # "easy" | "medium" | "hard" — oda kurma ekranında rozet olarak gösterilir.
    difficulty: str = "medium"
