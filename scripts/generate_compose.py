#!/usr/bin/env python3
"""
Generate docker-compose.yml and haproxy.cfg dynamically from .env settings.
Usage: python3 scripts/generate_compose.py
"""
import os
from pathlib import Path
from string import Template

# Prefer reading .env from the current working directory (mounted by the generator container)
CWD = Path.cwd()
if (CWD / '.env').exists():
  ROOT = CWD
else:
  ROOT = Path(__file__).resolve().parents[1]
ENV = ROOT / '.env'

# Load .env simple parser
vars = {}
if ENV.exists():
    for line in ENV.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith('#'):
            continue
        if '=' in line:
            k, v = line.split('=', 1)
            vars[k.strip()] = v.strip()

# Support separate counts for postgres and etcd clusters
NUM_PG = int(vars.get('NUMBER_OF_POSTGRES_CLUSTER', vars.get('NUMBER_OF_CLUSTER', '3')))
NUM_ETCD = int(vars.get('NUMBER_OF_ETCD_CLUSTER', vars.get('NUMBER_OF_CLUSTER', '3')))
PROJECT_NETWORK_SUBNET = vars.get('PROJECT_NETWORK_SUBNET', '172.25.0.0/16')
HAPROXY_IP = vars.get('HAPROXY_IP', '172.25.0.100')
HAPROXY_FRONTEND_READWRITE = vars.get('HAPROXY_FRONTEND_READWRITE', '5000')
HAPROXY_FRONTEND_READONLY = vars.get('HAPROXY_FRONTEND_READONLY', '5001')
HAPROXY_STATS_PORT = vars.get('HAPROXY_STATS_PORT', '8404')

# Generate node variables (fallbacks)
pg_nodes = []
etcd_nodes = []

# We'll assign default IP ranges so etcd and postgres don't collide when counts differ.
# Defaults: etcd nodes start at .10, postgres nodes start at .100 (both within same /16)
ETCD_IP_START = int(vars.get('ETCD_IP_START_OCTET', '10'))
PG_IP_START = int(vars.get('PG_IP_START_OCTET', '100'))

# Build etcd nodes (etcd-01..)
for i in range(1, NUM_ETCD+1):
  n = f"{i}"
  name_k = f"ETCD{n}_NAME"
  ip_k = f"ETCD{n}_IP"
  name = vars.get(name_k, f"etcd-{str(i).zfill(2)}")
  ip = vars.get(ip_k)
  if not ip:
    ip = f"172.25.0.{ETCD_IP_START + i - 1}"
  etcd_nodes.append({'index': i, 'name': name, 'ip': ip})

# Build postgres nodes (postgresql-01..)
for i in range(1, NUM_PG+1):
  n = f"{i}"
  name_k = f"NODE{n}_NAME"
  ip_k = f"NODE{n}_IP"
  name = vars.get(name_k, f"postgresql-{str(i).zfill(2)}")
  ip = vars.get(ip_k)
  if not ip:
    ip = f"172.25.0.{PG_IP_START + i - 1}"
  pg_nodes.append({'index': i, 'name': name, 'ip': ip})

# Build CLUSTER_NODES and ETCD_HOSTS
cluster_nodes = ','.join([f"{n['name']}=https://{n['ip']}:2380" for n in pg_nodes])
etcd_hosts = ','.join([f"{n['ip']}:2379" for n in etcd_nodes])
# ETCD_INITIAL_CLUSTER in http scheme for etcd initial-cluster config
etcd_initial_cluster = ','.join([f"{n['name']}=http://{n['ip']}:2380" for n in etcd_nodes])

# Ensure HAPROXY_IP does not collide with any node IP; if it does, pick a free IP
used_ips = {n['ip'] for n in pg_nodes + etcd_nodes}
if HAPROXY_IP in used_ips:
  # pick a free last-octet in the same /24 (try low numbers first)
  parts = HAPROXY_IP.split('.')
  base = '.'.join(parts[:3]) if len(parts) >= 3 else '172.25.0'
  chosen = None
  for octet in list(range(2, 256)):
    candidate = f"{base}.{octet}"
    if candidate not in used_ips:
      chosen = candidate
      break
  if chosen:
    print(f"HAPROXY_IP {HAPROXY_IP} collides with node IPs; choosing {chosen} instead")
    HAPROXY_IP = chosen
  else:
    print("Warning: could not find free IP for HAPROXY_IP; continuing with configured value")

# Compose generation - build strings with explicit indentation to avoid YAML issues
def indent(level):
  return '  ' * level

lines = []
lines.append('version: "3.8"')
lines.append('')
lines.append('networks:')
lines.append(indent(1) + 'patroni_network:')
lines.append(indent(2) + 'driver: bridge')
lines.append(indent(2) + 'ipam:')
lines.append(indent(3) + 'config:')
lines.append(indent(4) + '- subnet: ' + PROJECT_NETWORK_SUBNET)
lines.append('')
lines.append('volumes:')
for n in pg_nodes:
  lines.append(indent(1) + f'postgres_data_{str(n["index"]).zfill(2)}:')
for n in etcd_nodes:
  lines.append(indent(1) + f'etcd_data_{str(n["index"]).zfill(2)}:')
lines.append('')
lines.append('services:')

# Generate etcd services first
for n in etcd_nodes:
  idx = n['index']
  zidx = str(idx).zfill(2)
  name = n['name']
  ip = n['ip']

  lines.append(indent(1) + f'{name}:')
  lines.append(indent(2) + 'build: .')
  lines.append(indent(2) + f'container_name: {name}')
  lines.append(indent(2) + f'hostname: {name}')
  lines.append(indent(2) + 'networks:')
  lines.append(indent(3) + 'patroni_network:')
  lines.append(indent(4) + f'ipv4_address: {ip}')

  # conditional ports block for etcd
  ETCD_CLIENT_PORT_HOST = vars.get(f'ETCD{idx}_CLIENT_PORT')
  ETCD_PEER_PORT_HOST = vars.get(f'ETCD{idx}_PEER_PORT')
  if ETCD_CLIENT_PORT_HOST or ETCD_PEER_PORT_HOST:
    lines.append(indent(2) + 'ports:')
    if ETCD_CLIENT_PORT_HOST:
      lines.append(indent(3) + f'- "{ETCD_CLIENT_PORT_HOST}:{vars.get("ETCD_CLIENT_PORT","2379")}"')
    if ETCD_PEER_PORT_HOST:
      lines.append(indent(3) + f'- "{ETCD_PEER_PORT_HOST}:{vars.get("ETCD_PEER_PORT","2380")}"')

  lines.append(indent(2) + 'environment:')
  lines.append(indent(3) + f'- NODE_NAME={name}')
  lines.append(indent(3) + f'- NODE_IP={ip}')
  lines.append(indent(3) + f'- ETCD_CLUSTER_SIZE={NUM_ETCD}')
  lines.append(indent(3) + f'- ETCD_INITIAL_CLUSTER={etcd_initial_cluster}')
  # Ensure etcd-only services don't start Patroni/Postgres
  lines.append(indent(3) + f'- SKIP_POSTGRES=1')
  lines.append(indent(3) + f'- POSTGRES_PASSWORD={vars.get("POSTGRES_PASSWORD","postgres")}')
  lines.append(indent(2) + 'volumes:')
  lines.append(indent(3) + f'- etcd_data_{zidx}:/var/lib/etcd')
  lines.append(indent(2) + 'restart: unless-stopped')
  lines.append('')

# Generate postgres / patroni nodes
for n in pg_nodes:
  idx = n['index']
  zidx = str(idx).zfill(2)
  name = n['name']
  ip = n['ip']

  lines.append(indent(1) + f'{name}:')
  lines.append(indent(2) + 'build: .')
  lines.append(indent(2) + f'container_name: {name}')
  lines.append(indent(2) + f'hostname: {name}')
  lines.append(indent(2) + 'networks:')
  lines.append(indent(3) + 'patroni_network:')
  lines.append(indent(4) + f'ipv4_address: {ip}')

  # conditional ports block for postgres/patroni
  POSTGRES_PORT_HOST = vars.get(f'POSTGRES{idx}_PORT')
  PATRONI_PORT_HOST = vars.get(f'PATRONI{idx}_PORT')
  if POSTGRES_PORT_HOST or PATRONI_PORT_HOST:
    lines.append(indent(2) + 'ports:')
    if POSTGRES_PORT_HOST:
      lines.append(indent(3) + f'- "{POSTGRES_PORT_HOST}:{vars.get("POSTGRES_PORT","5432")}"')
    if PATRONI_PORT_HOST:
      lines.append(indent(3) + f'- "{PATRONI_PORT_HOST}:{vars.get("PATRONI_PORT","8008")}"')

  lines.append(indent(2) + 'environment:')
  lines.append(indent(3) + f'- NODE_NAME={name}')
  lines.append(indent(3) + f'- NODE_IP={ip}')
  lines.append(indent(3) + f'- CLUSTER_NODES={cluster_nodes}')
  lines.append(indent(3) + f'- ETCD_HOSTS={etcd_hosts}')
  # Ensure postgres-only services don't start etcd
  lines.append(indent(3) + f'- SKIP_ETCD=1')
  lines.append(indent(3) + f'- POSTGRES_PASSWORD={vars.get("POSTGRES_PASSWORD","postgres")}')
  lines.append(indent(3) + f'- REPLICATOR_PASSWORD={vars.get("REPLICATOR_PASSWORD","replicator")}')
  lines.append(indent(2) + 'volumes:')
  lines.append(indent(3) + f'- postgres_data_{zidx}:/var/lib/postgresql/data')
  lines.append(indent(2) + 'restart: unless-stopped')
  lines.append(indent(2) + 'healthcheck:')
  lines.append(indent(3) + 'test: ["CMD-SHELL", "curl -f http://localhost:${PATRONI_PORT}/health || exit 1"]')
  lines.append(indent(3) + 'interval: 30s')
  lines.append(indent(3) + 'timeout: 10s')
  lines.append(indent(3) + 'retries: 3')
  lines.append(indent(3) + 'start_period: 60s')
  lines.append('')

# haproxy service
lines.append(indent(1) + 'haproxy:')
lines.append(indent(2) + 'build:')
lines.append(indent(3) + 'context: ./docker-haproxy')
lines.append(indent(2) + f'container_name: {vars.get("HAPROXY_NAME","haproxy")}')
lines.append(indent(2) + f'hostname: {vars.get("HAPROXY_NAME","haproxy")}')
lines.append(indent(2) + 'networks:')
lines.append(indent(3) + 'patroni_network:')
lines.append(indent(4) + f'ipv4_address: {HAPROXY_IP}')
lines.append(indent(2) + 'ports:')
lines.append(indent(3) + f'- "{HAPROXY_FRONTEND_READWRITE}:{HAPROXY_FRONTEND_READWRITE}"')
lines.append(indent(3) + f'- "{HAPROXY_FRONTEND_READONLY}:{HAPROXY_FRONTEND_READONLY}"')
lines.append(indent(3) + f'- "{HAPROXY_STATS_PORT}:{HAPROXY_STATS_PORT}"')
lines.append(indent(2) + 'volumes:')
lines.append(indent(3) + '- ./haproxy.cfg:/usr/local/etc/haproxy/haproxy.cfg.template:ro')
lines.append(indent(2) + 'depends_on:')
for n in pg_nodes:
  lines.append(indent(3) + f'- {n["name"]}')
lines.append(indent(2) + 'restart: unless-stopped')

compose_content = '\n'.join(lines) + '\n'

# Write docker-compose.yml
out_compose = ROOT / 'docker-compose.yml'
out_compose.write_text(compose_content)
print(f'Wrote {out_compose} with {NUM_PG} postgres and {NUM_ETCD} etcd nodes')

# Generate haproxy.cfg
hap_tpl = Template('''global
    daemon
    maxconn 4096
    log stdout local0

defaults
    mode tcp
    timeout client 30s
    timeout connect 5s
    timeout server 30s
    timeout check 5s
    retries 3
    log global

# HAProxy Stats
listen stats
    bind *:${HAPROXY_STATS_PORT}
    mode http
    stats enable
    stats uri /stats
    stats refresh 30s

# PostgreSQL Read/Write and Read-Only
frontend postgres_rw_frontend
    bind *:${HAPROXY_FRONTEND_READWRITE}
    mode tcp
    default_backend postgres_rw

frontend postgres_ro_frontend
    bind *:${HAPROXY_FRONTEND_READONLY}
    mode tcp
    default_backend postgres_ro

backend postgres_rw
    mode tcp
    balance roundrobin
    option httpchk GET /role
    http-check expect string primary
${RW_SERVERS}

backend postgres_ro
    mode tcp
    balance roundrobin
    option httpchk GET /role
    http-check expect string replica
${RO_SERVERS}
''')

rw_servers = '\n'.join([f"    server {n['name']} {n['ip']}:{vars.get('POSTGRES_PORT','5432')} check port {vars.get('PATRONI_PORT','8008')} inter 2s" for n in pg_nodes])
ro_servers = rw_servers

haproxy_content = hap_tpl.substitute(
    HAPROXY_STATS_PORT=HAPROXY_STATS_PORT,
    HAPROXY_FRONTEND_READWRITE=HAPROXY_FRONTEND_READWRITE,
    HAPROXY_FRONTEND_READONLY=HAPROXY_FRONTEND_READONLY,
    RW_SERVERS=rw_servers,
    RO_SERVERS=ro_servers
)

(ROOT / 'haproxy.cfg').write_text(haproxy_content)
print(f'Wrote {ROOT / "haproxy.cfg"}')
