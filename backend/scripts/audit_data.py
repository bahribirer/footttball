"""Veri bütünlüğü raporu: bayrak, logo, fotoğraf kapsamı.

Kullanım (backend kökünden):
    python scripts/audit_data.py            # rapor
    python scripts/audit_data.py --json     # makine okunur

Aynı ölçümler tests/test_data_quality.py'de eşiklerle korunuyor.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent.parent))

from app.db.database import fetch_all, fetch_one  # noqa: E402
from app.services import logo_service  # noqa: E402
from app.services import player_service as ps  # noqa: E402
from app.services.country_service import get_iso_code  # noqa: E402

DART_CATALOG = Path(__file__).resolve().parent.parent.parent / "lib" / "data" / "services" / "country_catalog.dart"


def countries() -> dict:
    names = {r["c"] for r in fetch_all(
        "SELECT DISTINCT country_of_citizenship c FROM players WHERE c IS NOT NULL AND c <> ''")}
    names |= {r["c"] for r in fetch_all(
        "SELECT DISTINCT country c FROM club_history WHERE c IS NOT NULL AND c <> ''")}
    no_code = sorted(c for c in names if not get_iso_code(c))
    dart_missing: list[str] = []
    if DART_CATALOG.exists():
        text = DART_CATALOG.read_text()
        block = text[text.index("_isoByName"):]
        keys = set(re.findall(r"^\s+'((?:[^'\\]|\\.)+)': '", block, re.M))
        keys = {k.replace("\\'", "'") for k in keys}
        dart_missing = sorted(c for c in names if c not in keys)
    return {"total": len(names), "without_flag_code": no_code, "missing_in_client": dart_missing}


def clubs() -> dict:
    names = {r["c"] for r in fetch_all(
        "SELECT DISTINCT current_club_name c FROM players WHERE last_season >= 2022 AND c IS NOT NULL")}
    names |= {r["c"] for r in fetch_all("SELECT DISTINCT club_name c FROM club_history WHERE c IS NOT NULL")}
    names = {c for c in names if not c.startswith("Retired") and "Without Club" not in c}
    with_url = {r["name"] for r in fetch_all("SELECT name FROM clubs WHERE logo_url IS NOT NULL AND logo_url <> ''")}
    no_source = sorted(c for c in names if c not in with_url and not logo_service.cached_logo_path(c))
    no_cache = sorted(c for c in names if not logo_service.cached_logo_path(c))
    return {"total": len(names), "without_logo_source": no_source, "not_cached_locally": len(no_cache)}


def photos() -> dict:
    def ratio(sql: str) -> tuple[int, int]:
        rows = fetch_all(sql)
        have = sum(1 for r in rows if ps.photo_for(r["n"], r["img"]))
        return have, len(rows)

    current = ratio("""SELECT name_normalized n, image_url img FROM players WHERE last_season >= 2024""")
    recent = ratio("""SELECT name_normalized n, image_url img FROM players WHERE last_season >= 2022""")
    # efsaneler: büyük kulüp sayısı ≥ 3
    weights = ps._club_weights()
    rows = fetch_all("""SELECT ch.name_normalized n, MAX(ch.start_year) ly, GROUP_CONCAT(DISTINCT ch.club_name) clubs
                        FROM club_history ch LEFT JOIN players p ON p.name_normalized = ch.name_normalized
                        WHERE p.name_normalized IS NULL GROUP BY ch.name_normalized""")
    legends = []
    for r in rows:
        if (r["ly"] or 0) < 1970:
            continue
        big = {ps.normalize(c) for c in (r["clubs"] or "").split(",") if weights.get(c, 0) > 0}
        if len({" ".join(sorted(x.split())) for x in big}) >= 3:
            legends.append(r["n"])
    legend_have = sum(1 for n in legends if ps.photo_for(n))
    return {
        "players_2024": {"with_photo": current[0], "total": current[1]},
        "players_2022": {"with_photo": recent[0], "total": recent[1]},
        "legends_fame3": {"with_photo": legend_have, "total": len(legends)},
    }


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()
    report = {"countries": countries(), "clubs": clubs(), "photos": photos()}
    if args.json:
        print(json.dumps(report, ensure_ascii=False, indent=1))
        return 0
    c, k, p = report["countries"], report["clubs"], report["photos"]
    print(f"Ülkeler: {c['total']} · bayrak kodu olmayan: {len(c['without_flag_code'])} {c['without_flag_code'][:10]}")
    print(f"         istemci kataloğunda olmayan: {len(c['missing_in_client'])} {c['missing_in_client'][:10]}")
    print(f"Kulüpler: {k['total']} · logo kaynağı olmayan: {len(k['without_logo_source'])} {k['without_logo_source'][:10]}"
          f" · yerelde önbelleksiz: {k['not_cached_locally']}")
    for key, v in p.items():
        pct = 100.0 * v["with_photo"] / max(1, v["total"])
        print(f"Fotoğraf {key}: {v['with_photo']}/{v['total']} ({pct:.1f}%)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
