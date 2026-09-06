"""Oyuncu Tahmin — millet x kulüp eşleşmesine uyan futbolcuyu ilk bilen kazanır.

Tur akışı:
  1. hazırlık geri sayımı (5)
  2. seçim: bir oyuncuya 5 milli takım, diğerine 5 kulüp gelir
  3. açılış geri sayımı (3)
  4. cevap: iki oyuncu da yazar, ilk doğru bilen turu alır (3 deneme hakkı)

Kimsenin bilemediği turlarda sayacın dolmasını beklemek oyunun ritmini
bozuyordu; bir oyuncu pas teklif eder, rakip kabul ederse tur puansız
kapanır. Akış Tiki Taka Toe'daki rövanş isteğiyle aynı mantıkta.
"""

import asyncio
import logging

from app.core.config import settings
from app.realtime.modes.base import BaseMode
from app.realtime.protocol import ErrorCode, GameMode, ServerMessage, error
from app.services import player_service, pool_service

logger = logging.getLogger(__name__)

PICK_SECONDS = 12
ROUND_BREAK_SECONDS = 4


class PlayerGuessMode(BaseMode):
    mode_id = GameMode.PLAYER_GUESS

    def __init__(self, room) -> None:
        super().__init__(room)
        self.total_rounds: int = int(room.settings.get("round_count") or settings.PG_ROUNDS)
        # Puansız (kimsenin bilemediği) turlar seriyi uzatabilir;
        # maçın sonsuza gitmemesi için tavan konur.
        self.max_rounds: int = self.total_rounds * 3 + 3
        self.round: int = 0
        self.phase: str = "idle"
        self.countdown: int = 0

        self.nations: list[str] = []
        self.clubs: list[str] = []
        self.selected_nation: str | None = None
        self.selected_club: str | None = None

        self.attempts: dict[int, int] = {}
        self.wrong_guesses: dict[int, list[str]] = {}
        self.round_winner: int | None = None
        # Bekleyen pas teklifini veren oyuncunun slotu.
        self.pass_request_by: int | None = None
        # Teklifi bu turda reddedilenler; aynı turda tekrar soramazlar.
        self.pass_blocked: set[int] = set()
        self.solution: str | None = None
        self.solution_image: str | None = None

        self._pick_event = asyncio.Event()
        self._answer_event = asyncio.Event()

    # --- roller ----------------------------------------------------------

    @property
    def nation_picker(self) -> int:
        """Tur başına dönüşümlü: tek turlarda 0. oyuncu milleti seçer."""
        return 0 if self.round % 2 == 1 else 1

    @property
    def club_picker(self) -> int:
        return 1 - self.nation_picker

    # --- akış ------------------------------------------------------------

    async def start(self) -> None:
        await self.room.broadcast({
            "type": ServerMessage.START,
            "mode": self.mode_id,
            "payload": {"total_rounds": self.total_rounds},
        })
        self.spawn(self._run())

    async def _run(self) -> None:
        """Turu ilk `total_rounds` kez kazanan maçı alır.

        Eskiden sabit sayıda tur oynanıp en çok puanı toplayan kazanıyordu;
        kurucunun seçtiği sayı bir hedef değil, maç uzunluğu oluyordu. Artık
        seri 2-0'dan 2-3'e dönebilir. Berabere biten turlar kimseye puan
        yazmadığı için üst sınır konur.
        """
        round_no = 0
        while not self.finished and round_no < self.max_rounds:
            round_no += 1
            self.round = round_no
            await self._play_round()
            if self.finished:
                return
            if self._best_score() >= self.total_rounds:
                break
            await asyncio.sleep(ROUND_BREAK_SECONDS)

        await self._finish_match()

    def _best_score(self) -> int:
        return max((player.score for player in self.room.players), default=0)

    async def _play_round(self) -> None:
        self.selected_nation = None
        self.selected_club = None
        self.round_winner = None
        self.pass_request_by = None
        self.pass_blocked = set()
        self.solution = None
        self.solution_image = None
        self.attempts = {player.slot: settings.PG_MAX_ATTEMPTS for player in self.room.players}
        self.wrong_guesses = {player.slot: [] for player in self.room.players}
        self._pick_event.clear()
        self._answer_event.clear()

        self.nations, self.clubs = await asyncio.to_thread(pool_service.build_duel_board)

        await self._countdown("countdown", settings.PG_PICK_COUNTDOWN)
        await self._picking_phase()
        await self._countdown("revealing", settings.PG_ANSWER_COUNTDOWN)
        await self._answering_phase()
        await self._round_result()

    async def _countdown(self, phase: str, seconds: int) -> None:
        self.phase = phase
        for remaining in range(seconds, 0, -1):
            self.countdown = remaining
            await self.push_state()
            await asyncio.sleep(1)
        self.countdown = 0

    async def _picking_phase(self) -> None:
        self.phase = "picking"
        self.countdown = PICK_SECONDS
        await self.push_state()

        try:
            await asyncio.wait_for(self._wait_for_picks(), timeout=PICK_SECONDS)
        except asyncio.TimeoutError:
            pass

        # Seçmeyen oyuncu için rastgele tamamla.
        import random
        if self.selected_nation is None:
            self.selected_nation = random.choice(self.nations)
        if self.selected_club is None:
            self.selected_club = random.choice(self.clubs)

        await self.emit(
            "pick_complete",
            nation=self.selected_nation,
            club=self.selected_club,
        )

    async def _wait_for_picks(self) -> None:
        while self.selected_nation is None or self.selected_club is None:
            self._pick_event.clear()
            await self._pick_event.wait()

    async def _answering_phase(self) -> None:
        self.phase = "answering"
        self.countdown = settings.PG_ANSWER_SECONDS
        await self.push_state()

        for remaining in range(settings.PG_ANSWER_SECONDS, 0, -1):
            if self._answer_event.is_set() or self.finished:
                return
            self.countdown = remaining
            await self.push_state()
            try:
                await asyncio.wait_for(self._answer_event.wait(), timeout=1)
                return
            except asyncio.TimeoutError:
                continue
        self.countdown = 0

    async def _round_result(self) -> None:
        self.phase = "round_over"
        self.pass_request_by = None
        if self.solution is None and self.selected_nation and self.selected_club:
            example = await asyncio.to_thread(
                self._find_example, self.selected_nation, self.selected_club
            )
            if example:
                self.solution = example["name"]
                self.solution_image = example["image_url"]
        await self.push_state(event="round_over")

    @staticmethod
    def _find_example(nation: str, club: str) -> dict | None:
        """Tur sonunda gösterilecek örnek doğru cevap."""
        from app.db.database import fetch_one
        row = fetch_one(
            """SELECT name, image_url FROM players
               WHERE country_of_citizenship = ? AND current_club_name = ?
               ORDER BY CAST(COALESCE(market_value_in_eur, '0') AS INTEGER) DESC
               LIMIT 1""",
            (nation, club),
        )
        return {"name": row["name"], "image_url": row["image_url"]} if row else None

    async def _finish_match(self) -> None:
        self.phase = "finished"
        scores = {player.slot: player.score for player in self.room.players}
        if not scores:
            return
        best = max(scores.values())
        winners = [slot for slot, score in scores.items() if score == best]
        winner = winners[0] if len(winners) == 1 else None
        await self.finish(winner, "match_complete")

    # --- istemci hamleleri ------------------------------------------------

    async def handle_action(self, player, payload: dict) -> None:
        action = payload.get("action")
        if action == "pick":
            await self._handle_pick(player, payload)
        elif action == "guess":
            await self._handle_guess(player, payload)
        elif action == "pass_request":
            await self._handle_pass_request(player)
        elif action == "pass_response":
            await self._handle_pass_response(player, payload)

    async def _handle_pick(self, player, payload: dict) -> None:
        if self.phase != "picking":
            await player.send(error(ErrorCode.GAME_NOT_RUNNING, "Şu an seçim aşaması değil."))
            return

        value = (payload.get("value") or "").strip()
        if player.slot == self.nation_picker:
            if value not in self.nations or self.selected_nation is not None:
                return
            self.selected_nation = value
        elif player.slot == self.club_picker:
            if value not in self.clubs or self.selected_club is not None:
                return
            self.selected_club = value
        else:
            return

        self._pick_event.set()
        await self.push_state(event="picked")

    async def _handle_guess(self, player, payload: dict) -> None:
        if self.phase != "answering" or self.round_winner is not None:
            await player.send(error(ErrorCode.GAME_NOT_RUNNING, "Cevap aşaması aktif değil."))
            return

        if self.attempts.get(player.slot, 0) <= 0:
            await player.send(error(ErrorCode.INVALID_MESSAGE, "Deneme hakkın kalmadı."))
            return

        guess = (payload.get("value") or "").strip()
        if not guess:
            return

        correct = await asyncio.to_thread(
            player_service.verify_player, guess, self.selected_nation, self.selected_club
        )

        if correct:
            found = await asyncio.to_thread(player_service.find_player, guess)
            self.round_winner = player.slot
            self.solution = found["name"] if found else guess
            self.solution_image = found.get("image_url") if found else None
            player.score += 1
            await self.emit(
                "correct_answer",
                slot=player.slot,
                answer=self.solution,
                image_url=self.solution_image,
            )
            self._answer_event.set()
            return

        self.attempts[player.slot] -= 1
        self.wrong_guesses[player.slot].append(guess)
        await self.emit(
            "wrong_answer",
            slot=player.slot,
            answer=guess,
            attempts_left=self.attempts[player.slot],
        )

        # İki oyuncunun da hakkı bittiyse turu erken kapat.
        if all(left <= 0 for left in self.attempts.values()):
            self._answer_event.set()

    # --- pas teklifi ------------------------------------------------------

    async def _handle_pass_request(self, player) -> None:
        """Turu atlama teklifi gönderir; karar rakibindir."""
        if self.phase != "answering" or self.round_winner is not None:
            await player.send(error(ErrorCode.GAME_NOT_RUNNING, "Şu an pas verilemez."))
            return
        if self.pass_request_by is not None:
            return
        if player.slot in self.pass_blocked:
            await player.send(
                error(ErrorCode.INVALID_MESSAGE, "Bu turda pas teklifin zaten reddedildi.")
            )
            return
        if self.room.opponent_of(player) is None:
            return

        self.pass_request_by = player.slot
        await self.emit("pass_requested", slot=player.slot)
        await self.push_state()

    async def _handle_pass_response(self, player, payload: dict) -> None:
        """Teklifi yalnızca rakip yanıtlayabilir."""
        if self.pass_request_by is None or player.slot == self.pass_request_by:
            return

        requester = self.pass_request_by
        self.pass_request_by = None

        if self.phase != "answering":
            await self.push_state()
            return

        if payload.get("accept") is True:
            await self.emit("pass_accepted", slot=requester)
            # Tur kimseye puan yazmadan kapanır; _round_result örnek cevabı gösterir.
            self._answer_event.set()
            return

        self.pass_blocked.add(requester)
        await self.emit("pass_declined", slot=requester)
        await self.push_state()

    # --- durum ------------------------------------------------------------

    def state(self) -> dict:
        return {
            "phase": self.phase,
            "round": self.round,
            "total_rounds": self.total_rounds,
            "countdown": self.countdown,
            "nations": self.nations,
            "clubs": self.clubs,
            "nation_picker": self.nation_picker,
            "club_picker": self.club_picker,
            "selected_nation": self.selected_nation,
            "selected_club": self.selected_club,
            "attempts": self.attempts,
            "wrong_guesses": self.wrong_guesses,
            "round_winner": self.round_winner,
            "pass_request_by": self.pass_request_by,
            "pass_blocked": sorted(self.pass_blocked),
            "solution": self.solution,
            "solution_image": self.solution_image,
            "scores": {player.slot: player.score for player in self.room.players},
        }
