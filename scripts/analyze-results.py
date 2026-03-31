#!/usr/bin/env python3
"""
Parses a JMeter JTL file and prints an acceptance criteria report.
Writes a Markdown summary to GITHUB_STEP_SUMMARY when running in CI.
"""

import argparse
import csv
import sys
from collections import defaultdict

# ── ANSI colours ─────────────────────────────────────────────
GREEN = "\033[1;32m"
RED   = "\033[1;31m"
CYAN  = "\033[1;36m"
RESET = "\033[0m"
BOLD  = "\033[1m"

PASS = f"{GREEN}PASS{RESET}"
FAIL = f"{RED}FAIL{RESET}"


def load_rows(jtl_file: str) -> list[dict]:
    with open(jtl_file, newline="") as f:
        return list(csv.DictReader(f))


def compute_metrics(rows: list[dict]) -> dict:
    total   = len(rows)
    errors  = sum(1 for r in rows if r["success"] == "false")
    elapsed = sorted(int(r["elapsed"]) for r in rows)
    ts      = [int(r["timeStamp"]) for r in rows]

    duration_s = (max(ts) - min(ts)) / 1000
    throughput = total / duration_s

    return {
        "total":      total,
        "errors":     errors,
        "elapsed":    elapsed,
        "duration_s": duration_s,
        "throughput": throughput,
        "avg":        int(sum(elapsed) / total),
        "p90":        elapsed[int(total * 0.90)],
        "p95":        elapsed[int(total * 0.95)],
        "p99":        elapsed[int(total * 0.99)],
        "max":        elapsed[-1],
        "error_rate": errors / total * 100,
    }


def compute_violations(rows: list[dict], p90_threshold: int) -> dict:
    by_label = defaultdict(list)
    for r in rows:
        by_label[r["label"]].append(r)

    stats = {}
    for label, label_rows in sorted(by_label.items()):
        n       = len(label_rows)
        slow    = sum(1 for r in label_rows if int(r["elapsed"]) >= p90_threshold)
        failed  = sum(1 for r in label_rows if r["success"] == "false")
        stats[label] = {"n": n, "slow": slow, "failed": failed, "violated": slow + failed}

    return stats


def print_terminal(m: dict, violations: dict, thresholds: dict, title: str) -> None:
    ok_throughput  = m["throughput"]  >= thresholds["throughput"]
    ok_p90         = m["p90"]         <  thresholds["p90"]
    ok_error_rate  = m["error_rate"]  <= thresholds["error_rate"]
    overall_pass   = ok_throughput and ok_p90 and ok_error_rate

    sep_wide = "─" * 64
    sep      = "─" * 56

    print(f"\n{BOLD}{CYAN}{'═' * 64}{RESET}")
    print(f"{BOLD}{CYAN}  {title.upper()} — ACCEPTANCE CRITERIA{RESET}")
    print(f"{BOLD}{CYAN}{'═' * 64}{RESET}")
    # ... (rest of terminal print)

def write_github_summary(path: str, m: dict, violations: dict, thresholds: dict, title: str) -> None:
    ok_throughput = m["throughput"]  >= thresholds["throughput"]
    ok_p90        = m["p90"]         <  thresholds["p90"]
    ok_error_rate = m["error_rate"]  <= thresholds["error_rate"]
    overall_pass  = ok_throughput and ok_p90 and ok_error_rate

    icon          = "✅" if overall_pass  else "❌"
    tput_status   = "✅ PASS" if ok_throughput  else "❌ FAIL"
    p90_status    = "✅ PASS" if ok_p90         else "❌ FAIL"
    err_status    = "✅ PASS" if ok_error_rate  else "❌ FAIL"
    verdict_md    = "All criteria met" if overall_pass else "Criteria not met"

    total_slow     = sum(v["slow"]     for v in violations.values())
    total_violated = sum(v["violated"] for v in violations.values())
    p90_threshold  = thresholds["p90"]

    with open(path, "w") as f:
        f.write(f"## {title} — BlazeDemo {icon}\n\n")
        f.write(f"**{icon} Verdict: {verdict_md}**\n\n")
        # ... (rest of summary)

def main() -> None:
    parser = argparse.ArgumentParser(description="Analyse JMeter JTL results")
    parser.add_argument("--jtl",         required=True,  help="Path to JTL file")
    parser.add_argument("--title",       default="Load Test", help="Test title for reports")
    parser.add_argument("--throughput",  type=float, default=250,  help="Min req/s threshold")
    parser.add_argument("--p90",         type=int,   default=2000, help="Max P90 ms threshold")
    parser.add_argument("--error-rate",  type=float, default=1.0,  help="Max error rate %% threshold")
    parser.add_argument("--summary",     default="",               help="Path to GitHub Step Summary file")
    args = parser.parse_args()

    thresholds = {
        "throughput": args.throughput,
        "p90":        args.p90,
        "error_rate": args.error_rate,
    }

    rows      = load_rows(args.jtl)
    metrics   = compute_metrics(rows)
    violations = compute_violations(rows, args.p90)

    print_terminal(metrics, violations, thresholds, args.title)

    if args.summary:
        write_github_summary(args.summary, metrics, violations, thresholds, args.title)


if __name__ == "__main__":
    main()
