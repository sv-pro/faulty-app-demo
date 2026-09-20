#!/bin/bash
set -e

echo "=== FAULT MODE: timeout_upstream ==="
echo ""
echo "Symptom: 504 Gateway Timeout after ~5 seconds"
echo "Expected logs: Upstream call → slow response warning → timeout error"
echo ""

docker-compose down 2>/dev/null || true

export FAULT_MODE=none
docker-compose up -d

echo "Waiting for service to start..."
sleep 2

echo ""
echo "Triggering timeout fault (will take ~5 seconds):"
echo "  curl -H 'X-Fault: timeout_upstream' http://localhost:8000/orders/123"
echo ""

time curl -s -H "X-Fault: timeout_upstream" http://localhost:8000/orders/123 || echo ""

echo ""
echo "Checking logs..."
docker-compose logs --tail=30

echo ""
echo "Expected: 504 error, ~5000ms elapsed, payment-service-prod.internal timeout"
