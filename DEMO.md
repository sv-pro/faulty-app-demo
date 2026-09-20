# 60-Second Live Demo Script

This script demonstrates AI-assisted incident triage in under 60 seconds.

## Setup (Do Once Before Demo)

```bash
# Ensure Docker is running
docker --version

# Build the app (first time only)
make build
```

## Demo Flow (60 seconds)

### Option 1: OOM Crash Demo (~45 seconds)

```bash
# 1. Show a healthy service (5 seconds)
./scripts/run_healthy.sh
curl http://localhost:8000/health
# {"status":"healthy","service":"faulty-app-demo","version":"1.0.0"}

# 2. Trigger OOM crash (10 seconds)
echo "Triggering OOM fault..."
curl http://localhost:8000/orders/999
# Service crashes with exit 137

# 3. Show logs (15 seconds)
docker-compose logs --tail=10
# Point out: Memory pressure → allocation failure → FATAL exit 137

# 4. Explain triage (15 seconds)
echo "Triage hypotheses:"
echo "  1. Memory leak in order processing"
echo "  2. Container memory limit too low (2048 MB)"
echo "  3. Spike in traffic caused heap exhaustion"
echo ""
echo "Next steps:"
echo "  • Check heap dumps and GC logs"
echo "  • Review recent code changes to order handler"
echo "  • Increase container memory limit to 4096 MB"
```

### Option 2: Timeout Demo (~50 seconds)

```bash
# 1. Start healthy service
./scripts/run_healthy.sh

# 2. Trigger upstream timeout (takes ~5 seconds by design)
echo "Calling payment service (this will timeout)..."
time curl -H "X-Fault: timeout_upstream" http://localhost:8000/orders/123
# 504 Gateway Timeout after ~5 seconds

# 3. Show logs with latency progression
docker-compose logs --tail=15
# Point out: 1500ms warning → 5000ms timeout → ETIMEDOUT

# 4. Explain triage
echo "Triage hypotheses:"
echo "  1. payment-service-prod.internal is degraded"
echo "  2. Network latency spike between services"
echo "  3. Payment service DB connection pool exhausted"
echo ""
echo "Next steps:"
echo "  • Check payment-service health and metrics"
echo "  • Review payment-service logs for errors"
echo "  • Verify network connectivity and DNS resolution"
```

### Option 3: Intermittent Dependency Failure (~55 seconds)

```bash
# 1. Start service
./scripts/run_healthy.sh

# 2. Show successful request
curl http://localhost:8000/orders/100
# Success: {"order_id":100,"status":"fulfilled"...}

# 3. Show intermittent failure (order_id divisible by 3)
curl http://localhost:8000/orders/102
# 502 Bad Gateway

# 4. Show logs
docker-compose logs --tail=20
# Point out: inventory-service health check failed, circuit breaker open

# 5. Explain triage
echo "Triage hypotheses:"
echo "  1. inventory-service pod restarts or crashes"
echo "  2. Load balancer routing to unhealthy instances"
echo "  3. Intermittent network partition in k8s cluster"
echo ""
echo "Next steps:"
echo "  • Check inventory-service pod status (kubectl get pods)"
echo "  • Review inventory-service logs for crashes"
echo "  • Verify k8s service endpoints and health checks"
```

## Quick Reference

**All fault modes:**
- `oom_pressure` - OOM crash (exit 137)
- `timeout_upstream` - 504 timeout after 5s
- `bad_config` - Missing DATABASE_CONNECTION_STRING
- `deploy_crash` - ModuleNotFoundError on startup
- `dependency_blip` - Intermittent 502 (fails when order_id % 3 == 0)
- `auth_misconfig` - 401 with clock skew

**Inject via header:**
```bash
curl -H "X-Fault: <mode>" http://localhost:8000/orders/123
```

**Offline demo with fixtures:**
```bash
cat fixtures/oom_pressure.log | jq .
cat artifacts/alerts/oom_pressure.txt
```

## Tips for Live Demo

1. **Pre-build**: Run `make build` before the demo so Docker doesn't build during your 60 seconds.

2. **Terminal setup**: Have 2 terminals side-by-side:
   - Left: Run commands
   - Right: `docker-compose logs -f` (live log stream)

3. **Highlight key log fields**: Point out `request_id`, `order_id`, error progression in logs.

4. **Show structured JSON**: Pipe logs through `jq` if available: `docker-compose logs | jq -R 'fromjson? // .'`

5. **Have fixtures ready**: If Docker fails, use `cat fixtures/<mode>.log` as backup.

6. **Reset between demos**: `docker-compose down` cleans up containers.

## Talking Points

> "This is a realistic ops scenario. We have structured logs, a service crash, and we need to triage fast."

> "Notice the JSON logs give us everything: timestamp, request_id, heap_used_mb, error_code. This is what AI triage tools consume."

> "The logs show a progression: WARNING → ERROR → FATAL. That tells us this wasn't instant—it's memory pressure building up."

> "Three hypotheses in 10 seconds: memory leak, limit too low, or traffic spike. AI can generate these from just the logs."

> "Next steps are concrete: check heap dumps, review recent changes, increase memory limit. Ready for a ticket or chat."

---

**Total demo time: 45-60 seconds**

**Setup time: 0 seconds** (assuming `make build` already done)
