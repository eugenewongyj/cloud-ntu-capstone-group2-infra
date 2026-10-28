# Kubernetes Monitoring

Custom Kubernetes monitoring resources for the capstone SRE workstream.

## Files

| File | Description |
|---|---|
| `monitoring.yaml` | Contains the ServiceMonitor and PrometheusRule resources. |

## Components

**ServiceMonitor** discovers application metrics endpoints through Kubernetes Service labels and configures Prometheus scraping.

**PrometheusRule** defines alerting conditions evaluated by Prometheus using collected metrics.

## Monitoring Pipeline

Application Pods → Kubernetes Service → Prometheus → PrometheusRule → Alertmanager → Notifications

Grafana queries Prometheus to visualize application metrics and health.

## Prerequisites

- Prometheus Operator and monitoring CRDs installed.
- Application Service exposing Prometheus-compatible metrics.
- Verified namespace, Service labels and metrics port.
- Prometheus configured to discover ServiceMonitor and PrometheusRule resources.
- Alertmanager notification routing configured for operational alerts.

## Deployment Notes

The current manifest contains example labels and namespaces. These must be replaced with the actual capstone application configuration before deployment.

All deployments to the shared EKS cluster require team coordination and approval.
