#!/usr/bin/env bash
set -euo pipefail

JMX="scripts/blazedemo-spike-test.jmx"
JTL="results/spike/spike-test-results.jtl"
REPORT="reports/spike"

# Acceptance criteria aligned with project requirements
THRESHOLD_THROUGHPUT=250    # req/s (baseline target)
THRESHOLD_P90=2000          # ms (hard limit)
THRESHOLD_ERROR_RATE=1.0    # % (standard limit)

# Runtime overrides via env vars
EXTRA_ARGS=""
[[ -n "${THREADS:-}"   ]] && EXTRA_ARGS="$EXTRA_ARGS -Jthreads=$THREADS"
[[ -n "${RAMP_UP:-}"   ]] && EXTRA_ARGS="$EXTRA_ARGS -Jramp_up=$RAMP_UP"
[[ -n "${DURATION:-}"  ]] && EXTRA_ARGS="$EXTRA_ARGS -Jduration=$DURATION"

echo "==> Cleaning previous spike results..."
mkdir -p "$(dirname "$JTL")" "$REPORT"
rm -f "$JTL"
rm -rf "$REPORT" && mkdir -p "$REPORT"

echo "==> Running spike test..."
# shellcheck disable=SC2086
jmeter -n \
  -t "$JMX" \
  -q config/jtl-save.properties \
  -q config/load-test.properties \
  -l "$JTL" \
  -e -o "$REPORT" \
  $EXTRA_ARGS

echo ""
echo "==> Analysing spike results..."
python3 scripts/analyze-results.py \
  --title       "Spike Test" \
  --jtl         "$JTL" \
  --throughput  "$THRESHOLD_THROUGHPUT" \
  --p90         "$THRESHOLD_P90" \
  --error-rate  "$THRESHOLD_ERROR_RATE" \
  --summary     "${GITHUB_STEP_SUMMARY:-}"

# Open report — skip in Docker and CI/CD
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
