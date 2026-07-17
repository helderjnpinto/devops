# =============================================================================
# clickhouse-rd — Makefile
# =============================================================================
# Provides simple commands for every operation in the clickhouse-rd project.
# =============================================================================

SHELL := /usr/bin/bash
.ONESHELL:
.SHELLFLAGS := -Eeuo pipefail -c
.DEFAULT_GOAL := help

# Auto-detect project root
PROJECT_ROOT := $(dir $(abspath $(lastword $(MAKEFILE_LIST))))

# Load .env if present
ifneq (,$(wildcard ${PROJECT_ROOT}.env))
    include ${PROJECT_ROOT}.env
    export
endif

SCRIPTS      := ${PROJECT_ROOT}scripts
SQL          := ${PROJECT_ROOT}sql
COMPOSE      := docker compose -f ${PROJECT_ROOT}docker-compose.yml
CLIENT       := ${SCRIPTS}/clickhouse-client.sh
DB           := $(or ${CLICKHOUSE_DATABASE},clickhouse_rd)

.PHONY: help env up down restart logs ps wait shell sql init \
        seed seed-old seed-hot reset-data \
        force-ttl storage-status aggregates verify recalculate-day \
        backup list-backups restore restore-last \
        reset-database clean destroy

# ── Help ─────────────────────────────────────────────────────────────────
help: ## Show this help message
	@echo "clickhouse-rd — Makefile"
	@echo ""
	@echo "Usage: make <target>"
	@echo ""
	@echo "=== Setup ==="
	@echo "  env              Copy .env.example to .env (first-time setup)"
	@echo "  up               Start all services (docker compose up -d)"
	@echo "  down             Stop all services (preserves volumes)"
	@echo "  restart          Restart all services"
	@echo "  wait             Wait for all services to be healthy"
	@echo ""
	@echo "=== Shell & SQL ==="
	@echo "  shell            Open interactive clickhouse-client"
	@echo "  sql QUERY=...    Run a one-line SQL query"
	@echo "  logs             Follow all service logs"
	@echo "  ps               Show container status"
	@echo ""
	@echo "=== Seeding ==="
	@echo "  seed             Insert old + recent test data"
	@echo "  seed-old         Insert old data (>= 2h ago)"
	@echo "  seed-hot         Insert recent data (last 30s)"
	@echo "  reset-data       Delete ALL rows from events_raw and aggregates (keeps schema)"
	@echo ""
	@echo "=== TTL & Storage ==="
	@echo "  force-ttl        Materialize TTL on events_raw"
	@echo "  storage-status   Show disk/part distribution"
	@echo ""
	@echo "=== Aggregates ==="
	@echo "  aggregates       Display aggregate results"
	@echo "  verify           Verify aggregate consistency"
	@echo "  recalculate-day DATE=YYYY-MM-DD  Rebuild aggregates for a day"
	@echo ""
	@echo "=== Backups ==="
	@echo "  backup           Create native database backup"
	@echo "  list-backups     List available backups"
	@echo "  restore BACKUP=name  Restore backup into separate DB"
	@echo "  restore-last     Restore the most recent backup"
	@echo ""
	@echo "=== Cleanup ==="
	@echo "  reset-database   Drop and recreate the database"
	@echo "  clean            Remove temp files (preserves volumes)"
	@echo "  destroy          ⚠ Stop services and DELETE all volumes"
	@echo ""
	@echo "Current DB: ${DB}"
	@echo ""

# ── Setup ────────────────────────────────────────────────────────────────
env: ## Copy .env.example to .env (first-time setup)
	@if [ -f "${PROJECT_ROOT}.env" ]; then
		echo ".env already exists. Remove it first to re-copy."
	else
		cp "${PROJECT_ROOT}.env.example" "${PROJECT_ROOT}.env"
		echo "Created .env from .env.example. Edit .env to customize."
	fi

up: ## Start all services (detached)
	${COMPOSE} up -d --wait
	$(MAKE) wait

down: ## Stop all services (preserves volumes)
	${COMPOSE} down

restart: ## Restart all services
	${COMPOSE} restart

wait: ## Wait for all services to be healthy
	${SCRIPTS}/wait-for-services.sh

# ── Shell & SQL ──────────────────────────────────────────────────────────
shell: ## Open interactive clickhouse-client
	${COMPOSE} exec clickhouse \
		clickhouse-client \
		--host localhost \
		--port 9000 \
		--user ${CLICKHOUSE_USER:-rd_user} \
		--password ${CLICKHOUSE_PASSWORD:-rd_local_password} \
		--database ${CLICKHOUSE_DATABASE:-clickhouse_rd}

sql: ## Run a one-line SQL query: make sql QUERY="SELECT 1"
	@if [ -z "${QUERY}" ]; then
		echo "Usage: make sql QUERY=\"SELECT 1\""
		exit 1
	fi
	${CLIENT} --query "${QUERY}"

logs: ## Follow all service logs
	${COMPOSE} logs -f

ps: ## Show container status
	${COMPOSE} ps

# ── Seeding ──────────────────────────────────────────────────────────────
seed: ## Insert old + recent test data
	$(MAKE) seed-old
	$(MAKE) seed-hot

seed-old: ## Insert old data (>= 2h ago)
	@echo "=== Seeding old data ==="
	${CLIENT} --query "$$(envsubst < ${SQL}/seed-old.sql)"

seed-hot: ## Insert recent data (last 30s)
	@echo "=== Seeding hot data ==="
	${CLIENT} --query "$$(envsubst < ${SQL}/seed-hot.sql)"

reset-data: ## Truncate events_raw and aggregate tables
	@echo "=== Resetting data ==="
	${CLIENT} --query "TRUNCATE TABLE IF EXISTS ${DB}.events_raw;"
	${CLIENT} --query "TRUNCATE TABLE IF EXISTS ${DB}.tenant_metrics_5m;"
	${CLIENT} --query "TRUNCATE TABLE IF EXISTS ${DB}.tenant_metrics_30m;"
	@echo "Data reset. See README for note about repeated seeding."

# ── TTL & Storage ────────────────────────────────────────────────────────
force-ttl: ## Materialize TTL on events_raw
	${SCRIPTS}/force-ttl.sh

storage-status: ## Show disk/part distribution
	${SCRIPTS}/storage-status.sh

# ── Aggregates ───────────────────────────────────────────────────────────
aggregates: ## Display aggregate results
	${CLIENT} --query "$$(envsubst < ${SQL}/aggregate-results.sql)"

verify: ## Verify aggregate consistency
	${SCRIPTS}/verify.sh

recalculate-day: ## Rebuild aggregates for a day: make recalculate-day DATE=YYYY-MM-DD
	@if [ -z "${DATE}" ]; then
		echo "Usage: make recalculate-day DATE=YYYY-MM-DD"
		echo ""
		echo "To list available dates in the raw table:"
		echo '  make sql QUERY="SELECT DISTINCT toDate(event_time) AS day FROM ${DB}.events_raw ORDER BY day;"'
		exit 1
	fi
	${SCRIPTS}/recalculate-day.sh "${DATE}"

# ── Backups ──────────────────────────────────────────────────────────────
backup: ## Create native database backup
	${SCRIPTS}/backup.sh

list-backups: ## List available backups
	${SCRIPTS}/list-backups.sh

restore: ## Restore backup: make restore BACKUP=backup-name [TARGET_DB=db_name]
	@if [ -z "${BACKUP}" ]; then
		echo "Usage: make restore BACKUP=backup-name [TARGET_DB=db_name]"
		echo "  Use 'make list-backups' to see available backups."
		exit 1
	fi
	${SCRIPTS}/restore.sh "${BACKUP}" "${TARGET_DB:-}"

restore-last: ## Restore the most recent backup
	@if [ ! -f "${PROJECT_ROOT}.last-backup" ]; then
		echo "No .last-backup file found. Run 'make backup' first."
		exit 1
	fi
	$(MAKE) restore BACKUP="$$(cat ${PROJECT_ROOT}.last-backup)"

# ── Cleanup ──────────────────────────────────────────────────────────────
reset-database: ## Drop and recreate the database (re-runs init logic via piped SQL files)
	@echo "=== Dropping and recreating database ${DB} ==="
	${CLIENT} --query "DROP DATABASE IF EXISTS ${DB};"
	# Re-initialize by running the init script inside the container
	${COMPOSE} exec -T clickhouse \
		/bin/bash /docker-entrypoint-initdb.d/000-init.sh
	@echo "Database reset complete."

clean: ## Remove temp files (preserves Docker volumes)
	@rm -f "${PROJECT_ROOT}.last-backup"
	@echo "Cleaned temporary files."

destroy: ## ⚠ Stop services and DELETE all volumes (data loss!)
	@echo "WARNING: This will DELETE all ClickHouse and MinIO data volumes!"
	@read -p "Type 'destroy' to confirm: " CONFIRM
	if [ "$${CONFIRM}" != "destroy" ]; then
		echo "Aborted."
		exit 1
	fi
	${COMPOSE} down -v
	@rm -f "${PROJECT_ROOT}.last-backup"
	@echo "Volumes destroyed."
