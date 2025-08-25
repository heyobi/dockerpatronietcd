FROM ubuntu:24.04

# Ubuntu 24.04 için gerekli paketleri yükle
ENV DEBIAN_FRONTEND=noninteractive
ENV TZ=Europe/Istanbul

RUN apt-get update && apt-get install -y \
    wget \
    curl \
    gnupg \
    lsb-release \
    ca-certificates \
    postgresql-common \
    python3 \
    python3-pip \
    python3-dev \
    python3-venv \
    libpq-dev \
    acl \
    openssl \
    netcat-openbsd \
    jq \
    vim-tiny \
    tzdata \
    supervisor \
    iputils-ping \
    telnet \
    && rm -rf /var/lib/apt/lists/*

# PostgreSQL repository ekle (Ubuntu 24.04 için güncel yöntem)
RUN wget --quiet -O - https://www.postgresql.org/media/keys/ACCC4CF8.asc | gpg --dearmor -o /etc/apt/trusted.gpg.d/postgresql.gpg \
    && echo "deb http://apt.postgresql.org/pub/repos/apt/ $(lsb_release -cs)-pgdg main" > /etc/apt/sources.list.d/pgdg.list

# PostgreSQL 17 ve gerekli eklentileri yükle
RUN apt-get update && apt-get install -y \
    postgresql-17 \
    postgresql-contrib-17 \
    postgresql-client-17 \
    && rm -rf /var/lib/apt/lists/*

# etcd indir ve yükle
RUN wget https://github.com/etcd-io/etcd/releases/download/v3.5.17/etcd-v3.5.17-linux-amd64.tar.gz \
    && tar xvf etcd-v3.5.17-linux-amd64.tar.gz \
    && mv etcd-v3.5.17-linux-amd64/etcd* /usr/local/bin/ \
    && rm -rf etcd-v3.5.17-linux-amd64*

# Patroni yükle (Ubuntu 24.04'te pip break-system-packages için)
RUN pip3 install --break-system-packages patroni[etcd3] psycopg2-binary

# Kullanıcılar oluştur
RUN useradd --system --home /var/lib/etcd --shell /bin/false etcd \
    && useradd --system --home /var/lib/postgresql --shell /bin/false postgres || true

# Gerekli dizinleri oluştur
RUN mkdir -p /var/lib/etcd \
    && mkdir -p /var/lib/postgresql/data \
    && mkdir -p /var/lib/postgresql/ssl \
    && mkdir -p /etc/etcd/ssl \
    && mkdir -p /etc/patroni \
    && mkdir -p /opt/scripts

# Sahiplik ve izinleri ayarla
RUN chown -R etcd:etcd /var/lib/etcd \
    && chown -R postgres:postgres /var/lib/postgresql \
    && chown -R postgres:postgres /etc/patroni

# SSL sertifikaları için script
COPY scripts/generate_certs.sh /opt/scripts/
COPY scripts/entrypoint.sh /opt/scripts/
COPY configs/patroni_template.yml /opt/configs/
COPY configs/etcd_template.env /opt/configs/

RUN chmod +x /opt/scripts/*.sh

# Portları aç
EXPOSE 5432 8008 2379 2380

# Volumes
VOLUME ["/var/lib/postgresql/data", "/var/lib/etcd"]

# Entrypoint
ENTRYPOINT ["/opt/scripts/entrypoint.sh"]
