# Architecture Decision Records (ADRs) — SRE & Observability

**Project:** `group2-capstone` (`ap-southeast-1`)

**Scope:** EKS Observability, Alert Routing, Automated Incident Investigation (AWS DevOps Agent), CloudWatch Integration, and Workload Isolation

**Date:** November 2026

## Summary Index

| ADR ID | Title | Status | Key Components | 
| ----- | ----- | ----- | ----- | 
| **ADR-001** | Adopt `kube-prometheus-stack` for Unified Kubernetes Observability | Accepted | Prometheus, Alertmanager, Grafana, `kube-state-metrics` | 
| **ADR-002** | Isolate Monitoring & Platform Workloads via Dedicated Tainted Node Groups | Accepted | EKS Managed Node Groups (`t3-medium-monitoring`), Tolerations | 
| **ADR-003** | Decouple Alertmanager from AWS DevOps Agent via an HMAC-Signing Relay Lambda | Accepted | `AlertmanagerConfig`, `group2-capstone-devops-agent-relay`, Secrets Manager | 
| **ADR-004** | Implement Severity-Based Multi-Channel Alert Routing (Discord + DevOps Agent) | Accepted | `capstone-discord-routing`, `discord-notifications`, `devops-agent-webhook` | 
| **ADR-005** | Grant Least-Privilege Read-Only Cluster & AWS Access to AWS DevOps Agent | Accepted | `group2-capstone-agent-space`, `AIDevOpsAgentAccessPolicy`, `AmazonAIOpsAssistantPolicy` | 
| **ADR-006** | Coordinate Chaos/Demo Fault Injection with ArgoCD Sync Policies | Accepted | ArgoCD `Application` (`root`, `root-app`, `cart`), `selfHeal` | 
| **ADR-007** | Combine In-Cluster Prometheus/Grafana with AWS CloudWatch for Control-Plane & Telemetry Coverage | Accepted | CloudWatch Metrics/Logs, SNS, `AIDevOpsAgentAccessPolicy` | 

## ADR-001: Adopt `kube-prometheus-stack` for Unified Kubernetes Observability

### Context

The `group2-capstone` EKS cluster runs microservices (`retail-store` namespace) alongside platform and security add-ons. SREs require cluster-level metrics, pod/deployment health alerts, and pre-built visualization dashboards without maintaining custom scrape pipelines from scratch.

### Decision

Deploy `kube-prometheus-stack` into the `monitoring` namespace via GitOps/Helm, combining Prometheus Operator, Alertmanager, Grafana, `kube-state-metrics`, and `node-exporter`, extended with custom `PrometheusRule` CRDs (`capstone-alerts`, `capstone-sre-alerts`).

### Consequences

* **Positive:** Declarative alerting and scraping via CRDs (`PrometheusRule`, `ServiceMonitor`, `AlertmanagerConfig`); immediate visibility into Kubernetes control plane, node, and `retail-store` pod availability.

* **Negative:** Default rule sets generate background noise (e.g., `Watchdog`, `TargetDown`) that must be filtered in Alertmanager routing to prevent alert fatigue and webhook rate-limiting.

## ADR-002: Isolate Monitoring & Platform Workloads via Dedicated Tainted Node Groups

### Context

Prometheus time-series ingestion, Alertmanager state, and Grafana sidecars consume predictable CPU and memory. Scheduling business applications onto monitoring nodes—or vice versa—risks resource contention during traffic spikes or incident storms.

### Decision

Partition EKS worker nodes by workload domain using node taints (e.g., `workload=t3-medium-monitoring:NoSchedule`, `workload=t3-medium-apps:NoSchedule`, `CriticalAddonsOnly:NoSchedule`) and configure monitoring components with explicit matching tolerations.

### Consequences

* **Positive:** Monitoring and alerting remain operational even when `retail-store` application nodes experience high load or pod churn.

* **Negative:** Ad-hoc diagnostic pods (`kubectl run`) must include explicit `tolerations` overrides in their pod spec or they will remain `Pending` (`FailedScheduling`).

## ADR-003: Decouple Alertmanager from AWS DevOps Agent via an HMAC-Signing Relay Lambda

### Context

AWS DevOps Agent's generic webhook endpoint (`https://event-ai.ap-southeast-1.api.aws/webhook/generic/...`) requires a specific JSON schema (`eventType`, `incidentId`, `action`, `priority`, `timestamp`, `description`) and HMAC-SHA256 request signing via `x-amzn-event-timestamp` and `x-amzn-event-signature` headers. Alertmanager's native `webhookConfigs` cannot dynamically compute per-request HMAC signatures or reshape alert payloads into the DevOps Agent incident schema.

### Decision

Deploy a lightweight Python 3.12 AWS Lambda function (`group2-capstone-devops-agent-relay`) exposed via a Lambda Function URL, configured as Alertmanager's `devops-agent-webhook` receiver. The Lambda retrieves `webhook-url` and `hmac-secret` from AWS Secrets Manager (`group2-capstone/sre/devops-agent-webhook`), enriches the description with EKS cluster/namespace/deployment metadata, signs the payload, and forwards it to AWS DevOps Agent.

### Consequences

* **Positive:** Cleanly bridges standard Alertmanager webhooks to AWS DevOps Agent without modifying Alertmanager binaries; keeps HMAC secrets out of Kubernetes manifests; enriches incidents with cluster topology context for faster root-cause triage.

* **Negative:** Introduces an extra network hop and requires keeping the Kubernetes `devops-agent-webhook` secret synchronized whenever the Lambda Function URL is recreated. Warm Lambda containers cache `SECRET_ARN` in memory (`_cached_secret`), so secret rotations require either a cold start/redeploy or cache TTL handling.

## ADR-004: Implement Severity-Based Multi-Channel Alert Routing (Discord + DevOps Agent)

### Context

Human operators need visibility into both `warning` and `critical` alerts in Discord, whereas automated root-cause investigations in AWS DevOps Agent should only trigger for actionable `critical` infrastructure/application incidents (and never recursively trigger on Alertmanager's own notification-failure meta-alerts).

### Decision

Configure an `AlertmanagerConfig` (`capstone-discord-routing` in `monitoring`) with two ordered child routes:

1. **`devops-agent-webhook` (`continue: true`):** Matches `severity = critical` and `alertname != AlertmanagerClusterFailedToSendAlerts`.

2. **`discord-notifications`:** Matches `severity =~ critical|warning` and formats human-readable summaries/descriptions into the SRE Discord channel.

### Consequences

* **Positive:** Parallel delivery ensures SREs see alerts in Discord immediately while AWS DevOps Agent begins autonomous triage in the background; excluding `AlertmanagerClusterFailedToSendAlerts` prevents feedback loops.

* **Negative:** Fine-grained `groupBy` labels (`['alertname', 'namespace', 'pod', 'deployment']`) with short `groupWait` (`10s`) can trigger Discord HTTP `429` rate limits during multi-pod failures unless grouped more broadly.

## ADR-005: Grant Least-Privilege Read-Only Cluster & AWS Access to AWS DevOps Agent

### Context

To perform automated root-cause analysis across EKS pods and AWS infrastructure, `group2-capstone-agent-space` needs permission to inspect Kubernetes resources, CloudWatch logs/metrics, and AWS service configurations without holding unrestricted write/admin privileges.

### Decision

1. Attach the AWS-managed `AIDevOpsAgentAccessPolicy` to `group2-capstone-devops-agent-space-role` and associate the AWS account in `monitor` mode.

2. Create an EKS Access Entry (`aws_eks_access_entry.devops_agent`) binding `AmazonAIOpsAssistantPolicy` at cluster scope so the agent can read pod statuses, events, deployments, and logs via the Kubernetes API.

3. Enable the Operator Web App (`group2-capstone-devops-agent-operator-role`) with scoped `aidevops:*` and `devops-agent:*` permissions on the Agent Space ARN.

### Consequences

* **Positive:** Enables end-to-end correlation across EKS events and AWS telemetry while adhering to least-privilege, auditable IAM and EKS Access Entry boundaries.

* **Negative:** Remediation actions remain human-in-the-loop (or GitOps-driven) rather than autonomously mutating cluster state.

## ADR-006: Coordinate Chaos/Demo Fault Injection with ArgoCD Sync Policies

### Context

ArgoCD manages `retail-store` applications (`root`, `root-app`, `cart`) with `automated` sync (`prune: true`, `selfHeal: true`). Any manual `kubectl set image` or `kubectl patch` fault injection is immediately reverted by ArgoCD before Prometheus's `2m` alert evaluation window completes.

### Decision

Standardize a controlled fault-injection workflow (documented in `DEVOPS_AGENT_DEMO_RUNBOOK.md`) that temporarily clears `spec.syncPolicy` on `root`, `root-app`, and `cart` prior to injecting faults, and restores `automated` sync (`prune: true`, `selfHeal: true`) immediately after `kubectl rollout undo`.

### Consequences

* **Positive:** Allows deterministic, repeatable SRE game days and live demos without permanently drifting Git state.

* **Negative:** Requires strict adherence to post-demo cleanup steps so GitOps self-healing is never left disabled.

## ADR-007: Combine In-Cluster Prometheus/Grafana with AWS CloudWatch for Control-Plane & Telemetry Coverage

### Context

In-cluster Prometheus (`kube-prometheus-stack`) excels at granular pod, deployment, and service-level metrics inside EKS, but cannot detect out-of-band AWS infrastructure failures (such as EKS control-plane degradation, EC2 Auto Scaling Group node failures, or Lambda/Secrets Manager errors) if the cluster itself is degraded. Additionally, AWS DevOps Agent (`group2-capstone-agent-space`) natively queries CloudWatch Logs and Metrics via `AIDevOpsAgentAccessPolicy` during root-cause investigations, while `group2-capstone-devops-agent-relay` expects Alertmanager's `{"alerts": [...]}` JSON schema rather than raw AWS SNS envelopes.

### Decision

Adopt a complementary dual-layer observability model:

1. **Primary Kubernetes & Application Alerting:** Use in-cluster Prometheus and Alertmanager (`kube-prometheus-stack`) for pod/deployment health (`RetailStorePodNotReady`, `RetailStoreDeploymentUnavailable`), routing critical alerts to `group2-capstone-devops-agent-relay` and Discord.

2. **Out-of-Band AWS Telemetry & Investigation Enrichment:** Retain AWS CloudWatch Logs (e.g., `/aws/lambda/group2-capstone-devops-agent-relay`, EKS control-plane logs, Container Insights) and AWS-native CloudWatch Alarms (for EC2/ASG nodes, RDS/managed services, and Lambda errors) so AWS DevOps Agent can correlate Kubernetes state with underlying AWS infrastructure metrics.

3. **Dedicated SNS-to-DevOps-Agent Adapter (When Triggering Investigations from CloudWatch Alarms):** Keep CloudWatch Alarm SNS topics decoupled from `group2-capstone-devops-agent-relay`; route CloudWatch SNS notifications through a dedicated SNS-parsing Lambda (or EventBridge rule) that extracts `Records[].Sns.Message` and signs payloads using `group2-capstone/sre/devops-agent-webhook` rather than sending raw SNS envelopes to the Alertmanager relay.

### Consequences

* **Positive:** Preserves full visibility during cluster-wide or node-level outages; enriches AWS DevOps Agent investigations with native AWS logs and metrics; prevents schema mismatches between SNS envelopes and Alertmanager webhook payloads.

* **Negative:** Requires maintaining clear alert ownership boundaries between Prometheus rules and CloudWatch Alarms to avoid duplicate incidents firing simultaneously for the same failure.