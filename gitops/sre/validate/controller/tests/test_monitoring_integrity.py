import unittest
import time

from datetime import datetime, timezone
from unittest.mock import Mock

from monitoring_integrity import (
    MonitoringIntegrityGate,
    REQUIRED_RULES,
    EXPECTED_SCRAPE_POOLS,
    NAMESPACE,
)


class MonitoringIntegrityTests(unittest.TestCase):

    def setUp(self):

        self.now = time.time()

        self.timestamp = datetime.fromtimestamp(
            self.now - 5, timezone.utc
        ).isoformat()

        self.session = Mock()

        self.gate = MonitoringIntegrityGate(
            self.session
        )

        self.session.get.return_value.status_code = 200

        self.targets = [
            {
                "labels": {
                    "namespace": NAMESPACE,
                    "job": name,
                    "service": name,
                    "pod": f"{name}-replica-{replica}",
                },
                "scrapePool": pool,
                "health": "up",
                "lastError": "",
                "lastScrape": self.timestamp,
            }
            for name, pool in EXPECTED_SCRAPE_POOLS.items()
            for replica in (1, 2)
        ]

        self.targets.append({
            "labels": {
                "namespace": "monitoring",
                "job": "kube-state-metrics",
            },
            "health": "up",
            "lastError": "",
            "lastScrape": self.timestamp,
        })

        self.rules = [
            {
                "name": name,
                "health": "ok",
                "lastError": "",
                "lastEvaluation": self.timestamp,
            }
            for name in REQUIRED_RULES
        ]

        self.alerts = []

        self.gate.api = Mock(
            side_effect=self.api
        )

    def api(self, path):

        if path == "/api/v1/targets":
            return {
                "activeTargets": self.targets
            }

        if path == "/api/v1/rules":
            return {
                "groups": [{
                    "rules": self.rules
                }]
            }

        if path == "/api/v1/alerts":
            return {
                "alerts": self.alerts
            }

        raise RuntimeError("Unexpected API path")

    def test_production_namespace(self):
        self.assertEqual(NAMESPACE, "retail-store")

    def test_all_checks_healthy(self):
        self.assertTrue(
            self.gate.evaluate()["healthy"]
        )

    def test_prometheus_not_ready(self):
        self.session.get.return_value.status_code = 503
        self.assertFalse(
            self.gate.evaluate()["healthy"]
        )

    def test_missing_production_targets(self):
        self.targets = self.targets[-1:]
        self.assertFalse(
            self.gate.targets(self.now)["healthy"]
        )

    def test_missing_kube_state_metrics(self):
        self.targets.pop()
        self.assertFalse(
            self.gate.targets(self.now)["healthy"]
        )

    def test_unhealthy_production_target(self):
        self.targets[0]["health"] = "down"
        self.assertFalse(
            self.gate.targets(self.now)["healthy"]
        )

    def test_target_scrape_error(self):
        self.targets[0]["lastError"] = "timeout"
        self.assertFalse(
            self.gate.targets(self.now)["healthy"]
        )

    def test_stale_scrape(self):
        self.targets[0]["lastScrape"] = (
            "2020-01-01T00:00:00Z"
        )
        self.assertFalse(
            self.gate.targets(self.now)["healthy"]
        )

    def test_missing_required_rule(self):
        self.rules.pop()
        self.assertFalse(
            self.gate.rules(self.now)["healthy"]
        )

    def test_unhealthy_rule(self):
        self.rules[0]["health"] = "err"
        self.assertFalse(
            self.gate.rules(self.now)["healthy"]
        )

    def test_stale_rule_evaluation(self):
        self.rules[0]["lastEvaluation"] = (
            "2020-01-01T00:00:00Z"
        )
        self.assertFalse(
            self.gate.rules(self.now)["healthy"]
        )

    def test_production_critical_alert(self):
        self.alerts.append({
            "state": "firing",
            "labels": {
                "namespace": "retail-store",
                "severity": "critical",
                "alertname": "ProductionFailure",
            },
        })
        self.assertFalse(
            self.gate.alerts()["healthy"]
        )

    def test_platform_critical_alert(self):
        self.alerts.append({
            "state": "firing",
            "labels": {
                "severity": "critical",
                "alertname": "KubernetesNodeNotReady",
            },
        })
        self.assertFalse(
            self.gate.alerts()["healthy"]
        )

    def test_pending_alert_not_firing(self):
        self.alerts.append({
            "state": "pending",
            "labels": {
                "namespace": NAMESPACE,
                "severity": "critical",
            },
        })
        self.assertTrue(
            self.gate.alerts()["healthy"]
        )

    def test_all_five_services_covered(self):
        result = self.gate.targets(self.now)
        self.assertTrue(result["healthy"])
        self.assertEqual(
            len(result["service_coverage"]), 5
        )

    def test_missing_catalog_blocks(self):
        self.targets = [
            t for t in self.targets
            if t["labels"].get("service") != "catalog"
        ]
        self.assertFalse(
            self.gate.targets(self.now)["healthy"]
        )

    def test_missing_replica_blocks(self):
        self.targets.pop(0)
        self.assertFalse(
            self.gate.targets(self.now)["healthy"]
        )

    def test_wrong_scrape_pool_blocks(self):
        self.targets[0]["scrapePool"] = "unexpected"
        self.assertFalse(
            self.gate.targets(self.now)["healthy"]
        )

    def test_duplicate_pod_not_counted_twice(self):
        self.targets[1]["labels"]["pod"] = (
            self.targets[0]["labels"]["pod"]
        )
        self.assertFalse(
            self.gate.targets(self.now)["healthy"]
        )

    def test_scaled_up_service_is_valid(self):
        import copy
        target = copy.deepcopy(self.targets[0])
        target["labels"]["pod"] = "additional-replica"
        self.targets.append(target)
        self.assertTrue(
            self.gate.targets(self.now)["healthy"]
        )

    def test_all_observed_rules_required(self):
        self.assertEqual(len(REQUIRED_RULES), 14)

    def test_missing_application_rule_blocks(self):
        self.rules = [
            rule for rule in self.rules
            if rule["name"] != "RetailStorePodNotReady"
        ]
        self.assertFalse(
            self.gate.rules(self.now)["healthy"]
        )

    def test_api_failure_blocks_execution(self):
        self.gate.api.side_effect = RuntimeError(
            "Prometheus unavailable"
        )
        self.assertFalse(
            self.gate.evaluate()["healthy"]
        )


if __name__ == "__main__":
    unittest.main()
