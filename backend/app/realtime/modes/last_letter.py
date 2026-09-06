"""Son Harf — rakibin yazdığı futbolcunun son harfiyle başlayan futbolcu yazılır."""

import asyncio
import unicodedata

from app.realtime.modes.turn_clock import AnswerResult, TurnClockMode
from app.realtime.protocol import GameMode
from app.services import player_service


def last_letter(name: str) -> str:
    """İsmin son harfini aksansız ve küçük harf olarak döndürür."""
    cleaned = "".join(ch for ch in name if ch.isalpha())
    if not cleaned:
        return ""
    decomposed = unicodedata.normalize("NFKD", cleaned[-1])
    base = "".join(ch for ch in decomposed if not unicodedata.combining(ch))
    return base.lower()


def first_letter(name: str) -> str:
    cleaned = "".join(ch for ch in name if ch.isalpha() or ch.isspace()).strip()
    if not cleaned:
        return ""
    decomposed = unicodedata.normalize("NFKD", cleaned[0])
    base = "".join(ch for ch in decomposed if not unicodedata.combining(ch))
    return base.lower()


def _openings(typed: str, canonical: str) -> set[str]:
    """Zincirde kabul edilebilir baş harfler.

    Oyuncu futbolcuyu soyadıyla yazabildiği için ("Messi" → "Lionel Messi"),
    harf kontrolü yazılan metnin, kanonik adın ve soyadın baş harflerini
    birlikte kabul eder.
    """
    letters = {first_letter(typed), first_letter(canonical)}
    words = canonical.split()
    if words:
        letters.add(first_letter(words[-1]))
    return {letter for letter in letters if letter}


class LastLetterMode(TurnClockMode):
    mode_id = GameMode.LAST_LETTER

    def __init__(self, room) -> None:
        super().__init__(room)
        self.required_letter: str | None = None   # ilk hamlede serbest
        self.last_answer: str | None = None

    async def validate_answer(self, answer: str) -> AnswerResult:
        # Önce oyuncu bulunur: kullanıcı "Messi" yazdığında kanonik ad
        # "Lionel Messi" olur ve harf kontrolü ikisini birden kabul eder.
        found = await asyncio.to_thread(player_service.find_player, answer)
        if not found:
            return AnswerResult(False, reason="not_found")

        if self.required_letter and self.required_letter not in _openings(
            answer, found["name"]
        ):
            return AnswerResult(False, reason="wrong_letter")

        return AnswerResult(True, canonical=found["name"], player=found)

    async def on_accepted(self, canonical: str) -> None:
        self.last_answer = canonical
        self.required_letter = last_letter(canonical)

    def round_payload(self) -> dict:
        return {
            "required_letter": self.required_letter,
            "last_answer": self.last_answer,
        }
