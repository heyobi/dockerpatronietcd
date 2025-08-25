#!/bin/bash

# SSL sertifikaları için yardımcı script - Ubuntu 24.04

set -euo pipefail

CERT_DIR=${1:-"/tmp/certs"}
NODE_IP=${2:-"127.0.0.1"}
NODE_NAME=${3:-"postgresql-01"}

mkdir -p $CERT_DIR
cd $CERT_DIR

echo "Sertifikalar $CERT_DIR dizininde oluşturuluyor..."

# CA oluştur (eğer yoksa)
if [ ! -f "ca.crt" ]; then
    echo "CA oluşturuluyor..."
    openssl genrsa -out ca.key 2048
    openssl req -x509 -new -nodes -key ca.key -subj "/CN=etcd-ca" -days 7300 -out ca.crt
fi

# Node sertifikası oluştur
echo "Node sertifikası oluşturuluyor: $NODE_NAME ($NODE_IP)"

# Private key oluştur
openssl genrsa -out etcd-${NODE_NAME}.key 2048

# Temp config dosyası (Ubuntu'da güvenli temp file)
temp_config=$(mktemp)
cat > "$temp_config" <<EOF
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
openssl req -new -key etcd-${NODE_NAME}.key -out etcd-${NODE_NAME}.csr \
  -subj "/C=TR/ST=Istanbul/L=Istanbul/O=Organization/OU=Unit/CN=${NODE_NAME}" \
  -config "$temp_config"

# Sertifikayı imzala
openssl x509 -req -in etcd-${NODE_NAME}.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
  -out etcd-${NODE_NAME}.crt -days 7300 -sha256 -extensions v3_req -extfile "$temp_config"

# Geçici dosyaları temizle
rm "$temp_config" etcd-${NODE_NAME}.csr

echo "Sertifika oluşturuldu: etcd-${NODE_NAME}.crt"
echo "Dosyalar:"
ls -la etcd-${NODE_NAME}.*
