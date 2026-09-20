#!/bin/bash
set -e

echo "=== FAULT MODE: auth_misconfig ==="
echo ""
echo "Symptom: 401 Unauthorized"
echo "Expected logs: JWT expired, clock skew detected, NTP unreachable"
echo ""

docker-compose down 2>/dev/null || true

export FAULT_MODE=none
docker-compose up -d

echo "Waiting for service to start..."
sleep 2

echo ""
echo "Triggering auth misconfiguration:"
echo "  curl -H 'X-Fault: auth_misconfig' http://localhost:8000/orders/123"
echo ""

curl -s -H "X-Fault: auth_misconfig" http://localhost:8000/orders/123 || echo ""

echo ""
echo "Checking logs..."
docker-compose logs --tail=25

echo ""
echo "Expected: JWT expired, clock skew 9300 seconds, NTP unreachable"
