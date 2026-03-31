#!/usr/bin/env bash
set -euo pipefail

IMAGE="blazedemo-perf-test"
REPORT_DIR="$(pwd)/reports/load"

echo "==> Building Docker image..."
docker build -t "$IMAGE" .

echo "==> Running test in container..."
docker run --rm \
  -e IN_DOCKER=true \
  -e THREADS="${THREADS:-}" \
  -e RAMP_UP="${RAMP_UP:-}" \
  -e DURATION="${DURATION:-}" \
  -v "$(pwd)/results:/test/results" \
  -v "$(pwd)/reports:/test/reports" \
  "$IMAGE"

echo "==> Opening report..."
if command -v open &>/dev/null; then
  open "$REPORT_DIR/index.html"
elif command -v xdg-open &>/dev/null; then
  xdg-open "$REPORT_DIR/index.html"
else
  echo "Report at: $REPORT_DIR/index.html"
fi
