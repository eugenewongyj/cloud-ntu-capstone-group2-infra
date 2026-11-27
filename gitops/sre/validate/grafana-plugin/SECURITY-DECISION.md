# Capstone SRE Mission Control — Security Decision

## Build validation

- Grafana SDK: 13.3.0
- React: 19.3.1
- Webpack: 5.113.0
- Copy Webpack plugin: 14.0.0
- serialize-javascript: 7.1.4

## Remediated findings

The copy-webpack-plugin upgrade from 13.0.1
to 14.0.0 resolved the high-severity
serialize-javascript dependency finding.

TypeScript and Webpack compilation passed.

## Remaining findings

- Critical: 0
- High: 0
- Moderate: 8

Moderate findings involve transitive Grafana SDK
dependencies, including i18next and react-router.

Forced dependency downgrades are not permitted.

Remaining risks require team review before
shared production deployment.

## Mandatory deployment controls

- Authenticated Grafana backend
- Server-side operator authorization
- Server-side controller credential injection
- Restricted API routes
- Kubernetes least-privilege RBAC
- Plugin signature verification
- Bounded production load execution
- Concurrent assessment prevention
- Recovery validation before recurrence

## CI security gate

npm audit --audit-level=high
