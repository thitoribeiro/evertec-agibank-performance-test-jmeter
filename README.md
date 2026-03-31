# evertec-agibank-performance-test-jmeter

Performance test automation for BlazeDemo using Apache JMeter.

## Project Structure

```
.
├── Dockerfile
├── .github/
│   └── workflows/
│       └── load-test.yml            # Manual GitHub Actions trigger
├── scripts/
│   ├── blazedemo-load-test.jmx      # Test logic (samplers, assertions, timers)
│   ├── run-load-test.sh             # Local execution + acceptance criteria report
│   └── run-load-test-docker.sh      # Docker execution + opens report on host
├── config/
│   ├── load-test.properties         # Scenario parameters (threads, duration, host…)
│   └── jtl-save.properties          # JTL column configuration for HTML report
├── results/
│   ├── load/                        # Load test raw results (.jtl)
│   └── spike/                       # Spike test raw results (.jtl)
└── reports/
    ├── load/                        # Load test HTML dashboard
    └── spike/                       # Spike test HTML dashboard
```

## Separation of Concerns

| File | Responsibility |
|---|---|
| `scripts/*.jmx` | Test scenario: flow, samplers, assertions, think time |
| `config/load-test.properties` | Runtime parameters: host, threads, timeouts |
| `config/jtl-save.properties` | Output format: JTL columns required for HTML report |

## Acceptance Criteria

| Metric | Target |
|---|---|
| Throughput | ≥ 250 req/s |
| P90 Response Time | < 2000 ms |
| Error Rate | < 1% |

---

## Running Tests

### Local

Requires JMeter 5.6.3+ and Java 17+ installed.

```bash
bash scripts/run-load-test.sh
```

Cleans previous results, executes the test, prints the acceptance criteria verdict and opens the HTML report automatically.

**Override parameters without editing files:**
```bash
THREADS=50 DURATION=60 bash scripts/run-load-test.sh
```

---

### Docker

Requires Docker installed. No JMeter or Java needed locally.

```bash
bash scripts/run-load-test-docker.sh
```

Builds the image, runs the container with results/reports mounted as volumes, and opens the HTML report on the host after the test completes.

**Override parameters:**
```bash
THREADS=50 DURATION=60 bash scripts/run-load-test-docker.sh
```

---

### GitHub Actions (manual)

1. Go to **Actions → Load Test — BlazeDemo → Run workflow**
2. Fill in the optional parameters (threads, ramp_up, duration)
3. Click **Run workflow**

After the run:
- The acceptance criteria verdict appears in the **job summary**
- The HTML report and JTL file are available as **artifacts** (retained 30 days)

---

## Requirements

| Environment | Requirements |
|---|---|
| Local | JMeter 5.6.3+, Java 17+, Python 3 |
| Docker | Docker Engine |
| GitHub Actions | No setup required |
