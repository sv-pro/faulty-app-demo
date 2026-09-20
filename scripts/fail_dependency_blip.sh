#!/bin/bash
set -e

echo "=== FAULT MODE: dependency_blip ==="
echo ""
echo "Symptom: Intermittent 502 Bad Gateway (fails when order_id % 3 == 0)"
echo "Expected logs: inventory-service health check failures, circuit breaker open"
echo ""

docker-compose down 2>/dev/null || true

export FAULT_MODE=none
docker-compose up -d

echo "Waiting for service to start..."
sleep 2

echo ""
echo "Testing multiple order IDs:"
echo ""

echo "Order 100 (should succeed):"
curl -s -H "X-Fault: dependency_blip" http://localhost:8000/orders/100 || echo "Failed"
echo ""

echo "Order 101 (should succeed):"
curl -s -H "X-Fault: dependency_blip" http://localhost:8000/orders/101 || echo "Failed"
echo ""

echo "Order 102 (should FAIL - divisible by 3):"
curl -s -H "X-Fault: dependency_blip" http://localhost:8000/orders/102 || echo "Failed as expected"
echo ""

echo "Checking logs..."
docker-compose logs --tail=40

echo ""
echo "Expected: Order 102 fails with 502, inventory-service unavailable, circuit breaker open"
