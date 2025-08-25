# Makefile for dockerpatroni
# Targets:
#  - gen: build and run the generator (writes docker-compose.yml and haproxy.cfg)
#  - up: start the main stack (builds images)
#  - down: stop and remove the main stack
#  - set-nodes N: set NUMBER_OF_CLUSTER in .env to N
#  - regen: regenerate configs after changing .env

.PHONY: gen up down regen set-nodes

.PHONY: check

GEN_COMPOSE_FILE := docker-compose.generator.yml

gen:
	@docker compose -f $(GEN_COMPOSE_FILE) build --no-cache
	@docker compose -f $(GEN_COMPOSE_FILE) run --rm generator

up:
	@docker compose up -d --build

down:
	@docker compose down -v

regen:
	@# regenerate using existing .env
	@docker compose -f $(GEN_COMPOSE_FILE) run --rm generator

set-nodes:
	@if [ "$(N)" = "" ]; then \
		echo "Usage: make set-nodes N=5"; exit 1; \
	fi
	@# replace or add NUMBER_OF_CLUSTER in .env
	@sed -i -E 's/^NUMBER_OF_CLUSTER=.*/NUMBER_OF_CLUSTER=$(N)/' .env || echo "NUMBER_OF_CLUSTER=$(N)" >> .env
	@echo "NUMBER_OF_CLUSTER set to $(N) in .env"
	@echo "Run 'make regen' to regenerate configs"

check:
	@docker compose exec postgresql-01 /usr/local/bin/patronictl -c /etc/patroni/config.yml list
	@docker compose exec postgresql-01 bash -lc 'ENDPOINTS=$$(printf "http://%s:2379," etcd-01 etcd-02 etcd-03); ENDPOINTS=$${ENDPOINTS%,}; echo ENDPOINTS=$$ENDPOINTS; etcdctl --endpoints="$$ENDPOINTS" endpoint status --write-out=table'
