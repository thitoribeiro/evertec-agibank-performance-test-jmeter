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


def print_terminal(m: dict, violations: dict, thresholds: dict) -> None:
    ok_throughput  = m["throughput"]  >= thresholds["throughput"]
    ok_p90         = m["p90"]         <  thresholds["p90"]
    ok_error_rate  = m["error_rate"]  <= thresholds["error_rate"]
    overall_pass   = ok_throughput and ok_p90 and ok_error_rate

    sep_wide = "─" * 64
    sep      = "─" * 56

    print(f"\n{BOLD}{CYAN}{'═' * 64}{RESET}")
    print(f"{BOLD}{CYAN}  LOAD TEST — ACCEPTANCE CRITERIA{RESET}")
    print(f"{BOLD}{CYAN}{'═' * 64}{RESET}")

    print(f"\n  {'Criterion':<30} {'Required':>12}  {'Result':>12}  Status")
    print(f"  {sep_wide}")
    print(f"  {'Throughput':<30} {thresholds['throughput']:>10.0f} r/s  {m['throughput']:>10.1f} r/s  {PASS if ok_throughput else FAIL}")
    print(f"  {'P90 Response Time':<30} {'< '+str(thresholds['p90'])+' ms':>12}  {str(m['p90'])+' ms':>12}  {PASS if ok_p90 else FAIL}")
    print(f"  {'Error Rate':<30} {'≤ '+str(thresholds['error_rate'])+'%':>12}  {m['error_rate']:>10.2f}%  {PASS if ok_error_rate else FAIL}")
    print(f"  {sep_wide}")

    verdict = (f"{GREEN}█████  ALL CRITERIA MET  █████{RESET}"
               if overall_pass else
               f"{RED}█████  CRITERIA NOT MET  █████{RESET}")
    print(f"\n  {verdict}")

    print(f"\n{BOLD}{CYAN}  METRICS SUMMARY{RESET}")
    print(f"  {sep}")
    print(f"  {'Total Samples':<28} {m['total']:>10,}")
    print(f"  {'Duration':<28} {m['duration_s']:>9.0f}s")
    print(f"  {'Throughput':<28} {m['throughput']:>9.1f} req/s")
    print(f"  {'Error Rate':<28} {m['error_rate']:>9.2f}% ({m['errors']}/{m['total']})")
    print(f"  {'Avg Response Time':<28} {m['avg']:>9} ms")
    print(f"  {'P90 Response Time':<28} {m['p90']:>9} ms")
    print(f"  {'P95 Response Time':<28} {m['p95']:>9} ms")
    print(f"  {'P99 Response Time':<28} {m['p99']:>9} ms")
    print(f"  {'Max Response Time':<28} {m['max']:>9} ms")

    total_slow     = sum(v["slow"]     for v in violations.values())
    total_violated = sum(v["violated"] for v in violations.values())
    p90_threshold  = thresholds["p90"]

    print(f"\n{BOLD}{CYAN}  VIOLATIONS PER TRANSACTION  (threshold: {p90_threshold} ms){RESET}")
    print(f"  {sep_wide}")
    print(f"  {'Transaction':<30} {'Total':>6}  {'Slow (≥{} ms)'.format(p90_threshold):>14}  {'Errors':>6}  {'Violated':>9}  {'% Violated':>10}")
    print(f"  {sep_wide}")

    for label, s in violations.items():
        pct      = s["violated"] / s["n"] * 100
        slow_s   = f"{RED}{s['slow']:>5}{RESET}"     if s["slow"]     > 0 else f"{s['slow']:>5}"
        fail_s   = f"{RED}{s['failed']:>5}{RESET}"   if s["failed"]   > 0 else f"{s['failed']:>5}"
        viol_s   = f"{RED}{s['violated']:>8}{RESET}" if s["violated"] > 0 else f"{s['violated']:>8}"
        pct_s    = f"{RED}{pct:>9.1f}%{RESET}"       if pct           > 0 else f"{pct:>9.1f}%"
        print(f"  {label:<30} {s['n']:>6}  {slow_s:>14}  {fail_s:>6}  {viol_s:>9}  {pct_s:>10}")

    print(f"  {sep_wide}")
    total_pct = total_violated / m["total"] * 100
    ts_s  = f"{RED}{total_slow:>5}{RESET}"      if total_slow     > 0 else f"{total_slow:>5}"
    te_s  = f"{RED}{m['errors']:>5}{RESET}"     if m["errors"]    > 0 else f"{m['errors']:>5}"
    tv_s  = f"{RED}{total_violated:>8}{RESET}"  if total_violated > 0 else f"{total_violated:>8}"
    tp_s  = f"{RED}{total_pct:>9.1f}%{RESET}"   if total_pct      > 0 else f"{total_pct:>9.1f}%"
    print(f"  {BOLD}{'TOTAL':<30} {m['total']:>6}  {ts_s:>14}  {te_s:>6}  {tv_s:>9}  {tp_s:>10}{RESET}")
    print(f"{BOLD}{CYAN}{'═' * 64}{RESET}\n")


def write_github_summary(path: str, m: dict, violations: dict, thresholds: dict) -> None:
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
        f.write(f"## Load Test — BlazeDemo {icon}\n\n")
        f.write(f"**{icon} Verdict: {verdict_md}**\n\n")

        f.write("### Acceptance Criteria\n\n")
        f.write("| Criterion | Required | Result | Status |\n")
        f.write("|---|---|---|---|\n")
        f.write(f"| Throughput | ≥ {thresholds['throughput']:.0f} req/s | {m['throughput']:.1f} req/s | {tput_status} |\n")
        f.write(f"| P90 Response Time | < {thresholds['p90']} ms | {m['p90']} ms | {p90_status} |\n")
        f.write(f"| Error Rate | ≤ {thresholds['error_rate']}% | {m['error_rate']:.2f}% | {err_status} |\n\n")

        f.write("### Metrics Summary\n\n")
        f.write("| Metric | Value |\n|---|---|\n")
        f.write(f"| Total Samples | {m['total']:,} |\n")
        f.write(f"| Duration | {m['duration_s']:.0f}s |\n")
        f.write(f"| Throughput | {m['throughput']:.1f} req/s |\n")
        f.write(f"| Error Rate | {m['error_rate']:.2f}% ({m['errors']}/{m['total']}) |\n")
        f.write(f"| Avg Response Time | {m['avg']} ms |\n")
        f.write(f"| P90 Response Time | {m['p90']} ms |\n")
        f.write(f"| P95 Response Time | {m['p95']} ms |\n")
        f.write(f"| P99 Response Time | {m['p99']} ms |\n")
        f.write(f"| Max Response Time | {m['max']} ms |\n\n")

        f.write(f"### Violations per Transaction *(threshold: {p90_threshold} ms)*\n\n")
        f.write("| Transaction | Total | Slow (≥{} ms) | Errors | Violated | % Violated |\n".format(p90_threshold))
        f.write("|---|---:|---:|---:|---:|---:|\n")
        for label, s in violations.items():
            pct      = s["violated"] / s["n"] * 100
            slow_md  = f"⚠️ {s['slow']}"    if s["slow"]     > 0 else str(s["slow"])
            fail_md  = f"🔴 {s['failed']}"  if s["failed"]   > 0 else str(s["failed"])
            viol_md  = f"**{s['violated']}**" if s["violated"] > 0 else str(s["violated"])
            pct_md   = f"**{pct:.1f}%**"      if pct           > 0 else f"{pct:.1f}%"
            f.write(f"| {label} | {s['n']:,} | {slow_md} | {fail_md} | {viol_md} | {pct_md} |\n")
        total_pct = total_violated / m["total"] * 100
        f.write(f"| **TOTAL** | **{m['total']:,}** | **{total_slow}** | **{m['errors']}** | **{total_violated}** | **{total_pct:.1f}%** |\n")


def main() -> None:
    parser = argparse.ArgumentParser(description="Analyse JMeter JTL results")
    parser.add_argument("--jtl",         required=True,  help="Path to JTL file")
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

    print_terminal(metrics, violations, thresholds)

    if args.summary:
        write_github_summary(args.summary, metrics, violations, thresholds)


if __name__ == "__main__":
    main()
