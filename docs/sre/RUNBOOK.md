# Incident Runbook: Retail Store High Latency / Pod Degradation

| Field | Details |
|---|---|
| **Service** | Group 2 Retail Store (`retail-store` namespace) |
| **Cluster / Region** | `group2-capstone-cluster` (`ap-southeast-1`) |
| **Severity** | SEV-2 (Degraded Performance) / SEV-1 (Complete Outage) |
| **SLO Impacted** | Product Listing p95 Latency $\le 500\text{ ms}$ / Availability $\ge 99.9\%$ |
| **Alert Channels** | AWS SNS (`group2-capstone-alerts`) $\rightarrow$ Team Email & Discord Webhook |
| **Primary Tools** | Grafana (Prometheus + Loki), CloudWatch (`group2-capstone-overview`), ArgoCD, `kubectl`, AWS DevOps Agent |

---

## 1. Detection

This incident is triggered automatically when any of the following alerts fire and notify the on-call team via **Email**, **Discord**, or **AWS DevOps Agent**:

- **CloudWatch Alarms (Application & SLOs):**
  - `group2-capstone-alb-p95-latency-high` — ALB `TargetResponseTime` (p95) $> 500\text{ ms}$ for 2 consecutive minutes.
  - `group2-capstone-retail-store-pod-cpu-high` — Average pod CPU in `retail-store` $> 80\%$ for 2 minutes.
  - `group2-capstone-retail-store-pod-restarts` — Container restarts $> 0$ in `retail-store` within 5 minutes.
  - `group2-capstone-retail-store-running-pods-low` — Running pods in `retail-store` $< 1$.
  - `group2-capstone-retail-store-log-errors-high` — $> 5$ `ERROR` / `Exception` log entries in `retail-store` within 5 minutes.
- **CloudWatch Alarms (Infrastructure & Backends):**
  - `group2-capstone-eks-node-cpu-high` / `group2-capstone-eks-node-memory-high` — EKS cluster node CPU $> 80\%$ or memory $> 85\%$.
  - `group2-capstone-aurora-mysql-cpu-high` / `group2-capstone-aurora-pg-cpu-high` — Aurora CPU $> 80\%$.
  - `group2-capstone-dynamodb-carts-throttles` — DynamoDB `ThrottledRequests` $> 0$.
  - `group2-capstone-sqs-orders-backlog` — SQS `ApproximateNumberOfMessagesVisible` $> 100$.
- **Grafana / Prometheus Alerts:** High HTTP 5xx error rate or elevated p95 latency on the Capstone Dashboard.

---

## 2. Diagnosis Steps

Follow these steps in order to isolate whether the issue is at the **Application/Pod**, **Autoscaling/Node**, or **Database** layer.

### Step 2.1: Check Overall Health on Dashboards & Logs (1–2 mins)
1. Open **Grafana → Capstone Dashboard** and **CloudWatch → `group2-capstone-overview`** to verify:
  - Current request rate, HTTP 5xx error rate, and p95 latency.
  - Whether the spike correlates with a traffic surge (e.g., 11:11 sale / load test) or a recent deployment.
2. Check **Loki Logs** (in Grafana) or **CloudWatch Logs Insights** (`/aws/containerinsights/group2-capstone-cluster/application`, 14-day retention) filtered by `namespace_name="retail-store"` for `ERROR`, `OOMKilled`, or database timeout exceptions:
  ```text
  fields @timestamp, kubernetes.pod_name, log
  | filter kubernetes.namespace_name = "retail-store"
  | filter log like /ERROR|Exception|OOMKilled/
  | sort @timestamp desc
  | limit 25
  ```

### Step 2.2: Inspect Pods, Events, and Autoscaling (2–3 mins)
```bash
# 1. Check pod status, restarts, and resource usage
kubectl get pods -n retail-store -o wide
kubectl top pods -n retail-store

# 2. Check HPA scaling status (is it maxed out or unable to scale?)
kubectl get hpa -n retail-store

# 3. Check recent warning events (OOMKilled, FailedScheduling, Unhealthy probes)
kubectl get events -n retail-store --sort-by='.lastTimestamp' | tail -n 20
```
- **If pods are `Pending`:** Check node capacity and EKS Auto Mode provisioning (`kubectl get nodes,nodepool`).
- **If pods are `CrashLoopBackOff` / `OOMKilled`:** Inspect the previous container logs:
  ```bash
  kubectl logs -n retail-store <pod-name> --previous --tail=50
  ```

### Step 2.3: Check Managed AWS Backends (2–3 mins)
If pods are healthy but latency remains $> 500\text{ ms}$, check downstream dependencies:
- **Aurora MySQL (`group2-capstone-aurora-mysql`) & Aurora PostgreSQL (`group2-capstone-orders-pg`):** Check CloudWatch `CPUUtilization` and `DatabaseConnections` (confirm Serverless v2 ACUs are not pinned at max capacity).
- **DynamoDB (`group2-capstone-carts`):** Check CloudWatch `ThrottledRequests` and `SuccessfulRequestLatency`.
- **SQS (`group2-capstone-orders-events`):** Check `ApproximateNumberOfMessagesVisible` for queue backlog.

### Step 2.4: Check Recent GitOps Changes
Open **ArgoCD** (`retail-store` application) and check **HISTORY AND ROLLBACK** to see if a recent commit or image update preceded the incident.

---

## 3. Mitigation & Recovery

Apply the mitigation that matches your diagnosis:

| Root Cause | Immediate Mitigation |
|---|---|
| **Bad recent deployment / config** | Roll back to the last known good revision in **ArgoCD** (`History and Rollback` $\rightarrow$ `Rollback`) or revert the commit in Git. |
| **Traffic spike exceeding HPA maxReplicas** | Temporarily increase HPA `maxReplicas` or scale the affected deployment to absorb load:<br>`kubectl scale deployment ui -n retail-store --replicas=4` |
| **Hung / deadlocked pod** | Perform a zero-downtime rolling restart:<br>`kubectl rollout restart deployment/<service> -n retail-store` |
| **Aurora MySQL / PostgreSQL CPU saturation** | Increase `aurora_max_capacity` in Terraform (`variables.tf`) and apply to allow Serverless v2 to scale higher. |
| **ALB / Ingress unhealthy targets** | Verify target health in AWS Console (EC2 $\rightarrow$ Target Groups $\rightarrow$ `k8s-retailst-ui-*`) and check security group / readiness probe configuration. |

### Recovery Verification
Confirm the incident is resolved only when **all** of the following hold for at least 5 consecutive minutes:
1. `kubectl get pods -n retail-store` shows all pods `Running` and `Ready` with no new restarts.
2. Grafana Capstone Dashboard and CloudWatch `group2-capstone-overview` show **p95 latency $\le 500\text{ ms}$** and **5xx error rate $< 0.1\%$**.
3. All CloudWatch Alarms return to **`OK`** state and notify via SNS / Discord.

---

## 4. Escalation

Escalate immediately if the issue is not mitigated within the target timeframe:

| Level | Trigger | Contact / Role | Action |
|---|---|---|---|
| **L1 — On-Call SRE** | Alert fires | Primary On-Call Engineer | Acknowledge within 5 mins; execute Diagnosis & Mitigation steps. |
| **L2 — Platform / Cloud Lead** | Unresolved after **15 mins** OR SEV-1 complete outage | Infrastructure / DevSecOps Lead | Investigate EKS Auto Mode, VPC/ALB networking, IAM, or Aurora/DynamoDB quotas. |
| **L3 — Engineering & Business Stakeholders** | Unresolved after **30 mins** OR data loss / security impact | Project Lead / Product Owner | Issue customer/stakeholder status update; authorize emergency architecture changes or AWS Support case. |

### Post-Incident Follow-Up
Within 24 hours of resolution, document a brief blameless post-mortem covering root cause, timeline, and preventive action items (e.g., tuning HPA thresholds, memory limits, or alert sensitivity).