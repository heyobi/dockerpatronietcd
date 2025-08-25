#!/usr/bin/env bash
set -euo pipefail
# Render template if present
if [ -f /usr/local/etc/haproxy/haproxy.cfg.template ]; then
  echo "Rendering /usr/local/etc/haproxy/haproxy.cfg from template"
  envsubst < /usr/local/etc/haproxy/haproxy.cfg.template > /usr/local/etc/haproxy/haproxy.cfg
fi

# exec default entrypoint (haproxy)
exec "$@"
