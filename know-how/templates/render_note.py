#!/usr/bin/env python3
"""Müşteriye giden güncelleme talimatını üretir.

Talimatlar elle yazıldığında sürümler arasında kayıyor: birinde revert
notu var öbüründe yok, birinde komutlar tam öbüründe eksik. Buradan
üretilince hepsi aynı iskelette çıkar ve paketin gerçek içeriğini anlatır
(hangi servisler değişti, veritabanı var mı, hangi sürüme dönülebilir).

    python3 render_note.py --version 1.2.1 --included "backend frontend" \
        --skipped "nginx" --previous 1.2.0 --with-data 0 --output out.md
"""

import argparse
from datetime import date

TEMPLATE = """---
title: "Tiki Taka Toe {version} Güncelleme Talimatı"
date: "{today}"
lang: tr-TR
---

# {version} Güncelleme Talimatı

Bu talimat **{version}** sürümünün internetsiz sunucuya USB ile
uygulanmasını anlatır. Sunucunun internete çıkması gerekmez.

## Bu sürümde ne var

{content_summary}

## Ön Hazırlık

1. USB'yi teslim aldığınızda içinde `release_{version}` klasörü olmalı.
2. Sunucuya erişebildiğinizi doğrulayın:

   ```
   ssh <kullanici>@<sunucu-adresi>
   ```

3. Güncelleme sırasında oyun birkaç saniye kesintiye uğrar. Yoğun
   olmayan bir saat seçin.

## Host'ta Yapılacaklar

USB'yi kendi bilgisayarınıza takın ve klasörü sunucuya gönderin:

```
cp -R /Volumes/<USB>/release_{version} ~/Desktop/
cd ~/Desktop
tar czf release_{version}.tar.gz release_{version}
scp release_{version}.tar.gz <kullanici>@<sunucu-adresi>:/tmp/
```

## Sunucuda Yapılacaklar

```
ssh <kullanici>@<sunucu-adresi>
cd /tmp
tar xzvf release_{version}.tar.gz
cd release_{version}
sudo ./update.sh /srv/tikitakatoe
```

Betik sırasıyla şunları yapar:

1. Paketin bozulmadığını doğrular (bozuksa **hiçbir şeye dokunmaz**)
2. Mevcut ayarları ve veritabanını yedekler
3. İmajları yükler
4. Servisleri yeniden başlatır
5. Sağlık kontrolü yapar — geçemezse önceki sürüme döner

Sonunda `✓ {version} uygulandı` satırını görmelisiniz.

### Önce denemek isterseniz

Hiçbir şeye dokunmadan ne yapacağını görmek için:

```
sudo ./update.sh /srv/tikitakatoe --dry-run
```

## Geri Alma

{revert_section}

## Teknik Destek

Sorun yaşarsanız, aşağıdaki çıktıyı alıp iletin:

```
cd /srv/tikitakatoe
docker compose ps
docker compose logs --tail=100 backend
```
"""

REVERT_WITH = """Bir aksaklık olursa **{previous}** sürümüne dönebilirsiniz:

```
cd /tmp/release_{version}
sudo ./revert_{previous}.sh /srv/tikitakatoe
```

Geri dönüş imaj yüklemez, yalnızca ayarları geri yazar; saniyeler sürer.
{previous} imajları sunucuda durduğu sürece çalışır.
"""

REVERT_WITHOUT = """Bu ilk sürüm olduğu için dönülecek önceki bir sürüm yok.
Sorun yaşarsanız teknik desteğe başvurun.
"""


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--version", required=True)
    parser.add_argument("--included", default="")
    parser.add_argument("--skipped", default="")
    parser.add_argument("--previous", default="")
    parser.add_argument("--with-data", default="0")
    parser.add_argument("--output", required=True)
    args = parser.parse_args()

    included = [s for s in args.included.split() if s]
    skipped = [s for s in args.skipped.split() if s]

    lines = []
    if included:
        lines.append("Güncellenen servisler:")
        lines.append("")
        for service in included:
            lines.append(f"- `{service}`")
    if skipped:
        lines.append("")
        lines.append(
            "Değişmediği için pakete alınmayan servisler: "
            + ", ".join(f"`{s}`" for s in skipped)
            + ". Bunlar sunucuda çalışmaya devam eder, yeniden başlatılmaz."
        )
    if args.with_data == "1":
        lines.append("")
        lines.append(
            "**Bu pakette futbolcu veritabanı da var.** Güncelleme sırasında "
            "sunucudaki veritabanı yenisiyle değiştirilir; eskisi "
            "`know-how-backups/` altına yedeklenir."
        )

    revert = (
        REVERT_WITH.format(previous=args.previous, version=args.version)
        if args.previous
        else REVERT_WITHOUT
    )

    text = TEMPLATE.format(
        version=args.version,
        today=date.today().isoformat(),
        content_summary="\n".join(lines) if lines else "Küçük düzeltmeler.",
        revert_section=revert,
    )
    with open(args.output, "w", encoding="utf-8") as fh:
        fh.write(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
