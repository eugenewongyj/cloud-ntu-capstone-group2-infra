import time


NAMESPACE = "retail-store"

SERVICES = (
    "carts",
    "catalog",
    "checkout",
    "orders",
    "ui",
)


class ExecutionGate:

    def __init__(
        self,
        infrastructure,
        monitoring,
    ):
        self.infrastructure = infrastructure
        self.monitoring = monitoring

    @staticmethod
    def evaluate_component(component):

        try:
            result = component.evaluate()

            if not isinstance(result, dict):
                raise ValueError("Invalid gate result")

            return result

        except Exception as error:

            return {
                "healthy": False,
                "error_type": type(error).__name__,
            }

    def evaluate(self):

        started_at = time.time()

        infrastructure = self.evaluate_component(
            self.infrastructure
        )

        monitoring = self.evaluate_component(
            self.monitoring
        )

        failed = []

        if infrastructure.get("healthy") is not True:
            failed.append("infrastructure")

        if monitoring.get("healthy") is not True:
            failed.append("monitoring")

        coverage = {}

        deployments = infrastructure.get("checks", {})

        targets = monitoring.get(
            "checks", {}
        ).get("targets", {})

        service_coverage = targets.get(
            "service_coverage", {}
        )

        for service in SERVICES:

            deployment = deployments.get(
                f"deployment/{service}", {}
            )

            observed = service_coverage.get(
                service, {}
            )

            desired = deployment.get("desired")

            healthy_pods = observed.get(
                "healthy_pods"
            )

            healthy = (
                deployment.get("healthy") is True
                and observed.get("healthy") is True
                and type(desired) is int
                and type(healthy_pods) is int
                and desired >= 2
                and healthy_pods == desired
            )

            coverage[service] = {
                "healthy": healthy,
                "desired_replicas": desired,
                "healthy_scrape_targets": healthy_pods,
            }

            if not healthy:
                failed.append(
                    f"replica_coverage/{service}"
                )

        return {
            "healthy": not failed,
            "namespace": NAMESPACE,
            "started_at": started_at,
            "observed_at": time.time(),
            "infrastructure": infrastructure,
            "monitoring": monitoring,
            "failed_checks": failed,
            "replica_coverage": coverage,
        }
