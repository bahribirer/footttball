"""Satranç saati mantığıyla çalışan modlar için ortak temel.

Her oyuncunun kendine ait bir süresi vardır ve yalnızca sırası gelen oyuncunun
saati işler. Yanlış cevap sırayı devretmez, süreden ceza düşer. Süresi biten
oyuncu kaybeder.
"""

import asyncio
import random
from dataclasses import dataclass

from app.core.config import settings
from app.realtime.modes.base import BaseMode
from app.realtime.protocol import ErrorCode, ServerMessage, error
from app.services.player_service import normalize

TICK_SECONDS = 1.0


@dataclass
class AnswerResult:
    ok: bool
    canonical: str | None = None
    reason: str | None = None      # hata sebebi: not_found / wrong_letter / duplicate / off_category
    player: dict | None = None     # kabul edilen oyuncunun görseli, kulübü, ülkesi


class TurnClockMode(BaseMode):
    """Alt sınıflar `validate_answer` ve `round_payload` uygular."""

    def __init__(self, room) -> None:
        super().__init__(room)
        self.clock_seconds: int = int(room.settings.get("clock_seconds") or settings.CLOCK_SECONDS)
        self.penalty: int = int(room.settings.get("penalty") or settings.WRONG_ANSWER_PENALTY)
        self.clocks: dict[int, float] = {}
        self.current_turn: int = 0
        self.history: list[dict] = []
        self.used: set[str] = set()
        self.phase: str = "idle"
        self._turn_lock = asyncio.Lock()

    # --- yaşam döngüsü ---------------------------------------------------

    async def start(self) -> None:
        self.clocks = {player.slot: float(self.clock_seconds) for player in self.room.players}
        self.current_turn = random.choice([player.slot for player in self.room.players])
        self.phase = "playing"

        await self.prepare()
        await self.room.broadcast({
            "type": ServerMessage.START,
            "mode": self.mode_id,
            "payload": self.state(),
        })
        self.spawn(self._tick_loop())

    async def prepare(self) -> None:
        """Oyun başlamadan önce moda özgü hazırlık (kategori seçimi vb.)."""

    async def _tick_loop(self) -> None:
        while not self.finished:
            await asyncio.sleep(TICK_SECONDS)
            if self.finished or self.phase != "playing":
                continue

            slot = self.current_turn
            self.clocks[slot] = max(0.0, self.clocks[slot] - TICK_SECONDS)

            if self.clocks[slot] <= 0:
                await self._timeout(slot)
                return

            await self.push_state()

    async def _timeout(self, slot: int) -> None:
        self.phase = "finished"
        opponent = next((s for s in self.clocks if s != slot), None)
        await self.emit("time_up", slot=slot)
        await self.finish(opponent, "timeout")

    # --- hamleler --------------------------------------------------------

    async def handle_action(self, player, payload: dict) -> None:
        if payload.get("action") != "answer":
            return

        if self.phase != "playing" or self.finished:
            await player.send(error(ErrorCode.GAME_NOT_RUNNING, "Oyun aktif değil."))
            return

        if player.slot != self.current_turn:
            await player.send(error(ErrorCode.NOT_YOUR_TURN, "Sıra sende değil."))
            return

        answer = (payload.get("value") or "").strip()
        if not answer:
            return

        async with self._turn_lock:
            if player.slot != self.current_turn or self.finished:
                return

            if normalize(answer) in self.used:
                await self._apply_penalty(player, answer, "duplicate")
                return

            result = await self.validate_answer(answer)
            if not result.ok:
                await self._apply_penalty(player, answer, result.reason or "invalid")
                return

            canonical = result.canonical or answer
            info = result.player or {}
            self.used.add(normalize(canonical))
            self.history.append({
                "slot": player.slot,
                "answer": canonical,
                "image_url": info.get("image_url"),
                "club": info.get("club"),
                "country": info.get("country"),
            })
            player.score += 1

            await self.on_accepted(canonical)
            self.current_turn = 1 - player.slot
            await self.emit(
                "accepted",
                slot=player.slot,
                answer=canonical,
                image_url=info.get("image_url"),
                club=info.get("club"),
                country=info.get("country"),
            )
            await self.push_state()

    async def _apply_penalty(self, player, answer: str, reason: str) -> None:
        self.clocks[player.slot] = max(0.0, self.clocks[player.slot] - self.penalty)
        await self.emit(
            "rejected",
            slot=player.slot,
            answer=answer,
            reason=reason,
            penalty=self.penalty,
        )

        if self.clocks[player.slot] <= 0:
            await self._timeout(player.slot)
            return

        await self.push_state()

    # --- alt sınıf kancaları ---------------------------------------------

    async def validate_answer(self, answer: str) -> AnswerResult:
        raise NotImplementedError

    async def on_accepted(self, canonical: str) -> None:
        """Kabul edilen cevaptan sonra moda özgü durum güncellemesi."""

    def round_payload(self) -> dict:
        return {}

    # --- durum ------------------------------------------------------------

    def state(self) -> dict:
        return {
            "phase": self.phase,
            "current_turn": self.current_turn,
            "clocks": {slot: round(value, 1) for slot, value in self.clocks.items()},
            "penalty": self.penalty,
            "history": self.history[-12:],
            "scores": {player.slot: player.score for player in self.room.players},
            **self.round_payload(),
        }
