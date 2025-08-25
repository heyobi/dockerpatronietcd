FROM haproxy:2.8

# ensure we run package install as root (some base images switch user)
USER root

# install envsubst (gettext-base) for template rendering
RUN set -eux \
  && export DEBIAN_FRONTEND=noninteractive \
  && apt-get update \
  && apt-get install -y --no-install-recommends gettext-base \
  && rm -rf /var/lib/apt/lists/*

# (optional) switch back to root - keep root for simplicity
USER root

COPY docker-entrypoint-haproxy.sh /usr/local/bin/docker-entrypoint-haproxy.sh
RUN chmod +x /usr/local/bin/docker-entrypoint-haproxy.sh

ENTRYPOINT ["/usr/local/bin/docker-entrypoint-haproxy.sh"]
CMD ["haproxy", "-f", "/usr/local/etc/haproxy/haproxy.cfg", "-db"]
