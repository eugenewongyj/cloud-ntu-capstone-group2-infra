import unittest

from unittest.mock import Mock

from engine import AssessmentEngine
from state import initial_state


class EngineTests(unittest.TestCase):

    def setUp(self):

        self.lifecycle = Mock()
        self.lifecycle.execution_gate = Mock()

        self.store = Mock()

        self.state = initial_state()

        self.store.read.return_value = (
            self.state, "100"
        )

        self.engine = AssessmentEngine(
            self.lifecycle,
            self.store,
        )

    def test_gate_is_mandatory(self):

        self.lifecycle.execution_gate = None

        with self.assertRaises(ValueError):

            AssessmentEngine(
                self.lifecycle,
                self.store,
            )

    def test_invalid_interval(self):

        with self.assertRaises(ValueError):

            AssessmentEngine(
                self.lifecycle,
                self.store,
                interval=0,
            )

    def test_start_normal_sale(self):

        self.lifecycle.start.return_value = {
            "state": "starting",
        }

        self.engine.start_assessment("normal")

        self.lifecycle.start.assert_called_once_with(
            "normal", 1, 10, False, 3
        )

    def test_start_flash_sale(self):

        self.lifecycle.start.return_value = {
            "state": "starting",
        }

        self.engine.start_assessment(
            "1111", 1, 10, True, 3
        )

        self.lifecycle.start.assert_called_once_with(
            "1111", 1, 10, True, 3
        )

    def test_stop_assessment(self):

        self.lifecycle.request_stop.return_value = {
            "state": "stopping",
        }

        self.engine.stop_assessment("a" * 32)

        self.lifecycle.request_stop.assert_called_once_with(
            "a" * 32
        )

    def test_idle_does_not_create_job(self):

        result = self.engine.reconcile_once()

        self.assertEqual(result["state"], "idle")

        self.lifecycle.reconcile_start.assert_not_called()

    def test_starting_dispatch(self):

        self.state["state"] = "starting"

        self.engine.reconcile_once()

        self.lifecycle.reconcile_start.assert_called_once()

    def test_running_dispatch(self):

        self.state["state"] = "running"

        self.engine.reconcile_once()

        self.lifecycle.reconcile_running.assert_called_once()

    def test_recovering_dispatch(self):

        self.state["state"] = "recovering"

        self.engine.reconcile_once()

        self.lifecycle.reconcile_running.assert_called_once()

    def test_stopping_dispatch(self):

        self.state["state"] = "stopping"

        self.engine.reconcile_once()

        self.lifecycle.reconcile_stop.assert_called_once()

    def test_evaluating_dispatch(self):

        self.state["state"] = "evaluating"

        self.engine.reconcile_once()

        self.lifecycle.reconcile_finalization.assert_called_once()

    def test_stopped_dispatch(self):

        self.state["state"] = "stopped"

        self.engine.reconcile_once()

        self.lifecycle.reconcile_finalization.assert_called_once()

    def test_finalizing_dispatch(self):

        self.state["state"] = "finalizing"

        self.engine.reconcile_once()

        self.lifecycle.reconcile_finalization.assert_called_once()

    def test_blocked_does_not_create_job(self):

        self.state["state"] = "blocked"

        self.engine.reconcile_once()

        self.lifecycle.reconcile_start.assert_not_called()

    def test_unknown_state_rejected(self):

        self.state["state"] = "invalid"

        with self.assertRaises(ValueError):

            self.engine.reconcile_once()

    def test_status_is_independent_copy(self):

        result = self.engine.status()

        result["state"] = "modified"

        self.assertEqual(self.state["state"], "idle")

    def test_history_preserved(self):

        self.state["history"] = [
            {"assessment_run": "a" * 32}
        ]

        self.assertEqual(
            self.engine.history(),
            self.state["history"],
        )

    def test_worker_not_started(self):

        result = self.engine.health()

        self.assertFalse(result["healthy"])
        self.assertFalse(result["worker_running"])


if __name__ == "__main__":
    unittest.main()
