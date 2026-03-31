#!/usr/bin/env bash
set -euo pipefail

JMX="scripts/blazedemo-load-test.jmx"
JTL="results/load/load-test-results.jtl"
REPORT="reports/load"

# Acceptance criteria
THRESHOLD_THROUGHPUT=250   # req/s
THRESHOLD_P90=2000         # ms
THRESHOLD_ERROR_RATE=1.0   # %

# Runtime overrides via env vars (used by Docker and CI/CD)
EXTRA_ARGS=""
[[ -n "${THREADS:-}"   ]] && EXTRA_ARGS="$EXTRA_ARGS -Jthreads=$THREADS"
[[ -n "${RAMP_UP:-}"   ]] && EXTRA_ARGS="$EXTRA_ARGS -Jramp_up=$RAMP_UP"
[[ -n "${DURATION:-}"  ]] && EXTRA_ARGS="$EXTRA_ARGS -Jduration=$DURATION"

echo "==> Cleaning previous results..."
mkdir -p "$(dirname "$JTL")" "$REPORT"
rm -f "$JTL"
rm -rf "$REPORT" && mkdir -p "$REPORT"

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
python3 scripts/analyze-results.py \
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
