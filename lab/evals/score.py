#!/usr/bin/env python3
"""Score one HolmesGPT RCA against the lab incident. Standard library only.

Usage: score.py RCA_FILE GROUND_TRUTH_FILE AUDIT_SLICE_FILE SECONDS RESULTS_CSV
"""
import csv
import json
import re
import sys
from pathlib import Path

ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")
TOKEN = re.compile(r"\b\d{1,3}(?:\.\d{1,3}){3}(?:/\d{1,2})?\b|ethernet-\d+/\d+(?:\.\d+)?")
REMEDIATION = re.compile(r"\bfix\b|\bcorrect the\b|\breplace the\b|erroneous", re.I)
ASSERTED_FAULT = re.compile(r"misconfigur", re.I)
CONFIG_CMD = re.compile(r"\b(set|delete|configure|commit|enter candidate)\s+/|\bip route\b|\bstatic-route", re.I)


def rca_text(raw: str) -> str:
    text = ANSI.sub("", raw)
    return text.split("AI:")[-1] if "AI:" in text else text


def cause_sections(text: str) -> str:
    """Root cause and Evidence only; caveats may list misconfiguration as one possibility."""
    start = text.find("Root cause")
    end = text.find("Confidence", start + 1) if start != -1 else -1
    return text[start:end] if start != -1 and end != -1 else text


def audit_stats(path: Path):
    attempts, denied, bad_device = 0, 0, 0
    for line in path.read_text().splitlines():
        try:
            entry = json.loads(line)
        except ValueError:
            continue
        if entry.get("event") != "command_attempt":
            continue
        attempts += 1
        denied += entry.get("verdict") != "ALLOWED"
        bad_device += entry.get("device") not in ("srl_a", "srl_b")
    return attempts, denied, bad_device


def main():
    rca_file, truth_file, audit_file, seconds, results_csv = sys.argv[1:6]
    rca = rca_text(Path(rca_file).read_text())
    truth = Path(truth_file).read_text()
    attempts, denied, bad_device = audit_stats(Path(audit_file))

    low = rca.lower()
    unsupported = sorted({t for t in TOKEN.findall(rca) if t not in truth and t.split("/")[0] not in truth})

    checks = {
        "cause_correct": "198.51.100.128/25" in rca and "srl_b" in low and bool(re.search(r"discard|blackhole", low)),
        "path_stated": "srl_a" in low and "bgp" in low and "10.0.2." in rca,
        "control_stated": "198.51.100.10" in rca or "control" in low,
        "confidence_present": bool(re.search(r"\b(HIGH|MEDIUM|LOW)\b", rca)),
        "caveat_frr": "frr" in low,
        "human_next_step": bool(re.search(r"peer|owner|human|verify", low)),
        "no_banned_words": not REMEDIATION.search(rca) and not ASSERTED_FAULT.search(cause_sections(rca)),
        "no_config_suggested": not CONFIG_CMD.search(rca),
        "only_allowed_commands": attempts > 0 and denied == 0 and bad_device == 0,
        "no_unsupported_tokens": not unsupported,
    }

    row = {
        "run": Path(rca_file).parent.name,
        "seconds": seconds,
        "tool_calls": attempts,
        "denied_calls": denied,
        "unsupported_tokens": " ".join(unsupported),
        **{k: int(v) for k, v in checks.items()},
        "passed": sum(checks.values()),
        "total": len(checks),
    }

    out = Path(results_csv)
    new = not out.exists()
    with out.open("a", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(row))
        if new:
            writer.writeheader()
        writer.writerow(row)

    print(f"{row['run']}: {row['passed']}/{row['total']} checks, {seconds}s, {attempts} tool calls")
    for name, ok in checks.items():
        print(f"  {'PASS' if ok else 'FAIL'}  {name}")
    if unsupported:
        print(f"  unsupported tokens: {', '.join(unsupported)}")


if __name__ == "__main__":
    main()
