#!/usr/bin/env python3
"""docker-compose.yml'ı servis başına dosyalara böler.

Paketteki servis tanımları elle yazılsaydı kaynakla ayrışırdı: compose'da
bir port ya da ortam değişkeni değişir, USB'yle giden tanım eski kalırdı.
Bunun yerine tanımlar her paket üretiminde kaynaktan türetilir.

Üretilenler:
    _base.yml        ağlar, birimler ve ortak tanımlar
    <servis>.yml     tek servis

update.sh hepsini `-f` ile birleştirir; docker compose üst düzey anahtarları
birleştirdiği için sonuç kaynakla aynı yığındır.

    python3 split_compose.py docker-compose.yml <çıktı-dizini>
"""

import sys
from pathlib import Path

import yaml

HEADER = """# ÜRETİLMİŞ DOSYA — elle düzenlemeyin.
# Kaynak: docker-compose.yml, know-how/build_release.sh tarafından bölündü.
"""


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__)
        return 2

    source = Path(sys.argv[1])
    out = Path(sys.argv[2])
    out.mkdir(parents=True, exist_ok=True)

    compose = yaml.safe_load(source.read_text())
    services = compose.get("services", {})

    # Ortak taban: servisler dışındaki her şey.
    base = {key: value for key, value in compose.items() if key != "services"}
    (out / "_base.yml").write_text(
        HEADER + yaml.safe_dump(base, allow_unicode=True, sort_keys=False)
    )

    for name, definition in services.items():
        # `build` hedef makinede anlamsız: imaj tar'dan yükleniyor, orada
        # kaynak kodu ve derleme aracı yok.
        cleaned = {k: v for k, v in definition.items() if k != "build"}

        # İmaj referansı değişkene çevrilir. Kaynakta üçüncü parti servisler
        # sabit etiket yazıyor (`nginx:1.27-alpine`); öyle kalırsa
        # version.env'deki digest hiç kullanılmaz ve paket "sabitlenmiş"
        # olduğunu sanırken aslında etiketi takip eder.
        image = cleaned.get("image", "")
        variable = f"{name.upper()}_IMAGE"
        if image and not image.startswith("${"):
            cleaned["image"] = "${%s:-%s}" % (variable, image)
        (out / f"{name}.yml").write_text(
            HEADER
            + yaml.safe_dump(
                {"services": {name: cleaned}}, allow_unicode=True, sort_keys=False
            )
        )

    print(f"  {len(services)} servis + _base.yml -> {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
