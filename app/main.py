"""
Faulty App Demo - HTTP service with controlled fault injection.
Designed for incident triage demonstrations.
"""
import asyncio
import json
import logging
import os
import sys
import time
from datetime import datetime
from typing import Optional
from uuid import uuid4

from fastapi import FastAPI, Header, HTTPException, Request, Response
from fastapi.responses import JSONResponse
import uvicorn

SERVICE_NAME = "faulty-app-demo"
VERSION = "1.0.0"
ADMIN_TOKEN = os.getenv("ADMIN_TOKEN", "demo-secret-token")
FAULT_MODE = os.getenv("FAULT_MODE", "none")

current_fault_mode = FAULT_MODE


class StructuredLogger:
    """JSON structured logger for realistic ops logging."""
    
    def __init__(self, service_name: str):
        self.service_name = service_name
        self.logger = logging.getLogger(service_name)
        handler = logging.StreamHandler(sys.stdout)
        handler.setFormatter(logging.Formatter('%(message)s'))
        self.logger.addHandler(handler)
        self.logger.setLevel(logging.INFO)
    
    def _log(self, level: str, message: str, **kwargs):
        log_entry = {
            "timestamp": datetime.utcnow().isoformat() + "Z",
            "level": level,
            "service": self.service_name,
            "message": message,
            **kwargs
        }
        self.logger.info(json.dumps(log_entry))
    
    def info(self, message: str, **kwargs):
        self._log("INFO", message, **kwargs)
    
    def warning(self, message: str, **kwargs):
        self._log("WARNING", message, **kwargs)
    
    def error(self, message: str, **kwargs):
        self._log("ERROR", message, **kwargs)
    
    def fatal(self, message: str, **kwargs):
        self._log("FATAL", message, **kwargs)


logger = StructuredLogger(SERVICE_NAME)

app = FastAPI(title="Faulty App Demo", version=VERSION)


def get_request_id() -> str:
    """Generate unique request ID."""
    return str(uuid4())


@app.middleware("http")
async def logging_middleware(request: Request, call_next):
    """Add request logging and fault injection."""
    request_id = get_request_id()
    request.state.request_id = request_id
    
    start_time = time.time()
    
    logger.info(
        "Request started",
        request_id=request_id,
        method=request.method,
        path=request.url.path,
        client_ip=request.client.host if request.client else "unknown"
    )
    
    try:
        response = await call_next(request)
        duration_ms = (time.time() - start_time) * 1000
        
        logger.info(
            "Request completed",
            request_id=request_id,
            method=request.method,
            path=request.url.path,
            status_code=response.status_code,
            duration_ms=round(duration_ms, 2)
        )
        
        return response
    except Exception as e:
        duration_ms = (time.time() - start_time) * 1000
        logger.error(
            "Request failed",
            request_id=request_id,
            method=request.method,
            path=request.url.path,
            error=str(e),
            duration_ms=round(duration_ms, 2)
        )
        raise


@app.get("/health")
async def health_check():
    """Health check endpoint."""
    return {"status": "healthy", "service": SERVICE_NAME, "version": VERSION}


@app.get("/orders/{order_id}")
async def get_order(
    order_id: int,
    request: Request,
    x_fault: Optional[str] = Header(None)
):
    """
    Get order by ID. Supports fault injection via X-Fault header.
    """
    request_id = getattr(request.state, 'request_id', 'unknown')
    
    # Determine active fault mode (header overrides env)
    fault_mode = x_fault or current_fault_mode
    
    logger.info(
        "Processing order request",
        request_id=request_id,
        order_id=order_id,
        fault_mode=fault_mode
    )
    
    # Execute fault injection
    if fault_mode == "oom_pressure":
        return await inject_oom_pressure(request_id, order_id)
    elif fault_mode == "timeout_upstream":
        return await inject_timeout_upstream(request_id, order_id)
    elif fault_mode == "bad_config":
        return await inject_bad_config(request_id, order_id)
    elif fault_mode == "deploy_crash":
        return await inject_deploy_crash(request_id, order_id)
    elif fault_mode == "dependency_blip":
        return await inject_dependency_blip(request_id, order_id)
    elif fault_mode == "auth_misconfig":
        return await inject_auth_misconfig(request_id, order_id)
    
    # Happy path
    logger.info(
        "Order retrieved successfully",
        request_id=request_id,
        order_id=order_id,
        status="fulfilled"
    )
    
    return {
        "order_id": order_id,
        "status": "fulfilled",
        "items": ["widget-A", "widget-B"],
        "total": 129.99
    }


async def inject_oom_pressure(request_id: str, order_id: int):
    """Simulate OOM pressure leading to crash."""
    logger.warning(
        "Memory pressure detected",
        request_id=request_id,
        order_id=order_id,
        heap_used_mb=1847,
        heap_limit_mb=2048,
        gc_pause_ms=450
    )
    
    logger.error(
        "Memory allocation failed",
        request_id=request_id,
        order_id=order_id,
        heap_used_mb=2012,
        heap_limit_mb=2048,
        allocation_size_mb=128,
        error_code="ENOMEM"
    )
    
    logger.fatal(
        "Out of memory - terminating",
        request_id=request_id,
        exit_code=137,
        heap_used_mb=2048,
        heap_limit_mb=2048
    )
    
    # Simulate crash without actually OOMing the host
    sys.exit(137)


async def inject_timeout_upstream(request_id: str, order_id: int):
    """Simulate upstream service timeout."""
    logger.info(
        "Calling payment service",
        request_id=request_id,
        order_id=order_id,
        upstream_service="payment-service-prod.internal",
        timeout_ms=5000
    )
    
    # Simulate delay
    await asyncio.sleep(1.5)
    
    logger.warning(
        "Upstream service slow response",
        request_id=request_id,
        order_id=order_id,
        upstream_service="payment-service-prod.internal",
        elapsed_ms=1500,
        timeout_ms=5000
    )
    
    await asyncio.sleep(3.5)
    
    logger.error(
        "Upstream service timeout",
        request_id=request_id,
        order_id=order_id,
        upstream_service="payment-service-prod.internal",
        elapsed_ms=5000,
        timeout_ms=5000,
        error_code="ETIMEDOUT"
    )
    
    raise HTTPException(
        status_code=504,
        detail="Upstream service timeout"
    )


async def inject_bad_config(request_id: str, order_id: int):
    """Simulate missing/invalid configuration."""
    logger.error(
        "Configuration error",
        request_id=request_id,
        order_id=order_id,
        config_key="DATABASE_CONNECTION_STRING",
        error="Configuration value not set or empty",
        expected_format="postgresql://user:pass@host:port/db"
    )
    
    logger.error(
        "Failed to initialize database connection",
        request_id=request_id,
        error="NoneType object has no attribute 'split'",
        config_key="DATABASE_CONNECTION_STRING"
    )
    
    raise HTTPException(
        status_code=500,
        detail="Service configuration error"
    )


async def inject_deploy_crash(request_id: str, order_id: int):
    """Simulate process crash after deployment."""
    logger.error(
        "Failed to load required module",
        request_id=request_id,
        order_id=order_id,
        module_name="payment_processor_v2",
        error="ModuleNotFoundError: No module named 'payment_processor_v2'",
        python_path="/app:/app/lib:/usr/local/lib/python3.11"
    )
    
    logger.fatal(
        "Critical startup dependency missing - terminating",
        request_id=request_id,
        exit_code=1,
        deployment_version="v2.5.0",
        previous_version="v2.4.9"
    )
    
    sys.exit(1)


async def inject_dependency_blip(request_id: str, order_id: int):
    """Simulate intermittent dependency failure."""
    # Fail deterministically based on order_id
    if order_id % 3 == 0:
        logger.warning(
            "Inventory service health check failed",
            request_id=request_id,
            order_id=order_id,
            upstream_service="inventory-service.prod.svc.cluster.local",
            health_status="unhealthy",
            consecutive_failures=2
        )
        
        logger.error(
            "Failed to fetch inventory",
            request_id=request_id,
            order_id=order_id,
            upstream_service="inventory-service.prod.svc.cluster.local",
            status_code=503,
            error="Service Unavailable",
            circuit_breaker_state="open"
        )
        
        raise HTTPException(
            status_code=502,
            detail="Upstream dependency unavailable"
        )
    
    # Success case
    logger.info(
        "Inventory check completed",
        request_id=request_id,
        order_id=order_id,
        in_stock=True
    )
    
    return {
        "order_id": order_id,
        "status": "fulfilled",
        "items": ["widget-A"],
        "total": 59.99
    }


async def inject_auth_misconfig(request_id: str, order_id: int):
    """Simulate authentication misconfiguration."""
    logger.warning(
        "Token validation started",
        request_id=request_id,
        order_id=order_id,
        token_issuer="https://auth.example.com",
        expected_audience="faulty-app-prod"
    )
    
    logger.error(
        "JWT validation failed",
        request_id=request_id,
        order_id=order_id,
        error="Token signature expired",
        token_issued_at="2026-09-20T18:30:00Z",
        token_expires_at="2026-09-20T19:30:00Z",
        server_time="2026-09-20T22:05:00Z",
        clock_skew_detected=True,
        skew_seconds=9300
    )
    
    logger.warning(
        "Possible clock synchronization issue",
        request_id=request_id,
        server_time="2026-09-20T22:05:00Z",
        ntp_last_sync="2026-09-18T14:22:00Z",
        ntp_status="unreachable"
    )
    
    raise HTTPException(
        status_code=401,
        detail="Authentication failed"
    )


@app.post("/admin/fault")
async def set_fault_mode(
    mode: str,
    token: str = Header(None, alias="X-Admin-Token")
):
    """Admin endpoint to change fault mode at runtime."""
    global current_fault_mode
    
    if token != ADMIN_TOKEN:
        logger.warning(
            "Unauthorized admin access attempt",
            provided_token=token[:8] + "..." if token else "none"
        )
        raise HTTPException(status_code=403, detail="Invalid admin token")
    
    valid_modes = [
        "none", "oom_pressure", "timeout_upstream", "bad_config",
        "deploy_crash", "dependency_blip", "auth_misconfig"
    ]
    
    if mode not in valid_modes:
        raise HTTPException(
            status_code=400,
            detail=f"Invalid mode. Valid modes: {', '.join(valid_modes)}"
        )
    
    current_fault_mode = mode
    logger.info(
        "Fault mode changed",
        new_mode=mode,
        previous_mode=current_fault_mode
    )
    
    return {"status": "ok", "fault_mode": mode}


@app.get("/admin/fault")
async def get_fault_mode(token: str = Header(None, alias="X-Admin-Token")):
    """Get current fault mode."""
    if token != ADMIN_TOKEN:
        raise HTTPException(status_code=403, detail="Invalid admin token")
    
    return {"fault_mode": current_fault_mode}


if __name__ == "__main__":
    # Check for bad_config at startup if FAULT_MODE=bad_config
    if FAULT_MODE == "bad_config":
        logger.error(
            "Startup configuration validation failed",
            config_key="DATABASE_CONNECTION_STRING",
            error="Required configuration missing"
        )
        logger.fatal(
            "Cannot start service with invalid configuration",
            exit_code=1
        )
        sys.exit(1)
    
    logger.info(
        "Service starting",
        service=SERVICE_NAME,
        version=VERSION,
        fault_mode=FAULT_MODE,
        port=8000
    )
    
    uvicorn.run(app, host="0.0.0.0", port=8000, log_config=None)
