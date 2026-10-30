"""Failure alerting. Slack webhook if SLACK_WEBHOOK_URL is set; email via default_args; always logs."""
from __future__ import annotations

import json
import logging
import os
import urllib.request

log = logging.getLogger(__name__)


def notify_failure(context) -> None:
    ti = context["task_instance"]
    msg = (f":red_circle: *{ti.dag_id}.{ti.task_id}* failed "
           f"(run {context['run_id']}, try {ti.try_number}). Logs: {ti.log_url}")
    log.error(msg)
    url = os.getenv("SLACK_WEBHOOK_URL")
    if url:
        req = urllib.request.Request(url, data=json.dumps({"text": msg}).encode(),
                                     headers={"Content-Type": "application/json"})
        try:
            urllib.request.urlopen(req, timeout=10)
        except Exception:  # alerting must never mask the real failure
            log.exception("Slack alert failed")
