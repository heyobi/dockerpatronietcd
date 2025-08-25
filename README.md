# dockerpatroni — quick usage

This repo is prepared to easily launch a high availability (HA) cluster based on PostgreSQL + Patroni + etcd using Docker Compose.

This README now focuses on the simple Makefile-based workflow you will use most often: `make up` / `make down` and `.env` preparation.

## Quick commands

- make gen    — builds and runs the generator image (produces: `docker-compose.yml`, `haproxy.cfg`).
- make up     — starts the main stack (build + up -d). The most common command.
- make down   — stops the stack and removes volumes.
- make regen  — reruns the generator using the current `.env` (configs are regenerated).
- make set-nodes N=3 — changes the `NUMBER_OF_CLUSTER` value inside `.env` (afterwards `make regen` is recommended).
- make check  — runs simple cluster checks (patronictl, etcdctl).

In most cases, the only two commands you need are:

- `make up`   — start the cluster
- `make down` — stop the entire stack

## How to prepare `.env`

At the repo root there is a `.env` file. For a basic setup you can edit the existing `.env` or copy it and create your own version.

Example (minimal, required fields):

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

Notes:
- You can control the number of nodes with `NUMBER_OF_POSTGRES_CLUSTER` and `NUMBER_OF_ETCD_CLUSTER`.
- After making changes in `.env` (especially if you change node counts or names), run `make regen` or `make gen`; these commands regenerate files like `docker-compose.yml` and `haproxy.cfg` in `configs/`.

## Typical workflow

1. Prepare or edit your `.env` file.  
2. (If needed) run `make gen` or `make regen` to generate configuration files.  
3. Run `make up` to start the cluster in the background.  
4. Check status with `make check` or watch services via `docker compose logs -f`.  
5. Run `make down` to shut down everything.  

## Example: Quick local startup

```
# dockerpatroni — quick reference

This repository provides a Docker Compose setup for a PostgreSQL + Patroni + etcd high-availability cluster.

The README contains project-specific instructions: Makefile commands, `.env` hints, and quick checks for Patroni/etcd/HAProxy.

## Quick commands

- `make gen`    — build and run the generator (produces `docker-compose.yml` and `haproxy.cfg`).
- `make up`     — start the main stack.
- `make down`   — stop the stack and remove volumes.
- `make regen`  — regenerate configs using the existing `.env` (re-run generator).
- `make set-nodes N=3` — set `NUMBER_OF_CLUSTER` in `.env` (run `make regen` after changing).
- `make check`  — run quick project-specific cluster checks (uses `patronictl` and `etcdctl`).

Usually `make up` / `make down` are enough for normal usage.

## .env (minimal example)

Edit the `.env` file in the repository root. Minimal values for testing:

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

Notes:
- `NUMBER_OF_POSTGRES_CLUSTER` and `NUMBER_OF_ETCD_CLUSTER` control node counts.
- After editing `.env`, run `make regen` or `make gen` to regenerate `docker-compose.yml` and `haproxy.cfg` if topology changed.

## Typical flow

1. Prepare or edit `.env`.  
2. (If needed) `make gen` or `make regen` to produce configs.  
3. `make up` to start the cluster.  
4. Check cluster health with `make check` or inspect logs.  
5. `make down` to stop and remove volumes.  

## Project-specific checks & troubleshooting

Configuration regeneration  
- If you changed node counts or topology in `.env`:

  ```
  make set-nodes N=3
  make regen
  ```

Patroni and etcd checks  
- Patroni cluster list:

  ```
  docker compose exec postgresql-01 /usr/local/bin/patronictl -c /etc/patroni/config.yml list
  ```

- etcd endpoints status (example):

  ```
  ENDPOINTS=$(printf "http://%s:2379," etcd-01 etcd-02 etcd-03); ENDPOINTS=${ENDPOINTS%,}; etcdctl --endpoints="$ENDPOINTS" endpoint status --write-out=table
  ```

HAProxy  
- HAProxy stats are exposed on `HAPROXY_STATS_PORT` (e.g. `8404`). Open `http://<HAPROXY_HOST>:<HAPROXY_STATS_PORT>` to view.

Logs and containers  
- Postgres node logs: `docker compose logs -f postgresql-01`  
- HAProxy logs: `docker compose logs -f haproxy`  

Config changes applied while containers are running  
- If configs were regenerated, prefer `docker compose down -v` then `make up` to ensure containers pick up the new configs.

Short note on `make check`  
- `make check` runs quick Patroni/etcd validations useful for CI or manual verification.

## Architecture

The following diagram shows the cluster topology and component interactions (etcd, Patroni, PostgreSQL nodes, HAProxy):

![Architecture diagram](./etcdpatroniimg.png)

Figure: Component diagram — etcd cluster, Patroni-managed PostgreSQL nodes, and HAProxy in front of Postgres.

## Files (short)

- `Makefile` — main project commands (`gen`, `up`, `down`, `regen`, `set-nodes`, `check`).  
- `docker-compose.generator.yml` — generator service that renders configs.  
- `docker-compose.yml` — generated Compose file used to run the stack.  
- `configs/` — templates and generated config files.  

## Summary

This README contains only project-specific instructions: `.env` hints, generator flow, Makefile commands, and quick Patroni/etcd/HAProxy checks. General Docker/system instructions were intentionally removed.

If you'd like, I can add an `env.example` file, or reduce this to a one-paragraph quick start.

Config changes applied while containers are running  
- If configs were regenerated, prefer `docker compose down -v` then `make up` to ensure containers use the new configs.

Short note on `make check`  
- `make check` runs quick Patroni/etcd validations useful for CI or manual verification.

## Files (short)

- `Makefile` — main project commands (`gen`, `up`, `down`, `regen`, `set-nodes`, `check`).  
- `docker-compose.generator.yml` — generator service that renders configs.  
- `docker-compose.yml` — generated Compose file used to run the stack.  
- `configs/` — templates and generated config files.  
