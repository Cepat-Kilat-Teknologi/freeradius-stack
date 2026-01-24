.PHONY: help build up down restart logs logs-radius logs-db status clean rebuild shell-radius shell-db test-auth test-status init-env

# Load .env file if exists
ifneq (,$(wildcard ./.env))
    include .env
    export
endif

# Default target
help:
	@echo "FreeRADIUS Stack - Available Commands"
	@echo "======================================"
	@echo ""
	@echo "Setup:"
	@echo "  make init-env     - Create .env file from template"
	@echo "  make build        - Build Docker images"
	@echo ""
	@echo "Container Management:"
	@echo "  make up           - Start all services"
	@echo "  make down         - Stop all services"
	@echo "  make restart      - Restart all services"
	@echo "  make status       - Show container status"
	@echo ""
	@echo "Logs:"
	@echo "  make logs         - Follow logs for all services"
	@echo "  make logs-radius  - Follow FreeRADIUS logs"
	@echo "  make logs-db      - Follow MySQL logs"
	@echo ""
	@echo "Shell Access:"
	@echo "  make shell-radius - Open shell in FreeRADIUS container"
	@echo "  make shell-db     - Open shell in MySQL container"
	@echo ""
	@echo "Testing:"
	@echo "  make test-auth    - Test RADIUS authentication"
	@echo "  make test-status  - Test RADIUS status server"
	@echo ""
	@echo "Database:"
	@echo "  make mysql        - Connect to MySQL as radius user"
	@echo "  make mysql-root   - Connect to MySQL as root"
	@echo "  make db-backup    - Backup database"
	@echo "  make db-restore FILE=<path> - Restore database"
	@echo "  make add-test-user - Add test user to database"
	@echo "  make show-users   - Show all RADIUS users"
	@echo "  make show-clients - Show all NAS clients"
	@echo ""
	@echo "Cleanup:"
	@echo "  make clean        - Stop and remove containers, networks"
	@echo "  make clean-all    - Stop and remove everything including volumes"
	@echo "  make rebuild      - Clean and rebuild from scratch"

# Setup
init-env:
	@if [ -f .env ]; then \
		echo "Error: .env already exists. Remove it first or edit manually."; \
		exit 1; \
	fi
	@cp env.template .env
	@echo ".env file created from template."
	@echo ""
	@echo "IMPORTANT: Edit .env and change all CHANGE_ME_* values!"
	@echo ""

# Build
build:
	docker compose build

build-no-cache:
	docker compose build --no-cache

# Container Management
up:
	docker compose up -d

up-logs:
	docker compose up

down:
	docker compose down

restart:
	docker compose restart

restart-radius:
	docker compose restart freeradius

restart-db:
	docker compose restart db

status:
	@echo "=== Container Status ==="
	@docker compose ps
	@echo ""
	@echo "=== Health Status ==="
	@docker inspect --format='{{.Name}}: {{if .State.Health}}{{.State.Health.Status}}{{else}}no healthcheck{{end}}' $$(docker compose ps -q) 2>/dev/null || echo "No containers running"

# Logs
logs:
	docker compose logs -f

logs-radius:
	docker compose logs -f freeradius

logs-db:
	docker compose logs -f db

logs-tail:
	docker compose logs --tail=100

# Shell Access
shell-radius:
	docker compose exec freeradius bash

shell-db:
	docker compose exec db bash

# MySQL Access (uses variables from .env)
mysql:
	@docker compose exec db mysql -u"$(MYSQL_USER)" -p"$(MYSQL_PASSWORD)" "$(MYSQL_DBNAME)"

mysql-root:
	@docker compose exec db mysql -uroot -p"$(MYSQL_ROOT_PASSWORD)"

# Testing
test-auth:
	@echo "Testing RADIUS authentication..."
	@if [ -z "$(RADIUS_SECRET)" ]; then \
		echo "Error: RADIUS_SECRET not set. Run 'source .env' or check your .env file."; \
		exit 1; \
	fi
	@echo "Running: radtest testuser testpass localhost 0 <secret>"
	@docker compose exec freeradius radtest testuser testpass localhost 0 "$(RADIUS_SECRET)" || true

test-status:
	@echo "Testing RADIUS status server (internal healthcheck)..."
	@docker compose exec freeradius sh -c 'radclient -t 3 -x 127.0.0.1:18121 status testing123 < /dev/null'

# Debug
debug-radius:
	@echo "Starting FreeRADIUS in debug mode..."
	@echo "Press Ctrl+C to stop"
	docker compose stop freeradius
	docker compose run --rm freeradius freeradius -X

config-check:
	@echo "Checking FreeRADIUS configuration..."
	docker compose exec freeradius freeradius -CX

# Cleanup
clean:
	docker compose down --remove-orphans

clean-all:
	docker compose down --remove-orphans -v
	@echo "All containers, networks, and volumes removed."

clean-images:
	docker compose down --remove-orphans --rmi local

# Rebuild
rebuild: clean build up
	@echo "Rebuild complete."

rebuild-all: clean-all build up
	@echo "Full rebuild complete (including fresh database)."

# Database Management
db-backup:
	@mkdir -p backups
	@docker compose exec -T db mysqldump -uroot -p"$(MYSQL_ROOT_PASSWORD)" "$(MYSQL_DBNAME)" > backups/radius_$$(date +%Y%m%d_%H%M%S).sql
	@echo "Backup saved to backups/"
	@ls -la backups/*.sql | tail -1

db-restore:
	@if [ -z "$(FILE)" ]; then \
		echo "Usage: make db-restore FILE=backups/radius_xxx.sql"; \
		exit 1; \
	fi
	@if [ ! -f "$(FILE)" ]; then \
		echo "Error: File $(FILE) not found"; \
		exit 1; \
	fi
	@docker compose exec -T db mysql -uroot -p"$(MYSQL_ROOT_PASSWORD)" "$(MYSQL_DBNAME)" < $(FILE)
	@echo "Database restored from $(FILE)"

# Add test user to database
add-test-user:
	@echo "Adding test user to database..."
	@docker compose exec db mysql -uroot -p"$(MYSQL_ROOT_PASSWORD)" "$(MYSQL_DBNAME)" -e "\
		INSERT INTO radcheck (username, attribute, op, value) \
		VALUES ('testuser', 'Cleartext-Password', ':=', 'testpass') \
		ON DUPLICATE KEY UPDATE value='testpass';"
	@echo "Test user added: username='testuser', password='testpass'"

# Show NAS clients
show-clients:
	@docker compose exec db mysql -uroot -p"$(MYSQL_ROOT_PASSWORD)" "$(MYSQL_DBNAME)" -e "SELECT * FROM nas;"

# Show users
show-users:
	@docker compose exec db mysql -uroot -p"$(MYSQL_ROOT_PASSWORD)" "$(MYSQL_DBNAME)" -e "SELECT id, username, attribute, op, value FROM radcheck;"

# Log management
logs-size:
	@echo "=== Docker Log Sizes ==="
	@docker inspect --format='{{.LogPath}}' $$(docker compose ps -q) 2>/dev/null | xargs -I {} sh -c 'ls -lh {} 2>/dev/null' || echo "No containers running"

logs-clear:
	@echo "Clearing container logs..."
	@docker compose ps -q | xargs -I {} sh -c 'docker inspect --format="{{.LogPath}}" {} | xargs truncate -s 0' 2>/dev/null || true
	@echo "Logs cleared."

# Validate environment
check-env:
	@echo "Checking environment configuration..."
	@if [ -z "$(MYSQL_PASSWORD)" ] || [ "$(MYSQL_PASSWORD)" = "CHANGE_ME_STRONG_PASSWORD" ]; then \
		echo "WARNING: MYSQL_PASSWORD not configured properly"; \
	else \
		echo "OK: MYSQL_PASSWORD is set"; \
	fi
	@if [ -z "$(MYSQL_ROOT_PASSWORD)" ] || [ "$(MYSQL_ROOT_PASSWORD)" = "CHANGE_ME_ROOT_PASSWORD" ]; then \
		echo "WARNING: MYSQL_ROOT_PASSWORD not configured properly"; \
	else \
		echo "OK: MYSQL_ROOT_PASSWORD is set"; \
	fi
	@if [ -z "$(RADIUS_SECRET)" ] || [ "$(RADIUS_SECRET)" = "CHANGE_ME_RADIUS_SECRET" ]; then \
		echo "WARNING: RADIUS_SECRET not configured properly"; \
	else \
		echo "OK: RADIUS_SECRET is set"; \
	fi