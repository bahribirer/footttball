"""Oyuncu adları için aksansız arama kolonu ekler.

SQLite'ın `LIKE` işleci aksana duyarlıdır: "Calhanoglu" yazan bir oyuncu
"Hakan Çalhanoğlu" kaydını bulamıyordu. Bu betik her satır için aksansız,
küçük harfli bir kopya üretir ve üzerine indeks kurar.

Yeniden çalıştırılabilir; var olan kolonu günceller.

    python scripts/add_normalized_names.py [veritabanı-yolu]
"""

import sqlite3
import sys
import unicodedata
from pathlib import Path

DEFAULT_DB = Path(__file__).resolve().parent.parent / "data" / "tikitakapi.db"

# NFKD ayrıştırması bu harfleri çözemiyor; elle karşılık verilir.
_TRANSLIT = str.maketrans({
    "ı": "i", "İ": "i", "ß": "ss", "ø": "o", "Ø": "o", "đ": "d", "Đ": "d",
    "ł": "l", "Ł": "l", "æ": "ae", "Æ": "ae", "œ": "oe", "Œ": "oe",
    "ð": "d", "Ð": "d", "þ": "th", "Þ": "th", "ħ": "h", "ŋ": "n",
})


def normalize(text: str | None) -> str:
    """Aksan, büyük/küçük harf ve fazla boşluk farklarını siler."""
    if not text:
        return ""
    translated = text.translate(_TRANSLIT)
    decomposed = unicodedata.normalize("NFKD", translated)
    stripped = "".join(ch for ch in decomposed if not unicodedata.combining(ch))
    return " ".join(stripped.lower().split())


def main(db_path: Path) -> None:
    con = sqlite3.connect(db_path)
    cur = con.cursor()

    columns = {row[1] for row in cur.execute("PRAGMA table_info(players)")}
    if "name_normalized" not in columns:
        cur.execute("ALTER TABLE players ADD COLUMN name_normalized TEXT")
        print("• name_normalized kolonu eklendi")
    else:
        print("• name_normalized kolonu zaten var, güncelleniyor")

    rows = cur.execute("SELECT rowid, name FROM players").fetchall()
    updates = [(normalize(name), rowid) for rowid, name in rows]
    cur.executemany("UPDATE players SET name_normalized = ? WHERE rowid = ?", updates)
    print(f"• {len(updates)} satır normalize edildi")

    cur.execute(
        "CREATE INDEX IF NOT EXISTS idx_players_name_normalized "
        "ON players(name_normalized)"
    )
    # Arama sonuçları en güncel sezona göre sıralandığı için bu indeks de eklenir.
    cur.execute(
        "CREATE INDEX IF NOT EXISTS idx_players_last_season "
        "ON players(last_season DESC)"
    )
    print("• indeksler hazır")

    con.commit()

    sample = cur.execute(
        "SELECT name, name_normalized FROM players "
        "WHERE name_normalized LIKE '%calhanoglu%' LIMIT 3"
    ).fetchall()
    print("• doğrulama (calhanoglu):", sample or "sonuç yok")

    con.close()


if __name__ == "__main__":
    path = Path(sys.argv[1]) if len(sys.argv) > 1 else DEFAULT_DB
    if not path.exists():
        raise SystemExit(f"Veritabanı bulunamadı: {path}")
    main(path)
