"""OpenTelemetry SDK setup: metrics and traces over OTLP/HTTP to the node-local collector.

Endpoint and service name come from the standard OTEL_* env vars
(OTEL_EXPORTER_OTLP_ENDPOINT, OTEL_SERVICE_NAME), set in the k8s Deployment.
"""
import logging
import os
from opentelemetry import metrics, trace
from opentelemetry.exporter.otlp.proto.http.metric_exporter import OTLPMetricExporter
from opentelemetry.exporter.otlp.proto.http.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.metrics import MeterProvider
from opentelemetry.sdk.metrics.export import PeriodicExportingMetricReader
from opentelemetry.sdk.resources import Resource
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor


def setup_telemetry() -> None:
    otel_endpoint = os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT")
    otel_servicename = os.getenv("OTEL_SERVICE_NAME")
    logging.getLogger("sample-api").info(
        "configuring telemetry", extra={"otlp_endpoint": otel_endpoint, "service": otel_servicename}
    )
    resource = Resource.create()  # reads OTEL_SERVICE_NAME / OTEL_RESOURCE_ATTRIBUTES

    reader = PeriodicExportingMetricReader(OTLPMetricExporter(), export_interval_millis=1000)
    metrics.set_meter_provider(MeterProvider(resource=resource, metric_readers=[reader]))

    tracer_provider = TracerProvider(resource=resource)
    tracer_provider.add_span_processor(BatchSpanProcessor(OTLPSpanExporter()))
    trace.set_tracer_provider(tracer_provider)
