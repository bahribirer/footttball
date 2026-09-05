"""Oda kayıt defteri: oluşturma, katılma, ayrılma ve temizlik."""

import asyncio
import logging
import random
import string
import time

from fastapi import WebSocket

from app.core.config import settings
from app.realtime.modes.base import BaseMode
from app.realtime.modes.category_race import CategoryRaceMode
from app.realtime.modes.last_letter import LastLetterMode
from app.realtime.modes.player_guess import PlayerGuessMode
from app.realtime.modes.tiki_taka_toe import TikiTakaToeMode
from app.realtime.protocol import GameMode
from app.realtime.room import Player, Room

logger = logging.getLogger(__name__)

MODE_ENGINES: dict[str, type[BaseMode]] = {
    GameMode.TIKI_TAKA_TOE: TikiTakaToeMode,
    GameMode.PLAYER_GUESS: PlayerGuessMode,
    GameMode.LAST_LETTER: LastLetterMode,
    GameMode.CATEGORY_RACE: CategoryRaceMode,
}


class RoomFull(Exception):
    pass


class RoomNotFound(Exception):
    pass


class ModeMismatch(Exception):
    def __init__(self, expected: str) -> None:
        super().__init__(expected)
        self.expected = expected


class RoomHub:
    def __init__(self) -> None:
        self._rooms: dict[str, Room] = {}
        self._lock = asyncio.Lock()

    # --- oda yaşam döngüsü ------------------------------------------------

    def generate_code(self) -> str:
        """Kullanımda olmayan bir oda kodu üretir."""
        for _ in range(50):
            code = "".join(random.choices(string.digits, k=settings.ROOM_CODE_LENGTH))
            if code not in self._rooms:
                return code
        raise RuntimeError("Boş oda kodu bulunamadı")

    async def reserve(self, mode: str, room_settings: dict | None = None) -> Room:
        """İstemci bağlanmadan önce odayı rezerve eder (kod çakışmasını önler)."""
        async with self._lock:
            code = self.generate_code()
            room = Room(code=code, mode=GameMode(mode), settings=room_settings or {})
            room.emptied_at = time.time()
            self._rooms[code] = room
            return room

    async def join(self, code: str, socket: WebSocket, name: str, mode: str | None) -> tuple[Room, Player]:
        async with self._lock:
            room = self._rooms.get(code)

            # Oda yalnızca `POST /api/v1/rooms` ile kurulur. Bağlanırken oda
            # yaratmak, katılma ekranına yazılan her kodun yeni bir oda
            # açmasına yol açıyordu.
            if room is None:
                raise RoomNotFound(code)

            if mode and room.mode != mode:
                raise ModeMismatch(room.mode)

            active = [player for player in room.players if player.connected]
            if len(active) >= settings.MAX_PLAYERS_PER_ROOM:
                raise RoomFull(code)

            # Kopmuş oyuncu kayıtlarını temizle, slotu geri kazan.
            room.players = active

            player = Player(socket=socket, name=name or f"Oyuncu {room.next_free_slot() + 1}",
                            slot=room.next_free_slot())
            room.players.append(player)
            room.emptied_at = None
            room.had_players = True
            return room, player

    async def leave(self, room: Room, player: Player) -> None:
        async with self._lock:
            player.connected = False
            if player in room.players:
                room.players.remove(player)
            if room.is_empty:
                room.emptied_at = time.time()

        if room.engine:
            await room.engine.on_player_left(player)

    async def drop_room(self, code: str) -> None:
        async with self._lock:
            self._rooms.pop(code, None)

    # --- sorgular ---------------------------------------------------------

    def get(self, code: str) -> Room | None:
        return self._rooms.get(code)

    def room_status(self, code: str) -> dict:
        room = self._rooms.get(code)
        if room is None:
            return {"room_exists": False, "is_joinable": False}

        active = len([player for player in room.players if player.connected])
        return {
            "room_exists": True,
            "is_joinable": active < settings.MAX_PLAYERS_PER_ROOM,
            "mode": room.mode,
            "players": active,
            "settings": room.settings,
        }

    # --- motor ------------------------------------------------------------

    def build_engine(self, room: Room) -> BaseMode:
        engine_cls = MODE_ENGINES[room.mode]
        room.engine = engine_cls(room)
        return room.engine

    # --- bakım ------------------------------------------------------------

    async def cleanup_loop(self) -> None:
        """Boş kalan odaları belirli bir süre sonra siler."""
        while True:
            await asyncio.sleep(30)
            try:
                now = time.time()
                async with self._lock:
                    stale = [
                        code for code, room in self._rooms.items()
                        if room.is_empty
                        and room.emptied_at
                        and now - room.emptied_at > (
                            settings.EMPTY_ROOM_TTL_SECONDS if room.had_players
                            else settings.RESERVED_ROOM_TTL_SECONDS
                        )
                    ]
                    for code in stale:
                        room = self._rooms.pop(code, None)
                        if room and room.engine:
                            await room.engine.stop()
                if stale:
                    logger.info("Boş oda temizlendi: %s", ", ".join(stale))
            except asyncio.CancelledError:
                raise
            except Exception:
                logger.exception("Oda temizliği başarısız")


hub = RoomHub()
