#!/usr/bin/env python3
"""Alertmanager webhook receiver: runs a read-only HolmesGPT investigation and posts the RCA to Slack."""
import json
import os
import re
import subprocess
import tempfile
import threading
import time
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HOST = os.environ.get("RECEIVER_HOST", "127.0.0.1")
PORT = int(os.environ.get("RECEIVER_PORT", "9095"))
ALERTMANAGER_URL = os.environ.get("ALERTMANAGER_URL", "http://localhost:9093")
SLACK_WEBHOOK_URL = os.environ.get("SLACK_WEBHOOK_URL", "")
HOLMES_BIN = os.environ.get("HOLMES_BIN", "holmes")
ALLOWED_ALERTS = set(os.environ.get("ALLOWED_ALERTS", "SubprefixProbeFailure").split(","))
DEDUPE_SECONDS = int(os.environ.get("DEDUPE_SECONDS", "600"))
HOLMES_TIMEOUT = int(os.environ.get("HOLMES_TIMEOUT", "600"))
SLACK_LIMIT = 3500

_seen = {}
_lock = threading.Lock()
_ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")


def post_slack(text):
    if not SLACK_WEBHOOK_URL:
        print(f"[slack disabled]\n{text}\n", flush=True)
        return
    body = json.dumps({"text": text[:SLACK_LIMIT]}).encode()
    req = urllib.request.Request(SLACK_WEBHOOK_URL, body, {"Content-Type": "application/json"})
    urllib.request.urlopen(req, timeout=15).read()


def investigate(alertname):
    started = time.time()
    with tempfile.NamedTemporaryFile(suffix=".json") as out:
        cmd = [
            HOLMES_BIN, "investigate", "alertmanager",
            "--alertmanager-url", ALERTMANAGER_URL,
            "--alertmanager-alertname", alertname,
            "--json-output-file", out.name,
        ]
        try:
            proc = subprocess.run(cmd, capture_output=True, text=True, timeout=HOLMES_TIMEOUT)
        except subprocess.TimeoutExpired:
            post_slack(f":warning: Holmes timed out on *{alertname}*. On-call: investigate manually.")
            return
        rca = ""
        try:
            data = json.load(open(out.name))
            rca = data[0].get("analysis", "") if isinstance(data, list) else data.get("analysis", "")
        except (OSError, ValueError, AttributeError, IndexError):
            pass
        if not rca:
            rca = _ANSI.sub("", proc.stdout)[-SLACK_LIMIT:]
    elapsed = int(time.time() - started)
    if not rca.strip():
        post_slack(f":warning: Holmes returned no RCA for *{alertname}*. On-call: investigate manually.")
        return
    post_slack(f":mag: *HolmesGPT RCA for {alertname}* ({elapsed}s, read-only)\n{rca}\n_Unverified. A human approves any change._")


def should_run(alert):
    name = alert.get("labels", {}).get("alertname", "")
    if alert.get("status") != "firing" or name not in ALLOWED_ALERTS:
        return None
    key = alert.get("fingerprint", name)
    with _lock:
        if time.time() - _seen.get(key, 0) < DEDUPE_SECONDS:
            return None
        _seen[key] = time.time()
    return name


class Handler(BaseHTTPRequestHandler):
    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        try:
            payload = json.loads(self.rfile.read(min(length, 1_000_000)))
        except ValueError:
            self.send_response(400)
            self.end_headers()
            return
        self.send_response(202)
        self.end_headers()
        for alert in payload.get("alerts", []):
            name = should_run(alert)
            if name:
                threading.Thread(target=investigate, args=(name,), daemon=True).start()

    def log_message(self, fmt, *args):
        print(f"{self.address_string()} {fmt % args}", flush=True)


if __name__ == "__main__":
    print(f"listening on {HOST}:{PORT}, alerts={sorted(ALLOWED_ALERTS)}, slack={'on' if SLACK_WEBHOOK_URL else 'off'}", flush=True)
    ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()
