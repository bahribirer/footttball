# TestFlight 1.1.0 (build 6) — test notları

İç testten gelen geri bildirimlerin tamamı bu sürümde.

## Neyi test edelim

**1. Futbolcu adını eksik yazmak**
Artık soyad yetiyor: "Messi", "Haaland", "Mbappe", "Gundogan". Aksan da
gerekmiyor. Son Harf'te zincir hem yazdığınız metnin hem tam adın baş
harfini kabul ediyor — `m` sırasındayken "Messi" yazmayı deneyin.

**2. Öneri listesi**
Harf yazarken liste açılıp kapanırken ekranın zıplamadığını kontrol edin.
Son Harf'te öneri çıkmamalı; diğer modlarda yalnızca isim görünmeli.

**3. Tur sayısı**
Seçtiğiniz sayı artık bir hedef: turu ilk o kadar kez kazanan seriyi alır.
2-0 önde başlayıp 2-3 kaybedilebilir. Skor tablosunda "İLK 3 / 4. TUR"
yazıyor.

**4. Eski futbolcular ve kulüpler**
"Trabzonspor × Türkiye" hücresine Fatih Tekke yazmayı deneyin. Kulüplerin
tüm dönem kadroları ve eksik uyruklar tamamlandı.

**5. Bağlantı kopması (en önemlisi)**
Oyunun ortasında uçak modunu 10-20 saniye açıp kapatın:
- Oyun bitmemeli, yeriniz korunmalı (45 saniye süre var)
- Ekranda "yeniden bağlanılıyor" şeridi çıkmalı
- Geri geldiğinizde oyun kaldığı yerden sürmeli
- Rakibinize "ayrıldı" değil "bağlantısı koptu, bekleniyor" yazmalı

**6. Kategoriler**
Oda kurarken 5 seçenek çıkıyor, her birinde KOLAY/ORTA/ZOR rozeti var.
Artık çoğunluk kolay ("Fransız futbolcular" gibi geniş kategoriler).

## Bilinen sınırlar

- Kulüp tarihçesi Wikidata'dan geliyor; çok küçük kulüplerde eksik olabilir.
- Açılış görseli (launch image) hâlâ Flutter'ın varsayılanı.
- En düşük iOS sürümü 15.0 (önceden 13.0) — daha eski cihazlar kuramaz.
