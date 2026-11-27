# Incident Runbook: Retail Store High Latency / Pod Degradation

| Field | Details |
|---|---|
| **Service** | Group 2 Retail Store (`retail-store` namespace) |
| **Cluster / Region** | `group2-capstone-cluster` (`ap-southeast-1`) |
| **Severity** | SEV-2 (Degraded Performance) / SEV-1 (Complete Outage) |
| **SLO Impacted** | Product Listing p95 Latency ≤ 500ms / Availability ≥ 99.9% |
| **Primary Tools** | Grafana (Prometheus + Loki), CloudWatch, ArgoCD, `kubectl`, AWS DevOps Agent |

---

## 1. Detection

This incident is triggered automatically when any of the following alerts fire and notify the on-call channel (Email / Slack / Telegram) or AWS DevOps Agent:

* **CloudWatch Alarms:**
  * `group2-capstone-alb-p95-latency-high` — ALB `TargetResponseTime` (p95) > 500ms for 2 consecutive minutes.
  * `group2-capstone-retail-store-pod-cpu-high` — Average pod CPU in `retail-store` > 80% for 2 minutes.
  * `group2-capstone-retail-store-pod-restarts` — Container restarts > 0 in `retail-store` within 5 minutes.
  * `group2-capstone-retail-store-running-pods-low` — Running pods in `retail-store` < 1.
* **Grafana / Prometheus Alerts:** High HTTP 5xx error rate or elevated p95 latency on the Capstone Dashboard.

---

## 2. Diagnosis Steps

Follow these steps in order to isolate whether the issue is at the **Application/Pod**, **Autoscaling/Node**, or **Database** layer.

### Step 2.1: Check Overall Health on Dashboards (1–2 mins)
1. Open **Grafana → Capstone Dashboard** to verify:
   * Current request rate, HTTP 5xx error rate, and p95 latency.
   * Whether the spike correlates with a traffic surge (e.g., 11:11 sale / load test) or a recent deployment.
2. Check **Loki Logs** (in Grafana) or **CloudWatch Logs** (`/aws/containerinsights/group2-capstone-cluster/application`) filtered by `namespace_name="retail-store"` for `ERROR`, `OOMKilled`, or database timeout exceptions.

### Step 2.2: Inspect Pods, Events, and Autoscaling (2–3 mins)
```bash
# 1. Check pod status, restarts, and resource usage
kubectl get pods -n retail-store -o wide
kubectl top pods -n retail-store

# 2. Check HPA scaling status (is it maxed out or unable to scale?)
kubectl get hpa -n retail-store

# 3. Check recent warning events (OOMKilled, FailedScheduling, Unhealthy probes)
kubectl get events -n retail-store --sort-by='.lastTimestamp' | tail -n 20