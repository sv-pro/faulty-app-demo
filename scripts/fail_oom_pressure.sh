#!/bin/bash
set -e

echo "=== FAULT MODE: oom_pressure ==="
echo ""
echo "Symptom: Service crashes with exit code 137 (OOM killed)"
echo "Expected logs: Memory pressure warnings → allocation failure → termination"
echo ""

docker-compose down 2>/dev/null || true

export FAULT_MODE=oom_pressure
docker-compose up -d

echo "Waiting for service to start..."
sleep 2

echo ""
echo "Triggering OOM fault:"
echo "  curl http://localhost:8000/orders/999"
echo ""

curl -s http://localhost:8000/orders/999 || echo "(Request failed as expected)"

echo ""
echo "Checking logs..."
sleep 1
docker-compose logs --tail=20

echo ""
echo "Container should have exited with code 137 (OOM)"
