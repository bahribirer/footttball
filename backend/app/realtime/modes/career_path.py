"""Kariyer Yolu — kulüp yolundan futbolcuyu ilk bilen turu alır.

Tur akışı:
  1. sunucu bir futbolcu seçer; yolu ilk kulüpten güncele kronolojik
  2. başta yalnız ilk kulüp açık, gerisi gizli
  3. her REVEAL_INTERVAL saniyede bir kulüp HERKESE açılır — tur kilitlenmesin
  4. iki oyuncu da yazar; ilk doğru bilen turu alır
  5. süre dolarsa tur puansız biter, çözüm gösterilir

İpucu: her oyuncunun MAÇ boyunca CLUES_PER_MATCH hakkı var, tur başına
değil. İpucu yalnızca KULLANANA bir sonraki gizli kulübü açar — rakibe
göstermez. Böylece ipucu bir yatırım: erken kullanırsan sonraki turlarda
elin boş kalır.

Maç: hedefe (round_count) ilk ulaşan kazanır, 2-0'dan 2-3'e dönebilir.
"""

import asyncio
import logging

from app.core.config import settings
from app.realtime.modes.base import BaseMode
from app.realtime.protocol import ErrorCode, GameMode, ServerMessage, error
from app.services import career_service

logger = logging.getLogger(__name__)

CLUES_PER_MATCH = 3
REVEAL_INTERVAL = 10          # saniye; herkese bir kulüp daha
ANSWER_SECONDS = 60
ROUND_BREAK_SECONDS = 5
OPEN_COUNTDOWN = 3
MAX_ATTEMPTS_PER_ROUND = 5    # spam önlemi; ipucu yerine deneme yağmuru olmasın


class CareerPathMode(BaseMode):
    mode_id = GameMode.CAREER_PATH

    def __init__(self, room) -> None:
        super().__init__(room)
        self.total_rounds: int = int(room.settings.get("round_count") or 3)
        self.max_rounds: int = self.total_rounds * 3 + 3
        self.round: int = 0
        self.phase: str = "idle"
        self.countdown: int = 0

        self.player: dict | None = None
        self.path: list[dict] = []
        self.revealed: int = 0                       # herkese açık kulüp sayısı
        self.private_reveal: dict[int, int] = {}     # slot -> ek açık kulüp (ipucu)
        self.clues_left: dict[int, int] = {}
        self.attempts: dict[int, int] = {}
        self.wrong_guesses: dict[int, list[str]] = {}
        self.round_winner: int | None = None
        self.used_keys: set[str] = set()

        self._answer_event = asyncio.Event()

    # --- akış ------------------------------------------------------------

    async def start(self) -> None:
        self.clues_left = {p.slot: CLUES_PER_MATCH for p in self.room.players}
        await self.room.broadcast({
            "type": ServerMessage.START,
            "mode": self.mode_id,
            "payload": self.state(),
        })
        self.spawn(self._run())

    async def _run(self) -> None:
        round_no = 0
        while not self.finished and round_no < self.max_rounds:
            round_no += 1
            self.round = round_no
            ok = await self._play_round()
            if self.finished:
                return
            if not ok:
                # Havuz tükendiyse maçı mevcut skorla bitir.
                break
            if self._best_score() >= self.total_rounds:
                break
            await asyncio.sleep(ROUND_BREAK_SECONDS)
        await self._finish_match()

    def _best_score(self) -> int:
        return max((p.score for p in self.room.players), default=0)

    async def _play_round(self) -> bool:
        picked = await asyncio.to_thread(career_service.pick_player, self.used_keys)
        if picked is None:
            logger.warning("Kariyer Yolu: futbolcu havuzu tukendi")
            return False
        self.player = picked
        self.path = picked["path"]
        self.used_keys.add(picked["key"])
        self.revealed = 1
        self.private_reveal = {p.slot: 0 for p in self.room.players}
        self.attempts = {p.slot: MAX_ATTEMPTS_PER_ROUND for p in self.room.players}
        self.wrong_guesses = {p.slot: [] for p in self.room.players}
        self.round_winner = None
        self._answer_event.clear()

        await self._countdown("countdown", OPEN_COUNTDOWN)
        await self._answering_phase()
        await self._round_result()
        return True

    async def _countdown(self, phase: str, seconds: int) -> None:
        self.phase = phase
        for remaining in range(seconds, 0, -1):
            self.countdown = remaining
            await self.push_state()
            await asyncio.sleep(1)
        self.countdown = 0

    async def _answering_phase(self) -> None:
        self.phase = "answering"
        self.countdown = ANSWER_SECONDS
        await self.push_state()

        elapsed = 0
        while elapsed < ANSWER_SECONDS:
            if self._answer_event.is_set() or self.finished:
                return
            try:
                await asyncio.wait_for(self._answer_event.wait(), timeout=1)
                return
            except asyncio.TimeoutError:
                pass
            elapsed += 1
            self.countdown = ANSWER_SECONDS - elapsed
            # Zamanla herkese bir kulüp daha; tur asla tamamen tıkanmasın.
            if elapsed % REVEAL_INTERVAL == 0 and self.revealed < len(self.path):
                self.revealed += 1
                await self.emit("club_revealed", index=self.revealed - 1, public=True)
            await self.push_state()
        self.countdown = 0

    async def _round_result(self) -> None:
        self.phase = "round_over"
        self.revealed = len(self.path)   # çözümde tüm yol açılır
        await self.push_state(event="round_over")

    async def _finish_match(self) -> None:
        self.phase = "finished"
        scores = {p.slot: p.score for p in self.room.players}
        if not scores:
            return
        best = max(scores.values())
        winners = [s for s, v in scores.items() if v == best]
        await self.finish(winners[0] if len(winners) == 1 else None, "match_complete")

    # --- hamleler ---------------------------------------------------------

    async def handle_action(self, player, payload: dict) -> None:
        action = payload.get("action")
        if action == "guess":
            await self._handle_guess(player, payload)
        elif action == "clue":
            await self._handle_clue(player)

    async def _handle_guess(self, player, payload: dict) -> None:
        if self.phase != "answering" or self.round_winner is not None:
            await player.send(error(ErrorCode.GAME_NOT_RUNNING, "Cevap aşaması aktif değil."))
            return
        if self.attempts.get(player.slot, 0) <= 0:
            await player.send(error(ErrorCode.INVALID_MESSAGE, "Bu turda deneme hakkın kalmadı."))
            return
        guess = (payload.get("value") or "").strip()
        if not guess or self.player is None:
            return

        correct = await asyncio.to_thread(career_service.matches, guess, self.player["key"])
        if correct:
            self.round_winner = player.slot
            player.score += 1
            await self.emit(
                "correct_answer",
                slot=player.slot,
                answer=self.player["name"],
                image_url=self.player.get("image_url"),
            )
            self._answer_event.set()
            return

        self.attempts[player.slot] -= 1
        self.wrong_guesses[player.slot].append(guess)
        await self.emit("wrong_answer", slot=player.slot, answer=guess,
                        attempts_left=self.attempts[player.slot])
        if all(left <= 0 for left in self.attempts.values()):
            self._answer_event.set()

    async def _handle_clue(self, player) -> None:
        """Yalnızca kullanana bir sonraki gizli kulübü açar."""
        if self.phase != "answering":
            await player.send(error(ErrorCode.GAME_NOT_RUNNING, "Şu an ipucu alınamaz."))
            return
        if self.clues_left.get(player.slot, 0) <= 0:
            await player.send(error(ErrorCode.INVALID_MESSAGE, "İpucu hakkın kalmadı."))
            return
        visible = self._visible_for(player.slot)
        if visible >= len(self.path):
            await player.send(error(ErrorCode.INVALID_MESSAGE, "Yolun tamamı zaten açık."))
            return

        self.clues_left[player.slot] -= 1
        self.private_reveal[player.slot] = self.private_reveal.get(player.slot, 0) + 1
        # Sadece o oyuncuya; rakip ipucu kullanıldığını görür, içeriğini değil.
        await player.send({
            "type": ServerMessage.EVENT,
            "event": "clue_used",
            "slot": player.slot,
            "clues_left": self.clues_left[player.slot],
            "index": visible,
        })
        opponent = self.room.opponent_of(player)
        if opponent:
            await opponent.send({
                "type": ServerMessage.EVENT,
                "event": "opponent_clue",
                "slot": player.slot,
                "clues_left": self.clues_left[player.slot],
            })
        await self.push_state()

    def _visible_for(self, slot: int) -> int:
        return min(len(self.path), self.revealed + self.private_reveal.get(slot, 0))

    # --- durum ------------------------------------------------------------

    def state(self) -> dict:
        """Her oyuncuya kendi görüşüne göre yol gönderilir.

        `path` alanı gizli kulüpleri null bırakır; her oyuncu için ayrı
        olduğundan broadcast'te ortak kısım gider, `visible` sözlüğü ise
        istemcinin kaç kulüp görebileceğini söyler. İstemci kendi slotuna
        bakarak maskeler — ama gizli kulüp adı istemciye HİÇ gitmez; yoksa
        istemci ipucu kullanmadan okuyabilirdi.
        """
        total = len(self.path)
        per_slot = {}
        for p in self.room.players:
            n = self._visible_for(p.slot) if self.phase != "round_over" else total
            per_slot[p.slot] = [
                {"club": c["club"], "start": c["start"], "end": c["end"]} if i < n else None
                for i, c in enumerate(self.path)
            ]
        return {
            "phase": self.phase,
            "round": self.round,
            "total_rounds": self.total_rounds,
            "countdown": self.countdown,
            "path_length": total,
            "paths": per_slot,
            "revealed_public": self.revealed,
            "clues_left": self.clues_left,
            "attempts": self.attempts,
            "wrong_guesses": self.wrong_guesses,
            "round_winner": self.round_winner,
            "solution": self.player["name"] if (self.phase in ("round_over", "finished") and self.player) else None,
            "solution_image": self.player.get("image_url") if (self.phase in ("round_over", "finished") and self.player) else None,
            "solution_nationality": self.player.get("nationality") if (self.phase in ("round_over", "finished") and self.player) else None,
            "scores": {p.slot: p.score for p in self.room.players},
        }

    def snapshot(self) -> dict | None:
        base = super().snapshot() or {}
        base["clues_left"] = self.clues_left
        return base

    def restore(self, data: dict) -> None:
        super().restore(data)
        if data and isinstance(data.get("clues_left"), dict):
            self.clues_left = {int(k): int(v) for k, v in data["clues_left"].items()}
