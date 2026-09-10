#!/usr/bin/env python3
"""docker-compose.yml'ı servis başına dosyalara böler.

Paketteki servis tanımları elle yazılsaydı kaynakla ayrışırdı: compose'da
bir port ya da ortam değişkeni değişir, USB'yle giden tanım eski kalırdı.
Bunun yerine tanımlar her paket üretiminde kaynaktan türetilir.

Servis tanımları compose'daki hâlleriyle birebir aynıdır; tek fark `build`
anahtarının düşmesi (hedef makinede kaynak kod ve derleme aracı yok).

Bir de bind bağlamaları ve portlar değişkene çevrilir. Kaynakta bunlar sabit
yazılı (`./infra/certbot/conf`, `80:80`); hedef makinenin dizin yapısı ya da
kullandığı portlar farklı olabilir. Değişkenler bind_defaults.env dosyasına
varsayılanlarıyla yazılır, build_release.sh onları version.env'e taşır.

Değişken adı SERVİSTEN değil YOLDAN türetilir: aynı host dizini birden fazla
serviste geçebiliyor (certbot yapılandırması hem nginx'te hem certbot'ta) ve
servise göre adlandırılsaydı aynı dizin iki ad alıp yanlışlıkla farklı
yerlere bakabilirdi.

Üretilenler:
    _base.yml           ağlar, birimler ve ortak tanımlar
    <servis>.yml        tek servis
    bind_defaults.env   bind ve port değişkenleri, varsayılanlarıyla

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


# Konteyner portundan okunabilir değişken adı.
PORT_NAMES = {"80": "HTTP_PORT", "443": "HTTPS_PORT", "8000": "BACKEND_PORT"}


def path_variable(source: str, base: Path) -> tuple[str, str]:
    """Host yolundan değişken adı türetir.

    ./infra/nginx/nginx.conf -> INFRA_NGINX_CONF_FILE
    ./infra/nginx/conf.d     -> INFRA_NGINX_CONFD_DIR
    ./backend/data           -> BACKEND_DATA_DIR

    Ardışık tekrar eden parçalar ayıklanır, yoksa "nginx/nginx.conf"
    INFRA_NGINX_NGINX_CONF gibi okunmaz bir ad üretirdi.

    DIR/FILE eki dosya sisteminden okunur. Uzantıya bakmak yanıltıyordu:
    "conf.d" nokta içerdiği için dosya sanılıp _FILE ekini alıyordu, oysa
    dizin.
    """
    cleaned = source.lstrip("./").rstrip("/")

    parts: list[str] = []
    for chunk in cleaned.split("/"):
        # "conf.d" gibi dizin adlarında nokta kaybolur: CONFD daha okunur.
        chunk = chunk.replace(".d", "d").replace(".", "_").upper()
        if parts and parts[-1] == chunk:
            continue
        if parts and chunk.startswith(parts[-1] + "_"):
            chunk = chunk[len(parts[-1]) + 1:]
        parts.append(chunk)

    resolved = (base / cleaned).resolve()
    if resolved.exists():
        suffix = "FILE" if resolved.is_file() else "DIR"
    else:
        # Depoda yoksa (üretimde oluşan dizinler) uzantıya bakılır.
        last = cleaned.split("/")[-1]
        suffix = "FILE" if "." in last and not last.endswith(".d") else "DIR"
    return "_".join(parts) + "_" + suffix, source


def is_bind(source: str) -> bool:
    """Adlandırılmış birim mi, host yolu mu."""
    return source.startswith(("./", "../", "/", "~"))


def main() -> int:
    if len(sys.argv) != 3:
        print(__doc__)
        return 2

    source = Path(sys.argv[1])
    out = Path(sys.argv[2])
    out.mkdir(parents=True, exist_ok=True)

    compose = yaml.safe_load(source.read_text())
    # Yolların dizin mi dosya mı olduğu compose'un bulunduğu
    # yere göre çözülür.
    source_dir = source.resolve().parent
    services = compose.get("services", {})

    # Ortak taban: servisler dışındaki her şey.
    base = {key: value for key, value in compose.items() if key != "services"}
    (out / "_base.yml").write_text(
        HEADER + yaml.safe_dump(base, allow_unicode=True, sort_keys=False)
    )

    # Bind yolları ve portlar için değişkenler; yola göre tekilleştirilir.
    bind_vars: dict[str, str] = {}

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

        # Bind bağlamaları: kaynak yol değişkene çevrilir, hedef ve bayraklar
        # (":ro" gibi) olduğu gibi kalır. Adlandırılmış birimlere dokunulmaz;
        # onların yeri host'ta değil, docker'da.
        volumes = cleaned.get("volumes")
        if volumes:
            rewritten = []
            for entry in volumes:
                if not isinstance(entry, str) or ":" not in entry:
                    rewritten.append(entry)
                    continue
                source, rest = entry.split(":", 1)
                if not is_bind(source) or source.startswith("${"):
                    rewritten.append(entry)
                    continue
                var, default = path_variable(source, source_dir)
                bind_vars[var] = default
                rewritten.append("${%s:-%s}:%s" % (var, default, rest))
            cleaned["volumes"] = rewritten

        # Portlar: host tarafı değişkene çevrilir, konteyner tarafı sabit.
        ports = cleaned.get("ports")
        if ports:
            rewritten_ports = []
            for entry in ports:
                text = str(entry)
                if ":" not in text or text.startswith("${"):
                    rewritten_ports.append(entry)
                    continue
                host, container = text.split(":", 1)
                var = PORT_NAMES.get(container.split("/")[0], f"PORT_{host}")
                bind_vars[var] = host
                rewritten_ports.append("${%s:-%s}:%s" % (var, host, container))
            cleaned["ports"] = rewritten_ports
        (out / f"{name}.yml").write_text(
            HEADER
            + yaml.safe_dump(
                {"services": {name: cleaned}}, allow_unicode=True, sort_keys=False
            )
        )

    lines = [
        "# Bind bağlamaları ve portlar. update.sh bunları hedefteki .env'e",
        "# yazar; zaten tanımlıysa dokunmaz, böylece taşınmış bir dizin",
        "# sonraki güncellemede geri alınmaz.",
        "",
    ]
    for var in sorted(bind_vars):
        lines.append(f"{var}={bind_vars[var]}")
    (out / "bind_defaults.env").write_text("\n".join(lines) + "\n")

    print(f"  {len(services)} servis + _base.yml + {len(bind_vars)} bind/port değişkeni -> {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
