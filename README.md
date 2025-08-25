# dockerpatroni — hızlı kullanım

Bu repo, Docker Compose kullanarak PostgreSQL + Patroni + etcd tabanlı bir yüksek erişilebilirlik (HA) kümesini kolayca başlatmanız için hazırlanmıştır.

Bu README, artık sık kullandığınız basit Makefile tabanlı akışa odaklanır: `make up` / `make down` ve `.env` hazırlama.

## Hızlı komutlar

- make gen    — generator image'ını build edip çalıştırır (oluşan dosyalar: `docker-compose.yml`, `haproxy.cfg`).
- make up     — ana stack'i başlatır (build + up -d). En sık kullandığınız komut.
- make down   — stack'i durdurur ve volume'leri kaldırır.
- make regen  — mevcut `.env` ile generator'ı tekrar çalıştırır (configs yeniden üretilir).
- make set-nodes N=3 — `.env` içindeki `NUMBER_OF_CLUSTER` değerini değiştirir (sonrasında `make regen` önerilir).
- make check  — basit cluster kontrolleri çalıştırır (patronictl, etcdctl).

Genelde ihtiyacınız olan tek iki komut:

- `make up`  — cluster'ı başlatır
- `make down` — tüm stack'i kapatır

## .env nasıl hazırlanır

Repo kökünde `.env` dosyası bulunur. Basit bir kurulum için mevcut `.env`'i düzenleyebilir veya kopyalayarak kendi versiyonunuzu oluşturabilirsiniz.

Örnek (minimal, gerekli alanlar):

```
POSTGRES_PASSWORD=securepassword123
REPLICATOR_PASSWORD=replicatorpassword123
HAPROXY_NAME=haproxy
HAPROXY_IP=172.25.0.100
HAPROXY_FRONTEND_READWRITE=5000
HAPROXY_FRONTEND_READONLY=5001
HAPROXY_STATS_PORT=8404
POSTGRES_PORT=5432
PATRONI_PORT=8008
ETCD_CLIENT_PORT=2379
ETCD_PEER_PORT=2380
NUMBER_OF_POSTGRES_CLUSTER=3
NUMBER_OF_ETCD_CLUSTER=3
```

Notlar:
- `NUMBER_OF_POSTGRES_CLUSTER` ve `NUMBER_OF_ETCD_CLUSTER` ile node sayısını kontrol edebilirsiniz.
- `.env`'de değişiklik yaptıktan sonra (özellikle node sayısı veya isimleri değiştiyse) `make regen` veya `make gen` çalıştırın; bu komutlar `docker-compose.yml` ve `haproxy.cfg` gibi dosyaları (configs/) üretir.

## Tipik akış

1. `.env` dosyanızı hazırla veya düzenle.
2. (Gerekli ise) `make gen` veya `make regen` — konfigürasyon dosyalarını üretin.
3. `make up` — cluster'ı arka planda başlatın.
4. Kontrol: `make check` veya `docker compose logs -f` ile servisleri izleyin.
5. Kapatmak için `make down`.

## Örnek: Hızlı başlatma (yerel)

```
# .env hazırsa
make up

# Loglara bakmak için
docker compose logs -f --tail=200

# Kapatmak için
make down
```

## Hata ayıklama kısa notları

- Eğer port çakışması veya network hatası görürseniz, `.env` içindeki IP/PORT ayarlarını kontrol edin.
- Konfigürasyon yeniden üretildiyse, `docker compose down -v` sonrası `make up` ile devam edin.
- `make check` çalıştırarak Patroni/etcd durumunu hızlıca kontrol edebilirsiniz.

## Dosyalar (kısa)

- `Makefile` — ana komutlar (`gen`, `up`, `down`, `regen`, `set-nodes`, `check`).
- `docker-compose.generator.yml` — generator service'i (configs üretir).
- `docker-compose.yml` — üretildikten sonra stack'i çalıştırmak için kullanılır.
- `configs/` — template ve üretilmiş konfigürasyonlar.

## Projeye özel hızlı kontroller ve hata ayıklama

Aşağıdakiler sadece bu projeye özgü kontrollerdir — genel Docker veya sistem talimatları çıkarıldı.

- Konfigürasyonları yeniden üretmek için:
  - `.env` değiştirdiyseniz node sayısı/ayarı ile ilgili `make set-nodes N=...` ardından `make regen` çalıştırın.
  - Alternatif: `make gen` (generator image'ını build edip çalıştırır).

- Cluster sağlık kontrolleri (proje-spesifik):
  - Patroni cluster listesi:

    docker compose exec postgresql-01 /usr/local/bin/patronictl -c /etc/patroni/config.yml list

  - etcd endpoint durumu (örnek):

    ENDPOINTS=$(printf "http://%s:2379," etcd-01 etcd-02 etcd-03); ENDPOINTS=${ENDPOINTS%,}; etcdctl --endpoints="$ENDPOINTS" endpoint status --write-out=table

  - HAProxy stats endpoint'i HAPROXY_STATS_PORT ile erişilebilir (örn. port `8404`):

    http://<HAPROXY_HOST>:<HAPROXY_STATS_PORT>

- Log ve container spesifik kontrol (proje servisleri):
  - Postgres node logları: `docker compose logs -f postgresql-01`
  - HAProxy logları: `docker compose logs -f haproxy`

- Konfigürasyon yeniden üretilip container'lar hala çalışıyorsa:
  - `docker compose down -v` ardından `make up` (configs güncel şekilde yeniden başlatır).

- Makefile içindeki `make check` hedefi, Patroni ve etcd için hızlı bir doğrulama sağlar; CI veya manuel kontrol için kullanın.

## Kısa Özet

Sadece proje-spesifik araçlar ve akışlar README'de kaldı: `.env` ayarları, `make gen/regen`, `make up/down`, `make check` ve Patroni/etcd/HAProxy için hızlı kontroller.

Geri kalan genel Docker/sistem komutlarını dosyadan kaldırdım. İsterseniz README'yi daha da kısaltıp sadece 3-5 satırlık "başlat/durdur/env" özetine indireyim.
