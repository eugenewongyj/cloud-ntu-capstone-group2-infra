import math
import time

import requests


NAMESPACE = "retail-store"

DEPLOYMENTS = (
    "carts",
    "catalog",
    "checkout",
    "orders",
    "ui",
)

STOREFRONT_URL = (
    "https://group2-shop."
    "sctp-sandbox.com/catalog"
)

CONTENT_MARKER = (
    "These products are for demonstration purposes only"
)

PROMETHEUS_URL = (
    "http://kube-prometheus-stack-prometheus."
    "monitoring.svc.cluster.local:9090"
)

CRITICAL_ALERT_QUERY = (
    'count(ALERTS{alertstate="firing",'
    'severity="critical",namespace="retail-store"})'
    ' or vector(0)'
)

PLATFORM_ALERT_QUERY = (
    'count(ALERTS{alertstate="firing",'
    'severity="critical",'
    'alertname=~"KubernetesNodeNotReady|'
    'KubernetesNodeCriticalMemory|OTelCollectorDown"})'
    ' or vector(0)'
)


class InfrastructureHealthGate:

    def __init__(
        self,
        apps_api,
        autoscaling_api,
        telemetry,
        session=None,
    ):

        self.apps_api = apps_api
        self.autoscaling_api = autoscaling_api
        self.telemetry = telemetry
        self.session = session or requests.Session()

    @staticmethod
    def conditions(items):

        return {
            item.type: item.status
            for item in (items or [])
        }

    def deployment_check(self, name):

        obj = self.apps_api.read_namespaced_deployment(
            name=name,
            namespace=NAMESPACE,
            _request_timeout=5,
        )

        desired = obj.spec.replicas
        status = obj.status

        ready = status.ready_replicas or 0
        available = status.available_replicas or 0
        updated = status.updated_replicas or 0

        conditions = self.conditions(
            status.conditions
        )

        healthy = (
            desired is not None
            and desired >= 1
            and ready == desired
            and available == desired
            and updated == desired
            and status.replicas == desired
            and status.observed_generation
                == obj.metadata.generation
            and conditions.get("Available") == "True"
            and conditions.get("Progressing") != "False"
        )

        return {
            "healthy": healthy,
            "desired": desired,
            "ready": ready,
            "available": available,
            "updated": updated,
        }

    def hpa_check(self, name):

        obj = (
            self.autoscaling_api
            .read_namespaced_horizontal_pod_autoscaler(
                name=name,
                namespace=NAMESPACE,
                _request_timeout=5,
            )
        )

        spec = obj.spec
        status = obj.status

        targets = [
            item.resource.target.average_utilization
            for item in (spec.metrics or [])
            if item.type == "Resource"
            and item.resource is not None
            and item.resource.name == "cpu"
            and item.resource.target.type == "Utilization"
        ]

        current = [
            item.resource.current.average_utilization
            for item in (status.current_metrics or [])
            if item.type == "Resource"
            and item.resource is not None
            and item.resource.name == "cpu"
        ]

        target = targets[0] if len(targets) == 1 else None
        utilization = current[0] if len(current) == 1 else None

        conditions = self.conditions(
            status.conditions
        )

        reference = spec.scale_target_ref

        healthy = (
            reference.api_version == "apps/v1"
            and reference.kind == "Deployment"
            and reference.name == name
            and target is not None
            and target > 0
            and utilization is not None
            and 0 <= utilization < target
            and status.current_replicas
                == status.desired_replicas
            and (spec.min_replicas or 1)
                <= status.current_replicas
                <= spec.max_replicas
            and status.observed_generation
                == obj.metadata.generation
            and conditions.get("AbleToScale") == "True"
            and conditions.get("ScalingActive") == "True"
        )

        return {
            "healthy": healthy,
            "cpu_utilization": utilization,
            "cpu_target": target,
            "current_replicas": status.current_replicas,
            "desired_replicas": status.desired_replicas,
            "minimum_replicas": spec.min_replicas,
            "maximum_replicas": spec.max_replicas,
        }

    def storefront_check(self):

        started = time.monotonic()

        response = self.session.get(
            STOREFRONT_URL,
            timeout=(3, 10),
            allow_redirects=False,
        )

        elapsed_ms = (
            time.monotonic() - started
        ) * 1000

        marker_present = (
            CONTENT_MARKER in response.text
        )

        return {
            "healthy": (
                response.status_code == 200
                and marker_present
            ),
            "http_status": response.status_code,
            "content_marker_present": marker_present,
            "request_duration_ms": round(elapsed_ms, 2),
        }

    def alert_check(self, now):

        production = self.telemetry.query(
            CRITICAL_ALERT_QUERY,
            now,
        )

        platform = self.telemetry.query(
            PLATFORM_ALERT_QUERY,
            now,
        )

        valid = all(
            type(value) in (int, float)
            and math.isfinite(value)
            and value >= 0
            for value in (production, platform)
        )

        return {
            "healthy": (
                valid
                and production == 0
                and platform == 0
            ),
            "production_critical_alerts": production,
            "platform_critical_alerts": platform,
            "telemetry_valid": valid,
        }

    def evaluate(self):

        started_at = time.time()

        checks = {}

        def collect(key, operation):

            try:
                checks[key] = operation()

            except Exception as exc:
                checks[key] = {
                    "healthy": False,
                    "error_type": type(exc).__name__,
                }

        for name in DEPLOYMENTS:

            collect(
                f"deployment/{name}",
                lambda name=name:
                    self.deployment_check(name),
            )

            collect(
                f"hpa/{name}",
                lambda name=name:
                    self.hpa_check(name),
            )

        collect(
            "storefront",
            self.storefront_check,
        )

        collect(
            "critical_alerts",
            lambda: self.alert_check(time.time()),
        )

        for name in DEPLOYMENTS:

            deployment = checks[f"deployment/{name}"]
            hpa = checks[f"hpa/{name}"]

            if (
                deployment.get("healthy") is True
                and hpa.get("healthy") is True
                and deployment["desired"]
                    != hpa["desired_replicas"]
            ):
                deployment["healthy"] = False
                deployment["error"] = (
                    "Deployment and HPA replicas differ"
                )

        failed = [
            key
            for key, result in checks.items()
            if result.get("healthy") is not True
        ]

        return {
            "healthy": not failed,
            "started_at": started_at,
            "observed_at": time.time(),
            "namespace": NAMESPACE,
            "checks": checks,
            "failed_checks": failed,
        }
