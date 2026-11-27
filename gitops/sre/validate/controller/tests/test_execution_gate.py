import unittest

from unittest.mock import Mock

from execution_gate import ExecutionGate


class ExecutionGateTests(unittest.TestCase):

    def setUp(self):

        self.infrastructure = Mock()
        self.monitoring = Mock()

        services = (
            "carts", "catalog", "checkout",
            "orders", "ui",
        )

        self.infrastructure.evaluate.return_value = {
            "healthy": True,
            "checks": {
                f"deployment/{name}": {
                    "healthy": True,
                    "desired": 2,
                }
                for name in services
            },
        }

        self.monitoring.evaluate.return_value = {
            "healthy": True,
            "checks": {
                "targets": {
                    "service_coverage": {
                        name: {
                            "healthy": True,
                            "healthy_pods": 2,
                        }
                        for name in services
                    },
                },
            },
        }

        self.gate = ExecutionGate(
            self.infrastructure,
            self.monitoring,
        )

    def test_both_healthy(self):

        result = self.gate.evaluate()

        self.assertTrue(result["healthy"])

        self.assertEqual(
            result["namespace"],
            "retail-store",
        )

    def test_infrastructure_unhealthy(self):

        self.infrastructure.evaluate.return_value = {
            "healthy": False,
        }

        result = self.gate.evaluate()

        self.assertFalse(result["healthy"])

        self.assertIn(
            "infrastructure",
            result["failed_checks"],
        )

    def test_monitoring_unhealthy(self):

        self.monitoring.evaluate.return_value = {
            "healthy": False,
        }

        result = self.gate.evaluate()

        self.assertFalse(result["healthy"])

        self.assertIn(
            "monitoring",
            result["failed_checks"],
        )

    def test_both_unhealthy(self):

        self.infrastructure.evaluate.return_value = {
            "healthy": False,
        }

        self.monitoring.evaluate.return_value = {
            "healthy": False,
        }

        result = self.gate.evaluate()

        self.assertFalse(result["healthy"])

        self.assertIn(
            "infrastructure",
            result["failed_checks"],
        )

        self.assertIn(
            "monitoring",
            result["failed_checks"],
        )

    def test_infrastructure_exception(self):

        self.infrastructure.evaluate.side_effect = (
            RuntimeError("Kubernetes unavailable")
        )

        self.assertFalse(
            self.gate.evaluate()["healthy"]
        )

    def test_monitoring_exception(self):

        self.monitoring.evaluate.side_effect = (
            RuntimeError("Prometheus unavailable")
        )

        self.assertFalse(
            self.gate.evaluate()["healthy"]
        )

    def test_missing_health_status(self):

        self.monitoring.evaluate.return_value = {}

        self.assertFalse(
            self.gate.evaluate()["healthy"]
        )

    def test_invalid_gate_response(self):

        self.infrastructure.evaluate.return_value = None

        self.assertFalse(
            self.gate.evaluate()["healthy"]
        )

    def test_both_components_evaluated(self):

        self.gate.evaluate()

        self.infrastructure.evaluate.assert_called_once()
        self.monitoring.evaluate.assert_called_once()

    def test_complete_replica_coverage(self):
        result = self.gate.evaluate()
        self.assertTrue(result["healthy"])
        self.assertEqual(
            len(result["replica_coverage"]), 5
        )

    def test_scaled_out_coverage(self):
        self.infrastructure.evaluate.return_value[
            "checks"
        ]["deployment/ui"]["desired"] = 4

        self.monitoring.evaluate.return_value[
            "checks"
        ]["targets"]["service_coverage"]["ui"][
            "healthy_pods"
        ] = 4

        self.assertTrue(
            self.gate.evaluate()["healthy"]
        )

    def test_missing_scaled_out_target(self):
        self.infrastructure.evaluate.return_value[
            "checks"
        ]["deployment/ui"]["desired"] = 4

        result = self.gate.evaluate()

        self.assertFalse(result["healthy"])

        self.assertIn(
            "replica_coverage/ui",
            result["failed_checks"],
        )

    def test_stale_extra_target_blocks(self):
        self.monitoring.evaluate.return_value[
            "checks"
        ]["targets"]["service_coverage"]["ui"][
            "healthy_pods"
        ] = 3

        self.assertFalse(
            self.gate.evaluate()["healthy"]
        )

    def test_missing_service_coverage_blocks(self):
        del self.monitoring.evaluate.return_value[
            "checks"
        ]["targets"]["service_coverage"]["catalog"]

        self.assertFalse(
            self.gate.evaluate()["healthy"]
        )

    def test_invalid_replica_count_blocks(self):
        self.infrastructure.evaluate.return_value[
            "checks"
        ]["deployment/ui"]["desired"] = None

        self.assertFalse(
            self.gate.evaluate()["healthy"]
        )

    def test_evidence_preserved(self):

        result = self.gate.evaluate()

        self.assertEqual(
            result["infrastructure"],
            self.infrastructure.evaluate.return_value,
        )

        self.assertEqual(
            result["monitoring"],
            self.monitoring.evaluate.return_value,
        )


if __name__ == "__main__":
    unittest.main()
