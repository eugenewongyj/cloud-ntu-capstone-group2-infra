import unittest

from unittest.mock import Mock, create_autospec
from kubernetes import client

from health_gate import (
    InfrastructureHealthGate,
    DEPLOYMENTS,
    NAMESPACE,
    CONTENT_MARKER,
    STOREFRONT_URL,
)


class HealthGateTests(unittest.TestCase):

    def setUp(self):

        self.apps = create_autospec(
            client.AppsV1Api,
            instance=True,
        )

        self.hpa = create_autospec(
            client.AutoscalingV2Api,
            instance=True,
        )

        self.telemetry = Mock()
        self.telemetry.query.return_value = 0

        self.session = Mock()

        self.session.get.return_value.status_code = 200
        self.session.get.return_value.text = CONTENT_MARKER

        self.apps.read_namespaced_deployment.side_effect = (
            self.deployment
        )

        self.hpa.read_namespaced_horizontal_pod_autoscaler.side_effect = (
            self.autoscaler
        )

        self.gate = InfrastructureHealthGate(
            self.apps,
            self.hpa,
            self.telemetry,
            self.session,
        )

    def deployment(self, name, namespace, **kwargs):

        self.assertIn(name, DEPLOYMENTS)
        self.assertEqual(namespace, NAMESPACE)

        obj = Mock()

        obj.metadata.generation = 1
        obj.spec.replicas = 2

        obj.status.ready_replicas = 2
        obj.status.available_replicas = 2
        obj.status.updated_replicas = 2
        obj.status.replicas = 2
        obj.status.observed_generation = 1

        available = Mock()
        available.type = "Available"
        available.status = "True"

        progressing = Mock()
        progressing.type = "Progressing"
        progressing.status = "True"

        obj.status.conditions = [
            available,
            progressing,
        ]

        return obj

    def autoscaler(self, name, namespace, **kwargs):

        self.assertIn(name, DEPLOYMENTS)
        self.assertEqual(namespace, NAMESPACE)

        obj = Mock()

        obj.metadata.generation = 1

        obj.spec.min_replicas = 2
        obj.spec.max_replicas = 6

        ref = obj.spec.scale_target_ref
        ref.api_version = "apps/v1"
        ref.kind = "Deployment"
        ref.name = name

        target = Mock()
        target.type = "Resource"
        target.resource.name = "cpu"
        target.resource.target.type = "Utilization"
        target.resource.target.average_utilization = 70

        obj.spec.metrics = [target]

        current = Mock()
        current.type = "Resource"
        current.resource.name = "cpu"
        current.resource.current.average_utilization = 6

        obj.status.current_metrics = [current]

        obj.status.current_replicas = 2
        obj.status.desired_replicas = 2
        obj.status.observed_generation = 1

        able = Mock()
        able.type = "AbleToScale"
        able.status = "True"

        active = Mock()
        active.type = "ScalingActive"
        active.status = "True"

        limited = Mock()
        limited.type = "ScalingLimited"
        limited.status = "True"

        obj.status.conditions = [
            able,
            active,
            limited,
        ]

        return obj

    def test_all_checks_healthy(self):

        result = self.gate.evaluate()

        self.assertTrue(result["healthy"])
        self.assertEqual(len(result["checks"]), 12)

    def test_all_five_deployments_checked(self):

        self.gate.evaluate()

        self.assertEqual(
            self.apps.read_namespaced_deployment.call_count,
            5,
        )

    def test_all_five_hpas_checked(self):

        self.gate.evaluate()

        self.assertEqual(
            self.hpa
            .read_namespaced_horizontal_pod_autoscaler
            .call_count,
            5,
        )

    def test_unavailable_deployment_blocks(self):

        obj = self.deployment("ui", NAMESPACE)
        obj.status.available_replicas = 0

        self.apps.read_namespaced_deployment.side_effect = None
        self.apps.read_namespaced_deployment.return_value = obj

        self.assertFalse(
            self.gate.evaluate()["healthy"]
        )

    def test_stale_deployment_generation_blocks(self):

        obj = self.deployment("ui", NAMESPACE)
        obj.status.observed_generation = 0

        self.apps.read_namespaced_deployment.side_effect = None
        self.apps.read_namespaced_deployment.return_value = obj

        self.assertFalse(
            self.gate.evaluate()["healthy"]
        )

    def test_cpu_at_target_blocks(self):

        obj = self.autoscaler("ui", NAMESPACE)

        obj.status.current_metrics[
            0
        ].resource.current.average_utilization = 70

        self.hpa.read_namespaced_horizontal_pod_autoscaler.side_effect = (
            lambda **kwargs: obj
        )

        self.assertFalse(
            self.gate.hpa_check("ui")["healthy"]
        )

    def test_missing_cpu_metric_blocks(self):

        obj = self.autoscaler("ui", NAMESPACE)
        obj.status.current_metrics = []

        self.hpa.read_namespaced_horizontal_pod_autoscaler.side_effect = (
            lambda **kwargs: obj
        )

        self.assertFalse(
            self.gate.hpa_check("ui")["healthy"]
        )

    def test_hpa_not_converged_blocks(self):

        obj = self.autoscaler("ui", NAMESPACE)
        obj.status.desired_replicas = 3

        self.hpa.read_namespaced_horizontal_pod_autoscaler.side_effect = (
            lambda **kwargs: obj
        )

        self.assertFalse(
            self.gate.hpa_check("ui")["healthy"]
        )

    def test_storefront_failure_blocks(self):

        self.session.get.return_value.status_code = 503

        self.assertFalse(
            self.gate.evaluate()["healthy"]
        )

    def test_missing_content_blocks(self):

        self.session.get.return_value.text = ""

        self.assertFalse(
            self.gate.evaluate()["healthy"]
        )

    def test_production_target_is_fixed(self):

        self.gate.storefront_check()

        self.session.get.assert_called_once_with(
            STOREFRONT_URL,
            timeout=(3, 10),
            allow_redirects=False,
        )

    def test_production_critical_alert_blocks(self):

        self.telemetry.query.side_effect = [1, 0]

        self.assertFalse(
            self.gate.evaluate()["healthy"]
        )

    def test_platform_critical_alert_blocks(self):

        self.telemetry.query.side_effect = [0, 1]

        self.assertFalse(
            self.gate.evaluate()["healthy"]
        )

    def test_missing_alert_telemetry_blocks(self):

        self.telemetry.query.return_value = None

        self.assertFalse(
            self.gate.evaluate()["healthy"]
        )

    def test_kubernetes_api_failure_blocks(self):

        self.apps.read_namespaced_deployment.side_effect = (
            RuntimeError("API unavailable")
        )

        self.assertFalse(
            self.gate.evaluate()["healthy"]
        )

    def test_prometheus_failure_blocks(self):

        self.telemetry.query.side_effect = (
            RuntimeError("Prometheus unavailable")
        )

        self.assertFalse(
            self.gate.evaluate()["healthy"]
        )

    def test_scaling_limited_at_minimum_is_valid(self):

        self.assertTrue(
            self.gate.hpa_check("ui")["healthy"]
        )

    def test_hpa_target_is_read_dynamically(self):

        obj = self.autoscaler("ui", NAMESPACE)

        obj.spec.metrics[
            0
        ].resource.target.average_utilization = 65

        self.hpa.read_namespaced_horizontal_pod_autoscaler.side_effect = (
            lambda **kwargs: obj
        )

        result = self.gate.hpa_check("ui")

        self.assertEqual(result["cpu_target"], 65)
        self.assertTrue(result["healthy"])

    def test_scaled_up_but_stable_hpa_is_valid(self):

        obj = self.autoscaler("ui", NAMESPACE)

        obj.status.current_replicas = 3
        obj.status.desired_replicas = 3

        self.hpa.read_namespaced_horizontal_pod_autoscaler.side_effect = (
            lambda **kwargs: obj
        )

        self.assertTrue(
            self.gate.hpa_check("ui")["healthy"]
        )

    def test_replica_disagreement_blocks(self):

        def scaled(name, namespace, **kwargs):

            obj = self.autoscaler(
                name,
                namespace,
                **kwargs,
            )

            obj.status.current_replicas = 3
            obj.status.desired_replicas = 3

            return obj

        self.hpa.read_namespaced_horizontal_pod_autoscaler.side_effect = (
            scaled
        )

        self.assertFalse(
            self.gate.evaluate()["healthy"]
        )


if __name__ == "__main__":
    unittest.main()
