from datetime import datetime
import time

import requests


PROMETHEUS_URL = (
    "http://kube-prometheus-stack-prometheus."
    "monitoring.svc.cluster.local:9090"
)

NAMESPACE = "retail-store"

PLATFORM_RULES = {
    "KubernetesNodeNotReady",
    "KubernetesNodeCriticalMemory",
    "OTelCollectorDown",
}

REQUIRED_RULES = PLATFORM_RULES | {
    "CapstoneTargetDown",
    "CapstoneDeploymentUnavailable",
    "RetailStorePodCrashLooping",
    "RetailStoreDeploymentUnavailable",
    "RetailStorePodNotReady",
    "RetailStoreHPAMaxedOut",
    "RetailStoreHighMemoryUsage",
    "RetailStoreContainerOOMKilled",
    "RetailStoreHighCPUUsage",
    "RetailStoreCPUThrottlingHigh",
    "RetailStoreExposedSecretDetected",
}

EXPECTED_SCRAPE_POOLS = {
    "ui": "serviceMonitor/monitoring/capstone-actuator-metrics/0",
    "carts": "serviceMonitor/monitoring/capstone-actuator-metrics/0",
    "orders": "serviceMonitor/monitoring/capstone-actuator-metrics/0",
    "catalog": "serviceMonitor/monitoring/capstone-http-metrics/0",
    "checkout": "serviceMonitor/monitoring/capstone-http-metrics/0",
}

MINIMUM_PRODUCTION_REPLICAS = 2

MAX_SCRAPE_AGE = 120
MAX_RULE_AGE = 180


def timestamp_age(value, now):
    if not value:
        return float("inf")

    parsed = datetime.fromisoformat(
        value.replace("Z", "+00:00")
    )

    return now - parsed.timestamp()


class MonitoringIntegrityGate:

    def __init__(self, session=None):
        self.session = session or requests.Session()

    def api(self, path):

        response = self.session.get(
            PROMETHEUS_URL + path,
            timeout=5,
        )

        response.raise_for_status()

        payload = response.json()

        if payload.get("status") != "success":
            raise RuntimeError("Prometheus API failure")

        return payload["data"]

    def readiness(self):

        response = self.session.get(
            PROMETHEUS_URL + "/-/ready",
            timeout=5,
        )

        return {
            "healthy": response.status_code == 200,
            "http_status": response.status_code,
        }

    def target_healthy(self, target, now):

        age = timestamp_age(
            target.get("lastScrape"),
            now,
        )

        return (
            target.get("health") == "up"
            and not target.get("lastError")
            and 0 <= age <= MAX_SCRAPE_AGE
        )

    def targets(self, now=None):

        targets = self.api(
            "/api/v1/targets"
        )["activeTargets"]

        if now is None:
            now = time.time()

        production = [
            target for target in targets
            if target.get("labels", {}).get(
                "namespace"
            ) == NAMESPACE
        ]

        ksm = [
            target for target in targets
            if "kube-state-metrics" in
            target.get("labels", {}).get("job", "")
        ]

        coverage = {}

        for service, pool in EXPECTED_SCRAPE_POOLS.items():

            matching = [
                target for target in production
                if target.get("labels", {}).get("service") == service
                and target.get("scrapePool") == pool
            ]

            healthy_pods = {
                target["labels"]["pod"]
                for target in matching
                if target.get("labels", {}).get("pod")
                and self.target_healthy(target, now)
            }

            coverage[service] = {
                "healthy": (
                    len(healthy_pods) >= MINIMUM_PRODUCTION_REPLICAS
                    and all(
                        self.target_healthy(t, now)
                        for t in matching
                    )
                ),
                "healthy_pods": len(healthy_pods),
                "scrape_pool": pool,
            }

        production_healthy = (
            all(item["healthy"] for item in coverage.values())
            and all(
                self.target_healthy(t, now)
                for t in production
            )
        )

        ksm_healthy = (
            bool(ksm)
            and all(
                self.target_healthy(t, now)
                for t in ksm
            )
        )

        return {
            "healthy": (
                production_healthy and ksm_healthy
            ),
            "production_targets": len(production),
            "service_coverage": coverage,
            "production_targets_healthy": (
                production_healthy
            ),
            "kube_state_metrics_targets": len(ksm),
            "kube_state_metrics_healthy": ksm_healthy,
        }

    def rules(self, now=None):

        groups = self.api(
            "/api/v1/rules"
        )["groups"]

        if now is None:
            now = time.time()

        discovered = set()
        unhealthy = []

        for group in groups:

            for rule in group.get("rules", []):

                name = rule.get("name")

                if name not in REQUIRED_RULES:
                    continue

                discovered.add(name)

                age = timestamp_age(
                    rule.get("lastEvaluation")
                    or group.get("lastEvaluation"),
                    now,
                )

                if (
                    rule.get("health") != "ok"
                    or rule.get("lastError")
                    or not 0 <= age <= MAX_RULE_AGE
                ):
                    unhealthy.append(name)

        missing = REQUIRED_RULES - discovered

        return {
            "healthy": (
                not missing and not unhealthy
            ),
            "missing_rules": sorted(missing),
            "unhealthy_rules": sorted(unhealthy),
        }

    def alerts(self):

        alerts = self.api(
            "/api/v1/alerts"
        )["alerts"]

        critical = []

        for alert in alerts:

            labels = alert.get("labels", {})

            if alert.get("state") != "firing":
                continue

            if labels.get("severity") != "critical":
                continue

            if (
                labels.get("namespace") == NAMESPACE
                or labels.get("alertname")
                in PLATFORM_RULES
            ):
                critical.append(
                    labels.get("alertname", "unknown")
                )

        return {
            "healthy": not critical,
            "critical_alerts": sorted(critical),
        }

    def evaluate(self):

        now = time.time()

        checks = {}

        operations = {
            "readiness": self.readiness,
            "targets": self.targets,
            "rules": self.rules,
            "alerts": self.alerts,
        }

        for name, operation in operations.items():

            try:
                checks[name] = operation()

            except Exception as error:
                checks[name] = {
                    "healthy": False,
                    "error_type": type(error).__name__,
                }

        failed = [
            name
            for name, result in checks.items()
            if not result["healthy"]
        ]

        return {
            "healthy": not failed,
            "namespace": NAMESPACE,
            "observed_at": time.time(),
            "checks": checks,
            "failed_checks": failed,
        }
