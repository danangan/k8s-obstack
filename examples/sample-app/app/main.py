import asyncio
import logging
import os
import random
import time
import uuid
from dataclasses import dataclass

from fastapi import FastAPI
from fastapi.responses import JSONResponse
from opentelemetry import metrics, trace
from opentelemetry.instrumentation.fastapi import FastAPIInstrumentor
from opentelemetry.trace import SpanKind

from app.logging_config import setup_logging
from app.telemetry import setup_telemetry

setup_logging()
setup_telemetry()

log = logging.getLogger("sample-api")

app = FastAPI(title="sample-api")
# http.server.* metrics + a server span per request. Skip the readiness probe, and the
# per-ASGI-message "http send/receive" spans that add noise without information.
FastAPIInstrumentor.instrument_app(app, excluded_urls="healthz", exclude_spans=["receive", "send"])

meter = metrics.get_meter("sample-api")
tracer = trace.get_tracer("sample-api")

orders_counter = meter.create_counter("orders.created", unit="{order}", description="Orders created")
orders_failed = meter.create_counter("orders.failed", unit="{order}", description="Orders that failed, by reason")
processing_time = meter.create_histogram("orders.processing.duration", unit="s", description="Order processing time")

# Fraction of /orders requests that fail (0.0-1.0).
FAILURE_RATE = float(os.getenv("ORDER_FAILURE_RATE", "0.2"))


@dataclass(frozen=True)
class Failure:
    reason: str
    step: str  # the processing step (span) where it happens
    status: int  # HTTP status returned
    level: int  # log level
    weight: int  # relative likelihood
    extra_latency: tuple[float, float]  # seconds added to the failing step


FAILURES = [
    Failure("out_of_stock", "reserve inventory", 409, logging.WARNING, 5, (0.0, 0.05)),
    Failure("payment_declined", "charge payment", 402, logging.WARNING, 3, (0.1, 0.3)),
    Failure("database_timeout", "save order", 500, logging.ERROR, 2, (1.0, 2.0)),
]


class OrderFailed(Exception):
    def __init__(self, failure: Failure):
        super().__init__(failure.reason)
        self.failure = failure


async def run_step(name: str, failure: Failure | None, kind: SpanKind = SpanKind.INTERNAL, **attributes) -> None:
    """Simulate one processing step as a child span. If `failure` belongs to this step, the step
    raises; the span records the exception and is marked as an error."""
    with tracer.start_as_current_span(name, kind=kind, attributes=attributes):
        await asyncio.sleep(random.uniform(0.005, 0.04))
        if failure and failure.step == name:
            await asyncio.sleep(random.uniform(*failure.extra_latency))
            raise OrderFailed(failure)


@app.get("/healthz")
def healthz():
    return {"status": "ok"}


@app.get("/")
def root():
    log.info("hello requested")
    return {"message": "hello from sample-api"}


@app.post("/orders")
async def create_order(item: str = "widget", quantity: int = 1):
    order_id = str(uuid.uuid4())
    fields = {"order_id": order_id, "item": item, "quantity": quantity}
    # Tag the server span so traces can be searched by order, e.g. { span.order.item = "book" }.
    trace.get_current_span().set_attributes({"order.id": order_id, "order.item": item, "order.quantity": quantity})
    log.info("order received", extra=fields)

    failure = None
    if random.random() < FAILURE_RATE:
        failure = random.choices(FAILURES, weights=[f.weight for f in FAILURES])[0]

    start = time.perf_counter()
    try:
        await run_step("validate order", failure)
        await run_step("reserve inventory", failure, **{"inventory.item": item, "inventory.quantity": quantity})
        # CLIENT spans to (simulated) external dependencies; `peer.service` / `db.system` make them
        # show up as separate nodes in Tempo's service graph.
        await run_step("charge payment", failure, SpanKind.CLIENT, **{"peer.service": "payment-gateway"})
        await run_step(
            "save order", failure, SpanKind.CLIENT,
            **{"db.system": "postgresql", "db.name": "orders", "db.operation": "INSERT"},
        )
    except OrderFailed as exc:
        f = exc.failure
        duration = time.perf_counter() - start
        orders_failed.add(quantity, {"item": item, "reason": f.reason})
        processing_time.record(duration, {"item": item, "outcome": f.reason})
        log.log(f.level, "order failed", extra={**fields, "reason": f.reason, "duration_s": round(duration, 3)})
        return JSONResponse(status_code=f.status, content={**fields, "status": "failed", "reason": f.reason})

    duration = time.perf_counter() - start
    orders_counter.add(quantity, {"item": item})
    processing_time.record(duration, {"item": item, "outcome": "success"})
    log.info("order created", extra={**fields, "duration_s": round(duration, 3)})
    return {**fields, "status": "created"}
