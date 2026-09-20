.PHONY: help build up down logs restart clean test-local install-local

help:
	@echo "Faulty App Demo - Make targets:"
	@echo "  build        - Build Docker image"
	@echo "  up           - Start service with docker-compose"
	@echo "  down         - Stop service"
	@echo "  logs         - Tail service logs"
	@echo "  restart      - Restart service"
	@echo "  clean        - Remove containers and images"
	@echo "  install-local - Install Python dependencies locally"
	@echo "  test-local   - Run service locally (without Docker)"

build:
	docker-compose build

up:
	docker-compose up -d
	@echo "Service running on http://localhost:8000"
	@echo "Health check: curl http://localhost:8000/health"

down:
	docker-compose down

logs:
	docker-compose logs -f

restart:
	docker-compose restart

clean:
	docker-compose down -v --rmi all

install-local:
	pip install -r requirements.txt

test-local:
	FAULT_MODE=none python -m app.main
