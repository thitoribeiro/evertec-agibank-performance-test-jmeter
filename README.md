# evertec-agibank-performance-test-jmeter

Performance test automation for BlazeDemo using Apache JMeter.

## Project Structure

```
.
├── scripts/        # JMeter test plans (.jmx)
├── results/
│   ├── load/       # Load test results (.jtl)
│   └── spike/      # Spike test results (.jtl)
├── reports/
│   ├── load/       # Load test HTML reports
│   └── spike/      # Spike test HTML reports
└── config/         # Configuration files and variables
```

## Requirements

- Apache JMeter 5.x+
- Java 11+

## Running Tests

### Load Test

```bash
jmeter -n -t scripts/<test-plan>.jmx \
  -l results/load/results.jtl \
  -e -o reports/load/
```

### Spike Test

```bash
jmeter -n -t scripts/<test-plan>.jmx \
  -l results/spike/results.jtl \
  -e -o reports/spike/
```
