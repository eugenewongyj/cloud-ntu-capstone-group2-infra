# Capstone — Live Mission Control

## Shared interactive assessment

- Normal Sale: five minutes.
- 11.11 Flash Sale: five minutes.
- Recovery observation: five to ten minutes.
- Recovery target: within five minutes.
- Existing assessment controller retained.
- Existing Grafana authentication retained.
- Existing production workload limits retained.

## Plugin distribution

Image: `255945442255.dkr.ecr.ap-southeast-1.amazonaws.com/group2-capstone-sre-plugins@sha256:102b46a96286c6d60bd74f59e4c1143604ea7d01c9acabcf0f5e9e66af1e600d`

The self-hosted Grafana instance explicitly permits only:

- capstone-sremissioncontrol-panel
- capstone-srecontrol-app

This is a scoped unsigned-plugin exception for the controlled
Capstone demonstration, subject to team review.

Global plugin signature enforcement is not disabled.
The distribution image is pinned by immutable ECR digest.
Digest pinning does not replace publisher signature verification.

## Telemetry

- Prometheus and k6.
- Kubernetes resource utilisation and HPA.
- CloudWatch edge and infrastructure metrics.
- Loki production application logs.
- Existing Alertmanager and Discord routing.
- Technical and plain-language broadcast commentary.

## Evidence limitations

Actual scaling, recovery, alert delivery and CloudWatch
rendering require runtime verification.

The five-minute compressed flash-sale demonstration does
not establish two-hour sustained capacity.

## Shared dashboard

https://group2-capstone-grafana.sctp-sandbox.com/d/capstone-retail-sre-live
