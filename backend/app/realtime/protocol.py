"""WebSocket protokolü v2 — mesaj tipleri ve yardımcıları.

Tüm mesajlar JSON'dur ve `type` alanı taşır. Eski protokolde düz metin
("ready", "X", "O") ile JSON karışıktı; bu belirsizlik ayıklandı.
"""

from enum import StrEnum


class ClientMessage(StrEnum):
    PING = "ping"
    READY = "ready"
    RELAY = "relay"          # oyun mantığı istemcide olan modlar için ham aktarım
    ACTION = "action"        # sunucu yönetimli modlarda oyun hamlesi
    REMATCH = "rematch"
    LEAVE = "leave"


class ServerMessage(StrEnum):
    PONG = "pong"
    JOINED = "joined"        # bağlanan oyuncuya kimlik + oda bilgisi
    ROOM = "room"            # oda/oyuncu listesi değişti
    START = "start"          # oyun başladı
    STATE = "state"          # moda özgü tam durum
    EVENT = "event"          # anlık olay (doğru cevap, ceza, tur değişimi...)
    OVER = "over"            # oyun bitti
    RELAY = "relay"          # rakipten gelen ham mesaj
    OPPONENT_LEFT = "opponent_left"
    ERROR = "error"


class ErrorCode(StrEnum):
    ROOM_FULL = "room_full"
    ROOM_NOT_FOUND = "room_not_found"
    MODE_MISMATCH = "mode_mismatch"
    INVALID_MESSAGE = "invalid_message"
    NOT_YOUR_TURN = "not_your_turn"
    GAME_NOT_RUNNING = "game_not_running"


class GameMode(StrEnum):
    TIKI_TAKA_TOE = "tiki_taka_toe"
    PLAYER_GUESS = "player_guess"
    LAST_LETTER = "last_letter"
    CATEGORY_RACE = "category_race"


def error(code: ErrorCode, message: str) -> dict:
    return {"type": ServerMessage.ERROR, "code": code, "message": message}
