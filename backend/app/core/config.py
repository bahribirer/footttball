"""Uygulama ayarları. Tüm yollar ve ayarlanabilir değerler tek yerden okunur."""

import os
from pathlib import Path

# backend/app/core/config.py -> backend/
BASE_DIR = Path(__file__).resolve().parent.parent.parent


class Settings:
    # Ortam
    ENVIRONMENT: str = os.getenv("ENVIRONMENT", "development")
    DEBUG: bool = os.getenv("DEBUG", "false").lower() == "true"

    # Veri
    DB_PATH: str = os.getenv("DB_PATH", str(BASE_DIR / "data" / "tikitakapi.db"))
    LOGO_DIR: str = os.getenv("LOGO_DIR", str(BASE_DIR / "static" / "logos"))

    # Dış servisler
    TSDB_API: str = "https://www.thesportsdb.com/api/v1/json/3/searchteams.php"
    BROWSER_UA: str = (
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
        "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36"
    )
    HTTP_TIMEOUT: int = int(os.getenv("HTTP_TIMEOUT", "8"))

    # Oyun / oda
    ROOM_CODE_LENGTH: int = 4
    MAX_PLAYERS_PER_ROOM: int = 2
    WS_HEARTBEAT_SECONDS: int = int(os.getenv("WS_HEARTBEAT_SECONDS", "25"))
    WS_IDLE_TIMEOUT_SECONDS: int = int(os.getenv("WS_IDLE_TIMEOUT_SECONDS", "90"))
    EMPTY_ROOM_TTL_SECONDS: int = int(os.getenv("EMPTY_ROOM_TTL_SECONDS", "120"))
    # Kurucu lig/kategori/süre seçerken oda kimse bağlanmadan bekler; kısa
    # ömür, seçimi uzatan oyuncunun odasını ayar kaydedilmeden siliyordu.
    RESERVED_ROOM_TTL_SECONDS: int = int(os.getenv("RESERVED_ROOM_TTL_SECONDS", "1800"))

    # Tiki Taka Toe
    TTT_TURN_SECONDS: int = 30

    # Oyuncu Tahmin
    PG_PICK_COUNTDOWN: int = 5      # seçim ekranı geri sayımı
    PG_ANSWER_COUNTDOWN: int = 3    # cevap öncesi geri sayım
    PG_ANSWER_SECONDS: int = 30     # cevap süresi
    PG_MAX_ATTEMPTS: int = 3        # oyuncu başına deneme hakkı
    PG_ROUNDS: int = 5              # varsayılan raunt sayısı

    # Son Harf & Kategori Yarışı
    CLOCK_SECONDS: int = 50         # oyuncu başına toplam süre
    WRONG_ANSWER_PENALTY: int = 3   # yanlış cevap cezası (saniye)


settings = Settings()
