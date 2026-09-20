#!/bin/bash
set -e

echo "=== Running Faulty App in HEALTHY mode ==="
echo ""

# Stop any existing containers
docker-compose down 2>/dev/null || true

# Start service in healthy mode
export FAULT_MODE=none
docker-compose up -d

echo "Waiting for service to be ready..."
sleep 3

echo ""
echo "Service is running at http://localhost:8000"
echo ""
echo "Try these commands:"
echo "  curl http://localhost:8000/health"
echo "  curl http://localhost:8000/orders/123"
echo ""
echo "View logs:"
echo "  docker-compose logs -f"
