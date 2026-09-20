#!/bin/bash
set -e

echo "=== FAULT MODE: deploy_crash ==="
echo ""
echo "Symptom: Service crashes immediately after receiving first request"
echo "Expected logs: ModuleNotFoundError for payment_processor_v2, exit code 1"
echo ""

docker-compose down 2>/dev/null || true

export FAULT_MODE=none
docker-compose up -d

echo "Waiting for service to start..."
sleep 2

echo ""
echo "Triggering deploy crash:"
echo "  curl -H 'X-Fault: deploy_crash' http://localhost:8000/orders/123"
echo ""

curl -s -H "X-Fault: deploy_crash" http://localhost:8000/orders/123 || echo "(Request failed as expected)"

echo ""
echo "Checking logs..."
sleep 1
docker-compose logs --tail=20

echo ""
echo "Expected: ModuleNotFoundError, deployment v2.5.0, exit code 1"
