# SwiftKart SRE — Helm Configuration

This directory contains Helm values and Grafana dashboard definitions for the SwiftKart observability stack.

## Components

| Component | Purpose |
|---|---|
| Prometheus | Collects application and Kubernetes workload metrics |
| Grafana | Visualises service health, metrics, and logs |
| Loki | Stores and queries application logs |
| Alloy | Collects Kubernetes application logs and forwards them to Loki |

## Deployment

The configurations are prepared for future deployment to the SwiftKart AWS EKS Auto Mode environment.

All Helm templates and configuration files should be validated before deployment. Kubernetes resource manifests are maintained separately under `sre/kubernetes/`.

**Status:** Locally validated; not yet deployed to the capstone EKS cluster.
