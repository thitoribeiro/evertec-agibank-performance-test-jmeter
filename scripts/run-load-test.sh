#!/usr/bin/env bash
set -euo pipefail

JMX="scripts/blazedemo-load-test.jmx"
JTL="results/load/load-test-results.jtl"
REPORT="reports/load"

# Acceptance criteria
THRESHOLD_THROUGHPUT=250   # req/s
THRESHOLD_P90=2000         # ms

# Runtime overrides via env vars (used by Docker and CI/CD)
EXTRA_ARGS=""
[[ -n "${THREADS:-}"  ]] && EXTRA_ARGS="$EXTRA_ARGS -Jthreads=$THREADS"
[[ -n "${RAMP_UP:-}"  ]] && EXTRA_ARGS="$EXTRA_ARGS -Jramp_up=$RAMP_UP"
[[ -n "${DURATION:-}" ]] && EXTRA_ARGS="$EXTRA_ARGS -Jduration=$DURATION"

echo "==> Cleaning previous results..."
rm -f "$JTL"
rm -rf "$REPORT" && mkdir -p "$REPORT"
mkdir -p "$(dirname "$JTL")"

echo "==> Running load test..."
# shellcheck disable=SC2086
jmeter -n \
  -t "$JMX" \
  -q config/jtl-save.properties \
  -q config/load-test.properties \
  -l "$JTL" \
  -e -o "$REPORT" \
  $EXTRA_ARGS

echo ""
echo "==> Analysing results..."
python3 - "$JTL" "$THRESHOLD_THROUGHPUT" "$THRESHOLD_P90" "${GITHUB_STEP_SUMMARY:-}" <<'PYEOF'
import csv, sys

jtl_file       = sys.argv[1]
req_throughput = float(sys.argv[2])
req_p90        = int(sys.argv[3])
summary_file   = sys.argv[4] if len(sys.argv) > 4 else ""

GREEN  = "\033[1;32m"
RED    = "\033[1;31m"
CYAN   = "\033[1;36m"
RESET  = "\033[0m"
BOLD   = "\033[1m"

PASS = f"{GREEN}PASS{RESET}"
FAIL = f"{RED}FAIL{RESET}"

from collections import defaultdict

with open(jtl_file) as f:
    rows = list(csv.DictReader(f))

total   = len(rows)
errors  = sum(1 for r in rows if r["success"] == "false")
elapsed = sorted(int(r["elapsed"]) for r in rows)

ts         = [int(r["timeStamp"]) for r in rows]
duration_s = (max(ts) - min(ts)) / 1000
throughput = total / duration_s

p90 = elapsed[int(total * 0.90)]
p95 = elapsed[int(total * 0.95)]
p99 = elapsed[int(total * 0.99)]
avg = int(sum(elapsed) / total)

ok_throughput = throughput >= req_throughput
ok_p90        = p90 < req_p90
overall_pass  = ok_throughput and ok_p90

# ── Per-label violation breakdown ───────────────────────────
by_label = defaultdict(list)
for r in rows:
    by_label[r["label"]].append(r)

label_stats = {}
for label, label_rows in sorted(by_label.items()):
    n        = len(label_rows)
    slow     = sum(1 for r in label_rows if int(r["elapsed"]) >= req_p90)
    failed   = sum(1 for r in label_rows if r["success"] == "false")
    violated = slow + failed
    label_stats[label] = {"n": n, "slow": slow, "failed": failed, "violated": violated}

total_slow     = sum(v["slow"]     for v in label_stats.values())
total_violated = sum(v["violated"] for v in label_stats.values())

sep  = "─" * 64
sep2 = "─" * 56

# ── Terminal output ──────────────────────────────────────────
print(f"\n{BOLD}{CYAN}{'═' * 64}{RESET}")
print(f"{BOLD}{CYAN}  LOAD TEST — ACCEPTANCE CRITERIA{RESET}")
print(f"{BOLD}{CYAN}{'═' * 64}{RESET}")
print(f"\n  {'Criterion':<30} {'Required':>12}  {'Result':>12}  Status")
print(f"  {sep}")
print(f"  {'Throughput':<30} {req_throughput:>10.0f} r/s  {throughput:>10.1f} r/s  {PASS if ok_throughput else FAIL}")
print(f"  {'P90 Response Time':<30} {'< '+str(req_p90)+' ms':>12}  {str(p90)+' ms':>12}  {PASS if ok_p90 else FAIL}")
print(f"  {sep}")

verdict_term = (f"{GREEN}█████  ALL CRITERIA MET  █████{RESET}"
                if overall_pass else
                f"{RED}█████  CRITERIA NOT MET  █████{RESET}")
print(f"\n  {verdict_term}")

print(f"\n{BOLD}{CYAN}  METRICS SUMMARY{RESET}")
print(f"  {sep2}")
print(f"  {'Total Samples':<28} {total:>10,}")
print(f"  {'Duration':<28} {duration_s:>9.0f}s")
print(f"  {'Throughput':<28} {throughput:>9.1f} req/s")
print(f"  {'Error Rate':<28} {errors/total*100:>9.2f}% ({errors}/{total})")
print(f"  {'Avg Response Time':<28} {avg:>9} ms")
print(f"  {'P90 Response Time':<28} {p90:>9} ms")
print(f"  {'P95 Response Time':<28} {p95:>9} ms")
print(f"  {'P99 Response Time':<28} {p99:>9} ms")
print(f"  {'Max Response Time':<28} {elapsed[-1]:>9} ms")

# ── Violations per transaction ───────────────────────────────
print(f"\n{BOLD}{CYAN}  VIOLATIONS PER TRANSACTION  (threshold: {req_p90} ms){RESET}")
print(f"  {sep}")
print(f"  {'Transaction':<30} {'Total':>6}  {'Slow (≥{} ms)'.format(req_p90):>14}  {'Errors':>6}  {'Violated':>9}  {'% Violated':>10}")
print(f"  {sep}")
for label, s in label_stats.items():
    pct      = s["violated"] / s["n"] * 100
    slow_str = f"{RED}{s['slow']:>5}{RESET}"   if s["slow"]     > 0 else f"{s['slow']:>5}"
    fail_str = f"{RED}{s['failed']:>5}{RESET}" if s["failed"]   > 0 else f"{s['failed']:>5}"
    viol_str = f"{RED}{s['violated']:>8}{RESET}" if s["violated"] > 0 else f"{s['violated']:>8}"
    pct_str  = f"{RED}{pct:>9.1f}%{RESET}"    if pct           > 0 else f"{pct:>9.1f}%"
    print(f"  {label:<30} {s['n']:>6}  {slow_str:>14}  {fail_str:>6}  {viol_str:>9}  {pct_str:>10}")
print(f"  {sep}")
total_pct    = total_violated / total * 100
total_slow_s = f"{RED}{total_slow:>5}{RESET}"     if total_slow     > 0 else f"{total_slow:>5}"
total_err_s  = f"{RED}{errors:>5}{RESET}"         if errors         > 0 else f"{errors:>5}"
total_viol_s = f"{RED}{total_violated:>8}{RESET}" if total_violated > 0 else f"{total_violated:>8}"
total_pct_s  = f"{RED}{total_pct:>9.1f}%{RESET}"  if total_pct      > 0 else f"{total_pct:>9.1f}%"
print(f"  {BOLD}{'TOTAL':<30} {total:>6}  {total_slow_s:>14}  {total_err_s:>6}  {total_viol_s:>9}  {total_pct_s:>10}{RESET}")
print(f"{BOLD}{CYAN}{'═' * 64}{RESET}\n")

# ── GitHub Step Summary (markdown) ───────────────────────────
if summary_file:
    verdict_md  = "✅ All criteria met" if overall_pass else "❌ Criteria not met"
    tput_status = "✅ PASS" if ok_throughput else "❌ FAIL"
    p90_status  = "✅ PASS" if ok_p90        else "❌ FAIL"

    with open(summary_file, "w") as f:
        f.write(f"## Load Test — BlazeDemo {'✅' if overall_pass else '❌'}\n\n")
        f.write(f"**Verdict: {verdict_md}**\n\n")

        f.write("### Acceptance Criteria\n\n")
        f.write("| Criterion | Required | Result | Status |\n")
        f.write("|---|---|---|---|\n")
        f.write(f"| Throughput | ≥ {req_throughput:.0f} req/s | {throughput:.1f} req/s | {tput_status} |\n")
        f.write(f"| P90 Response Time | < {req_p90} ms | {p90} ms | {p90_status} |\n\n")

        f.write("### Metrics Summary\n\n")
        f.write("| Metric | Value |\n")
        f.write("|---|---|\n")
        f.write(f"| Total Samples | {total:,} |\n")
        f.write(f"| Duration | {duration_s:.0f}s |\n")
        f.write(f"| Throughput | {throughput:.1f} req/s |\n")
        f.write(f"| Error Rate | {errors/total*100:.2f}% ({errors}/{total}) |\n")
        f.write(f"| Avg Response Time | {avg} ms |\n")
        f.write(f"| P90 Response Time | {p90} ms |\n")
        f.write(f"| P95 Response Time | {p95} ms |\n")
        f.write(f"| P99 Response Time | {p99} ms |\n")
        f.write(f"| Max Response Time | {elapsed[-1]} ms |\n\n")

        f.write(f"### Violations per Transaction  *(threshold: {req_p90} ms)*\n\n")
        f.write("| Transaction | Total | Slow (≥{} ms) | Errors | Violated | % Violated |\n".format(req_p90))
        f.write("|---|---:|---:|---:|---:|---:|\n")
        for label, s in label_stats.items():
            pct = s["violated"] / s["n"] * 100
            slow_md = f"⚠️ {s['slow']}"   if s["slow"]     > 0 else str(s["slow"])
            fail_md = f"🔴 {s['failed']}" if s["failed"]   > 0 else str(s["failed"])
            viol_md = f"**{s['violated']}**" if s["violated"] > 0 else str(s["violated"])
            pct_md  = f"**{pct:.1f}%**"      if pct           > 0 else f"{pct:.1f}%"
            f.write(f"| {label} | {s['n']:,} | {slow_md} | {fail_md} | {viol_md} | {pct_md} |\n")
        total_pct = total_violated / total * 100
        f.write(f"| **TOTAL** | **{total:,}** | **{total_slow}** | **{errors}** | **{total_violated}** | **{total_pct:.1f}%** |\n")

# Exit 0 always — acceptance criteria are informational only.
# The workflow fails only if JMeter itself fails (set -euo pipefail above).
sys.exit(0)
PYEOF

# ── Open report — skip in Docker and CI/CD ───────────────────
if [[ "${IN_DOCKER:-false}" != "true" && "${CI:-false}" != "true" ]]; then
  echo "==> Opening report..."
  if command -v open &>/dev/null; then
    open "$REPORT/index.html"
  elif command -v xdg-open &>/dev/null; then
    xdg-open "$REPORT/index.html"
  else
    echo "Report at: $REPORT/index.html"
  fi
fi
