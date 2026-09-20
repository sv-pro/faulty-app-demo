#!/bin/bash
set -e

if [ -z "$1" ]; then
    echo "Usage: $0 <fault_mode>"
    echo "Fault modes: oom_pressure, timeout_upstream, bad_config, deploy_crash, dependency_blip, auth_misconfig"
    exit 1
fi

FAULT_MODE=$1
TIMESTAMP=$(date +%Y%m%d-%H%M%S)
LOG_DIR="artifacts/logs"
ALERT_DIR="artifacts/alerts"

mkdir -p "$LOG_DIR"
mkdir -p "$ALERT_DIR"

LOG_FILE="$LOG_DIR/${FAULT_MODE}-${TIMESTAMP}.log"
ALERT_FILE="$ALERT_DIR/${FAULT_MODE}.txt"

echo "=== Capturing logs for fault mode: $FAULT_MODE ==="
echo ""

# Stop existing containers
docker-compose down 2>/dev/null || true

# Start with the fault mode (if not deploy_crash which needs header)
if [ "$FAULT_MODE" == "oom_pressure" ]; then
    export FAULT_MODE=oom_pressure
    docker-compose up -d
    sleep 2
    curl -s http://localhost:8000/orders/999 > /dev/null || true
    sleep 1
elif [ "$FAULT_MODE" == "timeout_upstream" ]; then
    export FAULT_MODE=none
    docker-compose up -d
    sleep 2
    curl -s -H "X-Fault: timeout_upstream" http://localhost:8000/orders/123 > /dev/null || true
    sleep 1
elif [ "$FAULT_MODE" == "bad_config" ]; then
    export FAULT_MODE=none
    docker-compose up -d
    sleep 2
    curl -s -H "X-Fault: bad_config" http://localhost:8000/orders/123 > /dev/null || true
    sleep 1
elif [ "$FAULT_MODE" == "deploy_crash" ]; then
    export FAULT_MODE=none
    docker-compose up -d
    sleep 2
    curl -s -H "X-Fault: deploy_crash" http://localhost:8000/orders/123 > /dev/null || true
    sleep 1
elif [ "$FAULT_MODE" == "dependency_blip" ]; then
    export FAULT_MODE=none
    docker-compose up -d
    sleep 2
    curl -s -H "X-Fault: dependency_blip" http://localhost:8000/orders/102 > /dev/null || true
    sleep 1
elif [ "$FAULT_MODE" == "auth_misconfig" ]; then
    export FAULT_MODE=none
    docker-compose up -d
    sleep 2
    curl -s -H "X-Fault: auth_misconfig" http://localhost:8000/orders/123 > /dev/null || true
    sleep 1
else
    echo "Unknown fault mode: $FAULT_MODE"
    exit 1
fi

# Capture logs
echo "Capturing logs to $LOG_FILE..."
docker-compose logs --tail=50 > "$LOG_FILE"

# Generate fake alert
echo "Generating alert to $ALERT_FILE..."
cat > "$ALERT_FILE" <<EOF
╔═══════════════════════════════════════════════════════════════════╗
║              🚨 PAGERDUTY INCIDENT ALERT 🚨                       ║
╚═══════════════════════════════════════════════════════════════════╝

Incident ID: INC-$(date +%Y%m%d)-$(( RANDOM % 9000 + 1000 ))
Service: faulty-app-demo (Production)
Severity: HIGH
Status: TRIGGERED
Created: $(date '+%Y-%m-%d %H:%M:%S UTC')

────────────────────────────────────────────────────────────────────
SUMMARY
────────────────────────────────────────────────────────────────────
EOF

case "$FAULT_MODE" in
    oom_pressure)
        cat >> "$ALERT_FILE" <<EOF
Service faulty-app-demo has crashed with exit code 137 (OOM Kill)

────────────────────────────────────────────────────────────────────
DETAILS
────────────────────────────────────────────────────────────────────
• Exit Code: 137 (SIGKILL - Out of Memory)
• Last Known State: Memory pressure detected (2012/2048 MB used)
• Restart Count: 5 in last 10 minutes
• Grafana: Memory usage spiked to 98% before crash

────────────────────────────────────────────────────────────────────
METRICS
────────────────────────────────────────────────────────────────────
• Heap Usage: 2048 MB / 2048 MB (100%)
• GC Pause: 450ms (abnormal)
• Last Allocation Failed: 128 MB
• Container State: Restarting
EOF
        ;;
    timeout_upstream)
        cat >> "$ALERT_FILE" <<EOF
High latency and timeouts detected on /orders endpoint

────────────────────────────────────────────────────────────────────
DETAILS
────────────────────────────────────────────────────────────────────
• Affected Endpoint: GET /orders/{id}
• Error Rate: 85% (504 Gateway Timeout)
• P99 Latency: 5000ms (SLA: 500ms)
• Upstream: payment-service-prod.internal
• Time Window: Last 5 minutes

────────────────────────────────────────────────────────────────────
METRICS
────────────────────────────────────────────────────────────────────
• Timeout Count: 47 in last 5 minutes
• Upstream Health: Degraded
• Circuit Breaker: Half-Open
• User Impact: Payment processing blocked
EOF
        ;;
    bad_config)
        cat >> "$ALERT_FILE" <<EOF
Configuration error causing 500 Internal Server Error

────────────────────────────────────────────────────────────────────
DETAILS
────────────────────────────────────────────────────────────────────
• Error Type: Configuration Missing
• Config Key: DATABASE_CONNECTION_STRING
• Error Rate: 100% on affected endpoints
• First Seen: $(date '+%Y-%m-%d %H:%M:%S UTC')
• Deployment: v2.5.0 (deployed 10 minutes ago)

────────────────────────────────────────────────────────────────────
METRICS
────────────────────────────────────────────────────────────────────
• 500 Errors: 234 in last 5 minutes
• Success Rate: 0%
• Affected Endpoints: /orders/*
• Database Connection: Failed
EOF
        ;;
    deploy_crash)
        cat >> "$ALERT_FILE" <<EOF
Service crash immediately after deployment v2.5.0

────────────────────────────────────────────────────────────────────
DETAILS
────────────────────────────────────────────────────────────────────
• Deployment: v2.5.0 → FAILED
• Previous Stable: v2.4.9
• Exit Code: 1 (Fatal Error)
• Error: ModuleNotFoundError: payment_processor_v2
• Rollback: Recommended

────────────────────────────────────────────────────────────────────
METRICS
────────────────────────────────────────────────────────────────────
• Crash Loop: 8 restarts in 3 minutes
• Uptime: <5 seconds per restart
• Traffic: Routing to old pods (v2.4.9)
• Deployment Progress: 0/5 pods ready
EOF
        ;;
    dependency_blip)
        cat >> "$ALERT_FILE" <<EOF
Intermittent failures from inventory-service dependency

────────────────────────────────────────────────────────────────────
DETAILS
────────────────────────────────────────────────────────────────────
• Upstream: inventory-service.prod.svc.cluster.local
• Error Type: 503 Service Unavailable
• Error Pattern: Intermittent (30% failure rate)
• Circuit Breaker: OPEN
• Impact: Order fulfillment blocked

────────────────────────────────────────────────────────────────────
METRICS
────────────────────────────────────────────────────────────────────
• Success Rate: 70% (SLA: 99.9%)
• 502/503 Errors: 89 in last 5 minutes
• Upstream Health Checks: 2 consecutive failures
• Retry Exhausted: 45 requests
EOF
        ;;
    auth_misconfig)
        cat >> "$ALERT_FILE" <<EOF
Authentication failures - JWT validation errors

────────────────────────────────────────────────────────────────────
DETAILS
────────────────────────────────────────────────────────────────────
• Error Type: 401 Unauthorized
• Cause: JWT signature expired
• Clock Skew: 9300 seconds (~2.5 hours)
• NTP Status: Unreachable
• Last NTP Sync: 2 days ago

────────────────────────────────────────────────────────────────────
METRICS
────────────────────────────────────────────────────────────────────
• 401 Errors: 567 in last 5 minutes
• Auth Success Rate: 0%
• Token Issuer: auth.example.com
• Expected Audience: faulty-app-prod
EOF
        ;;
esac

cat >> "$ALERT_FILE" <<EOF

────────────────────────────────────────────────────────────────────
ACTIONS
────────────────────────────────────────────────────────────────────
• Acknowledge incident: https://acme.pagerduty.com/incidents/$(date +%s)
• Runbook: https://docs.internal/runbooks/faulty-app
• Logs: Check artifacts/logs/${FAULT_MODE}-${TIMESTAMP}.log
• Escalate to: Platform Team (if not resolved in 15 minutes)

────────────────────────────────────────────────────────────────────
This is an automated alert from Grafana Alert Manager
EOF

echo ""
echo "✓ Logs saved to: $LOG_FILE"
echo "✓ Alert saved to: $ALERT_FILE"
echo ""
echo "View logs: cat $LOG_FILE"
echo "View alert: cat $ALERT_FILE"
