"""Structured (JSON) logging to stdout.

One JSON object per line, e.g.
  {"level": "INFO", "message": "order created", "order_id": "..."}

The otel collector's file_log receiver parses these lines: `level` becomes the log severity
and the other fields become log attributes (structured metadata in Loki). There's no timestamp
field: the container runtime stamps every line, and the collector uses that as the log time.
Pod identity (namespace, pod, container, node, deployment) is also added by the collector,
so the app doesn't log it. Lines logged inside a span carry `trace_id` and `span_id`, which
Grafana uses to link logs and traces.
"""
import json
import logging
import os
import sys

from opentelemetry import trace

# Attributes every LogRecord has; anything else was passed via `extra=` and is logged as a field.
# (color_message is uvicorn's ANSI-colored duplicate of the message.)
_STANDARD_ATTRS = set(vars(logging.makeLogRecord({}))) | {"message", "asctime", "taskName", "color_message"}


class JsonFormatter(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        entry = {
            "level": record.levelname,
            "message": record.getMessage(),
        }
        # uvicorn access records carry the request details as positional args.
        if record.name == "uvicorn.access" and isinstance(record.args, tuple) and len(record.args) == 5:
            client, method, path, http_version, status = record.args
            entry.update(client=client, method=method, path=path, http_version=http_version, status_code=status)
        for key, value in vars(record).items():
            if key not in _STANDARD_ATTRS and not key.startswith("_"):
                entry[key] = value
        span_context = trace.get_current_span().get_span_context()
        if span_context.is_valid:
            entry["trace_id"] = trace.format_trace_id(span_context.trace_id)
            entry["span_id"] = trace.format_span_id(span_context.span_id)
        if record.exc_info:
            entry["exception"] = self.formatException(record.exc_info)
        return json.dumps(entry, default=str)


def setup_logging() -> None:
    handler = logging.StreamHandler(sys.stdout)
    handler.setFormatter(JsonFormatter())

    root = logging.getLogger()
    root.handlers[:] = [handler]
    root.setLevel(os.getenv("LOG_LEVEL", "INFO").upper())

    # uvicorn configures its own plain-text handlers before importing the app; route them
    # through the root JSON handler instead.
    for name in ("uvicorn", "uvicorn.error", "uvicorn.access"):
        logger = logging.getLogger(name)
        logger.handlers.clear()
        logger.propagate = True
