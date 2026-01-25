.PHONY: help build up down restart logs status clean

# Load .env file if exists
ifneq (,$(wildcard ./.env))
    include .env
    export
endif

help:
	@echo "FreeRADIUS Docker - Commands"
	@echo "============================"
	@echo ""
	@echo "  make init-env     - Create .env from template"
	@echo "  make build        - Build images"
	@echo "  make up           - Start services"
	@echo "  make down         - Stop services"
	@echo "  make logs         - View logs"
	@echo "  make status       - Show status"
	@echo "  make clean        - Remove everything"
	@echo ""
	@echo "  make mysql        - Connect to MySQL"
	@echo "  make test-auth    - Test RADIUS auth"
	@echo "  make add-test-user - Add test user"

init-env:
	@if [ -f .env ]; then echo ".env exists"; exit 1; fi
	@cp .env.example .env
	@echo "Edit .env and change CHANGE_ME_* values"

build:
	docker compose build

up:
	docker compose up -d

down:
	docker compose down

restart:
	docker compose restart

logs:
	docker compose logs -f

status:
	@docker compose ps
	@echo ""
	@docker inspect --format='{{.Name}}: {{if .State.Health}}{{.State.Health.Status}}{{else}}no healthcheck{{end}}' $$(docker compose ps -q) 2>/dev/null || true

clean:
	docker compose down -v --remove-orphans

mysql:
	@docker compose exec db mysql -u"$(MYSQL_USER)" -p"$(MYSQL_PASSWORD)" "$(MYSQL_DBNAME)"

test-auth:
	@docker compose exec freeradius radtest testuser testpass localhost 0 "$(RADIUS_SECRET)" || true

add-test-user:
	@docker compose exec db mysql -uroot -p"$(MYSQL_ROOT_PASSWORD)" "$(MYSQL_DBNAME)" -e \
		"INSERT INTO radcheck (username, attribute, op, value) VALUES ('testuser', 'Cleartext-Password', ':=', 'testpass') ON DUPLICATE KEY UPDATE value='testpass';"
	@echo "Test user added: testuser/testpass"
