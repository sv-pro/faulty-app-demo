# Faulty App Demo

A controlled-failure HTTP service designed for demonstrating AI-assisted incident triage. Built for platform/on-call engineers who need realistic, reproducible failures for testing monitoring, alerting, and triage workflows.

## Quick Start

### Using Docker (Recommended)

```bash
# Build and start the service
make build
make up

# Test healthy endpoint
curl http://localhost:8000/health

# Test with fault injection
curl -H "X-Fault: timeout_upstream" http://localhost:8000/orders/123
```

### Using Local Python

```bash
# Install dependencies
python3 -m venv venv
source venv/bin/activate
pip install -r requirements.txt

# Run service
python -m app.main

# In another terminal
curl http://localhost:8000/orders/456
```

## Purpose

Sergey (or any engineer) can demo AI-assisted incident triage in ~60 seconds. The app provides:

- **Realistic failures**: Logs look like production ops problems
- **Deterministic**: Same input = same failure every time
- **Controllable**: Enable/disable faults via headers, env vars, or API
- **Safe**: No actual OOM, no secrets, no internet required
- **Fast**: Pre-captured fixtures work offline

## Architecture

```
┌──────────────────────────────────────────────────────────┐
│                    Faulty App Demo                       │
│                  (FastAPI + Python 3.11)                 │
├──────────────────────────────────────────────────────────┤
│  Endpoints:                                              │
│    GET  /health              → 200 OK                    │
│    GET  /orders/{id}         → 200 or fault-injected    │
│    POST /admin/fault         → Change fault mode         │
│    GET  /admin/fault         → Get current mode          │
├──────────────────────────────────────────────────────────┤
│  Fault Injection:                                        │
│    • Header: X-Fault: <mode>                             │
│    • Env: FAULT_MODE=<mode>                              │
│    • API: POST /admin/fault + X-Admin-Token              │
├──────────────────────────────────────────────────────────┤
│  Structured Logging:                                     │
│    JSON logs → stdout                                    │
│    Fields: timestamp, level, service, request_id, etc.   │
└──────────────────────────────────────────────────────────┘
```

## Fault Modes

All modes are **deterministic** and produce realistic multi-layered logs (not just `FAULT=X`).

### 1. `oom_pressure`

**Symptom:** Service crashes with exit code 137 (OOM kill)

**Logs:**
- `WARNING`: Memory pressure detected (1847/2048 MB, GC pause 450ms)
- `ERROR`: Memory allocation failed (ENOMEM, attempted 128 MB)
- `FATAL`: Out of memory - terminating (exit 137)

**Triage Hypotheses:**
1. Memory leak in order processing code
2. Container memory limit too low (2048 MB insufficient)
3. Traffic spike caused heap exhaustion

**Next Steps:**
- Check heap dumps and GC logs
- Review recent code changes to order handler
- Increase container memory limit to 4096 MB
- Set up memory profiling

**Trigger:**
```bash
curl http://localhost:8000/orders/999
# Or
curl -H "X-Fault: oom_pressure" http://localhost:8000/orders/123
```

---

### 2. `timeout_upstream`

**Symptom:** 504 Gateway Timeout after ~5 seconds

**Logs:**
- `INFO`: Calling payment service (timeout 5000ms)
- `WARNING`: Slow response after 1500ms
- `ERROR`: Timeout after 5000ms (ETIMEDOUT)

**Triage Hypotheses:**
1. payment-service-prod.internal is degraded or down
2. Network latency spike between services
3. Payment service DB connection pool exhausted

**Next Steps:**
- Check payment-service health and error rate
- Review payment-service logs for DB connection issues
- Verify network connectivity and DNS resolution
- Check if payment-service scaled down recently

**Trigger:**
```bash
curl -H "X-Fault: timeout_upstream" http://localhost:8000/orders/123
```

---

### 3. `bad_config`

**Symptom:** 500 Internal Server Error

**Logs:**
- `ERROR`: Configuration error (DATABASE_CONNECTION_STRING not set)
- `ERROR`: Failed to initialize database connection (NoneType.split())

**Triage Hypotheses:**
1. Missing environment variable in deployment config
2. ConfigMap/Secret not mounted in k8s pod
3. Recent deployment forgot to set DATABASE_CONNECTION_STRING

**Next Steps:**
- Check deployment manifests for DATABASE_CONNECTION_STRING
- Verify k8s ConfigMap and Secret are applied
- Compare current deployment with previous stable version
- Check if secret was rotated without updating pods

**Trigger:**
```bash
curl -H "X-Fault: bad_config" http://localhost:8000/orders/123
```

---

### 4. `deploy_crash`

**Symptom:** Service exits immediately with code 1 after deployment

**Logs:**
- `ERROR`: ModuleNotFoundError: payment_processor_v2
- `FATAL`: Critical startup dependency missing (deployment v2.5.0)

**Triage Hypotheses:**
1. Missing dependency in requirements.txt (payment_processor_v2)
2. Breaking change in v2.5.0 not present in v2.4.9
3. Build step failed to include new module

**Next Steps:**
- Review git diff between v2.4.9 and v2.5.0
- Check requirements.txt for payment_processor_v2
- Verify Docker build logs for missing pip install
- Roll back to v2.4.9 immediately

**Trigger:**
```bash
curl -H "X-Fault: deploy_crash" http://localhost:8000/orders/123
```

---

### 5. `dependency_blip`

**Symptom:** Intermittent 502 Bad Gateway (fails when `order_id % 3 == 0`)

**Logs:**
- `WARNING`: Inventory service health check failed (consecutive_failures: 2)
- `ERROR`: Failed to fetch inventory (503, circuit breaker open)

**Triage Hypotheses:**
1. inventory-service pods restarting intermittently
2. Load balancer routing to unhealthy instances
3. Intermittent network partition in k8s cluster

**Next Steps:**
- Check inventory-service pod status (`kubectl get pods`)
- Review inventory-service logs for crashes or OOM
- Verify k8s service endpoints and health checks
- Check if recent inventory-service deploy is rolling out

**Trigger:**
```bash
# These succeed:
curl -H "X-Fault: dependency_blip" http://localhost:8000/orders/100
curl -H "X-Fault: dependency_blip" http://localhost:8000/orders/101

# This fails (102 % 3 == 0):
curl -H "X-Fault: dependency_blip" http://localhost:8000/orders/102
```

---

### 6. `auth_misconfig`

**Symptom:** 401 Unauthorized

**Logs:**
- `WARNING`: Token validation started (issuer: auth.example.com)
- `ERROR`: JWT validation failed (token expired, clock skew 9300 seconds)
- `WARNING`: Clock synchronization issue (NTP unreachable)

**Triage Hypotheses:**
1. Server clock is 2.5 hours behind (9300 second skew)
2. NTP service unreachable for 2 days
3. Auth service or token issuer has wrong time

**Next Steps:**
- Check server time: `date` and `ntpq -p`
- Restart NTP service: `systemctl restart ntp`
- Verify auth.example.com is issuing valid tokens
- Check if clock was adjusted manually

**Trigger:**
```bash
curl -H "X-Fault: auth_misconfig" http://localhost:8000/orders/123
```

## Fault Injection Methods

### Method 1: Request Header (Temporary)

Override for a single request:

```bash
curl -H "X-Fault: oom_pressure" http://localhost:8000/orders/123
```

### Method 2: Environment Variable (Startup)

Set fault mode when starting the service:

```bash
# Docker Compose
FAULT_MODE=timeout_upstream docker-compose up

# Local Python
FAULT_MODE=bad_config python -m app.main
```

### Method 3: Admin API (Runtime)

Change fault mode without restarting:

```bash
# Set fault mode
curl -X POST http://localhost:8000/admin/fault?mode=oom_pressure \
  -H "X-Admin-Token: demo-secret-token"

# Check current mode
curl http://localhost:8000/admin/fault \
  -H "X-Admin-Token: demo-secret-token"
```

**Admin Token:**
- Default: `demo-secret-token`
- Override: Set `ADMIN_TOKEN` environment variable

## Demo Scripts

All scripts are in the `scripts/` directory and executable:

### Run Healthy Service

```bash
./scripts/run_healthy.sh
```

### Trigger Specific Failures

```bash
./scripts/fail_oom_pressure.sh
./scripts/fail_timeout_upstream.sh
./scripts/fail_bad_config.sh
./scripts/fail_deploy_crash.sh
./scripts/fail_dependency_blip.sh
./scripts/fail_auth_misconfig.sh
```

Each script:
1. Stops existing containers
2. Starts service with fault mode
3. Triggers the failure
4. Shows logs with expected symptoms

### Capture Logs and Alerts

```bash
./scripts/capture_logs.sh oom_pressure

# Outputs:
#   artifacts/logs/oom_pressure-20260920-220015.log
#   artifacts/alerts/oom_pressure.txt (fake PagerDuty alert)
```

## Pre-Captured Fixtures

For offline demos or when Docker isn't available:

```bash
# View structured logs
cat fixtures/oom_pressure.log | jq .
cat fixtures/timeout_upstream.log | jq .
cat fixtures/dependency_blip.log | jq .

# View fake CI failure
cat artifacts/ci/deploy-failure.txt
```

Available fixtures:
- `fixtures/oom_pressure.log`
- `fixtures/timeout_upstream.log`
- `fixtures/bad_config.log`
- `fixtures/deploy_crash.log`
- `fixtures/dependency_blip.log`
- `fixtures/auth_misconfig.log`
- `artifacts/ci/deploy-failure.txt` (GitHub Actions deploy failure)

## Log Format

All logs are structured JSON:

```json
{
  "timestamp": "2026-09-20T22:00:18.448Z",
  "level": "WARNING",
  "service": "faulty-app-demo",
  "message": "Memory pressure detected",
  "request_id": "a8f3c2d1-4e5f-6789-abcd-ef0123456789",
  "order_id": 999,
  "heap_used_mb": 1847,
  "heap_limit_mb": 2048,
  "gc_pause_ms": 450
}
```

**Key fields:**
- `timestamp`: ISO 8601 UTC
- `level`: INFO, WARNING, ERROR, FATAL
- `service`: faulty-app-demo
- `message`: Human-readable description
- `request_id`: UUID for request correlation
- Additional context fields per log entry

## API Reference

### `GET /health`

Health check endpoint (always returns 200).

**Response:**
```json
{
  "status": "healthy",
  "service": "faulty-app-demo",
  "version": "1.0.0"
}
```

### `GET /orders/{order_id}`

Get order by ID. Supports fault injection.

**Headers:**
- `X-Fault` (optional): Fault mode to inject

**Response (success):**
```json
{
  "order_id": 123,
  "status": "fulfilled",
  "items": ["widget-A", "widget-B"],
  "total": 129.99
}
```

**Response (fault):** Varies by fault mode (401, 500, 502, 504, or crash)

### `POST /admin/fault?mode=<mode>`

Set fault mode at runtime.

**Headers:**
- `X-Admin-Token`: Admin token (default: `demo-secret-token`)

**Query Parameters:**
- `mode`: Fault mode (none, oom_pressure, timeout_upstream, etc.)

**Response:**
```json
{
  "status": "ok",
  "fault_mode": "timeout_upstream"
}
```

### `GET /admin/fault`

Get current fault mode.

**Headers:**
- `X-Admin-Token`: Admin token

**Response:**
```json
{
  "fault_mode": "none"
}
```

## Make Targets

```bash
make help           # Show available targets
make build          # Build Docker image
make up             # Start service (detached)
make down           # Stop service
make logs           # Tail service logs
make restart        # Restart service
make clean          # Remove containers and images
make install-local  # Install Python deps locally
make test-local     # Run service locally (no Docker)
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `FAULT_MODE` | `none` | Initial fault mode at startup |
| `ADMIN_TOKEN` | `demo-secret-token` | Token for `/admin/fault` endpoint |

## Design Notes

### Safety Guarantees

1. **No Real OOM:** `oom_pressure` mode calls `sys.exit(137)` instead of allocating memory
2. **No Secrets:** Admin token is a demo value, not production-grade
3. **No Outbound Internet:** All failures are simulated locally
4. **No Data Persistence:** Stateless service, no database required

### Why These Failure Modes?

Each mode represents a common ops scenario:

- **OOM:** Frequent in memory-constrained containers
- **Timeout:** Classic distributed systems problem
- **Bad Config:** Common after deployments/secret rotations
- **Deploy Crash:** Dependency hell, classic CI/CD issue
- **Dependency Blip:** Intermittent failures are hardest to debug
- **Auth Misconfig:** Clock skew is a real production gotcha

### Log Design Principles

1. **Structured JSON:** Machine-parseable, queryable
2. **Request IDs:** Enable distributed tracing correlation
3. **Progressive Detail:** Logs show problem escalation (WARNING → ERROR → FATAL)
4. **Context-Rich:** Each log includes relevant metrics (heap_used_mb, elapsed_ms, etc.)
5. **No Single Smoking Gun:** Multiple logs required for full picture (realistic triage)

## Troubleshooting

**Service won't start:**
```bash
# Check Docker is running
docker ps

# Rebuild image
docker-compose down
make build
make up
```

**Port 8000 already in use:**
```bash
# Find process using port
lsof -ti:8000 | xargs kill -9

# Or change port in docker-compose.yml
```

**Logs not showing:**
```bash
# View all logs
docker-compose logs

# Follow logs in real-time
docker-compose logs -f
```

**Fault not triggering:**
```bash
# Verify fault mode is set
curl http://localhost:8000/admin/fault \
  -H "X-Admin-Token: demo-secret-token"

# Check service is running
curl http://localhost:8000/health
```

## Contributing

This is a demo app designed for a specific triage use case. Contributions welcome for:

- Additional realistic fault modes
- Improved log realism
- Better demo scripts

Not in scope:
- Real database integration
- Authentication/authorization
- Kubernetes manifests
- Monitoring/Grafana setup

## License

MIT License - Free for demo and educational use.

---

**For a 60-second live demo, see [`DEMO.md`](DEMO.md).**
