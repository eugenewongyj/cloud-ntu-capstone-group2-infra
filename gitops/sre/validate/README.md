# Capstone SRE — k6 Load Testing

## Architecture

k6 generates HTTP traffic against the approved Capstone retail application.
The existing Prometheus stack can receive k6 metrics through Remote Write when explicitly enabled and correctly configured. Successful ingestion must be verified.
The existing Grafana dashboard visualizes application performance.

## Scripts

- `k6/product-listing.js` — product-listing scenario and thresholds.
- `k6/run.sh` — test runner with optional Prometheus Remote Write.
- `k6/results/` — local test evidence; do not commit.

## Load Profiles

| Profile | Description |
|---|---|
| smoke | 1 virtual user, approximately 40 seconds |
| baseline | Configurable baseline, approximately 5 minutes |
| flash-demo | Baseline, 10x, 20x, recovery; approximately 10 minutes |

BASE_USERS defaults to 1 and must be between 1 and 10.
Virtual-user multipliers do not guarantee equivalent RPS multipliers.

## Configuration

- TARGET_HOST: approved staging application URL.
- CAPSTONE_PRODUCT_PATH: verified product-listing route.
- LOAD_PROFILE: smoke, baseline or flash-demo.
- BASE_USERS: baseline virtual users.
- CAPSTONE_LOAD_APPROVED=YES: required for flash-demo.
- CAPSTONE_K6_REMOTE_WRITE=YES: enable Prometheus export.
- K6_PROMETHEUS_RW_SERVER_URL: authorized remote-write endpoint.
- K6_PROMETHEUS_RW_TREND_STATS: runner exports p(95) when remote write is enabled.

## Execution

From this directory, after verifying the target and obtaining approval:

    export TARGET_HOST=https://YOUR-APPROVED-STAGING-HOST
    export CAPSTONE_PRODUCT_PATH=/YOUR-VERIFIED-PATH
    LOAD_PROFILE=smoke BASE_USERS=1 ./k6/run.sh

For an approved flash-sale demonstration:

    CAPSTONE_LOAD_APPROVED=YES LOAD_PROFILE=flash-demo BASE_USERS=1 ./k6/run.sh

## Monitoring and Evidence

- Actual requests per second and achieved load multiplier.
- Product-listing p95 latency below 500 milliseconds.
- HTTP failure rate below 1 percent.
- Baseline, peak and recovery measurements.
- HPA desired/current replicas when HPA is enabled.
- Pod readiness, node capacity, CPU and memory.
- Timestamped evidence of recovery after peak load.

Verify exported Prometheus metric names before adding Grafana queries.
Configuration validation alone does not prove successful metrics ingestion.

## Safety

Run only against approved staging endpoints with teammate authorization.
Start with one virtual user. Use synthetic data.
Stop immediately if unexpected errors, instability or cost increases occur.
Do not commit credentials, sensitive data or generated test results.
