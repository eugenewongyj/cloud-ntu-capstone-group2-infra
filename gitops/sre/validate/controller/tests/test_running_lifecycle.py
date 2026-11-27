import unittest
from unittest.mock import Mock
from copy import deepcopy

from lifecycle import AssessmentLifecycle
from state import initial_state


class RunningLifecycleTests(unittest.TestCase):

    def setUp(self):

        self.store = Mock()
        self.executor = Mock()
        self.telemetry = Mock()

        self.state = initial_state()

        self.state.update({
            "state": "running",
            "assessment_run": "a" * 32,
            "profile": "1111",
            "repeat": True,
            "recovery_minutes": 5,
        })

        self.version = 100

        self.store.read.side_effect = (
            lambda: (
                deepcopy(self.state),
                str(self.version)
            )
        )

        self.store.write.side_effect = self.persist

        self.executor.status.return_value = {
            "state": "running",
            "assessment_run": "a" * 32,
        }

        self.lifecycle = AssessmentLifecycle(
            self.store,
            self.executor,
            self.telemetry,
        )

        self.lifecycle.phase_detector = Mock()
        self.lifecycle.recovery = Mock()

        self.lifecycle.phase_detector.detect.return_value = {
            "phase": "load",
            "execution_started_at": 1000,
            "recovery_started_at": 1300,
            "observation_deadline": 1600,
        }

        self.lifecycle.recovery.observe.side_effect = (
            lambda now: deepcopy(self.state)
        )

    def persist(self, state, version):

        self.assertEqual(version, str(self.version))

        self.state = deepcopy(state)
        self.version += 1

        return str(self.version)

    def test_persist_execution_clock(self):

        result = self.lifecycle.reconcile_running(1100)

        self.assertEqual(
            result["execution_started_at"], 1000
        )

        self.assertEqual(
            result["recovery_started_at"], 1300
        )

        self.assertEqual(result["state"], "running")

    def test_recovery_transition(self):

        result = self.lifecycle.reconcile_running(1300)

        self.assertEqual(result["state"], "recovering")

        self.lifecycle.recovery.observe.assert_called_once_with(
            now=1300
        )

    def test_persisted_clock_survives_restart(self):

        self.lifecycle.reconcile_running(1100)

        self.lifecycle.phase_detector.reset_mock()

        result = self.lifecycle.reconcile_running(1300)

        self.assertEqual(result["state"], "recovering")

        self.lifecycle.phase_detector.detect.assert_not_called()

    def test_missing_clock_does_not_invent_recovery(self):

        self.lifecycle.phase_detector.detect.return_value = {
            "phase": "unknown"
        }

        result = self.lifecycle.reconcile_running(1300)

        self.assertEqual(result["state"], "running")

        self.lifecycle.recovery.observe.assert_not_called()

    def test_failed_job_disables_repeat(self):

        self.executor.status.return_value["state"] = "failed"

        result = self.lifecycle.reconcile_running(1300)

        self.assertEqual(result["state"], "evaluating")
        self.assertFalse(result["repeat"])

    def test_missing_job_disables_repeat(self):

        self.executor.status.return_value = {
            "state": "idle"
        }

        result = self.lifecycle.reconcile_running(1300)

        self.assertEqual(result["job_outcome"], "missing")
        self.assertFalse(result["repeat"])

    def test_wrong_job_identity_blocks_assessment(self):

        self.executor.status.return_value[
            "assessment_run"
        ] = "b" * 32

        result = self.lifecycle.reconcile_running(1300)

        self.assertEqual(result["state"], "blocked")
        self.assertFalse(result["repeat"])

    def test_stop_requested_prevents_observation(self):

        self.state["stop_requested"] = True

        self.lifecycle.reconcile_running(1300)

        self.executor.status.assert_not_called()

        self.lifecycle.recovery.observe.assert_not_called()

    def test_early_job_completion_is_unconfirmed(self):

        self.lifecycle.reconcile_running(1100)

        self.executor.status.return_value[
            "state"
        ] = "completed"

        result = self.lifecycle.reconcile_running(1400)

        self.assertEqual(
            result["recovery_outcome"], "unconfirmed"
        )

        self.assertFalse(result["repeat"])

    def test_completed_job_without_clock(self):

        self.lifecycle.phase_detector.detect.return_value = {
            "phase": "unknown"
        }

        self.executor.status.return_value[
            "state"
        ] = "completed"

        result = self.lifecycle.reconcile_running(1600)

        self.assertEqual(result["state"], "evaluating")
        self.assertFalse(result["repeat"])


if __name__ == "__main__":
    unittest.main()
