# Capstone SRE — Helm Configuration References

## Overview

The Capstone observability stack is managed declaratively through Argo CD and Helm, using GitOps as the configuration source of truth.

Active Helm configurations are maintained under `gitops/sre/apps/`, rather than duplicated in standalone reference values files.

## Observability Components

| Component | Responsibility | Active Configuration |
|---|---|---|
| Prometheus | Collects application and Kubernetes workload metrics | `gitops/sre/apps/prometheus-stack.yaml` |
| Grafana | Visualises metrics, logs, dashboards, and service health | `gitops/sre/apps/prometheus-stack.yaml` |
| Loki | Receives, stores, and queries application logs | `gitops/sre/apps/loki.yaml` |
| Grafana Alloy | Discovers Kubernetes pods and forwards logs to Loki | `gitops/sre/apps/alloy.yaml` |

## Configuration Architecture

```text
Capstone Git Repository
    |
    v
gitops/sre/apps/
    |
    v
Argo CD Applications
    |
    v
spec.source.helm.valuesObject
    |
    v
Helm Chart Rendering
    |
    v
Kubernetes Observability Resources
    |
    +-- Prometheus
    +-- Grafana
    +-- Loki
    +-- Alloy
```

## Configuration Management

- Active Helm settings are maintained within their respective Argo CD Application manifests.
- Standalone Helm values examples are being retired to avoid duplicated configuration sources.
- This directory retains supporting documentation only.
- Configuration changes must undergo validation and pull-request review before GitOps reconciliation.

## Deployment and Validation

Helm rendering and static configuration checks have been performed locally for the Alloy configuration.

These checks do not establish successful deployment or runtime health in the Capstone EKS cluster. Runtime verification remains a separate requirement.

## Source of Truth

Refer to `gitops/README.md` for the complete GitOps architecture and `gitops/sre/README.md` for SRE-specific technical documentation.
