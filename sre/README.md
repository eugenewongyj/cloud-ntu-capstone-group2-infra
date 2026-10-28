# Site Reliability Engineering (SRE)

This directory contains the Site Reliability Engineering workstream for Group 2's Capstone e-commerce capstone on Amazon EKS.

## Objective

Establish application reliability through observability, performance monitoring, service-level objectives (SLOs), alerting, and incident response.

## Monitoring Approach

**Baseline → Logging & Metrics → SLOs → Alerting → Dashboards → Incident Response**

| Layer | Planned approach | Purpose |
|---|---|---|
| Baseline | AWS CLI / kubectl | Verify infrastructure and application health |
| Logging | Loki or CloudWatch Logs | Centralise logs and investigate failures |
| Metrics | Prometheus | Monitor CPU, memory, request rate, errors, and latency |
| Reliability | SLIs / SLOs | Define measurable availability and performance targets |
| Alerting | Prometheus / Alertmanager | Detect reliability issues and notify responders |
| Visualisation | Grafana | Display application and infrastructure health |
| Incident response | Runbooks | Support diagnosis, escalation, and recovery |

## Key Reliability Requirements

- Monitor Capstone's five microservices: UI, Catalog, Carts, Orders, and Checkout.
- Measure product listing p95 latency against the 500 ms flash-sale requirement.
- Observe automatic scaling during increased traffic.
- Define at least two measurable SLIs/SLOs.
- Implement and validate at least two routed alerts.
- Centralise application logs with documented retention.

## Implementation Status

**Phase 1 — SRE workspace initialisation**

This branch establishes the SRE monitoring workstream and documents the proposed approach.

Prometheus, Grafana, logging, and alerting integrations are planned but have not yet been implemented or verified.

Monitoring resources will be introduced incrementally and coordinated with the infrastructure team to avoid disrupting shared AWS resources.
