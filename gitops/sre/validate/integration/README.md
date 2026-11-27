# Capstone SRE Live Automation Integration

This directory contains inactive deployment templates.

Do not activate until:

1. Terraform provisions the SRE ECR repositories.
2. Controller authentication secret is populated.
3. External Secrets synchronizes the authentication token.
4. Controller image is published and digest verified.
5. Both Grafana plugins are signed and published.
6. Runtime Kustomize resources are assembled and validated.
7. Grafana plugin image placeholder is replaced.
8. Helm baseline and candidate manifests are compared.
9. Grafana rollout and rollback procedures are reviewed.

The original Mission Control dashboard remains unchanged.

No additional public ingress, ALB, DNS record,
Grafana instance or namespace is required.

Existing Grafana authentication is retained.
