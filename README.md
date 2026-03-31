# evertec-agibank-performance-test-jmeter

Performance test automation for BlazeDemo using Apache JMeter 5.6.3.

## Project Structure

```
.
├── Dockerfile
├── .github/
│   └── workflows/
│       ├── load-test.yml            # Load test GitHub Actions trigger
│       └── spike-test.yml           # Spike test GitHub Actions trigger
├── scripts/
│   ├── blazedemo-load-test.jmx      # Load test logic (250 threads target)
│   ├── blazedemo-spike-test.jmx     # Spike test logic (multi-phase peaks)
│   ├── run-load-test.sh             # Load test local execution
│   ├── run-spike-test.sh            # Spike test local execution
│   ├── run-load-test-docker.sh      # Load test via Docker
│   └── run-spike-test-docker.sh     # Spike test via Docker
├── config/
│   ├── load-test.properties         # Scenario parameters (host, protocol…)
│   └── jtl-save.properties          # JTL column configuration
├── results/
│   ├── load/                        # Load test raw results (.jtl)
│   └── spike/                       # Spike test raw results (.jtl)
└── reports/
    ├── load/                        # Load test HTML dashboard
    └── spike/                       # Spike test HTML dashboard
```

## Acceptance Criteria

Targets for both Load and Spike scenarios (baseline/peaks):

| Metric | Target |
|---|---|
| Throughput | ≥ 250 req/s |
| P90 Response Time | < 2000 ms |
| Error Rate | < 1% |

---

## Running Tests

### Local Execution (JMeter 5.6.3+ / Java 17+ / Python 3)

**Load Test:**
```bash
bash scripts/run-load-test.sh
```

**Spike Test:**
```bash
bash scripts/run-spike-test.sh
```

*Note: You can override parameters via environment variables:*
`THREADS=100 DURATION=60 bash scripts/run-load-test.sh`

---

### Docker Execution (Docker Engine)

No JMeter or Java required locally. Reports are opened automatically on the host.

**Load Test:**
```bash
bash scripts/run-load-test-docker.sh
```

**Spike Test:**
```bash
bash scripts/run-spike-test-docker.sh
```

---

### GitHub Actions (Manual Trigger)

1. Go to **Actions** tab in GitHub.
2. Select either **Load Test — BlazeDemo** or **Spike Test — BlazeDemo**.
3. Click **Run workflow**, fill optional parameters, and click the green button.

**Outputs:**
- Acceptance criteria verdict in **Job Summary**.
- Full HTML Report and JTL file as **Artifacts** (30-day retention).

---

## Technical Details

- **Sequential Execution**: Spike tests use multiple Thread Groups executed in order (Baseline → Spike 1 → Recov 1 → Spike 2 → Recov 2 → Max Spike → Final Recov).
- **Inlined Flow**: Both tests share the same HTTP flow (Home → Select → Purchase → Confirm) for consistency.
- **Reporting**: Acceptance criteria are automatically analyzed by `scripts/analyze-results.py` after each run.
