# Capstone SRE — Load Generator and Load Tests

A **read-only HTTP GET** product-listing load generator using Locust. This is a standalone package: it does not alter Terraform, Kubernetes, GitHub repositories or AWS resources. Running it **does generate traffic** and may incur cloud cost or affect availability. Use only on an approved staging/test target, with teammate permission and a rollback/stop plan.

## Prerequisites

Python 3.10+, network access to your approved environment, and a **verified** product-listing endpoint. The actual Capstone route is **not confirmed** by the supplied infrastructure inventory; do not assume `/products` is correct.

```bash
cd capstone-load-testing
python3 -m venv .venv
source .venv/bin/activate
pip install -r requirements.txt
```

## Configuration

| Variable | Required | Meaning |
|---|---|---|
| `TARGET_HOST` | Yes | Approved base URL, e.g. `https://staging.example.com` |
| `CAPSTONE_PRODUCT_PATH` | Yes | Verified product listing path, e.g. `/catalogue` |
| `LOAD_PROFILE` | No | `baseline` (default), `flash-demo`, `flash-2h` |
| `BASE_USERS` | No | Baseline concurrent simulated users (default 5) |
| `SPAWN_RATE` | No | Maximum new users started per second (default 2) |
| `CAPSTONE_EXPECT_TEXT` | No | Optional text marker that successful responses must contain |
| `OUTPUT_DIR` | No | CSV output prefix |

**Important:** Concurrent users are **not** the same as requests per second. The 10× and 20× stages multiply simulated users; validate achieved RPS using Locust results and Prometheus. Tune the baseline and spawn rate for the approved test environment. The 500 ms SLO is a *measurement requirement*, not a guarantee.

## Tests

### Baseline (5 minutes)

```bash
export TARGET_HOST='https://YOUR-APPROVED-STAGING-HOST'
export CAPSTONE_PRODUCT_PATH='/YOUR-VERIFIED-PRODUCT-LISTING-PATH'
LOAD_PROFILE=baseline BASE_USERS=5 ./run.sh
```

### Flash-sale demonstration (10 minutes)

```bash
LOAD_PROFILE=flash-demo BASE_USERS=5 SPAWN_RATE=10 ./run.sh
```

Stages: 0–2m = 1×, 2–5m = 10×, 5–8m = 20×, 8–10m = recovery at 1×. This is a short classroom demonstration, not a full 2-hour endurance test.

### Extended flash-sale simulation (130 minutes)

```bash
LOAD_PROFILE=flash-2h BASE_USERS=5 SPAWN_RATE=10 ./run.sh
```

Stages: 5m baseline + 60m at 10× + 60m at 20× + 5m recovery. Peak elevated load lasts 120 minutes. Obtain explicit approval before this test; it can be expensive or disruptive.

## What to collect

`run.sh` writes Locust CSV statistics, failures, exception data (when present), time-series history, and an HTML report under `results/` (the folder is gitignored). Locust's `product_listing` label lets you identify the measured endpoint.

For every stage record:

1. Actual achieved requests/s, not merely target user count.
2. Product-listing p95 response time in **milliseconds**, with success/error rate and sample count.
3. Desired/current/available replicas; HPA status if configured.
4. Pending/Ready Pods and EKS Auto Mode node count/capacity.
5. CPU/memory and downstream dependency errors.
6. Timestamped baseline/peak cost assumptions or measured resource usage.

**SLO interpretation:** the assignment requires product-listing p95 ≤ 500 ms *during the load test*. Evaluate p95 across appropriate stage windows, not only a whole-test aggregate. Record the chosen time windows, sample counts and whether the actual RPS achieved the intended multiplier. A non-2xx response is recorded as a Locust failure; distinguish HTTP error rate from latency percentile. An error-free but slow endpoint can still violate the latency SLO.

## Grafana / Prometheus alignment

Locust CSV files are evidence artifacts, not Prometheus time series. For a live dashboard, scrape application HTTP metrics (request rate, latency histogram, errors) and Kubernetes metrics, then align with the Locust time window. If the application lacks HTTP histograms, use Locust reports as the authoritative test-client latency measurement while instrumenting the app. Do not invent PromQL metric names until the actual exporters are confirmed.

Recommended panels: RPS; p95 product-listing latency with 500 ms threshold; error ratio; HPA desired/current replicas; Deployment available replicas; Pending Pods; node count; CPU/memory; downstream errors.

## Logical verification

- **Claim:** 10×/20× load was generated. **Proof:** achieved request-rate history versus baseline (not user count alone).
- **Claim:** application automatically scaled. **Proof:** timestamped replica changes and autoscaling configuration; distinguish Pod scaling from node scaling.
- **Claim:** EKS Auto Mode added capacity. **Proof:** observed node capacity/count changes, when needed; a scale test that fits existing nodes does not prove node scale-out.
- **Claim:** p95 stayed ≤ 500 ms. **Proof:** stage-specific measured product-listing latency, request samples and errors.
- **Claim:** system recovered. **Proof:** post-peak latency/errors and replica/node scale-down where configured, with observation window.

## Safety

- Never target a real production system without explicit authorization.
- Begin with `BASE_USERS=1` for endpoint validation and confirm 2xx responses before increasing load.
- Use synthetic data; do not put credentials, tokens or sensitive response data in the repository.
- Stop immediately with Ctrl+C if unexpected errors, resource exhaustion, cost spikes or service impact occur.
- Keep tests within a documented test window; confirm the load generator can reach the endpoint before beginning.
