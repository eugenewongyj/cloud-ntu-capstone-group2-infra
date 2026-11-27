import unittest
from unittest.mock import Mock

from state import initial_state
from recovery import RecoveryObservation
from recovery_coordinator import RecoveryCoordinator


class RecoveryCoordinatorTests(unittest.TestCase):

    def setUp(self):
        self.store = Mock()
        self.telemetry = Mock()

        self.state = initial_state()

        self.state.update({
            "state": "recovering",
            "assessment_run": "a" * 32,
            "recovery_started_at": 1000,
            "recovery_minutes": 5,
            "repeat": True,
        })

        self.store.read.side_effect = (
            lambda: (self.state.copy(), "100")
        )

        self.store.write.side_effect = self.persist

        self.telemetry.recovery_observation.side_effect = (
            lambda run_id, now: RecoveryObservation(
                timestamp=now,
                p95_ms=100,
                failure_rate=0,
                content_failure_rate=0,
                request_count=10,
                fresh=True,
            )
        )

        self.coordinator = RecoveryCoordinator(
            self.store,
            self.telemetry,
        )

    def persist(self, state, version):
        self.state = state.copy()
        return "101"

    def test_persist_observation(self):
        result = self.coordinator.observe(1000)

        self.assertEqual(result["healthy_since"], 1000)
        self.assertTrue(result["telemetry_valid"])
        self.assertEqual(
            result["latest_metrics"]["p95_ms"], 100
        )

    def test_confirm_sustained_recovery(self):
        for t in range(1000, 1061, 10):
            result = self.coordinator.observe(t)

        self.assertEqual(result["recovery_seconds"], 0)
        self.assertTrue(result["current_health_confirmed"])

    def test_recovery_does_not_end_early(self):
        for t in range(1000, 1061, 10):
            result = self.coordinator.observe(t)

        self.assertEqual(result["state"], "recovering")

    def test_successful_observation_deadline(self):
        for t in range(1000, 1301, 10):
            result = self.coordinator.observe(t)

        self.assertEqual(result["state"], "evaluating")
        self.assertEqual(
            result["recovery_outcome"], "recovered"
        )

    def test_missing_telemetry_disables_repeat(self):
        self.telemetry.recovery_observation.side_effect = (
            lambda run_id, now: RecoveryObservation(
                timestamp=now,
                p95_ms=None,
                failure_rate=None,
                content_failure_rate=None,
                request_count=0,
                fresh=False,
            )
        )

        result = self.coordinator.observe(1300)

        self.assertEqual(
            result["recovery_outcome"], "unconfirmed"
        )

        self.assertFalse(result["repeat"])

    def test_restart_preserves_recovery(self):
        for t in range(1000, 1051, 10):
            self.coordinator.observe(t)

        restarted = RecoveryCoordinator(
            self.store,
            self.telemetry,
        )

        result = restarted.observe(1060)

        self.assertTrue(result["current_health_confirmed"])
        self.assertEqual(result["recovery_seconds"], 0)

    def test_duplicate_observation_ignored(self):
        self.coordinator.observe(1000)
        self.telemetry.reset_mock()

        self.coordinator.observe(1000)

        self.telemetry.recovery_observation.assert_not_called()

    def test_stop_prevents_observation(self):
        self.state["stop_requested"] = True

        self.coordinator.observe(1000)

        self.telemetry.recovery_observation.assert_not_called()

    def test_late_health_failure_blocks_repeat(self):
        for t in range(1000, 1300, 10):
            self.coordinator.observe(t)

        self.telemetry.recovery_observation.side_effect = None

        self.telemetry.recovery_observation.return_value = (
            RecoveryObservation(
                timestamp=1300,
                p95_ms=900,
                failure_rate=0.05,
                content_failure_rate=0,
                request_count=10,
                fresh=True,
            )
        )

        result = self.coordinator.observe(1300)

        self.assertFalse(result["current_health_confirmed"])
        self.assertFalse(result["repeat"])

    def test_non_recovery_state_ignored(self):
        self.state["state"] = "idle"

        self.coordinator.observe(1000)

        self.telemetry.recovery_observation.assert_not_called()


if __name__ == "__main__":
    unittest.main()
