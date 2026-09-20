#!/bin/bash
set -e

echo "=== FAULT MODE: bad_config ==="
echo ""
echo "Symptom: 500 Internal Server Error on requests"
echo "Expected logs: Missing DATABASE_CONNECTION_STRING configuration"
echo ""

docker-compose down 2>/dev/null || true

export FAULT_MODE=none
docker-compose up -d

echo "Waiting for service to start..."
sleep 2

echo ""
echo "Triggering config fault:"
echo "  curl -H 'X-Fault: bad_config' http://localhost:8000/orders/123"
echo ""

curl -s -H "X-Fault: bad_config" http://localhost:8000/orders/123 || echo ""

echo ""
echo "Checking logs..."
docker-compose logs --tail=20

echo ""
echo "Expected: Configuration error, DATABASE_CONNECTION_STRING not set"
