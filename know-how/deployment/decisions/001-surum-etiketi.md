# ADR-001 — Paket imajları digest yerine sürüm etiketiyle taşınır

| | |
|---|---|
| **Durum** | Kabul |
| **Tarih** | 2026-09-10 |

## Bağlam

İnternetsiz kurulum paketleri `docker save` ile taşınan imajlar içeriyor.
Paketin tekrar üretilebilir olması için imajların hangi sürüme işaret
ettiği kesin olmalı. İlk tasarımda üçüncü parti imajlar digest'e
sabitlendi (`nginx@sha256:...`), çünkü `nginx:1.27-alpine` etiketi zamanla
farklı imaja işaret edebiliyor.

## Karar

Paketteki imajlar sürüme özel etiketle taşınır (`ttt-nginx:1.2.0`); digest
yalnızca köken bilgisi olarak `manifest.json`'da tutulur.

## Gerekçe

`docker save`/`load` ile taşınan bir imajın digest'ini geri kazanmak
Docker'ın imaj deposuna bağlı. Yeni sürümler (containerd) koruyor, eski
graph driver korumuyor. Korumadığı durumda compose digest'i yerelde
bulamayıp imajı **kayıt defterinden çekmeye** kalkıyor — internetsiz
makinede tam olarak olmaması gereken şey ve hata mesajı da bunu
anlatmıyor.

Sürüme özel etiket her Docker sürümünde çalışır. Tekrar üretilebilirlik
digest'i manifest'te saklayarak korunur.

Denenen alternatif: digest referansı. Test makinesinde (Docker 28,
containerd) çalıştı, ama davranışın sürüme bağlı olması riski kabul
edilemez bulundu — paket bilinmeyen makinelere gidiyor.

## Sonuçları

- `version.env` okunur ama hangi upstream sürümü olduğu doğrudan
  görünmez; bunun için `manifest.json`'a bakmak gerekir.
- Etiket her sürümde değiştiği için delta karşılaştırması etiket adına
  değil imaj kimliğine bakmak zorunda.

## İlgili

- [know-how/README.md](../../README.md)
