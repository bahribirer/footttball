#!/usr/bin/env python3
"""İsim aramasını indeksli hale getiren token tablosunu üretir.

Sorun: soyadla arama `name_normalized LIKE '% messi'` ile yapılıyordu.
Baştan joker içeren LIKE indeks kullanamaz, SQLite her sorguda tabloyu baştan
sona tarıyordu — ölçümde players 43 ms, club_history 64 ms. Tek bir cevap
doğrulaması üç katmana birden baktığı için ~110 ms saf taramaya çıkıyordu.

Çözüm: her ismin kelimeleri ayrı satırlara açılır ve token üzerinde indeks
kurulur. Böylece "messi" araması eşitlik sorgusuna dönüşür.

    python backend/scripts/build_name_tokens.py

Katmanlar yeniden yüklendiğinde (push_data_layers.sh, sync_* betikleri)
tekrar çalıştırılmalı; tablo baştan kurulur, artımlı değildir.
"""

from __future__ import annotations

import os
import sqlite3
import sys
import time

DB_PATH = os.getenv("DB_PATH") or os.path.join(
    os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "data", "tikitakapi.db"
)

# İsim kolonu bu adla duran katmanlar. Hepsinde `name_normalized` var.
SOURCES = ("players", "squad_updates", "club_history")

# Tek harflik parçalar ("a.c.", baş harfler) arama için gürültü; token
# tablosunu şişirmelerinin faydası yok.
MIN_TOKEN_LEN = 2


def _existing_tables(con: sqlite3.Connection) -> list[str]:
    rows = con.execute(
        "SELECT name FROM sqlite_master WHERE type='table' AND name IN (%s)"
        % ",".join("?" * len(SOURCES)),
        SOURCES,
    ).fetchall()
    return [r[0] for r in rows]


def build(con: sqlite3.Connection) -> int:
    tables = _existing_tables(con)
    if not tables:
        raise SystemExit("Kaynak tablo bulunamadi")

    print(f"kaynaklar: {', '.join(tables)}")

    # Geçici tabloya kurup atomik takas: yarıda kalan bir çalıştırma canlı
    # aramayı bozmasın.
    con.executescript(
        """
        DROP TABLE IF EXISTS name_tokens__new;
        CREATE TABLE name_tokens__new (
            token           TEXT NOT NULL,
            name_normalized TEXT NOT NULL
        );
        """
    )

    seen_sql = """
        INSERT INTO name_tokens__new (token, name_normalized)
        SELECT DISTINCT ?, name_normalized FROM {table}
        WHERE name_normalized IS NOT NULL AND name_normalized <> ''
    """

    # Kelimelere ayırma SQL'de zahmetli; Python tarafında yapılıyor.
    total = 0
    for table in tables:
        names = con.execute(
            f"SELECT DISTINCT name_normalized FROM {table} "
            "WHERE name_normalized IS NOT NULL AND name_normalized <> ''"
        ).fetchall()
        batch: list[tuple[str, str]] = []
        for (name,) in names:
            parts = {p for p in str(name).split() if len(p) >= MIN_TOKEN_LEN}
            # Tam ad da token olarak durur; eşitlik yolu tek sorguda çözülür.
            parts.add(str(name))
            batch.extend((token, name) for token in parts)
            if len(batch) >= 50_000:
                con.executemany(
                    "INSERT INTO name_tokens__new (token, name_normalized) VALUES (?, ?)",
                    batch,
                )
                total += len(batch)
                batch.clear()
        if batch:
            con.executemany(
                "INSERT INTO name_tokens__new (token, name_normalized) VALUES (?, ?)", batch
            )
            total += len(batch)
        print(f"  {table}: {len(names)} isim")

    print("  yinelenenler ayikianiyor...")
    con.executescript(
        """
        DROP TABLE IF EXISTS name_tokens__dedup;
        CREATE TABLE name_tokens__dedup AS
            SELECT DISTINCT token, name_normalized FROM name_tokens__new;
        DROP TABLE name_tokens__new;
        ALTER TABLE name_tokens__dedup RENAME TO name_tokens__new;
        CREATE INDEX idx_name_tokens__new ON name_tokens__new(token, name_normalized);
        """
    )

    rows = con.execute("SELECT COUNT(*) FROM name_tokens__new").fetchone()[0]
    if rows == 0:
        raise SystemExit("token tablosu bos kaldi, degisiklik uygulanmadi")

    con.executescript(
        """
        BEGIN;
        DROP TABLE IF EXISTS name_tokens;
        ALTER TABLE name_tokens__new RENAME TO name_tokens;
        DROP INDEX IF EXISTS idx_name_tokens;
        COMMIT;
        """
    )
    # Indeks adi tablo ile birlikte tasindi; kalici adiyla yeniden kurulur.
    con.execute("DROP INDEX IF EXISTS idx_name_tokens__new")
    con.execute("CREATE INDEX IF NOT EXISTS idx_name_tokens ON name_tokens(token, name_normalized)")
    con.commit()
    return rows


def main() -> int:
    if not os.path.exists(DB_PATH):
        print(f"Veritabani yok: {DB_PATH}", file=sys.stderr)
        return 1
    started = time.time()
    con = sqlite3.connect(DB_PATH, timeout=60)
    try:
        rows = build(con)
        con.execute("ANALYZE")
        con.commit()
    finally:
        con.close()
    print(f"✓ name_tokens: {rows} satir, {time.time() - started:.1f} sn")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
