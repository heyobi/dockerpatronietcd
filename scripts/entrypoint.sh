#!/bin/bash

set -euo pipefail

# Ubuntu 24.04 için entrypoint script
# Çevresel değişkenler
NODE_NAME=${NODE_NAME:-${NODE1_NAME:-"postgresql-01"}}
NODE_IP=${NODE_IP:-${NODE1_IP:-"127.0.0.1"}}
# CLUSTER_NODES and ETCD_HOSTS should be provided via .env; fallback to single-node
CLUSTER_NODES=${CLUSTER_NODES:-"${NODE_NAME}=https://${NODE_IP}:2380"}
ETCD_HOSTS=${ETCD_HOSTS:-"${NODE_IP}:2379"}
POSTGRES_PASSWORD=${POSTGRES_PASSWORD:-"defaultpassword123"}
REPLICATOR_PASSWORD=${REPLICATOR_PASSWORD:-"replicatorpassword123"}

# Log fonksiyonu
log() {
    echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*"
}

log "Başlatılan Node Bilgileri:"
log "NODE_NAME: $NODE_NAME"
log "NODE_IP: $NODE_IP"
log "CLUSTER_NODES: $CLUSTER_NODES"
log "ETCD_HOSTS: $ETCD_HOSTS"
log "POSTGRES_PASSWORD: $POSTGRES_PASSWORD"
log "REPLICATOR_PASSWORD: $REPLICATOR_PASSWORD"

# SSL sertifikalarını oluştur
log "SSL sertifikaları oluşturuluyor..."
if [ ! -f "/var/lib/postgresql/ssl/server.crt" ]; then
    mkdir -p /var/lib/postgresql/ssl
    cd /var/lib/postgresql/ssl
    
    # Self-signed sertifika oluştur
    log "PostgreSQL SSL sertifikası oluşturuluyor..."
    openssl genrsa -out server.key 2048
    openssl req -new -key server.key -out server.req \
        -subj "/C=TR/ST=Istanbul/L=Istanbul/O=Organization/OU=Unit/CN=${NODE_NAME}"
    openssl req -x509 -key server.key -in server.req -out server.crt -days 7300
    
    # PEM dosyası oluştur (Patroni için)
    cat server.crt server.key > server.pem
    
    # Ubuntu'da doğru izinleri ayarla
    chmod 600 server.key server.pem server.req
    chmod 644 server.crt
    chown -R postgres:postgres /var/lib/postgresql/ssl/
    
    log "PostgreSQL SSL sertifikaları oluşturuldu"
fi

# etcd için self-signed sertifika oluştur
log "etcd SSL sertifikaları oluşturuluyor..."
if [ ! -f "/etc/etcd/ssl/ca.crt" ]; then
    mkdir -p /etc/etcd/ssl
    cd /etc/etcd/ssl
    
    # CA oluştur
    log "etcd CA sertifikası oluşturuluyor..."
    openssl genrsa -out ca.key 2048
    openssl req -x509 -new -nodes -key ca.key -subj "/CN=etcd-ca" -days 7300 -out ca.crt
    
    # Node sertifikası oluştur
    log "etcd node sertifikası oluşturuluyor..."
    openssl genrsa -out etcd-node.key 2048
    
    # Temp config dosyası (Ubuntu'da mktemp kullan)
    temp_file=$(mktemp)
    cat > "$temp_file" <<EOF
[ req ]
distinguished_name = req_distinguished_name
req_extensions = v3_req
[ req_distinguished_name ]
[ v3_req ]
subjectAltName = @alt_names
[ alt_names ]
IP.1 = ${NODE_IP}
IP.2 = 127.0.0.1
DNS.1 = ${NODE_NAME}
DNS.2 = localhost
EOF
    
    # CSR oluştur
    openssl req -new -key etcd-node.key -out etcd-node.csr \
      -subj "/C=TR/ST=Istanbul/L=Istanbul/O=Organization/OU=Unit/CN=${NODE_NAME}" \
      -config "$temp_file"
    
    # Sertifikayı imzala
    openssl x509 -req -in etcd-node.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
      -out etcd-node.crt -days 7300 -sha256 -extensions v3_req -extfile "$temp_file"
    
    # Geçici dosyaları temizle
    rm "$temp_file" etcd-node.csr
    
    # Ubuntu'da doğru izinleri ayarla
    chmod 600 etcd-node.key ca.key
    chmod 644 etcd-node.crt ca.crt
    chown -R etcd:etcd /etc/etcd/ssl/
    
    # ACL ile postgres kullanıcısına okuma izni ver (Ubuntu 24.04'te varsayılan)
    setfacl -m u:postgres:r /etc/etcd/ssl/ca.crt
    setfacl -m u:postgres:r /etc/etcd/ssl/etcd-node.crt
    setfacl -m u:postgres:r /etc/etcd/ssl/etcd-node.key
    
    log "etcd SSL sertifikaları oluşturuldu"
fi

# etcd konfigürasyonu oluştur
log "etcd konfigürasyonu oluşturuluyor..."
mkdir -p /etc/etcd
# Prefer explicit ETCD_INITIAL_CLUSTER from env (generator); otherwise convert CLUSTER_NODES to http
ETCD_INITIAL_CLUSTER="${ETCD_INITIAL_CLUSTER:-}"
if [ -z "${ETCD_INITIAL_CLUSTER}" ]; then
  ETCD_INITIAL_CLUSTER="$(echo "${CLUSTER_NODES}" | sed 's@https://@http://@g')"
fi
log "ETCD initial cluster (http): ${ETCD_INITIAL_CLUSTER}"
cat > /etc/etcd/etcd.env <<EOF
export ETCD_NAME="${NODE_NAME}"
export ETCD_DATA_DIR="/var/lib/etcd"
export ETCD_INITIAL_CLUSTER="${ETCD_INITIAL_CLUSTER}"
export ETCD_INITIAL_CLUSTER_STATE="new"
export ETCD_INITIAL_CLUSTER_TOKEN="etcd-cluster"
export ETCD_INITIAL_ADVERTISE_PEER_URLS="http://${NODE_IP}:${ETCD_PEER_PORT:-2380}"
export ETCD_LISTEN_PEER_URLS="http://0.0.0.0:${ETCD_PEER_PORT:-2380}"
export ETCD_LISTEN_CLIENT_URLS="http://0.0.0.0:${ETCD_CLIENT_PORT:-2379}"
export ETCD_ADVERTISE_CLIENT_URLS="http://${NODE_IP}:${ETCD_CLIENT_PORT:-2379}"
# SSL-free modda sertifika ve auth parametreleri kaldırıldı
EOF

# Patroni konfigürasyonu oluştur
log "Patroni konfigürasyonu oluşturuluyor..."
mkdir -p /etc/patroni
cat > /etc/patroni/config.yml <<EOF
scope: postgresql-cluster
namespace: /service/
name: ${NODE_NAME}

etcd3:
  hosts: ${ETCD_HOSTS:-"127.0.0.1:2379"}
  protocol: http

restapi:
  listen: 0.0.0.0:8008
  connect_address: ${NODE_IP}:8008
  # certfile: /var/lib/postgresql/ssl/server.pem

bootstrap:
  dcs:
    ttl: 30
    loop_wait: 10
    retry_timeout: 10
    maximum_lag_on_failover: 1048576
    postgresql:
      parameters:
        ssl: 'off'
        # ssl_cert_file: /var/lib/postgresql/ssl/server.crt
        # ssl_key_file: /var/lib/postgresql/ssl/server.key
  # pg_hba entries applied at bootstrap so replicas can connect for basebackup and replication
  pg_hba:
  # allow local socket replication checks and localhost TCP
  - local replication replicator peer
  - host replication replicator 127.0.0.1/32 md5
  - host replication replicator ::1/128 md5
  - host replication replicator 0.0.0.0/0 md5
  - host all all 127.0.0.1/32 md5
  - host all all 0.0.0.0/0 md5
  initdb:
    - encoding: UTF8
    - data-checksums

postgresql:
  listen: 0.0.0.0:5432
  connect_address: ${NODE_IP}:5432
  data_dir: /var/lib/postgresql/data
  bin_dir: /usr/lib/postgresql/17/bin
  authentication:
    superuser:
      username: postgres
      password: ${POSTGRES_PASSWORD}
    replication:
      username: replicator
      password: ${REPLICATOR_PASSWORD}
  parameters:
    max_connections: 100
    shared_buffers: 256MB


  nofailover: false
  noloadbalance: false
  clonefrom: false
EOF
chown postgres:postgres /etc/patroni/config.yml

# Dizin sahipliklerini ayarla
chown -R postgres:postgres /etc/patroni/
chown -R etcd:etcd /var/lib/etcd/
chown -R postgres:postgres /var/lib/postgresql/

# Eğer veri dizini zaten varsa, pg_hba.conf dosyasına replikasyon için gerekli satırı ekle
# (bootstrap sadece initdb sırasında uygulanır; hali hazırda initialize edilmiş bir primary
# varsa bu giriş eksik olabilir, replikaların pg_basebackup yapabilmesi için ekliyoruz)
PG_HBA_FILE="/var/lib/postgresql/data/pg_hba.conf"
if [ -f "$PG_HBA_FILE" ]; then
  # Ensure local socket replication entry exists
  if ! grep -qE '^\s*local\s+replication\s+replicator' "$PG_HBA_FILE"; then
    log "pg_hba: local replication satırı ekleniyor -> $PG_HBA_FILE"
    cat >> "$PG_HBA_FILE" <<'EOH'
# Added by entrypoint to allow Patroni replicas (local socket)
local replication replicator peer
EOH
  else
    log "pg_hba: local replication satırı zaten mevcut"
  fi
  # Ensure localhost host replication exists
  if ! grep -qE '^\s*host\s+replication\s+replicator\s+127.0.0.1' "$PG_HBA_FILE"; then
    log "pg_hba: host replication 127.0.0.1 satırı ekleniyor -> $PG_HBA_FILE"
    cat >> "$PG_HBA_FILE" <<'EOH'
# Added by entrypoint to allow Patroni replicas (localhost)
host replication replicator 127.0.0.1/32 md5
EOH
  else
    log "pg_hba: host replication 127.0.0.1 satırı zaten mevcut"
  fi
  # Ensure IPv6 localhost replication exists
  if ! grep -qE '^\s*host\s+replication\s+replicator\s+::1' "$PG_HBA_FILE"; then
    log "pg_hba: host replication ::1 satırı ekleniyor -> $PG_HBA_FILE"
    cat >> "$PG_HBA_FILE" <<'EOH'
# Added by entrypoint to allow Patroni replicas (localhost IPv6)
host replication replicator ::1/128 md5
EOH
  else
    log "pg_hba: host replication ::1 satırı zaten mevcut"
  fi
  # Ensure global host replication exists
  if ! grep -qE '^\s*host\s+replication\s+replicator\s+0.0.0.0' "$PG_HBA_FILE"; then
    log "pg_hba: host replication 0.0.0.0 satırı ekleniyor -> $PG_HBA_FILE"
    cat >> "$PG_HBA_FILE" <<'EOH'
# Added by entrypoint to allow Patroni replicas
host replication replicator 0.0.0.0/0 md5
EOH
  else
    log "pg_hba: host replication 0.0.0.0 satırı zaten mevcut"
  fi
  chown postgres:postgres "$PG_HBA_FILE" || true
else
  log "pg_hba: $PG_HBA_FILE bulunamadı, initdb sırasında oluşturulacak"
fi

# etcd'yi başlat (skippable)
if [ -z "${SKIP_ETCD:-}" ]; then
  log "etcd başlatılıyor..."
  # Ubuntu'da systemd yerine direkt çalıştır; environment dosyası sourcing sorunlarını atlamak için
  cd /var/lib/etcd
  su - etcd -s /bin/bash -c "cd /var/lib/etcd && /usr/local/bin/etcd \
    --name \"${NODE_NAME}\" \
    --data-dir \"/var/lib/etcd\" \
    --initial-cluster \"${ETCD_INITIAL_CLUSTER}\" \
    --initial-cluster-state \"new\" \
    --initial-cluster-token \"etcd-cluster\" \
    --initial-advertise-peer-urls \"http://${NODE_IP}:${ETCD_PEER_PORT:-2380}\" \
    --listen-peer-urls \"http://0.0.0.0:${ETCD_PEER_PORT:-2380}\" \
    --listen-client-urls \"http://0.0.0.0:${ETCD_CLIENT_PORT:-2379}\" \
    --advertise-client-urls \"http://${NODE_IP}:${ETCD_CLIENT_PORT:-2379}\"" &
  ETCD_PID=$!

  # etcd'nin hazır olmasını bekle
  log "etcd'nin hazır olması bekleniyor..."
  for i in {1..60}; do
      if timeout 2 bash -c "</dev/tcp/localhost/${ETCD_CLIENT_PORT:-2379}" 2>/dev/null; then
          log "etcd hazır!"
          break
      fi
      log "etcd bekleniyor... ($i/60)"
      sleep 2
      if [ $i -eq 60 ]; then
          log "HATA: etcd başlatılamadı"
          exit 1
      fi
  done
else
  log "SKIP_ETCD set, etcd başlatılmıyor"
fi

# Ubuntu'da PostgreSQL binary path'ini kontrol et
if [ ! -d "/usr/lib/postgresql/17/bin" ]; then
    log "PostgreSQL 17 binary bulunamadı, alternatif aranıyor..."
    PG_VERSION=$(ls /usr/lib/postgresql/ | sort -V | tail -1)
    if [ -n "$PG_VERSION" ]; then
        sed -i "s|/usr/lib/postgresql/17/bin|/usr/lib/postgresql/$PG_VERSION/bin|g" /etc/patroni/config.yml
        log "PostgreSQL $PG_VERSION kullanılıyor"
    fi
fi

# Patroni'yi başlat
if [ -z "${SKIP_POSTGRES:-}" ]; then
  log "Patroni başlatılıyor..."
  # Ensure postgres data directory ownership and permissions are correct so
  # replicas created by basebackup don't fail with "data directory ... has invalid permissions".
  PG_DATA="/var/lib/postgresql/data"
  if [ -d "$PG_DATA" ]; then
    log "Veri dizini izinleri kontrol ediliyor: $PG_DATA"
    chown -R postgres:postgres "$PG_DATA" || true
    # directoy must be 0700 or 0750 for PostgreSQL
    find "$PG_DATA" -type d -exec chmod 700 {} \; || true
    find "$PG_DATA" -type f -exec chmod 600 {} \; || true
    log "Veri dizini izinleri düzeltildi"
  fi
  exec su - postgres -c "/usr/local/bin/patroni /etc/patroni/config.yml"
else
  log "SKIP_POSTGRES set, Patroni/Postgres başlatılmıyor"
  # If etcd was started in the background, wait for it so the container stays up.
  if [ -n "${ETCD_PID:-}" ]; then
    log "etcd PID ${ETCD_PID} varsa bekleniyor..."
    wait ${ETCD_PID}
  else
    # No etcd running here - keep container alive so user can exec in it if needed.
    tail -f /dev/null
  fi
fi
